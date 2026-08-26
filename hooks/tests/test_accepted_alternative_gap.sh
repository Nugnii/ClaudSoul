#!/usr/bin/env bash
# test_accepted_alternative_gap.sh — детекция принятия чужого варианта в своей
# реплике на Stop. Изоляция через STATE_DIR; транскрипт — фикстурный jsonl.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/accepted-alternative-gap.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}
assert_empty() {
    local actual="$1" label="$2"
    if [ -z "$actual" ] || [ "$actual" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected empty, got: $actual"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

# mktemp, не счётчик: вызов идёт через $(...), инкремент в подоболочке терялся,
# и все фикстуры молча писались в один файл (латентно с рождения теста).
make_transcript() {
    local f
    f=$(mktemp "$TMP/transcript-XXXXXX")
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    jq -nc --arg t "$1" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    printf '%s' "$f"
}

run_with() {
    local sid="$1" transcript="$2"
    printf '{"session_id":"%s","transcript_path":"%s"}' "$sid" "$transcript" | \
        STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null
}

# --- T1: фраза принятия → fire с требованием гэп-разбора ---
F=$(make_transcript "Отличная идея, твой вариант лучше моего — вшиваю.")
OUT=$(run_with "sid1" "$F")
assert_contains "$OUT" "принят вариант" "T1: принятие детектировано"
assert_contains "$OUT" "Катчабельно ли принятое" "T1b: требование классификации"
assert_contains "$OUT" "минимум 3 уровня" "T1c: требование цепочки почему"

# --- T2: нейтральная реплика → silent ---
F=$(make_transcript "Готово, тесты зелёные, коммит создан.")
OUT=$(run_with "sid2" "$F")
assert_empty "$OUT" "T2: нейтральная реплика игнорируется"

# --- T3: принятие + гэп-разбор в той же реплике → silent (дисциплина исполнена) ---
F=$(make_transcript "Твой вариант лучше моего. Гэп-разбор: катчабельно pattern-inside-out-blindness.")
OUT=$(run_with "sid3" "$F")
assert_empty "$OUT" "T3: разбор в той же реплике глушит инжект"

# --- T4: постоянный механизм — принятие в НОВОМ ходе той же сессии тоже fire ---
# Маркер ключуется позицией последней реплики владельца: новая реплика двигает
# позицию, детектор взводится заново (повтор в том же ходе — T8).
F=$(make_transcript "Отличная идея, вшиваю.")
printf '{"message":{"role":"user","content":[{"type":"text","text":"а если так?"}]}}\n' >> "$F"
printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Беру твой вариант, так проще."}]}}\n' >> "$F"
OUT=$(run_with "sid1" "$F")
assert_contains "$OUT" "принят вариант" "T4: принятие в новом ходе срабатывает"

# --- T8: повторный Stop того же хода → маркер глушит (класс канарейки) ---
OUT=$(run_with "sid1" "$F")
assert_empty "$OUT" "T8: повтор в том же ходе — тишина"

# --- T9: stop_hook_active=true → тихий выход до детекта ---
F=$(make_transcript "Твой вариант лучше моего.")
OUT=$(printf '{"session_id":"sid9","transcript_path":"%s","stop_hook_active":true}' "$F" | \
    STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T9: stop_hook_active — страж молчит"

# --- T5: distressed state → silent (AP2) ---
printf '{"state_axis":"distressed"}' > "$STATE_DIR/intrusiveness-sid5.json"
F=$(make_transcript "Ваш вариант лучше, переделываю.")
OUT=$(run_with "sid5" "$F")
assert_empty "$OUT" "T5: distressed глушит инжект"

# --- T6: нет transcript_path → silent, не падает ---
OUT=$(printf '{"session_id":"sid6"}' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T6: без транскрипта тихий выход"

# --- T7: нет session_id → silent, не падает ---
F=$(make_transcript "Твой вариант лучше моего.")
OUT=$(printf '{"transcript_path":"%s"}' "$F" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T7: без session_id тихий выход"

echo "test_accepted_alternative_gap: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
