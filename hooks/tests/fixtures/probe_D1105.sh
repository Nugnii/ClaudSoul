set -u
# СУДИТ: hooks/five-whys-gate.sh
# probe_D1105.sh — страж разбора не предупреждает: при живом поводе ЧТЕНИЕ проходит молча (отказу там не место —
#   без чтения разбор не из чего строить), а подсказка «Признак повторяется» на чтении — шум: 160 строк расшифровки
#   (88 доставок, 64 на чтении) одного текста за сессию 5da41b08, читались и не меняли действия (D1105, решение
#   владельца 26 октября 2026: «страж должен не предупреждать, а не давать без разбора двигаться дальше»). Повод при
#   этом записан в журнал `.seen` уже на чтении — запись его увидит. Контроль: та же находка на ЗАПИСИ — отказ, и через
#   Write, и через Bash (D1161: мутанты «отказ на чтении», «Bash-запись не судится», «чтение не пишет журнал» прежде
#   проходили пробу).
#   0 — чтение молчит и пишет журнал, записи отбиты; 1 — нет (названо); 2 — нет стража, jq или контроль Write не отказал.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
H="$PWD/hooks/five-whys-gate.sh"
[ -f "$H" ] && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
T="$W/t.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$T"
jq -cn --arg t "Побочно вылезла дыра в границе слова, чиню заодно." \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$T"
touch "$W/error_streak_fired_p1105"
# Читающий вызов — оболочкой (`grep`): инструмент Read страж не судит вовсе, а подсказка печаталась именно на читающих
# вызовах Bash, по одной на ход (замер 26 октября 2026: Read — тишина, Bash `grep` — «Признак повторяется», Write — отказ).
gate() { jq -cn --arg tool "$1" --arg f "$2" --arg c "$3" --arg p "$T" --arg d "$PWD" \
    '{session_id:"p1105", transcript_path:$p, hook_event_name:"PreToolUse", tool_name:$tool, cwd:$d, tool_input:{file_path:$f, content:"x", command:$c}}' \
    | STATE_DIR="$W" bash "$H" 2>/dev/null; }
OR=$(gate Bash "" "grep -n x hooks/x.sh")
# Журнал — до любой записи: запись пишет его сама, и после неё нога не отличила бы молчащее чтение.
grep -q '^live|turn:[0-9]*|streak:' "$W/five-whys-p1105.seen" 2>/dev/null; JR=$?
OW=$(gate Write "hooks/x.sh" "")
grep -q '"deny"' <<< "$OW" || { echo "контроль: запись при поводе не отказана"; exit 2; }
grep -q '"deny"' <<< "$OR" && { echo "чтение при поводе отбито"; exit 1; }
# Молчит — значит ничего не печатает (скептик D1161, L3: прежняя нога ловила одну фразу «Признак повторяется»).
[ -z "$OR" ] || { echo "чтение при поводе печатает: ${OR:0:80}"; exit 1; }
[ "$JR" -eq 0 ] || { echo "чтение при поводе не записало повод в журнал"; exit 1; }
grep -q '"deny"' <<< "$(gate Bash "" "echo x >> hooks/x.sh")" || { echo "Bash-запись при поводе не отбита"; exit 1; }
echo "чтение молчит и пишет журнал, записи Write и Bash отбиты"
exit 0
