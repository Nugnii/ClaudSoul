#!/usr/bin/env bash
# СУДИТ: scripts/backlog-refresh-readings.sh hooks/backlog-lib.sh
# test_adv_cmdring_reading_run_silent.sh — пропуск «Показания» оградой кольца (D503) в режиме run назван, а не выдан за «показания свежие».
#
# Атака (противник ограды кольца, 1 октября 2026). Ограда пересчёта показаний кладёт пропуск в
# список `stale`, но в режиме run этот список печатается только при `changed > 0`. Когда
# пересчитывать больше нечего, вложенный прогон печатает «обновлять нечего: показания свежие
# либо команд показания нет» — то есть пропуск, который ограда обещала назвать, читается как
# «проверено, чисто». Свидетель ограды (test_backlog_cmd_ring.sh, нога R4) судит только --check.
#
# Устройство ноги: «Показание» открытого пункта зовёт пересчёт в режиме run на том же бэклоге;
# счётчик с предохранителем «четыре» держит кольцо конечным на любом дереве.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
# Вложенный пересчёт ждёт замок держателя: пять проб вместо ста.
export CLAUDSOUL_LOCK_TRIES=5
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
T=$(mktemp -d)   # временное уберёт система
F="$T/f"; mkdir -p "$F"
cat > "$F/again.sh" <<EOF
echo x >> "$F/cnt"
[ "\$(wc -l < "$F/cnt")" -ge 4 ] && { echo 1; exit 0; }
BACKLOG_FILE="$F/BACKLOG.md" bash "$REPO/scripts/backlog-refresh-readings.sh" run > "$F/inner.out" 2>&1
echo 1
EOF
printf -- '- ☐ **D9004** проба кольца\n  **Проверка.** `false` → 0\n  **Показание.** `bash %s/again.sh`\n' "$F" > "$F/BACKLOG.md"
BACKLOG_FILE="$F/BACKLOG.md" bash "$REPO/scripts/backlog-refresh-readings.sh" run >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_cmdring_reading_run_silent.sh:$LINENO" >&2; exit 1; }

N=0; [ -f "$F/cnt" ] && N=$(wc -l < "$F/cnt" | tr -d ' ')
# Положительный контроль рамки: команда показания исполнилась, и ровно один раз (ограда сработала).
[ "$N" = 1 ] && ok || bad T0 "команда показания исполнилась $N раз (ожидалось 1) — рамка ноги не собралась либо ограда не сработала"
IN=$(cat "$F/inner.out" 2>/dev/null || true)
grep -q 'кольцо' <<< "$IN" && ok \
    || bad T1 "вложенный пересчёт в режиме run не назвал пропуск по кольцу; его вывод: «${IN}»"
if grep -q 'показания свежие' <<< "$IN"; then
    bad T2 "вложенный пересчёт выдал НЕисполненное показание за «показания свежие»: «${IN}»"
else
    ok
fi

echo "adv cmdring reading run silent: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
