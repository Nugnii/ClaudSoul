#!/usr/bin/env bash
# test_ci_check_reminder.sh — после `git push` напоминание проверить прогон СВОЕГО коммита (D60).
#
# Повод. Дважды объявлено «CI зелёный» при красном прогоне: опрашивался «самый свежий»
# прогон, а сразу после push самым свежим числится ПРЕДЫДУЩИЙ. Инструмент `ci-status.sh`
# был заведён, но оставался уровнем 1 — его надо было не забыть вызвать. Хук делает
# напоминание механическим.
#
# Детект — по исполняемой части команды (command-scope-lib): «git push» в кавычках или
# heredoc — аргумент, а не команда. Ровно тот класс, что чинился для trust-guard в v1.14.1.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/ci-check-reminder.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

run() { # $1=команда $2=tool
    jq -cn --arg c "$1" --arg t "${2:-Bash}" '{tool_name:$t, tool_input:{command:$c}}' \
        | bash "$HOOK" 2>&1
}
msg() { printf '%s' "$1" | jq -r '.systemMessage // ""' 2>/dev/null; }

# --- T1: git push → напоминание, и оно называет инструмент ---
OUT=$(msg "$(run 'git push origin main --follow-tags')")
printf '%s' "$OUT" | grep -q 'ci-status.sh' && ok || bad "T1a" "инструмент не назван: $OUT"
printf '%s' "$OUT" | grep -q 'СВОЕГО коммита' && ok || bad "T1b" "суть напоминания потеряна"

# --- T2: обычные команды — тишина ---
[ -z "$(run 'git commit -m x')" ] && ok || bad "T2a" "сработал на git commit"
[ -z "$(run 'ls -la')" ]         && ok || bad "T2b" "сработал на ls"
[ -z "$(run 'git pull')" ]       && ok || bad "T2c" "сработал на git pull"

# --- T3: «git push» как ТЕКСТ — тишина (command-scope) ---
[ -z "$(run 'echo "git push origin main"')" ] && ok || bad "T3a" "сработал на git push в кавычках"
[ -z "$(run 'cat <<EOF
git push origin main
EOF')" ] && ok || bad "T3b" "сработал на git push в heredoc"

# --- T4: не Bash — тишина ---
[ -z "$(run 'git push' 'Edit')" ] && ok || bad "T4" "сработал на не-Bash инструменте"

# --- T5: push в составной команде (cd && git push) ловится ---
OUT=$(msg "$(run 'cd /x && git push origin main 2>&1 | tail -3')")
printf '%s' "$OUT" | grep -q 'ci-status.sh' && ok || bad "T5" "push внутри составной команды пропущен"

# --- T6: хук зарегистрирован в install.sh на PostToolUse ---
# PostToolUse выбран сознательно: на успешной команде он срабатывает, а после
# УПАВШЕГО пуша напоминать не о чем (D41: на упавшей команде событие не приходит).
if command -v python3 >/dev/null 2>&1; then
    EV=$(python3 - "$HOOKS_DIR/../install.sh" <<'PY'
import json, re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", t, re.S)
d = json.loads(m.group(1)) if m else {}
print(",".join(sorted({ev for ev, ms in d.get("hooks", {}).items()
                       for mm in ms for h in mm.get("hooks", [])
                       if "ci-check-reminder" in h.get("command", "")})))
PY
)
    [ "$EV" = "PostToolUse" ] && ok || bad "T6" "регистрация: '$EV', ожидалось PostToolUse"
else
    ok
fi

echo ""
echo "ci check reminder tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
