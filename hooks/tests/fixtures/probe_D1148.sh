#!/usr/bin/env bash
# СУДИТ: scripts/signal-precision-corpus.py
# probe_D1148 — замер опознания класса судит ту же единицу, что свод на Stop (`rc_turn_text`, hooks/root-cause-lib.sh):
# ход режется по реплике владельца с текстом, а не по каждому результату инструмента, и текст хода — все записи агента
# в ходе, с thinking и телами `: <<'CHAIN'`. Три ноги:
#   1) «носителей 3 из 7», вызов инструмента, «тот же класс» — реестр в том же ходу ДО опознания; ход, разрезанный на
#      результате инструмента, и суд одного последнего блока дают одинаково 1 (второй круг, L2: прежний порядок давал
#      на «последнем блоке» 2, неотличимое от рамки);
#   2) «тот же класс» + реестр только в теле `: <<'CHAIN'` вызова Bash — свод его засчитывает, замер обязан тоже (M1);
#   3) сверка двойника: `turn_texts(speech=True)` на последнем ходе фикстуры = `rc_turn_text` той же расшифровки.
# Красная (1), пока замер расходится со сводом; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/signal-precision-corpus.py" ] && [ -f "$R/hooks/root-cause-lib.sh" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
u() { jq -cn --arg t "$1" --arg s "$2" '{type:"user",message:{role:"user",content:$t},timestamp:$s}'; }
tr_() { jq -cn --arg s "$1" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:"ok"}]},timestamp:$s}'; }
a() { jq -cn --argjson c "$1" --arg s "$2" '{type:"assistant",message:{role:"assistant",content:$c},timestamp:$s}'; }
ask() {   # ask <каталог корпуса> — код замера опознания класса с окном 1
    CORPUS_DIR="$1" python3 "$R/scripts/signal-precision-corpus.py" --class-recognition --window 1 >/dev/null 2>&1
    echo $?
}
chain=": <<'CHAIN'
реестр: носителей 3 из 7
CHAIN"
mkdir -p "$T/c1/p" "$T/c2/p" || exit 2
{
    u 'проверь' 2026-10-27T10:00:00Z
    a '[{"type":"text","text":"Носителей 3 из 7."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]' 2026-10-27T10:00:01Z
    tr_ 2026-10-27T10:00:02Z
    a '[{"type":"text","text":"Это тот же класс."}]' 2026-10-27T10:00:03Z
    u 'дальше' 2026-10-27T10:01:00Z
} > "$T/c1/p/s.jsonl"
{
    u 'проверь' 2026-10-27T10:00:00Z
    a "$(jq -cn --arg c "$chain" '[{type:"text",text:"Это тот же класс."},{type:"tool_use",id:"t1",name:"Bash",input:{command:$c}}]')" 2026-10-27T10:00:01Z
    tr_ 2026-10-27T10:00:02Z
    a '[{"type":"thinking","thinking":""},{"type":"thinking","thinking":"мысль"},{"type":"text","text":"Чиню."}]' 2026-10-27T10:00:03Z
    a '"S"' 2026-10-27T10:00:04Z
} > "$T/c2/p/s.jsonl"
r1=$(ask "$T/c1"); r2=$(ask "$T/c2")
case "$r1:$r2" in
    0:0) ;;
    1:*) echo "реестр, названный в том же ходу до вызова инструмента, не засчитан: ход разрезан или судится последний блок"; exit 1 ;;
    *:1) echo "реестр в теле CHAIN не засчитан: замер не видит того, что видит свод"; exit 1 ;;
    *) echo "замер не ответил (коды $r1, $r2)"; exit 2 ;;
esac
mech=$(STATE_DIR="$T/st" bash -c '. "$1/hooks/root-cause-lib.sh" 2>/dev/null; rc_turn_text "$2"' _ "$R" "$T/c2/p/s.jsonl")
twin=$(python3 - "$R/scripts/signal-precision-corpus.py" "$T/c2/p/s.jsonl" <<'PY' 2>/dev/null
import importlib.util, sys
spec = importlib.util.spec_from_file_location('spc', sys.argv[1]); m = importlib.util.module_from_spec(spec)
f = sys.argv[2]; sys.argv = [sys.argv[0]]; spec.loader.exec_module(m)
print([t for _f, t in m.turn_texts(files=[f], speech=True)][-1])
PY
)
[ -n "$mech" ] || { echo "свод не отдал текст хода — рамка"; exit 2; }
[ "$mech" = "$twin" ] || { echo "двойник разошёлся со сводом: свод «${mech}», замер «${twin}»"; exit 1; }
# Отказ владельца тел CHAIN — «не измерено» (2), а не приговор «реестр не назван» (1): «Проверка» D408 читает только код.
r3=$(RC_LIB=/nonexistent/root-cause-lib.sh ask "$T/c2")
[ "$r3" = 2 ] || { echo "без библиотеки свода замер ответил кодом $r3, а не 2"; exit 1; }
echo "замер судит ту же единицу, что свод"
