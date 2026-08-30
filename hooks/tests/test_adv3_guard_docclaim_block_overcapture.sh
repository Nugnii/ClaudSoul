#!/usr/bin/env bash
# АТАКА: блок «Файлы» глотает следующий раздел, если у его маркера нет точки.
#
# Граница блока — `\n\*\*[^*\n]+\.\*\*` либо заголовок. Точка перед `**` обязательна,
# а в самих модульных доках есть маркер без неё: `**Связи изменённого берутся из ДВУХ
# источников**` (.claude-docs/modules/doc-impact-check.md). Такой маркер блок не
# останавливает, и текст следующего раздела разбирается как состав файлов.
#
# Дальше срабатывает то, от чего страж лечился: событие, названное в ОТРИЦАНИИ
# («на Stop не срабатывает»), становится утверждением о регистрации. Внутри блока это
# закрыли правилом «скобка принадлежит ближайшему хуку», но за границей блока лечение
# не действует — граница и есть дефект.
#
# Вход: верный док. Блок «Файлы» называет настоящее событие хука; следующий раздел
# помечен маркером без точки и говорит, что на ЧУЖОМ событии хук не срабатывает.
# Ожидание: 0 расхождений — обе фразы верны.
# Факт: страж требует править верный документ.
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

**Назначение.** Что-то делает.

**Файлы.** \`hooks/$HOOK\` ($REAL), инжект additionalContext.

**Названный предел** — правка видна, а завершение сессии нет:
\`hooks/$HOOK\` ($WRONG его событием не является) на выходе ничего не потребует.
DOC

OUT=$(bash "$D/hooks/tests/test_module_doc_registration_claims.sh" 2>&1)
RC=$?
echo "  док верен: блок «Файлы» называет $REAL (настоящее событие $HOOK),"
echo "  раздел за маркером БЕЗ точки говорит, что $WRONG его событием не является"
printf '%s\n' "$OUT" | sed 's/^/  | /'
echo "  код возврата: $RC"

if [ "$RC" -eq 0 ]; then
    echo "PASS: верный документ пропущен"
    exit 0
fi
echo "FAIL: документ верен в обеих фразах, а страж требует его править."
echo "      Маркер следующего раздела без завершающей точки границей блока не считается"
echo "      (такие маркеры есть в настоящих доках), блок «Файлы» глотает соседний раздел,"
echo "      и событие из ОТРИЦАНИЯ становится утверждением о регистрации."
exit 1
