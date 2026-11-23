#!/usr/bin/env bash
# СУДИТ: hooks/code-review-outcome.sh hooks/code-review-reminder.sh hooks/lib/adversary-run-lib.sh
# test_adv_arc_broken_transcript.sh — атака на `adversary_run_count`
# (hooks/lib/adversary-run-lib.sh:50) и на журнал знаменателя `code-review-reminder.sh:164`.
#
# ЧТО ДОКАЗЫВАЕТСЯ. Разбор идёт через `jq -rs`, то есть слурпом ВСЕГО файла. Одна
# нечитаемая строка где угодно в расшифровке роняет jq целиком (`rc=5`), вывод пуст,
# счётчик обнуляется — и настоящий вызов противника, лежащий строкой выше, становится
# невидим.
#
# Библиотека объявляет это безопасным: «потребители отличают "прогонов нет" от
# "прочитать не удалось" не кодом возврата, а гейтом существования файла ДО вызова»
# (adversary-run-lib.sh:30-31). Гейт здесь ПРОЙДЕН — файл существует и читается. Значит
# различения нет ни у одного потребителя, и оба получают «прогонов не было» как ФАКТ.
#
# Цена не в лишнем напоминании (оно безвредно), а в ЧИСЛЕ: страж пишет в журнал
# знаменателя `said` — «крупный дифф ушёл в коммит, прогона не было». Замер
# `adversary-before-commit` считает эту запись подтверждённым событием мира, хотя прибор
# не смог прочитать вход. Словарь `act` для ровно этого случая имеет значение `unread`
# (root-cause-lib.sh:272: «страж промолчал не по решению, а потому что ВХОД не
# прочитался»), и оно здесь не используется.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/code-review-reminder.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq недоступен";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# shellcheck source=/dev/null
. "$HOOK_DIR/lib/adversary-run-lib.sh"

big_repo() {
    local r="$1"; mkdir -p "$r"
    git -C "$r" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_broken_transcript.sh:$LINENO" >&2; exit 1; }
    git -C "$r" config user.email t@e; git -C "$r" config user.name t
    echo seed > "$r/seed.txt"; git -C "$r" add . >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_broken_transcript.sh:$LINENO" >&2; exit 1; }
    git -C "$r" commit -q -m seed 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_broken_transcript.sh:$LINENO" >&2; exit 1; }
    local i; for i in 1 2 3 4 5 6; do seq 1 30 > "$r/f$i.py"; done
    git -C "$r" add . >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_arc_broken_transcript.sh:$LINENO" >&2; exit 1; }
}
run_hook() {  # $1 = cwd, $2 = каталог состояния, $3 = сессия, $4 = расшифровка
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","transcript_path":"%s","tool_input":{"command":"git commit -m x"}}' \
        "$3" "$1" "$4" | env STATE_DIR="$TMP/$2" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null
    # Вторая половина механизма (D372, 9 сентября 2026): запись попадает в знаменатель
    # только после PostToolUse, то есть после УСПЕШНОЙ команды. Здесь сценарий именно
    # такой — коммит состоялся, — поэтому фикстура обязана моделировать обе половины.
    _oh="$HOOK_DIR/code-review-outcome.sh"
    [ -f "$_oh" ] || return 0
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' \
        "$3" "$1" | env STATE_DIR="$TMP/$2" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$_oh" >/dev/null 2>&1
}
acts() { jq -r 'select(.guard == "code-review-reminder") | .act' "$TMP/$1/detection-$2.jsonl" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'; }

# Расшифровка: НАСТОЯЩИЙ вызов противника, затем одна оборванная строка.
# Оборванная последняя строка — обычная форма живого файла: клиент дописывает журнал
# ходом, а страж читает его в тот же момент.
TR_OK="$TMP/tr-ok.jsonl"
jq -cn '{message:{content:[{type:"tool_use",name:"Skill",input:{skill:"adversary"}}]}}' > "$TR_OK"
TR_CUT="$TMP/tr-cut.jsonl"
cp "$TR_OK" "$TR_CUT"
printf '{"message":{"content":[{"type":"tool_' >> "$TR_CUT"

# --- T0: положительный контроль — на целой расшифровке прибор видит вызов ---
N_OK=$(adversary_run_count "$TR_OK")
if [ "${N_OK:-0}" -gt 0 ]; then ok; else bad "T0" "контроль провален: на целом файле счёт $N_OK — тест мерит не то"; fi

# --- T1: вызов в файле ЕСТЬ, оборванная строка ниже его не отменяет ---
N_CUT=$(adversary_run_count "$TR_CUT")
if [ "${N_CUT:-0}" -gt 0 ]; then ok
else bad "T1" "вызов противника лежит строкой 1, счёт $N_CUT — одна оборванная строка обнулила весь разбор"; fi

# --- T2: страж молчит, когда прогон в расшифровке есть (та же нога, что T7 основного теста) ---
R2="$TMP/r2"; big_repo "$R2"
OUT=$(run_hook "$R2" s2 sid-2 "$TR_CUT")
if [ -z "$OUT" ] || [ "$OUT" = "{}" ]; then ok
else bad "T2" "прогон в расшифровке есть, а страж требует прогнать: ${OUT:0:110}"; fi

# --- T3: журнал знаменателя не смеет утверждать «прогона не было» о непрочитанном входе ---
A=$(acts s2 sid-2)
case "$A" in
    said) bad "T3" "в журнале '$A' — замер посчитает это подтверждённым «ушло без прогона», хотя вход не прочитан (ожидалось satisfied либо unread)" ;;
    "")   bad "T3" "записи нет вовсе — событие выпало из знаменателя" ;;
    *)    ok ;;
esac

# --- T4: отрицательный контроль — на целой расшифровке страж молчит и пишет satisfied ---
# Без него T2/T3 неотличимы от «страж сломан на любом входе».
R4="$TMP/r4"; big_repo "$R4"
OUT4=$(run_hook "$R4" s4 sid-4 "$TR_OK")
if { [ -z "$OUT4" ] || [ "$OUT4" = "{}" ]; } && [ "$(acts s4 sid-4)" = "satisfied" ]; then ok
else bad "T4" "контроль провален: на целой расшифровке страж дал '${OUT4:0:60}' и журнал '$(acts s4 sid-4)'"; fi

echo ""
echo "adv-arc broken-transcript tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
