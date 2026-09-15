#!/usr/bin/env bash
# test_claude_md_size_check.sh — тест стража размера проектного CLAUDE.md.
# Предмет: молчит ниже порога; выше порога называет АДРЕС (самый жирный раздел) и
# отличает «детализацию без места» от «выноски, пересказывающей уже существующий модуль».
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/claude-md-size-check.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

assert_contains() { if grep -qF "$2" <<< "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет '$2' в '${1:0:200}'"; fi; }
assert_missing()  { if grep -qF "$2" <<< "$1"; then FAIL=$((FAIL+1)); echo "FAIL [$3]: не ждали '$2'"; else PASS=$((PASS+1)); fi; }
assert_empty()    { if [ -z "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалось пусто, '${1:0:120}'"; fi; }

REPO="$TMP/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q; git config user.email t@t; git config user.name t

pad() { head -c "$1" /dev/zero | tr '\0' 'x'; }   # ровно N байт наполнителя

run_hook() {  # $1 = state subdir
    printf '{"session_id":"test-size-%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$1" "$REPO" \
        | env STATE_DIR="$TMP/$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null
}

# T1: файл ниже порога → тихо
printf '# CLAUDE.md\n\n## Правила\n%s\n' "$(pad 1000)" > CLAUDE.md
assert_empty "$(run_hook s1)" "T1: ниже порога → тихо"

# T2: выше порога, выносок со ссылками на модули нет → прежний совет «вынеси в модуль»
{ printf '# CLAUDE.md\n\n## Мелкий раздел\nx\n\n## Жирный раздел\n'; pad 110000; printf '\n'; } > CLAUDE.md
OUT2=$(run_hook s2)
assert_contains "$OUT2" "вынеси детализацию" "T2: без пересказов → прежний совет"
assert_contains "$OUT2" "Жирный раздел"      "T2: назван адрес — самый жирный раздел"
assert_missing  "$OUT2" "ПЕРЕСКАЗЫВАЮТ"      "T2: про пересказы молчит"

# T3: выше порога и 12 выносок уже ссылаются на модули → совет про сжатие пересказов
{ printf '# CLAUDE.md\n\n## Бизнес-правила\n'
  for i in $(seq 1 12); do
      printf '> **Правило %d.** Текст. Подробно — [мод](.claude-docs/modules/m%d.md).\n\n' "$i" "$i"
  done
  pad 110000; printf '\n'; } > CLAUDE.md
OUT3=$(run_hook s3)
assert_contains "$OUT3" "ПЕРЕСКАЗЫВАЮТ"      "T3: пересказы распознаны"
assert_contains "$OUT3" ": 12"               "T3: число пересказов названо"
assert_missing  "$OUT3" "вынеси детализацию" "T3: бессмысленный совет не выдан"
assert_contains "$OUT3" "Бизнес-правила"     "T3: адрес раздела назван"

# T4: throttle — второй раз в той же сессии тихо
assert_empty "$(run_hook s3)" "T4: throttle держит"

# T5: не git commit → тихо
OUT5=$(printf '{"session_id":"t5","tool_name":"Bash","cwd":"%s","tool_input":{"command":"ls -la"}}' "$REPO" \
    | env STATE_DIR="$TMP/s5" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT5" "T5: не коммит → тихо"

echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
