#!/usr/bin/env bash
# disagreement-lib.sh — общий доступ к контуру опровержения (v1.12.0).
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

# Две шкалы в одном контуре. `correction-fired` пишет UTC с суффиксом `Z`,
# `injection-log` до v1.12.0 писал ЛОКАЛЬНОЕ время без суффикса. На машине с +02:00
# наивный джойн этих двух логов разъехался бы на два часа, а с переходом на летнее
# время — плавал бы. Суффикс `Z` и есть маркер шкалы, по нему и различаем: новые
# строки однозначны, старые читаются как локальные и не переписываются.
_dis_epoch() { iso_epoch "${1:-}"; }

_dis_state_dir() {
    echo "${1:-${STATE_DIR:-$HOME/.claude/hooks/state}}"
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
    local f sid
    for f in "$sd"/disagreement-pending-*.jsonl; do
        [ -f "$f" ] || continue
        sid=$(basename "$f"); sid="${sid#disagreement-pending-}"; sid="${sid%.jsonl}"
        # for-in вместо length(array) — BSD awk (pattern-shell-portability).
        awk -v sid="$sid" '
            function field(line, name,   parts, val) {
                if (split(line, parts, "\"" name "\":\"") < 2) return ""
                split(parts[2], val, "\"")
                return val[1]
            }
            {
                k = field($0, "key")
                if (k == "") next
                if ($0 ~ /"outcome":"pending"/) {
                    d[k] = field($0, "date")
                    t[k] = field($0, "tool")
                    c[k] = 0
                    if (match($0, /"confidence":[0-9]+/))
                        c[k] = substr($0, RSTART + 13, RLENGTH - 13)
                    open[k] = 1
                } else {
                    delete open[k]
                }
            }
            END { for (k in open) printf "%s|%s|%s|%s|%s\n", sid, k, d[k], c[k], t[k] }
        ' "$f" 2>/dev/null || true
    done
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
        | [.date, .file, (.confidence // 0)] | @tsv' --arg sid "$sid" "$inj_file" 2>/dev/null || true)
    [ -n "$injections" ] || { echo 0; return; }

    local corrections
    corrections=$(jq -rR 'fromjson? // empty | .date' "$corr_file" 2>/dev/null || true)
    [ -n "$corrections" ] || { echo 0; return; }

    local window_s=$(( window_min * 60 ))
    local made=0 seen="|"

    local c_ts c_s i_ts i_file i_conf i_s key
    while IFS= read -r c_ts; do
        [ -n "$c_ts" ] || continue
        c_s=$(_dis_epoch "$c_ts"); [ "$c_s" -gt 0 ] 2>/dev/null || continue
        while IFS=$'\t' read -r i_ts i_file i_conf; do
            [ -n "$i_file" ] || continue
            [ "$made" -lt "$max_cand" ] || break 2
            key="${i_file%.md}"
            case "$seen" in *"|$key|"*) continue ;; esac
            # Уже есть запись по этому ключу в этой сессии — не плодим дубли.
            if [ -f "$pend_file" ] && grep -Fq "\"key\":\"$key\"" "$pend_file" 2>/dev/null; then
                seen="$seen$key|"; continue
            fi
            i_s=$(_dis_epoch "$i_ts"); [ "$i_s" -gt 0 ] 2>/dev/null || continue
            # Инжект должен предшествовать поправке и попадать в окно.
            [ "$i_s" -le "$c_s" ] || continue
            [ $(( c_s - i_s )) -le "$window_s" ] || continue
            printf '{"date":"%s","key":"%s","outcome":"pending","confidence":%s,"tool":"correction","class":"correction_after_injection"}\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$key" "${i_conf:-0}" \
                >> "$pend_file" 2>/dev/null || true
            seen="$seen$key|"
            made=$((made + 1))
        done <<EOF
$injections
EOF
    done <<EOF
$corrections
EOF
    echo "$made"
}

# Здоровье самого контура: closed expired open.
# Смысл метрики — если доля истёкших высокая, контур не работает, и это видно
# числом. До v1.12.0 такого числа не было вообще, поэтому разрыв между алертом и
# закрытием жил три недели незамеченным.
dis_stats() {
    local sd; sd=$(_dis_state_dir "${1:-}")
    # local подняты из цикла — см. пояснение в dis_scan_open.
    local closed=0 expired=0 open=0 f counts fc fe fo
    for f in "$sd"/disagreement-pending-*.jsonl; do
        [ -f "$f" ] || continue
        counts=$(awk '
            function field(line, name,   parts, val) {
                if (split(line, parts, "\"" name "\":\"") < 2) return ""
                split(parts[2], val, "\"")
                return val[1]
            }
            {
                k = field($0, "key"); if (k == "") next
                if ($0 ~ /"outcome":"pending"/) { st[k] = "open" }
                else if ($0 ~ /"expired":true/) { st[k] = "expired" }
                else { st[k] = "closed" }
            }
            END {
                c = 0; e = 0; o = 0
                for (k in st) {
                    if (st[k] == "closed") c++
                    else if (st[k] == "expired") e++
                    else o++
                }
                printf "%d %d %d\n", c, e, o
            }
        ' "$f" 2>/dev/null || echo "0 0 0")
        # Позиционный разбор вместо `read -r a b c <<EOF`: в zsh та конструкция
        # печатает присваивания в stdout, и вывод функции засоряется. Хуки зовут
        # библиотеку через bash, где этого не происходит, — но ad-hoc её source'ят
        # и из zsh (pattern-shell-portability: не полагайся на семантику одного shell).
        fc=$(printf '%s' "$counts" | awk '{print $1+0}')
        fe=$(printf '%s' "$counts" | awk '{print $2+0}')
        fo=$(printf '%s' "$counts" | awk '{print $3+0}')
        closed=$((closed + ${fc:-0}))
        expired=$((expired + ${fe:-0}))
        open=$((open + ${fo:-0}))
    done
    echo "$closed $expired $open"
}
