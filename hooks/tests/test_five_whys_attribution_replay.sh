#!/usr/bin/env bash
# СУДИТ: scripts/five-whys-attribution-replay.py
# test_five_whys_attribution_replay.sh — «Проверка результата» five-whys-attribution-replay.py меряет объявленный результат.
#
# Результат: команда из шапки scripts/five-whys-attribution-replay.py на подложенном корпусе
#            печатает число ходов с напоминанием, число прежде разрешённых и число отбитых новым
#            правилом с неразобранным предметом поимённо; пустой корпус — 2 «НЕ ИЗМЕРЕНО».
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Кандидатов в свидетели у инструмента не было ни одного. Корпус
# подкладывается через FWG_REPLAY_CORPUS; след и вердикт цепочки считает настоящая
# hooks/root-cause-lib.sh (тело цепочки — то же, что в отрицательном контроле инструмента).
# Команда БЕРЁТСЯ из шапки инструмента.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/five-whys-attribution-replay.py"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—|печатает).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *five-whys-attribution-replay.py*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
C="$TMP/corpus"; mkdir -p "$C"
REM='🔁 Признак повторяется (один класс повторился за сутки трижды и больше, а именно pattern-alpha-beta-gamma), а разбора причин в этом ходе не было.'
CHAIN='Почему сломалось? ← первое. Почему? ← второе. Почему? ← третье.'
user() { printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
rem()  { printf '{"type":"attachment","attachment":{"content":["%s"]}}\n' "$REM"; }
agent(){ printf '{"message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
run_tool() {
    OUT=$(cd "$REPO" && FWG_REPLAY_CORPUS="$C/*.jsonl" CLAUDSOUL_REPO="$REPO" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: три хода — цепочка о ДРУГОМ предмете (адрес есть, предмет напоминания не назван),
# цепочка с предметом, без цепочки. Цепочка без единого адреса прежним правилом и так отбивается
# (след rc_trace: addr=0), поэтому ход 1 называет чужой паттерн, а не молчит об именах.
{
    user 'первый'; rem; agent "$CHAIN Это pattern-other-thing-here, и корень назван."
    user 'второй'; rem; agent "$CHAIN Это pattern-alpha-beta-gamma, и корень назван."
    user 'третий'; rem; agent 'Сделал.'
} > "$C/s1.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'ходов с напоминанием и ответом агента: 3'
has T1 'из них прежнее правило РАЗРЕШАЛО:       2'
has T1 'новое правило ОТБИВАЕТ:                 1 (50% прежде разрешённых)'
has T1 'pattern-alpha-beta-gamma'

# --- T2: корпус пуст — 2 «НЕ ИЗМЕРЕНО», не нули ------------------------------------------------
rm -f "$C"/*.jsonl; run_tool
[ "$RC" -eq 2 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 'НЕ ИЗМЕРЕНО: корпус пуст'

# --- T3: напоминание БЕЗ лексического предмета (вопрос/streak) гасится любой цепочкой — фильтр
# LEXICAL (условие предиката): имя файла в шапке предметом не становится ---------------------------
REM2='🔁 Признак повторяется (вопрос собеседника про hooks/budget-gate.sh остался без ответа), а разбора причин в этом ходе не было.'
rm -f "$C"/*.jsonl
{
    user 'один'; printf '{"type":"attachment","attachment":{"content":["%s"]}}\n' "$REM2"; agent "$CHAIN Это pattern-other-thing-here, и корень назван."
} > "$C/s2.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'из них прежнее правило РАЗРЕШАЛО:       1'
has T3 'новое правило ОТБИВАЕТ:                 0'

# --- T4: режим --sample-rework N предъявляет напоминания о переработке С ТЕКСТОМ хода (D358,
# носитель 2): число в корпусе, файлы из скобок, ответ агента; напоминания других сигналов в выборку
# не входят. Вердикт «разворот ли это» выносит человек — прибор лишь предъявляет -----------------
REM3='🔁 Признак повторяется (повторные заходы на один файл при зелёных прогонах (foo.sh)), а разбора причин в этом ходе не было.'
rm -f "$C"/*.jsonl
{
    user 'раз'; printf '{"type":"attachment","attachment":{"content":["%s"]}}\n' "$REM3"; agent 'Чиню foo.sh снова: первый заход не сработал.'
    user 'два'; rem; agent 'Другое.'
} > "$C/s3.jsonl"
OUT=$(cd "$REPO" && FWG_REPLAY_CORPUS="$C/*.jsonl" python3 "$TOOL" --sample-rework 5 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'напоминаний о переработке в корпусе: 1; выборка 1'
has T4 'файлы: foo.sh'
has T4 'первый заход не сработал'
if grep -Fq 'pattern-alpha-beta-gamma' <<< "$OUT"; then bad T4 "напоминание другого сигнала попало в выборку переработки"; else ok; fi

echo ""
echo "five-whys-attribution-replay tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
