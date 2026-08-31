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
#   fsrs_experience_days_since <last_confirmed>             → int дней ОПЫТА ("" = дата не разобрана)
#   fsrs_days_overdue <last_confirmed> <cc> <impact>        → int (neg = fresh)
#   fsrs_review_status <days_overdue>                       → fresh|due|overdue|critical
#   fsrs_score_penalty_num <status>                         → int 0..100 (multiplier × 100)
#   fsrs_marker <status>                                    → string marker (empty for fresh)
#
# Прошедшее (D234, case experience-not-calendar-as-denominator): мера опыта — прожитые
# сессии, не календарь. «Дни» формулы — дни ОПЫТА: уникальные сессии реестра
# (~/.claude/sessions/registry.jsonl), начатые после last_confirmed, делённые на темп
# FSRS_SESSIONS_PER_DAY. Полгода тишины = 0 сессий = 0 прошедшего — база не гниёт в
# critical без единого опровержения; 1000 сессий за день = ~33 дня опыта — мир двигался,
# знание стареет. Календарные дни остаются фоллбеком там, где реестра нет (чистая
# установка, CI-контейнер): прежняя модель, а не отказ.
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

# --- Дни опыта (D234) ---

# Реестр сессий и темп. FSRS_SESSIONS_PER_DAY=30 — медиана сессий за активный день по
# последним 10 активным дням реестра на 2026-08-31 (5..71, медиана ≈33); пересчёт:
# jq -r '.started_at[:10]' registry.jsonl | sort | uniq -c. Константа, не самонастройка:
# ритм меняется медленнее, чем стоит скан реестра на каждом вызове.
FSRS_SESSION_REGISTRY="${FSRS_SESSION_REGISTRY:-$HOME/.claude/sessions/registry.jsonl}"
FSRS_SESSIONS_PER_DAY="${FSRS_SESSIONS_PER_DAY:-30}"

# Индекс «день → число новых уникальных сессий», кэш рядом с реестром, пересборка по
# mtime (реестр дописывается на границах сессий — пересборка редкая). Вызовы идут из
# цикла активатора по сотням файлов знаний: скан 3,5К строк jq на каждый файл
# непозволителен, awk по ~140-строчному индексу — дёшев.
_fsrs_build_index() {
    local reg="$FSRS_SESSION_REGISTRY" idx cur_fp
    [ -s "$reg" ] || return 1
    idx="${reg}.days-index"
    # Свежесть — по РАВЕНСТВУ отпечатка (mtime:байты), не по -nt: порядок mtime держится
    # на допущении «реестр только растёт вперёд», а restore/cp -p/rsync --times уводят
    # mtime назад, и -nt отдавал СТАРЫЙ индекс на новом содержимом (прожарка 31.08,
    # атака adv6 backwards_mtime). Нет file_mtime (portable-lib не рядом) — отпечаток
    # пуст, совпадения не будет, индекс пересобирается каждый вызов: медленнее, но верно.
    cur_fp=""
    command -v file_mtime >/dev/null 2>&1 \
        && cur_fp="$(file_mtime "$reg" 2>/dev/null):$(wc -c < "$reg" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$cur_fp" ] && [ -f "$idx" ] \
       && [ "$(head -1 "$idx" 2>/dev/null)" = "#reg $cur_fp" ]; then
        echo "$idx"; return 0
    fi
    command -v jq >/dev/null 2>&1 || return 1
    # Сессия с НЕСКОЛЬКИМИ started_at (resume через границу суток дописывает вторую
    # запись тем же session_id) относится к ПОЗДНЕМУ дню: sort -u даёт дни по
    # возрастанию, awk перезаписью держит последний. Приписка к раннему дню теряла
    # опыт после порога (прожарка 31.08, атака fsrs_dupday_session).
    { printf '#reg %s\n' "$cur_fp"
      jq -r 'select(.started_at != null and .session_id != null)
             | "\(.session_id)\t\(.started_at[:10])"' "$reg" 2>/dev/null \
        | sort -u \
        | awk -F'\t' '{ d[$1] = $2 } END { for (k in d) c[d[k]]++; for (day in c) print day "\t" c[day] }' \
        | sort
    } > "$idx.tmp.$$" 2>/dev/null || { rm -f "$idx.tmp.$$" 2>/dev/null; return 1; }
    # Одна строка-отпечаток без данных = валидных записей нет → календарный фоллбек,
    # как и раньше при пустом индексе.
    [ "$(wc -l < "$idx.tmp.$$" 2>/dev/null | tr -d '[:space:]')" -gt 1 ] 2>/dev/null \
        || { rm -f "$idx.tmp.$$" 2>/dev/null; return 1; }
    mv "$idx.tmp.$$" "$idx" 2>/dev/null || { rm -f "$idx.tmp.$$" 2>/dev/null; return 1; }
    echo "$idx"
}

# Дни ОПЫТА с даты: сессии, начатые строго после дня last_confirmed (сессии того же дня
# не считаются — как раньше days_since=0 в день подтверждения), делённые на темп с
# округлением. Пустой ответ = дата не разобрана — решает вызывающий.
fsrs_experience_days_since() {
    local d="${1:0:10}" idx n per="$FSRS_SESSIONS_PER_DAY"
    [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo ""; return; }
    [[ "$per" =~ ^[0-9]+$ ]] && [ "$per" -ge 1 ] || per=30
    idx=$(_fsrs_build_index 2>/dev/null) || idx=""
    if [ -n "$idx" ]; then
        n=$(awk -F'\t' -v d="$d" '/^#/ { next } $1 > d { s += $2 } END { print s + 0 }' "$idx" 2>/dev/null)
        if [[ "$n" =~ ^[0-9]+$ ]]; then
            echo $(( (n + per / 2) / per ))
            return
        fi
    fi
    # Календарный фоллбек (реестра нет). Anchor both timestamps at noon to avoid
    # DST-boundary off-by-one (spring-forward loses an hour → truncates to prev day).
    # iso_epoch на неразобранной метке отдаёт 0 (без библиотеки — пустоту); оба случая
    # значат «дату прочитать не удалось» → пустой ответ, а не разница с 1970 годом.
    local lc_sec today_sec
    lc_sec=$(iso_epoch "$d 12:00:00" "%Y-%m-%d %H:%M:%S" 2>/dev/null)
    if [ -z "$lc_sec" ] || [ "$lc_sec" = "0" ]; then echo ""; return; fi
    today_sec=$(iso_epoch "$(date +%Y-%m-%d) 12:00:00" "%Y-%m-%d %H:%M:%S" 2>/dev/null)
    if [ -z "$today_sec" ] || [ "$today_sec" = "0" ]; then echo ""; return; fi
    # Round to nearest whole day (handles remaining DST hour-drift within the window).
    echo $(( (today_sec - lc_sec + 43200) / 86400 ))
}

fsrs_days_overdue() {
    local lc="$1" cc="${2:-0}" impact="${3:-1}"
    [ -z "$lc" ] && { echo 0; return; }
    local stability days_since
    days_since=$(fsrs_experience_days_since "$lc")
    # Неразобранная дата — прежний ответ 0 (не «просрочено», не «свежее с буфером»).
    if [ -z "$days_since" ]; then echo 0; return; fi
    stability=$(fsrs_stability "$cc" "$impact")
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
