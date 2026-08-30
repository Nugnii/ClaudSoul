#!/usr/bin/env bash
# test_throttle_lib.sh — характеризующий тест для общего throttle-lib.sh.
# Фиксирует семантику per-session подавления повторов (throttle_file / throttle_seen
# / throttle_mark), чтобы дедупликация из 6 хуков не изменила поведение «маркер не
# появляется дважды в сессии». Изоляция: tmp-файлы, lib через THROTTLE_LIB env.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
THROTTLE_LIB="${THROTTLE_LIB:-$HOOKS_DIR/throttle-lib.sh}"

[ -f "$THROTTLE_LIB" ] || { echo "FAIL: $THROTTLE_LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$THROTTLE_LIB"

PASS=0
FAIL=0
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}
# seen → exit 0; not-seen → exit 1. Helpers translate to a stable string.
seen_str() { if throttle_seen "$1" "$2"; then echo seen; else echo unseen; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- throttle_file: single naming scheme ---
F=$(throttle_file "$TMP" docs-family SID123)
assert_eq "$F" "$TMP/docs-family-fired-SID123.jsonl" "T1: file naming scheme"

# --- not seen before any mark (file absent) ---
assert_eq "$(seen_str "$F" "alpha")" "unseen" "T2: unseen on absent file, no crash"

# --- mark then seen ---
throttle_mark "$F" "alpha"
assert_eq "$(seen_str "$F" "alpha")" "seen" "T3: seen after mark"

# --- different key still unseen (per-key dedup) ---
assert_eq "$(seen_str "$F" "beta")" "unseen" "T4: other key unseen"

# --- mark with extra diagnostic fields, still valid JSON, still seen ---
throttle_mark "$F" "beta" '"pattern":"p1","signal":"s1"'
assert_eq "$(seen_str "$F" "beta")" "seen" "T5a: seen after mark-with-extra"
if command -v jq >/dev/null 2>&1; then
    last=$(tail -1 "$F")
    parsed=$(echo "$last" | jq -r '.key + "|" + .pattern + "|" + .signal' 2>/dev/null)
    assert_eq "$parsed" "beta|p1|s1" "T5b: extra fields are valid JSON"
else
    PASS=$((PASS + 1))  # jq absent: skip JSON parse, count as pass
fi

# --- idempotent read: marking same key twice still reads as seen ---
throttle_mark "$F" "alpha"
assert_eq "$(seen_str "$F" "alpha")" "seen" "T6: re-mark keeps seen"

# --- keys with special chars (real blocker keys: pattern@/abs/path, pattern:signal) ---
K1="pattern-inside-out@/tmp/My Project/file.sh"
K2="pattern-x:cross_hook_recall_gate@correction-fired"
throttle_mark "$F" "$K1"
throttle_mark "$F" "$K2"
assert_eq "$(seen_str "$F" "$K1")" "seen" "T7: path-style key with spaces/slashes"
assert_eq "$(seen_str "$F" "$K2")" "seen" "T8: colon/at-style key"
assert_eq "$(seen_str "$F" "pattern-inside-out@/tmp/other.sh")" "unseen" "T9: near-miss key unseen"

# --- isolation by session: different sid → different file → key invisible ---
F2=$(throttle_file "$TMP" docs-family OTHER_SID)
assert_eq "$(seen_str "$F2" "alpha")" "unseen" "T10: other session does not see key"

# --- field is canonically "key" (single name across all hooks) ---
if command -v jq >/dev/null 2>&1; then
    keyval=$(grep -F '"key":"alpha"' "$F" | head -1 | jq -r '.key' 2>/dev/null)
    assert_eq "$keyval" "alpha" "T11: canonical field name is key"
else
    PASS=$((PASS + 1))
fi

# --- T12: список KEEP выведен из читателей, а не из памяти автора ---
# Повод: 31 июля в KEEP внесли blocker и rework по грепу читателей; в v1.17.1 появился
# читатель `correction-fired-*` (metrics-collector.sh:504, выборка D25), а список никто
# не тронул — уборка стирала свидетельства поправок через 3 дня. Связь «есть читатель по
# маске → семейство в KEEP» держалась вручную, и разошлась во второй раз подряд.
# Сверка механическая: имя семейства перед `-fired-*` в НЕ-комментарии = межсессионный
# читатель. Джокер `*-fired-*` и `${_fam}-fired-*` не совпадают — regex требует буквы.
REPO_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
scan_readers() {
    grep -rhE -- '[a-z][a-z-]*-fired-\*' "$1" --include="*.sh" 2>/dev/null \
        | grep -v '^[[:space:]]*#' \
        | grep -oE '[a-z][a-z-]*-fired-\*' | sed 's/-fired-\*//' | sort -u
}
missing_from_keep() {
    # $1 — список читателей, $2 — список KEEP. Печатает семейства, которых нет в KEEP.
    local _r _k _found
    for _r in $1; do
        _found=0
        for _k in $2; do [ "$_r" = "$_k" ] && _found=1; done
        [ "$_found" -eq 0 ] && printf '%s ' "$_r"
    done
    true
}

READERS=$(scan_readers "$REPO_ROOT/hooks"; scan_readers "$REPO_ROOT/scripts")
READERS=$(printf '%s\n' $READERS | sort -u | tr '\n' ' ')

# Пустая выборка = сломанный греп, а не «нарушений нет»: без этой проверки тест был бы
# вечно зелёным ровно тогда, когда перестал измерять (pattern-detector-wired-to-failure).
if [ -n "$(printf '%s' "$READERS" | tr -d '[:space:]')" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T12a]: сканер не нашёл ни одного читателя — сломан греп, а не чисто"
fi

assert_eq "$(missing_from_keep "$READERS" "$THROTTLE_KEEP_FAMILIES" | sed 's/ $//')" "" \
    "T12b: у каждого семейства с читателем по маске есть строка в THROTTLE_KEEP_FAMILIES"

# Отрицательный контроль: сверка обязана краснеть на семействе, которого нет в списке.
assert_eq "$(missing_from_keep "blocker ghostfam" "blocker rework correction" | sed 's/ $//')" "ghostfam" \
    "T12c: сверка называет семейство, отсутствующее в списке"

# --- T13: уборка одинакова в bash и zsh (D83) ---
# Отбор защищённых семейств строился как `! -name ...` для find, а список раскрывался
# разбиением переменной на слова. zsh его по умолчанию не делает: «blocker rework
# correction» там ОДНО слово, keep-выражение уходило в find одним аргументом, и защита
# не действовала — уборка сносила в том числе blocker и rework. Хуки идут через bash,
# но те же функции зовут скиллы и Bash-инструмент, который на macOS zsh.
# Условие возврата пункта («первый вызов вне хука») выполнилось самим воспроизведением.
sweep_survivors() { # $1 — оболочка; печатает выжившие семейства через пробел
    local shell="$1" dir
    dir=$(mktemp -d)
    "$shell" -c 'source "$2"
        for fam in correction blocker rework decompose trust-guard; do
            f="$1/${fam}-fired-testsid.jsonl"; echo "{}" > "$f"; touch -t 202608160000 "$f"
        done
        throttle_file "$1" correction NEWSID >/dev/null
        ls "$1" 2>/dev/null | sed "s/-fired-.*//" | sort -u | tr "\n" " "' _ "$dir" "$THROTTLE_LIB"
    rm -rf "$dir" 2>/dev/null || true
}
BASH_SURV=$(sweep_survivors bash | tr -s ' ' | sed 's/ $//')
assert_eq "$BASH_SURV" "blocker correction rework" "T13a: под bash защищённые семейства выжили"
if command -v zsh >/dev/null 2>&1; then
    ZSH_SURV=$(sweep_survivors zsh | tr -s ' ' | sed 's/ $//')
    assert_eq "$ZSH_SURV" "blocker correction rework" "T13b: под zsh результат тот же"
    assert_eq "$ZSH_SURV" "$BASH_SURV" "T13c: оболочки не расходятся"
else
    PASS=$((PASS + 2))
fi

echo ""
echo "throttle-lib tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
