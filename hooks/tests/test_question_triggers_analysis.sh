#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/inquiry-gap.sh
# test_question_triggers_analysis.sh — вопрос собеседника требует разбора причин.
#
# Результат: вопрос собеседника доходит до гейта разбора и требует цепочки, не отказывая
# Проверка результата: bash hooks/tests/test_question_triggers_analysis.sh даёт 0
#
# Повод, 29 августа 2026, дословно: «сигнал поправки наравне с переделкой и провалами
# а как же мои вопросы? (даже этот, по сути я спрашиваю "почему" и ты тупо выдаёшь ответ
# сразу)». Замер того же часа: `inquiry-gap.sh` вопрос РАСПОЗНАЁТ (проверено прогоном на
# двух живых репликах), но в состояние ничего не пишет — записей ноль, только чтение
# `intrusiveness-<SID>.json`. Для поправки о поведении данные лежали и потребителя не
# было (27 файлов); для вопроса не было даже данных.
#
# Повод, не оставляющий следа, не может быть предметом НИКАКОЙ последующей проверки —
# ни гейта разбора, ни стража на правке. Это и есть звено, которое здесь проверяется.
#
# КОНТРПРИМЕРЫ, оба проверяются ниже:
#   · сессия без вопросов этого повода не получает — иначе гейт станет фоном;
#   · сигнал СТОЯЧИЙ: отказа по нему не бывает. Словарь продюсера ловит вопросительное
#     слово, а не род вопроса, и вопрос о факте («как запустить тесты?») попадёт в сигнал
#     наравне с вскрывающим дыру. Отказ на неизмеренный признак запрещён правилом,
#     записанным в шапке `five-whys-gate.sh`.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$HOOKS/five-whys-gate.sh"
PROD_SH="$HOOKS/inquiry-gap.sh"
[ -f "$GATE" ] || { echo "FAIL: нет $GATE"; exit 1; }
[ -f "$PROD_SH" ] || { echo "FAIL: нет $PROD_SH"; exit 1; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_gate() {
    STATE_DIR="$TMP" bash "$GATE" <<PAYLOAD
{"tool_name":"Edit","cwd":"$TMP","tool_input":{"file_path":"$TMP/x.sh"},"session_id":"$1"}
PAYLOAD
}

# Запись без права на отказ МОЛЧИТ (D1151, 31 октября 2026): вопрос — стоячий вид, и то, что гейт принял его поводом,
# читается строкой журнала `turn:…|<виды>`; повод и адрес порядка разбора звучат в ОТКАЗЕ, когда рядом повод с правом.
seen_q() { grep -q '^turn:.*question:' "$TMP/five-whys-$1.seen" 2>/dev/null; }

# --- T1: вопрос есть → гейт заводит повод; запись молчит ---
SID="with-question"
printf '{"date":"2026-08-29T12:19:00Z","kind":"question","digest":"1"}\n' \
    > "$TMP/question-open-${SID}.jsonl"
OUT=$(run_gate "$SID")
if seen_q "$SID" && [ -z "$OUT" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: вопрос не принят поводом либо запись не молчит: $OUT"; fi
SIDD="with-question-deny"
cp "$TMP/question-open-${SID}.jsonl" "$TMP/question-open-${SIDD}.jsonl"
printf '2' > "$TMP/error_streak_fired_${SIDD}"
OUTD=$(run_gate "$SIDD")
if grep -q 'вопрос собеседника' <<< "$OUTD" && grep -q 'rules/CLAUDE.md, Step 2' <<< "$OUTD"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1b]: в отказе не назван вопрос либо адрес порядка разбора: $OUTD"; fi

# --- T2: КОНТРПРИМЕР — без вопроса этого повода нет ---
OUT2=$(run_gate "clean-session")
if grep -q 'вопрос собеседника' <<< "$OUT2" || seen_q "clean-session"; then
    FAIL=$((FAIL+1)); echo "FAIL [T2]: повод назван без сигнала — гейт станет фоном"
else PASS=$((PASS+1)); fi

# --- T3: КОНТРПРИМЕР — сигнал стоячий, отказа по нему не бывает ---
if grep -q '"permissionDecision":"deny"' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [T3]: отказ по неизмеренному признаку"
else PASS=$((PASS+1)); fi

# --- T4: продюсер и потребитель сходятся на ОДНОМ имени файла ---
# Нормализация снимает ИМЕННО суффикс актора — по ИМЕНИ переменной, а не «любую вторую
# подстановку». Первая редакция схлопывала произвольную их последовательность в одну «SID», и
# настоящее расхождение у РОДИТЕЛЯ (`question-open-${SESSION_ID}${SESSION_ID}.jsonl` у писателя)
# проходило зелёным — сверщик R1, ослепший ровно в том ходе, где R1 и чинился. Поймано
# адверсариальной проверкой 18 сентября 2026 мутацией писателя; редакция HEAD ту же мутацию
# отбивала. Предмет ноги прежний: у родителя оба конца обязаны сойтись на одном имени.
norm() { sed -E 's/\$\{?(_FWG_ACTOR_SIGNALS|ET_ACTOR|RW_ACTOR)\}?//g; s/\$[{]?[A-Za-z_]+[}]?/SID/'; }
PROD=$(grep -oE 'question-open-(\$\{?[A-Za-z_]+\}?)+\.jsonl' "$PROD_SH" | head -1 | norm)
CONS=$(grep -oE 'question-open-(\$\{?[A-Za-z_]+\}?)+\.jsonl' "$GATE" | head -1 | norm)
if [ -n "$PROD" ] && [ "$PROD" = "$CONS" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: продюсер пишет '$PROD', гейт читает '$CONS'"; fi

# --- T5: сквозь оба механизма, а не по совпадению имён ---
# Согласие имён проверяет строки; здесь проверяется мир: продюсер запускается на живой
# реплике, потребитель читает то, что тот записал.
E2E="e2e-question"
if command -v jq >/dev/null 2>&1; then
    STATE_DIR="$TMP" bash "$PROD_SH" >/dev/null 2>&1 <<PAYLOAD || { echo "подготовка мира не удалась: hooks/tests/test_question_triggers_analysis.sh:$LINENO" >&2; exit 1; }
{"session_id":"$E2E","prompt":"почему не создаются механизмы?"}
PAYLOAD
    if [ -s "$TMP/question-open-${E2E}.jsonl" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [T5a]: продюсер не записал состояние"; fi
    run_gate "$E2E" >/dev/null
    if seen_q "$E2E"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [T5b]: гейт не увидел записанного продюсером"; fi
else
    echo "SKIP [T5]: нет jq"
fi

echo "question triggers analysis: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
