#!/usr/bin/env bash
# СУДИТ: scripts/stopper-effect.sh hooks/itr-event-detector.sh hooks/lib/backfill-replay-one.sh hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/backfill-intrusiveness.sh
# probe_D1150 — свои копии признака реплики зовут владельца (`is_owner_reply`, его двойник в jq `owner_reply`), а не
# своё правило. Записи — в форме мира: `type` и `message.role`, уведомление строкой с `origin.kind`, после него
# `api-request-blob` с `message.role` user, сводка сжатия с `isCompactSummary`, ветка субагента с `isSidechain`.
#  · stopper-effect — реплика строкой закрывает ход (цепочка следующего хода отказу прошлого не засчитана); сводка
#    сжатия, уведомление и blob посреди хода его НЕ закрывают (цепочка после них засчитана);
#  · детектор интрузивности — уведомление и blob репликой до текущей не становятся: вопрос агента до них судится, а
#    реплика до них найдена (fallback авторизации по ней даёт solicited; «реплик нет» дал бы proactive);
#  · backfill-replay-one — сводка сжатия и реплика ветки субагента точками реплея не становятся (событий нет);
#  · три питонских судьи автора (`is_owner_reply`, `is_owner_speech`, `_is_reply_any`) отвечают как jq-двойники;
#  · без библиотеки ввода (либо со старой её редакцией) не судят ни детектор, ни реплей, ни массовый реплей
#    `backfill-intrusiveness`, а итог массового реплея — код xargs, не grep.
# Мутанты, которые проба пропускала, держит `probe_D1155`. Красная (1), пока копия судит не так; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/stopper-effect.sh" ] && [ -f "$R/hooks/itr-event-detector.sh" ] && [ -f "$R/hooks/lib/backfill-replay-one.sh" ] \
    && command -v jq >/dev/null 2>&1 || exit 2
unset ITR_STATE_DIR   # библиотека состояния ставит её выше `STATE_DIR` ниже — унаследованная увела бы запись мимо (D1154, M2)
# Унаследованные адрес библиотеки ввода и путь модулей питона подставили бы деревьям без библиотеки настоящую (скептик
# D1155, L8): детектор и stopper-effect судили бы ею, и проба краснела бы на здоровом коде.
unset INPUT_LIB PYTHONPATH
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
cd "$T" || exit 2   # `python3 -` у stopper-effect ищет модуль и в текущем каталоге: из `hooks/lib` нашёл бы снятый
rec() { jq -nc "$@"; }
CH='Почему упало? Потому что вход неверен (scripts/a.py:12). Почему вход неверен? Потому что писатель режет строку (scripts/b.py:40). Почему режет? Потому что разбор делит по разделителю записи (scripts/b.py:41) — это корень.'
TN='{type:"user",origin:{kind:"task-notification"},message:{role:"user",content:"<task-notification>задача завершена</task-notification>"}}'
BLOB='{type:"api-request-blob",message:{role:"user",content:"[SYSTEM NOTIFICATION] background task finished"}}'
SUM='{type:"user",isCompactSummary:true,message:{role:"user",content:"This session is being continued from a previous conversation."}}'
stop_case() {  # stop_case <каталог> <вид середины> — отказ, «иду дальше», середина, цепочка
    mkdir -p "$1/p"
    { rec '{type:"user",message:{role:"user",content:"почини"}}'
      rec '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"Edit",input:{}}]}}'
      rec '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",is_error:true,content:"⛔ ОТКАЗ (вызов не выполнен). Правка не пройдёт, пока не названа цепочка причин."}]}}'
      if [ "$2" != pos ]; then
          rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Понял, иду дальше."}]}}'
          case "$2" in
              next) rec '{type:"user",message:{role:"user",content:"дальше"}}' ;;
              summary) rec "$SUM" ;;
              notification) rec "$TN" ;;
              blob) rec "$TN"; rec "$BLOB" ;;
              queued) rec '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",prompt:"и ещё вот это",origin:{kind:"human"}}}' ;;
          esac
      fi
      rec --arg t "$CH" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
    } > "$1/p/s.jsonl"
    STOPPER_TRANSCRIPT_DIR="$1" bash "$R/scripts/stopper-effect.sh" 2>/dev/null | grep -oE 'цепочка произнесена: [0-9]+'
}
[ "$(stop_case "$T/pos" pos)" = "цепочка произнесена: 1" ] || { echo "рамка: цепочка сразу после отказа не засчитана"; exit 2; }
[ "$(stop_case "$T/next" next)" = "цепочка произнесена: 0" ] || {
    echo "stopper-effect: цепочка следующего хода (после реплики строкой) засчитана отказу прошлого"; exit 1; }
# Вложение `queued_command` — реплика посреди хода: у понятия «граница-узкая» ход не делит (D1150, M2 — `is_owner_speech` вместо
# `is_owner_reply` проходил).
for mid in summary notification blob queued; do
    [ "$(stop_case "$T/$mid" "$mid")" = "цепочка произнесена: 1" ] || {
        echo "stopper-effect: $mid посреди хода стал границей — цепочка того же хода отказу не засчитана"; exit 1; }
done
detect() {  # detect <имя> <подача> — событие детектора на расшифровке $T/<имя>.jsonl, свежее состояние
    mkdir -p "$T/s-$1"
    jq -nc --arg p "$T/$1.jsonl" --arg up "$2" '{session_id:"p1150",transcript_path:$p,prompt:$up,hook_event_name:"UserPromptSubmit"}' \
        | STATE_DIR="$T/s-$1" bash "$R/hooks/itr-event-detector.sh" >/dev/null 2>&1
    jq -r '(.events // [])[] | "\(.type) \(.outcome)"' "$T/s-$1/intrusiveness-p1150.json" 2>/dev/null
}
{ rec '{type:"user",message:{role:"user",content:[{type:"text",text:"напиши функцию"}]}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
  rec "$TN"; rec "$BLOB"
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Фон готов."}]}}'
} > "$T/gentle.jsonl" || exit 2
detect gentle "да" | grep -q '^gentle accepted' || {
    echo "детектор: уведомление или blob приняты за реплику до текущей — вопрос «запускаем?» выпал из суда"; exit 1; }
{ rec '{type:"user",message:{role:"user",content:[{type:"text",text:"поправь заголовок в файле"}]}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"e1",name:"Edit",input:{}},{type:"text",text:"Готово."}]}}'
  rec "$TN"; rec "$BLOB"
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Фон готов."}]}}'
} > "$T/prior.jsonl" || exit 2
detect prior "спасибо, посмотрю результат позже — интересно вышло" | grep -q '^solicited' || {
    echo "детектор: реплика до уведомления не найдена — правка по поручению судится самовольной"; exit 1; }
replay() {  # replay <имя> — события реплея одной расшифровки
    mkdir -p "$T/b-$1"
    BACKFILL_TMP="$T/b-$1" bash "$R/hooks/lib/backfill-replay-one.sh" "$T/$1.jsonl" 2>/dev/null
}
{ rec '{type:"user",message:{role:"user",content:"привет"}}'
  rec '{type:"user",message:{role:"user",content:"напиши функцию"}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
  rec "$SUM"
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Продолжаю."}]}}'
} > "$T/rsum.jsonl" || exit 2
{ rec '{type:"user",isSidechain:true,message:{role:"user",content:"привет"}}'
  rec '{type:"user",isSidechain:true,message:{role:"user",content:"напиши функцию"}}'
  rec '{type:"assistant",isSidechain:true,message:{role:"assistant",content:[{type:"text",text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
  rec '{type:"user",isSidechain:true,message:{role:"user",content:"да"}}'
} > "$T/rside.jsonl" || exit 2
{ rec '{type:"user",message:{role:"user",content:"привет"}}'
  rec '{type:"user",message:{role:"user",content:"напиши функцию"}}'
  rec '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
  rec '{type:"user",message:{role:"user",content:"да"}}'
} > "$T/rpos.jsonl" || exit 2
[ -n "$(replay rpos)" ] || { echo "рамка: реплей на реплике владельца событий не дал"; exit 2; }
[ -z "$(replay rsum)" ] || { echo "backfill-replay-one: сводка сжатия стала точкой реплея — событие, которого не было"; exit 1; }
[ -z "$(replay rside)" ] || { echo "backfill-replay-one: реплика ветки субагента стала точкой реплея"; exit 1; }
# Паритет jq-двойников и питонских судей автора на формах, где они могли бы разойтись (D1150, M1, L1; D1155): isMeta,
# пустой автор, `kind:0` (в питоне `0 == False`, в jq 0 — не человек), вложение `queued_command` с каждым автором. Судей
# в питоне три, правило автора у них одно (`_human_kind`): граница — `is_owner_reply` против `owner_reply`, речь —
# `is_owner_speech` и `_is_reply_any` против `as_reply | owner_reply` (с D1209 `_is_reply_any` и есть `is_owner_speech`).
# Предел (скептик D1150, четвёртый круг, L5): вложение с
# `attachment.origin` null jq приводит, а питон нет, на false jq падает — в мире таких записей 0, здесь их нет; `origin`
# верхнего уровня строкой, false и null судьи судят одинаково (скептик D1155, L3), строка — в наборе.
FORMS="$T/forms.jsonl"
{ rec '{type:"user",message:{role:"user",content:"да"}}'; rec "$BLOB"; rec "$SUM"; rec "$TN"
  rec '{type:"user",isMeta:true,message:{role:"user",content:"Base directory for this skill: x"}}'
  rec '{type:"user",origin:{kind:""},message:{role:"user",content:"x"}}'
  rec '{type:"user",isSidechain:true,message:{role:"user",content:"x"}}'
  rec '{type:"user",message:{role:"user",content:[{type:"tool_result",content:"x"}]}}'
  rec '{type:"user",origin:{kind:null},message:{role:"user",content:"x"}}'; rec '{type:"user",origin:{kind:false},message:{role:"user",content:"x"}}'
  rec '{type:"user",origin:"x",message:{role:"user",content:"x"}}'; rec '{type:"user",origin:{kind:0},message:{role:"user",content:"x"}}'
  for k in '"human"' null false '""' 0 '"task-notification"'; do
      rec --argjson k "$k" '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",prompt:"x",origin:{kind:$k}}}'; done
  rec '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",prompt:"x",origin:{}}}'; } > "$FORMS" || exit 2
JQ=$(bash -c '. "$1/hooks/hook-input-lib.sh"; jq -c "$HIL_OWNER_REPLY_JQ owner_reply" "$2"' _ "$R" "$FORMS" 2>/dev/null | tr '\n' ' ')
JQS=$(bash -c '. "$1/hooks/hook-input-lib.sh"; jq -c "$HIL_AS_REPLY_JQ$HIL_OWNER_REPLY_JQ as_reply | owner_reply" "$2"' _ "$R" "$FORMS" 2>/dev/null | tr '\n' ' ')
PY3=$(python3 -c 'import sys,json; sys.path.insert(0, sys.argv[1] + "/hooks/lib"); from transcript_window import is_owner_reply, is_owner_speech, _is_reply_any
L = [json.loads(l) for l in open(sys.argv[2])]
for f in (is_owner_reply, is_owner_speech, _is_reply_any): print(" ".join(str(f(r)).lower() for r in L))' "$R" "$FORMS" 2>/dev/null)
{ read -r PY; read -r PYS; read -r PYA; } <<< "$PY3"
[ -n "$PY" ] && [ "$JQ" = "$PY " ] || { echo "двойник owner_reply ($JQ) и владелец is_owner_reply ($PY) расходятся"; exit 1; }
[ "$PY" = "true false false false false false false false true true true false false false false false false false false" ] \
    || { echo "владелец судит формы не так: $PY"; exit 1; }
[ -n "$PYS" ] && [ "$JQS" = "$PYS " ] || { echo "речь: as_reply | owner_reply ($JQS) и is_owner_speech ($PYS) расходятся"; exit 1; }
[ "$PYS" = "true false false false false false false false true true true false true true true false false false true" ] \
    || { echo "is_owner_speech судит формы не так: $PYS"; exit 1; }
[ "$JQS" = "$PYA " ] || { echo "речь: as_reply | owner_reply ($JQS) и _is_reply_any ($PYA) расходятся"; exit 1; }
# Без библиотеки ввода не судить (D1150, H1): детектор не пишет события (прежде — ложный proactive), реплей не идёт и
# говорит об этом (прежде — молчаливый ноль событий).
# Дерево без библиотеки ввода: её подключает и `intrusiveness-state-lib.sh`, поэтому подмена INPUT_LIB её не убирает;
# чужой HOME — чтобы не нашлась установленная.
mkdir -p "$T/nl/hooks/lib" "$T/fh" "$T/s-nolib" "$T/b-nolib"
hd="$R/hooks"; for f in "$hd"/*.sh; do [ "${f##*/}" = hook-input-lib.sh ] || cp "$f" "$T/nl/hooks/"; done
cp "$hd"/lib/*.sh "$hd"/lib/*.py "$T/nl/hooks/lib/" 2>/dev/null
[ -f "$T/nl/hooks/itr-event-detector.sh" ] && [ ! -f "$T/nl/hooks/hook-input-lib.sh" ] || exit 2
jq -nc --arg p "$T/prior.jsonl" '{session_id:"p1150n",transcript_path:$p,prompt:"спасибо, посмотрю результат позже — интересно вышло",hook_event_name:"UserPromptSubmit"}' \
    | HOME="$T/fh" STATE_DIR="$T/s-nolib" bash "$T/nl/hooks/itr-event-detector.sh" >/dev/null 2>&1
if jq -e '(.events // []) | length > 0' "$T/s-nolib/intrusiveness-p1150n.json" >/dev/null 2>&1; then
    echo "детектор без библиотеки ввода судит: $(jq -c '[.events[].type]' "$T/s-nolib/intrusiveness-p1150n.json")"; exit 1; fi
err=$(HOME="$T/fh" BACKFILL_TMP="$T/b-nolib" bash "$T/nl/hooks/lib/backfill-replay-one.sh" "$T/rpos.jsonl" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$err" | grep -q "hook-input-lib" || {
    echo "backfill-replay-one без библиотеки ввода не сказал об этом кодом 2 (rc=$rc)"; exit 1; }
# Без библиотеки нет и фильтра служебных ходов: писатель авторизации не судит ничего — уведомление задачи не взводит
# авторизацию (скептик четвёртого круга, H2). Контроль: с библиотекой поручение записывается.
mkdir -p "$T/s-auth" "$T/s-auth-ok"
jq -nc --arg p "$T/prior.jsonl" '{session_id:"p1150a",transcript_path:$p,prompt:"<task-notification>задача готова, сделай отчёт</task-notification>",hook_event_name:"UserPromptSubmit"}' \
    | HOME="$T/fh" STATE_DIR="$T/s-auth" bash "$T/nl/hooks/itr-event-detector.sh" >/dev/null 2>&1
if [ -f "$T/s-auth/authorization-p1150a.json" ]; then
    echo "детектор без библиотеки ввода записал авторизацию на служебном ходе: $(cat "$T/s-auth/authorization-p1150a.json")"; exit 1; fi
jq -nc --arg p "$T/prior.jsonl" '{session_id:"p1150k",transcript_path:$p,prompt:"сделай заголовок жирным",hook_event_name:"UserPromptSubmit"}' \
    | STATE_DIR="$T/s-auth-ok" bash "$R/hooks/itr-event-detector.sh" >/dev/null 2>&1
jq -e '.active == true' "$T/s-auth-ok/authorization-p1150k.json" >/dev/null 2>&1 || { echo "рамка: с библиотекой поручение не записано"; exit 2; }
# Пустой список расшифровок у массового реплея — не сбой (H1 четвёртого круга): код 0.
mkdir -p "$T/bp-empty"
HOME="$T/fh" BACKFILL_PROJECTS_DIR="$T/bp-empty" BACKFILL_OUT="$T/bo-empty.jsonl" BACKFILL_PARALLEL=1 \
    bash "$R/hooks/backfill-intrusiveness.sh" >/dev/null 2>&1 || { echo "backfill-intrusiveness: пустой список расшифровок — код $?, не 0"; exit 1; }
# Массовый реплей не глушит отказ воркера (H2): без библиотеки — код 2 и строка «реплей неисправен»; с ней — 0.
mkdir -p "$T/bp/p"; cp "$T/rpos.jsonl" "$T/bp/p/" || exit 2
err=$(HOME="$T/fh" BACKFILL_PROJECTS_DIR="$T/bp" BACKFILL_OUT="$T/bo-nl.jsonl" BACKFILL_PARALLEL=1 \
      bash "$T/nl/hooks/backfill-intrusiveness.sh" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$err" | grep -q "реплей неисправен" || {
    echo "backfill-intrusiveness: отказ воркера заглушён (rc=$rc)"; exit 1; }
# Строка причины настоящего воркера доходит целиком: выборочный фильтр stderr по его префиксу оставил бы только
# «реплей неисправен» (скептик D1155, M2).
printf '%s' "$err" | grep -q "^backfill-replay-one: .*hook-input-lib" || {
    echo "backfill-intrusiveness: строка причины воркера «backfill-replay-one: … hook-input-lib» не дошла до stderr"; exit 1; }
HOME="$T/fh" BACKFILL_PROJECTS_DIR="$T/bp" BACKFILL_OUT="$T/bo-ok.jsonl" BACKFILL_PARALLEL=1 \
    bash "$R/hooks/backfill-intrusiveness.sh" >/dev/null 2>&1 || { echo "рамка: массовый реплей с библиотекой не прошёл"; exit 2; }
# Итог массового реплея — код xargs, а не grep, строка причины воркера доходит до stderr, сводки при отказе нет (скептик
# D1150, четвёртый круг, M1–M3). Воркер-заглушка: отказывает на одной расшифровке, на другой печатает событие (grep 0,
# xargs нет), на третьей молчит (grep 1, xargs 0) — настоящему воркеру одну расшифровку из нескольких не уронить.
# Заглушка судит имя файла, а не путь: «bad» в TMPDIR ломал бы её (скептик D1155, L8). Агрегатор-заглушка пишет файл
# дайджеста: при отказе воркера дайджеста нет (скептик D1155, M1 — собранный до проверки, он уходил к calibrate.py);
# контроль — без отказа дайджест есть.
mkdir -p "$T/sw/hooks/lib" "$T/swp/mix" "$T/swp/quiet" "$T/swp/good"; cp "$hd/backfill-intrusiveness.sh" "$T/sw/hooks/" || exit 2
printf '%s\n' '#!/usr/bin/env bash' 'case "${1##*/}" in' '  bad.jsonl) echo "заглушка воркера: отказ на $1" >&2; exit 2 ;;' \
    "  good.jsonl) echo '{\"type\":\"gentle\",\"outcome\":\"accepted\"}' ;;" 'esac' > "$T/sw/hooks/lib/backfill-replay-one.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cp "$1" "$2"' > "$T/sw/hooks/lib/backfill-aggregate-digest.sh"; chmod +x "$T/sw/hooks/lib/backfill-aggregate-digest.sh"
: > "$T/swp/mix/good.jsonl"; : > "$T/swp/mix/bad.jsonl"; : > "$T/swp/quiet/quiet.jsonl"; : > "$T/swp/good/good.jsonl"
HOME="$T/fh" BACKFILL_PROJECTS_DIR="$T/swp/good" BACKFILL_OUT="$T/bo-good-history.jsonl" BACKFILL_PARALLEL=1 \
    bash "$T/sw/hooks/backfill-intrusiveness.sh" --digest >/dev/null 2>&1
[ -s "$T/bo-good-digest.jsonl" ] || { echo "рамка: без отказа воркера агрегатор-заглушка дайджеста не дал"; exit 2; }
# Унаследованная `BAK` в строку отказа не попадает: прежнего итога нет — нет и «прежний итог — …» (скептик D1155, L5).
out=$(HOME="$T/fh" BAK="$T/not-a-backup" BACKFILL_PROJECTS_DIR="$T/swp/mix" BACKFILL_OUT="$T/bo-mix-history.jsonl" \
      BACKFILL_PARALLEL=1 bash "$T/sw/hooks/backfill-intrusiveness.sh" --digest 2>"$T/bo-mix.err"); rc=$?
grep -q '"gentle"' "$T/bo-mix-history.jsonl" 2>/dev/null || { echo "рамка: заглушка воркера не дала события"; exit 2; }
[ "$rc" -eq 2 ] || { echo "backfill-intrusiveness: отказ воркера среди расшифровок с событиями — код $rc, не 2"; exit 1; }
grep -q "заглушка воркера: отказ" "$T/bo-mix.err" || { echo "backfill-intrusiveness: строка причины воркера заглушена"; exit 1; }
! printf '%s' "$out" | grep -q "Backfill complete" || { echo "backfill-intrusiveness: при отказе воркера напечатана сводка"; exit 1; }
[ ! -e "$T/bo-mix-digest.jsonl" ] && ! printf '%s' "$out" | grep -q "calibrate" || {
    echo "backfill-intrusiveness: при отказе воркера собран дайджест для calibrate.py"; exit 1; }
! grep -q "not-a-backup" "$T/bo-mix.err" || { echo "backfill-intrusiveness: строка отказа назвала прежним итогом унаследованную BAK"; exit 1; }
HOME="$T/fh" BACKFILL_PROJECTS_DIR="$T/swp/quiet" BACKFILL_OUT="$T/bo-quiet.jsonl" BACKFILL_PARALLEL=1 \
    bash "$T/sw/hooks/backfill-intrusiveness.sh" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || { echo "backfill-intrusiveness: расшифровка без событий — код $rc, не 0"; exit 1; }
# Старая редакция библиотеки (нынешняя установка): фильтр служебных ходов `is_non_user_turn` есть, правил реплики и
# границы хода нет — суда нет, охрана по правилу, а не по файлу (M1 третьего круга). Строится из нынешней библиотеки
# снятием правил, а не из истории git: дерево скептика истории не несёт (скептик пятого круга, M2 — прежняя фикстура
# без фильтра пропускала мутант «охрана только по фильтру»).
mkdir -p "$T/ol/hooks/lib" "$T/s-old" "$T/b-old"; cp "$T"/nl/hooks/*.sh "$T/ol/hooks/"; cp "$T"/nl/hooks/lib/* "$T/ol/hooks/lib/" 2>/dev/null
{ cat "$hd/hook-input-lib.sh"; printf '%s\n' "unset HIL_OWNER_REPLY_JQ HIL_TURN_USER_JQ"; } > "$T/ol/hooks/hook-input-lib.sh" || exit 2
bash -c '. "$1"; command -v is_non_user_turn >/dev/null && [ -z "${HIL_OWNER_REPLY_JQ:-}" ]' _ "$T/ol/hooks/hook-input-lib.sh" \
    || { echo "рамка: фикстура старой редакции не та (фильтра нет либо правило осталось)"; exit 2; }
jq -nc --arg p "$T/prior.jsonl" '{session_id:"p1150o",transcript_path:$p,prompt:"спасибо, посмотрю результат позже — интересно вышло",hook_event_name:"UserPromptSubmit"}' \
    | HOME="$T/fh" STATE_DIR="$T/s-old" bash "$T/ol/hooks/itr-event-detector.sh" >/dev/null 2>&1
if jq -e '(.events // []) | length > 0' "$T/s-old/intrusiveness-p1150o.json" >/dev/null 2>&1; then
    echo "детектор со старой редакцией библиотеки судит: $(jq -c '[.events[].type]' "$T/s-old/intrusiveness-p1150o.json")"; exit 1; fi
# Строка причины называет и старую редакцию: «нет библиотеки» при живом файле — ложь (скептик третьего круга, L4).
err=$(HOME="$T/fh" BACKFILL_TMP="$T/b-old" bash "$T/ol/hooks/lib/backfill-replay-one.sh" "$T/rpos.jsonl" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$err" | grep -q "старая редакция" || {
    echo "backfill-replay-one со старой редакцией библиотеки не отказал кодом 2 со строкой «старая редакция» (rc=$rc)"; exit 1; }
# Охрана детектора — по наличию фильтра, а не файла (скептик D1150 по b74ce609, L1): файл библиотеки есть, а фильтра
# служебных ходов в нём нет (редакция до фильтра либо сломанная) — детектор не пишет ничего; охрана `[ -f "$INPUT_LIB" ]`
# пустила бы уведомление задачи к писателю авторизации.
mkdir -p "$T/fl/hooks/lib" "$T/s-fl"; cp "$T"/nl/hooks/*.sh "$T/fl/hooks/"; cp "$T"/nl/hooks/lib/* "$T/fl/hooks/lib/" 2>/dev/null
{ cat "$hd/hook-input-lib.sh"; printf '%s\n' "unset -f is_non_user_turn; unset HIL_OWNER_REPLY_JQ HIL_TURN_USER_JQ"; } > "$T/fl/hooks/hook-input-lib.sh" || exit 2
bash -c '. "$1"; ! command -v is_non_user_turn >/dev/null' _ "$T/fl/hooks/hook-input-lib.sh" \
    || { echo "рамка: фикстура «файл без фильтра» не та (фильтр остался)"; exit 2; }
jq -nc --arg p "$T/prior.jsonl" '{session_id:"p1150f",transcript_path:$p,prompt:"<task-notification>задача готова, сделай отчёт</task-notification>",hook_event_name:"UserPromptSubmit"}' \
    | HOME="$T/fh" STATE_DIR="$T/s-fl" bash "$T/fl/hooks/itr-event-detector.sh" >/dev/null 2>&1
if [ -f "$T/s-fl/authorization-p1150f.json" ]; then
    echo "детектор с библиотекой без фильтра записал авторизацию на уведомлении задачи: $(cat "$T/s-fl/authorization-p1150f.json")"; exit 1; fi
# Старая редакция: фильтр есть, значит поручение записывается, а уведомление задачи отсечено до записи — как до D1150
# (скептик пятого круга, H1: охрана по правилу реплики стояла выше писателя и теряла поручение).
mkdir -p "$T/s-old-auth"
jq -nc --arg p "$T/prior.jsonl" '{session_id:"p1150ok",transcript_path:$p,prompt:"сделай заголовок жирным",hook_event_name:"UserPromptSubmit"}' \
    | HOME="$T/fh" STATE_DIR="$T/s-old-auth" bash "$T/ol/hooks/itr-event-detector.sh" >/dev/null 2>&1
jq -e '.active == true' "$T/s-old-auth/authorization-p1150ok.json" >/dev/null 2>&1 || {
    echo "детектор со старой редакцией библиотеки не записал поручение: $(cat "$T/s-old-auth/authorization-p1150ok.json" 2>/dev/null || echo 'нет файла')"; exit 1; }
jq -nc --arg p "$T/prior.jsonl" '{session_id:"p1150on",transcript_path:$p,prompt:"<task-notification>задача готова, сделай отчёт</task-notification>",hook_event_name:"UserPromptSubmit"}' \
    | HOME="$T/fh" STATE_DIR="$T/s-old-auth" bash "$T/ol/hooks/itr-event-detector.sh" >/dev/null 2>&1
if [ -f "$T/s-old-auth/authorization-p1150on.json" ]; then
    echo "детектор со старой редакцией библиотеки записал авторизацию на уведомлении задачи: $(cat "$T/s-old-auth/authorization-p1150on.json")"; exit 1; fi
# Отказ встроенного питона у stopper-effect — код 2, а не «есть обойдённые» (L2, M2 третьего круга).
mkdir -p "$T/se/hooks/lib" "$T/se/scripts"; cp "$R/scripts/stopper-effect.sh" "$T/se/scripts/"; cp "$hd"/*.sh "$T/se/hooks/"
for f in "$hd"/lib/*; do [ "${f##*/}" = transcript_window.py ] || cp "$f" "$T/se/hooks/lib/" 2>/dev/null; done
STOPPER_TRANSCRIPT_DIR="$T/pos" HOME="$T/fh" bash "$T/se/scripts/stopper-effect.sh" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] || { echo "stopper-effect без владельца реплики вышел кодом $rc, а не 2"; exit 1; }
echo "копии признака реплики судят её правилом владельца"
exit 0
