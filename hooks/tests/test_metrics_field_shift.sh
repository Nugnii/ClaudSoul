#!/usr/bin/env bash
# test_metrics_field_shift.sh — «обнулённые confidence/impact» считаются в том контуре,
# где эти поля вообще предусмотрены.
#
# Результат: метрика сдвига полей не объявляет дефектом записи второго контура
# Проверка результата: bash hooks/tests/test_metrics_field_shift.sh даёт 0
#
# Повод, 7 сентября 2026. Метрика сообщала «Записей с обнулёнными confidence/impact: 270
# (сдвиг полей, разделитель попал в текст)». Замер по живому журналу (19 744 записи):
# нулевых 289, из них relation 278 и fact 11 — то есть ВСЕ записи энциклопедического
# контура и НИ ОДНОЙ operational. У entity/fact/relation поля `impact` нет по построению:
# это схема другого контура. Точность метрики на её же срабатываниях — 0 настоящих из 289,
# и объяснение в тексте («разделитель попал в текст») тоже было неверным.
# Ног у этой метрики не было ни одной — потому ложность и прожила незамеченной.
#
# КОНТРПРИМЕР: настоящий сдвиг у operational-записи (pattern-*) обязан считаться по-прежнему,
# иначе починка выродилась бы в «никогда не сообщать».
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
COLLECTOR="$REPO/hooks/metrics-collector.sh"
[ -f "$COLLECTOR" ] || { echo "SKIP: нет $COLLECTOR"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMPROOT=$(mktemp -d); trap 'rm -rf "$TMPROOT"' EXIT

# rec <файл> <impact> — строка журнала инжектов в живом формате
rec() { printf '{"via":"activator","file":"%s","confidence":2,"impact":%s,"scope":"universal","rank":1,"score":1,"session_id":"t","slot":1,"injected":1,"project":"p","date":"2026-09-07","fsrs_status":"ok","speaker_status":"ok"}\n' "$1" "$2"; }

# run <строки журнала> — печатает файл метрик
run() {
    _d=$(mktemp -d -p "$TMPROOT" 2>/dev/null || mktemp -d "$TMPROOT/XXXXXX")
    mkdir -p "$_d/.claude/hooks/state" "$_d/.claude/global-lessons"
    cat > "$_d/.claude/global-lessons/principle-stub.md" <<'MD'
---
name: stub
type: principle
confidence: 3
impact: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-15
status: active
---
stub
MD
    # Каждая запись — своей строкой. Подстановка команд срезает завершающие переводы,
    # и склеенные записи jq не разбирает: нога зеленела бы на форме, которой мир не
    # производит (case-2026-09-02-fixture-green-on-a-form-the-world-never-produces).
    printf '%s\n' "$@" > "$_d/.claude/hooks/state/injection-log.jsonl"
    HOME="$_d" bash "$COLLECTOR" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_metrics_field_shift.sh:$LINENO" >&2; exit 1; }
    cat "$_d/.claude/hooks/state/metrics.md" 2>/dev/null
}

LINE='Записей с обнулёнными confidence/impact'

# --- T1: КОНТРПРИМЕР — настоящий сдвиг у operational-записи считается ---
OUT=$(run "$(rec 'pattern-something.md' 0)")
case "$OUT" in
    *"$LINE"*) ok ;;
    *) bad "T1" "настоящий сдвиг у pattern-записи не назван" ;;
esac

# --- T2: записи ВТОРОГО контура с impact=0 — не дефект, а другая схема ---
OUT=$(run "$(rec 'relation-a-b.md' 0)" "$(rec 'fact-x.md' 0)" "$(rec 'entity-y.md' 0)")
case "$OUT" in
    *"$LINE"*) bad "T2" "записи энциклопедического контура объявлены сдвигом полей" ;;
    *) ok ;;
esac

# --- T3: смесь — считается ТОЛЬКО operational, и число это показывает ---
OUT=$(run "$(rec 'pattern-one.md' 0)" "$(rec 'relation-a.md' 0)" "$(rec 'relation-b.md' 0)" "$(rec 'fact-c.md' 0)")
# grep -o вместо sed: шаблон с кириллицей BSD-sed принимает за флаг (pattern-shell-portability)
_n=$(printf '%s' "$OUT" | grep -F "$LINE" | grep -oE '[0-9]+' | head -1)
# Проверка написана так, чтобы отказ чтения был ВИДЕН приборам: пустое `_n` — это не
# «насчитано 0», а «прочитать не удалось», и ветка отказа стоит первой строкой.
if [ -z "${_n:-}" ]; then
    bad "T3" "число из строки метрики не прочитано — сама строка: $(printf '%s' "$OUT" | grep -F "$LINE" | head -1)"
elif [ "$_n" = "1" ]; then
    ok
else
    bad "T3" "в смеси 1 operational + 3 второго контура насчитано '$_n' (ожидалась 1)"
fi

# --- T4: нормальные записи — строки нет ---
OUT=$(run "$(rec 'pattern-ok.md' 4)" "$(rec 'case-ok.md' 3)")
case "$OUT" in
    *"$LINE"*) bad "T4" "на здоровом журнале метрика сообщила о сдвиге" ;;
    *) ok ;;
esac

echo "metrics field shift: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
