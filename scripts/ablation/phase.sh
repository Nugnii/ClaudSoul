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
            # Срок отсчитывается от ПЕРВОЙ ПРИНЯТОЙ задачи — как написано в §13
            # и как уже считает `ablation-phase-guard.sh` («8 недель с первой
            # принятой»). 2026-08-09 здесь перешли на отсчёт от начала фазы,
            # потому что при пустой очереди `days_left` выходил null и по
            # статусу нельзя было понять, когда закрывать. Это была беда
            # ЧИТАЕМОСТИ, а вылечили её сменой ПРАВИЛА: с якорем на старте фазы
            # окно закрывалось бы по календарю, не приняв ни одной задачи —
            # 8 недель без компьютера дают нулевой замер (владелец, 2026-08-27).
            # Теперь правило вернулось к §13, а читаемость закрыта явной
            # строкой `enrollment_clock`, и два места кода снова согласны.
            SINCE=$(jq -r '.since // empty' "$M")
            jq -s --arg since "$SINCE" '
                [.[] | select(.e=="queue")] as $q
                | ($q | length) as $n
                | ([.[] | select(.e=="pair_done")] | length) as $done
                | (if $n > 0 then ($q[0].ts | fromdateiso8601) else null end) as $t0
                | {queued: $n, pairs_done: $done,
                   first_queued: (if $n > 0 then $q[0].ts else null end),
                   phase_since: (if $since == "" then null else $since end),
                   enrollment_clock: (if $t0 == null
                                      then "не запущен — очередь пуста, календарь не идёт"
                                      else "идёт с первой принятой задачи" end),
                   days_elapsed: (if $t0 == null then null else (((now - $t0) / 86400) | floor) end),
                   days_left: (if $t0 == null then null
                               else ((((4838400 - (now - $t0)) / 86400) | floor)) end),
                   stop_condition_met: ($n >= 20 or ($t0 != null and (now - $t0) > 4838400))}' "$J"
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
