#!/usr/bin/env bash
# СУДИТ: scripts/backlog-refresh-readings.sh hooks/backlog-lib.sh
# test_adv2_cmdring_readings_check_hides_ring.sh — пересчёт показаний в режиме --check называет пропуск по ограде кольца (D503) и тогда, когда у соседнего пункта показание разошлось с миром.
#
# Атака (противник ограды кольца, раунд 2, 1 октября 2026; вход закрытого класса 3 — «пропуск гас»).
# В режиме --check ветка «разошлись» стоит ПЕРВОЙ и выходит `sys.exit(1)` до печати списка
# «не исполнены». Один устаревший сосед — и пропуск по кольцу не назван ни словом: вывод говорит
# только «показания разошлись с миром: · D9005», код тот же, что без пропуска. Нога R4
# test_backlog_cmd_ring.sh держит бэклог из одного пункта и этого не видит; режим run печатает
# оба списка (починка прошлого раунда) — расходятся два режима одного прибора.
#
# Рамка: как нога R4 — «Показание» D9004 зовёт пересчёт --check на том же бэклоге через посредника,
# счётчик с предохранителем «четыре»; рядом D9005 с показанием, разошедшимся с миром.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
export CLAUDSOUL_LOCK_TRIES=5
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX CLAUDSOUL_REPO
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"
F="$T/f"; mkdir -p "$F"
cat > "$F/again.sh" <<EOF
echo x >> "$F/cnt"
[ "\$(wc -l < "$F/cnt")" -ge 4 ] && { echo 1; exit 0; }
BACKLOG_FILE="$F/BACKLOG.md" bash "$REPO/scripts/backlog-refresh-readings.sh" --check > "$F/inner.out" 2>&1
echo 1
EOF
printf -- '- ☐ **D9004** проба кольца\n  **Проверка.** `false` → 0\n  **Показание.** `bash %s/again.sh`\n\n- ☐ **D9005** сосед с устаревшим показанием\n  **Проверка.** `false` → 0\n  **Показание.** `echo 2`\n  **Последнее показание (2026-01-01).** 1\n' "$F" > "$F/BACKLOG.md"
BACKLOG_FILE="$F/BACKLOG.md" bash "$REPO/scripts/backlog-refresh-readings.sh" --check >/dev/null 2>&1 || true  # `--check` отвечает не-нулём на устаревшее показание соседа — предмет: число прогонов читает строка ниже (D1261)

N=0; [ -f "$F/cnt" ] && N=$(wc -l < "$F/cnt" | tr -d ' ')
[ "$N" = 1 ] && ok || bad T0 "рамка: команда показания D9004 исполнилась $N раз (ожидалось 1)"
IN=$(cat "$F/inner.out" 2>/dev/null || true)
grep -q 'D9005' <<< "$IN" && ok || bad T0b "рамка: вложенный пересчёт не назвал устаревшее показание соседа D9005: «${IN}»"
grep -q 'кольцо' <<< "$IN" && ok \
    || bad T1 "вложенный пересчёт --check не назвал пропуск показания D9004 по кольцу — его скрыла ветка «разошлись» соседа; вывод: «$(printf '%s' "$IN" | tr '\n' ' ')»"

echo "adv2 cmdring readings check hides ring: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
