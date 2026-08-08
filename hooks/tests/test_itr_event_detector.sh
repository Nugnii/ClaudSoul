#!/usr/bin/env bash
# Unit tests for itr-event-detector.sh
# Run: bash hooks/tests/test_itr_event_detector.sh

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/itr-event-detector.sh"
LIB="$HOOK_DIR/intrusiveness-state-lib.sh"

# Isolate state
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Override both env vars so hook + lib agree on state dir.
export ITR_STATE_DIR="$TMP_DIR"
export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.claude/hooks/state"
# Hook reads LIB from $HOME/.claude/hooks/intrusiveness-state-lib.sh — symlink it.
# Lib sources its sibling intrusiveness-cost-lib.sh (Ф4 split) — symlink that too,
# иначе ${BASH_SOURCE%/*} в симлинкнутой библиотеке не найдёт под-библиотеку.
mkdir -p "$HOME/.claude/hooks"
ln -sf "$LIB" "$HOME/.claude/hooks/intrusiveness-state-lib.sh"
ln -sf "$HOOK_DIR/intrusiveness-cost-lib.sh" "$HOME/.claude/hooks/intrusiveness-cost-lib.sh"
ln -sf "$HOOK_DIR/intrusiveness-classify-lib.sh" "$HOME/.claude/hooks/intrusiveness-classify-lib.sh"
ln -sf "$HOOK_DIR/intrusiveness-format-lib.sh" "$HOME/.claude/hooks/intrusiveness-format-lib.sh"
ln -sf "$HOOK_DIR/intrusiveness-metrics-lib.sh" "$HOME/.claude/hooks/intrusiveness-metrics-lib.sh"

# Source lib for assertion helpers
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label: expected='$expected' actual='$actual'")
    fi
}

# Build a minimal transcript JSONL file with one assistant turn.
# Args: out_path, assistant_text
make_transcript() {
    local out="$1" text="$2"
    # JSONL: one record per line — must use compact (-c).
    jq -nc --arg t "$text" '{
        message: {
            role: "assistant",
            content: [{type:"text", text: $t}]
        }
    }' > "$out"
}

# Build a transcript with a prior user prompt + assistant turn that uses
# zero or more tool_use blocks plus optional text.
# Args: out_path, prior_user_text, assistant_text, tool_name1[,tool_name2,...]
# Pass empty string for assistant_text or tools to skip them. Tools are
# emitted as separate assistant records (matches Claude Code transcript
# layout where each block is its own JSONL line).
make_transcript_with_prior() {
    local out="$1"
    local prior_user="$2"
    local assistant_text="$3"
    local tools_csv="$4"

    : > "$out"

    # 1. Prior user prompt
    jq -nc --arg t "$prior_user" '{
        message: {
            role: "user",
            content: [{type:"text", text: $t}]
        }
    }' >> "$out"

    # 2. Tool_use records (one per tool)
    if [ -n "$tools_csv" ]; then
        local OLD_IFS="$IFS"
        IFS=','
        for tool in $tools_csv; do
            jq -nc --arg n "$tool" '{
                message: {
                    role: "assistant",
                    content: [{type:"tool_use", name:$n, id:"toolu_x", input:{}}]
                }
            }' >> "$out"
            # Tool result echoed by user role (mirrors real transcript)
            jq -nc --arg n "$tool" '{
                message: {
                    role: "user",
                    content: [{type:"tool_result", tool_use_id:"toolu_x", content:"ok"}]
                }
            }' >> "$out"
        done
        IFS="$OLD_IFS"
    fi

    # 3. Assistant text (last block of the turn — typical place for gentle
    #    questions) — only added if non-empty.
    if [ -n "$assistant_text" ]; then
        jq -nc --arg t "$assistant_text" '{
            message: {
                role: "assistant",
                content: [{type:"text", text: $t}]
            }
        }' >> "$out"
    fi
}

run_hook() {
    local sid="$1" prompt="$2" transcript="$3"
    local payload
    payload=$(jq -n \
        --arg sid "$sid" \
        --arg p "$prompt" \
        --arg tp "$transcript" \
        '{session_id:$sid, prompt:$p, transcript_path:$tp}')
    echo "$payload" | bash "$HOOK"
}

state_file() {
    printf '%s/intrusiveness-%s.json' "$ITR_STATE_DIR" "$1"
}

reset_session() {
    local sid="$1"
    rm -f "$(state_file "$sid")"
    rm -f "$HOME/.claude/hooks/state/itr_event_last_fire_${sid}"
    itr_init_state "$sid"
}

# =======================================================================
# Case 1: gentle + short accept → gentle_accepted=1
# =======================================================================
SID="t1-gentle-accept"
reset_session "$SID"
TR="$TMP_DIR/t1.jsonl"
make_transcript "$TR" "Готов приступать. Запускаем?"
run_hook "$SID" "да" "$TR"
assert_eq "t1: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t1: gentle_accepted=1" "1" "$(jq -r '.metrics.gentle_accepted' "$(state_file "$SID")")"
assert_eq "t1: gentle_ignored=0" "0" "$(jq -r '.metrics.gentle_ignored' "$(state_file "$SID")")"

# =======================================================================
# Case 2: gentle + short decline → gentle_ignored=1
# =======================================================================
SID="t2-gentle-decline"
reset_session "$SID"
TR="$TMP_DIR/t2.jsonl"
make_transcript "$TR" "Сделать X? Запускаем?"
run_hook "$SID" "нет, не надо" "$TR"
assert_eq "t2: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t2: gentle_ignored=1" "1" "$(jq -r '.metrics.gentle_ignored' "$(state_file "$SID")")"

# =======================================================================
# Case 3: gentle + new-topic long reply → gentle_ignored (moved_on)
# =======================================================================
SID="t3-gentle-moved-on"
reset_session "$SID"
TR="$TMP_DIR/t3.jsonl"
make_transcript "$TR" "Объём ~1 вечер. Запускаем?"
run_hook "$SID" "сначала покажи другой план проекта" "$TR"
assert_eq "t3: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t3: gentle_ignored=1" "1" "$(jq -r '.metrics.gentle_ignored' "$(state_file "$SID")")"
assert_eq "t3: reason contains moved_on" "1" \
    "$(jq -r '[.events[] | select(.reason | test("moved_on"))] | length' "$(state_file "$SID")")"

# =======================================================================
# Case 4: no gentle in assistant → no event
# =======================================================================
SID="t4-no-gentle"
reset_session "$SID"
TR="$TMP_DIR/t4.jsonl"
make_transcript "$TR" "План v1.4.0 — калибровка порогов. Блокер: мало истории."
run_hook "$SID" "да" "$TR"
assert_eq "t4: events=0" "0" "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 5: gentle without '?' in last paragraph → no event
#        (rhetorical/descriptive use of marker without actual question)
# =======================================================================
SID="t5-no-question"
reset_session "$SID"
TR="$TMP_DIR/t5.jsonl"
make_transcript "$TR" "Я могу запускать тесты по запросу. Они зелёные."
run_hook "$SID" "да" "$TR"
assert_eq "t5: events=0 (no '?' in para)" "0" "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 6: dedup — same turn twice, only one event
# =======================================================================
SID="t6-dedup"
reset_session "$SID"
TR="$TMP_DIR/t6.jsonl"
make_transcript "$TR" "Продолжаем?"
run_hook "$SID" "да" "$TR"
run_hook "$SID" "да" "$TR"
assert_eq "t6: events=1 after dup" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 7: English gentle + go ahead
# =======================================================================
SID="t7-english"
reset_session "$SID"
TR="$TMP_DIR/t7.jsonl"
make_transcript "$TR" "I've reviewed the code. Should I refactor this module?"
run_hook "$SID" "go ahead" "$TR"
assert_eq "t7: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t7: gentle_accepted=1" "1" "$(jq -r '.metrics.gentle_accepted' "$(state_file "$SID")")"

# =======================================================================
# Case 8: gentle buried in mid-message but trailing paragraph OK
# =======================================================================
SID="t8-last-para-only"
reset_session "$SID"
TR="$TMP_DIR/t8.jsonl"
make_transcript "$TR" "Обзор: код работает нормально.

Рекомендую рефакторинг модуля X. Запускаем?"
run_hook "$SID" "да" "$TR"
assert_eq "t8: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t8: gentle_accepted=1" "1" "$(jq -r '.metrics.gentle_accepted' "$(state_file "$SID")")"

# =======================================================================
# Case 9: gentle, but question is followed by more non-question paragraphs
#        → last-paragraph filter rejects (conservative — acceptable false neg)
# =======================================================================
SID="t9-last-para-nonquestion"
reset_session "$SID"
TR="$TMP_DIR/t9.jsonl"
make_transcript "$TR" "Запускаем?

Список изменений: A, B, C. Всё готово."
run_hook "$SID" "да" "$TR"
# Last paragraph has no '?' → no event. Conservative = preferred.
assert_eq "t9: events=0 (conservative false neg)" "0" "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 10: BACKWARD correction → ignored
# =======================================================================
SID="t10-correction"
reset_session "$SID"
TR="$TMP_DIR/t10.jsonl"
make_transcript "$TR" "Сделать через SQLite? Запускаем?"
run_hook "$SID" "не так — я имел в виду через JSON" "$TR"
assert_eq "t10: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t10: gentle_ignored=1" "1" "$(jq -r '.metrics.gentle_ignored' "$(state_file "$SID")")"

# =======================================================================
# Case 11: budget decrement — accepted bumps gentle_used
# =======================================================================
SID="t11-budget"
reset_session "$SID"
TR="$TMP_DIR/t11.jsonl"
make_transcript "$TR" "Запускаем?"
run_hook "$SID" "да" "$TR"
assert_eq "t11: gentle_used=1" "1" "$(jq -r '.budget.gentle_used' "$(state_file "$SID")")"
assert_eq "t11: gentle_max unchanged" "5" "$(jq -r '.budget.gentle_max' "$(state_file "$SID")")"

# =======================================================================
# Case 12: ignored shrinks budget (gentle_max -= 1, shrink_events += 1)
# =======================================================================
SID="t12-shrink"
reset_session "$SID"
TR="$TMP_DIR/t12.jsonl"
make_transcript "$TR" "Продолжаем?"
run_hook "$SID" "нет" "$TR"
assert_eq "t12: gentle_max shrunk to 4" "4" "$(jq -r '.budget.gentle_max' "$(state_file "$SID")")"
assert_eq "t12: shrink_events=1" "1" "$(jq -r '.budget.shrink_events' "$(state_file "$SID")")"

# =======================================================================
# Case 13: no transcript path → silent exit, no crash
# =======================================================================
SID="t13-no-transcript"
reset_session "$SID"
PAYLOAD=$(jq -n --arg sid "$SID" --arg p "да" '{session_id:$sid, prompt:$p}')
echo "$PAYLOAD" | bash "$HOOK"
assert_eq "t13: no crash, events=0" "0" "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 14: empty prompt → silent exit
# =======================================================================
SID="t14-empty-prompt"
reset_session "$SID"
TR="$TMP_DIR/t14.jsonl"
make_transcript "$TR" "Запускаем?"
run_hook "$SID" "" "$TR"
assert_eq "t14: empty prompt skips" "0" "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 15: missing session_id → silent exit
# =======================================================================
TR="$TMP_DIR/t15.jsonl"
make_transcript "$TR" "Запускаем?"
PAYLOAD=$(jq -n --arg tp "$TR" --arg p "да" '{transcript_path:$tp, prompt:$p}')
echo "$PAYLOAD" | bash "$HOOK"
# Hook exits silently. Nothing to assert beyond "didn't crash".
PASS=$((PASS + 1))

# =======================================================================
# PROACTIVE EVENT DETECTION
# =======================================================================

# Case 16: Edit without explicit request → proactive_accepted
# (user discussed an idea, agent edited a file, user moved on)
SID="t16-proactive-accept"
reset_session "$SID"
TR="$TMP_DIR/t16.jsonl"
make_transcript_with_prior "$TR" \
    "что думаешь о dependency hell в npm-проектах?" \
    "Внёс правку в package.json — синхронизировал версии." \
    "Edit"
run_hook "$SID" "ок" "$TR"
assert_eq "t16: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t16: type=proactive" "proactive" "$(jq -r '.events[0].type' "$(state_file "$SID")")"
assert_eq "t16: outcome=accepted" "accepted" "$(jq -r '.events[0].outcome' "$(state_file "$SID")")"

# =======================================================================
# Case 17: Edit with explicit imperative request → no event
# =======================================================================
SID="t17-explicit-request"
reset_session "$SID"
TR="$TMP_DIR/t17.jsonl"
make_transcript_with_prior "$TR" \
    "сделай рефакторинг этого блока" \
    "Готово." \
    "Edit"
run_hook "$SID" "ок" "$TR"
assert_eq "t17: explicit request → solicited" "solicited" \
    "$(jq -r '.events[0].type' "$(state_file "$SID")")"
assert_eq "t17: budget untouched" "0" \
    "$(jq -r '.budget.proactive_used' "$(state_file "$SID")")"

# =======================================================================
# Case 18: Edit after continuation marker → no event
# =======================================================================
SID="t18-continuation"
reset_session "$SID"
TR="$TMP_DIR/t18.jsonl"
make_transcript_with_prior "$TR" \
    "продолжай" \
    "Поправил." \
    "Edit"
run_hook "$SID" "ок" "$TR"
assert_eq "t18: continuation → solicited" "solicited" \
    "$(jq -r '.events[0].type' "$(state_file "$SID")")"
assert_eq "t18: budget untouched" "0" \
    "$(jq -r '.budget.proactive_used' "$(state_file "$SID")")"

# =======================================================================
# Case 19: Read-only tool (Read) — never proactive
# =======================================================================
SID="t19-read-only"
reset_session "$SID"
TR="$TMP_DIR/t19.jsonl"
make_transcript_with_prior "$TR" \
    "что в этом файле?" \
    "Здесь функция X." \
    "Read"
run_hook "$SID" "ок" "$TR"
assert_eq "t19: read-only → no event" "0" \
    "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 20: Edit + decline reply → proactive_ignored
# =======================================================================
SID="t20-proactive-decline"
reset_session "$SID"
TR="$TMP_DIR/t20.jsonl"
make_transcript_with_prior "$TR" \
    "обсудим архитектуру?" \
    "Внёс правку." \
    "Edit"
run_hook "$SID" "не надо так делать, откати" "$TR"
assert_eq "t20: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t20: type=proactive" "proactive" "$(jq -r '.events[0].type' "$(state_file "$SID")")"
assert_eq "t20: outcome=ignored" "ignored" "$(jq -r '.events[0].outcome' "$(state_file "$SID")")"

# =======================================================================
# Case 21: Edit + correction → proactive_ignored
# =======================================================================
SID="t21-proactive-correction"
reset_session "$SID"
TR="$TMP_DIR/t21.jsonl"
make_transcript_with_prior "$TR" \
    "посмотрим на варианты" \
    "Применил один из вариантов." \
    "Edit"
run_hook "$SID" "не так — я имел в виду другое" "$TR"
assert_eq "t21: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t21: outcome=ignored" "ignored" "$(jq -r '.events[0].outcome' "$(state_file "$SID")")"

# =======================================================================
# Case 22: Edit + neutral long reply → proactive_accepted (silent_accept)
# =======================================================================
SID="t22-silent-accept"
reset_session "$SID"
TR="$TMP_DIR/t22.jsonl"
make_transcript_with_prior "$TR" \
    "интересный кейс — что думаешь?" \
    "Внёс правку." \
    "Write"
run_hook "$SID" "теперь покажи список файлов в каталоге src" "$TR"
assert_eq "t22: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t22: outcome=accepted" "accepted" "$(jq -r '.events[0].outcome' "$(state_file "$SID")")"
assert_eq "t22: silent_accept marker" "1" \
    "$(jq -r '[.events[] | select(.reason | test("silent_accept"))] | length' "$(state_file "$SID")")"

# =======================================================================
# Case 23: Both gentle question AND tool_use → gentle takes precedence
# =======================================================================
SID="t23-gentle-priority"
reset_session "$SID"
TR="$TMP_DIR/t23.jsonl"
make_transcript_with_prior "$TR" \
    "что-нибудь сделай" \
    "Сделал. Запускаем?" \
    "Edit"
# Note: prior has "сделай" → action authorized → proactive can't fire
# anyway, but we want gentle to fire from the trailing "запускаем?".
# (Marker list requires verb+'?' adjacent, not separated by a noun.)
run_hook "$SID" "да" "$TR"
assert_eq "t23: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t23: type=gentle" "gentle" "$(jq -r '.events[0].type' "$(state_file "$SID")")"

# =======================================================================
# Case 24: English explicit request → no event
# =======================================================================
SID="t24-english-request"
reset_session "$SID"
TR="$TMP_DIR/t24.jsonl"
make_transcript_with_prior "$TR" \
    "fix this bug please" \
    "Done." \
    "Edit"
run_hook "$SID" "ok" "$TR"
assert_eq "t24: english request → solicited" "solicited" \
    "$(jq -r '.events[0].type' "$(state_file "$SID")")"
assert_eq "t24: budget untouched" "0" \
    "$(jq -r '.budget.proactive_used' "$(state_file "$SID")")"

# =======================================================================
# Case 25: Multiple tools, at least one destructive → proactive
# =======================================================================
SID="t25-multi-tools"
reset_session "$SID"
TR="$TMP_DIR/t25.jsonl"
make_transcript_with_prior "$TR" \
    "что у нас тут?" \
    "Прочитал, разобрался, поправил." \
    "Read,Grep,Edit"
run_hook "$SID" "ок" "$TR"
assert_eq "t25: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t25: type=proactive" "proactive" "$(jq -r '.events[0].type' "$(state_file "$SID")")"

# =======================================================================
# Case 26: Bash only — excluded from destructive set (handled by
#         bash-cost-detector separately) → no event
# =======================================================================
SID="t26-bash-only"
reset_session "$SID"
TR="$TMP_DIR/t26.jsonl"
make_transcript_with_prior "$TR" \
    "что выдаёт ls?" \
    "Список файлов." \
    "Bash"
run_hook "$SID" "ок" "$TR"
assert_eq "t26: bash → no event" "0" \
    "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 27: Long prior with embedded "сделай" → no event
# =======================================================================
SID="t27-embedded-request"
reset_session "$SID"
TR="$TMP_DIR/t27.jsonl"
make_transcript_with_prior "$TR" \
    "посмотрел вчера твой код. Кстати, сделай мне ещё пару правок в README" \
    "Сделал." \
    "Edit"
run_hook "$SID" "ок" "$TR"
assert_eq "t27: embedded request → solicited" "solicited" \
    "$(jq -r '.events[0].type' "$(state_file "$SID")")"
assert_eq "t27: budget untouched" "0" \
    "$(jq -r '.budget.proactive_used' "$(state_file "$SID")")"

# =======================================================================
# Case 28: Proactive dedup — same turn twice → only one event
# =======================================================================
SID="t28-proactive-dedup"
reset_session "$SID"
TR="$TMP_DIR/t28.jsonl"
make_transcript_with_prior "$TR" \
    "обсуждаем дизайн" \
    "Поправил файл." \
    "Edit"
run_hook "$SID" "ок" "$TR"
run_hook "$SID" "ок" "$TR"
assert_eq "t28: dedup → 1 event" "1" \
    "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 29: Proactive accepted bumps proactive_used budget
# =======================================================================
SID="t29-proactive-budget"
reset_session "$SID"
TR="$TMP_DIR/t29.jsonl"
make_transcript_with_prior "$TR" \
    "что думаешь о тестах?" \
    "Добавил тест." \
    "Write"
run_hook "$SID" "ок" "$TR"
assert_eq "t29: proactive_used=1" "1" \
    "$(jq -r '.budget.proactive_used' "$(state_file "$SID")")"
assert_eq "t29: proactive_max unchanged" "3" \
    "$(jq -r '.budget.proactive_max' "$(state_file "$SID")")"

# =======================================================================
# Case 30: Proactive ignored does NOT bump proactive_used
# =======================================================================
SID="t30-proactive-ignored-budget"
reset_session "$SID"
TR="$TMP_DIR/t30.jsonl"
make_transcript_with_prior "$TR" \
    "опиши проблему" \
    "Я её исправил." \
    "Edit"
run_hook "$SID" "не надо было — откати" "$TR"
assert_eq "t30: proactive_used=0 after ignored" "0" \
    "$(jq -r '.budget.proactive_used' "$(state_file "$SID")")"
assert_eq "t30: proactive_events=1" "1" \
    "$(jq -r '.metrics.proactive_events' "$(state_file "$SID")")"

# =======================================================================
# Case 31: Bug-fix regression — gentle question with text AFTER tool_use
#          (the bug that prompted the full-turn extraction refactor)
# =======================================================================
SID="t31-text-after-tool"
reset_session "$SID"
TR="$TMP_DIR/t31.jsonl"
# Note: tool comes between two assistant text entries → newest record
# is "Запускаем?" — but the OLD detector would have picked the FIRST
# assistant record walking backward, which is fine. The bug shows up
# when the newest IS a tool_use with no trailing text. Build that:
{
    jq -nc --arg t "вопрос" '{message:{role:"user",content:[{type:"text",text:$t}]}}'
    jq -nc --arg t "Запускаем?" '{message:{role:"assistant",content:[{type:"text",text:$t}]}}'
    jq -nc '{message:{role:"assistant",content:[{type:"tool_use",name:"Read",id:"x",input:{}}]}}'
    jq -nc '{message:{role:"user",content:[{type:"tool_result",tool_use_id:"x",content:"ok"}]}}'
} > "$TR"
run_hook "$SID" "да" "$TR"
# OLD code would set LAST_ASSISTANT="" (newest is tool_use, no text).
# NEW code joins all assistant text in turn → catches "Запускаем?".
assert_eq "t31: gentle event captured" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t31: type=gentle" "gentle" "$(jq -r '.events[0].type' "$(state_file "$SID")")"

# =======================================================================
# Case 32: системный turn (task-notification) как «реплика» → нет исхода.
#          Маркер отказа («не надо») в теле tool_result ≠ ответ юзера на
#          предложение (pattern-guard-scope-blindness, hook-input-lib).
# =======================================================================
SID="t32-system-turn"
reset_session "$SID"
TR="$TMP_DIR/t32.jsonl"
make_transcript "$TR" "Готов приступать. Запускаем?"
run_hook "$SID" "<task-notification><result>не надо</result></task-notification>" "$TR"
assert_eq "t32: system turn → no event" "0" "$(jq -r '.events | length' "$(state_file "$SID")")"

# =======================================================================
# Case 33: заглавная кириллица в предыдущем промпте юзера — «Проверь» такой же
#          явный запрос, как «проверь». Свёртка регистра должна работать и на
#          Linux, где GNU tr многобайтовые буквы не трогает.
#          Слово выбрано так, что без свёртки не срабатывает ни один маркер:
#          у «Сделай» остаток «делай» — сам по себе маркер, и тест был бы слеп.
# =======================================================================
SID="t33-prior-uppercase"
reset_session "$SID"
TR="$TMP_DIR/t33.jsonl"
make_transcript_with_prior "$TR" \
    "Проверь этот блок ещё раз" \
    "Готово." \
    "Edit"
run_hook "$SID" "ок" "$TR"
assert_eq "t33: uppercase request → solicited (свёртка регистра работает)" "solicited" \
    "$(jq -r '.events[0].type' "$(state_file "$SID")")"

# =======================================================================
# Case 34: заглавная кириллица в ответе юзера — «Да» это то же согласие,
#          что и «да» (второй сайт свёртки регистра).
# =======================================================================
SID="t34-reply-uppercase"
reset_session "$SID"
TR="$TMP_DIR/t34.jsonl"
make_transcript "$TR" "Готов приступать. Запускаем?"
run_hook "$SID" "Да" "$TR"
assert_eq "t34: events=1" "1" "$(jq -r '.events | length' "$(state_file "$SID")")"
assert_eq "t34: gentle_accepted=1" "1" "$(jq -r '.metrics.gentle_accepted' "$(state_file "$SID")")"

# =======================================================================
echo ""
echo "============================================================"
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "FAILURES:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
echo "All tests passed."
