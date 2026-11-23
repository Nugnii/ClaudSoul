#!/usr/bin/env bash
# journal.sh — журнал задач ablation-замера (протокол §3–§4, D64).
#
# Результат: ни одна регистрация не пережила закрытие своей фазы без классификации, и ни
#            одна строка журнала не переписана.
# Проверка результата: bash scripts/ablation/journal.sh unclassified даёт 0
#
# Приватный append-only jsonl ВНЕ репозитория (формулировки задач могут нести
# личный контекст): ABLATION_DIR, по умолчанию ~/.claude/ablation. В публичный
# снимок уходит только воронка числами (`funnel`).
#
# Дисциплина протокола, зашитая гвардами:
#   - task_id неизменяем, выдаётся при регистрации; повторной регистрации нет;
#   - классификация ровно одна (до вычисления сэмплера) — повторная запрещена;
#   - журнал append-only: никакая команда не переписывает прошлые строки;
#   - фаза не закрывается, пока в ней есть незакрытые классификацией регистрации
#     (`unclassified` + гейт в phase.sh close). Повод: задача t-20260827094245-20f2
#     зарегистрирована 27 августа 2026, фаза main-1 закрыта в тот же день, и задача
#     осталась без класса шестой день — никто не проверял полноту (D257).
#
# Команды:
#   register "<текст рабочего запроса>" [project]  → печатает task_id
#   classify <task_id> eligible|ineligible|nonsubstantive [reason] [type] [complexity]
#       type: bugfix|feature|maintenance (для eligible)
#   show <task_id>       → все события задачи
#   funnel               → числа воронки: registered/substantive/eligible/selected/queued
#   unclassified [фаза]  → без аргумента: задачи, зарегистрированные в УЖЕ ЗАКРЫТОЙ фазе и
#                          оставшиеся без classify. С именем фазы: то же по НАЗВАННОЙ фазе,
#                          открытой или закрытой (так гейт phase.sh close спрашивает про
#                          ту, которую закрывают). Код 1, если такие есть
#   replication-due      → задачи, которым положен второй независимый запуск (§10):
#                          каждая пятая ПО ПОРЯДКУ ВКЛЮЧЕНИЯ В ОЧЕРЕДЬ. До 3 сентября
#                          2026 §10 не имел исполнителя вовсе (grep по scripts/ablation:
#                          0 совпадений), и молчал он лишь потому, что queued = 0
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "journal: нужен jq" >&2; exit 1; }

DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
mkdir -p "$DIR"
J="$DIR/journal.jsonl"
touch "$J"

now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

CMD="${1:-}"
[ -n "$CMD" ] && shift || { echo "journal: команда обязательна (register|classify|show|funnel)" >&2; exit 1; }

case "$CMD" in
register)
    TEXT="${1:?journal register: текст запроса обязателен}"
    PROJECT="${2:-$PWD}"
    RAND=$(od -An -tx1 -N2 /dev/urandom | tr -d ' \n')
    ID="t-$(date -u +%Y%m%d%H%M%S)-${RAND}"
    jq -cn --arg id "$ID" --arg ts "$(now)" --arg text "$TEXT" --arg p "$PROJECT" \
        '{e:"register", id:$id, ts:$ts, text:$text, project:$p}' >> "$J"
    printf '%s\n' "$ID"
    ;;
classify)
    ID="${1:?task_id обязателен}"
    CLASS="${2:?класс обязателен}"
    case "$CLASS" in eligible|ineligible|nonsubstantive) ;; *)
        echo "journal classify: класс — eligible|ineligible|nonsubstantive" >&2; exit 1 ;; esac
    grep -q "\"id\":\"$ID\"" "$J" || { echo "journal: $ID не зарегистрирована" >&2; exit 1; }
    if jq -es --arg id "$ID" '[.[] | select(.e=="classify" and .id==$id)] | length > 0' "$J" >/dev/null 2>&1; then
        echo "journal: $ID уже классифицирована — классификация одна, до сэмплера (протокол §4)" >&2; exit 1
    fi
    jq -cn --arg id "$ID" --arg ts "$(now)" --arg c "$CLASS" \
        --arg r "${3:-}" --arg t "${4:-}" --arg x "${5:-}" \
        '{e:"classify", id:$id, ts:$ts, class:$c, reason:$r, type:$t, complexity:$x}' >> "$J"
    ;;
show)
    ID="${1:?task_id обязателен}"
    grep "\"id\":\"$ID\"" "$J" || { echo "journal: $ID не найдена" >&2; exit 1; }
    ;;
unclassified)
    # Окно между §3 (register до первого вызова инструмента) и §4 (classify до сэмплера)
    # штатно: reg > cls — норма, пока фаза ЖИВА. Дефект — регистрация, пережившая закрытие
    # своей фазы без класса: после close её уже никто не спросит.
    # Фаза регистрации определяется хронологическим проходом: register между phase_frozen
    # и phase_closed принадлежит той фазе. Регистрация вне активной фазы под правило не
    # подпадает — закрывать там нечего.
    ONLY="${1:-}"
    OUT=$(jq -s --arg only "$ONLY" '
        (reduce .[] as $r ({cur:null, reg:{}, closed:{}};
            if   $r.e=="phase_frozen" then .cur = $r.phase
            elif $r.e=="phase_closed" then .closed[$r.phase] = true | .cur = null
            elif $r.e=="register"     then .reg[$r.id] = {phase: .cur, ts: $r.ts, text: $r.text}
            else . end)) as $s
        | ([.[] | select(.e=="classify") | .id]) as $cls
        | [ $s.reg | to_entries[]
            | select(.value.phase != null
                     and (if $only == "" then ($s.closed[.value.phase] == true)
                          else (.value.phase == $only) end)
                     and (.key as $k | ($cls | index($k)) == null)) ]
        | .[] | "\(.key)  фаза \(.value.phase), зарегистрирована \(.value.ts)\n    \(.value.text)"
    ' -r "$J")
    if [ -n "$OUT" ]; then
        echo "journal: регистрации пережили закрытие своей фазы без классификации (§4):" >&2
        printf '%s\n' "$OUT" >&2
        echo "  Классифицирует владелец (§16). Команда:" >&2
        echo "  bash scripts/ablation/journal.sh classify <id> eligible|ineligible|nonsubstantive \"<почему>\" [type]" >&2
        exit 1
    fi
    ;;
replication-due)
    # §10: каждая пятая задача ПО ПОРЯДКУ ВКЛЮЧЕНИЯ В ОЧЕРЕДЬ получает второй независимый
    # запуск всех трёх плеч. Порядок — очереди, не завершения: инфраструктурные исключения
    # график не сдвигают. Печатает {id, position} на каждую задачу, которой положен повтор.
    jq -sc '[.[] | select(.e=="queue")] | to_entries[] | select((.key + 1) % 5 == 0)
            | {id: .value.id, position: (.key + 1)}' "$J"
    ;;
funnel)
    jq -s '
        def cnt(f): [.[] | select(f)] | length;
        {registered:  cnt(.e=="register"),
         substantive: cnt(.e=="classify" and (.class=="eligible" or .class=="ineligible")),
         eligible:    cnt(.e=="classify" and .class=="eligible"),
         selected:    cnt(.e=="sampler" and .selected==true),
         queued:      cnt(.e=="queue"),
         completed:   cnt(.e=="pair_done")}' "$J"
    ;;
*)
    echo "journal: неизвестная команда '$CMD'" >&2; exit 1
    ;;
esac
