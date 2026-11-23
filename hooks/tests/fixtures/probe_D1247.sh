#!/usr/bin/env bash
set -u
# СУДИТ: hooks/wakeup-author-mark.sh hooks/hook-input-lib.sh
# probe_D1247 — ход побудки `ScheduleWakeup` не судится речью владельца: текст, запланированный вызовом `ScheduleWakeup`
#   (его сумму пишет `hooks/wakeup-author-mark.sh` на PreToolUse), детектор событий `hooks/itr-event-detector.sh` на
#   подаче не принимает за поручение — авторизация не взводится. Контроль: тот же текст ДО записи побудки взводит
#   авторизацию `task:content` (иначе проба пуста), а другой текст после записи — по-прежнему взводит.
#   До D1247 вход хука автора не нёс, формы у текста нет, и детектор взводил авторизацию из слов агента.
# Код: 0 — ход побудки узнан служебным; 1 — нет (названо); 2 — нет хуков, jq либо контроль не собрался.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
MARK="$R/hooks/wakeup-author-mark.sh"; DET="$R/hooks/itr-event-detector.sh"
[ -f "$MARK" ] && [ -f "$DET" ] && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/state"
# Детектор без `transcript_path` выходит до авторизации — подаём расшифровку из одного хода агента.
jq -cn '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"Готово."}]}}' > "$W/t.jsonl"
P="Проверить, пришёл ли отчёт финального скептика, и довести закрытие пункта до коммита"
submit() {  # submit <сессия> <реплика> — подача реплики детектору
    jq -cn --arg s "$1" --arg p "$2" --arg t "$W/t.jsonl" \
        '{session_id:$s, prompt:$p, transcript_path:$t, hook_event_name:"UserPromptSubmit"}' \
        | env -u ITR_STATE_DIR STATE_DIR="$W/state" bash "$DET" >/dev/null 2>&1
}
active() { jq -r '.active // false' "$W/state/authorization-$1.json" 2>/dev/null; }
submit ctl "$P"
[ "$(active ctl)" = true ] || { echo "рамка: без записи побудки текст не взвёл авторизацию — судить нечем" >&2; exit 2; }
jq -cn --arg p "$P" '{session_id:"w", tool_name:"ScheduleWakeup", tool_input:{delaySeconds:60, prompt:$p, reason:"r"}}' \
    | env STATE_DIR="$W/state" bash "$MARK" >/dev/null 2>&1
[ -s "$W/state/wakeup-prompts.tsv" ] || { echo "запись побудки не легла: wakeup-prompts.tsv пуст"; exit 1; }
submit wk "$P"
submit other "Сделай, пожалуйста, разбор очереди и закрой оставшиеся пункты"
# Срок записи (скептик opus по 405034f0, M1): запись трёхчасовой давности — не побудка этого цикла, а повтор того же
# текста владельцем позже (в штатном `/loop` текст побудки — его команда); такая реплика остаётся поручением.
Q="Запусти цикл: проверяй очередь и закрывай готовые пункты до вечера"
printf '%s\t%s\n' "$(printf '%s' "$Q" | cksum | cut -d' ' -f1)" "$(( $(date +%s) - 10800 ))" >> "$W/state/wakeup-prompts.tsv"
submit late "$Q"
miss=""
[ "$(active wk)" = true ] && miss="$miss ход побудки взвёл авторизацию;"
[ "$(active other)" = true ] || miss="$miss реплика владельца после записи побудки авторизацию не взвела;"
[ "$(active late)" = true ] || miss="$miss запись трёхчасовой давности приняла реплику владельца за побудку;"
[ -z "$miss" ] && { echo "ход побудки узнан служебным, реплика владельца — поручением"; exit 0; }
echo "ход побудки судится речью владельца:$miss"
exit 1
