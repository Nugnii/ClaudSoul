#!/usr/bin/env bash
# test_measurement_due.sh — у замера есть срок, и просроченный виден.
#
# Повод, сформулированный собеседником: «ну и толку что ты мерил, а пока я не сказал — не
# мерил? А если бы вообще не вспомнил? Всё что меряют должно дедлайн иметь».
#
# Случай конкретный: замер «становится ли знание инструментом» дал 1,4% — но случился
# только потому, что о нём спросили. Ни владельца, ни срока у измерения не было, и его
# отсутствие ничем не обнаруживалось. Замер, держащийся на чьей-то памяти, — намерение,
# а не механизм.
#
# Проверяются обе стороны: просроченное называется и выполняется, свежее не трогается,
# сломанная команда отличается от выполненной. Плюс отрицательный контроль на сам реестр.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/measurement-due.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state" "$TMP/repo/scripts"
cp "$SCRIPT" "$TMP/repo/scripts/"

# Реестр-фикстура: свежий, просроченный, сломанный, событийный.
printf '# id\tдней\tкоманда\tчто\n' > "$TMP/repo/scripts/measurements.tsv"
{
  printf 'fresh\t7\ttrue\tсвежий замер\n'
  printf 'stale\t7\ttrue\tпросроченный замер\n'
  printf 'found\t7\tsh -c "exit 1"\tзамер отработал и НАШЁЛ проблему\n'
  printf 'broken\t7\tsh -c "exit 2"\tзамер НЕ СМОГ отработать\n'
  printf 'evented\t0\ttrue\tпо событию, не по календарю\n'
} >> "$TMP/repo/scripts/measurements.tsv"

mkdir -p "$TMP/state/measurement-runs"
date +%s > "$TMP/state/measurement-runs/fresh"                       # прогонялся только что
printf '%s\n' "$(( $(date +%s) - 40 * 86400 ))" > "$TMP/state/measurement-runs/stale"
printf '%s\n' "$(( $(date +%s) - 40 * 86400 ))" > "$TMP/state/measurement-runs/broken"
printf '%s\n' "$(( $(date +%s) - 40 * 86400 ))" > "$TMP/state/measurement-runs/found"

run() { CLAUDSOUL_REPO="$TMP/repo" STATE_DIR="$TMP/state" bash "$TMP/repo/scripts/measurement-due.sh" "${1:-run}" 2>&1; }
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# --- T1: режим check называет просроченные и не трогает свежие ---
OUT=$(run check)
grep -q 'просрочен: stale' <<< "$OUT"  && ok || bad "T1a" "просроченный не назван"
grep -q 'просрочен: broken' <<< "$OUT" && ok || bad "T1b" "сломанный не назван"
grep -q 'просрочен: fresh' <<< "$OUT"  && bad "T1c" "свежий назван просроченным" || ok
grep -q 'просрочен: evented' <<< "$OUT" && bad "T1d" "событийный попал в просрочку" || ok
grep -q 'по событию: 1' <<< "$OUT"     && ok || bad "T1e" "событийные не посчитаны"

# --- T2: check ничего не запускает — отметка о прогоне не двигается ---
_before=$(cat "$TMP/state/measurement-runs/stale")
run check >/dev/null
[ "$(cat "$TMP/state/measurement-runs/stale")" = "$_before" ] && ok || bad "T2" "режим check изменил отметку о прогоне"

# --- T3: run выполняет просроченные и двигает отметку ---
# Код возврата различает ТРИ вещи: 0 — отработал без находок, 1 — отработал и НАШЁЛ
# проблему, ≥2 — не смог отработать. Прежняя версия считала ошибкой любой ненулевой код,
# поэтому замер, чья задача — краснеть на находке, отметки не получал НИКОГДА и висел
# вечно просроченным. Обнаружено на живом `escalation-age`: заявке 99 дней, он честно
# вернул 1, и это прочиталось как «команда сломалась».
OUT=$(run run)
[ "$(cat "$TMP/state/measurement-runs/stale")" != "$_before" ] && ok || bad "T3a" "отметка не обновилась после выполнения"
grep -q 'НЕ ВЫПОЛНЕН' <<< "$OUT" && ok || bad "T3b" "отказ (код 2) не отличён от выполнения"
grep -q 'ЕСТЬ НАХОДКИ' <<< "$OUT" && ok || bad "T3c" "находка (код 1) не отличена от отсутствия находок"

# --- T4: не сумевший отработать замер не получает отметку — иначе он «протухнет» тихо ---
[ "$(cat "$TMP/state/measurement-runs/broken")" = "$_before" ] && ok || bad "T4a" "у не выполнившегося замера обновилась отметка"

# --- T4b: замер С НАХОДКОЙ отметку получает: он выполнен, просто нашёл проблему ---
[ "$(cat "$TMP/state/measurement-runs/found")" != "$_before" ] && ok \
    || bad "T4b" "замер с находкой не отмечен — будет висеть вечно просроченным"

# --- T5: после выполнения просроченным остаётся только тот, что не смог отработать ---
OUT=$(run check)
_n=$(printf '%s' "$OUT" | grep -c '^  просрочен:' || true)
[ "${_n:-0}" -eq 1 ] && ok || bad "T5" "ожидался ровно один просроченный (отказавший), получено ${_n}"

# --- T6: отрицательный контроль — проверка обязана уметь найти просрочку ---
# Без него зелёный T5 не отличим от «скрипт ничего не смотрит».
printf '%s\n' "$(( $(date +%s) - 999 * 86400 ))" > "$TMP/state/measurement-runs/fresh"
grep -q 'просрочен: fresh' <<< "$(run check)" && ok \
    || bad "T6" "состаренный замер не распознан — проверка ничего не измеряет"

# --- T7: реальный реестр проекта разбирается и содержит замер о знаниях ---
REAL="$REPO/scripts/measurements.tsv"
if [ -f "$REAL" ]; then
    grep -q '^knowledge-instrument' "$REAL" && ok || bad "T7a" "в реестре нет замера knowledge-instrument"
    _bad=$(awk -F'\t' '!/^#/ && NF>0 && NF<4 {print NR}' "$REAL" | head -1)
    [ -z "$_bad" ] && ok || bad "T7b" "строка $_bad реестра не имеет четырёх колонок"
else
    bad "T7" "нет реального реестра $REAL"
fi

echo ""
echo "measurement due tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
