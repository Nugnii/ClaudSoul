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
# $1=метка $2=вывод — хук обязан молчать. Отдельное имя, потому что мета-страж
# test_guards_provable.sh ищет утверждения о тишине лексически.
assert_empty() { [ -z "$2" ] && ok || bad "$1" "ожидалась тишина, получено: $2"; }

run() { # $1=команда $2=tool
    jq -cn --arg c "$1" --arg t "${2:-Bash}" '{tool_name:$t, tool_input:{command:$c}}' \
        | bash "$HOOK" 2>&1
}
msg() { printf '%s' "$1" | jq -r '.systemMessage // ""' 2>/dev/null; }

# --- T1: git push → напоминание, и оно называет инструмент ---
OUT=$(msg "$(run 'git push origin main --follow-tags')")
grep -q 'ci-status.sh' <<< "$OUT" && ok || bad "T1a" "инструмент не назван: $OUT"
grep -q 'СВОЕГО коммита' <<< "$OUT" && ok || bad "T1b" "суть напоминания потеряна"

# --- T2: обычные команды — тишина ---
assert_empty "T2a" "$(run 'git commit -m x')"
assert_empty "T2b" "$(run 'ls -la')"
assert_empty "T2c" "$(run 'git pull')"

# --- T3: «git push» как ТЕКСТ — тишина (command-scope) ---
assert_empty "T3a" "$(run 'echo "git push origin main"')"
HEREDOC_OUT=$(run 'cat <<EOF
git push origin main
EOF')
assert_empty "T3b" "$HEREDOC_OUT"

# --- T4: не Bash — тишина ---
assert_empty "T4" "$(run 'git push' 'Edit')"

# --- T5: push в составной команде (cd && git push) ловится ---
OUT=$(msg "$(run 'cd /x && git push origin main 2>&1 | tail -3')")
grep -q 'ci-status.sh' <<< "$OUT" && ok || bad "T5" "push внутри составной команды пропущен"

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

# --- T7: текст идёт обоими каналами ---
# Замер по истории расшифровок (2026-08-21): 12 срабатываний ушли в один
# `systemMessage`, и ход не отреагировал ни разу — записи `hook_system_message` в
# поток сообщений не попадают. Без этой проверки регресс канала выглядел бы как
# «хук молчит», а не как «хука никто не слышит».
OUT=$(run 'git push origin main')
AC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
EV=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)
grep -q 'ci-status.sh' <<< "$AC" && ok || bad "T7a" "additionalContext пуст — до хода текст не дойдёт"
[ "$EV" = "PostToolUse" ]        && ok || bad "T7b" "hookEventName '$EV', ожидалось PostToolUse"
[ -n "$(msg "$OUT")" ]           && ok || bad "T7c" "systemMessage пропал — владелец больше не видит"

# --- T8: где инструмента нет — совет назвал бы несуществующий файл ---
# Область действия по cwd из payload (аудит переносимости 2026-08-08).
if command -v git >/dev/null 2>&1; then
    TMP8=$(mktemp -d); trap 'rm -rf "$TMP8"' EXIT
    git -C "$TMP8" init -q 2>/dev/null
    CWD_OUT=$(jq -cn --arg c 'git push' --arg d "$TMP8" \
        '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' | bash "$HOOK" 2>&1)
    assert_empty "T8" "$CWD_OUT"
else
    ok
fi

echo ""
echo "ci check reminder tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
