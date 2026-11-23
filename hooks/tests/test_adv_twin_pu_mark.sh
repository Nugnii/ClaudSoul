#!/usr/bin/env bash
# СУДИТ: hooks/timestamp-canary-check.sh hooks/accepted-alternative-gap.sh hooks/hook-input-lib.sh hooks/lib/transcript_window.py
# test_adv_twin_pu_mark.sh — противник окна хода (D498): метка «на этот ход уже алертили»
# хранит $PU — индекс последней реплики В РАЗОБРАННОМ МАССИВЕ. На всём файле индекс
# абсолютный и сдвигается с каждой новой репликой владельца; на окне массив начинается с
# самой реплики, и $PU = 0 на КАЖДОМ ходу. После первого алерта сессии метка «0» совпадает
# с $PU всех следующих ходов, и оба стража немеют до конца сессии.
# Записи — в форме мира: type user + origin.kind human (фикстуры прежних тестов этих стражей
# писались без поля type, и окно на них вырождалось в файл целиком — ноги T13 / T7 зелёные).
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"
# Прежнее поведение — окно = файл целиком: настоящая библиотека ввода (её определения признака, D1153), окно подменено.
printf '. "%s/hook-input-lib.sh"\n%s\n' "$HOOKS" 'transcript_turn_window() { cat "$1"; }' > "$T/whole-lib.sh"

user() { jq -nc --arg t "$1" '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:$t}]}}'; }
asst() { jq -nc --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
clock() { jq -nc --arg c "🕐 $1 — начни ответ этим таймштампом" '{type:"attachment",attachment:{type:"hook_additional_context",hookName:"UserPromptSubmit",content:[$c]}}'; }
NOW_TS=$(date '+%Y-%m-%d %H:%M')

canary() {  # canary <транскрипт> <каталог метки> [библиотека ввода]
    printf '{"session_id":"sid-c","transcript_path":"%s"}' "$1" \
        | env ${3:+INPUT_LIB="$3"} CANARY_STATE_DIR="$2" TIMESTAMP_INJECT_PATH="$HOOKS/timestamp-inject.sh" \
          bash "$HOOKS/timestamp-canary-check.sh" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_twin_pu_mark.sh:$LINENO" >&2; exit 1; }
}
accalt() {  # accalt <транскрипт> <каталог состояния> [библиотека ввода]
    printf '{"session_id":"sid-a","transcript_path":"%s"}' "$1" \
        | env ${3:+INPUT_LIB="$3"} STATE_DIR="$2" bash "$HOOKS/accepted-alternative-gap.sh" 2>/dev/null
}

# --- Канарейка: два хода владельца, оба ответа без шапки при живом инжекте ---
for mode in window whole; do
    F="$T/c-$mode.jsonl"; S="$T/cst-$mode"; mkdir -p "$S"
    lib=""; [ "$mode" = whole ] && lib="$T/whole-lib.sh"
    { user "вопрос"; clock "$NOW_TS"; asst "Ответ без шапки."; } > "$F"
    OUT1=$(canary "$F" "$S" "$lib")
    { user "ещё вопрос"; clock "$NOW_TS"; asst "Снова без шапки."; } >> "$F"
    OUT2=$(canary "$F" "$S" "$lib")
    grep -q "БЕЗ таймштампа" <<< "$OUT1" && ok || bad "canary-$mode-1" "первый ход — алерта нет: «${OUT1}»"
    grep -q "БЕЗ таймштампа" <<< "$OUT2" && ok \
        || bad "canary-$mode-2" "новая реплика владельца не взвела канарейку (метка «$(cat "$S/canary-alerted-sid-c" 2>/dev/null)»): «${OUT2}»"
done

# --- Принятие чужого варианта: два хода, в обоих ответ «отличная идея» ---
for mode in window whole; do
    F="$T/a-$mode.jsonl"; S="$T/ast-$mode"; mkdir -p "$S"
    lib=""; [ "$mode" = whole ] && lib="$T/whole-lib.sh"
    { user "вопрос"; asst "Отличная идея, беру."; } > "$F"
    OUT1=$(accalt "$F" "$S" "$lib")
    { user "а так?"; asst "Твой вариант лучше моего."; } >> "$F"
    OUT2=$(accalt "$F" "$S" "$lib")
    grep -q "принят вариант" <<< "$OUT1" && ok || bad "accalt-$mode-1" "первый ход — алерта нет: «${OUT1}»"
    grep -q "принят вариант" <<< "$OUT2" && ok \
        || bad "accalt-$mode-2" "новая реплика владельца не взвела детектор (метка «$(cat "$S/accepted-alt-alerted-sid-a" 2>/dev/null)»): «${OUT2}»"
done

echo "test_adv_twin_pu_mark: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
