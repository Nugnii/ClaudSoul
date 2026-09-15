#!/usr/bin/env bash
# test_attack_r3_h1_document.sh — АТАКА: признак вставленного документа опознаёт
# ровно `^##`, поэтому пересылка с заголовками первого уровня (`# Заголовок`) не
# опознаётся документом вовсе и уходит потребителям целиком.
#
# В awk стоит `if (line ~ /^##/) { doc = 1 }`. Три обычные формы заголовка мимо:
#   1. `# Заголовок` — первый уровень; так начинается почти любой README, статья,
#      выгрузка из чата, файл с фронтматтером;
#   2. `  ## Заголовок` — markdown разрешает до трёх пробелов отступа, и копирование
#      из отступленного блока их сохраняет;
#   3. setext — `Заголовок` и `=====` строкой ниже.
# Ни одна не ставит doc, а другие признаки (таблица, две строки цитаты, зачин-подпись
# с двоеточием) в такой пересылке отсутствуют. Реплика печатается ЦЕЛИКОМ.
#
# Комментарий в коде выводит правило из замера по 31 срабатыванию, где «2 — markdown-
# структура пересланного документа». Признак настроен на две наблюдённые пересылки;
# первый уровень заголовка в выборку не попал и потому не закрыт.
#
# Итог: пересланная рецензия в 900 символов уходит как собственная речь собеседника.
# reformulation-tracker пишет «Пользователь КОРРЕКТИРУЕТ», itr_compute_state читает
# чужие слова как речевые акты собеседника.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/hook-input-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

BODY=""
i=0
while [ "$i" -lt 12 ]; do
    BODY="${BODY}Разбор идёт по кругу, и автор пишет длинно, абзац за абзацем. "
    i=$((i + 1))
done

assert_silent() {  # $1=текст $2=имя
    local got; got=$(user_own_speech "$1")
    if [ -z "$got" ]; then ok
    else bad "$2" "пересылка ушла как собственная речь (${#got} символов): $(printf '%s' "$got" | tr '\n' '/' | cut -c1-90)"; fi
}

# t0 — контроль: тот же документ с `##` признаётся вставкой и гасится
assert_silent "## Рецензия

$BODY
Автор считает, что это не совсем то, что нужно. $BODY" "t0 h2 document silenced"

# t1 — АТАКА: заголовок первого уровня — документ не опознан
assert_silent "# Рецензия

$BODY
Автор считает, что это не совсем то, что нужно. $BODY" "t1 h1 document leaks"

# t2 — АТАКА: `##` с отступом в два пробела (markdown это разрешает)
assert_silent "  ## Рецензия

$BODY
Автор считает, что это не совсем то, что нужно. $BODY" "t2 indented h2 leaks"

# t3 — АТАКА: setext-заголовок (подчёркивание строкой `=====`)
assert_silent "Рецензия
=========

$BODY
Автор считает, что это не совсем то, что нужно. $BODY" "t3 setext document leaks"

# t4 — та же дыра доходит до состояния: чужой отчёт объявляет собеседника застрявшим
ITR_LIB="$HOOKS_DIR/intrusiveness-state-lib.sh"
if [ -f "$ITR_LIB" ]; then
    TMP=$(mktemp -d)
    export ITR_STATE_DIR="$TMP"
    export STATE_DIR="$TMP"
    # shellcheck source=/dev/null
    source "$ITR_LIB" 2>/dev/null || true
    if command -v itr_compute_state >/dev/null 2>&1; then
        st=$(itr_compute_state "" "# Отчёт из соседней сессии

$BODY
Тут опять не работает сборка, снова та же ошибка. $BODY" 2>/dev/null)
        case "$st" in
            stuck*) bad "t4 state from h1 document" "чужой отчёт дал состояние: $st" ;;
            *) ok ;;
        esac
    fi
fi

# t5 — сквозной: хук объявляет коррекцию на пересланной рецензии
HOOK="$HOOKS_DIR/reformulation-tracker.sh"
if [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1; then
    TMP2=$(mktemp -d); mkdir -p "$TMP2/state"
    out=$(jq -nc --arg s r3h1 --arg p "# Рецензия

$BODY
Автор считает, что это не совсем то, что нужно. $BODY" \
        '{session_id:$s,prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP2/state" bash "$HOOK" 2>/dev/null)
    if grep -qF "КОРРЕКТИРУЕТ" <<< "$out"; then
        bad "t5 hook fires BACKWARD on forwarded review" "хук объявил коррекцию"
    else ok; fi
fi

echo ""
echo "attack r3 h1-document: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
