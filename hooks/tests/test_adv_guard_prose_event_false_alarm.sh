#!/usr/bin/env bash
# test_adv_guard_prose_event_false_alarm.sh — страж ругается на верный документ: событие,
# названное в ОТРИЦАНИИ внутри блока «Файлы», приписывается первому хуку блока.
#
# Вход: правдивый модульный док. Блок «Файлы» называет два хука: у второго событие в
#   скобках (`hooks/partial-read-guard.sh` (PostToolUse) — так и есть), у первого скобки
#   нет, а в конце блока стоит фраза «Ни один из них на PreToolUse не висит» — верная.
# Ожидание: расхождений нет, код 0. В документе нет утверждения, что session-collector
#   зарегистрирован на PreToolUse; сказано ровно обратное.
# Факт: ветка «Регистрация:» (`rest = events_in(...)`) собирает события ИЗ ВСЕГО блока после
#   вырезания скобок — без оглядки на то, есть ли в блоке слово «Регистрация» и в каком
#   смысле событие названо, — и приписывает их первому хуку без своей скобки. Страж
#   печатает «`session-collector.sh` заявлен на PreToolUse; в install.sh — Stop» и выходит
#   с 1. Правка документа под это требование сделает документ ЛОЖНЫМ.
#
# Достижимость: форма «первый хук без скобки + второй со скобкой + фраза про чужое событие»
#   уже живёт в дереве. Ближайший образец — bridge-shared-language.md: блок «Файлы»
#   называет `hooks/shared-language-lib.sh` и рядом «Stop-алерт … в `session-collector.sh`»;
#   от срабатывания его спасает только исключение `*-lib.sh`. Убери исключение или поставь
#   на его место обычный хук — и получишь ровно этот вход.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD_SRC="$REPO/hooks/tests/test_module_doc_registration_claims.sh"
[ -f "$GUARD_SRC" ] || { echo "FAIL: нет $GUARD_SRC"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

premise=$(python3 - "$REPO/install.sh" <<'PY'
import json, re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", t, re.S)
if not m: print("SKIP"); raise SystemExit
cfg = json.loads(m.group(1)); ev = {}
for e, gs in cfg.get("hooks", {}).items():
    for g in gs:
        for h in g.get("hooks", []):
            for n in ("session-collector.sh", "partial-read-guard.sh"):
                if n in h.get("command", ""): ev.setdefault(n, set()).add(e)
ok = (ev.get("session-collector.sh") == {"Stop"}
      and ev.get("partial-read-guard.sh") == {"PostToolUse"})
print("OK" if ok else "SKIP")
PY
)
[ "$premise" = "OK" ] || { echo "SKIP: посылка входа изменилась (регистрации session-collector / partial-read-guard)"; exit 0; }

T="$(mktemp -d)"; P="$T/repo"
mkdir -p "$P/hooks/tests" "$P/.claude-docs/modules"
cp "$REPO/install.sh" "$P/install.sh"
cp "$GUARD_SRC" "$P/hooks/tests/guard.sh"

cat > "$P/.claude-docs/modules/pravdivyi.md" <<'MD'
# Модуль: сбор итога и счёт строк

**Файлы.** `hooks/session-collector.sh` — сборщик итога сессии; `hooks/partial-read-guard.sh` (PostToolUse) — счётчик прочитанных строк. Ни один из них на PreToolUse не висит.

**Зависимости.** jq.
MD

echo "документ (всё сказанное в нём — правда):"
sed -n '3p' "$P/.claude-docs/modules/pravdivyi.md" | sed 's/^/  /'
out="$(bash "$P/hooks/tests/guard.sh" 2>&1)"; rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
echo "код возврата стража: $rc"

fail=0
if [ "$rc" -ne 0 ]; then
    echo "ПРОВАЛ: страж требует правки верного документа — событие из отрицания приписано первому хуку блока"
    fail=1
fi
case "$out" in
    *"session-collector.sh"*"PreToolUse"*)
        echo "ПРОВАЛ: страж приписал документу утверждение, которого в нём нет"
        fail=1 ;;
esac
[ "$fail" -eq 0 ] && echo "OK: событие из прозы блока не выдаётся за утверждение о регистрации"
exit "$fail"
