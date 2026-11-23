#!/usr/bin/env bash
# СУДИТ: scripts/adversary-before-commit.sh
# test_adv_arc_journal_unreadable.sh — атака на замер scripts/adversary-before-commit.sh:71.
#
# ЧТО ДОКАЗЫВАЕТСЯ. Разбор журнала сессии идёт слурпом:
#
#     _acts=$(jq -rs '...' "$_f" 2>/dev/null) || continue
#
# Одна нечитаемая строка роняет jq на ВСЁМ файле (`rc=5`), и `|| continue` уносит сессию
# целиком: её `said`/`muted`/`satisfied` в знаменатель не попадают, и её же строка
# «без подписи» (`NOSIG`, считается ниже по тому же телу цикла) тоже не считается —
# `continue` стоит ДО неё. Замер печатает меньшее «всего» и НЕ ГОВОРИТ, что читал не всё.
#
# Это ровно то различение, ради которого написана шапка самого замера и нога T3 его
# штатного теста: «прибор отличает "измерил, чисто" от "мерить нечем"». Повод там назван
# дословно — `ab-authorization-replay.sh`: «прибор не отличал "нет" от "не измерил"».
# Между «нет данных» и «данные есть, но не прочитаны» замер снова не различает, и второе
# выдаёт за первое молча.
#
# Цена — число: доля «ушло без прогона» считается от урезанного знаменателя, а решение по
# ADR-015 («выше половины при n ≥ MIN_N») принимается по ней же. Урезание может и
# перевести долю через порог, и увести n под MIN_N, погасив вывод целиком.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Команда — из реестра, как у штатного теста: замер, зелёный у себя и сломанный у бегуна,
# проверенным не считается.
MCMD=$(awk -F'\t' '$1=="adversary-before-commit"{print $3}' "$REPO/scripts/measurements.tsv")
[ -n "$MCMD" ] || { echo "SKIP: строки adversary-before-commit нет в scripts/measurements.tsv"; exit 0; }

run() { ( cd "$REPO" && env STATE_DIR="$TMP/$1" ADVERSARY_COMMIT_MIN_N="${2:-2}" bash -c "$MCMD" 2>&1 ); }

journal() {  # $1 = каталог, $2 = сессия, далее пары «act sig»
    local d="$TMP/$1"; mkdir -p "$d"; local sid="$2"; shift 2
    local f="$d/detection-$sid.jsonl"; : > "$f"
    while [ "$#" -ge 2 ]; do
        printf '{"ts":"2026-09-09T00:00:00Z","guard":"code-review-reminder","act":"%s","sig":"%s"}\n' "$1" "$2" >> "$f"
        shift 2
    done
}

# Две сессии: одна чистая (2 события), вторая с тремя событиями и одной оборванной строкой.
# Итого читаемых событий пять.
for d in clean torn; do
    journal "$d" sid-a  said d1  satisfied d2
    journal "$d" sid-b  said e1  said e2  satisfied e3
done
printf '{ оборвано\n' >> "$TMP/torn/detection-sid-b.jsonl"

OUT_CLEAN=$(run clean)
OUT_TORN=$(run torn)

# --- T0: положительный контроль — без оборванной строки знаменатель равен пяти ---
case "$OUT_CLEAN" in
    *"всего: 5"*) ok ;;
    *) bad "T0" "контроль провален: на целых журналах не 5 — тест мерит не то: $OUT_CLEAN" ;;
esac

# --- T1: события читаемых строк не должны пропадать из знаменателя ---
case "$OUT_TORN" in
    *"всего: 5"*) ok ;;
    *"всего: 2"*) bad "T1" "три читаемых события сессии sid-b выброшены целиком, напечатано «всего: 2»" ;;
    *)            bad "T1" "знаменатель не 5: $OUT_TORN" ;;
esac

# --- T2: если прибор всё же не смог прочитать журнал — он обязан это НАЗВАТЬ ---
# Нога независима от T1: даже отказавшись считать сессию, замер не имеет права выдавать
# «не смог прочитать» за «столько было».
case "$OUT_TORN" in
    *прочит*|*"не смог"*|*битым*|*пропущ*|*"НЕ ИЗМЕР"*|*"сбой"*) ok ;;
    *) bad "T2" "о нечитаемом журнале не сказано ни слова, число выдано как измеренное: $OUT_TORN" ;;
esac

# --- T3: та же слепота гасит и счётчик «без подписи» ---
# `continue` стоит выше подсчёта NOSIG, поэтому строки без подписи из сорванной сессии
# тоже исчезают — а они печатаются отдельной строкой именно чтобы «ноль» не оказался
# тишиной прибора (шапка замера, предел 3).
mkdir -p "$TMP/nosig"
journal nosig sid-a  said d1  satisfied d2
printf '{"ts":"2026-09-09T00:00:00Z","guard":"code-review-reminder","act":"said"}\n' >  "$TMP/nosig/detection-sid-c.jsonl"
printf '{"ts":"2026-09-09T00:00:00Z","guard":"code-review-reminder","act":"said"}\n' >> "$TMP/nosig/detection-sid-c.jsonl"
printf '{ оборвано\n'                                                                >> "$TMP/nosig/detection-sid-c.jsonl"
OUT_NOSIG=$(run nosig)
case "$OUT_NOSIG" in
    *"без подписи"*"2"*) ok ;;
    *) bad "T3" "две записи без подписи из сорванной сессии не названы: $OUT_NOSIG" ;;
esac

echo ""
echo "adv-arc journal-unreadable tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
