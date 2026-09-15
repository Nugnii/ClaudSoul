#!/usr/bin/env bash
# АТАКА: ложное утверждение о регистрации, вынесенное в ЗАГОЛОВОК, не проверяется.
#
# Страж берёт утверждения только из блоков `**Файлы.**`. Его КОНТРПРИМЕР исключает
# «упоминание события в прозе БЕЗ имени хука рядом» — здесь имя хука есть, событие
# есть, оба в одной строке заголовка, и утверждение механически выводимо. Не
# проверяется оно не потому, что невыразимо, а потому, что предмет задан тем, ГДЕ
# его нашли в первый раз, — ровно тот класс, который шапка стража называет поводом.
#
# Вход: модульный док, где заголовок утверждает `hooks/<хук>.sh` (<чужое событие>),
# а блок «Файлы» перечисляет только тестовый файл.
# Ожидание: расхождение названо — хук на этом событии не зарегистрирован.
# Факт: «утверждений о регистрации проверено: 0, расходятся: 0», код возврата 0.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/tests/test_module_doc_registration_claims.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PICK=$(python3 - "$REPO/install.sh" <<'PY'
import json, pathlib, re, sys
cfg = json.loads(re.search(r"HOOKS_CONFIG='(\{.*?\n\})'",
                           pathlib.Path(sys.argv[1]).read_text(), re.S).group(1))
reg = {}
for ev, groups in cfg["hooks"].items():
    for g in groups:
        for h in g.get("hooks", []):
            m = re.search(r"hooks/([A-Za-z0-9._-]+\.sh)", h.get("command", ""))
            if m:
                reg.setdefault(m.group(1), set()).add(ev)
EVENTS = {"PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop",
          "SessionStart", "PreCompact", "SessionEnd"}
for name in sorted(reg):
    wrong = sorted(EVENTS - reg[name])
    if wrong and not name.endswith("-lib.sh"):
        print(f"{name}|{sorted(reg[name])[0]}|{wrong[0]}")
        break
PY
)
[ -n "$PICK" ] || { echo "SKIP: не нашёл хука с незанятым событием"; exit 0; }
HOOK="${PICK%%|*}"; REST="${PICK#*|}"; REAL="${REST%%|*}"; WRONG="${REST#*|}"
STEM="${HOOK%.sh}"

TMP=$(mktemp -d)
D="$TMP/repo"
mkdir -p "$D/hooks/tests" "$D/.claude-docs/modules"
cp "$REPO/install.sh" "$D/"
cp "$GUARD" "$D/hooks/tests/"

cat > "$D/.claude-docs/modules/$STEM.md" <<DOC
# Модуль $STEM

## Регистрация: \`hooks/$HOOK\` ($WRONG)

**Назначение.** Что-то делает.

**Файлы.** \`hooks/tests/test_$STEM.sh\` (проверки модуля).
DOC

OUT=$(bash "$D/hooks/tests/test_module_doc_registration_claims.sh" 2>&1)
RC=$?
echo "  док утверждает: $HOOK ($WRONG); в install.sh хук стоит на $REAL"
printf '%s\n' "$OUT" | sed 's/^/  | /'
echo "  код возврата: $RC"

if [ "$RC" -ne 0 ]; then
    echo "PASS: ложное утверждение из заголовка названо"
    exit 0
fi
echo "FAIL: док называет событие $WRONG, на котором $HOOK не зарегистрирован, и страж"
echo "      молчит: утверждения берутся только из блоков «**Файлы.**», а заголовок с"
echo "      именем хука и событием в одной строке проверяем ровно так же и не проверен."
exit 1
