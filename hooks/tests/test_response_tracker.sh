#!/usr/bin/env bash
# test_response_tracker.sh — онлайн-запись реакции агента на стимул.
#
# Зачем: это единственный писатель зависимой переменной («что агент сделал после
# предупреждения»). Тихий отказ здесь невидим — данные просто не копятся, а
# обнаружится это через месяцы при первом же анализе. Плюс хук висит на КАЖДОМ
# вызове инструмента, поэтому отдельно фиксируем дешёвый выход без стимула.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/response-tracker.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: ожидалось '$expected', получено '$actual'"; fi
}

run() {  # $1 — tool_name, $2 — file_path, $3 — sid
    printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$3" "$1" "$2" | \
        STATE_DIR="$TMP" bash "$HOOK" 2>/dev/null
}
LOG() { echo "$TMP/response-$1.jsonl"; }
lines() { { grep -c '' "$1" 2>/dev/null || echo 0; } | tr -d ' '; }

# === T1: нет стимула → тишина, файл не создаётся ===
run Read /tmp/a.md s1
assert_eq "0" "$([ -f "$(LOG s1)" ] && echo 1 || echo 0)" "T1: без маркера ничего не пишется"

# === T2: маркер блокера → пишем ===
printf '{"date":"x","key":"y"}\n' > "$TMP/blocker-fired-s2.jsonl"
run Read "/tmp/dir with space/PLAN.md" s2
assert_eq "1" "$(lines "$(LOG s2)")" "T2a: после маркера блокера запись появилась"
assert_eq "Read" "$(jq -r '.tool' "$(LOG s2)")" "T2b: инструмент записан"
assert_eq "/tmp/dir with space/PLAN.md" "$(jq -r '.file' "$(LOG s2)")" "T2c: путь с пробелами не сломал JSON"
assert_eq "blocker" "$(jq -r '.after' "$(LOG s2)")" "T2d: after=blocker"

# === T3: маркер инжекта знания → пишем ===
touch "$TMP/knowledge_injected_s3"
run Edit /tmp/x.md s3
assert_eq "knowledge" "$(jq -r '.after' "$(LOG s3)")" "T3: after=knowledge"

# === T4: оба маркера ===
printf '{"date":"x","key":"y"}\n' > "$TMP/blocker-fired-s4.jsonl"
touch "$TMP/knowledge_injected_s4"
run Write /tmp/x.md s4
assert_eq "both" "$(jq -r '.after' "$(LOG s4)")" "T4: after=both"

# === T5: последовательность вызовов накапливается в порядке ===
printf '{"date":"x","key":"y"}\n' > "$TMP/blocker-fired-s5.jsonl"
run Read /tmp/a.md s5
run Grep "" s5
run Edit /tmp/a.md s5
assert_eq "3" "$(lines "$(LOG s5)")" "T5a: три вызова — три строки"
assert_eq "Read Grep Edit" "$(jq -r '.tool' "$(LOG s5)" | tr '\n' ' ' | sed 's/ $//')" "T5b: порядок сохранён"

# === T6: пустой blocker-лог (нулевой размер) стимулом не считается ===
: > "$TMP/blocker-fired-s6.jsonl"
run Read /tmp/a.md s6
assert_eq "0" "$([ -f "$(LOG s6)" ] && echo 1 || echo 0)" "T6: пустой лог маркера не считается стимулом"

# === T7: битый вход не роняет хук ===
printf 'не json' | STATE_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
assert_eq "0" "$?" "T7: мусор на входе → exit 0"

# === T8: все записи — валидный JSON ===
BAD=0
while IFS= read -r l; do
    [ -z "$l" ] && continue
    printf '%s' "$l" | jq -e . >/dev/null 2>&1 || BAD=$((BAD + 1))
done < "$(LOG s5)"
assert_eq "0" "$BAD" "T8: все строки валидный JSON"

echo ""
echo "response-tracker tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
