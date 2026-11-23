#!/usr/bin/env bash
# disagreement-lib.sh — общий доступ к контуру опровержения (v1.12.0).
#
# ПРЕФИКСЫ: dis_
# Объявление пространства имён (11 сентября 2026, D390). Функция этой библиотеки
# носит один из названных префиксов; имя с ведущим `_` считается внутренним и под
# правило не подпадает. Сверяет `hooks/lib-prefix-guard.sh` при записи файла.
# Список собран ИЗ ФАКТА, а не придуман: он фиксирует нынешнее состояние, чтобы
# разнобой не рос дальше — из 21 библиотеки с 3+ функциями лишь 10 держали 80%+
# имён под одним префиксом, а объявления не было ни у одной из 29.
#
# Зачем библиотека. До v1.12.0 контур был разорван посередине, и это объясняет,
# почему на 25 июля 2026 `contradicted_count` был равен нулю во всех 265 знаниях базы
# (нынешнее число — `scripts/doc-figures.sh kb_contradicted_nonzero`):
#
#   ПРОДЮСЕР (knowledge-activator) пишет в disagreement-pending-<SID>.jsonl текущей сессии.
#   АЛЕРТ (session-collector) считает только файл ТЕКУЩЕЙ сессии, но кладёт текст в
#     pending-alerts.txt, и показывается он на СЛЕДУЮЩЕЙ сессии.
#   ЗАКРЫТИЕ (/learn Step 4e) читает disagreement-pending-<SID>.jsonl — снова текущей.
#
# То есть на следующей сессии агент видит алерт про запись, которой в его файле нет,
# и закрыть её документированной процедурой физически не может. На живых данных на
# 28 июля 2026 это было видно точно: из 5 записей закрыта одна — та, что закрылась через
# 10 минут внутри своей же сессии. Остальные четыре висели с 25, 26 и 27 июля.
#
# Библиотека даёт всем трём потребителям один способ смотреть на контур целиком:
# по ВСЕМ файлам, а не по файлу текущей сессии.
#
# Функции:
#   dis_scan_open   [state_dir]        → строки `sid|key|date|confidence|tool` (открытые)
#   dis_expire_old  [days] [state_dir] → закрывает просроченные как not_applicable, печатает счёт
#   dis_harvest_corrections sid [state_dir] [window_min] [max_candidates]
#                                      → второй продюсер: поправка собеседника вскоре после
#                                        инжекта знания даёт запись-кандидата; печатает число созданных
#   dis_stats       [state_dir]        → `closed expired open` (через пробел)
#
# Словарь исходов (четвёртый добавлен 2026-08-01):
#   confirmed_knowledge     — знание применялось и оказалось верным      → confirmed++
#   outdated_knowledge      — знание противоречило делу                  → contradicted++
#   applicable_not_followed — знание ОТНОСИЛОСЬ к делу и НЕ БЫЛО применено → счётчики не трогать
#   not_applicable          — знание просто не относилось к делу         → счётчики не трогать
#
# Зачем четвёртый. Трёх не хватало ровно на тот случай, ради которого проект существует:
# правило о поведении агента бывает не только верным, неверным или посторонним — оно бывает
# УМЕСТНЫМ И ПРОИГНОРИРОВАННЫМ. Раньше такой случай приходилось записывать как
# `not_applicable` («не относилось»), что прямая неправда, либо как `confirmed`
# («применялось»), что завышает счётчик. Первый живой случай: за сессию 2026-07-31 запущены
# две долгие проверки (65 и 64 мин), знание `progress-visibility-long-async` предписывает
# назвать ориентир заранее — не названо ни разу, при том что знание висело в контексте.
#
# Счётчики не трогаются намеренно: пропуск не подтверждает и не опровергает знание, он
# измеряет РАЗРЫВ между знанием и действием. Для этого у него отдельная метрика.
#
# Разделитель `|` безопасен: key — имя файла знания, tool — имя инструмента.

# Портируемый разбор ISO-времени (single source — see portable-lib.sh): `date -j`
# понимает только BSD, на Linux все три вызова ниже падали (pattern-shell-portability).
# Путь к библиотеке ищется двумя способами, потому что источают эту библиотеку и из zsh
# (`/learn` Step 4e через Bash-инструмент), где `BASH_SOURCE` не существует и относительный
# путь уехал бы в текущий каталог — тот же приём, что и в session-collector.sh.
# Запасная ветка не фатальна намеренно: `exit 1` при недоставленном файле убил бы
# Stop-хук и metrics-collector целиком, а не одну строку метрики.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
[ -f "$PORTABLE_LIB" ] || PORTABLE_LIB="$HOME/.claude/hooks/portable-lib.sh"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
else
    iso_epoch() {
        local ts="${1:-}"
        [ -n "$ts" ] || { echo 0; return; }
        case "$ts" in
            *Z)
                date -u -d "$ts" +%s 2>/dev/null && return
                date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null && return
                ;;
            *)
                date -d "$ts" +%s 2>/dev/null && return
                date -j -f "%Y-%m-%dT%H:%M:%S" "$ts" +%s 2>/dev/null && return
                ;;
        esac
        echo 0
    }
fi
# Жнецы ниже зовут `iso_epoch_lines` по имени (D1000), а под `set -u` недостающее имя убивает Stop-хук
# на первом же вызове. Ветка нужна в двух случаях: библиотеки времени нет вовсе, либо установлена
# старая portable-lib без этой функции. Запасной вариант — построчный iso_epoch: ответ тот же,
# только с процессами на каждую метку, как до D1000.
if ! command -v iso_epoch_lines >/dev/null 2>&1; then
    iso_epoch_lines() {
        local line
        while IFS= read -r line || [ -n "$line" ]; do iso_epoch "$line"; done
        return 0
    }
fi

# Две шкалы в одном контуре. `correction-fired` пишет UTC с суффиксом `Z`,
# `injection-log` до v1.12.0 писал ЛОКАЛЬНОЕ время без суффикса. На машине с +02:00
# наивный джойн этих двух логов разъехался бы на два часа, а с переходом на летнее
# время — плавал бы. Суффикс `Z` и есть маркер шкалы, по нему и различаем: новые
# строки однозначны, старые читаются как локальные и не переписываются.
_dis_epoch() { iso_epoch "${1:-}"; }

_dis_state_dir() {
    echo "${1:-${STATE_DIR:-$HOME/.claude/hooks/state}}"
}

# Строки журналов несогласия «за всё время» — «имя файла ⇥ mtime ⇥ строка» (D1008): архив уборки (`hooks/lib/
# state_archive.py`), затем живые файлы прежней маской — она шире формы члена архива (у фикстур имена без UUID). Без
# библиотеки архива (установка старше D1008) — только живые файлы: архива тогда и не было.
_dis_lines() {
    local sd="$1" sa f rc=0
    sa="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/lib/state_archive.py"
    # Под zsh `$0` внутри функции — имя функции, и путь выше указывает в текущий каталог: архив молча пропадал
    # (скептик D1008, H1). Запасной путь — установка, как у `_of_rcl` в `hooks/lib/open-findings-lib.sh`.
    [ -f "$sa" ] || sa="$HOME/.claude/hooks/lib/state_archive.py"
    # Архив не прочитан — код 2: вывод тогда неполон, и вызывающий обязан это различить (род B, второй скептик M-1).
    if [ -f "$sa" ]; then python3 "$sa" archived "$sd" disagreement-pending || rc=2; fi
    for f in "$sd"/disagreement-pending-*.jsonl; do
        [ -f "$f" ] && [ -r "$f" ] && awk -v n="${f##*/}" '{ print n "\t0\t" $0 }' "$f" 2>/dev/null
    done
    return "$rc"
}

# n-я строка текста (с единицы), без процессов. Жнец поправок по номеру из _dis_join_pairs достаёт
# ИСХОДНУЮ строку даты: по ней, а не по эпохе, ищется snippet в correction-fired. Цикл read по
# here-doc, а не срез `${t#*перевод}` в цикле: срез копирует остаток списка на каждой строке, и на
# bash 3.2 цена квадратична (замер 17 октября 2026, строка 3000 из 3000: срез 2,4 с на вызов, read 0,02 с).
_dis_nth() {
    local n="$1" line="" i=0
    while [ "$i" -lt "$n" ] && IFS= read -r line; do i=$((i + 1)); done <<EOF
$2
EOF
    printf '%s' "$line"
}

# Колонка показов для _dis_join_pairs: `ts` — метка, `rec` — файл<TAB>уверенность. Разбор тем же
# `IFS=$'\t' read -r`, что у прежнего цикла (табуляция — пробельный разделитель: пустая дата СДВИГАЕТ
# поля), строка без файла пропускается там же, где пропускал её прежний цикл. Вывод собирает
# вызывающий подстановкой команды: накопление `x="${x}…"` в цикле на bash 3.2 КВАДРАТИЧНО (замер
# 17 октября 2026, 10 000 строк: накопление 13,6 с, подстановка команды 0,1 с).
_dis_inj_col() {
    local mode="$1" i_ts i_file i_conf
    while IFS=$'\t' read -r i_ts i_file i_conf; do
        [ -n "$i_file" ] || continue
        if [ "$mode" = ts ]; then printf '%s\n' "$i_ts"; else printf '%s\t%s\n' "$i_file" "$i_conf"; fi
    done <<EOF
$2
EOF
}

# Соединение «провал (поправка) × показ знания» для обоих жнецов — ОДИН процесс awk вместо процессов
# на пару (D1000, 17 октября 2026).
#
# Замер. Вложенный цикл «провалы × показы» запускал на каждую пару процессы: `_dis_epoch` (sed и date
# дважды) и `grep -Fq` по pending-файлу. На живых данных сессии 19c775dd это 909 провалов (2 серии
# ошибок и 907 внешних событий ЗА ВСЁ ВРЕМЯ из pending-events.jsonl) × 239 показов = 217 251 пара,
# 257 с из 267 с границы хода. Журнал событий общий и только растёт, показы копятся к концу
# сессии — граница дорожала со временем. Теперь время каждой метки разбирается ОДИН раз
# (`iso_epoch_lines`), присутствие ключа в pending-файле считается ОДИН раз на ключ, а пары
# перебирает awk в памяти. Замер после починки (17 октября 2026, те же данные, bash 3.2 и BSD awk,
# три прогона подряд): соединение 0,16 с (разбор 909 меток из них 0,035 с), вся `dis_harvest_failures`
# 0,5-0,9 с, и почти всё это — jq по журналу показов на 18,8 МБ, то есть цена чтения, а не пар.
# Тождество прежнему циклу доказано сличением HEAD с нынешней редакцией: 1924 прогона обеих функций
# на 782 фикстурах (720 случайных — формы меток, повторы ключей, окно на границе, потолок
# 0/1/3/нечисловой, пустая дата показа — и 62 целевых), столько же со старой portable-lib (запасной
# `iso_epoch_lines` ниже) и 16 прогонов на живых данных двух сессий — расхождений ноль; ноги — в
# `hooks/tests/test_harvest_failures.sh` (T8-T15) и `hooks/tests/test_iso_epoch_lines.sh`.
#
# Семантика прежнего цикла сохранена дословно — тот же порядок (внешний перебор — провалы в порядке
# источника, внутренний — показы в порядке журнала) и те же проверки в том же порядке: пустой файл
# показа — пропуск; набран потолок кандидатов — стоп всего; ключ (файл без .md) уже в seen — пропуск;
# в pending-файле есть `"key":"<ключ>"` — ключ в seen и пропуск; эпоха показа <= 0 — пропуск; показ
# позже провала — пропуск; разница больше окна — пропуск; иначе кандидат, ключ в seen. Эпоха
# провала <= 0 снимает провал целиком. TSV показа разбирается тем же `IFS=$'\t' read -r`, что и
# раньше: табуляция там пробельный разделитель, пустая дата (`.date` отсутствует — jq отдаёт пустое
# поле) СДВИГАЕТ поля, и прежний исход (показ с эпохой 0, пропуск) остаётся тем же ПО ПОСТРОЕНИЮ.
#
# Аргументы: список провалов (строка на метку), TSV показов `дата<TAB>файл<TAB>уверенность`, окно в
# секундах, потолок кандидатов, pending-файл. Печатает по строке на кандидата в порядке создания:
# `номер_провала<TAB>файл<TAB>уверенность`; записывает кандидата вызывающий — формат записи у
# жнецов разный. Всегда возвращает 0.
#
# Пределы. (1) Перебор пар остаётся O(провалы × показы), но в одном процессе: 217 251 пара вместе с
# запуском awk и разбором меток — 0,16 с, а не минуты; при 10^7 пар (годы журнала событий) перебор
# придётся отсекать по времени. (2) Списки и pending-файл целиком в памяти. (3) Два отличия от
# прежнего цикла, оба видны ТОЛЬКО на ключе со знаком `|` или `"`, а имя файла знания их не несёт
# (kebab-case; замер 17 октября 2026: ноль таких имён во всём живом журнале показов, 18,8 МБ):
# прежний `seen` был строкой с разделителем `|` — ключ `a|b` прятал ключи `a` и `b`;
# прежний цикл перечитывал pending-файл на каждой паре, и запись, дописанная в этом же прогоне для
# ключа `a"b`, содержала подстроку `"key":"a"` и прятала ключ `a`. Здесь `seen` — массив, файл
# читается один раз. Оба прежних поведения — ложные пропуски, воспроизводить их нечем и незачем.
# (4) Ранний выход на потолке стоит в END, то есть после чтения всего ввода: ранний потребитель
# после большого производителя дал бы SIGPIPE 141 под `set -o pipefail` (D239), а ввод идёт через
# here-doc, не через конвейер. (5) Только на BSD awk (macOS) и bash 3.2: mawk, gawk и bash 5.2
# (Linux CI) на этой машине не гонялись — код держится в POSIX-подмножестве awk.
_dis_join_pairs() {
    local outer="$1" injections="$2" window_s="$3" max_cand="$4" pend_file="$5"
    local ts_list rec_list ie_list fe_list
    # Нечисловой потолок прежний цикл ронял сравнением `[ -lt ]` на первой достижимой паре:
    # ответ 0 и ни одной записи. Здесь то же самое, без обращения к awk.
    [ "$max_cand" -eq "$max_cand" ] 2>/dev/null || return 0
    ts_list=$(_dis_inj_col ts "$injections")
    # Годных показов нет — пары составлять не из чего. Метка годного показа не бывает пустой: пустое
    # поле TSV не стоит перед непустым (табуляция — пробельный разделитель), и подстановка команды,
    # срезающая хвостовые переводы строки, не теряет ни одной строки колонки.
    [ -n "$ts_list" ] || return 0
    rec_list=$(_dis_inj_col rec "$injections")
    ie_list=$(iso_epoch_lines <<<"$ts_list")
    fe_list=$(iso_epoch_lines <<<"$outer")
    # Три секции через строку `#`: эпохи показов, их `файл<TAB>уверенность`, эпохи провалов. Строкой `#`
    # не бывает ни эпоха (цифры), ни запись показа (в ней есть табуляция). Число эпох показов обязано
    # равняться числу записей — иначе пары съехали бы молча, и awk не отдаёт ничего.
    DIS_PEND_FILE="$pend_file" awk -v ws="$window_s" -v mc="$max_cand" '
        function inpend(key,   needle, j) {
            if (key in pc) return pc[key]
            if (!loaded) {
                if (pf != "") {
                    while ((getline pl < pf) > 0) plines[++np] = pl
                    close(pf)
                }
                loaded = 1
            }
            needle = "\"key\":\"" key "\""
            pc[key] = 0
            for (j = 1; j <= np; j++)
                if (index(plines[j], needle) > 0) { pc[key] = 1; break }
            return pc[key]
        }
        BEGIN { pf = ENVIRON["DIS_PEND_FILE"]; ws += 0; mc += 0; sec = 0; m = 0; nr = 0; nf = 0; made = 0 }
        $0 == "#" { sec++; next }
        sec == 0 { ie[++m] = $0 + 0; next }
        sec == 1 {
            j = ++nr; rec[j] = $0
            k = $0; p = index(k, "\t"); if (p > 0) k = substr(k, 1, p - 1)
            sub(/\.md$/, "", k); ik[j] = k
            next
        }
        { fe[++nf] = $0 + 0 }
        END {
            if (m != nr) exit
            for (f = 1; f <= nf; f++) {
                if (fe[f] <= 0) continue
                for (i = 1; i <= m; i++) {
                    if (made >= mc) exit
                    k = ik[i]
                    if (k in seen) continue
                    if (inpend(k)) { seen[k] = 1; continue }
                    if (ie[i] <= 0) continue
                    if (ie[i] > fe[f]) continue
                    if (fe[f] - ie[i] > ws) continue
                    print f "\t" rec[i]
                    seen[k] = 1; made++
                }
            }
        }
    ' 2>/dev/null <<EOF || true
$ie_list
#
$rec_list
#
$fe_list
EOF
    return 0
}

# Открытые записи по всем сессиям.
# Ключ считается закрытым, если по нему в ТОМ ЖЕ файле есть более поздняя строка
# с outcome != pending. Один и тот же ключ в разных сессиях — разные записи.
dis_scan_open() {
    local sd; sd=$(_dis_state_dir "${1:-}")
    # Объявления подняты из тела цикла: в zsh повторное `local x` для уже существующей
    # переменной ПЕЧАТАЕТ `x=значение` в stdout, в bash молчит. Выдача этой функции
    # разбирается по колонкам, а /learn Step 4e предписывает звать её через Bash-инструмент,
    # то есть под zsh — и три мусорные строки `sid=...` были прочитаны как три открытые
    # записи. Прежний фикс в dis_stats заменил `read <<EOF` на позиционный разбор, то есть
    # лечил конструкцию, а не причину: причина — объявление внутри повторяемой области.
    # ОДИН ПРОЦЕСС НА ВСЕ ФАЙЛЫ (D498). Процесс `awk` на файл стоил 0,84 с при 168 файлах
    # сессий, и цена каждого Stop росла с числом прожитых сессий. Состояние сбрасывается на
    # границе файла: ключ закрывает только строка ТОГО ЖЕ файла, как прежде.
    # Сессия — ИМЯ файла, а не граница файла (D1008): уборка переносит строки старых файлов в архив семейства, и одна
    # сессия может прийти архивным блоком и воссозданным живым файлом (запись об истечении в чужой сессии).
    # Архив не прочитан — перечень неполон и функция выходит кодом 2 (вызывающий называет это вслух).
    # for-in вместо length(array) — BSD awk (pattern-shell-portability).
    local rows rc=0
    rows=$(_dis_lines "$sd") || rc=$?
    printf '%s\n' "$rows" | awk -F'\t' '
        function field(line, name,   parts, val) {
            if (split(line, parts, "\"" name "\":\"") < 2) return ""
            split(parts[2], val, "\"")
            return val[1]
        }
        {
            line = $0; sub(/^[^\t]*\t[^\t]*\t/, "", line)
            k = field(line, "key")
            if (k == "") next
            id = $1 SUBSEP k
            if (line ~ /"outcome":"pending"/) {
                d[id] = field(line, "date")
                t[id] = field(line, "tool")
                c[id] = 0
                if (match(line, /"confidence":[0-9]+/))
                    c[id] = substr(line, RSTART + 13, RLENGTH - 13)
                open[id] = 1
            } else {
                delete open[id]
            }
        }
        END {
            for (id in open) {
                split(id, p, SUBSEP)
                sid = p[1]; sub(/^disagreement-pending-/, "", sid); sub(/\.jsonl$/, "", sid)
                printf "%s|%s|%s|%s|%s\n", sid, p[2], d[id], c[id], t[id]
            }
        }
    ' 2>/dev/null | sort || true
    return "$rc"
}

# Автогашение просроченных.
#
# Почему возраст в ДНЯХ, а не «N сессий», как формулировалось в плане: сессия не
# единица времени. В живых данных одна сессия дала 156 событий Stop и шла больше
# суток, другая закрылась за минуту. Считать по сессиям значит мерить линейкой,
# длина которой меняется в 150 раз. Неразрешимой запись делает не число сессий, а
# ушедший контекст — а он уходит по времени.
#
# Счётчики знаний НЕ трогаются: истёкшая запись это отсутствие данных, а не
# подтверждение. Иначе автогашение раздувало бы confirmed_count тишиной.
#
# Ревизия D234 (31 августа 2026): оставлено календарным осознанно. Это исключение
# «физического времени» из case-2026-08-31-experience-not-calendar-as-denominator:
# неразрешимой запись делает ушедший контекст, а контекст уходит по времени — довод
# и замер (сессия как линейка меняется в 150 раз) выше по этой же шапке.
dis_expire_old() {
    local days="${1:-${DISAGREEMENT_EXPIRE_DAYS:-7}}"
    local sd; sd=$(_dis_state_dir "${2:-}")
    local now_s cutoff n=0
    now_s=$(date -u +%s)
    cutoff=$(( now_s - days * 86400 ))

    local line sid key dt rec_s
    while IFS='|' read -r sid key dt _ _; do
        [ -n "$key" ] || continue
        rec_s=$(_dis_epoch "$dt")
        [ "$rec_s" -gt 0 ] 2>/dev/null || continue
        [ "$rec_s" -lt "$cutoff" ] || continue
        printf '{"date":"%s","key":"%s","outcome":"not_applicable","expired":true,"age_days":%d}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$key" "$(( (now_s - rec_s) / 86400 ))" \
            >> "$sd/disagreement-pending-${sid}.jsonl" 2>/dev/null || true
        n=$((n + 1))
    done <<EOF
$(dis_scan_open "$sd")
EOF
    echo "$n"
}

# Второй продюсер: поправка собеседника вскоре после инжекта знания (v1.12.0).
#
# Зачем второй. Первый продюсер (knowledge-activator) пишет запись только при инжекте
# знания уровня блокера — а знание попадает в этот уровень потому, что подтвердилось
# пять раз и больше. Выборка берётся там, где знание вероятнее всего право, поэтому
# исход почти всегда `confirmed`, и счётчик структурно не может убыть. За всю историю
# базы до 28 июля 2026 contradicted_count был равен нулю во всех 265 знаниях.
#
# Здесь выборка берётся там, где ошибка вероятна: собеседник поправил агента вскоре
# после того, как знание было инжектировано. Это КАНДИДАТ, не приговор — поправка
# могла касаться совсем другого. Продюсер лишь ставит вопрос там, где ответ на него
# информативен; решение остаётся за суждением при закрытии исхода.
#
# Аргументы: sid [state_dir] [window_min] [max_candidates]
# Печатает число созданных кандидатов.
# ВЕРДИКТ ИСПОЛНИМ ТОЛЬКО ДЛЯ ОПЕРАЦИОННОГО КОНТУРА (7 сентября 2026, род L).
# Кандидат «знание вероятно ошиблось» исполняется knowledge-counter-bump.sh, который правит
# confirmed_count / contradicted_count / last_confirmed / provenance_log — четырёх этих полей
# в схеме entity/fact/relation нет. Реплика-поправка собеседника и не является событием,
# опровергающим запись вида «статья опубликована там-то». Замер: 15 кандидатов из 1316
# (1,1%) были вторым контуром, три вердикта по relation уже вынесены — порчи не случилось
# лишь потому, что все три оказались not_applicable, а этот исход счётчиков не трогает.
dis_harvest_corrections() {
    local sid="${1:-}"
    local sd; sd=$(_dis_state_dir "${2:-}")
    local window_min="${3:-${DISAGREEMENT_CORRECTION_WINDOW_MIN:-30}}"
    local max_cand="${4:-${DISAGREEMENT_MAX_CANDIDATES:-3}}"
    [ -n "$sid" ] || { echo 0; return; }

    local corr_file="$sd/correction-fired-${sid}.jsonl"
    local inj_file="$sd/injection-log.jsonl"
    local pend_file="$sd/disagreement-pending-${sid}.jsonl"
    [ -f "$corr_file" ] && [ -f "$inj_file" ] || { echo 0; return; }
    command -v jq >/dev/null 2>&1 || { echo 0; return; }

    # Инжекты ЭТОЙ сессии, только реально показанные (rank 1-3): ранги 4-6 — контрольная
    # группа, агент их не видел, и поправка не может быть реакцией на них.
    local injections
    injections=$(jq -rR 'fromjson? // empty
        | select(.session_id == $sid and .injected == true)
        | select((.file // "") | test("(^|/)(case|pattern|principle)-"))
        | [.date, .file, (.confidence // 0)] | @tsv' --arg sid "$sid" "$inj_file" 2>/dev/null || true)
    [ -n "$injections" ] || { echo 0; return; }

    local corrections
    corrections=$(jq -rR 'fromjson? // empty | .date' "$corr_file" 2>/dev/null || true)
    [ -n "$corrections" ] || { echo 0; return; }

    local window_s=$(( window_min * 60 ))
    local made=0

    # Соединение «поправка × показ» — один процесс awk (D1000, см. _dis_join_pairs): окно,
    # дедуп по ключу и «уже есть запись по этому ключу в этой сессии» решены там, в прежнем
    # порядке проверок. Здесь остаётся запись кандидата.
    local cands c_idx c_ts i_file i_conf key snip snip_json
    cands=$(_dis_join_pairs "$corrections" "$injections" "$window_s" "$max_cand" "$pend_file")
    while IFS=$'\t' read -r c_idx i_file i_conf; do
        [ -n "$i_file" ] || continue
        c_ts=$(_dis_nth "$c_idx" "$corrections")
        key="${i_file%.md}"
        # Улика замораживается в кандидате. Судья на Stop видел «ключ+дата+инструмент»
        # и вслепую писал «не к месту»: 304 кандидата → 0 опровержений за всю историю
        # (диагностика 2026-08-31). Текст поправки уже пишет user-correction-guard в
        # correction-fired — берём snippet строки, чья дата дала кандидата; jq -Rs
        # экранирует произвольный текст собеседника для JSON.
        snip=$(jq -rR --arg d "$c_ts" \
            'fromjson? // empty | select(.date == $d) | .snippet // empty' \
            "$corr_file" 2>/dev/null | sed -n '1p')
        snip_json=$(printf '%s' "$snip" | jq -Rs . 2>/dev/null) || snip_json='""'
        printf '{"date":"%s","key":"%s","outcome":"pending","confidence":%s,"tool":"correction","class":"correction_after_injection","snippet":%s}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$key" "${i_conf:-0}" "$snip_json" \
            >> "$pend_file" 2>/dev/null || true
        made=$((made + 1))
    done <<EOF
$cands
EOF
    echo "$made"
}

# dis_harvest_failures <sid> [state_dir] [window_min] [max_candidates]
#   Жнец опровержений из ПРОВАЛОВ (D229): знание было показано, и вскоре ход упал —
#   кандидат «знание вероятно ошиблось» с классом failure_after_injection. Клон
#   dis_harvest_corrections с другим источником времени: вместо реплик-поправок —
#   (а) серии провалов команд этой сессии (error-streak-log-<SID>.jsonl, мост D229 в
#   error-tracker) и (б) внешние события мира без сессии (pending-events.jsonl, роды
#   revert и ci-red) — у них есть только ts, привязка к сессии не восстанавливается,
#   предел назван; условие снятия: внешние продюсеры понесут идентификатор сессии
#   (перестанут быть только скриптами по расписанию) — джойн станет точным равенством,
#   а не окном по ts. Корреляция не вина: запись — pending-кандидат, исход решается
#   контуром 4e, счётчики не трогаются (правило «сами записи создаёте вы»).
dis_harvest_failures() {
    local sid="${1:-}"
    local sd; sd=$(_dis_state_dir "${2:-}")
    local window_min="${3:-${DISAGREEMENT_FAILURE_WINDOW_MIN:-30}}"
    local max_cand="${4:-${DISAGREEMENT_MAX_CANDIDATES:-3}}"
    [ -n "$sid" ] || { echo 0; return; }

    local streak_file="$sd/error-streak-log-${sid}.jsonl"
    local events_file="$sd/pending-events.jsonl"
    local inj_file="$sd/injection-log.jsonl"
    local pend_file="$sd/disagreement-pending-${sid}.jsonl"
    [ -f "$inj_file" ] || { echo 0; return; }
    command -v jq >/dev/null 2>&1 || { echo 0; return; }

    local injections
    injections=$(jq -rR 'fromjson? // empty
        | select(.session_id == $sid and .injected == true)
        | select((.file // "") | test("(^|/)(case|pattern|principle)-"))
        | [.date, .file, (.confidence // 0)] | @tsv' --arg sid "$sid" "$inj_file" 2>/dev/null || true)
    [ -n "$injections" ] || { echo 0; return; }

    local failures=""
    [ -f "$streak_file" ] && \
        failures=$(jq -rR 'fromjson? // empty | .ts // empty' "$streak_file" 2>/dev/null || true)
    if [ -f "$events_file" ]; then
        local ext
        ext=$(jq -rR 'fromjson? // empty
            | select(.kind == "revert" or .kind == "ci-red"
                     or .kind == "hotfix-repeat" or .kind == "resurrected")
            | .ts // empty' "$events_file" 2>/dev/null || true)
        [ -n "$ext" ] && failures="${failures}${failures:+
}${ext}"
    fi
    [ -n "$failures" ] || { echo 0; return; }

    local window_s=$(( window_min * 60 ))
    local made=0

    # Соединение «провал × показ» — один процесс awk (D1000, см. _dis_join_pairs): окно, дедуп
    # по ключу и «в pending-файле уже есть ключ» решены там, в прежнем порядке проверок. Здесь
    # остаётся запись кандидата; номер провала (первое поле) этому жнецу не нужен.
    local cands _f_idx i_file i_conf key
    cands=$(_dis_join_pairs "$failures" "$injections" "$window_s" "$max_cand" "$pend_file")
    while IFS=$'\t' read -r _f_idx i_file i_conf; do
        [ -n "$i_file" ] || continue
        key="${i_file%.md}"
        printf '{"date":"%s","key":"%s","outcome":"pending","confidence":%s,"tool":"failure","class":"failure_after_injection"}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$key" "${i_conf:-0}" \
            >> "$pend_file" 2>/dev/null || true
        made=$((made + 1))
    done <<EOF
$cands
EOF
    echo "$made"
}

# Здоровье самого контура: closed expired open.
# Смысл метрики — если доля истёкших высокая, контур не работает, и это видно
# числом. До v1.12.0 такого числа не было вообще, поэтому разрыв между алертом и
# закрытием жил три недели незамеченным.
dis_stats() {
    local sd; sd=$(_dis_state_dir "${1:-}")
    # Последнее состояние ключа — в пределах СЕССИИ (имя файла), как прежде в пределах файла; один процесс на все
    # строки «архив + живые файлы» (D1008). Вывод — одна строка «закрыто истекло открыто», без присваиваний: функцию
    # source'ят и из zsh (pattern-shell-portability). Архив не прочитан — чисел нет и код 2: меньшее число читалось бы
    # как настоящее (род B, второй скептик M-1).
    local rows
    rows=$(_dis_lines "$sd") || return 2
    printf '%s\n' "$rows" | awk -F'\t' '
        function field(line, name,   parts, val) {
            if (split(line, parts, "\"" name "\":\"") < 2) return ""
            split(parts[2], val, "\"")
            return val[1]
        }
        {
            line = $0; sub(/^[^\t]*\t[^\t]*\t/, "", line)
            k = field(line, "key"); if (k == "") next
            id = $1 SUBSEP k
            if (line ~ /"outcome":"pending"/) { st[id] = "open" }
            else if (line ~ /"expired":true/) { st[id] = "expired" }
            else { st[id] = "closed" }
        }
        END {
            c = 0; e = 0; o = 0
            for (id in st) {
                if (st[id] == "closed") c++
                else if (st[id] == "expired") e++
                else o++
            }
            printf "%d %d %d\n", c, e, o
        }
    ' 2>/dev/null || echo "0 0 0"
}

# Живые суждения долговременного журнала: строки, ОТМЕНЁННЫЕ отзывом, снимаются.
#
# Зачем. У контура нет отмены — `knowledge-counter-bump.sh` знает только приращения, — и
# отзыв суждения делается дописыванием строки с полем `supersedes` (прежний исход) и `note`
# (почему отозвано). Строка-отзыв ЗАМЕЩАЕТ оригинал, но обе лежат в журнале, и всякий, кто
# просто считает строки, считает событие дважды.
#
# Цена измерена 1 сентября 2026 на живом состоянии: 253 строки журнала, 56 отзывов;
# `confirmed_knowledge` читается как 138 при 95 живых — завышение на 43 (+45%), и доли
# исходов смещены все четыре (55/35/10/0 против 48/39/12/1). Читателей поля `supersedes` не
# было ни одного.
#
# Правило снятия — то же, что у `dis_scan_open` для очереди: состояние ключа определяет
# последняя запись о нём. Здесь «ключ» есть тройка (knowledge, session, прежний исход), и
# каждый отзыв снимает РОВНО ОДИН ближайший более ранний оригинал. На живых данных
# сопоставление однозначно: 56 отзывов → 56 оригиналов, неоднозначных 0, несопоставленных 0.
#
# КОНТРПРИМЕР: строка `outdated_knowledge` (единственная в базе) не отзывалась и остаётся —
# схлопывание по (knowledge, session) её теряло, потому что съедало и законные повторные
# суждения той же сессии в разные дни (3 пары).
#
# Печатает JSONL живых суждений в stdout; нет файла или python3 — печатает журнал как есть
# (лучше завышенное число, чем пустое: читатель, получивший ноль строк, объявит контур мёртвым).
dis_live_outcomes() {
    local sd; sd=$(_dis_state_dir "${1:-}")
    local f="$sd/disagreement-outcomes.jsonl"
    [ -f "$f" ] || return 0
    command -v python3 >/dev/null 2>&1 || { cat "$f"; return 0; }
    python3 - "$f" <<'PY' 2>/dev/null || cat "$f"
import json, sys
rows = []
for line in open(sys.argv[1], errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        rows.append(json.loads(line))
    except ValueError:
        continue          # битая строка не должна ронять весь журнал
consumed = set()
for r in rows:
    if "supersedes" not in r:
        continue
    for i, x in enumerate(rows):
        if (i not in consumed and "supersedes" not in x
                and x.get("knowledge") == r.get("knowledge")
                and x.get("session") == r.get("session")
                and x.get("outcome") == r.get("supersedes")
                and x.get("date", "") < r.get("date", "")):
            consumed.add(i)
            break
for i, x in enumerate(rows):
    if i not in consumed:
        # Компактно, БЕЗ пробелов после двоеточий — ровно в том виде, в каком строки писал
        # `dis_close_outcome`. Формат журнала нигде не объявлен: он живёт литералом в одном
        # printf и в пяти grep/awk читателей, и второй писатель молча делит контур надвое.
        # Замер 1 сентября 2026 на живом состоянии: 56 отзывов записаны рукой С ПРОБЕЛАМИ,
        # и `grep '"outcome":"'` находит 197 строк из 253 — отзывов не видит НИ ОДИН
        # грепающий читатель (metrics-collector.sh:576,604), тогда как jq-читатели
        # (five-whys-gate.sh:178, scripts/injection-outcome.sh) видят все 253 и считают
        # оригинал вместе с его отзывом. Вывод с пробелами повторил бы ту же ошибку.
        print(json.dumps(x, ensure_ascii=False, separators=(",", ":")))
PY
}
