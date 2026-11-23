#!/usr/bin/env bash
# phase.sh — состояние измерительной фазы (протокол §6): помнить не нужно никому.
#
# Результат: активная фаза известна из маркера, а не из памяти владельца, и закрытая фаза
#            не оставила за собой регистраций без классификации.
# Проверка результата: bash scripts/ablation/journal.sh unclassified даёт 0
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
                   stop_condition_met: ($n >= 20 or ($t0 != null and (now - $t0) > 4838400)),
                   # Закрытие enrollment: 20-я принятая либо t0 + 8 недель — что раньше (§13);
                   # добор страты would_surface (§7) — не дольше +4 недель (2419200 с) после него.
                   # Заведено 3 сентября 2026 (D283): срок добора стоял в §7 и §13 с 27 августа,
                   # а в коде его не было (grep 2419200 по scripts/ablation — 0 совпадений), и по
                   # статусу нельзя было сказать, когда добор кончается. Сверяет с документом
                   # hooks/tests/test_ablation_protocol_claims.sh (P9).
                   # «Что раньше» — МИНИМУМ двух сроков, а не первая ветка условия (D299,
                   # 12 сентября 2026): прежняя редакция при n ≥ 20 брала время 20-й задачи
                   # безусловно, и если 20-я пришла через 95 дней, окно добора растягивалось
                   # вслед за ней. stop_condition_met строкой выше считал «или» верно — правило
                   # было переписано дважды разной формой, и вторая была неполна.
                   enrollment_closes_at: (if $t0 == null then null
                                          elif $n >= 20 then ([($q[19].ts | fromdateiso8601), $t0 + 4838400] | min | todate)
                                          else ($t0 + 4838400 | todate) end),
                   surface_extension_until: (if $t0 == null then null
                                             elif $n >= 20 then (([($q[19].ts | fromdateiso8601), $t0 + 4838400] | min) + 2419200 | todate)
                                             else ($t0 + 4838400 + 2419200 | todate) end)}' "$J"
        fi
    else echo "none"; exit 1; fi
    ;;
close)
    P="${2:?имя фазы}"
    [ -f "$M" ] || { echo "phase: активной фазы нет" >&2; exit 1; }
    CUR=$(jq -r '.phase' "$M")
    [ "$CUR" = "$P" ] || { echo "phase: активна '$CUR', не '$P'" >&2; exit 1; }
    # Полнота классификации — условие закрытия, а не пожелание. Протокол (§4) требует
    # ровно одну classify на каждую register; окно между ними штатно, пока фаза ЖИВА, и
    # становится дырой ровно в момент close: после него задачу уже никто не спросит.
    # Повод (D257): t-20260827094245-20f2 зарегистрирована 27 августа 2026, main-1 закрыта
    # в тот же день, задача осталась без класса шестой день. Никто не проверял — close
    # писал phase_closed и снимал маркер, не спросив ни разу, а ablation-phase-guard после
    # закрытия молчит по построению.
    # Отказ, а не напоминание: последствие у продолжения ОДНО — регистрация переживает свою
    # фазу без класса и выпадает из воронки навсегда. Выход из отказа один и он же верный:
    # классифицировать (§16 — решение владельца), команду печатает сам journal.sh.
    if ! bash "$(dirname -- "${BASH_SOURCE[0]:-$0}")/journal.sh" unclassified "$P"; then
        echo "phase: '$P' не закрыта — сперва классифицируй перечисленное выше (§4)" >&2
        exit 1
    fi
    jq -cn --arg p "$P" --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{e:"phase_closed", phase:$p, ts:$ts}' >> "$DIR/journal.jsonl"
    rm -f "$M"
    echo "phase: $P закрыта — накопленные policy-изменения можно активировать (§6)"
    ;;
*)  echo "phase: команда status|close" >&2; exit 1 ;;
esac
