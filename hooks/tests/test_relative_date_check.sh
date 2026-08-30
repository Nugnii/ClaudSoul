#!/usr/bin/env bash
# test_relative_date_check.sh — относительная дата без якоря в ответе агента.
#
# Что доказывается: страж горит на «вчера» без даты, молчит когда дата рядом,
# молчит на цитатах и коде, гасит находку после одного показа.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/relative-date-check.sh"
DETECTOR="$HOOKS_DIR/lib/relative-date-detect.py"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }
[ -f "$DETECTOR" ] || { echo "FAIL: $DETECTOR not found"; exit 1; }

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

assert_file_contains() {
    local file="$1" needle="$2" label="$3"
    [ -f "$file" ] || { FAIL=$((FAIL + 1)); echo "FAIL [$label]: file $file missing"; return; }
    if grep -Fq "$needle" "$file"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in $file:"; cat "$file"; fi
}

assert_file_missing() {
    local file="$1" label="$2"
    if [ ! -f "$file" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: $file should not exist:"; cat "$file"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
mkdir -p "$HOME/.claude/hooks/state"
STATE_DIR="$HOME/.claude/hooks/state"

make_transcript() {
    local path="$1" assistant_text="$2"
    {
        jq -cn '{type:"user", message:{role:"user", content:[{type:"text", text:"вопрос"}]}}'
        jq -cn --arg t "$assistant_text" \
            '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}'
    } > "$path"
}

run_hook() {
    local event="$1" sid="$2" transcript="${3:-}"
    jq -cn --arg event "$event" --arg sid "$sid" --arg tp "$transcript" \
        '{hook_event_name: $event, session_id: $sid, transcript_path: $tp}' \
        | bash "$SCRIPT" 2>/dev/null
}

detect() { printf '%s' "$1" | python3 "$DETECTOR" 2>/dev/null; }

# --- Детектор ---------------------------------------------------------------

# D1: относительное слово без даты — находка
OUT=$(detect "Вчера мы починили счётчики.")
assert_contains "$OUT" "Вчера" "D1: «вчера» без даты поймано"

# D2: дата рядом — чисто (главное различение стража)
OUT=$(detect "Вчера (20 августа) мы починили счётчики.")
assert_empty "$OUT" "D2: дата рядом → тишина"

# D3: абсолютная дата в ISO — чисто
OUT=$(detect "Сегодня, 2026-08-21, прогон зелёный.")
assert_empty "$OUT" "D3: ISO-дата → тишина"

# D4: цитата чужого текста — не утверждение агента
OUT=$(detect "> вчера всё падало")
assert_empty "$OUT" "D4: цитата → тишина"

# D5: код не сканируется
OUT=$(detect 'Смотри `git log --since=вчера` в консоли.')
assert_empty "$OUT" "D5: inline-код → тишина"

# D6: «N недель назад» — тот же класс
OUT=$(detect "Кейс писался неделю назад и висит до сих пор.")
assert_contains "$OUT" "неделю назад" "D6: «неделю назад» поймано"

# D7: соседнее предложение с датой не отбеливает — якорь нужен в своём
OUT=$(detect "Релиз был 12 августа. Вчера всё сломалось снова.")
assert_contains "$OUT" "Вчера" "D7: дата в другом предложении не считается"

# D8: «час назад» без времени — находка (правило про время, не только про календарь)
OUT=$(detect "Ветка ушла час назад.")
assert_contains "$OUT" "час назад" "D8: «час назад» поймано"

# D9: время суток как якорь — чисто
OUT=$(detect "Ветка ушла час назад (в 19:40).")
assert_empty "$OUT" "D9: время суток → тишина"

# D10: «только что» без якоря — находка
OUT=$(detect "Прогон только что закончился.")
assert_contains "$OUT" "только что" "D10: «только что» поймано"

# D11: слово в кавычках — упоминание, не датировка (разговор о самом правиле)
OUT=$(detect "Правило про «вчера» и «сегодня» держит хук.")
assert_empty "$OUT" "D11: упоминание в кавычках → тишина"

# D12: упоминание не глушит датировку в том же предложении
OUT=$(detect "Слово «вчера» я вчера написал зря.")
assert_contains "$OUT" "вчера" "D12: употребление рядом с упоминанием поймано"

# D13: текст без относительных слов — тишина
OUT=$(detect "Правка внесена 21 августа, тесты зелёные.")
assert_empty "$OUT" "D13: чистый текст → тишина"

# --- Хук --------------------------------------------------------------------

# T1: неизвестное событие → тишина, без следов
OUT=$(run_hook "PostToolUse" "sid-t1" "")
assert_empty "$OUT" "T1: чужое событие → тишина"
assert_file_missing "$STATE_DIR/relative-date-findings-sid-t1.jsonl" "T1: файла нет"

# T2: Stop без транскрипта → тишина
OUT=$(run_hook "Stop" "sid-t2" "")
assert_empty "$OUT" "T2: нет транскрипта → тишина"
assert_file_missing "$STATE_DIR/relative-date-findings-sid-t2.jsonl" "T2: файла нет"

# T3: Stop, чистый ответ → находок нет
TR3="$TMP/t3.jsonl"
make_transcript "$TR3" "Счётчики разведены 21 августа, прогон зелёный."
OUT=$(run_hook "Stop" "sid-t3" "$TR3")
assert_empty "$OUT" "T3: чистый ответ → тишина"
assert_file_missing "$STATE_DIR/relative-date-findings-sid-t3.jsonl" "T3: находок нет"

# T4: Stop, «вчера» без даты → находка записана, сам Stop молчит
TR4="$TMP/t4.jsonl"
make_transcript "$TR4" "Вчера мы разнесли версию и счётчики."
OUT=$(run_hook "Stop" "sid-t4" "$TR4")
assert_empty "$OUT" "T4: Stop не инжектит"
assert_file_contains "$STATE_DIR/relative-date-findings-sid-t4.jsonl" "Вчера" "T4: находка записана"
assert_file_contains "$STATE_DIR/relative-date-findings-sid-t4.jsonl" "pending" "T4: статус pending"

# T5: повторный скан того же текста → дубля нет
run_hook "Stop" "sid-t4" "$TR4" >/dev/null
COUNT=$(wc -l < "$STATE_DIR/relative-date-findings-sid-t4.jsonl" | tr -d ' ')
if [ "$COUNT" = "1" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T5: дедуп]: ожидалась 1 строка, получено $COUNT"; fi

# T6: UserPromptSubmit → инжект с сегодняшней датой как якорем
OUT=$(run_hook "UserPromptSubmit" "sid-t4" "")
assert_contains "$OUT" "Относительное время без якоря" "T6: маркер инжектнут"
assert_contains "$OUT" "$(date '+%Y-%m-%d %H:%M')" "T6: текущие дата и время в сообщении"
assert_contains "$OUT" '"hookEventName":"UserPromptSubmit"' "T6: конверт события"

# T7: второй показ → тишина
OUT=$(run_hook "UserPromptSubmit" "sid-t4" "")
assert_empty "$OUT" "T7: уже показано → тишина"

# T8: PreToolUse — второй канал показа, свой конверт
SID8="sid-t8"
jq -cn '{ts:"2026-08-21T10:00:00Z", sid:"sid-t8", event:"Stop", finding:"на днях :: поправим на днях", status:"pending"}' \
    > "$STATE_DIR/relative-date-findings-${SID8}.jsonl"
OUT=$(run_hook "PreToolUse" "$SID8" "")
assert_contains "$OUT" '"hookEventName":"PreToolUse"' "T8: конверт PreToolUse"
assert_contains "$OUT" "на днях" "T8: находка в сообщении"

# T9: PreCompact сканирует как Stop
TR9="$TMP/t9.jsonl"
make_transcript "$TR9" "Позавчера ушла ветка."
OUT=$(run_hook "PreCompact" "sid-t9" "$TR9")
assert_empty "$OUT" "T9: PreCompact молчит на выходе"
assert_file_contains "$STATE_DIR/relative-date-findings-sid-t9.jsonl" "Позавчера" "T9: PreCompact сканирует"

# T10: без python3 → тишина, не падение
# Оставляем ровно то, чем хук пользуется ДО проверки python3 (dirname/mkdir/jq),
# иначе 127 приходит от отсутствия mkdir и доказывает не то.
NOBIN=$(mktemp -d)
for b in jq mkdir dirname; do ln -sf "$(command -v "$b")" "$NOBIN/$b" 2>/dev/null || true; done
OUT=$(jq -cn '{hook_event_name:"Stop", session_id:"sid-t10", transcript_path:""}' \
    | env PATH="$NOBIN" /bin/bash "$SCRIPT" 2>/dev/null); RC=$?
rm -rf "$NOBIN"
assert_empty "$OUT" "T10: без python3 → тишина"
if [ "$RC" -eq 0 ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T10b]: rc=$RC, ожидался 0"; fi

echo ""
echo "=== relative-date-check tests ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
