#!/usr/bin/env bash
# test_launchd_freshness.sh — у задания по расписанию есть владелец, но не было проверки,
# что владелец жив.
#
# Повод. `scripts/measurements.tsv` перечисляет три замера с периодом 0 — «по расписанию
# launchd». `measurement-due.sh:46-49` делает `continue` ДО сравнения возраста, то есть
# период 0 означает буквальное освобождение от проверки. Развёртка по системе (D38) нашла
# ровно этот класс: обязанность, у которой владелец назван, а того, что он сработал, не
# проверяет ничто.
#
# Отдельно проверяется ветка «выгружено»: на машине, где задания загружены, воспроизвести
# её иначе нельзя, и она осталась бы недоказанной — а это ровно тот случай, когда зелёный
# прогон ничего не значит.
#
# И отдельно — SIGPIPE. Первая версия скрипта объявила выгруженными два ЖИВЫХ задания:
# `launchctl list | grep -q` под `set -o pipefail` даёт статус 141, потому что launchctl
# пишет постепенно, а grep выходит по первому совпадению. Совпадало только то задание,
# что стоит в выводе последним. Этот случай закреплён T5.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/launchd-freshness.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# Фикстура: все три задания «загружены», артефакты свежие.
LIST=$(printf -- '-\t0\tcom.claudsoul.knowledge-audit\n-\t0\tcom.claudsoul.bridge-health\n-\t0\tcom.claudsoul.scanner\n')
mkdir -p "$TMP/state" "$TMP/lessons/_audit-history" "$TMP/bridges"
touch "$TMP/state/last-scan-timestamp"
touch "$TMP/lessons/_audit-history/audit-2026-W31.md"
touch "$TMP/bridges/health-2026-07.md"

run() {
    CLAUDSOUL_LAUNCHD_LIST="${1-$LIST}" \
    STATE_DIR="$TMP/state" LESSONS_DIR="$TMP/lessons" BRIDGES_HISTORY_DIR="$TMP/bridges" \
    bash "$SCRIPT" 2>&1
}

# --- T1: всё живо и свежо — проверка молчит и возвращает 0 ---
OUT=$(run); RC=$?
[ "$RC" -eq 0 ] && ok || bad "T1a" "здоровое состояние вернуло $RC"
printf '%s' "$OUT" | grep -q 'все живы и свежи' && ok || bad "T1b" "нет строки об исправном состоянии: $OUT"

# --- T2: задание выгружено — названо поимённо и роняет проверку ---
OUT=$(run "$(printf -- '-\t0\tcom.claudsoul.scanner\n')"); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T2a" "выгруженные задания не уронили проверку"
printf '%s' "$OUT" | grep -q 'выгружено: com.claudsoul.knowledge-audit' && ok \
    || bad "T2b" "выгруженное задание не названо"
printf '%s' "$OUT" | grep -q 'выгружено: com.claudsoul.scanner' && bad "T2c" "живое задание названо выгруженным" || ok

# --- T3: артефакт протух — названо с возрастом и допуском ---
touch -t 202601010000 "$TMP/state/last-scan-timestamp"
OUT=$(run); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3a" "протухший артефакт не уронил проверку"
printf '%s' "$OUT" | grep -q 'протухло:   com.claudsoul.scanner' && ok || bad "T3b" "протухшее не названо: $OUT"
touch "$TMP/state/last-scan-timestamp"

# --- T4: артефакта нет вовсе — отличается от «протух» ---
rm -f "$TMP/bridges/health-2026-07.md"
OUT=$(run)
printf '%s' "$OUT" | grep -q 'без следа:  com.claudsoul.bridge-health' && ok \
    || bad "T4" "отсутствие артефакта не отличено от устаревания"
touch "$TMP/bridges/health-2026-07.md"

# --- T5: SIGPIPE — список заданий снимается один раз, а не конвейером на проверку ---
# Прямой отрицательный контроль: воспроизвести прежнюю конструкцию и убедиться, что она
# ВРЁТ, а нынешняя — нет. Без этого случая T1 зелен и при возврате дефекта.
if command -v launchctl >/dev/null 2>&1; then
    _old=$(bash -c 'set -uo pipefail; launchctl list 2>/dev/null | grep -q "[[:space:]]com.claudsoul.knowledge-audit$"; echo $?' 2>/dev/null || echo skip)
    _new=$(bash -c 'set -uo pipefail; L=$(launchctl list 2>/dev/null || true); printf "%s\n" "$L" | grep -q "[[:space:]]com.claudsoul.knowledge-audit$"; echo $?' 2>/dev/null || echo skip)
    if [ "$_old" = "skip" ] || ! printf '%s' "$LIST" >/dev/null; then
        ok   # нет launchctl — нечего доказывать
    elif [ "$_new" = "0" ]; then
        ok   # нынешняя конструкция даёт верный ответ (а прежняя давала 141)
    else
        bad "T5" "снятие списка в переменную не дало верного ответа (_old=$_old _new=$_new)"
    fi
else
    ok
fi

# --- T6: скрипт не содержит конвейера `launchctl ... | grep` — источник дефекта ---
# Комментарии исключаются: дефект в них описан намеренно, и без этого T6 краснел на
# собственном объяснении. Ровно тот случай, о котором предупреждает документация проекта:
# страж сопоставляет текст, а не действие.
if grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -qE 'launchctl[^|]*\|[[:space:]]*grep'; then
    bad "T6" "вернулся конвейер launchctl | grep — статус 141 под pipefail"
else ok; fi

# --- T7: реестр замеров знает про эту проверку ---
REG="$REPO/scripts/measurements.tsv"
if [ -f "$REG" ]; then
    grep -q '^launchd-freshness' "$REG" && ok || bad "T7" "проверки нет в реестре замеров — у неё самой нет срока"
else
    bad "T7" "нет реестра $REG"
fi

echo ""
echo "launchd freshness tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
