#!/usr/bin/env bash
# test_adversary_before_commit.sh — тест замера «доля крупных коммитов без прогона» (D372).
#
# Команда берётся ИЗ РЕЕСТРА, а не пишется в тесте: замер, зелёный у себя и сломанный у
# бегуна, — это не проверенный замер. Образец приёма — test_completion_gate_open_fired.sh.
#
# Главное, что здесь доказывается: прибор отличает «измерил, чисто» от «мерить нечем».
# Повод для отдельной ноги — ab-authorization-replay.sh: «два прогона подряд публиковали
# нули как "нет ходов", пока причиной была расщеплённая песочница».
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Команда замера — из реестра. Если строки нет, тест обязан упасть, а не пропуститься:
# «замера нет» и «замер в порядке» неотличимы только для того, кто не смотрит.
MCMD=$(awk -F'\t' '$1=="adversary-before-commit"{print $3}' "$REPO/scripts/measurements.tsv")
if [ -n "$MCMD" ]; then ok; else bad "T0" "строки adversary-before-commit нет в scripts/measurements.tsv"; fi

# Запуск замера на подставном состоянии. Порог знаменателя снижен: ноги проверяют ветвление,
# а не величину порога; сам порог проверяется ногой T4.
run() {  # $1 = каталог состояния, $2 = MIN_N (опц.)
    ( cd "$REPO" && env STATE_DIR="$TMP/$1" ADVERSARY_COMMIT_MIN_N="${2:-2}" \
        bash -c "$MCMD" 2>&1 )
}
rc() {   # $1 = каталог состояния, $2 = MIN_N (опц.)
    ( cd "$REPO" && env STATE_DIR="$TMP/$1" ADVERSARY_COMMIT_MIN_N="${2:-2}" \
        bash -c "$MCMD" >/dev/null 2>&1 ); echo $?
}

# Запись журнала признаков: $1 = каталог, $2 = сессия, дальше пары «act sig».
journal() {
    local d="$TMP/$1"; mkdir -p "$d"; local sid="$2"; shift 2
    local f="$d/detection-$sid.jsonl"; : > "$f"
    while [ "$#" -ge 2 ]; do
        jq -cn --arg a "$1" --arg s "$2" \
            '{ts:"2026-09-09T00:00:00Z", guard:"code-review-reminder", act:$a, sig:$s}' >> "$f"
        shift 2
    done
}

# --- T1: правило исполняется в большинстве случаев → 0 ---
journal s1 sid-1  satisfied d1  satisfied d2  satisfied d3  said d4
OUT=$(run s1); RC=$(rc s1)
[ "$RC" = "0" ] && ok || bad "T1a" "ожидался код 0, получен $RC"
case "$OUT" in *"всего: 4"*) ok ;; *) bad "T1b" "не назвал знаменатель 4: $OUT" ;; esac
case "$OUT" in *"с прогоном: 3"*) ok ;; *) bad "T1c" "не назвал число прогонов: $OUT" ;; esac

# --- T2: больше половины уходит без прогона → 1 и маркер находки ---
journal s2 sid-2  said d1  said d2  muted d3  satisfied d4
OUT=$(run s2); RC=$(rc s2)
[ "$RC" = "1" ] && ok || bad "T2a" "находка обязана сообщаться КОДОМ возврата (ADR-015), получен $RC"
case "$OUT" in *"[замер: находки, не сбой]"*) ok ;; *) bad "T2b" "нет маркера находки: $OUT" ;; esac

# --- T3: журнала нет → замер НЕ выдаёт это за «правило исполняется» ---
#
# Код возврата здесь 0 намеренно: по контракту бегуна (scripts/measurement-due.sh) код ≥2
# значит «не смог отработать» и отметка не ставится — замер висел бы вечно просроченным с
# первого дня, когда данных ещё нет по естественной причине. Поэтому пустоту отличает ТЕКСТ,
# и ловит это нога: молчаливого «— правило исполняется» на пустом входе быть не должно.
mkdir -p "$TMP/s3"
OUT=$(run s3); RC=$(rc s3)
[ "$RC" = "0" ] && ok || bad "T3a" "пустое состояние — не поломка прибора, ожидался 0, получен $RC"
case "$OUT" in *"нет"*) ok ;; *) bad "T3b" "пустота не названа явно: $OUT" ;; esac
case "$OUT" in
    *"правило исполняется"*) bad "T3c" "пустота выдана за исполнение правила: $OUT" ;;
    *) ok ;;
esac

# --- T4: мало данных → выводов не делает, даже когда доля высокая ---
journal s4 sid-4  said d1  said d2
OUT=$(run s4 20); RC=$(rc s4 20)
[ "$RC" = "0" ] && ok || bad "T4a" "при n<MIN_N решения не принимаются, ожидался 0, получен $RC"
case "$OUT" in *"мало данных"*) ok ;; *) bad "T4b" "не сказал про порог: $OUT" ;; esac

# --- T5: единица счёта — РАЗНЫЙ дифф, а не вызов ---
#
# Отрицательный контроль к самому предмету замера. Без него прибор, считающий все записи,
# проходит T1-T4 и при этом меряет объём работы вместо частоты предмета.
journal s5 sid-5  said d1  muted d1  muted d1  satisfied d2
OUT=$(run s5)
case "$OUT" in *"всего: 2"*) ok ;; *) bad "T5" "три записи одной подписи посчитаны как разные события: $OUT" ;; esac

# --- T6: чужие стражи в том же журнале не попадают в знаменатель ---
mkdir -p "$TMP/s6"
jq -cn '{ts:"2026-09-09T00:00:00Z", guard:"rework-detector", act:"said", sig:"x"}' > "$TMP/s6/detection-sid-6.jsonl"
jq -cn '{ts:"2026-09-09T00:00:00Z", guard:"code-review-reminder", act:"said", sig:"d1"}' >> "$TMP/s6/detection-sid-6.jsonl"
OUT=$(run s6)
case "$OUT" in *"всего: 1"*) ok ;; *) bad "T6" "запись чужого стража попала в знаменатель: $OUT" ;; esac

# --- T7: целостность пары фаз (D374) — ожидания без исхода видны числом, немая вторая половина даёт 2 ---
pending() {  # $1 = каталог состояния, $2 = sid, далее — акты ожиданий
    local d="$TMP/$1"; mkdir -p "$d"; local f="$d/crr-pending-$2.jsonl"; : > "$f"; shift 2
    for a in "$@"; do jq -cn --arg a "$a" '{ts:"2026-09-09T00:00:01Z", act:$a, key:"k"}' >> "$f"; done
}
journal s7 sid-7  satisfied d1  satisfied d2
pending s7 sid-7 said said
OUT=$(run s7); RC=$(rc s7)
case "$OUT" in *"ожиданий без исхода"*"2 строк в 1 сессиях"*) ok ;; *) bad "T7a" "ожидания не названы числом: $OUT" ;; esac
[ "$RC" = "0" ] && ok || bad "T7b" "ожидания при живой второй половине — не поломка, ожидался 0, получен $RC"
mkdir -p "$TMP/s8"
jq -cn '{ts:"2026-09-09T00:00:00Z", guard:"rework-detector", act:"said", sig:"x"}' > "$TMP/s8/detection-sid-8.jsonl"
pending s8 sid-8 said
OUT=$(run s8); RC=$(rc s8)
[ "$RC" = "2" ] && ok || bad "T7c" "немая вторая половина — «не измерено», ожидался 2, получен $RC"
case "$OUT" in *"ВТОРАЯ ПОЛОВИНА"*) ok ;; *) bad "T7d" "немая половина не названа: $OUT" ;; esac
mkdir -p "$TMP/s9"; pending s9 sid-9 said
RC=$(rc s9)
[ "$RC" = "2" ] && ok || bad "T7e" "ожидания без единого журнала — ожидался 2, а не «нечего замерять» с нулём, получен $RC"
journal s10 sid-10  satisfied d1  satisfied d2
pending s10 sid-old said said said
touch -t 202501010000 "$TMP/s10/crr-pending-sid-old.jsonl"
OUT=$(run s10)
case "$OUT" in *"0 строк в 0 сессиях"*) ok ;; *) bad "T7f" "ожидание старше окна посчитано: $OUT" ;; esac
OUT=$(run s1)
case "$OUT" in *"ожиданий без исхода"*"0 строк"*) ok ;; *) bad "T7g" "ноль ожиданий не назван, а умолчан: $OUT" ;; esac
journal s11 sid-11  satisfied d1
pending s11 sid-11 said said said
OUT=$(run s11)
case "$OUT" in *"ожиданий больше подтверждённых"*) ok ;; *) bad "T7h" "перевес ожиданий не назван: $OUT" ;; esac

echo ""
echo "adversary-before-commit tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
