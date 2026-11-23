#!/usr/bin/env bash
set -u
# СУДИТ: hooks/five-whys-gate.sh
# probe_D1151.sh — страж разбора на ЗАПИСИ без права на отказ молчит (D1151, решение владельца 26 октября 2026 «не
#   предупреждать, а не давать без разбора двигаться дальше»; «отказ или тишина» решён замером в пользу тишины). Пути к
#   прежней подсказке — суды, каждый в своём каталоге состояния (событие лежит в общем `pending-events.jsonl` и иначе
#   протекает в соседние случаи): (A) только стоячие виды (`FWG_STANDING`); (B) виды с правом на отказ под цепочкой,
#   зачтённой раньше (`chain-ok|`); (C) субагент со своими поводами; (D) поздний ход сессии — журнал уже несёт строку
#   прошлого хода. B и C «все виды» судятся на позднем ходе (в живых журналах так идут 1130 строк `carried|` из 1200 и
#   521 строка субагента из 523, скептик D1206), прочие случаи — на первом.
#   ВИДЫ берутся у стража (D1206): перечень — `RC_KINDS_RE` библиотеки разбора, стоячие — умолчание `FWG_STANDING`
#   стража; у каждого вида построитель состояния в `mk_case`, и вид стража без построителя даёт 2 — новый вид мимо пробы
#   молча не пройдёт. Метки видов для зачтённой цепочки снимаются с журнала стража непишущим вызовом, а не пересчитываются:
#   у `discovery` метка — отпечаток текста хода, у `repeat` и `notfollowed` — имена знаний.
#   На каждом пути — каждый вид по одному и случай «все виды» (мутант, привязанный к НАЛИЧИЮ любого вида на пути, ловится
#   одним вызовом). «Все виды» — покрытие, а не живое состояние: в 29 живых ходах с подсказкой (D1151 круг 4) виды шли
#   разными наборами — `rework` 29, `event` 21, `correction` 11, `notfollowed` 7, `repeat` 5, `discovery` 1.
#   Тишина — выход 0 и пустой stdout на КАЖДОМ вызове: ни подсказки любым ключом, ни отказа, ни выхода 2 (в PreToolUse это
#   блокирующий канал stderr); первый же голос — выход 1 сразу. Тишина судится в паре с журналом: строка `turn:…` с видами
#   повода обязана лечь — иначе «молчит» неотличимо от «повода не увидел»; контроль — серия форм записи при полосе у
#   родителя даёт отказ на каждой форме, иначе тишина на форме неотличима от «не признана записью». Страж зовётся без
#   `FWG_STANDING` вызывающего: унаследованный перечень менял бы, что страж считает стоячим.
#   0 — на всех путях тихо, поводы увидены; 1 — что-то напечатано или выход не 0; 2 — нет стража/jq, контроль не прошёл,
#   журнал повода не принял либо у вида стража нет построителя.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
H="$PWD/hooks/five-whys-gate.sh"; L="$PWD/hooks/root-cause-lib.sh"
[ -f "$H" ] && [ -f "$L" ] && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
KL=$(env -u RC_KINDS_RE bash -c '. "$1" >/dev/null 2>&1; printf "%s" "${RC_KINDS_RE:-}"' _ "$L" | tr '|' '\n' | sed 's/:$//' | grep .)
ST=$(sed -n 's/^FWG_STANDING="\${FWG_STANDING:-\([^}]*\)}".*$/\1/p' "$H")
# Умолчание стража указывает на владельца перечня (D1256: `RC_STANDING_KINDS` в root-cause-lib) — читаем у него.
case "$ST" in '$RC_STANDING_KINDS') ST=$(bash -c '. "$1" >/dev/null 2>&1 && printf "%s" "${RC_STANDING_KINDS:-}"' _ \
    "$(dirname "$H")/root-cause-lib.sh") ;; esac
[ -n "$KL" ] && [ -n "$ST" ] || { echo "рамка: перечень видов либо стоячих у стража не прочитан"; exit 2; }
STAND=""; DENY=""
for k in $KL; do case " $ST " in *" $k "*) STAND="$STAND $k" ;; *) DENY="$DENY $k" ;; esac; done
DENY_RE=$(printf '%s' "${DENY# }" | tr ' ' '|')
tr_of() {  # tr_of <файл> <текст ответа>
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' >> "$1"
    jq -cn --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"; }
SRT="Это третий раз за день, когда тест падает на той же строке. Чиню."   # повтор в речи (`self_repeat`)
DST="Оказалось, кэш устарел. Чиню."                                       # находка по ходу (`discovery`)
Q='{"q":"почему падает?"}'
B='{"date":"2026-10-31T00:00:00Z","snippet":"всё сломалось","hash":"1151"}'
C='{"q":"не так"}'
# Событие — строкой с пустым проектом: такое подходит любому проекту (`rc_open_events`), и рамка не зависит от того, git ли
# дерево (`rc_note_event` пишет ключ проекта по рабочему каталогу — в копии без git он не совпадал со стражевым).
EV='{"ts":"2026-10-31T00:00:00Z","kind":"ci-red","detail":"прогон 1151: failure","project":"","status":"open"}'
outcome() {  # outcome <случай> <исход> <знание> — два исхода одного знания за сессию (`repeat` / `notfollowed`)
    local i; for i in 1 2; do
        jq -cn --arg s "$1" --arg o "$2" --arg k "$3" '{ts:"2026-10-31T00:00:00Z", session:$s, knowledge:$k, outcome:$o}'
    done >> "$W/$1/disagreement-outcomes.jsonl"; }
mk_case() {  # mk_case <случай> <agent_id|""> <вид>… — каталог, расшифровка и состояние, дающее эти виды
    local c=$1 a=$2 sfx="" txt="" k; shift 2
    [ -n "$a" ] && sfx=".agent-$a"
    mkdir -p "$W/$c" || exit 2
    for k; do case "$k" in self_repeat) txt="$txt $SRT" ;; discovery) txt="$txt $DST" ;; esac; done
    txt="${txt# }"; [ -n "$txt" ] || txt="Правлю строку."
    tr_of "$W/$c/t.jsonl" "$txt"
    [ -z "$a" ] || { mkdir -p "$W/$c/$c/subagents" && tr_of "$W/$c/$c/subagents/agent-$a.jsonl" "$txt"; }
    for k; do
        case "$k" in
            question)    printf '%s\n' "$Q" > "$W/$c/question-open-$c$sfx.jsonl" ;;
            breakage)    printf '%s\n' "$B" > "$W/$c/breakage-fired-$c$sfx.jsonl" ;;
            event)       printf '%s\n' "$EV" > "$W/$c/pending-events.jsonl" ;;
            streak)      printf '2' > "$W/$c/error_streak_fired_$c$sfx" ;;
            correction)  printf '%s\n' "$C" > "$W/$c/correction-fired-$c$sfx.jsonl" ;;
            rework)      printf '{"path":"/x/a.sh","cycles":2}\n' > "$W/$c/rework-fired-$c$sfx.jsonl" ;;
            repeat)      outcome "$c" confirmed_knowledge pattern-p1206-repeat ;;
            notfollowed) outcome "$c" applicable_not_followed pattern-p1206-notfollowed ;;
            self_repeat|discovery) ;;
            *) echo "рамка: у вида стража «${k}» нет построителя в пробе"; exit 2 ;;
        esac
    done; }
# Формы записи — те, что страж признаёт записью: файловые инструменты (путь и относительный, и абсолютный — так шлёт каждый
# живой Write; документ поведения `rules/*.md` — запись, прочий `.md` — запись документа, D1036) и Bash по `is_write_command`
# (`hooks/command-scope-lib.sh`, D1160). `Write` дважды — повторный отказ контроля дедуп не гасит.
SERIES="Write Write Edit MultiEdit WriteAbs WriteRule Bash BashTee Append SedI PyWrite Commit"
call() {  # call <случай> <форма> [agent_id] — вызов в ходе случая; печатает stdout стража и строку `rc=<выход>`
    local t=Write cmd="" fp="hooks/x.sh"
    case "$2" in
        Read)      t=Bash; cmd='cat hooks/x.sh' ;;   # непишущий вызов: строка журнала ложится, отказа нет
        Bash)      t=Bash; cmd='echo x > hooks/x.sh' ;;
        BashTee)   t=Bash; cmd='printf x | tee hooks/x.sh' ;;
        Append)    t=Bash; cmd='printf x >> hooks/x.sh' ;;
        SedI)      t=Bash; cmd="sed -i '' s/a/b/ hooks/x.sh" ;;
        PyWrite)   t=Bash; cmd="python3 -c \"open('hooks/x.sh','w').write('x')\"" ;;
        Commit)    t=Bash; cmd='git commit -qm x' ;;
        Edit)      t=Edit ;;
        MultiEdit) t=MultiEdit ;;
        WriteAbs)  fp="$PWD/hooks/x.sh" ;;
        WriteRule) fp="rules/x.md" ;;
    esac
    jq -cn --arg s "$1" --arg a "${3:-}" --arg p "$W/$1/t.jsonl" --arg d "$PWD" --arg t "$t" --arg cmd "$cmd" --arg fp "$fp" \
        '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:$t, cwd:$d,
          tool_input:(if $t == "Bash" then {command:$cmd}
                      elif $t == "Edit" then {file_path:$fp, old_string:"a", new_string:"b"}
                      elif $t == "MultiEdit" then {file_path:$fp, edits:[{old_string:"a", new_string:"b"}]}
                      else {file_path:$fp, content:"x"} end)}
         + (if $a == "" then {} else {agent_id:$a, agent_type:"lean"} end)' \
        | env -u FWG_STANDING STATE_DIR="$W/$1" bash "$H" 2>/dev/null
    echo "rc=$?"; }
# ponytail: полная серия — у контроля и у B и C «все виды», прочие случаи — один `Write` (58 вызовов стража, около 18 с).
#   Предел: мутант, привязанный к ТОЧНОМУ составу видов (пара) либо к форме записи вне B и C «все виды» (Bash у родителя при
#   одних стоячих видах), пройдёт; форма, которую
#   владелец признака записи научится видеть, в серию сама не попадёт — перечня форм у `is_write_command` нет (разбор, а не
#   список), рост — серия у всех случаев и форма-перечень у владельца.
judge() {  # judge <случай> <имя> <agent_id|""> <вид>… — каждый вызов молчит, строка журнала несёт каждый вид
    local c=$1 n=$2 a=$3 t o ser=Write l k; shift 3
    case "$c" in ba|ca) ser=$SERIES ;; esac
    for t in $ser; do
        o=$(call "$c" "$t" "$a")
        [ "$o" = "rc=0" ] || { echo "$n, $t: запись не молчит: ${o:0:120}"; exit 1; }
    done
    l=$(grep '^turn:' "$W/$c/five-whys-$c.seen" 2>/dev/null) || { echo "$n: строки повода в журнале нет"; exit 2; }
    [ -z "$a" ] || l=$(grep -F -- "|actor:.agent-$a|" <<< "$l") || { echo "$n: повод не приписан субагенту"; exit 2; }
    l=$(tail -1 <<< "$l")   # строка ЭТОГО хода: строка прошлого хода не покрывает слепоту позднего
    for k; do l=$(grep -F -- "|$k:" <<< "$l") || { echo "$n: вид $k журналом не принят"; exit 2; }; done; }
chain_from_journal() {  # chain_from_journal <случай> — метки видов с правом на отказ зачтены цепочкой раньше в сессии
    local c=$1 toks
    call "$c" Read >/dev/null
    toks=$(grep '^turn:' "$W/$c/five-whys-$c.seen" 2>/dev/null | tail -1 | tr '|' '\n' | grep -E "^($DENY_RE):")
    [ -n "$toks" ] || { echo "рамка: непишущий вызов случая $c не дал меток видов с правом на отказ"; exit 2; }
    printf 'chain-ok|%s|\n' "$(printf '%s\n' "$toks" | paste -sd'|' -)" >> "$W/$c/five-whys-$c.seen"; }
next_turn() {  # next_turn <расшифровка> — реплика владельца и тот же ответ (метки видов те же, ход новый)
    local last; last=$(tail -1 "$1")
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"дальше"}]}}\n' >> "$1"
    printf '%s\n' "$last" >> "$1"; }
carried() { grep -q '^carried|' "$W/$1/five-whys-$1.seen" || { echo "B: память цепочки не сработала ($1)"; exit 2; }; }

# Порядок — от случаев, где голос мутанта звучит раньше всего (B и C «все виды», поздний ход), к одиночным; контроль —
# последним: голос стража судится без него, а тишину он делает различимой и в конце (прогон над мутантами, D1206, иначе
# платил бы 12 вызовов контроля прежде сути).
# (B) виды с правом покрыты цепочкой, зачтённой раньше в сессии: ни подсказки, ни отказа; снятый отказ — строка `carried|`.
mk_case ba "" $KL; chain_from_journal ba; next_turn "$W/ba/t.jsonl"
judge ba "B: все виды под зачтённой цепочкой" "" $KL; carried ba
# (C) субагент со своими поводами: права на отказ у него нет (решение 10 сентября 2026).
mk_case ca d1151 $KL; call ca Read d1151 >/dev/null; next_turn "$W/ca/ca/subagents/agent-d1151.jsonl"
judge ca "C: субагент, все виды" d1151 $KL
# (D) поздний ход: новая реплика и ответ в той же сессии, журнал уже несёт строку первого хода.
mk_case lt "" event
judge lt "D: первый ход" "" event
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"дальше"}]}}\n' >> "$W/lt/t.jsonl"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Правлю дальше."}]}}' >> "$W/lt/t.jsonl"
judge lt "D: поздний ход" "" event
[ "$(grep -c '^turn:' "$W/lt/five-whys-lt.seen")" -ge 2 ] || { echo "рамка: поздний ход не лёг своей строкой журнала"; exit 2; }
# (A) каждый стоячий вид по отдельности и все сразу; (B) и (C) — по одному виду.
for k in $STAND; do mk_case "a_$k" "" "$k"; judge "a_$k" "A: $k" "" "$k"; done
mk_case aa "" $STAND
judge aa "A: все стоячие" "" $STAND
for k in $DENY; do mk_case "b_$k" "" "$k"; chain_from_journal "b_$k"; judge "b_$k" "B: зачтённый $k" "" "$k"; carried "b_$k"; done
mk_case sa d1151 streak
judge sa "C: субагент, полоса" d1151 streak
# Контроль: вид с правом на отказ у родителя — отказ на каждой форме серии.
mk_case ctl "" streak
for t in $SERIES; do
    grep -q '"deny"' <<< "$(call ctl "$t")" || { echo "контроль, $t: запись при полосе провалов не отказана"; exit 2; }
done
echo "запись без права на отказ — тишина на всех путях, видах стража и формах серии, поводы в журнале"
exit 0
