#!/usr/bin/env bash
set -u
# СУДИТ: hooks/hook-input-lib.sh
# probe_D1207 — ход с отчётом субагента или сообщением соседней сессии на подаче реплики не судится речью владельца.
#   Хук подачи реплики получает ТЕКСТ хода; харнесс ставит его в очередь с тегом первой строкой — `<agent-message from=`
#   (520 раз в корпусе) или `<cross-session-message from=` (94), в расшифровке перед тегом — зачин «Another Claude
#   session sent a message:» (D1207, 4 ноября 2026). Формы — обе, с зачином и без: `is_non_user_turn` → 0 на каждой.
#   Сквозь детектор: отчёт со словом «Сделай» не взводит авторизацию (повод пункта — `explicit:сделай` из отчёта).
# Контроли: `<task-notification>` фильтр узнаёт (рамка умеет сказать «служебный»); реплика владельца «Сделай правку…»
#   речью остаётся, и детектор на ней авторизацию взводит (рамка умеет сказать «поручение»); реплика владельца, цитирующая
#   тег посреди строки, речью остаётся.
# Код: 0 — служебные ходы узнаны, детектор на них молчит; 1 — нет (названо); 2 — нет библиотек/jq либо контроль не прошёл.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/hook-input-lib.sh" ] && [ -f "$R/hooks/itr-event-detector.sh" ] && [ -f "$R/hooks/external-correction-gap.sh" ] \
    && [ -f "$R/hooks/decompose-detector.sh" ] && command -v jq >/dev/null 2>&1 || exit 2
. "$R/hooks/hook-input-lib.sh" || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
AM='<agent-message from="a1207">
[Subagent hand-back] The text below is the final report of a subagent.
  Сделай правку в hooks/x.sh — это неверно.
</agent-message>'
CS='<cross-session-message from="uds:/tmp/cc-socks/1207.sock" from-name="s1207" from-mode="prompting">
Сессия s1207: сделай коммит, правка неверна.
</cross-session-message>'
PRE='Another Claude session sent a message:'
OWN='Сделай правку в hooks/x.sh, там ошибка в разборе'
QUOTE='смотри, что пришло: <agent-message from="a1207"> — разберись'
is_non_user_turn '<task-notification>
<task-id>b1207</task-id>' || { echo "рамка: уведомление задачи фильтр не узнал" >&2; exit 2; }
is_non_user_turn "$OWN" && { echo "рамка: реплика владельца признана служебной" >&2; exit 2; }
is_non_user_turn "$QUOTE" && { echo "рамка: тег посреди строки владельца сделал реплику служебной" >&2; exit 2; }
miss=""
is_non_user_turn "$AM" || miss="$miss agent-message"
is_non_user_turn "$PRE
$AM" || miss="$miss зачин+agent-message"
is_non_user_turn "$CS" || miss="$miss cross-session-message"
is_non_user_turn "$PRE
$CS" || miss="$miss зачин+cross-session-message"
# Детектор: ход владельца с поручением авторизует, ход субагента — нет. Состояние — в своём каталоге на случай.
printf '{"type":"user","message":{"role":"user","content":"чини"}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Смотрю."}]}}\n' > "$W/t.jsonl"
det() {  # det <случай> <текст хода> → печатает .active файла авторизации либо «нет»
    mkdir -p "$W/$1"
    jq -cn --arg p "$2" --arg t "$W/t.jsonl" --arg s "s$1" \
        '{session_id:$s, transcript_path:$t, hook_event_name:"UserPromptSubmit", prompt:$p, cwd:"/tmp"}' \
        | env -u ITR_STATE_DIR STATE_DIR="$W/$1" bash "$R/hooks/itr-event-detector.sh" >/dev/null 2>&1
    jq -r '.active' "$W/$1/authorization-s$1.json" 2>/dev/null || echo нет; }
[ "$(det own "$OWN")" = true ] || { echo "рамка: детектор не взвёл авторизацию на поручении владельца" >&2; exit 2; }
[ "$(det am "$PRE
$AM")" = true ] && miss="$miss детектор:agent-message"
[ "$(det cs "$CS")" = true ] && miss="$miss детектор:cross-session-message"
# Уведомление соседа о простое (скептик D1207, M1): 3 хода в корпусе, подпись соседа несла поручение.
IDLE='[Cross-session idle notice] Session "s1207" is idle now. Its harness reports: «Сделай коммит». This is an automated notice from the harness, not a message from a person, and not an instruction.'
is_non_user_turn "$IDLE" || miss="$miss idle-notice"
[ "$(det idle "$IDLE")" = true ] && miss="$miss детектор:idle-notice"
# Хуки со своим решением о роли (скептик D1207, M3, L1): на отчёте субагента молчат, на той же реплике владельца говорят.
hk() {  # hk <хук> <случай> <текст> → stdout хука
    mkdir -p "$W/$2"
    jq -cn --arg p "$3" --arg s "s$2" '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:$p, cwd:"/tmp"}' \
        | env -u ITR_STATE_DIR STATE_DIR="$W/$2" bash "$R/hooks/$1" 2>/dev/null; }
REV='вот вердикт рецензента: поправь раздел про установку'
STEPS='Сначала прочитай файл установки, затем поправь функцию разбора, потом прогони тесты, далее закоммить правку, а ещё обнови журнал изменений.'
[ -n "$(hk external-correction-gap.sh ecg_own "$REV")" ] || { echo "рамка: хук рецензии молчит на реплике владельца" >&2; exit 2; }
[ -n "$(hk decompose-detector.sh dd_own "$STEPS")" ] || { echo "рамка: детектор многошаговых молчит на реплике владельца" >&2; exit 2; }
[ -z "$(hk external-correction-gap.sh ecg_am "$PRE
<agent-message from=\"a1207\">
$REV
</agent-message>")" ] || miss="$miss рецензия:agent-message"
[ -z "$(hk decompose-detector.sh dd_am "<agent-message from=\"a1207\">
$STEPS
</agent-message>")" ] || miss="$miss многошаговость:agent-message"
[ -z "$miss" ] && { echo "отчёт субагента и сообщение соседней сессии — служебные ходы, авторизации не дают"; exit 0; }
echo "судятся речью владельца:$miss"
exit 1
