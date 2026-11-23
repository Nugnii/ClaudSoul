#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/root-cause-lib.sh
# probe_D484.sh — проба пункта D484: цепочка причин, переданная вызовом `: <<'CHAIN' … CHAIN`, засчитывается гейтом разбора.
#
# Предмет. С моделью Opus 5.5 промежуточная речь агента ложится в расшифровку не дословно, а
# пересказом в записи `thinking`: запись `text` есть лишь у 8–14% сообщений с вызовом инструмента
# (у Opus 5 — 53–82%; замер 3 октября 2026 по 11 расшифровкам проекта, деление по модели, а не по
# версии клиента). Гейт ищет цепочку в тексте хода и потому чаще всего её не видит — ожидание
# тут не помогает. Дословно расшифровка хранит ВХОД вызова инструмента, и канал речи для цепочки —
# вызов Bash `: <<'CHAIN' … CHAIN` (команда-пустышка, тело — сама цепочка).
# Проба: ход с находкой (повод отказа) и цепочкой, переданной этим вызовом, — пишущая команда
# обязана пройти. Положительный контроль: тот же ход БЕЗ цепочки — отказ, иначе «прошло» не значит
# ничего. Коды: 0 — канал засчитан; 1 — отказ при цепочке в канале; 2 — не исполнимо.
set -uo pipefail
HOOKS="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}/hooks"
[ -f "$HOOKS/five-whys-gate.sh" ] || { echo "НЕ ИСПОЛНЕНО: нет $HOOKS/five-whys-gate.sh"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "НЕ ИСПОЛНЕНО: нет jq"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

CHAIN='Проявления: hooks/x.sh:12 и hooks/y.sh:40.
Почему сломалось? Граница не доехала (hooks/x.sh:12).
Почему не доехала? Правили соседнюю ветку.
Почему только соседнюю? Чинили там, где заметили.
Корень: правка по месту замеченного.'
mk() {  # mk <файл> <цепочка в канале: 1|0>
    { jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"чини"}]}}'
      jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Оказалось, страж поймал мой же тест. Чиню."}]}}'
      if [ "$2" = 1 ]; then
          jq -nc --arg c ": <<'CHAIN'
$CHAIN
CHAIN" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"Bash",input:{command:$c}}]}}'
          jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:""}]}}'
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

mk "$T/without.jsonl" 0; mk "$T/with.jsonl" 1
D0=$(decision "$T/without.jsonl" p0)
[ "$D0" = deny ] || { echo "НЕ ИСПОЛНЕНО: контроль — без цепочки гейт обязан отказать, получено «${D0}»"; exit 2; }
D1=$(decision "$T/with.jsonl" p1)
if [ "$D1" = deny ]; then
    echo "FAIL [D484]: цепочка, переданная вызовом \`: <<'CHAIN'\`, гейтом не засчитана — правка отказана"
    exit 1
fi
echo "probe_D484: цепочка в канале вызова засчитана (без неё — отказ)"
exit 0
