#!/usr/bin/env bash
# test_adv4_fsrs_dupday_session.sh
# АТАКА: _fsrs_build_index строит день→сессии как
#   jq '"\(.session_id)\t\(.started_at[:10])"' | sort -u | awk '!($1 in s){s[$1]=1; c[$2]++}'
# Одна сессия с ДВУМЯ started_at на РАЗНЫЕ дни (registry.jsonl это допускает: --resume/
# --continue переиспользует session_id; финализация через день дописывает вторую строку
# с тем же session_id и более поздним started_at) → после sort -u строки идут
# лексикографически, «sid\tРАННИЙ» раньше «sid\tПОЗДНИЙ», awk засчитывает сессию на
# РАННЕМ дне. Если ранний день ≤ порога last_confirmed, а поздний > порога — сессия,
# реально активная ПОСЛЕ порога, в окно опыта не попадает: опыт недосчитан, знание
# стареет медленнее реальности.
#
# Ожидание: сессия, начатая (при возобновлении) 2026-08-30, засчитана как опыт после
#           2026-08-28 → experience_days_since ≥ 1 (при темпе 1 сессия/день).
# Факт:     сессия приписана к 2026-08-27 → 0 сессий после порога → experience = 0.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

LIB="$(cd "$(dirname "$0")/.." && pwd)/fsrs-lib.sh"
# shellcheck source=/dev/null
source "$LIB"

TMP=$(mktemp -d)
REG="$TMP/reg.jsonl"
# Одна сессия s1, два started_at: до порога (27-е) и после (30-е).
printf '{"session_id":"s1","started_at":"2026-08-27T09:00:00Z"}\n'  > "$REG"
printf '{"session_id":"s1","started_at":"2026-08-30T09:00:00Z"}\n' >> "$REG"

FSRS_SESSION_REGISTRY="$REG"
FSRS_SESSIONS_PER_DAY=1     # темп 1: 1 сессия после порога = 1 день опыта; 0 = 0

GOT=$(fsrs_experience_days_since 2026-08-28)

echo "index:"; sed 's/^/  /' "$REG.days-index" 2>/dev/null
echo "experience_days_since(2026-08-28) = [$GOT] (ожидалось >= 1)"

RC=0
case "$GOT" in
    ''|*[!0-9]*) echo "RED [ATTACK]: не число — [$GOT]"; RC=1 ;;
    *) if [ "$GOT" -ge 1 ]; then
           echo "PASS: сессия после порога засчитана — атака не воспроизведена"
       else
           echo "RED [ATTACK]: опыт = $GOT. Сессия s1 активна 2026-08-30 (после порога),"
           echo "  но приписана к 2026-08-27 (ранний started_at) и в окно не попала."
           RC=1
       fi ;;
esac

echo "temp: $TMP (уберёт система)"
exit "$RC"
