#!/usr/bin/env bash
# test_module_doc_check.sh — module-doc-check.sh: новый модуль без модульного дока.
#
# Закрепляется (обе стороны, guards-provable):
#   - НОВЫЙ hooks/*.sh в staged без .claude-docs/modules/ → инжект с именем файла;
#   - модульный док в том же staged → тишина;
#   - правка СУЩЕСТВУЮЩЕГО хука (статус M) → тишина (модуль ≠ каждая правка);
#   - новый файл в hooks/tests/ → тишина (тест — не модуль);
#   - не git-commit команда → тишина;
#   - throttle: то же множество модулей второй раз за сессию → тишина.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/module-doc-check.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_silent()   { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина: $1"; }
assert_contains() { if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в: $1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

# Изолированный репозиторий-фикстура
R="$TMP/repo"
mkdir -p "$R/hooks/tests" "$R/.claude-docs/modules"
git -C "$R" init -q -b main
git -C "$R" -c user.email=test@test.local -c user.name=t commit -q --allow-empty -m init

run_hook() { # $1 sid, $2 command; cwd = фикстурный репозиторий
    jq -cn --arg sid "$1" --arg c "$2" \
        '{tool_name:"Bash", tool_input:{command:$c}, session_id:$sid}' \
        | (cd "$R" && bash "$HOOK" 2>/dev/null)
}

# --- T1: новый модуль без дока → инжект -------------------------------------------
echo "#!/usr/bin/env bash" > "$R/hooks/new-module.sh"
git -C "$R" add hooks/new-module.sh
OUT=$(run_hook s1 "git commit -m x")
assert_contains "$OUT" "hooks/new-module.sh" "T1a имя модуля"
assert_contains "$OUT" "Модульный док" "T1b текст напоминания"

# --- T2: throttle — тот же набор второй раз → тишина ------------------------------
OUT=$(run_hook s1 "git commit -m x")
assert_silent "$OUT" "T2 throttle"

# --- T3: док в том же staged → тишина ---------------------------------------------
echo "# Модуль" > "$R/.claude-docs/modules/new-module.md"
git -C "$R" add .claude-docs/modules/new-module.md
OUT=$(run_hook s3 "git commit -m x")
assert_silent "$OUT" "T3 док приложен"
git -C "$R" -c user.email=test@test.local -c user.name=t commit -qm "module+doc"

# --- T4: правка существующего хука → тишина ---------------------------------------
echo "# правка" >> "$R/hooks/new-module.sh"
git -C "$R" add hooks/new-module.sh
OUT=$(run_hook s4 "git commit -m x")
assert_silent "$OUT" "T4 правка не модуль"
git -C "$R" -c user.email=test@test.local -c user.name=t commit -qm "edit"

# --- T5: новый файл в tests/ → тишина ---------------------------------------------
echo "#!/usr/bin/env bash" > "$R/hooks/tests/test_x.sh"
git -C "$R" add hooks/tests/test_x.sh
OUT=$(run_hook s5 "git commit -m x")
assert_silent "$OUT" "T5 тест не модуль"

# --- T7: механизм вне hooks/ → инжект (модуль задан правилом, не местом) ----------
mkdir -p "$R/scripts"
echo "#!/usr/bin/env bash" > "$R/scripts/new-measure.sh"
git -C "$R" add scripts/new-measure.sh
OUT=$(run_hook s7 "git commit -m x")
assert_contains "$OUT" "scripts/new-measure.sh" "T7 механизм вне hooks/"
git -C "$R" rm -q --cached scripts/new-measure.sh; rm -f "$R/scripts/new-measure.sh"

# --- T8: библиотека → тишина (составная часть, не модуль) -------------------------
echo "#!/usr/bin/env bash" > "$R/hooks/new-thing-lib.sh"
git -C "$R" add hooks/new-thing-lib.sh
OUT=$(run_hook s8 "git commit -m x")
assert_silent "$OUT" "T8 библиотека не модуль"
git -C "$R" rm -q --cached hooks/new-thing-lib.sh; rm -f "$R/hooks/new-thing-lib.sh"

# --- T6: не commit-команда → тишина -----------------------------------------------
OUT=$(run_hook s6 "git status")
assert_silent "$OUT" "T6 не commit"

echo ""
echo "test_module_doc_check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
