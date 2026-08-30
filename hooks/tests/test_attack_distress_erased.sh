#!/usr/bin/env bash
# test_attack_distress_erased.sh — АТАКА: настоящий distressed собеседника стирается
# любой «документной» строкой, приложенной к его же жалобе.
#
# itr_compute_state читает классы distressed и stuck по `user_own_speech`. Функция
# отдаёт ПУСТО целиком, если во всём turn'е нашлась хоть одна строка вида `##...`,
# строка с `---` и `|`, две строки с `>` — или если первая строка кончается двоеточием
# при длине ≥ 500. Реплика «я устал, помогите» + приложенный кусок вывода перестаёт
# быть распознанной: state падает в idle.
#
# Заявленная асимметрия цены («ложное срабатывание пишет событие, пропуск не пишет
# ничего») для этой оси не выполняется: пропуск distressed СНИМАЕТ тормоз AP2 —
# агент остаётся при праве на proactive ровно там, где собеседнику плохо.

set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/intrusiveness-state-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }

TMP=$(mktemp -d)
export ITR_STATE_DIR="$TMP"
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
state_of() { itr_compute_state "" "$1" | cut -d'|' -f1; }

assert_state() {  # $1=имя $2=ожидаемое $3=текст
    local got; got=$(state_of "$3")
    if [ "$got" = "$2" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$1]: ожидалось '$2', получено '$got'"; fi
}

DISTRESS="я устал от этого, помогите хоть как-нибудь"

# t0 — контроль: та же жалоба без приложений распознаётся
assert_state "t0 plain distress (control)" "distressed" "$DISTRESS"

# t1 — жалоба + заголовок приложенного лога
assert_state "t1 distress + markdown heading" "distressed" "$DISTRESS
## лог сборки
строка вывода"

# t2 — жалоба + строка, похожая на разделитель таблицы (`---` и `|` в одной строке)
assert_state "t2 distress + table-ish line" "distressed" "$DISTRESS
собрал вот так: cmd --- | tee out.log"

# t3 — жалоба + две строки, начатые с `>` (обычная вставка двух строк лога)
assert_state "t3 distress + two > lines" "distressed" "> step 1 failed
> step 2 failed
$DISTRESS"

# t4 — незакрытая ограда: всё, что после неё, глотается, включая собственные слова
assert_state "t4 distress after unclosed fence" "distressed" "вот вывод:
\`\`\`
error text
$DISTRESS"

# t5 — зачин с двоеточием + длинное тело: остаётся ТОЛЬКО первая строка,
# собственный хвост собеседника после вставки выбрасывается вместе с телом
LOG=$(awk 'BEGIN { for (i = 0; i < 14; i++) print "INFO worker step ok, nothing special here at all." }')
assert_state "t5 own tail after colon-header + paste" "distressed" "смотри что происходит:
$LOG
$DISTRESS"

# t6 — та же дыра на оси stuck: признак застревания теряется тем же заголовком
assert_state "t6 stuck + markdown heading" "stuck" "опять не работает, третий раз подряд
## лог
строка вывода"

rm -rf "$TMP"
echo ""
echo "attack distress-erased: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
