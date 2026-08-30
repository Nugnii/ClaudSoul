#!/usr/bin/env bash
# outcome.sh — записать исход повода разбора, который наблюдением не отличить от бездействия.
#
# Результат: у повода, признанного ложным, в журнале исходов стоит `disproved` с причиной,
#            а не `none` — доля ложных срабатываний считается, а не угадывается
# Проверка результата: bash hooks/tests/test_outcome_journal.sh даёт 0
#
# Зачем отдельная команда. Исход повода сверщик `declared-problem-recorded.sh` определяет
# НАБЛЮДАЕМО: изменился носитель после начала хода — `recorded`, не изменился — `none`.
# Один исход так не увидеть: вердикт «показалось» выглядит ровно как бездействие. Он и
# нужен здесь — не как поблажка исполнителю, а как ЗАМЕР: доля `disproved` есть точность
# признака. Больше четверти — сигнал сужается, а не исполнитель воспитывается
# (case-2026-08-28-enforcement-is-a-property-of-consequence: 40 отказов, 32 ложных).
#
# Применение:
#   bash scripts/outcome.sh disproved <сигнал> "<чем опровергнуто>"
#   bash scripts/outcome.sh fixed     <сигнал> "<что починено>"
#   bash scripts/outcome.sh debt      <сигнал> "<D-номер>"
#   bash scripts/outcome.sh knowledge <сигнал> "<имя знания>"
# Сигнал — один из сродов: rework correction question streak repeat daily discovery.
# Сессия берётся из DIS_SESSION либо CLAUDE_CODE_SESSION_ID; ключ хода — `manual`, потому
# что расшифровка команде недоступна: запись руками отличима от записи механизмом.
set -uo pipefail

OUT="${1:-}"; SIG="${2:-}"; WHY="${3:-}"
case "$OUT" in
    disproved|fixed|debt|knowledge) ;;
    *) echo "применение: bash scripts/outcome.sh {disproved|fixed|debt|knowledge} <сигнал> \"<чем>\"" >&2; exit 2 ;;
esac
[ -n "$SIG" ] || { echo "не назван сигнал (rework|correction|question|streak|repeat|daily|discovery)" >&2; exit 2; }
[ -n "$WHY" ] || { echo "не названа причина: исход без основания не считается" >&2; exit 2; }

RC_LIB="${RC_LIB:-$(cd "$(dirname "$0")/../hooks" 2>/dev/null && pwd)/root-cause-lib.sh}"
[ -f "$RC_LIB" ] || RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
[ -f "$RC_LIB" ] || { echo "нет root-cause-lib.sh — журнал исходов недоступен" >&2; exit 1; }
# shellcheck source=/dev/null
. "$RC_LIB"

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
SID="${DIS_SESSION:-${CLAUDE_CODE_SESSION_ID:-manual}}"
KEY="manual-$(printf '%s' "$WHY" | cksum | awk '{print $1}')"

rc_log_outcome "$STATE" "$SID" "$KEY" "$SIG" "$OUT" "$WHY"
echo "исход записан: $SIG → $OUT ($STATE/outcome-${SID}.jsonl)"
