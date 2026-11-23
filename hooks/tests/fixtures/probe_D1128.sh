#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh hooks/five-whys-gate.sh scripts/outcome.sh
# probe_D1128 — «не прочитан» при первом взгляде не запирает повод: когда бэклог снова читается, следующий вызов стража
# снимает его состояние заново, и пункт, записанный после, принимается. Красная (1), пока строка `snapbl …|unread|`
# пишется один раз и не пересматривается (третий скептик, M4: в мире «не устоялся» за ~2 с, пока бэклог пишет соседняя
# сессия). Положительный контроль — тот же сценарий с читаемым бэклогом. Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
[ "$(id -u)" -ne 0 ] || exit 2
run() {   # <sid> <0|1 — отнять право при первом взгляде> → решение стража после исхода
    P="$SB/p-$1"; gproj "$P" || return 2
    TR="$SB/tr-$1.jsonl"; mk_tr "$TR" "$FINDING"
    [ "$2" = 1 ] && chmod 000 "$P/BACKLOG.md"
    [ "$(dec "$(cw "$1" "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || { chmod 644 "$P/BACKLOG.md"; return 2; }
    chmod 644 "$P/BACKLOG.md"
    cr "$1" "$TR" "$P"                                   # следующий вызов стража — бэклог уже читается
    item "$P/BACKLOG.md" D9901 "hooks/x.sh:4"; no "$1" debt discovery D9901 "$P"
    dec "$(cw "$1" "$P/hooks/x.sh" "$TR" "$P")"
}
[ "$(run s1 0)" = allow ] || exit 2
[ "$(run s2 1)" = allow ] || { echo "«не прочитан» при первом взгляде запер повод: верный пункт не снял отказ" >&2; exit 1; }
echo "«не прочитан» пересматривается"
exit 0
