#!/usr/bin/env bash
# test_changelog_reminder.sh — тест напоминания о CHANGELOG при изменениях кода.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/changelog-reminder.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

assert_contains() { if grep -qF "$2" <<< "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет '$2'"; fi; }
assert_empty()    { if [ -z "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалось пусто, '${1:0:60}'"; fi; }

REPO="$TMP/repo"
mkdir -p "$REPO/hooks" "$REPO/docs"
cd "$REPO"
git init -q; git config user.email t@t; git config user.name t
echo "# changelog" > CHANGELOG.md
echo "x" > hooks/feature.sh
echo "d" > docs/note.md
git add CHANGELOG.md; git commit -qm init

run_hook() {  # $1 = state subdir, $2 = команда (по умолчанию голый коммит)
    cd "$REPO"
    printf '{"session_id":"test-cl","tool_name":"Bash","tool_input":{"command":"%s"}}' "${2:-git commit -m x}" | env \
        STATE_DIR="$TMP/$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null
}

# T1: код staged, CHANGELOG нет → напоминание
git reset -q; git add hooks/feature.sh
assert_contains "$(run_hook s1)" "CHANGELOG" "T1: код без CHANGELOG → напоминание"

# T2: код + CHANGELOG staged → тихо
git reset -q; echo "change" >> CHANGELOG.md; git add hooks/feature.sh CHANGELOG.md
assert_empty "$(run_hook s2)" "T2: CHANGELOG в staged → тихо"
# Откат именно из HEAD: `git checkout -- <файл>` берёт содержимое из ИНДЕКСА, куда
# строку только что добавили, и правка осталась бы в рабочем дереве до конца прогона.
git checkout -q HEAD -- CHANGELOG.md 2>/dev/null || true

# T3: только docs staged (нет кода) → тихо
git reset -q; git add docs/note.md
assert_empty "$(run_hook s3)" "T3: только docs → тихо"

# T4: throttle — тот же diff кода дважды → второй раз тихо
git reset -q; git add hooks/feature.sh
assert_contains "$(run_hook s4)" "CHANGELOG" "T4a: первый раз напоминает"
assert_empty   "$(run_hook s4)" "T4b: throttle — второй раз тихо"

# T5: не-коммит → тихо
cd "$REPO"
OUT=$(printf '{"session_id":"test-cl","tool_name":"Bash","tool_input":{"command":"ls -la"}}' | env STATE_DIR="$TMP/s5" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T5: не-коммит игнорируется"

# T6: CHANGELOG правлен в рабочем дереве, но ещё не добавлен в индекс → молчим.
#
# Так выглядит составная команда `git add -A && git commit -m x`: хук стоит на
# PreToolUse и читает индекс ДО того, как отработает `git add` из той же строки.
# CHANGELOG уйдёт в тот же коммит, а страж объявлял его отсутствующим — ложная
# тревога, снятая на этом же дереве 22.08. Тот же дефект чинили в docs-family-check
# на релизе v1.14.1; здесь он жил дальше.
cd "$REPO"
git reset -q
echo "новый код" >> hooks/feature.sh
git add hooks/feature.sh
printf '# changelog\n\n## [Unreleased]\n- запись\n' > CHANGELOG.md   # правлен, НЕ добавлен
assert_empty "$(run_hook s6 'git add -A && git commit -m x')" \
    "T6: CHANGELOG правлен, команда сама добавит всё → молчим"

# T6b/T6c: тот же грязный CHANGELOG, но команда добавляет ТОЛЬКО код → горит.
#
# Первая версия T6 подавала голый `git commit` и требовала молчания, то есть
# закрепляла ошибку: в такой коммит правленый в дереве файл не попадёт, и страж
# промолчал бы зря. Найдено адверсариальным прогоном — там сценарий довели до
# реального коммита и прочли `git show --name-only HEAD`: записи в нём не было.
assert_contains "$(run_hook s6b 'git commit -m fix hooks/feature.sh')" "CHANGELOG" \
    "T6b: pathspec-коммит не унесёт CHANGELOG → напоминает"
assert_contains "$(run_hook s6c)" "CHANGELOG" \
    "T6c: голый коммит уносит только индекс → напоминает"

# T7: контрольный случай — CHANGELOG не тронут вовсе, всё прочее то же → горит.
# Без него зелёный T6 неотличим от стража, отключённого до немоты.
git checkout -q -- CHANGELOG.md
assert_contains "$(run_hook s7 'git add -A && git commit -m x')" "CHANGELOG" \
    "T7: CHANGELOG не тронут → напоминает даже при add -A"

echo ""
echo "changelog-reminder tests: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
