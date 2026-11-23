#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/root-cause-lib.sh
# probe_D505.sh — проба пункта D505: находка, сказанная промежуточной речью в форме расшифровки Opus 5.5, становится поводом гейта разбора.
#
# Предмет. С моделью Opus 5.5 промежуточная речь агента ложится в расшифровку пересказом записи
# `thinking`, а не записью `text` (запись `text` — у 8–14% сообщений с вызовом инструмента, у Opus 5 —
# 53–82%; замер 3 октября 2026, пункт D484). Читатели речи хода видят только `text`, и находка
# «оказалось…», сказанная по ходу, поводом не становится. Представитель класса — признак находки
# `five-whys-gate` по последнему блоку речи (`rc_last_block`); перечень прочих читателей — в пункте.
# Проба: ход, где находка лежит ТОЛЬКО пересказом в `thinking`, и пишущая команда — гейт обязан
# назвать повод (отказ). Положительный контроль: та же находка записью `text` — отказ, иначе
# «молчит» значило бы «гейт сломан». Способ починки открыт (чтение пересказа, иной канал): проба
# судит ПОВЕДЕНИЕ — повод замечен. Коды: 0 — замечен; 1 — молчит; 2 — не исполнимо.
set -uo pipefail
HOOKS="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}/hooks"
[ -f "$HOOKS/five-whys-gate.sh" ] || { echo "НЕ ИСПОЛНЕНО: нет $HOOKS/five-whys-gate.sh"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "НЕ ИСПОЛНЕНО: нет jq"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FIND="Оказалось, страж поймал мой же тест. Чиню."
mk() {  # mk <файл> <text|thinking>
    { jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"чини"}]}}'
      if [ "$2" = text ]; then
          jq -nc --arg t "$FIND" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
      else
          jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"thinking",thinking:"",signature:"x"}]}}'
          jq -nc --arg t "$FIND" '{type:"assistant",message:{role:"assistant",content:[{type:"thinking",thinking:$t,signature:"x"}]}}'
      fi
    } > "$1"
}
decision() {  # decision <расшифровка> <sid> → permissionDecision гейта на пишущей команде
    # Без метки «полоса упавших команд»: она сама даёт право на отказ, и отказ перестал бы
    # различать предмет пробы (поймано на D505: проба зеленела на гейте, слепом к находке).
    mkdir -p "$T/st-$2"
    jq -cn --arg p "$1" --arg s "$2" \
        '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"cat > hooks/x.sh <<E\necho hi\nE"}}' \
      | STATE_DIR="$T/st-$2" bash "$HOOKS/five-whys-gate.sh" 2>/dev/null \
      | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null
}
mk "$T/text.jsonl" text; mk "$T/thinking.jsonl" thinking
D0=$(decision "$T/text.jsonl" q0)
[ "$D0" = deny ] || { echo "НЕ ИСПОЛНЕНО: контроль — находка записью text обязана дать отказ, получено «${D0}»"; exit 2; }
D1=$(decision "$T/thinking.jsonl" q1)
if [ "$D1" != deny ]; then
    echo "FAIL [D505]: находка, сказанная промежуточной речью (пересказ в thinking, форма Opus 5.5), поводом гейта не стала"
    exit 1
fi
echo "probe_D505: находка в промежуточной речи замечена"
exit 0
