#!/usr/bin/env bash
# test_question_survival.sh — «Проверка результата» question-survival.py меряет объявленный результат.
#
# Результат: команда из шапки scripts/question-survival.py на подложенном корпусе печатает число
#            реплик, число признанных вопросом, число ходов, дошедших до правки файлов, и число из
#            них с произнесённой цепочкой; итог хода подводится на настоящей реплике, а не на
#            tool_result; без правок вердикт «ни разу не пережил».
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Кандидатов в свидетели у инструмента не было ни одного. Корпус
# подкладывается через HOME; вопросительные слова — настоящие, из hooks/inquiry-gap.sh (их наличие
# инструмент сам проверяет отрицательным контролем). Команда БЕРЁТСЯ из шапки инструмента.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/question-survival.py"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—|печатает).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *question-survival.py*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; P="$H/.claude/projects/proj"
run_tool() {
    OUT=$(cd "$REPO" && HOME="$H" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: вопрос → цепочка из трёх «почему» и правка; tool_result ход не закрывает ---------------
rm -rf "$H"; mkdir -p "$P"
{
    printf '{"type":"user","message":{"role":"user","content":"а почему тут не создаются механизмы?"}}\n'
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Почему? Потому. Почему? Потому. Почему? Вот."},{"type":"tool_use","name":"Edit","id":"1","input":{}}]}}\n'
    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}\n'
    printf '{"type":"user","message":{"role":"user","content":"сделай вот это"}}\n'
    printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","id":"2","input":{}}]}}\n'
} > "$P/s1.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'реплик собеседника в корпусе: 2'
has T1 'признак считает вопросом: 1'
has T1 'из них ход дошёл до правки файлов: 1'
has T1 'из них с произнесённой цепочкой (>=3 «почему»): 1'
has T1 'ВЕРДИКТ: вопрос переживает начало стройки в 100% случаев'

# --- T2: вопрос без правки следом — «ни разу не пережил» ----------------------------------------
rm -rf "$H"; mkdir -p "$P"
{
    printf '{"type":"user","message":{"role":"user","content":"а почему тут не создаются механизмы?"}}\n'
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Потому что."}]}}\n'
} > "$P/s1.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 'признак считает вопросом: 1'
has T2 'из них ход дошёл до правки файлов: 0'
has T2 'ВЕРДИКТ: вопрос ни разу не пережил начала стройки'

# --- T3: одно «почему» и правка — дожил до правки, цепочки нет (порог >=3 держится) --------------
rm -rf "$H"; mkdir -p "$P"
{
    printf '{"type":"user","message":{"role":"user","content":"а почему тут не создаются механизмы?"}}\n'
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Почему? Потому."},{"type":"tool_use","name":"Edit","id":"1","input":{}}]}}\n'
    printf '{"type":"user","message":{"role":"user","content":"сделай вот это"}}\n'
} > "$P/s1.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'из них ход дошёл до правки файлов: 1'
has T3 'из них с произнесённой цепочкой (>=3 «почему»): 0'

# --- T4: вопрос длиннее 400 символов вопросом не считается (порог инструмента) -------------------
rm -rf "$H"; mkdir -p "$P"
long=$(printf 'почему %.0s' $(seq 1 70))
printf '{"type":"user","message":{"role":"user","content":"%s?"}}\n{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","id":"1","input":{}}]}}\n{"type":"user","message":{"role":"user","content":"сделай вот это"}}\n' "$long" > "$P/s1.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'признак считает вопросом: 0'

echo ""
echo "question-survival tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
