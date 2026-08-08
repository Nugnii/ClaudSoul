#!/bin/bash
# fsrs-lib.sh — v1.0.0
# FSRS-adapted decay for knowledge base.
#
# Formula (from knowledge/META.md §Decay):
#   stability    = 7 × (1 + confirmed_count × 0.5) × (1 + (impact - 1) × 0.25)   [days]
#   next_review  = last_confirmed + stability
#   days_overdue = today - next_review   (>0 → overdue, ≤0 → fresh)
#
# (ln(0.9)/ln(0.9) = 1, so interval_days = stability — формула в META упрощается.)
#
# Provides:
#   fsrs_stability <confirmed_count> <impact>               → int days
#   fsrs_days_overdue <last_confirmed> <cc> <impact>        → int (neg = fresh)
#   fsrs_review_status <days_overdue>                       → fresh|due|overdue|critical
#   fsrs_score_penalty_num <status>                         → int 0..100 (multiplier × 100)
#   fsrs_marker <status>                                    → string marker (empty for fresh)
#
# All functions fail silently — sourced from hooks where errors must not crash.

# Единый источник разбора дат (portable-lib.sh): ключ `date -j` есть только у BSD,
# на Linux разбор падал бы всегда. Без библиотеки iso_epoch останется неопределённой —
# вызов ниже трактует пустой ответ так же, как неразобранную дату, то есть возвращает 0.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then source "$PORTABLE_LIB"; fi

fsrs_stability() {
    local cc="${1:-0}" impact="${2:-1}"
    [[ "$cc" =~ ^-?[0-9]+$ ]] || cc=0
    [[ "$impact" =~ ^[0-9]+$ ]] || impact=1
    [ "$cc" -lt 0 ] && cc=0
    [ "$impact" -lt 1 ] && impact=1
    [ "$impact" -gt 5 ] && impact=5
    # awk: 7 × (1 + cc × 0.5) × (1 + (impact-1) × 0.25), округление до int
    awk -v c="$cc" -v i="$impact" \
        'BEGIN { s = 7 * (1 + c * 0.5) * (1 + (i - 1) * 0.25); printf "%d\n", (s < 1 ? 1 : s + 0.5) }'
}

fsrs_days_overdue() {
    local lc="$1" cc="${2:-0}" impact="${3:-1}"
    [ -z "$lc" ] && { echo 0; return; }
    # Anchor both timestamps at noon to avoid DST-boundary off-by-one
    # (spring-forward loses an hour → integer division truncates to prev day).
    local lc_sec today_sec
    # iso_epoch на неразобранной метке отдаёт 0 (а без библиотеки — пустоту); оба случая
    # значат «дату прочитать не удалось» и дают прежний ответ 0, а не разницу с 1970 годом.
    lc_sec=$(iso_epoch "$lc 12:00:00" "%Y-%m-%d %H:%M:%S" 2>/dev/null)
    if [ -z "$lc_sec" ] || [ "$lc_sec" = "0" ]; then echo 0; return; fi
    today_sec=$(iso_epoch "$(date +%Y-%m-%d) 12:00:00" "%Y-%m-%d %H:%M:%S" 2>/dev/null)
    if [ -z "$today_sec" ] || [ "$today_sec" = "0" ]; then echo 0; return; fi
    local stability days_since
    stability=$(fsrs_stability "$cc" "$impact")
    # Round to nearest whole day (handles remaining DST hour-drift within the window).
    days_since=$(( (today_sec - lc_sec + 43200) / 86400 ))
    echo $(( days_since - stability ))
}

fsrs_review_status() {
    local overdue="${1:-0}"
    [[ "$overdue" =~ ^-?[0-9]+$ ]] || { echo "fresh"; return; }
    if   [ "$overdue" -le 0 ];  then echo "fresh"
    elif [ "$overdue" -le 7 ];  then echo "due"
    elif [ "$overdue" -le 30 ]; then echo "overdue"
    else                              echo "critical"
    fi
}

# Score multiplier × 100 (integer math for bash consumers).
# fresh=100 (no penalty), due=100, overdue=80, critical=50.
fsrs_score_penalty_num() {
    case "${1:-fresh}" in
        fresh|due) echo 100 ;;
        overdue)   echo 80  ;;
        critical)  echo 50  ;;
        *)         echo 100 ;;
    esac
}

fsrs_marker() {
    case "${1:-fresh}" in
        fresh)    echo "" ;;
        due)      echo "⏳ due review" ;;
        overdue)  echo "⚠️ overdue" ;;
        critical) echo "🔴 critical overdue" ;;
        *)        echo "" ;;
    esac
}
