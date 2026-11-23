#!/usr/bin/env bash
# test_state_size.sh — «Проверка результата» state-size.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/state-size.sh печатает число файлов и объём каталога
#            состояния, крупнейшие семейства с именами без идентификатора сессии, отвечает 1 при
#            превышении порога файлов либо объёма и 2, когда каталога нет.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Кандидатов в свидетели у инструмента не было ни одного.
# Каталог подкладывается через STATE_DIR, пороги — через STATE_MAX_FILES/STATE_MAX_MB. Команда
# БЕРЁТСЯ из шапки инструмента, как в test_split_provenance_log.sh.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/state-size.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *state-size.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
S="$TMP/state"
SID1=0123abcd-0123-4567-89ab-0123456789ab; SID2=89abcdef-4567-0123-cdef-0123456789ab
# Четвёртый файл — в ПОДПАПКЕ: предмет — весь каталог, а мутант `find -maxdepth 1` проходил на
# плоской фикстуре (живой каталог несёт подпапки handoff-snapshots, measurement-runs).
mk_state() {
    rm -rf "$S"; mkdir -p "$S/sub"
    : > "$S/detect-$SID1.jsonl"; : > "$S/detect-$SID2.jsonl"; : > "$S/plain.txt"; : > "$S/sub/deep.jsonl"
}
run_tool() {   # MAXF / MAXM — пороги
    OUT=$(cd "$REPO" && STATE_DIR="$S" STATE_MAX_FILES="${MAXF:-3000}" STATE_MAX_MB="${MAXM:-40}" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: в пределах порогов — 0, числа и семейства напечатаны -----------------------------------
mk_state; run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'Каталог состояния: 4 файлов, 0 МБ (пороги: 3000 / 40 МБ)'
has T1 'Крупнейшие семейства:'
has T1 '2  detect-<sid>.jsonl'

# --- T2: файлов больше порога — 1 -----------------------------------------------------------
mk_state; MAXF=3 run_tool
[ "$RC" -eq 1 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 'файлов больше порога'

# --- T3: объём больше порога — 1 ------------------------------------------------------------
mk_state; dd if=/dev/zero of="$S/big.bin" bs=1024 count=2048 2>/dev/null; MAXM=1 run_tool
[ "$RC" -eq 1 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'объём больше порога'

# --- T4: каталога нет — 2, не «0 файлов» -----------------------------------------------------
rm -rf "$S"; run_tool
[ "$RC" -eq 2 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'нет каталога'

# --- T-DEF (D1006, 20 октября 2026; D1225, 7 ноября 2026): пороги по умолчанию — 6000 файлов / 160 МБ, решения владельца
# Остальные ноги задают пороги окружением, поэтому откат значений по умолчанию к 3000 / 40 был бы им не виден.
mk_state
OUT=$(cd "$REPO" && env -u STATE_MAX_FILES -u STATE_MAX_MB STATE_DIR="$S" bash scripts/state-size.sh 2>&1)
has T-DEF '(пороги: 6000 / 160 МБ)'

# --- T-KNOB (второй круг финального скептика D1006): порог не число — код 2, а не ложный зелёный --------------
# `[ -gt ]` на нечисле падает, ветка превышения не берётся, и прежде замер отвечал 0, ничего не сравнив.
for kv in STATE_MAX_FILES=abc STATE_MAX_MB=9x STATE_MAX_FILES=99999999999999999999; do
    mk_state; OUT=$(cd "$REPO" && env "$kv" STATE_DIR="$S" bash scripts/state-size.sh 2>&1); RC=$?
    [ "$RC" -eq 2 ] && ok || bad T-KNOB "$kv: rc=$RC — $OUT"
    has T-KNOB 'порог не проверялся'
done

echo ""
echo "state-size tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
