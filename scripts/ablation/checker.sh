#!/usr/bin/env bash
# checker.sh — проверяющий контракт пары ВНЕ writable-песочниц (протокол §9).
#
# Чекер живёт в ABLATION_DIR/checkers/ (агенты песочниц его не видят и не могут
# менять), его sha256 фиксируется в журнале ДО запусков; изменение чекера,
# гейта или DoD самим агентом успехом не считается — сверка hash перед каждым
# прогоном, расхождение = infrastructure_failure.
#
# Команды:
#   register <task_id> <script>   — копия чекера + sha256 в журнал (однократно)
#   run <task_id> full|vanilla    — классификация исхода плеча:
#       exit чекера 0 → success; 3 → blocked (запрос уточнения — собеседника
#       нет); прочее → objective_failure; raw timeout плеча → timeout.
set -euo pipefail

DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
J="$DIR/journal.jsonl"
CMD="${1:?команда: register|run}"; shift

now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

case "$CMD" in
register)
    ID="${1:?task_id}"; SRC="${2:?путь к скрипту чекера}"
    [ -f "$SRC" ] || { echo "checker: $SRC не найден" >&2; exit 1; }
    grep -q "\"id\":\"$ID\"" "$J" || { echo "checker: $ID не в журнале" >&2; exit 1; }
    if jq -es --arg id "$ID" '[.[] | select(.e=="checker_registered" and .id==$id)] | length > 0' "$J" >/dev/null 2>&1; then
        echo "checker: чекер $ID уже зафиксирован — hash фиксируется до запусков, один раз (§9)" >&2; exit 1
    fi
    mkdir -p "$DIR/checkers"
    cp "$SRC" "$DIR/checkers/$ID.sh"
    chmod 555 "$DIR/checkers/$ID.sh"
    jq -cn --arg id "$ID" --arg ts "$(now)" --arg h "$(sha "$DIR/checkers/$ID.sh")" \
        '{e:"checker_registered", id:$id, ts:$ts, sha256:$h}' >> "$J"
    ;;
run)
    ID="${1:?task_id}"; ARM="${2:?плечо}"
    CHK="$DIR/checkers/$ID.sh"
    H_REG=$(jq -rs --arg id "$ID" '[.[] | select(.e=="checker_registered" and .id==$id)][0].sha256 // empty' "$J")
    [ -n "$H_REG" ] || { echo "checker: hash $ID не зафиксирован до запусков" >&2; exit 1; }
    # События текущей попытки = после последнего pair_annulled (§9: повтор пары
    # целиком; прошлые события остаются в журнале свидетельством).
    CUT=$(jq -s --arg id "$ID" \
        '[to_entries[] | select(.value.e=="pair_annulled" and .value.id==$id) | .key] | max // -1' "$J")
    if jq -es --arg id "$ID" --arg a "$ARM" --argjson cut "$CUT" \
        'to_entries | [.[] | select(.key > $cut) | .value
         | select(.e=="arm_result" and .id==$id and .arm==$a)] | length > 0' "$J" >/dev/null 2>&1; then
        echo "checker: исход $ID/$ARM уже классифицирован в текущей попытке" >&2; exit 1
    fi
    if [ "$(sha "$CHK")" != "$H_REG" ]; then
        jq -cn --arg id "$ID" --arg a "$ARM" --arg ts "$(now)" \
            '{e:"arm_result", id:$id, arm:$a, ts:$ts, outcome:"infrastructure_failure", stage:"checker-hash"}' >> "$J"
        echo "checker: hash чекера изменился → infrastructure_failure" >&2; exit 1
    fi
    RAW=$(jq -rs --arg id "$ID" --arg a "$ARM" --argjson cut "$CUT" \
        'to_entries | [.[] | select(.key > $cut) | .value
         | select(.e=="arm_run" and .id==$id and .arm==$a)] | last.raw_outcome // empty' "$J")
    [ -n "$RAW" ] || { echo "checker: плечо $ID/$ARM ещё не бежало (нет arm_run)" >&2; exit 1; }
    WORK="$DIR/runs/$ID/$ARM/work"
    if [ "$RAW" = "timeout_or_error" ]; then
        OUTCOME="timeout"
    else
        set +e; bash "$CHK" "$WORK" >/dev/null 2>&1; RC=$?; set -e
        case "$RC" in 0) OUTCOME="success" ;; 3) OUTCOME="blocked" ;; *) OUTCOME="objective_failure" ;; esac
    fi
    jq -cn --arg id "$ID" --arg a "$ARM" --arg ts "$(now)" --arg o "$OUTCOME" --arg h "$H_REG" \
        '{e:"arm_result", id:$id, arm:$a, ts:$ts, outcome:$o, checker_sha256:$h}' >> "$J"
    echo "$OUTCOME"
    ;;
*)  echo "checker: неизвестная команда" >&2; exit 1 ;;
esac
