#!/usr/bin/env bash
# test_user_correction_guard.sh — предметный признак сравнивает реплику с ходом агента
# ДО неё, а не со своим эхом.
#
# Результат: «Сигнал C» стража поправок считает пересечение слов реплики с последним
#   текстом агента, написанным ДО этой реплики; текст текущего хода в сравнение не входит
# Проверка результата: bash hooks/tests/test_user_correction_guard.sh даёт 0
#
# Повод, измеренный 13 сентября 2026. Шапка стража объявляет предмет так: «поправка
# говорит о том, что агент только что назвал сделанным». Код брал последний текст агента
# ВООБЩЕ (`select(.type=="assistant") | … | tail -1`), а на первом же вызове инструмента
# текущего хода последним оказывается текст, написанный УЖЕ ПОСЛЕ реплики. Пункт 0 велит
# начинать ход с переформулировки реплики своими словами — и признак сравнивал реплику
# с её собственным эхом.
#
# Цена по корпусу (243 расшифровки, 1929 настоящих реплик): срабатываний предметного
# признака 681, из них 414 (60,8%) держались ТОЛЬКО на тексте после реплики; словарь
# перехватывает из них 39. Ложная поправка не только шумит: срод `correction` даёт гейту
# разбора право на ОТКАЗ (five-whys-gate.sh:98), и первым же таким отказом в этой сессии
# был остановлен законный прогон набора тестов.
#
# КОНТРПРИМЕР (страж обязан СКАЗАТЬ): реплика, чьи слова стоят в ходе агента ДО неё, —
# это и есть объявленный предмет, и молчание на ней было бы починкой вырезанием проверки.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/user-correction-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
assert_silent()   { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; }
assert_contains() { if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в: $(printf '%s' "$1" | head -c 200)"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Записи расшифровки — в той форме, в какой их читает `transcript_agent_text_before_reply`.
rec_user()  { jq -cn --arg t "$1" '{type:"user", origin:{kind:"human"}, message:{content:[{type:"text", text:$t}]}}'; }
rec_meta()  { jq -cn --arg t "$1" '{type:"user", isMeta:true, message:{content:[{type:"text", text:$t}]}}'; }
rec_agent() { jq -cn --arg t "$1" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}'; }

run_guard() { # $1 sid, $2 transcript → stdout
    jq -cn --arg s "$1" --arg p "$2" \
        '{session_id:$s, transcript_path:$p, tool_name:"Bash", tool_input:{}, hook_event_name:"PreToolUse"}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

# Реплика подобрана так, чтобы СЛОВАРЬ поправок её не брал: срабатывание или тишина
# ниже говорят о предметном признаке, а не о лексике.
REPLY='Доля переработок посчитана неверно'
BEFORE_HIT='Посчитана доля переработок в журнале: 13 процентов'
BEFORE_MISS='Открыл журнал и сверил числа'
ECHO_TURN='Проверяю: доля переработок посчитана по всем журналам'

# --- T0: положительный контроль — слова реплики стоят в ходе агента ДО неё → страж говорит ---
T="$TMP/t0.jsonl"
{ rec_user 'Посчитай долю переработок в журнале'; rec_agent "$BEFORE_HIT"; rec_user "$REPLY"; } > "$T"
OUT=$(run_guard t0 "$T")
assert_contains "$OUT" 'permissionDecision' 'T0 предмет назван — страж обязан сказать'

# --- T1: эхо текущего хода предметом не является → тишина (на прежнем коде нога красная) ---
T="$TMP/t1.jsonl"
{ rec_user 'Открой журнал'; rec_agent "$BEFORE_MISS"; rec_user "$REPLY"; rec_agent "$ECHO_TURN"; } > "$T"
OUT=$(run_guard t1 "$T")
assert_silent "$OUT" 'T1 сравнение с собственным эхом реплики'

# --- T2: первая реплика сессии — агент до неё не говорил, сравнивать не с чем ---
T="$TMP/t2.jsonl"
{ rec_user "$REPLY"; } > "$T"
OUT=$(run_guard t2 "$T")
assert_silent "$OUT" 'T2 сравнивать не с чем'

# --- T3: вставка харнесса границу не уводит ---
# Без признака авторства последней «репликой» стала бы вставка (:5), и в окно «до неё»
# попал бы эхо-текст текущего хода (:4) — то есть дефект вернулся бы через другую дверь.
T="$TMP/t3.jsonl"
{ rec_user 'Открой журнал'; rec_agent "$BEFORE_MISS"; rec_user "$REPLY"; rec_agent "$ECHO_TURN"
  rec_meta 'Доля переработок посчитана по журналам — тело скилла'; } > "$T"
OUT=$(run_guard t3 "$T")
assert_silent "$OUT" 'T3 граница по авторству, а не по роли записи'

echo "user correction guard subject window: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
