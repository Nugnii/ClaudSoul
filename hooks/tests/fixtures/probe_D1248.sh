#!/usr/bin/env bash
set -u
# СУДИТ: hooks/intrusiveness-tracker.sh
# probe_D1248 — служебный ход (уведомление задачи, отчёт субагента) не двигает модель собеседника: после реплики
#   владельца «опять не работает…» (состояние stuck) уведомление задачи и отчёт субагента не меняют ни `state.current`,
#   ни `cost_hints.timing_cost_current`, ни счёт `state.distribution`, а следующая реплика владельца модель двигает
#   (idle записан, счёт idle +1). До D1248 трекер писал поверх `idle|1|non_user_turn` и цену момента по тексту
#   уведомления. Нога реплики владельца ПОСЛЕ служебных ходов и нога отчёта субагента — по скептику opus по 3c71142b
#   (M1): без них зелены были починки «служебный — только `<task-notification>`», «idle от владельца не пишется» и
#   «модель замерзает после первой реплики». Контроль — сама первая реплика владельца даёт stuck.
# Код: 0 — служебный ход модель не двигает, реплика владельца двигает; 1 — нет (названо); 2 — нет трекера, jq либо
#   контроль не собрался.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/intrusiveness-tracker.sh"
[ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/state"
run() {  # run <реплика>
    jq -cn --arg p "$1" '{session_id:"p1248", prompt:$p}' \
        | env -u ITR_STATE_DIR STATE_DIR="$W/state" bash "$HOOK" >/dev/null 2>&1
}
F="$W/state/intrusiveness-p1248.json"
snap() { jq -c '[.state.current, (.cost_hints.timing_cost_current // 0), (.state.distribution // {})]' "$F" 2>/dev/null; }
run "опять не работает, ещё раз то же самое"
[ -f "$F" ] || { echo "рамка: трекер не завёл состояние" >&2; exit 2; }
before=$(snap)
[ "$(jq -r '.state.current' "$F")" = stuck ] || { echo "рамка: реплика владельца не дала stuck: $before" >&2; exit 2; }
# Служебные ходы несут следы кода («error:», путь со строкой, `git commit`) — по ним цена момента выше нуля, а у
# реплики владельца 0: так видно, по чьему тексту она посчитана.
run "<task-notification> <task-id>x</task-id> <status>completed</status> <summary>error: hooks/x.sh:12 failed after git commit — всё готово? давай дальше</summary> </task-notification>"
after1=$(snap)
run "<agent-message from=\"a1\">[Subagent hand-back] error: hooks/y.sh:7 после git commit — давай дальше, всё готово</agent-message>"
after2=$(snap)
miss=""
[ "$after1" = "$before" ] || miss="$miss уведомление задачи сдвинуло модель (было $before, стало $after1);"
[ "$after2" = "$before" ] || miss="$miss отчёт субагента сдвинул модель (было $before, стало $after2);"
idle0=$(jq -r '.state.distribution.idle // 0' "$F")
run "хорошо, спасибо"
[ "$(jq -r '.state.current' "$F")" = idle ] && [ "$(jq -r '.state.distribution.idle // 0' "$F")" -eq $((idle0 + 1)) ] \
    || miss="$miss реплика владельца после служебных ходов модель не сдвинула: $(snap);"
[ -z "$miss" ] && { echo "служебный ход модель не двигает, реплика владельца двигает: $(snap)"; exit 0; }
echo "модель собеседника судится не по владельцу:$miss"
exit 1
