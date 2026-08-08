#!/usr/bin/env bash
# phase.sh — состояние измерительной фазы (протокол §6): помнить не нужно никому.
#
#   status         — активная фаза (JSON) или "none"; exit 0 = активна, 1 = нет
#   close <phase>  — конец фазы: событие phase_closed, маркер снят; накопленные
#                    policy-изменения можно активировать (§6)
#
# Источник истины — маркер ABLATION_DIR/active-phase.json (пишет freeze-policy).
# Его читают: ablation-phase-guard (сигнал в сессию + страж деплоя) и владелец.
set -euo pipefail

DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
M="$DIR/active-phase.json"

case "${1:?команда: status|close}" in
status)
    if [ -f "$M" ]; then
        cat "$M"
        # Счёт enrollment к условию остановки (§13: 20 в очереди либо 8 недель).
        J="$DIR/journal.jsonl"
        if [ -f "$J" ]; then
            jq -s '
                [.[] | select(.e=="queue")] as $q
                | ($q | length) as $n
                | ([.[] | select(.e=="pair_done")] | length) as $done
                | (if $n > 0 then ($q[0].ts | fromdateiso8601) else null end) as $first
                | {queued: $n, pairs_done: $done,
                   first_queued: (if $n > 0 then $q[0].ts else null end),
                   stop_condition_met: ($n >= 20 or ($first != null and (now - $first) > 4838400))}' "$J"
        fi
    else echo "none"; exit 1; fi
    ;;
close)
    P="${2:?имя фазы}"
    [ -f "$M" ] || { echo "phase: активной фазы нет" >&2; exit 1; }
    CUR=$(jq -r '.phase' "$M")
    [ "$CUR" = "$P" ] || { echo "phase: активна '$CUR', не '$P'" >&2; exit 1; }
    jq -cn --arg p "$P" --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{e:"phase_closed", phase:$p, ts:$ts}' >> "$DIR/journal.jsonl"
    rm -f "$M"
    echo "phase: $P закрыта — накопленные policy-изменения можно активировать (§6)"
    ;;
*)  echo "phase: команда status|close" >&2; exit 1 ;;
esac
