#!/usr/bin/env bash
# test_code_review_reminder.sh — тест стража крупного дифа перед коммитом.
#
# Главное, что здесь доказывается помимо порогов: детект уже состоявшегося
# адверсариального прогона считает ВЫЗОВ инструмента, а не упоминание имени
# скилла в разговоре. Без отрицательного контроля (T8) зелёный T7 не отличить
# от «молчит на любой транскрипт, где встретилось слово».
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/code-review-reminder.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }

assert_contains() { if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет '$2' в '${1:0:120}'"; fi; }
assert_empty()    { if [ -z "$1" ] || [ "$1" = "{}" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалось пусто, '${1:0:120}'"; fi; }

new_repo() {
    local r="$1"; rm -rf "$r"; mkdir -p "$r"
    git -C "$r" init -q 2>/dev/null
    git -C "$r" config user.email t@e; git -C "$r" config user.name t
    echo seed > "$r/seed.txt"; git -C "$r" add . >/dev/null 2>&1
    git -C "$r" commit -q -m seed 2>/dev/null
}

big_repo() {  # репозиторий с крупным кодовым дифом в индексе
    local r="$1"; new_repo "$r"
    local i; for i in 1 2 3 4 5 6; do seq 1 30 > "$r/f$i.py"; done
    git -C "$r" add . >/dev/null 2>&1
}

run_hook() {  # $1 = cwd, $2 = state subdir, $3 = session id, $4 = transcript path (опц.)
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","transcript_path":"%s","tool_input":{"command":"git commit -m x"}}' \
        "$3" "$1" "${4:-}" | env STATE_DIR="$TMP/$2" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null
}

# --- пороги ---

R1="$TMP/big"; big_repo "$R1"
OUT=$(run_hook "$R1" s1 sid-1)
assert_contains "$OUT" "Крупный кодовый дифф" "T1: крупный дифф → напоминает"

R2="$TMP/small"; new_repo "$R2"
echo "one line" > "$R2/small.py"; git -C "$R2" add . >/dev/null 2>&1
assert_empty "$(run_hook "$R2" s2 sid-2)" "T2: мелкий дифф → тишина"

R3="$TMP/docs"; new_repo "$R3"
mkdir -p "$R3/docs"; seq 1 200 > "$R3/docs/note.md"; git -C "$R3" add . >/dev/null 2>&1
assert_empty "$(run_hook "$R3" s3 sid-3)" "T3: только docs → тишина"

OUT=$(printf '{"session_id":"sid-4","tool_name":"Bash","cwd":"%s","tool_input":{"command":"ls -la"}}' "$R1" \
    | env STATE_DIR="$TMP/s4" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T4: не-коммит → тишина"

# --- throttle ---

R5="$TMP/big5"; big_repo "$R5"
assert_contains "$(run_hook "$R5" s5 sid-5)" "Крупный кодовый дифф" "T5a: первый раз напоминает"
assert_empty    "$(run_hook "$R5" s5 sid-5)" "T5b: throttle — второй раз тихо"

# --- текст: поручение, а не статус ---

R6="$TMP/big6"; big_repo "$R6"
OUT=$(run_hook "$R6" s6 sid-6)
assert_contains "$OUT" "СКАЖИ собеседнику" "T6a: текст — поручение сказать, не статус для агента"
assert_contains "$OUT" "/противник"        "T6b: зовёт противника, а не самокритику"

# --- детект состоявшегося прогона ---

TR_SKILL="$TMP/tr-skill.jsonl"
jq -cn '{message:{content:[{type:"tool_use",name:"Skill",input:{skill:"противник"}}]}}' > "$TR_SKILL"
R7="$TMP/big7"; big_repo "$R7"
assert_empty "$(run_hook "$R7" s7 sid-7 "$TR_SKILL")" "T7: прогон скиллом был → тишина"

# Отрицательный контроль: имя есть в расшифровке, но только как ТЕКСТ разговора.
# Без него T7 неотличим от «молчит на любой транскрипт со словом внутри».
TR_TALK="$TMP/tr-talk.jsonl"
jq -cn '{message:{content:[{type:"text",text:"обсуждаем скилл противник и как он устроен"},{type:"tool_use",name:"Bash",input:{command:"echo противник"}}]}}' > "$TR_TALK"
R8="$TMP/big8"; big_repo "$R8"
assert_contains "$(run_hook "$R8" s8 sid-8 "$TR_TALK")" "Крупный кодовый дифф" \
    "T8: имя лишь упомянуто в разговоре → всё равно напоминает"

# Прямой запуск субагента с промптом противника, без скилла.
TR_AGENT="$TMP/tr-agent.jsonl"
jq -cn '{message:{content:[{type:"tool_use",name:"Agent",input:{prompt:"Ты противник. Единственная цель — ДОКАЗАТЬ, что booking.py ломается."}}]}}' > "$TR_AGENT"
R9="$TMP/big9"; big_repo "$R9"
assert_empty "$(run_hook "$R9" s9 sid-9 "$TR_AGENT")" "T9: прогон субагентом был → тишина"

# Битая расшифровка не должна глушить стража.
TR_BROKEN="$TMP/tr-broken.jsonl"
printf 'не json вовсе\n{"message":{"content":' > "$TR_BROKEN"
R10="$TMP/big10"; big_repo "$R10"
assert_contains "$(run_hook "$R10" s10 sid-10 "$TR_BROKEN")" "Крупный кодовый дифф" \
    "T10: битая расшифровка → страж не глохнет"

# Путь к расшифровке указан, а файла нет.
R11="$TMP/big11"; big_repo "$R11"
assert_contains "$(run_hook "$R11" s11 sid-11 "$TMP/нет-такого.jsonl")" "Крупный кодовый дифф" \
    "T11: расшифровки нет на диске → страж не глохнет"

# Имена файлов вне ASCII: git отдаёт их в кавычках с escape-последовательностями
# ("\\321\\204….py"), и фильтр, требующий конца строки на .py, их теряет — страж
# молчит на крупном диффе. Найдено прогоном противника 2026-08-22.
R12="$TMP/big12"; new_repo "$R12"
for i in 1 2 3 4 5 6; do seq 1 30 > "$R12/файл$i.py"; done
git -C "$R12" add . >/dev/null 2>&1
assert_contains "$(run_hook "$R12" s12 sid-12)" "Крупный кодовый дифф" \
    "T12: кодовые файлы с кириллицей в имени → считаются кодом"

# Прогон через Workflow. Два разных случая: скрипт передан ТЕКСТОМ (лежит в
# расшифровке целиком) и передан ПУТЁМ (в расшифровке только путь, промпт на диске).
# Найдено 22 августа тем, что страж потребовал прогона сразу после прогона.
TR_WF="$TMP/tr-wf.jsonl"
jq -cn '{message:{content:[{type:"tool_use",name:"Workflow",input:{description:"проверка",script:"phase(\"Атака\")\nagent(\"Ты противник. Докажи, что ломается.\")"}}]}}' > "$TR_WF"
R13="$TMP/big13"; big_repo "$R13"
assert_empty "$(run_hook "$R13" s13 sid-13 "$TR_WF")" "T13: прогон через Workflow со скриптом текстом → тишина"

WF_SCRIPT="$TMP/wf-script.js"
printf 'phase("Атака")\nagent("Ты противник. Единственная цель — доказать, что ломается.")\n' > "$WF_SCRIPT"
TR_WFP="$TMP/tr-wfp.jsonl"
jq -cn --arg p "$WF_SCRIPT" '{message:{content:[{type:"tool_use",name:"Workflow",input:{description:"второй заход",scriptPath:$p}}]}}' > "$TR_WFP"
R14="$TMP/big14"; big_repo "$R14"
assert_empty "$(run_hook "$R14" s14 sid-14 "$TR_WFP")" "T14: прогон через Workflow по пути к скрипту → тишина"

# Отрицательные контроли: без них T13/T14 неотличимы от «молчит на любой Workflow».
WF_OTHER="$TMP/wf-other.js"
printf 'phase("Разведка")\nagent("Изучи конвенции репозитория.")\n' > "$WF_OTHER"
TR_WFO="$TMP/tr-wfo.jsonl"
jq -cn --arg p "$WF_OTHER" '{message:{content:[{type:"tool_use",name:"Workflow",input:{description:"разведка",scriptPath:$p}}]}}' > "$TR_WFO"
R15="$TMP/big15"; big_repo "$R15"
assert_contains "$(run_hook "$R15" s15 sid-15 "$TR_WFO")" "Крупный кодовый дифф" \
    "T15: посторонний Workflow → всё равно напоминает"

# Имя в описании вызова — это упоминание, а не запуск: описание агент пишет свободно.
TR_WFD="$TMP/tr-wfd.jsonl"
jq -cn '{message:{content:[{type:"tool_use",name:"Workflow",input:{description:"обсуждаем скилл противник",script:"agent(\"Изучи конвенции.\")"}}]}}' > "$TR_WFD"
R16="$TMP/big16"; big_repo "$R16"
assert_contains "$(run_hook "$R16" s16 sid-16 "$TR_WFD")" "Крупный кодовый дифф" \
    "T16: имя только в описании Workflow → напоминает"

echo ""
echo "code-review-reminder tests: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
