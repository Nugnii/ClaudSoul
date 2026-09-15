#!/usr/bin/env bash
# tool-gate-check.sh — PostToolUse: вызов инструмента без гейта и печать отказа на Stop.
# Подробно: ссылка на инструмент по корню сессии вне проверки существования; печать
# additionalContext на Stop из ветки отказа при непрочитанном stop_hook_active.
# en: PostToolUse on hook writes — unguarded project-tool calls and brakeless Stop turn-restarts.
#
# Результат: в hooks/*.sh нет ни одного вызова инструмента по корню сессии без проверки
#            существования и ни одной печати additionalContext на Stop из ветки отказа
#            при непрочитанном stop_hook_active
# Проверка результата: bash hooks/tool-gate-check.sh --check даёт 0
#
# Зачем отдельным файлом. Оба признака судят ФАЙЛ ЦЕЛИКОМ, а не строку: гейт для `$REFRESH`
# стоит на backlog-reading-refresh.sh:102, ссылка — на :101; тормоз stop_hook_active стоит на
# :50 при печати на :126. Признак, встроенный в раннер или в соседний хук, получил бы на вход
# фрагмент правки и дал бы ложную тревогу по построению; подменить ему вход было бы нечем.
# Отдельный файл с режимом --check — единственная форма, которой тест умеет подсунуть мутанта.
#
# Почему в hooks/, а не в hooks/tests/. install.sh копирует только hooks/*.sh и hooks/lib/*;
# hooks/tests/ не устанавливается ничем, ~/.claude/scripts не существует, а все регистрации
# имеют вид `bash ~/.claude/hooks/<имя>.sh`. Прибор из hooks/tests/ был бы зарегистрирован на
# несуществующий путь — ровно тот дефект, который он ловит. Тонкая обёртка тоже негодна: её
# универсум — `$ПЕРЕМЕННАЯ/(scripts|bin|tools)/…`, и hooks/tests/ в него не входит, то есть
# прибор не судил бы собственного вызывающего. Здесь он не зовёт внешних инструментов вовсе.
#
# Почему PostToolUse, а не PreToolUse. На PreToolUse в payload лежит ФРАГМЕНТ правки
# (tool_input.new_string), а оба признака файловые: фрагмент со строкой :77 без строки :78
# дал бы ложный NOGATE гарантированно. Судить файл на диске в PreToolUse значит судить
# состояние ДО правки, то есть докладывать с опозданием на одну правку. Тот же размен уже
# решён и записан у соседа: hooks/undefined-function-check.sh:25-29.
#
# Повод, замер 7 сентября 2026. carrier-growth-check.sh в чужом проекте (ProjectA) звал
# отсутствующий scripts/defect-class-carriers.py, получал код 2 и печатал additionalContext
# на событии Stop. Непустой additionalContext на Stop ПЕРЕЗАПУСКАЕТ ход, а «прибора в этом
# дереве нет» — состояние ПОСТОЯННОЕ: восемь пустых ходов подряд, остановлено владельцем
# вручную. Два признака — две половины этой цепи, и каждая ловится отдельно: без первой не
# было бы отказа, без второй отказ был бы тихим.
#
# ВЫВЕДЕННОЕ ПРАВИЛО: состояние, которое не меняется само, не имеет права печататься на
# каждом ходу. Первая половина: чужое дерево без инструмента постоянно, и вызов без гейта
# делает из постоянного состояния вечный отказ. Вторая: отказ, ушедший через
# additionalContext на Stop, перезапускает ход и потому печатается снова.
#
# ПРИЗНАК 1 — NOGATE.
#   Правило: файл ССЫЛАЕТСЯ на путь вида `$ПЕРЕМЕННАЯ/(scripts|bin|tools)/<инструмент>` вне
#   проверки существования, и НИГДЕ в этом файле нет проверки, называющей этот инструмент —
#   ни по литеральному пути, ни через переменную, в которую путь положен.
#   Класс переменной НЕ перечисляется по именам: перечень ROOT|CWD|REPO был бы вторым местом,
#   где живёт знание о корнях, и промахнулся бы мимо $CLAUDSOUL_ROOT, $_rr_root,
#   ${DEP_INDEX_TOOL:-$ROOT/...}. Различает не имя, а ФОРМА: каталог инструментов под
#   переменным корнем. Соседи-хуки адресуются иначе — $(dirname "${BASH_SOURCE[0]}") или
#   $HOME/.claude/hooks/ — и в универсум не попадают.
#   КОНТРПРИМЕР (признак обязан НЕ поймать): hooks/ci-check-reminder.sh:43 — единственная
#   ссылка на $ROOT/scripts/ci-status.sh стоит внутри `[ -f ... ] || exit 0`. Второй, с
#   гейтом через переменную: hooks/doc-impact-check.sh:56 (INDEXER=) при гейте на :57.
#   ТОЧНОСТЬ, измеренная прогоном по обоим деревьям 7 сентября 2026 (BSD awk 20200816):
#   универсум 14 пар «файл + инструмент» в репозитории, совпадений 0, ложных 0. На
#   исторической редакции `git show <до правки>:hooks/carrier-growth-check.sh` — 1 совпадение,
#   настоящее. Итого 1 из 1 настоящих при 14 отрицательных.
#
# ПРИЗНАК 2 — STOPLOOP.
#   Правило: хук, зарегистрированный на Stop в живом settings.json, печатает
#   additionalContext при ЛИТЕРАЛЬНОМ `hookEventName: "Stop"`, ближайшее объемлющее условие
#   (по отступу) несёт примету отказа, и слово stop_hook_active в файле не встречается ни разу.
#   КОНТРПРИМЕР (признак обязан НЕ поймать): hooks/install-drift-notice.sh — ветка `*)` разбора
#   кода возврата есть чистый отказ, но канал очередь/systemMessage: ход не перезапускается.
#   Второй: hooks/carrier-growth-check.sh — печать additionalContext на Stop без тормоза, но
#   НЕ из ветки отказа, и состояние самоустраняется снимком. Третий:
#   hooks/accepted-alternative-gap.sh:126 — та же печать при тормозе на :50-51.
#   ТОЧНОСТЬ, измеренная тем же прогоном: универсум 10 Stop-хуков; на исторической редакции
#   1 совпадение, настоящее; в живом дереве после починки 0. Ложных 0.
#
# ЧТО КАЖДАЯ СТРОКА УТВЕРЖДАЕТ И ЧЕГО НЕ УТВЕРЖДАЕТ (род L: область механизма шире предмета).
#   NOGATE утверждает: в этом файле путь к инструменту назван на строке N вне проверки, и во
#   всём файле нет проверки, называющей этот инструмент или держащую его переменную. НЕ
#   утверждает: что вызов исполнится без гейта на всяком пути управления (гейт может стоять в
#   источаемой библиотеке), и что инструмента в дереве нет.
#   STOPLOOP утверждает: файл зарегистрирован на Stop в ПРОЧИТАННОМ settings.json; строка N
#   печатает additionalContext при литеральном Stop; ближайшее объемлющее условие несёт примету
#   отказа; тормоза в файле нет. НЕ утверждает: что состояние в самом деле не самоустраняется,
#   и что цикл наступит.
#   OK утверждает только «совпадений не найдено на названном знаменателе». Дерево без
#   перезапусков хода он не обещает.
#
# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ВСТРОЕН И БЕЖИТ КАЖДЫЙ РАЗ. Прибор, не поймавший ни одного носителя,
# неотличим от сломанного, а исторический носитель уже починен и в живом дереве его нет.
# Поэтому перед разбором дерева обе программы прогоняются по вшитым канарейкам: по одной,
# которую они ОБЯЗАНЫ поймать, и по трём, которые обязаны пропустить. Канарейка не сработала —
# исход BROKEN, а не OK. Фикстур на диске нет намеренно: файл-фикстура есть второй экземпляр
# правила, способный разойтись с прибором молча.
#
# НАЗВАННЫЕ ПРЕДЕЛЫ (у каждого — условие снятия).
#   1. Путь, собранный в другом месте (`T="$ROOT"; "$T/scripts/x"`), и косвенный вызов через
#      eval не видны. Снятие: прослеживание присваиваний внутри файла; таких мест сегодня 0.
#   2. Упоминание пути в ТЕКСТЕ сообщения неотличимо от вызова. Замер: 0 таких в обоих
#      деревьях. Снятие: разбор строки на слова с учётом кавычек.
#   3. Каталог инструментов ограничен scripts|bin|tools. Снятие: когда заведут другой.
#   4. Регистрация Stop НЕ в ~/.claude/settings.json (проектная, enterprise) вне универсума.
#      Снятие: слияние всех уровней настроек тем же порядком, каким их сливает харнесс.
#   5. Печать additionalContext с событием в ПЕРЕМЕННОЙ не судится вовсе: сегодня таких 3, и
#      у всех трёх Stop уходит в scan_and_persist, то есть не в печать (проверено глазом, не
#      механизмом). Число несудимых печатается всегда, чтобы дыра была видна.
#      Снятие: разбор диспетчера `case "$EVENT"`.
#   6. Ближайшее объемлющее условие ищется ПО ОТСТУПУ — соглашение, а не синтаксис.
#   7. Правка хука ЧЕРЕЗ Bash (heredoc в файл) события Write/Edit/MultiEdit не даёт и прибором
#      не увидена. Снятие: отметка прохода + `find -newer`, как у undefined-function-check.sh.
#   8. hooks/lib/* не осматривается. Замер: 0 ссылок на инструмент по корню там сегодня.
#   9. ВНЕ ClaudSoul прибор МОЛЧИТ: правка не в каталоге `hooks` отсекается первой проверкой,
#      а отсутствие settings.json в хук-режиме читается как «другой мир». Это названный
#      предел, а не свойство: в чужом проекте эти два дефекта не ловит никто.
#
# ПОЧЕМУ ОТСУТСТВИЕ settings.json В ХУК-РЕЖИМЕ — ТИШИНА, А В --check — BROKEN. Это тот же
# дефект, что прибор ловит: «настроек нет» — состояние ПОСТОЯННОЕ, и доклад о нём на каждой
# правке хука стал бы вечным фоном. В режиме --check возвращаемый код существует и обязан
# кричать; в хук-режиме кода нет, а есть только канал, который нельзя засорять постоянным.
#
# Формат вывода (--check), по строке на признак, поля разделены вертикальной чертой:
#   СТАТУС|метка|сколько_сравнено|сколько_разошлось|подробности
#   OK      — сравнили хотя бы одну единицу, носителей нет
#   NOGATE  — носители признака 1; подробности: ` <файл>:<строка> <инструмент>`
#   STOPLOOP— носители признака 2; подробности: ` <файл>:<строка печати>(cond:<строка условия>)`
#   ABSENT  — единиц для суждения в дереве нет вовсе; вопрос не стоит
#   BROKEN  — прибор не смог судить (нет файлов, нет jq/settings.json, канарейка не сработала)
# Пять полей и статус первым — как у hooks/tests/drift-check.sh: один разбор на оба прибора.
#
# Код возврата: 0 — всё OK/ABSENT, 1 — есть носители, 2 — BROKEN либо неизвестный аргумент.
#
# Input  (stdin, хук-режим): {tool_name, tool_input} (PostToolUse JSON)
# Output (stdout, хук-режим): {hookSpecificOutput:{hookEventName, additionalContext}} либо пусто
# Exit:  хук-режим — всегда 0; режим --check — 0/1/2.

set -uo pipefail

# Режим решает АРГУМЕНТ, а не догадка про stdin: эвристика «есть ли tty» вешает прогон насмерть.
MODE=hook
case "${1:-}" in
    "")       MODE=hook ;;
    --check)  MODE=check ;;
    *)        printf 'tool-gate-check: неизвестный аргумент: %s (ожидается --check либо ничего)\n' "$1" >&2
              exit 2 ;;
esac

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

# Программы ЧИСТО ASCII: русские слова живут в оболочке, а awk-программа — это синтаксис
# (pattern-shell-portability). Ни одного расширения GNU: ни ENDFILE, ни gensub().
NG_AWK='
{ if (FNR==1) { nf++; files[nf]=FILENAME }
  L=$0
  if (L ~ /^[ \t]*#/) next
  isgate = (L ~ /(\[|\[\[|test)[ \t]+!?[ \t]*-[fxrsed][ \t]/) || (L ~ /command[ \t]+-v/)
  if (isgate) { ngl[FILENAME]++; gl[FILENAME, ngl[FILENAME]]=L }
  hit=0
  if (match(L, /\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\/(scripts|bin|tools)\/[A-Za-z0-9._-]+/)) { s=substr(L,RSTART,RLENGTH); hit=1 }
  if (!hit) next
  n=split(s, P, "/"); t=P[n]
  if (!((FILENAME,t) in seen)) { seen[FILENAME,t]=1; nt[FILENAME]++; tl[FILENAME, nt[FILENAME]]=t; firstref[FILENAME,t]=FNR }
  if (isgate) { gated[FILENAME,t]=1; next }
  if (!((FILENAME,t) in useln)) useln[FILENAME,t]=FNR
  if (match(L, /^[ \t]*(local[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=/)) {
      a=substr(L,RSTART,RLENGTH); sub(/^[ \t]*/,"",a); sub(/^local[ \t]+/,"",a); sub(/=$/,"",a)
      nh[FILENAME]++; hv[FILENAME,nh[FILENAME]]=a; ht[FILENAME,nh[FILENAME]]=t }
}
END { for (k=1;k<=nf;k++) { f=files[k]
    for (j=1;j<=nh[f];j++) { h=hv[f,j]
      for (i=1;i<=ngl[f];i++) if (gl[f,i] ~ ("[$][{]?" h "[^A-Za-z0-9_]")) gated[f, ht[f,j]]=1 }
    for (i=1;i<=nt[f];i++) { t=tl[f,i]; U++
      if (!((f,t) in gated)) { C++; ln=((f,t) in useln)?useln[f,t]:firstref[f,t]; D=D " " f ":" ln " " t } } }
  print nf+0 "|" U+0 "|" C+0 "|" D }
'

SL_AWK='
function ind(s,  i,c,n) { n=0; for(i=1;i<=length(s);i++){ c=substr(s,i,1); if(c==" ")n++; else if(c=="\t")n+=8; else break } return n }
{ if (FNR==1) { nf++; files[nf]=FILENAME; last[FILENAME]=0 }
  raw[FILENAME,FNR]=$0; ip[FILENAME,FNR]=ind($0); cm[FILENAME,FNR]=($0 ~ /^[ \t]*#/); last[FILENAME]=FNR
  if (!cm[FILENAME,FNR] && $0 ~ /stop_hook_active/) brake[FILENAME]=1 }
END { for (k=1;k<=nf;k++) { f=files[k]
  for (i=1;i<=last[f];i++) {
   if (cm[f,i] || raw[f,i] !~ /additionalContext/) continue
   ev=""
   for (j=i;j>=i-3 && j>=1;j--) { if (cm[f,j]) continue; if (raw[f,j] ~ /hookEventName/) { ev=raw[f,j]; break } }
   if (ev=="" || ev ~ /hookEventName[^,}]*\$/) { NU++; continue }
   if (ev !~ /hookEventName[^,}]*"Stop"/) continue
   NJ++; if (f in brake) continue
   cond=""; cl=0
   for (j=i-1;j>=1;j--) { if (cm[f,j]) continue
     if (ip[f,j] < ip[f,i]) { t=raw[f,j]; sub(/^[ \t]+/,"",t); if (t ~ /^(if|elif)[ \t]/) { cond=t; cl=j } break } }
   if (cond=="") continue
   if (cond ~ /-gt[ \t]+[0-9]|-ne[ \t]+[0-9]|-ge[ \t]+[0-9]|\$\?|-z[ \t]+"|\[[ \t]+!|![ \t]+command|!=[ \t]*"?0/) {
       C++; D=D " " f ":" i "(cond:" cl ")" } } }
 print nf+0 "|" C+0 "|" NJ+0 "|" NU+0 "|" D }
'

# ВЕРДИКТ ПО РОДУ B (реестр назвал этот файл носителем 7 сентября 2026, «подстановок=5»).
# Все пять подстановок живут в канарейках ниже и ведут в ветку ОТКАЗА: пустое значение даёт
# 0 либо 1, сравнение не сходится, канарейка НЕ проходит, и исход — BROKEN. Это названный
# ЛОЖНЫЙ класс сужения рода B («подстановка ведёт в ветку отказа: последствие обратное роду»).
# Носителем файл не является, и обход этого признака здесь не нужен.
# Разбор ВЫВОДА awk — другое дело, и он починен: пустое поле там даёт BROKEN, а не ноль,
# потому что ноль вёл бы в ABSENT и OK. Канарейка ловит слепоту признака, а не порчу вывода.
_ng_canary() {
    _cp=$( { printf 'X="$ROOT/scripts/nope.py"\n'; printf 'python3 "$X"\n'; } | awk "$NG_AWK" | cut -d'|' -f3 )
    _cn=$( { printf 'X="$ROOT/scripts/nope.py"\n'; printf '[ -f "$X" ] || exit 0\n'; printf 'python3 "$X"\n'; } | awk "$NG_AWK" | cut -d'|' -f3 )
    [ "${_cp:-0}" = "1" ] && [ "${_cn:-1}" = "0" ]
}
# ФОРМА КАНАРЕЙКИ ВЗЯТА ИЗ ДЕРЕВА, А НЕ ИЗ ГОЛОВЫ. Первая редакция подставляла jq-форму с
# ЭКРАНИРОВАННЫМИ кавычками, а подстроки Stop в кавычках в такой строке нет вовсе — признак
# был исправен, лжива была фикстура, и прибор честно доложил BROKEN вместо OK. В дереве живут
# две формы, обе с настоящими кавычками: printf (carrier-growth-check.sh:200) и jq
# (timestamp-canary-check.sh:154). Берём первую — ровно ту, что была у исторического носителя.
_SL_EMIT='  printf '\''{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":%s}}'\'' "$m"'
_sl_canary() {
    _p=$( { printf 'RC=2\n'; printf 'if [ "$RC" -gt 1 ]; then\n'; printf '%s\n' "$_SL_EMIT"; printf 'fi\n'; } | awk "$SL_AWK" | cut -d'|' -f2 )
    _n1=$( { printf 'S=$(jq -r .stop_hook_active)\n'; printf 'if [ "$RC" -gt 1 ]; then\n'; printf '%s\n' "$_SL_EMIT"; printf 'fi\n'; } | awk "$SL_AWK" | cut -d'|' -f2 )
    _n2=$( { printf 'if [ -n "$NEW" ]; then\n'; printf '%s\n' "$_SL_EMIT"; printf 'fi\n'; } | awk "$SL_AWK" | cut -d'|' -f2 )
    _n3=$( { printf 'if [ "$RC" -gt 1 ]; then\n'; printf '  jq -cn "{hookSpecificOutput: {hookEventName: $ev, additionalContext: $m}}"\n'; printf 'fi\n'; } | awk "$SL_AWK" | cut -d'|' -f2 )
    [ "${_p:-0}" = "1" ] && [ "${_n1:-1}" = "0" ] && [ "${_n2:-1}" = "0" ] && [ "${_n3:-1}" = "0" ]
}

_broken=0; _found=0; _rows=""
_emit() {
    _rows="$_rows$1|$2|$3|$4|$5
"
    [ "$1" = "BROKEN" ] && _broken=$((_broken + 1))
    case "$1" in NOGATE|STOPLOOP) _found=$((_found + 1)) ;; esac
    return 0
}

if [ "$MODE" = "check" ]; then
    # Дерево — каталог САМОГО прибора: в репозитории он судит репозиторий, установленный —
    # установленное. Корень сессии для этого не нужен, и прибор потому не попадает в
    # универсум собственного признака 1.
    HOOKS_DIR="${TOOL_GATE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)}"
else
    command -v jq >/dev/null 2>&1 || exit 0
    INPUT=$(cat)
    [ -n "$INPUT" ] || exit 0
    case "$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)" in
        Write|Edit|MultiEdit) ;;
        *) exit 0 ;;
    esac
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    case "$FILE" in
        */hooks/*.sh) ;;
        *) exit 0 ;;
    esac
    HOOKS_DIR=$(dirname "$FILE")
fi

# Список файлов собирается ДО awk, и awk всегда получает хотя бы один аргумент: awk без
# файлов читает stdin и виснет молча — в PostToolUse это повесило бы сессию целиком.
set -- "$HOOKS_DIR"/*.sh
if [ ! -f "$1" ]; then
    _emit BROKEN "вызов инструмента по корню сессии" 0 0 "в каталоге нет ни одного .sh: $HOOKS_DIR"
    _emit BROKEN "additionalContext на Stop без тормоза" 0 0 "в каталоге нет ни одного .sh: $HOOKS_DIR"
else

if ! _ng_canary; then
    _emit BROKEN "вызов инструмента по корню сессии" 0 0 "положительный контроль не сработал: признак ослеп"
else
    _ng=$( cd "$HOOKS_DIR" && awk "$NG_AWK" *.sh /dev/null )
    # РАЗБОР ОДИН, И ПУСТОЕ ПОЛЕ — ОТКАЗ, А НЕ НОЛЬ. Прежняя редакция резала вывод четырьмя
    # `cut` и подставляла `${…:-0}` при чтении; ноль вёл в ветки ABSENT и OK, то есть прибор
    # доложил бы «чисто», не сумев прочитать СВОЙ ЖЕ вывод (род B реестра, найдено самим
    # реестром 7 сентября 2026). Канарейка такого не ловит: она проверяет зрячесть признака,
    # а не разбираемость вывода — это разные отказы.
    _ng_files=""; _ng_univ=""; _ng_car=""; _ng_det=""
    IFS='|' read -r _ng_files _ng_univ _ng_car _ng_det <<EONG
$_ng
EONG
    if [ -z "$_ng_files" ] || [ -z "$_ng_univ" ] || [ -z "$_ng_car" ]; then
        _emit BROKEN "вызов инструмента по корню сессии" 0 0 "вывод разбора неразбираем: «${_ng}»"
    elif [ "$_ng_files" -eq 0 ] 2>/dev/null; then
        _emit BROKEN "вызов инструмента по корню сессии" 0 0 "не прочитано ни одного файла: $HOOKS_DIR"
    elif [ "$_ng_univ" -eq 0 ] 2>/dev/null; then
        # Ноль ЕДИНИЦ при живой канарейке — честное «вопрос не стоит», а не отказ: чужое дерево
        # хуков вправе не звать ни одного инструмента по корню.
        _emit ABSENT "вызов инструмента по корню сессии" 0 0 "в $_ng_files файлах нет ни одной ссылки на инструмент по корню сессии"
    elif [ "$_ng_car" -gt 0 ] 2>/dev/null; then
        _emit NOGATE "вызов инструмента по корню сессии" "$_ng_univ" "$_ng_car" "$_ng_det"
    else
        _emit OK "вызов инструмента по корню сессии" "$_ng_univ" 0 ""
    fi
fi

if ! command -v jq >/dev/null 2>&1; then
    _emit BROKEN "additionalContext на Stop без тормоза" 0 0 "нет jq — список Stop-хуков не читается"
elif [ ! -f "$SETTINGS" ]; then
    _emit BROKEN "additionalContext на Stop без тормоза" 0 0 "не прочитан $SETTINGS — какой хук на каком событии, неизвестно"
elif ! _sl_canary; then
    _emit BROKEN "additionalContext на Stop без тормоза" 0 0 "положительный контроль не сработал: признак ослеп"
else
    STOPS=$(jq -r '.hooks.Stop[]?.hooks[]?.command // empty' "$SETTINGS" 2>/dev/null | sed 's|.*/||')
    set --
    for _h in $STOPS; do
        [ -f "$HOOKS_DIR/$_h" ] && set -- "$@" "$_h"
    done
    if [ "$#" -eq 0 ]; then
        _emit BROKEN "additionalContext на Stop без тормоза" 0 0 "в $SETTINGS нет ни одного Stop-хука, найденного в $HOOKS_DIR"
    else
        _sl=$( cd "$HOOKS_DIR" && awk "$SL_AWK" "$@" /dev/null )
        # То же, что у признака 1: пустое поле — отказ, а не ноль.
        _sl_n=""; _sl_car=""; _sl_j=""; _sl_u=""; _sl_det=""
        IFS='|' read -r _sl_n _sl_car _sl_j _sl_u _sl_det <<EOSL
$_sl
EOSL
        if [ -z "$_sl_n" ] || [ -z "$_sl_car" ] || [ -z "$_sl_j" ] || [ -z "$_sl_u" ]; then
            _emit BROKEN "additionalContext на Stop без тормоза" 0 0 "вывод разбора неразбираем: «${_sl}»"
        # Знаменатель — Stop-ХУКИ, а не печати: ноль печатей значит «никто не перезапускает
        # ход», и это законное чистое состояние мира, а не отказ прибора. Число несудимых
        # печатей идёт в подробности всегда, чтобы дыра предела 5 была на виду.
        elif [ "$_sl_car" -gt 0 ] 2>/dev/null; then
            _emit STOPLOOP "additionalContext на Stop без тормоза" "$_sl_n" "$_sl_car" "$_sl_det (судимых печатей: $_sl_j, несудимых: $_sl_u)"
        else
            _emit OK "additionalContext на Stop без тормоза" "$_sl_n" 0 "судимых печатей: $_sl_j, несудимых: $_sl_u"
        fi
    fi
fi

fi

if [ "$MODE" = "check" ]; then
    printf '%s' "$_rows"
    [ "$_broken" -gt 0 ] && exit 2
    [ "$_found"  -gt 0 ] && exit 1
    exit 0
fi

# Хук-режим. BROKEN по причине «нет settings.json / нет jq» СЮДА НЕ ПОПАДАЕТ: состояние
# постоянное, и доклад о нём на каждой правке был бы ровно тем фоном, который прибор ловит.
# Ослепший признак (канарейка) — попадает: это дефект ЭТОГО файла, он чинится и потому
# самоустраняется.
MSG=""
while IFS='|' read -r _st _lbl _n _d _det; do
    [ -n "$_st" ] || continue
    case "$_st" in
        NOGATE)   MSG="$MSG
🚪 Вызов инструмента по корню сессии без гейта существования (осмотрено вызовов: $_n):$_det
   В чужом дереве инструмента нет, вызов даёт ненулевой код, и состояние это ПОСТОЯННОЕ.
   Гейт ставится ДО вызова: [ -f \"путь\" ] || exit 0 — образец hooks/ci-check-reminder.sh:43." ;;
        STOPLOOP) MSG="$MSG
🔁 additionalContext на Stop из ветки ОТКАЗА без чтения stop_hook_active (Stop-хуков: $_n):$_det
   Непустой additionalContext на Stop ПЕРЕЗАПУСКАЕТ ход, а отказ сам не проходит.
   Тормоз — образец hooks/timestamp-canary-check.sh:42-43; либо очередь pending-alerts.txt." ;;
        BROKEN)
            case "$_det" in
                *"положительный контроль"*) MSG="$MSG
⚠️ tool-gate-check ослеп: $_lbl — $_det. Молчание прибора сейчас не значит «чисто»." ;;
            esac ;;
    esac
done <<EOF
$_rows
EOF

[ -n "$MSG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
jq -cn --arg m "${MSG# }" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}' 2>/dev/null || true
exit 0
