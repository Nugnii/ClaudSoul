#!/usr/bin/env bash
# СУДИТ: hooks/lib/reply-readers.tsv
# test_reply_readers_behavior.sh — D1149 (корень R5): понятие «реплики владельца», объявленное строкой реестра
# `hooks/lib/reply-readers.tsv`, сверяется с ПОВЕДЕНИЕМ читателя. Прежде реестр судила только проба D1145 — «слово из
# словаря», а поведение держали ноги `test_queued_reply_readers.sh` литералами, реестра не читая: подмена понятия у
# строки проходила зелёной (скептик opus по D1145, M1), и одним словом «граница» реестр звал и узкое понятие, и широкое
# (скептики по D1153, второй повод D1149).
#
# Каждый читатель прогоняется своим драйвером на различающих случаях. Ход: реплика владельца A → текст агента → запись X
# → текст агента. Драйвер печатает, считает ли читатель X репликой владельца (для читателя границы — началом хода):
#   Q  — X: реплика, набранная посреди хода (вложение `queued_command`, автор человек), текст — списком блоков;
#   Qs — та же реплика, текст строкой: в мире строкой 141 вложение из 229 (скептик opus, круг 3, M1); ответ обязан
#        совпасть с Q — форма содержимого понятия не меняет;
#   S1 — X: сводка сжатия (`isCompactSummary`), текст — простая метка;
#   S2 — X: уведомление задачи (`origin.kind: task-notification`), текст — простая метка;
#   S1w, S2w — те же записи в форме мира: текст с префиксом сводки и обёрткой `<task-notification>`. Ответ обязан
#        совпасть с S1/S2: понятие судится полем (без обёртки подмена проверки поля пряталась за отсевом по тексту —
#        скептик opus, H1 круга 1), а отсев по форме текста при верном поле менял бы понятие в мире (H1 круга 2);
#   P  — X: реплика посреди хода, совпадающая с ТЕКУЩЕЙ подачей (только у читателя подачи; иным — «-»); Ps — то же
#        с текстом строкой (в 402 расшифровках строкой 237 вложений из 546 — скептик opus, круг 4, L1), ответ = P;
#   M, Sc, Qn, U0 — X отличается от реплики одним полем (D1202): служебная запись `isMeta`, запись боковой ветки
#        `isSidechain`, уведомление задачи вложением (`commandMode: task-notification`, без автора), реплика без поля
#        автора; Qp — вложение-реплика от не-человека (отчёт субагента, `origin.kind: peer`), Q0 — вложение-реплика без
#        поля автора, ответ = Q. M, Qn и Qp — не реплика и не граница никому, U0 — реплика и граница всем; что судится у
#        какого понятия — `rr_want`. У читателя с двумя путями (страж поправок, `root-cause-lib`) наблюдаются оба;
#        разошлись — «≠».
# Ответ: 1 — считает, 0 — нет, «-» — случай читателю неприменим (законно только для P), «?» — драйвер не смог
# наблюдать (контроль не сработал: читатель не отозвался и там, где обязан). Сигнатура «Q S1 S2» понятия:
#   граница-узкая   0 0 0   запись user владельца (`is_owner_reply`, в jq `owner_reply`); X ход не делит
#   граница-широкая 0 1 1   запись user (`is_turn_user`, в jq `turn_user`); сводка и уведомление ход делят
#   граница-без-сводки 0 0 1  запись user, кроме сводки сжатия: уведомление ход делит, сжатие посреди хода — нет
#   речь            1 0 0   последняя речь владельца (`is_owner_speech`, `as_reply`); P — «-» либо 1
#   до-текущей      1 0 0   речь до текущей подачи; P обязан быть 0 (без P «до-текущей» от «речи» не отличить)
# `не-реплика` драйвера не имеет: драйвер у такой строки — красное; `источник` не судится.
# Красное: наблюдение не сигнатура объявленного понятия, у строки нет драйвера, драйвер без строки, «?».
#
# НАЗВАННЫЙ ПРЕДЕЛ (корень R3 — формы перечислены). Формы записей в случаях взяты из мира замером 31 октября 2026
# (60 расшифровок): текст реплики посреди хода списком и строкой, сводка и уведомление с полем и с обёрткой в тексте.
# Три круга скептика подряд находили форму, которой в фикстуре не было; новая форма мира (иной вид содержимого, новая
# служебная пометка) сюда сама не придёт; поля `isMeta`, `isSidechain`, вложение-уведомление и запись без автора
# добавлены D1202 по поводам скептиков, а не переписью.
# Условие снятия: формы случаев выводятся переписью видов записей живых расшифровок, а не перечнем в фикстуре.
# Запуск: без аргументов — все строки реестра; `--only <путь>[,<путь>…]` — названные; реестр — `REPLY_READERS_REG`
# (по умолчанию `hooks/lib/reply-readers.tsv`). Проба `hooks/tests/fixtures/probe_D1149.sh` судит этим свидетелем
# копию реестра с подменой понятия.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
R="$(cd "$HOOKS/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
REG="${REPLY_READERS_REG:-$HOOKS/lib/reply-readers.tsv}"
[ -f "$REG" ] || { echo "FAIL: реестра нет: $REG"; exit 1; }
ONLY=""
if [ "${1:-}" = --only ]; then
    ONLY=",$(printf '%s' "${2:-}" | tr -d ' \t'),"           # пробел и таб вокруг запятой — не часть пути (скептик D1149)
    [ "$ONLY" != ",," ] || { echo "FAIL: --only без путей — судить нечего"; exit 1; }
fi
# Память наблюдений (ниже) — только для прогона по названным строкам: полный прогон, унаследовавший её из окружения,
# судил бы старые наблюдения вместо читателей.
[ -n "$ONLY" ] || unset REPLY_READERS_OBS
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"
unset ITR_STATE_DIR   # библиотека состояния ставит её выше `STATE_DIR` — унаследованная увела бы запись мимо (D1154, M2)
unset INPUT_LIB       # путь библиотеки реплик у стража поправок драйвер задаёт сам (путь без помощника окна, D1202)
export PYTHONDONTWRITEBYTECODE=1                      # читатели на питоне не пишут __pycache__ в дерево

# --- Фикстуры ---------------------------------------------------------------------------------------------------------
MARK='МЕТКА-ИКС'                      # уникальный текст записи X: по нему драйвер узнаёт, взята ли она
A_TEXT='сделай заголовок страницы синим'
rr_reply() { jq -nc --arg t "$1" '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:$t}]}}'; }
rr_said()  { jq -nc --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
rr_x() {  # rr_x <Q|S1|S2|P> [текст] — запись X различающего случая; текст по умолчанию — метка
    local t="${2:-$MARK}"
    case "$1" in
        Q|P) jq -nc --arg t "$t" '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",
                 origin:{kind:"human"},prompt:[{type:"text",text:$t}]}}' ;;
        Qs|Ps) jq -nc --arg t "$t" '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",
                 origin:{kind:"human"},prompt:$t}}' ;;
        # S1/S2 — различает только ПОЛЕ (`isCompactSummary`, `origin.kind`), текст — простая метка; S1w/S2w — форма мира
        # (префикс сводки, обёртка уведомления): в 60 расшифровках обёртка у 144 из 144 уведомлений и 18 из 18 сводок.
        S1) jq -nc --arg t "$t" '{type:"user",isCompactSummary:true,message:{role:"user",content:$t}}' ;;
        S2) jq -nc --arg t "$t" '{type:"user",origin:{kind:"task-notification"},message:{role:"user",content:$t}}' ;;
        S1w) jq -nc --arg t "$t" '{type:"user",isCompactSummary:true,message:{role:"user",
                 content:("This session is being continued from a previous conversation. " + $t)}}' ;;
        S2w) jq -nc --arg t "$t" '{type:"user",origin:{kind:"task-notification"},message:{role:"user",
                 content:("<task-notification>\n<task-id>b1</task-id>\n<summary>" + $t + "</summary>\n</task-notification>")}}' ;;
        # Служебные поля и автор (D1202): каждую запись отличает от реплики A ровно одно поле, текст — метка.
        M)  jq -nc --arg t "$t" '{type:"user",isMeta:true,origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:$t}]}}' ;;
        Sc) jq -nc --arg t "$t" '{type:"user",isSidechain:true,origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:$t}]}}' ;;
        # Уведомление задачи вложением: в мире 1509 вложений `queued_command` из 1962, 378 — без автора; без автора
        # реплику от него отличает один `commandMode`.
        Qn) jq -nc --arg t "$t" '{type:"attachment",attachment:{type:"queued_command",commandMode:"task-notification",prompt:$t}}' ;;
        # Вложение-реплика от не-человека — отчёт субагента (`origin.kind: peer`, в мире 272 в 412 расшифровках) — и без
        # поля автора (2 в мире): реплику от них отличает один автор (скептик opus D1202, H1 и L1).
        Qp) jq -nc --arg t "$t" '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",
                 origin:{kind:"peer"},prompt:[{type:"text",text:$t}]}}' ;;
        Q0) jq -nc --arg t "$t" '{type:"attachment",attachment:{type:"queued_command",commandMode:"prompt",
                 prompt:[{type:"text",text:$t}]}}' ;;
        # Реплика без поля автора — запись владельца версий 2.1.170–2.1.294 (45 реплик в 25 расшифровках).
        U0) jq -nc --arg t "$t" '{type:"user",message:{role:"user",content:[{type:"text",text:$t}]}}' ;;
    esac
}
fresh() { rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"; }
stop_input() { jq -nc --arg s "$1" --arg p "$2" '{hook_event_name:"Stop",session_id:$s,transcript_path:$p}'; }
# Число строк; нет файла — 0. Не `grep -c … || echo 0`: у пустого файла grep сам печатает 0 и выходит 1, и запасной
# ноль давал «0\n0» (род D1193) — сравнение `-ge` на таком числе ложно, и вердикт читался по случайной ветке.
lines() { local k; k=$(grep -c '' "$1" 2>/dev/null); echo "${k:-0}"; }
# scan_case <случай> <файл> <текст с находкой> <текст без находки> — ход для сканера речи на Stop: находка сказана ДО X
# (читает ли сканер текст до X — значит, X ход не делит), контроль — находка ПОСЛЕ X (сканер вообще отзывается).
scan_case() {
    { rr_reply "$A_TEXT"; rr_said "$3"; rr_x "$1"; rr_said "$4"; } > "$2"
    { rr_reply "$A_TEXT"; rr_said "$4"; rr_x "$1"; rr_said "$3"; } > "$2.ctl"
}
# scan_verdict <находок до X> <находок в контроле> → 1 (X начал ход: находку до него не судили), 0, ?
scan_verdict() {
    [ "$2" -ge 1 ] 2>/dev/null || { echo '?'; return; }
    if [ "$1" -ge 1 ] 2>/dev/null; then echo 0; else echo 1; fi
}

# --- Драйверы ---------------------------------------------------------------------------------------------------------
# drv_<путь, где не буква и не цифра — «_»> <Q|S1|S2|P> → 1 | 0 | - | ?

drv_hooks_output_language_check_sh() {  # смешение алфавитов на Stop: токен в состоянии нарушений
    [ "$1" = P ] && { echo -; return; }
    local f="$T/olc-$1.jsonl" n c
    scan_case "$1" "$f" "Сделал trёх правок." "Шрифт увеличил."
    fresh; stop_input s-ol "$f" | bash "$HOOKS/output-language-check.sh" >/dev/null 2>&1
    n=$(lines "$STATE_DIR/output-violations-s-ol.jsonl")
    fresh; stop_input s-ol "$f.ctl" | bash "$HOOKS/output-language-check.sh" >/dev/null 2>&1
    c=$(lines "$STATE_DIR/output-violations-s-ol.jsonl")
    scan_verdict "$n" "$c"
}

drv_hooks_shared_language_lib_sh() {  # речь для общего словаря: какие тексты взяты речью собеседника
    [ "$1" = P ] && { echo -; return; }
    local f="$T/shl-$1.jsonl" out
    { rr_reply "$A_TEXT"; rr_said "Сделал."; rr_x "$1"; rr_said "Дальше."; } > "$f"
    out=$(bash -c '. "$1/shared-language-lib.sh"; shlang_user_text "$2"' _ "$HOOKS" "$f" 2>/dev/null)
    grep -Fq "$A_TEXT" <<< "$out" || { echo '?'; return; }
    if grep -Fq "$MARK" <<< "$out"; then echo 1; else echo 0; fi
}

# B1 — драйверы читателей границы хода (D1149): relative-date-check, fix-level-check, accepted-alternative-gap,
# timestamp-canary-check, declared-problem-recorded. Все — стражи Stop: P всегда «-».
# Изоляция: LESSONS_DIR, CANARY_STATE_DIR, ABLATION_DIR, DPR_LOCAL_BACKLOG — под $T; STATE_DIR чистит fresh.

b1_stop() {  # b1_stop <хук> <sid> <расшифровка> [ENV=…] → stdout хука; состояние чистое
    local h="$1" s="$2" t="$3"; shift 3
    fresh
    stop_input "$s" "$t" | env "$@" bash "$HOOKS/$h" 2>/dev/null
}

drv_hooks_relative_date_check_sh() {  # «вчера» без даты: находка в файле находок
    [ "$1" = P ] && { echo -; return; }
    local f="$T/b1-rdc-$1.jsonl" n c
    scan_case "$1" "$f" "Вчера мы починили счётчики." "Цвет вернул."
    b1_stop relative-date-check.sh s-b1rd "$f" >/dev/null
    n=$(lines "$STATE_DIR/relative-date-findings-s-b1rd.jsonl")
    b1_stop relative-date-check.sh s-b1rd "$f.ctl" >/dev/null
    c=$(lines "$STATE_DIR/relative-date-findings-s-b1rd.jsonl")
    scan_verdict "$n" "$c"
}

drv_hooks_fix_level_check_sh() {  # текстовый фикс после инцидента: фраза в состоянии. LESSONS_DIR — пустой каталог
    [ "$1" = P ] && { echo -; return; }
    local f="$T/b1-flc-$1.jsonl" n c
    mkdir -p "$T/b1-nolessons"
    scan_case "$1" "$f" "Ошибся, буду внимательнее." "Шрифт увеличил."
    b1_stop fix-level-check.sh s-b1fl "$f" LESSONS_DIR="$T/b1-nolessons" >/dev/null
    n=$(lines "$STATE_DIR/fix-level-s-b1fl.jsonl")
    b1_stop fix-level-check.sh s-b1fl "$f.ctl" LESSONS_DIR="$T/b1-nolessons" >/dev/null
    c=$(lines "$STATE_DIR/fix-level-s-b1fl.jsonl")
    scan_verdict "$n" "$c"
}

drv_hooks_accepted_alternative_gap_sh() {  # принятый вариант: additionalContext на stdout
    [ "$1" = P ] && { echo -; return; }
    local f="$T/b1-aag-$1.jsonl" n c
    scan_case "$1" "$f" "Отличная идея, беру твой вариант." "Шрифт увеличил."
    n=$(b1_stop accepted-alternative-gap.sh s-b1aa "$f" | grep -c additionalContext)
    c=$(b1_stop accepted-alternative-gap.sh s-b1aa "$f.ctl" | grep -c additionalContext)
    scan_verdict "$n" "$c"
}

drv_hooks_timestamp_canary_check_sh() {
    # Шапка с эхом инжекта сказана ДО X, после X шапки нет. X начал ход → шапки в ходе нет → алерт «Канарейка» (1).
    # Не начал → шапка засчитана → алерта нет (0). Контроль: шапки нет нигде — алерт обязан быть.
    [ "$1" = P ] && { echo -; return; }
    # Реплика без автора — настоящая реплика, и окно шапки за ней открывает её же инжект 🕐: без инжекта после реплики
    # (такой записи в мире нет) канарейка шапки не ждёт, с ним — ждёт при любой границе. Случай ей неприменим (D1202).
    [ "$1" = U0 ] && { echo -; return; }
    local f="$T/b1-tcc-$1.jsonl" inj n c
    inj='{"type":"attachment","attachment":{"type":"hook_additional_context","content":["🕐 2026-10-27 12:00 CEST"]}}'
    mkdir -p "$T/b1-noabl"
    { rr_reply "$A_TEXT"; printf '%s\n' "$inj"; rr_said "🕐 2026-10-27 12:00 Сделал."; rr_x "$1"; rr_said "Дальше."; } > "$f"
    { rr_reply "$A_TEXT"; printf '%s\n' "$inj"; rr_said "Сделал."; rr_x "$1"; rr_said "Дальше."; } > "$f.ctl"
    n=$(b1_stop timestamp-canary-check.sh s-b1tc "$f" CANARY_STATE_DIR="$STATE_DIR" ABLATION_DIR="$T/b1-noabl" | grep -c Канарейка)
    c=$(b1_stop timestamp-canary-check.sh s-b1tc "$f.ctl" CANARY_STATE_DIR="$STATE_DIR" ABLATION_DIR="$T/b1-noabl" | grep -c Канарейка)
    [ "$c" -ge 1 ] 2>/dev/null || { echo '?'; return; }
    if [ "$n" -ge 1 ] 2>/dev/null; then echo 1; else echo 0; fi
}

b1_iso() { python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
b1_touch() { python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"; }

b1_dpr() {  # b1_dpr <расшифровка> <эпоха правки бэклога> → число строк напоминания «закрытого списка»
    local f="$1" key
    key=$(bash -c '. "$1/root-cause-lib.sh"; rc_turn_key "$2"' _ "$HOOKS" "$f" 2>/dev/null)
    printf '# долг\n' > "$T/b1-BACKLOG.md"; b1_touch "$T/b1-BACKLOG.md" "$2"
    fresh
    printf 'turn:%s|discovery:123|\n' "$key" > "$STATE_DIR/five-whys-s-b1dp.seen"
    stop_input s-b1dp "$f" | DPR_LOCAL_BACKLOG="$T/b1-BACKLOG.md" bash "$HOOKS/declared-problem-recorded.sh" >/dev/null 2>&1
    key=$(grep -c 'закрытого списка' "$STATE_DIR/stop-signals-s-b1dp.txt" 2>/dev/null); echo "${key:-0}"
}

drv_hooks_declared_problem_recorded_sh() {
    # Реплика A (−3600 с) → «Нашёл проблему» → X (−30 с, с отметкой времени) → текст. Бэклог тронут на −1800 с, между A и X.
    # X начал ход → правка бэклога до начала хода не засчитана → напоминание есть (1). Не начал → исход засчитан (0).
    # Контроль: бэклог тронут до A (−7200 с) — напоминание обязано быть.
    [ "$1" = P ] && { echo -; return; }
    local f="$T/b1-dpr-$1.jsonl" now n c
    now=$(date -u +%s)
    { jq -nc --arg ts "$(b1_iso $((now - 3600)))" '{type:"user",origin:{kind:"human"},timestamp:$ts,message:{role:"user",content:"разбери это"}}'
      rr_said "Нашёл проблему."
      rr_x "$1" | jq -c --arg ts "$(b1_iso $((now - 30)))" '. + {timestamp:$ts}'
      rr_said "Дальше."; } > "$f"
    n=$(b1_dpr "$f" $((now - 1800)))
    c=$(b1_dpr "$f" $((now - 7200)))
    [ "$c" -ge 1 ] 2>/dev/null || { echo '?'; return; }
    if [ "$n" -ge 1 ] 2>/dev/null; then echo 1; else echo 0; fi
}

# --- B2: root-cause-lib, five-whys-gate, session-collector, publish-guard, user-correction-guard, activity-flush-lib ---

b2_cksum() { printf '%s\n' "$1" | cksum | awk '{print $1}'; }
b2_bash() {  # b2_bash <команда> — запись агента с вызовом Bash
    jq -nc --arg c "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"b2t",name:"Bash",input:{command:$c}}]}}'
}

# Два пути границы (D1202): свёртка хода `rc_turn_digest` и исход хода `rc_outcome_observed` — второй зовёт
# `declared-problem-recorded.sh`. Ответ — общий; разошлись — «≠». Исход хода наблюдается и без помощника окна (D1235):
# с помощником его окно начинается с широкой границы (`wide`) и границу решает питонский признак, без помощника либо со
# старым, не знающим `wide`, — jq-признак по всему файлу; библиотека реплик — ссылкой из каталога без `lib/`, как у
# стража поправок ниже.
drv_hooks_root_cause_lib_sh() {
    [ "$1" = P ] && { echo -; return; }
    local nh="$T/rcl-nohelper"
    [ -e "$nh/hook-input-lib.sh" ] || { mkdir -p "$nh"; ln -s "$HOOKS/hook-input-lib.sh" "$nh/hook-input-lib.sh"; }
    b2_join "$(b2_rcl_digest "$1")" "$(b2_rcl_outcome "$1")" "$(INPUT_LIB="$nh/hook-input-lib.sh" b2_rcl_outcome "$1")"
}
b2_rcl_digest() {  # ключ и текст хода из свёртки rc_turn_digest: чья реплика взята ключом хода
    local f="$T/rcl-$1.jsonl" k
    { rr_reply "$A_TEXT"; rr_said "Сделал."; rr_x "$1"; rr_said "Дальше."; } > "$f"
    fresh
    k=$(bash -c '. "$1/root-cause-lib.sh"; rc_turn_digest "$2"' _ "$HOOKS" "$f" 2>/dev/null | jq -r '.k' 2>/dev/null)
    if [ "$k" = "$A_TEXT" ]; then echo 0
    elif grep -Fq "$MARK" <<< "$k"; then echo 1
    else echo '?'; fi
}
b2_rcl_outcome() {  # правка механизма ДО X: X начал ход → исхода в ходе нет (1); не начал → «починка механизма» (0)
    local f="$T/rclo-$1.jsonl" c="$T/rclo-$1.ctl" e
    e=$(jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"o1",name:"Edit",
        input:{file_path:"hooks/zz-mech.sh",new_string:"x"}}]}}')
    { rr_reply "$A_TEXT"; printf '%s\n' "$e"; rr_x "$1"; rr_said "Дальше."; } > "$f"
    { rr_reply "$A_TEXT"; printf '%s\n' "$e"; rr_said "Дальше."; } > "$c"
    b2_rcl_out "$c" || { echo '?'; return; }                   # контроль: без X правка механизма — исход хода
    if b2_rcl_out "$f"; then echo 0; else echo 1; fi
}
b2_rcl_out() { fresh; grep -Fq 'починка механизма' <<< "$(bash -c '. "$1/root-cause-lib.sh"; rc_outcome_observed "$2"' _ "$HOOKS" "$1" 2>/dev/null)"; }

drv_hooks_five_whys_gate_sh() {  # ключ хода в журнале срабатываний five-whys-<SID>.seen: «turn:<cksum>|…»
    [ "$1" = P ] && { echo -; return; }
    local f="$T/fwg-$1.jsonl" g="$T/fwg-$1-ctl.jsonl" kx ka
    { rr_reply "$A_TEXT"; rr_said "Сделал."; rr_x "$1"; rr_said "Дальше."; } > "$f"
    { rr_reply "$A_TEXT"; rr_said "Сделал."; rr_said "Дальше."; } > "$g"
    ka=$(b2_cksum "$A_TEXT")
    kx=$(b2_fwg_key "$f")
    [ "$(b2_fwg_key "$g")" = "$ka" ] || { echo '?'; return; }   # контроль: без X ключ хода — реплика A
    case "$kx" in ''|*[!0-9]*) echo '?'; return ;; esac
    if [ "$kx" = "$ka" ]; then echo 0; else echo 1; fi
}
b2_fwg_key() {  # b2_fwg_key <расшифровка> → ключ хода из журнала стража при повторе-сигнале (поправка в состоянии)
    fresh
    printf '%s\n' '{"date":"2026-01-01T00:00:00Z","hash":"x","snippet":"s"}' > "$STATE_DIR/correction-fired-s-fw.jsonl"
    jq -nc --arg p "$1" --arg c "$T" '{hook_event_name:"PreToolUse",session_id:"s-fw",transcript_path:$p,cwd:$c,tool_name:"Bash",tool_input:{command:"ls"}}' \
        | (cd "$T" && HOME="$T/home" bash "$HOOKS/five-whys-gate.sh") >/dev/null 2>&1
    grep -o '^turn:[0-9]*' "$STATE_DIR/five-whys-s-fw.seen" 2>/dev/null | head -1 | cut -d: -f2
}

drv_hooks_session_collector_sh() {  # свод на Stop: долг «реестр носителей» судит текст ХОДА (rc_turn_text); след — журнал class-registry-fired
    [ "$1" = P ] && { echo -; return; }
    local f="$T/sc-$1.jsonl" n c
    scan_case "$1" "$f" "Это тот же класс дефектов." "Дальше."
    b2_sc_run "$f"; n=$(lines "$STATE_DIR/class-registry-fired-s-sc.jsonl")
    b2_sc_run "$f.ctl"; c=$(lines "$STATE_DIR/class-registry-fired-s-sc.jsonl")
    scan_verdict "$n" "$c"
}
b2_sc_run() {  # b2_sc_run <расшифровка> — настоящий хук в изолированном мире: HOME, корень проекта и состояние под $T
    fresh; mkdir -p "$T/home" "$T/scroot/scripts"
    [ -f "$T/scroot/scripts/signal-precision-corpus.py" ] || cp "$HOOKS/../scripts/signal-precision-corpus.py" "$T/scroot/scripts/"
    [ -e "$T/scroot/hooks" ] || ln -s "$HOOKS" "$T/scroot/hooks"
    stop_input s-sc "$1" | (cd "$T" && env HOME="$T/home" CLAUDSOUL_ROOT="$T/scroot" CLAUDSOUL_REPO="$T/scroot" PYTHONDONTWRITEBYTECODE=1 \
        CLAUDE_CODE_SESSION_ID=b2sc bash "$HOOKS/session-collector.sh") >/dev/null 2>&1
}

drv_hooks_publish_guard_sh() {  # публикация --push отбивается, если в ХОДЕ нет сухого прогона: сухой прогон ДО X
    [ "$1" = P ] && { echo -; return; }
    local f="$T/pg-$1.jsonl" a b n
    { rr_reply "$A_TEXT"; b2_bash "bash scripts/publish-public.sh"; rr_x "$1"; rr_said "Дальше."; } > "$f"
    { rr_reply "$A_TEXT"; rr_x "$1"; b2_bash "bash scripts/publish-public.sh"; } > "$f.ctl"     # сухой прогон после X — виден всегда
    { rr_reply "$A_TEXT"; rr_x "$1"; rr_said "Дальше."; } > "$f.none"                           # сухого прогона нет — отказ обязан быть
    a=$(b2_pg_deny "$f"); b=$(b2_pg_deny "$f.ctl"); n=$(b2_pg_deny "$f.none")
    [ "$b" = 0 ] && [ "$n" = 1 ] || { echo '?'; return; }
    echo "$a"
}
b2_pg_deny() {  # 1 — страж отбил, 0 — пропустил
    local out
    out=$(jq -nc --arg p "$1" '{hook_event_name:"PreToolUse",session_id:"s-pg",transcript_path:$p,tool_name:"Bash",tool_input:{command:"bash scripts/publish-public.sh --push"}}' \
        | (cd "$T" && HOME="$T/home" bash "$HOOKS/publish-guard.sh") 2>/dev/null)
    if grep -Fq '"permissionDecision": "deny"' <<< "$out" || grep -Fq '"permissionDecision":"deny"' <<< "$out"; then echo 1; else echo 0; fi
}

# Страж поправок читает реплику двумя путями, а образец «правка, затем реплика» — своим (D1202): последнюю реплику —
# помощником окна (`transcript_user_texts … 1` режет окно по `is_owner_speech`) либо без него разбором всего файла;
# образец — быстрым путём `_is_reply_any` либо запасным jq. Наблюдаются все четыре, ответ — общий; разошлись — «≠».
# Без помощника — библиотека реплик ссылкой из каталога без `lib/`: её `_HIL_DIR` — каталог ссылки (`pwd`).
drv_hooks_user_correction_guard_sh() {
    [ "$1" = P ] && { echo -; return; }
    local nh="$T/ucg-nohelper"
    [ -e "$nh/hook-input-lib.sh" ] || { mkdir -p "$nh"; ln -s "$HOOKS/hook-input-lib.sh" "$nh/hook-input-lib.sh"; }
    b2_join "$(b2_ucg_said "$1")" "$(b2_ucg_eh "$1")" \
        "$(INPUT_LIB="$nh/hook-input-lib.sh" b2_ucg_said "$1")" "$(INPUT_LIB="$nh/hook-input-lib.sh" b2_ucg_eh "$1")"
}
b2_join() {  # b2_join <ответ пути>… → общий ответ; «?» — какой-то путь не наблюдён; «≠» — пути разошлись
    local a; for a; do [ "$a" = '?' ] && { echo '?'; return; }; done
    for a; do [ "$a" = "$1" ] || { echo '≠'; return; }; done
    echo "$1"
}
# Контроли от случая не зависят — снимаются раз за прогон свидетеля на путь (страж поправок — самый дорогой драйвер).
b2_ucg_said() {  # какая реплика взята речью: поправка в X (со словарём поправок) попала в snippet стража
    local f="$T/ucg-$1${INPUT_LIB:+-nh}.jsonl" c="$T/ucg-ctl${INPUT_LIB:+-nh}" out
    local fix="Стоп, подожди, ты опять сделал не то $MARK"
    if [ ! -f "$c.res" ]; then   # контроль: на реплике-поправке страж отзывается
        { rr_reply "Стоп, подожди, ты опять сделал не то"; rr_said "Сделал."; rr_said "Дальше."; } > "$c.jsonl"
        if grep -Fq "ты опять сделал не то" <<< "$(b2_ucg "$c.jsonl")"; then echo 1 > "$c.res"; else echo 0 > "$c.res"; fi
    fi
    [ "$(cat "$c.res")" = 1 ] || { echo '?'; return; }
    { rr_reply "$A_TEXT"; rr_said "Сделал."; rr_x "$1" "$fix"; rr_said "Дальше."; } > "$f"
    out=$(b2_ucg "$f")
    if grep -Fq "$MARK" <<< "$out"; then echo 1; else echo 0; fi
}
b2_ucg_eh() {  # образец «правка, затем реплика»: правка страницы, X, повторная правка — X реплика, если страж назвал образец
    local f="$T/ucg-eh-$1${INPUT_LIB:+-nh}.jsonl" c="$T/ucg-eh-ctl${INPUT_LIB:+-nh}" e x="добавь подпись под картинкой $MARK"
    local hit='Ты правишь файл, который уже правил'
    e=$(jq -nc --arg f "$T/ucg-page.html" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"e1",
        name:"Edit",input:{file_path:$f}}]}}')
    if [ ! -f "$c.res" ]; then   # контроль: реплика после правки — образец есть
        { rr_reply "$A_TEXT"; printf '%s\n' "$e"; rr_reply "$x"; rr_said "Дальше."; } > "$c.jsonl"
        if grep -Fq "$hit" <<< "$(b2_ucg "$c.jsonl")"; then echo 1 > "$c.res"; else echo 0 > "$c.res"; fi
    fi
    [ "$(cat "$c.res")" = 1 ] || { echo '?'; return; }
    { rr_reply "$A_TEXT"; printf '%s\n' "$e"; rr_x "$1" "$x"; rr_said "Дальше."; } > "$f"
    if grep -Fq "$hit" <<< "$(b2_ucg "$f")"; then echo 1; else echo 0; fi
}
b2_ucg() {  # b2_ucg <расшифровка> → текст отзыва стража (snippet реплики); INPUT_LIB окружения — библиотека реплик
    fresh
    jq -nc --arg p "$1" --arg f "$T/ucg-page.html" '{session_id:"s-uc",transcript_path:$p,tool_name:"Edit",
        tool_input:{file_path:$f,old_string:"a",new_string:"b"},hook_event_name:"PreToolUse"}' \
        | (cd "$T" && HOME="$T/home" bash "$HOOKS/user-correction-guard.sh") 2>/dev/null
}

drv_hooks_activity_flush_lib_sh() {  # журнал активности: реплика X записана — читатель считает её речью
    [ "$1" = P ] && { echo -; return; }
    local f="$T/af-$1.jsonl" d="$T/af-cwd-$1" act
    { rr_reply "$A_TEXT"; b2_bash "ls"; rr_x "$1"; rr_said "Дальше."; } > "$f"
    fresh; mkdir -p "$d"
    HOME="$T/home" bash -c '. "$1/activity-flush-lib.sh"; activity_flush s-af-abcdefgh "$2" "$3"' _ "$HOOKS" "$f" "$d" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_reply_readers_behavior.sh:$LINENO" >&2; exit 1; }
    act=$(cat "$d/.claude-docs/session-activity.md" 2>/dev/null)
    grep -Fq "$A_TEXT" <<< "$act" || { echo '?'; return; }
    if grep -Fq "$MARK" <<< "$act"; then echo 1; else echo 0; fi
}

# B3 — драйверы: стражи PreToolUse (bulk-copy-guard, trust-guard, internal-doc-leak-guard) и детектор подачи (itr-event-detector).
# Вставляется свидетелем перед судьёй; пользуется его фикстурами rr_reply, rr_said, rr_x, fresh, A_TEXT, $T, $STATE_DIR.

# Страж PreToolUse: решение зависит от разрешения владельца в окне последних реплик. Три прогона:
#   база  — нет слова разрешения нигде: страж обязан спросить (ask), иначе «?»;
#   конт. — то же слово в реплике A (без X): страж обязан промолчать, иначе «?»;
#   опыт  — слово только в X (A, текст агента, X, текст агента): молчит — X прочитан как реплика (1), спрашивает — нет (0).
# b3_guard <хук> <слово разрешения> <ввод хука json> <Q|S1|S2>
b3_ask() {  # b3_ask <хук> <ввод> <файл расшифровки> → число «ask» в выводе
    local o
    fresh
    o=$(jq -nc --arg p "$3" "$2"' + {session_id:"s-b3",transcript_path:$p,hook_event_name:"PreToolUse"}' \
        | bash "$HOOKS/$1" 2>/dev/null)
    grep -c 'permissionDecision\|additionalContext' <<< "$o" || true
}
b3_guard() {
    local hook="$1" word="$2" input="$3" k="$4" f g b c x; f="$T/b3-$k-${hook%.sh}"; g="$T/b3-ctl-${hook%.sh}"
    # Контроли от случая не зависят — снимаются раз за прогон свидетеля (цена: три запуска стража на случай вместо одного).
    if [ ! -f "$g.res" ]; then
        { rr_reply "$A_TEXT"; rr_said "Сделал."; } > "$g.base"
        { rr_reply "$word"; rr_said "Сделал."; } > "$g.ctl"
        printf '%s %s\n' "$(b3_ask "$hook" "$input" "$g.base")" "$(b3_ask "$hook" "$input" "$g.ctl")" > "$g.res"
    fi
    read -r b c < "$g.res"
    { rr_reply "$A_TEXT"; rr_said "Сделал."; rr_x "$k" "$word"; rr_said "Дальше."; } > "$f.x"
    x=$(b3_ask "$hook" "$input" "$f.x")
    [ "$b" -ge 1 ] 2>/dev/null && [ "$c" = 0 ] || { echo '?'; return; }
    if [ "$x" = 0 ]; then echo 1; else echo 0; fi
}

drv_hooks_bulk_copy_guard_sh() {
    [ "$1" = P ] && { echo -; return; }
    b3_guard bulk-copy-guard.sh 'копируй всё' \
        '{tool_name:"Bash",tool_input:{command:"cp -r /tmp/zzb3src /tmp/zzb3dst"}}' "$1"
}

drv_hooks_trust_guard_sh() {
    [ "$1" = P ] && { echo -; return; }
    b3_guard trust-guard.sh 'да, снеси' \
        '{tool_name:"Bash",tool_input:{command:"git branch -D zzb3branch"}}' "$1"
}

drv_hooks_internal_doc_leak_guard_sh() {
    [ "$1" = P ] && { echo -; return; }
    b3_guard internal-doc-leak-guard.sh 'отправь как есть' \
        '{tool_name:"Write",tool_input:{file_path:"/tmp/zzb3/Lawyer/note.md",content:"TODO: проверить"}}' "$1"
}

# Детектор подачи: прежняя реплика prior_user наблюдается по причине записанного события. Ход агента правит файл (Edit);
# прежняя реплика — поручение → событие «solicited» (причина «prior:Edit»), иначе «proactive».
#   база  — A и подача нейтральны: «proactive», иначе «?»; конт. — A поручение, X нет: «solicited», иначе «?».
#   опыт  — Q/S1/S2: A нейтральна, X поручение после ответа агента с правкой, подача нейтральна; «solicited» — X взята
#           прежней (1), «proactive» — нет (0).
#   P     — A поручение, ответ с правкой, X — вопрос после последнего ответа, подача совпадает с X. X не взята (прежняя — A)
#           → «solicited» (0); взята → после неё в ходе пусто и события нет (1). Что «события нет» и есть вид «X взята»,
#           доказывает контроль: та же расшифровка с другой подачей (X — прежняя по любому понятию) обязана дать «нет».
#           Подача-поручение здесь не годится: она сама включает авторизацию, и причина события меняется (мутант D1149 m4).
b3_edit() { jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Готово."},{type:"tool_use",id:"t1",name:"Edit",input:{}}]}}'; }
b3_itr() {  # b3_itr <файл> <подача> → solicited | proactive | пусто
    fresh
    jq -nc --arg p "$2" --arg t "$1" '{hook_event_name:"UserPromptSubmit",session_id:"s-b3i",transcript_path:$t,prompt:$p}' \
        | bash "$HOOKS/itr-event-detector.sh" >/dev/null 2>&1
    local r; r=$(cat "$STATE_DIR"/* 2>/dev/null | grep -o '"reason": *"[^"]*"' | head -1)
    case "$r" in *prior:Edit*) echo solicited ;; *"proactive:"*) echo proactive ;; *) echo none ;; esac
}
drv_hooks_itr_event_detector_sh() {
    local N='что там с погодой?' W="$A_TEXT" f="$T/b3-itr-$1" g="$T/b3-itr-ctl" base ctl x
    # Контроли от случая не зависят — снимаются раз за прогон свидетеля (детектор — самый дорогой читатель пробы D1149).
    if [ ! -f "$g.res" ]; then
        { rr_reply "$N"; b3_edit; } > "$g.base"
        { rr_reply "$W"; b3_edit; } > "$g.ctl"
        printf '%s %s\n' "$(b3_itr "$g.base" 'ок')" "$(b3_itr "$g.ctl" 'ок')" > "$g.res"
    fi
    read -r base ctl < "$g.res"
    [ "$base" = proactive ] && [ "$ctl" = solicited ] || { echo '?'; return; }
    if [ "$1" = P ] || [ "$1" = Ps ]; then
        { rr_reply "$W"; b3_edit; rr_x "$1" "$N"; } > "$f.x"
        [ "$(b3_itr "$f.x" 'а дальше что?')" = none ] || { echo '?'; return; }
        case "$(b3_itr "$f.x" "$N")" in solicited) echo 0 ;; none) echo 1 ;; *) echo '?' ;; esac
        return
    fi
    { rr_reply "$N"; b3_edit; rr_x "$1" "$W"; b3_edit; } > "$f.x"; x=$(b3_itr "$f.x" 'ок')
    case "$x" in solicited) echo 1 ;; proactive) echo 0 ;; *) echo '?' ;; esac
}

# B4: читатели-замеры над корпусом расшифровок (границу хода ставит сам читатель).
# Общий ход: A -> агент "до" -> X -> агент "после". Корпус — только под $T.

b4_py() { env -i PATH="$PATH" HOME="$T/home" TMPDIR="$TMPDIR" STATE_DIR="$STATE_DIR" PYTHONDONTWRITEBYTECODE=1 "$@"; }

# b4_dir <метка> — свежий каталог корпуса под $T (старое не удаляем: имя уникально по метке)
b4_dir() { local d="$T/b4-$1"; mkdir -p "$d" "$T/home"; echo "$d"; }

# --- scripts/five-whys-attribution-replay.py: "ходов с напоминанием и ответом агента: N".
# Ход: A, напоминание гейта, X, ответ агента. X делит -> напоминание и ответ в разных ходах -> 0 ходов;
# не делит -> 1 ход. Контроль: тот же ход без X даёт 1 (замер вообще считает).
b4_fw_reminder() { jq -nc '{type:"attachment",attachment:{type:"hook_additional_context",content:["🔁 Признак повторяется (повторные заходы на один файл (a.md)), а разбора причин в этом ходе не было."]}}'; }
b4_fw_seen() {  # b4_fw_seen <каталог> → число или пусто
    b4_py env FWG_REPLAY_CORPUS="$1/*.jsonl" python3 "$R/scripts/five-whys-attribution-replay.py" 2>/dev/null \
        | sed -n 's/^ходов с напоминанием и ответом агента: \([0-9][0-9]*\).*/\1/p' | head -1
}
drv_scripts_five_whys_attribution_replay_py() {
    [ "$1" = P ] && { echo -; return; }
    local d c n k
    d=$(b4_dir "fw-$1"); c=$(b4_dir "fwc-$1")
    { rr_reply "$A_TEXT"; b4_fw_reminder; rr_x "$1"; rr_said "Правлю файл."; } > "$d/c.jsonl"
    { rr_reply "$A_TEXT"; b4_fw_reminder; rr_said "Правлю файл."; } > "$c/c.jsonl"
    k=$(b4_fw_seen "$c"); [ "$k" = 1 ] || { echo '?'; return; }
    n=$(b4_fw_seen "$d")
    case "$n" in 0) echo 1 ;; 1) echo 0 ;; *) echo '?' ;; esac
}

# --- scripts/signal-precision-corpus.py: turn_texts(files=[…]) отдаёт текст агента по ходам.
# X делит -> два хода ("до", "после"); не делит -> один "до\nпосле". Контроль: без X один ход с обоими.
b4_spc_turns() {  # b4_spc_turns <файл> → ходы через «|»
    b4_py env CORPUS_DIR="$T/b4-none" python3 - "$R/scripts/signal-precision-corpus.py" "$1" <<'PY' 2>/dev/null
import importlib.util, sys
spec = importlib.util.spec_from_file_location("spc", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print("|".join(t.replace("\n", "+") for _f, t in m.turn_texts(files=[sys.argv[2]])))
PY
}
drv_scripts_signal_precision_corpus_py() {
    [ "$1" = P ] && { echo -; return; }
    local d f c o k
    d=$(b4_dir "sp-$1"); f="$d/c.jsonl"; c="$d/ctl.jsonl"
    { rr_reply "$A_TEXT"; rr_said "до"; rr_x "$1"; rr_said "после"; } > "$f"
    { rr_reply "$A_TEXT"; rr_said "до"; rr_said "после"; } > "$c"
    k=$(b4_spc_turns "$c"); [ "$k" = "до+после" ] || { echo '?'; return; }
    o=$(b4_spc_turns "$f")
    case "$o" in "до|после") echo 1 ;; "до+после") echo 0 ;; *) echo '?' ;; esac
}

# --- scripts/self-repeat-replay.py: маркер повтора сказан ДО X, цепочка разбора — ПОСЛЕ X.
# Цепочка ищется от произнесения до конца хода: X не делит -> «без разбора» 0; делит -> 1.
# Отрицательный контроль по форме инструмента: тот же ход без X обязан дать произнесений 1, без разбора 0.
B4_SR_MARK='Это третий раз за день, когда тест падает на той же строке. Чиню.'
B4_SR_CHAIN='Почему падает — читается старый индекс (mcp-server/indexer.py:231). Почему старый — add шёл после. Почему не поймали — тест брал фикстуру.'
b4_sr_counts() {  # b4_sr_counts <каталог> → "N NO" (суммы по двум строкам) или пусто
    b4_py env FWG_REPLAY_CORPUS="$1/*.jsonl" python3 "$R/scripts/self-repeat-replay.py" 2>/dev/null \
        | sed -n 's/.*произнесений \([0-9][0-9]*\), без разбора в том же ходе \([0-9][0-9]*\).*/\1 \2/p' \
        | awk '{n+=$1; no+=$2; r=1} END{if(r) print n, no}'
}
drv_scripts_self_repeat_replay_py() {
    [ "$1" = P ] && { echo -; return; }
    local d c k o
    d=$(b4_dir "sr-$1"); c=$(b4_dir "src-$1")
    { rr_reply "$A_TEXT"; rr_said "$B4_SR_MARK"; rr_x "$1"; rr_said "$B4_SR_CHAIN"; } > "$d/c.jsonl"
    { rr_reply "$A_TEXT"; rr_said "$B4_SR_MARK"; rr_said "$B4_SR_CHAIN"; } > "$c/c.jsonl"
    k=$(b4_sr_counts "$c"); [ "$k" = "1 0" ] || { echo '?'; return; }
    o=$(b4_sr_counts "$d")
    case "$o" in "1 1") echo 1 ;; "1 0") echo 0 ;; *) echo '?' ;; esac
}

# --- scripts/stopper-effect.sh: речь после отказа считается до следующей реплики владельца (is_owner_reply).
# Ход: A, вызов, отказ гейта разбора, X, цепочка. X делит -> «обойдено без цепочки» 1; не делит -> «цепочка произнесена» 1.
# Контроль: без X цепочка произнесена 1, обойдено 0.
b4_se_denial() { jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",is_error:true,content:"⛔ ОТКАЗ (вызов не выполнен): нужна цепочка причин"}]}}'; }
b4_se_out() {  # b4_se_out <каталог> → "произнесена обойдено"
    b4_py env STOPPER_TRANSCRIPT_DIR="$1" bash "$R/scripts/stopper-effect.sh" 2>/dev/null | awk '
        /цепочка произнесена:/ { sub(/.*произнесена: */, ""); ok=$1+0; r=1 }
        /обойдено без цепочки:/ { sub(/.*цепочки: */, ""); by=$1+0 }
        END { if (r) print ok, by }'
}
drv_scripts_stopper_effect_sh() {
    [ "$1" = P ] && { echo -; return; }
    local d c k o
    d=$(b4_dir "se-$1"); c=$(b4_dir "sec-$1")
    { rr_reply "$A_TEXT"; rr_said "Пишу."; b4_se_denial; rr_x "$1"; rr_said "$B4_SR_CHAIN"; } > "$d/c.jsonl"
    { rr_reply "$A_TEXT"; rr_said "Пишу."; b4_se_denial; rr_said "$B4_SR_CHAIN"; } > "$c/c.jsonl"
    k=$(b4_se_out "$c"); [ "$k" = "1 0" ] || { echo '?'; return; }
    o=$(b4_se_out "$d")
    case "$o" in "0 1") echo 1 ;; "1 0") echo 0 ;; *) echo '?' ;; esac
}

# --- B5: читатели речи — воркер реплея и три замера на корпусе ----------------------------------------------------------
# b5_py <скрипт> <тег> <A-текст> <X-текст|""> <Q|S1|S2> → вывод замера. Свой HOME под $T: замер читает ~/.claude/projects.
b5_py() {
    local sc="$1" tag="$2" at="$3" xt="$4" k="$5" h="$T/b5-$2/home"
    mkdir -p "$h/.claude/projects/p"
    { rr_reply "$at"; rr_said "Сделал."; [ -n "$xt" ] && rr_x "$k" "$xt"; rr_said "Дальше."; } > "$h/.claude/projects/p/s.jsonl"
    HOME="$h" PYTHONDONTWRITEBYTECODE=1 python3 "$R/scripts/$sc" 2>/dev/null
}
# b5_count <скрипт> <тег> <A> <X> <вид> <фраза-перед-числом> → число
b5_count() {
    b5_py "$1" "$2" "$3" "$4" "$5" | sed -n "s/^$6[^0-9]*\([0-9][0-9]*\).*/\1/p" | head -1
}
# b5_judge <скрипт> <тег> <A> <X> <вид> <фраза>: контроль — A один даёт >=1; X взят, если с X счёт больше.
b5_judge() {
    local base with
    base=$(b5_count "$1" "$2-c" "$3" "" "$5" "$6")
    [ "${base:-0}" -ge 1 ] 2>/dev/null || { echo '?'; return; }
    with=$(b5_count "$1" "$2-x" "$3" "$4" "$5" "$6")
    [ -n "$with" ] || { echo '?'; return; }
    if [ "$with" -gt "$base" ]; then echo 1; else echo 0; fi
}

drv_scripts_colon_lead_in_count_py() {  # счёт реплик с зачином-двоеточием; X — вторая такая реплика
    [ "$1" = P ] && { echo -; return; }
    b5_judge colon-lead-in-count.py "cl-$1" $'Задача:\nсделай заголовок синим' $'МЕТКА-ИКС:\nвторая строка' "$1" 'реплик с зачином-двоеточием'
}

drv_scripts_authorization_replay_py() {  # «реплик собеседника в корпусе»; текст X без <task-notification>, чтобы судил только владелец
    [ "$1" = P ] && { echo -; return; }
    b5_judge authorization-replay.py "ar-$1" "$A_TEXT" "$MARK" "$1" 'реплик собеседника в корпусе'
}

drv_scripts_question_survival_py() {  # «реплик собеседника в корпусе»
    [ "$1" = P ] && { echo -; return; }
    b5_judge question-survival.py "qs-$1" "$A_TEXT" "$MARK" "$1" 'реплик собеседника в корпусе'
}

drv_hooks_lib_backfill_replay_one_sh() {  # воркер: какие реплики он подаёт детектору. Детектор — заглушка, пишет prompt в $T
    [ "$1" = P ] && { echo -; return; }
    local d="$T/b5-bf-$1" f seen
    mkdir -p "$d/h/lib" "$d/tmp"
    ln -sf "$HOOKS/lib/backfill-replay-one.sh" "$d/h/lib/backfill-replay-one.sh"
    ln -sf "$HOOKS/hook-input-lib.sh" "$d/h/hook-input-lib.sh"
    seen="$d/seen"; : > "$seen"
    printf '#!/usr/bin/env bash\njq -r .prompt >> "%s"\n' "$seen" > "$d/h/itr-event-detector.sh"
    f="$d/t.jsonl"
    { rr_reply "первая"; rr_said "Сделал."; rr_reply "$A_TEXT"; rr_said "Сделал."; rr_x "$1"; rr_said "Дальше."; } > "$f"
    BACKFILL_TMP="$d/tmp" bash "$d/h/lib/backfill-replay-one.sh" "$f" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_reply_readers_behavior.sh:$LINENO" >&2; exit 1; }
    grep -Fq "$A_TEXT" "$seen" || { echo '?'; return; }
    if grep -Fq "$MARK" "$seen"; then echo 1; else echo 0; fi
}

# --- Судья ------------------------------------------------------------------------------------------------------------
sig_ok() {  # sig_ok <понятие> <Q> <S1> <S2> <P>
    case "$1" in
        граница-узкая)   [ "$2$3$4" = 000 ] ;;
        граница-широкая) [ "$2$3$4" = 011 ] ;;
        граница-без-сводки) [ "$2$3$4" = 001 ] ;;
        речь)          [ "$2$3$4" = 100 ] && { [ "$5" = - ] || [ "$5" = 1 ]; } ;;
        до-текущей)      [ "$2$3$4" = 100 ] && [ "$5" = 0 ] ;;
        *) return 1 ;;
    esac
}
nearest() {  # какое понятие наблюдено
    case "$1$2$3" in
        000) echo граница-узкая ;; 011) echo граница-широкая ;; 001) echo граница-без-сводки ;;
        100) if [ "$4" = 0 ]; then echo до-текущей; else echo речь; fi ;;
        *) echo "вне словаря" ;;
    esac
}
rr_want() {  # rr_want <понятие> → ответы на M Sc Qn U0 Qp; «-» — не судится
    # Служебная запись, уведомление вложением и вложение-реплика от не-человека — не реплика и не граница ни одному
    # понятию; реплика без автора — реплика и граница всем. Боковая ветка у границ не судится: в мире её записи до читателей границы не доходят (0 из 412
    # основных расшифровок, хук получает расшифровку родителя), правило `turn_user` её не называет, а свои добавки
    # `timestamp-canary-check.sh:90` и `five-whys-attribution-replay.py:98` её исключают (решение при взятии D1202).
    # Реплика без автора у канарейки («граница-без-сводки») не судится: её окно шапки открывает инжект реплики.
    case "$1" in
        граница-широкая) echo "0 - 0 1 0" ;;
        граница-без-сводки) echo "0 - 0 - 0" ;;
        *) echo "0 0 0 1 0" ;;
    esac
}
fnname() { local p="$1"; printf 'drv_%s' "${p//[^A-Za-z0-9]/_}"; }

PASS=0; FAIL=0
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
listed=" "
while IFS=$'\t' read -r p concept _; do
    case "$p" in ''|'#'*) continue ;; esac
    listed="$listed$p "
    [ -z "$ONLY" ] || case "$ONLY" in *",$p,"*) ;; *) continue ;; esac
    fn=$(fnname "$p")
    case "$concept" in
        источник) continue ;;
        не-реплика)
            if declare -F "$fn" >/dev/null; then bad "$p: объявлен не-репликой, а драйвер реплики у него есть"; else PASS=$((PASS + 1)); fi
            continue ;;
    esac
    declare -F "$fn" >/dev/null || { bad "$p: понятие «${concept}», а драйвера нет — понятие не сверено с поведением"; continue; }
    # Память наблюдений `REPLY_READERS_OBS` (файл «путь<TAB>наблюдение») — для пробы, судящей один и тот же читатель
    # под несколькими реестрами: драйвер детерминирован, и повторный прогон дал бы то же, удвоив цену.
    obs=$(awk -F'\t' -v p="$p" '$1 == p { print $2; exit }' "${REPLY_READERS_OBS:-/dev/null}" 2>/dev/null)
    if [ -z "$obs" ]; then
        _p=$("$fn" P); if [ "$_p" = - ]; then _ps=-; else _ps=$("$fn" Ps); fi   # Ps — только у читателя подачи
        obs="Q=$("$fn" Q) S1=$("$fn" S1) S2=$("$fn" S2) S1w=$("$fn" S1w) S2w=$("$fn" S2w) Qs=$("$fn" Qs) P=$_p Ps=$_ps"
        obs="$obs M=$("$fn" M) Sc=$("$fn" Sc) Qn=$("$fn" Qn) U0=$("$fn" U0) Q0=$("$fn" Q0) Qp=$("$fn" Qp)"
        [ -z "${REPLY_READERS_OBS:-}" ] || printf '%s\t%s\n' "$p" "$obs" >> "$REPLY_READERS_OBS"
    fi
    case "$obs" in *≠*) bad "$p: объявлено «${concept}», пути читателя расходятся ($obs)"; continue ;; esac
    q=${obs#Q=}; q=${q%% *}; s1=${obs#*S1=}; s1=${s1%% *}; s2=${obs#*S2=}; s2=${s2%% *}; pp=${obs#*P=}; pp=${pp%% *}; ps=${obs#*Ps=}; ps=${ps%% *}
    s1w=${obs#*S1w=}; s1w=${s1w%% *}; s2w=${obs#*S2w=}; s2w=${s2w%% *}; qs=${obs#*Qs=}; qs=${qs%% *}
    m=${obs#*M=}; m=${m%% *}; sc=${obs#*Sc=}; sc=${sc%% *}; qn=${obs#*Qn=}; qn=${qn%% *}; u0=${obs#*U0=}; u0=${u0%% *}
    q0=${obs#*Q0=}; q0=${q0%% *}; qp=${obs#*Qp=}; qp=${qp%% *}
    case "$q|$s1|$s2|$s1w|$s2w|$qs|$m|$qn|$q0|$qp|$sc|$u0" in
        [01]\|[01]\|[01]\|[01]\|[01]\|[01]\|[01]\|[01]\|[01]\|[01]\|[01-]\|[01-]) ;; *) bad "$p: не измерено ($obs)"; continue ;; esac
    [ "$s1w|$s2w|$qs" = "$s1|$s2|$q" ] || { bad "$p: форма текста меняет ответ — понятие решает не поле ($obs)"; continue; }
    case "$pp|$ps" in [01-]\|[01-]) ;; *) bad "$p: не измерено ($obs)"; continue ;; esac
    [ "$ps" = "$pp" ] || { bad "$p: форма текста меняет ответ — понятие решает не поле ($obs)"; continue; }
    sig_ok "$concept" "$q" "$s1" "$s2" "$pp" || { bad "$p: объявлено «${concept}», наблюдено «$(nearest "$q" "$s1" "$s2" "$pp")» ($obs)"; continue; }
    # Вложение-реплика без поля автора — та же реплика посреди хода: ответ обязан совпасть с Q (автор не задан — человек).
    [ "$q0" = "$q" ] || { bad "$p: объявлено «${concept}», реплика посреди хода без поля автора читается иначе (Q0=${q0} при Q=${q}) ($obs)"; continue; }
    want=$(rr_want "$concept"); read -r _ w_sc _ w_u0 _ <<< "$want"   # «-» в ожидании — разряд не судится
    [ "$w_sc" != - ] || sc=-; [ "$w_u0" != - ] || u0=-
    if [ "$m $sc $qn $u0 $qp" = "$want" ]; then
        PASS=$((PASS + 1)); echo "ok: $p — ${concept} ($obs)"
    else
        bad "$p: объявлено «${concept}», на записях M Sc Qn U0 Qp наблюдено «${m} ${sc} ${qn} ${u0} ${qp}», ждали «${want}» ($obs)"
    fi
done < "$REG"
# Путь из `--only` без строки реестра — опечатка либо ушедшая строка: без этого «0 из 0» читалось бы зелёным. Глоб
# выключен: путь со звёздочкой или скобками раскрывался в существующий файл и проходил сверку (скептик D1149, круг 2).
set -f
for p in $(printf '%s' "${ONLY#,}" | tr ',' ' '); do
    case "$listed" in *" $p "*) ;; *) bad "$p: назван в --only, а строки реестра нет" ;; esac
done
set +f
# Ни одной судимой строки по `--only` («,», «,,», только «источник») — судить было нечего, это не зелёное.
[ -z "$ONLY" ] || [ $((PASS + FAIL)) -gt 0 ] || bad "по --only не судилась ни одна строка"
# Драйвер без строки реестра — читатель, о котором реестр не знает, либо строка ушла, а драйвер остался.
if [ -z "$ONLY" ]; then
    for fn in $(declare -F | awk '$3 ~ /^drv_/ {print $3}'); do
        found=0
        for p in $listed; do [ "$(fnname "$p")" = "$fn" ] && { found=1; break; }; done
        [ "$found" -eq 1 ] || bad "$fn: драйвер без строки реестра"
    done
fi
echo "test_reply_readers_behavior: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
