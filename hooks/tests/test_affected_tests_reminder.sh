#!/usr/bin/env bash
# СУДИТ: hooks/affected-tests-reminder.sh
# test_affected_tests_reminder.sh — напоминание о наборе затронутых тестов на `git commit` (D1296): звучит, пока набор для
#   нынешних изменений не собран, и молчит после сборки, на одних документах, в ClaudSoul, на не-коммите и без скрипта;
#   прибор, ответивший не 0/1, назван, а не прочитан «собран». Скрипт настоящий (копия `scripts/affected-tests.sh` в
#   песочнице корня ClaudSoul), поэтому нога T1 краснеет и на выпотрошенном скрипте.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/affected-tests-reminder.sh"
REPO_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

assert_contains() { if grep -qF "$2" <<< "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет '$2' в '${1:0:120}'"; fi; }
assert_empty()    { if [ -z "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалось пусто, '${1:0:120}'"; fi; }

CS="$TMP/cs"; mkdir -p "$CS/scripts"; cp "$REPO_ROOT/scripts/affected-tests.sh" "$CS/scripts/"
P="$TMP/proj"; mkdir -p "$P/web/lib" "$P/web/tests/unit"
git -C "$P" init -q; git -C "$P" config user.email t@t; git -C "$P" config user.name t
printf "export const L = 'Воронка';\n" > "$P/web/lib/labels.ts"
printf "import fs from 'fs'; fs.readdirSync('web');\n" > "$P/web/tests/unit/scan.test.ts"
printf '# notes\n' > "$P/NOTES.md"
git -C "$P" add -A; git -C "$P" commit -qm init

run_hook() {  # $1 — каталог проекта, $2 — команда, $3 — корень ClaudSoul
    printf '{"session_id":"t","tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "${2:-git commit -m x}" \
        | env STATE_DIR="$TMP/st" CLAUDSOUL_ROOT="${3:-$CS}" PATHS_LIB=/dev/null bash "$HOOK" 2>/dev/null
}

# T1: код изменён, набор не собирался → напоминание с командой
printf "export const L = 'Канбан';\n" > "$P/web/lib/labels.ts"
assert_contains "$(run_hook "$P")" "affected-tests.sh" "T1: набор не собран → команда названа"

# T2: набор собран для этих изменений → тихо
( cd "$P" && STATE_DIR="$TMP/st" bash "$CS/scripts/affected-tests.sh" >/dev/null 2>&1 )
assert_empty "$(run_hook "$P")" "T2: набор собран → тихо"

# T3: новая правка после сборки → снова напоминание
printf "export const L = 'Доска';\n" > "$P/web/lib/labels.ts"
assert_contains "$(run_hook "$P")" "не собирался" "T3: правка после сборки → напоминание"

# T4: изменены одни документы → тихо
git -C "$P" checkout -q -- web/lib/labels.ts; printf 'more\n' >> "$P/NOTES.md"
assert_empty "$(run_hook "$P")" "T4: только .md → тихо"
git -C "$P" checkout -q -- NOTES.md

# T5: не-коммит → тихо
printf "export const L = 'X';\n" > "$P/web/lib/labels.ts"
assert_empty "$(run_hook "$P" "ls -la")" "T5: не-коммит → тихо"

# T6: проект — сам ClaudSoul (свой выбор у run_all.sh --changed) → тихо
mkdir -p "$P/hooks/tests"; printf '#!/usr/bin/env bash\n' > "$P/hooks/tests/run_all.sh"
assert_empty "$(run_hook "$P")" "T6: дерево с hooks/tests/run_all.sh → тихо"
rm -rf "$P/hooks"

# T7: скрипта нет (другая установка) → тихо
assert_empty "$(run_hook "$P" "git commit -m x" "$TMP/nocs")" "T7: скрипта нет → тихо"

# T8: прибор ответил не 0/1 → назван «не ответил», а не прочитан «собран»
B="$TMP/broken"; mkdir -p "$B/scripts"; printf '#!/usr/bin/env bash\nexit 5\n' > "$B/scripts/affected-tests.sh"
assert_contains "$(run_hook "$P" "git commit -m x" "$B")" "не ответил (код 5)" "T8: код 5 → прибор не ответил"

# T9: самопроверка скрипта зелёна и прошла все свои ноги, их не меньше 21 (заглушка молчит — нога краснеет)
ST=$(bash "$REPO_ROOT/scripts/affected-tests.sh" --self-test 2>&1); STRC=$?
N=$(sed -n 's/^самопроверка: \([0-9][0-9]*\) из \1 .*/\1/p' <<< "$ST")
[ "$STRC" = 0 ] && [ -n "$N" ] && [ "$N" -ge 21 ] && ST_OK=yes || ST_OK="код $STRC, вывод: ${ST:0:120}"
assert_contains "$ST_OK" "yes" "T9: самопроверка скрипта"

# T10: изменён один документ с кириллицей в имени → тихо (git отдаёт такой путь в кавычках, и `.md` пряталось; M1)
git -C "$P" checkout -q -- web/lib/labels.ts; printf '# z\n' > "$P/заметки.md"
assert_empty "$(run_hook "$P")" "T10: только .md с кириллицей в имени → тихо"
rm -f "$P/заметки.md"

# T11: правка только в индексе (рабочее дерево вернули к HEAD) — коммит её унесёт → напоминание (L1)
printf "export const L = 'Индекс';\n" > "$P/web/lib/labels.ts"; git -C "$P" add web/lib/labels.ts
git -C "$P" show HEAD:web/lib/labels.ts > "$P/web/lib/labels.ts"
assert_contains "$(run_hook "$P")" "не собирался" "T11: правка только в индексе → напоминание"

echo "test_affected_tests_reminder: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
