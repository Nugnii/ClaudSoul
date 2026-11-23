#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_backlog_cmd_ring.sh scripts/backlog-archive.sh
# test_adv_cmdring_witness_pollutes_journal.sh — свидетель ограды кольца (D503) не пишет пропуск песочницы в журнал отказов архиватора в каталоге состояния владельца.
#
# Атака (противник ограды кольца, 1 октября 2026). Нога R1 свидетеля test_backlog_cmd_ring.sh
# зовёт архиватор без STATE_DIR. Вложенный архиватор называет пропуск по кольцу отказом и
# пишет его в журнал `${STATE_DIR:-~/.claude/hooks/state}/backlog-archive-fired-<день>.jsonl` —
# корпус замера `backlog-archive-refusals` («отказы архиватора поимённо … очередь на сверку»).
# Раннер набора STATE_DIR не задаёт (тесты изолируют его сами), значит каждый прогон набора
# кладёт владельцу поддельный отказ «D9001 … кольцо» с путём из /var/folders. Наблюдено в мире:
# в журнале 1 октября 2026 две такие строки (18:18 и 18:59 UTC).
#
# Рамка: свидетель исполняется с HOME в песочнице и без STATE_DIR — так, как его зовёт раннер;
# «каталог владельца» здесь — каталог состояния песочного HOME.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
SUBJ="$REPO/hooks/tests/test_backlog_cmd_ring.sh"
[ -f "$SUBJ" ] || { echo "FAIL [T-subj]: нет $SUBJ"; exit 1; }
T=$(mktemp -d)   # временное уберёт система
H="$T/home"; mkdir -p "$H"
OUT=$(env -u STATE_DIR -u BACKLOG_CHECKS_NESTED -u BACKLOG_CMD_RUNNING HOME="$H" bash "$SUBJ" 2>&1); RC=$?
# Положительный контроль рамки: свидетель отработал целиком (его собственный итог зелёный).
[ "$RC" = 0 ] && grep -q 'backlog cmd ring:' <<< "$OUT" && ok \
    || bad T0 "рамка: свидетель ограды не отработал (rc $RC): «${OUT}»"
J=$(cat "$H"/.claude/hooks/state/backlog-archive-fired-*.jsonl 2>/dev/null || true)
HIT=$(grep -c 'D9001' <<< "$J" || true)
[ "${HIT:-0}" = 0 ] && ok \
    || bad T1 "свидетель записал в журнал отказов архиватора каталога состояния HOME строк про песочный D9001: ${HIT} — каждый прогон набора пополняет корпус замера backlog-archive-refusals поддельным отказом"

echo "adv cmdring witness pollutes journal: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
