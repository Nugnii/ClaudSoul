#!/bin/bash
# fsrs-lib.sh — v1.0.0
#
# ПРЕФИКСЫ: fsrs_
# Объявление пространства имён (11 сентября 2026, D390). Функция этой библиотеки
# носит один из названных префиксов; имя с ведущим `_` считается внутренним и под
# правило не подпадает. Сверяет `hooks/lib-prefix-guard.sh` при записи файла.
# Список собран ИЗ ФАКТА, а не придуман: он фиксирует нынешнее состояние, чтобы
# разнобой не рос дальше — из 21 библиотеки с 3+ функциями лишь 10 держали 80%+
# имён под одним префиксом, а объявления не было ни у одной из 29.
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
#   fsrs_experience_days_since_epoch <epoch>                → int дней ОПЫТА ("" = отметки нет)
#   fsrs_days_overdue <last_confirmed> <cc> <impact>        → int (neg = fresh)
#   fsrs_review_status <days_overdue>                       → fresh|due|overdue|critical
#   fsrs_score_penalty_num <status>                         → int 0..100 (multiplier × 100)
#   fsrs_marker <status>                                    → string marker (empty for fresh)
#   fsrs_snapshot                                           → снимок индекса дней на прогон (D488)
#   fsrs_eval <last_confirmed> <cc> <impact>                → FSRS_DAYS FSRS_OVERDUE FSRS_STATUS FSRS_PENALTY
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

# Каждая формула — ядро, пишущее ответ в _FSRS_V без подоболочки (D488). Публичные функции
# печатают то же значение для разовых вызовов через $(...); цикл активатора по сотням
# файлов знаний зовёт fsrs_eval (внизу), собранный из тех же ядер: подоболочка на каждую
# функцию каждого файла стоила 1,35 с на 244 файлах.
_fsrs_stability_v() {
    local cc="${1:-0}" impact="${2:-1}"
    [[ "$cc" =~ ^-?[0-9]+$ ]] || cc=0
    [[ "$impact" =~ ^[0-9]+$ ]] || impact=1
    case "$cc" in -*) cc=0 ;; esac
    impact=$((10#$impact))
    [ "$impact" -lt 1 ] && impact=1
    [ "$impact" -gt 5 ] && impact=5
    # 7 × (1 + cc × 0.5) × (1 + (impact-1) × 0.25) = 7(2+cc)(3+impact)/8, половина
    # округляется вверх. Целая арифметика вместо awk: знаменатель — степень двойки, дробь
    # точная, ответ совпадает с прежним awk на всех целых входах, а процесса нет.
    # 10# — ведущие нули («08») bash иначе читает восьмеричными.
    _FSRS_V=$(( (7 * (2 + 10#$cc) * (3 + impact) + 4) / 8 ))
}
fsrs_stability() { _fsrs_stability_v "$@"; echo "$_FSRS_V"; }

# --- Дни опыта (D234) ---

# Реестр сессий и темп. FSRS_SESSIONS_PER_DAY=30 — КВАНТ работы: «день опыта» равен 30 уникальным сессиям реестра.
# Деление округляет к ближайшему: первый день опыта наступает на 15-й сессии, N-й — на (30N−15)-й.
# Это не рабочий день: новых уникальных сессий за активный день 4 (медиана на 31 августа 2026) — 7 (на 21 ноября
# 2026), то есть день опыта — 4–7 рабочих дней. Число 30 сняли 31 августа с ЗАПИСЕЙ реестра за день (10..71, медиана
# 33,5; `jq -r '.started_at[:10]' registry.jsonl | sort | uniq -c`), а счётчик ниже считает уникальные сессии — у одной
# сессии в среднем 8 записей. Ошибку единиц нашёл D1351; владелец оставил ритм прежним (21 ноября 2026): под него
# подобраны сроки замеров и старение знаний, верный темп дал бы 59 просроченных замеров вместо 18 и 626 знаний со
# штрафом из 1073 вместо 92. Срок, которому нужен рабочий день или чаще, пишется в коммитах («Nc» в реестре замеров).
# Константа, не самонастройка: скан реестра на каждом вызове дороже, чем стоит точность кванта.
FSRS_SESSION_REGISTRY="${FSRS_SESSION_REGISTRY:-$HOME/.claude/sessions/registry.jsonl}"
FSRS_SESSIONS_PER_DAY="${FSRS_SESSIONS_PER_DAY:-30}"

# Индекс «день → число новых уникальных сессий», кэш рядом с реестром, пересборка по
# mtime (реестр дописывается на границах сессий — пересборка редкая). Вызовы идут из
# цикла активатора по сотням файлов знаний: скан 3,5К строк jq на каждый файл
# непозволителен, awk по ~140-строчному индексу — дёшев.
# Рядом — индекс МГНОВЕНИЙ (`<реестр>.starts-index`, D1103): последнее начало каждой сессии в секундах эпохи, по
# возрастанию, с тем же отпечатком. Его читает счёт «после отметки» (`fsrs_experience_days_since_epoch`): отметка там —
# мгновение, и единица «прошедшего» берётся у неё, а не у календаря (корень R4). Тот же проход jq, что у индекса дней:
# второй сборщик реестра разошёлся бы с первым в правиле «сессия — по позднему началу».
_fsrs_build_index() {
    local reg="$FSRS_SESSION_REGISTRY" idx sidx cur_fp raw
    [ -s "$reg" ] || return 1
    idx="${reg}.days-index"; sidx="${reg}.starts-index"
    # Свежесть — по РАВЕНСТВУ отпечатка (mtime:байты), не по -nt: порядок mtime держится
    # на допущении «реестр только растёт вперёд», а restore/cp -p/rsync --times уводят
    # mtime назад, и -nt отдавал СТАРЫЙ индекс на новом содержимом (прожарка 31.08,
    # атака adv6 backwards_mtime). Нет file_mtime (portable-lib не рядом) — отпечаток
    # пуст, совпадения не будет, индекс пересобирается каждый вызов: медленнее, но верно.
    cur_fp=""
    command -v file_mtime >/dev/null 2>&1 \
        && cur_fp="$(file_mtime "$reg" 2>/dev/null):$(wc -c < "$reg" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$cur_fp" ] && [ -f "$idx" ] && [ -f "$sidx" ] \
       && [ "$(head -1 "$idx" 2>/dev/null)" = "#reg $cur_fp" ] \
       && [ "$(head -1 "$sidx" 2>/dev/null)" = "#reg $cur_fp" ]; then
        echo "$idx"; return 0
    fi
    command -v jq >/dev/null 2>&1 || return 1
    # Сессия с НЕСКОЛЬКИМИ started_at (resume через границу суток дописывает вторую
    # запись тем же session_id) относится к ПОЗДНЕМУ дню: sort -u даёт дни по
    # возрастанию, awk перезаписью держит последний. Приписка к раннему дню теряла
    # опыт после порога (прожарка 31.08, атака fsrs_dupday_session). Третье поле — то же начало в секундах эпохи:
    # цифр поровну, и порядок sort внутри дня — по времени, так что последней остаётся поздняя запись.
    raw="$idx.raw.$$"
    jq -r 'select(.started_at != null and .session_id != null)
           | "\(.session_id)\t\(.started_at[:10])\t\(.started_at | try fromdateiso8601 catch "")"' "$reg" 2>/dev/null \
        | sort -u > "$raw" 2>/dev/null || { rm -f "$raw" 2>/dev/null; return 1; }
    { printf '#reg %s\n' "$cur_fp"
      awk -F'\t' '{ d[$1] = $2 } END { for (k in d) c[d[k]]++; for (day in c) print day "\t" c[day] }' "$raw" \
        | sort
    } > "$idx.tmp.$$" 2>/dev/null || { rm -f "$idx.tmp.$$" "$raw" 2>/dev/null; return 1; }
    { printf '#reg %s\n' "$cur_fp"
      awk -F'\t' '{ e[$1] = $3 } END { for (k in e) if (e[k] != "") print e[k] }' "$raw" | sort -n
    } > "$sidx.tmp.$$" 2>/dev/null || rm -f "$sidx.tmp.$$" 2>/dev/null
    rm -f "$raw" 2>/dev/null
    # Одна строка-отпечаток без данных = валидных записей нет → календарный фоллбек,
    # как и раньше при пустом индексе.
    [ "$(wc -l < "$idx.tmp.$$" 2>/dev/null | tr -d '[:space:]')" -gt 1 ] 2>/dev/null \
        || { rm -f "$idx.tmp.$$" "$sidx.tmp.$$" 2>/dev/null; return 1; }
    # Индекс мгновений не собрался — индекс дней всё равно годен; счёт «после отметки» уйдёт в календарный фоллбек,
    # а следующий вызов соберёт оба заново (свежесть требует обоих).
    [ -f "$sidx.tmp.$$" ] && { mv "$sidx.tmp.$$" "$sidx" 2>/dev/null || rm -f "$sidx.tmp.$$" 2>/dev/null; }
    mv "$idx.tmp.$$" "$idx" 2>/dev/null || { rm -f "$idx.tmp.$$" 2>/dev/null; return 1; }
    echo "$idx"
}

# Снимок индекса дней в памяти процесса (D488). Цикл активатора зовёт счёт опыта на
# сотни файлов знаний, и каждый вызов сверял отпечаток реестра и запускал awk — около
# десяти процессов. Вызывающий берёт снимок один раз (fsrs_snapshot), подоболочки $(...)
# наследуют его без новых процессов. Реестр внутри такого прогона считается неподвижным:
# он дописывается на границах сессий, а прогон длится секунды. Снимок — по явному вызову:
# долгоживущий вызывающий без него сверяет реестр на каждом вызове, как раньше.
fsrs_snapshot() {
    local idx
    _FSRS_SNAP=""; _FSRS_MEMO="|"
    idx=$(_fsrs_build_index 2>/dev/null) || return 0
    _FSRS_SNAP=$(grep -v '^#' "$idx" 2>/dev/null) || _FSRS_SNAP=""
}

# Дни ОПЫТА с даты: сессии, начатые строго после дня last_confirmed (сессии того же дня
# не считаются — как раньше days_since=0 в день подтверждения), делённые на темп с
# округлением. Пустой ответ = дата не разобрана — решает вызывающий.
_fsrs_days_v() {
    local d="${1:0:10}" idx n per="$FSRS_SESSIONS_PER_DAY" _day _cnt
    _FSRS_V=""
    [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 0
    [[ "$per" =~ ^[0-9]+$ ]] && [ "$per" -ge 1 ] || per=30
    if [ -n "${_FSRS_SNAP:-}" ]; then
        # Под снимком ответ зависит только от даты и темпа — память на прогон по ключу
        # «темп:дата»: дат в базе в разы меньше, чем файлов.
        case "${_FSRS_MEMO:-}" in
            *"|$per:$d="*) _FSRS_V="${_FSRS_MEMO#*|"$per:$d"=}"; _FSRS_V="${_FSRS_V%%|*}"; return 0 ;;
        esac
        n=0
        while IFS=$'\t' read -r _day _cnt; do
            case "$_cnt" in ''|*[!0-9]*) continue ;; esac
            [[ "$_day" > "$d" ]] && n=$((n + 10#$_cnt))
        done <<< "$_FSRS_SNAP"
        _FSRS_V=$(( (n + per / 2) / per ))
        _FSRS_MEMO="${_FSRS_MEMO:-|}$per:$d=$_FSRS_V|"
        return 0
    fi
    idx=$(_fsrs_build_index 2>/dev/null) || idx=""
    if [ -n "$idx" ]; then
        n=$(awk -F'\t' -v d="$d" '/^#/ { next } $1 > d { s += $2 } END { print s + 0 }' "$idx" 2>/dev/null)
        if [[ "$n" =~ ^[0-9]+$ ]]; then
            _FSRS_V=$(( (n + per / 2) / per ))
            return 0
        fi
    fi
    # Календарный фоллбек (реестра нет). Anchor both timestamps at noon to avoid
    # DST-boundary off-by-one (spring-forward loses an hour → truncates to prev day).
    # iso_epoch на неразобранной метке отдаёт 0 (без библиотеки — пустоту); оба случая
    # значат «дату прочитать не удалось» → пустой ответ, а не разница с 1970 годом.
    local lc_sec today_sec
    lc_sec=$(iso_epoch "$d 12:00:00" "%Y-%m-%d %H:%M:%S" 2>/dev/null)
    if [ -z "$lc_sec" ] || [ "$lc_sec" = "0" ]; then return 0; fi
    today_sec=$(iso_epoch "$(date +%Y-%m-%d) 12:00:00" "%Y-%m-%d %H:%M:%S" 2>/dev/null)
    if [ -z "$today_sec" ] || [ "$today_sec" = "0" ]; then return 0; fi
    # Round to nearest whole day (handles remaining DST hour-drift within the window).
    _FSRS_V=$(( (today_sec - lc_sec + 43200) / 86400 ))
}
fsrs_experience_days_since() { _fsrs_days_v "$@"; echo "$_FSRS_V"; }

# Периодичность РАБОТЫ считается той же мерой, что старение знаний (D234). Обёртка нужна
# затем, что механизмы срока держат отметку прогона в epoch, а счётчик опыта принимает
# дату; без неё каждый потребитель писал свой `(now - last) / 86400` и тем ЗАНОВО объявлял
# единицу календарной. Замер 10 сентября 2026: мест, решающих «пора ли», шесть — календарём
# решали шесть, опытом ноль, при том что счётчик опыта лежал в этом же файле с августа.
#
# Повод — слово владельца: «Я за день могу 100500 инструментов сделать, а могу через год
# компьютер открыть. ВРЕМЯ НЕ ПОКАЗАТЕЛЬ при периодичности». Календарный срок кричит «пора»
# после года тишины, когда не изменилось ничего, и молчит внутри дня, за который дерево
# переписали.
#
# `date -r` — BSD (macOS); на Linux тот же ключ значит «время ФАЙЛА», не находит его и
# уступает место GNU-форме `-d @`. Порядок именно такой: у GNU `-r` не ошибётся молча
# (pattern-shell-portability).
#
# Пустая, нулевая или нечисловая отметка — «прогона не было»: ответ пуст, решение остаётся
# за вызывающим, как и у неразобранной даты выше. Пустота ОТЛИЧИМА от нуля намеренно: ноль
# значит «наработано нисколько», пустота — «сказать нечем».
#
# МГНОВЕНИЕ ПРОТИВ МГНОВЕНИЙ (D1103, 26 октября 2026, корень R4). Прежде отметка переводилась в МЕСТНУЮ дату, а сессии
# считались по UTC-дате строго после неё: сессии дня отметки, начатые позже неё, не засчитывались никогда, а отметка
# «минус 48 часов» через переход на зимнее время переезжала на дату сессий — нога T12 test_measurement_due краснела в
# 23:00–24:00. Теперь считаются сессии, чьё последнее начало позже мгновения отметки (индекс мгновений рядом с индексом
# дней); пояс и переход времени в счёт не входят. Календарь — только без реестра, как и прежде.
# Без реестра отметка — тоже мгновение, а единица — сутки по 86400 секунд от отметки до сейчас (у реестра единица другая —
# сессии на темп; D1164, 2 ноября 2026): прежде отметка шла в
# местную дату и считались календарные дни, и «30 суток назад» в 23:00–24:00 после перехода на зимнее время давало 29.
fsrs_experience_days_since_epoch() {
    local _e="${1:-}" _d="" _idx="" _n _s _now per="$FSRS_SESSIONS_PER_DAY"
    case "$_e" in ''|*[!0-9]*) echo ""; return ;; esac
    [ "$_e" -gt 0 ] 2>/dev/null || { echo ""; return; }
    [[ "$per" =~ ^[0-9]+$ ]] && [ "$per" -ge 1 ] || per=30
    _s="${FSRS_SESSION_REGISTRY}.starts-index"
    if _idx=$(_fsrs_build_index 2>/dev/null) && [ -f "$_s" ] \
       && [ "$(head -1 "$_s" 2>/dev/null)" = "$(head -1 "$_idx" 2>/dev/null)" ]; then
        _n=$(awk -v m="$_e" '/^#/ { next } ($1 + 0) > (m + 0) { c++ } END { print c + 0 }' "$_s" 2>/dev/null)
        if [[ "$_n" =~ ^[0-9]+$ ]]; then echo $(( (_n + per / 2) / per )); return; fi
    fi
    if [ -z "$_idx" ]; then
        _now=$(date +%s)
        [ "$_e" -le "$_now" ] && echo $(( (_now - _e) / 86400 )) || echo 0
        return
    fi
    _d=$(date -r "$_e" +%Y-%m-%d 2>/dev/null) || _d=""
    [ -n "$_d" ] || _d=$(date -d "@$_e" +%Y-%m-%d 2>/dev/null) || _d=""
    [ -n "$_d" ] || { echo ""; return; }
    fsrs_experience_days_since "$_d"
}

_fsrs_overdue_v() {
    local lc="${1:-}" days
    if [ -z "$lc" ]; then _FSRS_V=0; return 0; fi
    _fsrs_days_v "$lc"; days="$_FSRS_V"
    # Неразобранная дата — прежний ответ 0 (не «просрочено», не «свежее с буфером»).
    if [ -z "$days" ]; then _FSRS_V=0; return 0; fi
    _fsrs_stability_v "${2:-0}" "${3:-1}"
    _FSRS_V=$(( days - _FSRS_V ))
}
fsrs_days_overdue() { _fsrs_overdue_v "$@"; echo "$_FSRS_V"; }

_fsrs_status_v() {
    local overdue="${1:-0}"
    if ! [[ "$overdue" =~ ^-?[0-9]+$ ]]; then _FSRS_V="fresh"
    elif [ "$overdue" -le 0 ];  then _FSRS_V="fresh"
    elif [ "$overdue" -le 7 ];  then _FSRS_V="due"
    elif [ "$overdue" -le 30 ]; then _FSRS_V="overdue"
    else                              _FSRS_V="critical"
    fi
}
fsrs_review_status() { _fsrs_status_v "$@"; echo "$_FSRS_V"; }

# Score multiplier × 100 (integer math for bash consumers).
# fresh=100 (no penalty), due=100, overdue=80, critical=50.
_fsrs_penalty_v() {
    case "${1:-fresh}" in
        fresh|due) _FSRS_V=100 ;;
        overdue)   _FSRS_V=80  ;;
        critical)  _FSRS_V=50  ;;
        *)         _FSRS_V=100 ;;
    esac
}
fsrs_score_penalty_num() { _fsrs_penalty_v "$@"; echo "$_FSRS_V"; }

# fsrs_eval <last_confirmed> <cc> <impact> — всё, что нужно ранжированию, одним вызовом и
# без подоболочек (D488): FSRS_DAYS (дни опыта, пусто — дата не разобрана), FSRS_OVERDUE,
# FSRS_STATUS, FSRS_PENALTY. Значения те же, что у fsrs_experience_days_since,
# fsrs_days_overdue, fsrs_review_status и fsrs_score_penalty_num: ядра общие.
fsrs_eval() {
    _fsrs_days_v "${1:-}"; FSRS_DAYS="$_FSRS_V"
    _fsrs_overdue_v "$@"; FSRS_OVERDUE="$_FSRS_V"
    _fsrs_status_v "$FSRS_OVERDUE"; FSRS_STATUS="$_FSRS_V"
    _fsrs_penalty_v "$FSRS_STATUS"; FSRS_PENALTY="$_FSRS_V"
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
