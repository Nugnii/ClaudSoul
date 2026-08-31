#!/usr/bin/env bash
# test_adv2_bump_comment_tail_verify_rejects.sh
#
# Атака: `confirmed_count: 17  # накопилось за три месяца`.
#
# Эта форма поля поддержана НАМЕРЕННО — ветка awk (knowledge-counter-bump.sh:300-321)
# заведена под неё и хранит комментарий: «Хвост строки (комментарий) сохраняется».
# Инкремент проходит правильно: 17 → 18, комментарий на месте.
#
# А проверка записи (строки 363-368) читает счётчик через `show_counters | awk -F': '`,
# получает «18  # накопилось за три месяца», не признаёт это числом и объявляет
# «исход НЕ записан» с кодом 1 — ПОСЛЕ того, как файл уже перезаписан (строка 359).
#
# Итог одного вызова:
#   • confirmed_count увеличен на диске,
#   • last_confirmed переставлен на сегодня,
#   • в provenance_log добавлена запись «reinforced»,
#   • в disagreement-outcomes.jsonl НЕ записано ничего, pending НЕ погашен,
#   • код возврата 1, текст говорит «исход НЕ записан».
#
# И вторая половина цены: сообщение приглашает повторить вызов — повтор увеличивает
# счётчик ещё раз. Три вызова дают 17 → 20 при трёх сообщениях «НЕ записан» и пустом
# журнале. От confirmed_count считаются reliability, priority и FSRS.
#
# Тест НЕ выдумывает контракт: он сверяет утверждение скрипта с состоянием файла.
# Если скрипт говорит «не записан» — файл обязан остаться прежним; если файл изменён —
# исход обязан быть в журнале.

set -uo pipefail

BUMP="$(cd "$(dirname "$0")/.." && pwd)/knowledge-counter-bump.sh"
TMP="$(mktemp -d)"
LES="$TMP/lessons"; ST="$TMP/state"
mkdir -p "$LES" "$ST"

cat > "$LES/pattern-tail-form.md" <<'EOF'
---
type: pattern
confidence: 4
impact: 3
confirmed_count: 17  # накопилось за три месяца
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
provenance_log: []
---

# Тело
EOF

run() {
    env -u CLAUDE_STATE_DIR -u DIS_SESSION \
        STATE_DIR="$ST" LESSONS_DIR="$LES" \
        bash "$BUMP" pattern-tail-form confirmed "$1" 2>&1
}

counter() { awk -F'confirmed_count: ' '/^confirmed_count:/ {print $2; exit}' "$LES/pattern-tail-form.md"; }

OUT1=$(run "первый повод"); RC1=$?
CNT1=$(counter)

PASS=0; FAIL=0
say_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
say_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }

# 1. Отчёт о провале обязан означать, что файл не тронут.
if grep -q 'исход НЕ записан' <<< "$OUT1" && [ "$RC1" -ne 0 ]; then
    case "$CNT1" in
        17*) say_pass "код 1 + «исход НЕ записан» ⇒ счётчик остался 17" ;;
        *)   say_fail "код возврата $RC1 и текст «исход НЕ записан», но confirmed_count на диске = «${CNT1}» (было «17  # накопилось за три месяца»)" ;;
    esac
else
    case "$CNT1" in
        18*) say_pass "исход записан, счётчик 17 → 18" ;;
        *)   say_fail "неожиданный исход: rc=$RC1, счётчик «${CNT1}», вывод: $OUT1" ;;
    esac
fi

# 2. Файл изменён ⇒ исход обязан быть в durable-журнале.
JRN="$ST/disagreement-outcomes.jsonl"
case "$CNT1" in
    17*) say_pass "файл не менялся — журнал не требуется" ;;
    *)
        if [ -s "$JRN" ] && grep -q 'pattern-tail-form' "$JRN"; then
            say_pass "изменение файла отражено в disagreement-outcomes.jsonl"
        else
            say_fail "confirmed_count увеличен на диске, а в $JRN записи нет (файл $( [ -e "$JRN" ] && echo 'пуст' || echo 'не создан'))"
        fi
        ;;
esac

# 3. Повтор после сообщения «НЕ записан» не должен увеличивать счётчик второй раз.
OUT2=$(run "второй повод"); RC2=$?
OUT3=$(run "третий повод"); RC3=$?
CNT3=$(counter)
PROV=$(grep -c 'kind: reinforced' "$LES/pattern-tail-form.md")
if [ "$RC1" -ne 0 ] && [ "$RC2" -ne 0 ] && [ "$RC3" -ne 0 ]; then
    case "$CNT3" in
        17*) say_pass "три отказа подряд — счётчик не двигался" ;;
        *)   say_fail "три вызова, три сообщения «исход НЕ записан» (rc $RC1/$RC2/$RC3), а confirmed_count = «${CNT3}» и записей provenance_log = ${PROV}; журнал пуст" ;;
    esac
else
    say_pass "хотя бы один вызов признан успешным — расхождения нет"
fi

echo "--- срез файла после трёх вызовов ---"
sed -n '1,12p' "$LES/pattern-tail-form.md"

echo "adv2 bump comment-tail verify: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
