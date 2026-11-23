#!/usr/bin/env bash
# СУДИТ: hooks/code-review-outcome.sh hooks/code-review-reminder.sh hooks/lib/adversary-run-lib.sh
# test_adv_arc_mention_counts_as_run.sh — атака на adversary-run-lib.sh:56 (ветка Agent/Task).
#
# ЧТО ДОКАЗЫВАЕТСЯ. Библиотека объявляет своей границей «ВЫЗОВ, А НЕ УПОМИНАНИЕ» и ради
# этого НАМЕРЕННО не считает поле description: «его пишут свободным текстом, и
# "обсуждаем противника" стало бы ложным зачётом прогона» (шапка, строки 21-22).
#
# Поле prompt — такой же свободный текст, и правило к нему не применено: зачёт ставится
# по contains маркера где угодно внутри промпта. Субагент, которому ПОРУЧЕНО найти эту
# строку в дереве (или пересказать скилл, или разобрать чужой отчёт), считается
# состоявшимся прогоном противника.
#
# Направление ошибки — опасное, в отличие от ложного напоминания:
#  1. страж МОЛЧИТ на крупном коде, который никто не критиковал;
#  2. в журнал знаменателя идёт satisfied, и замер adversary-before-commit печатает
#     «с прогоном» там, где прогона не было. Доля «ушло без прогона» занижается, а по
#     ADR-015 именно она решает, поднимать ли уровень принуждения.
#
# Тот же зачёт разрешён и через Workflow: .input.script — тоже свободный текст, и
# скрипт, который лишь ЦИТИРУЕТ маркер (например, чтобы поискать его), закрывает стража.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/code-review-reminder.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq nedostupen";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git nedostupen"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# shellcheck source=/dev/null
. "$HOOK_DIR/lib/adversary-run-lib.sh"

big_repo() {
    local r="$1"; mkdir -p "$r"
    git -C "$r" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_mention_counts_as_run.sh:$LINENO" >&2; exit 1; }
    git -C "$r" config user.email t@e; git -C "$r" config user.name t
    echo seed > "$r/seed.txt"; git -C "$r" add . >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_mention_counts_as_run.sh:$LINENO" >&2; exit 1; }
    git -C "$r" commit -q -m seed 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_mention_counts_as_run.sh:$LINENO" >&2; exit 1; }
    local i; for i in 1 2 3 4 5 6; do seq 1 30 > "$r/f$i.py"; done
    git -C "$r" add . >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_mention_counts_as_run.sh:$LINENO" >&2; exit 1; }
}
run_hook() {
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","transcript_path":"%s","tool_input":{"command":"git commit -m x"}}' \
        "$3" "$1" "$4" | env STATE_DIR="$TMP/$2" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null
    # Вторая половина механизма (D372, 9 сентября 2026): запись попадает в знаменатель
    # только после PostToolUse, то есть после УСПЕШНОЙ команды. Сценарий здесь именно
    # такой — коммит состоялся, — поэтому фикстура моделирует обе половины.
    _oh="$HOOK_DIR/code-review-outcome.sh"
    [ -f "$_oh" ] || return 0
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' \
        "$3" "$1" | env STATE_DIR="$TMP/$2" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$_oh" >/dev/null 2>&1
}
acts() { jq -r 'select(.guard == "code-review-reminder") | .act' "$TMP/$1/detection-$2.jsonl" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'; }

MARKER="${ADVERSARY_PROMPT_MARKER:-Ты противник}"

# 1. Поиск строки в дереве. Это РАЗВЕДКА, а не прогон: субагенту read-only поручено
#    найти носителей маркера и перечислить их.
TR_SEARCH="$TMP/tr-search.jsonl"
jq -cn --arg m "$MARKER" '{message:{content:[{type:"tool_use",name:"Agent",input:{
    subagent_type:"Explore",
    description:"poisk nositelej markera",
    prompt:("Найди в дереве все файлы, где встречается строка " + $m + ", и перечисли их с адресами. Ничего не чини и ничего не запускай.")}}]}}' > "$TR_SEARCH"

# 2. Пересказ скилла: субагенту дана цитата начала промпта, чтобы он опознал скилл.
TR_QUOTE="$TMP/tr-quote.jsonl"
jq -cn --arg m "$MARKER" '{message:{content:[{type:"tool_use",name:"Agent",input:{
    subagent_type:"Explore",
    description:"pereskaz skilla",
    prompt:("Прочитай skills/adversary/SKILL.md и перескажи процедуру своими словами. Роль внутри его промпта начинается словами: " + $m + ".")}}]}}' > "$TR_QUOTE"

# 3. Тот же приём через Workflow: скрипт ИЩЕТ маркер, а не зовёт противника.
TR_WF="$TMP/tr-wf.jsonl"
jq -cn --arg m "$MARKER" '{message:{content:[{type:"tool_use",name:"Workflow",input:{
    description:"inventarizaciya",
    script:("phase(\"Inventory\")\nbash(\"grep -rl \\u0027" + $m + "\\u0027 hooks/ | sort\")")}}]}}' > "$TR_WF"
[ -s "$TR_WF" ] || { echo "FAIL [T3-setup]: rasshifrovka dlya T3 ne sobralas"; exit 1; }

# --- T1: поиск строки — не прогон ---
N=$(adversary_run_count "$TR_SEARCH")
if [ "${N:-0}" = "0" ]; then ok
else bad "T1" "read-only poisk stroki zaschitan progonom (schet $N): granica <vyzov, a ne upominanie> k polyu prompt ne primenena"; fi

# --- T2: цитата промпта в задании на пересказ — не прогон ---
N=$(adversary_run_count "$TR_QUOTE")
if [ "${N:-0}" = "0" ]; then ok
else bad "T2" "citirovanie prompta zaschitano progonom (schet $N)"; fi

# --- T3: grep по маркеру внутри воркфлоу — не прогон ---
N=$(adversary_run_count "$TR_WF")
if [ "${N:-0}" = "0" ]; then ok
else bad "T3" "grep po markeru vnutri skripta workflow zaschitan progonom (schet $N)"; fi

# --- T4: страж обязан напомнить — крупный код никто не критиковал ---
R4="$TMP/r4"; big_repo "$R4"
OUT=$(run_hook "$R4" s4 sid-4 "$TR_SEARCH")
case "$OUT" in
    *"Крупный кодовый дифф"*) ok ;;
    *) bad "T4" "strazh molchit na 180 strokah / 6 fajlah, kotoryh nikto ne kritikoval: [${OUT:0:80}]" ;;
esac

# --- T5: и знаменатель не смеет записать это как состоявшийся прогон ---
A=$(acts s4 sid-4)
if [ "$A" = "said" ]; then ok
else bad "T5" "v zhurnale [$A]: zamer napechataet <s progonom> tam, gde progona ne bylo"; fi

# --- T6: отрицательный контроль — настоящий вызов всё ещё виден ---
# Без него T1-T5 неотличимы от «функция перестала считать вообще».
TR_REAL="$TMP/tr-real.jsonl"
jq -cn --arg m "$MARKER" '{message:{content:[{type:"tool_use",name:"Agent",input:{
    subagent_type:"general-purpose",
    description:"protivnik",
    prompt:($m + ". Единственная цель — ДОКАЗАТЬ, что код ломается. Каждая атака — падающий тест.")}}]}}' > "$TR_REAL"
if [ "$(adversary_run_count "$TR_REAL")" = "1" ]; then ok
else bad "T6" "kontrol provalen: nastoyaschij vyzov ne opoznan, test merit ne to"; fi

echo ""
echo "adv-arc mention-counts-as-run tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
