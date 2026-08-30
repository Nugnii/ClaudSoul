#!/usr/bin/env bash
# detection-signals-lib.sh — pure evaluator of pattern detection_signals (v0.3)
#
# Purpose: blocker-tier knowledge needs a relational pre-action check.
# Each blocker pattern declares detection_signals — named compositions of base
# matchers. At PreToolUse time, blocker-tier-check.sh calls ds_evaluate for
# every blocker pattern; first matching signal fires a silent additionalContext
# injection.
#
# Signal format (stored as JSON inside YAML block literal `detection_signals: |`):
#   [{"name":"...","all_of":[matcher, ...]}, ...]
#
# Base matchers (single-key dicts):
#   {"tool_matches": ["Edit","Write"]}            — current tool is one of
#   {"file_path_regex": "..."}                    — tool_input.file_path matches POSIX ERE
#   {"file_size_min_lines": 300}                  — wc -l of file_path ≥ N (0 if file missing)
#   {"prompt_contains": "..."}                    — last user prompt contains substring
#   {"tool_input_contains": "..."}                — JSON-stringified tool_input contains substring
#   {"tool_input_regex": "..."}                   — tool_input matches POSIX ERE под LC_ALL=C
#   {"heredoc_body_regex": "..."}                 — ТЕЛО heredoc в .command matches ERE (D79)
#   {"command_uses": "..."}                       — команда ИСПОЛНЯЕТ подстроку, а не упоминает её
#
# Почему появился regex по содержимому (v1.14.8). До него содержимое можно было
# сопоставлять ТОЛЬКО точной подстрокой, то есть сигнал умел перечислять известные
# формы и не умел выражать правило. Цена измерена: класс «не-ASCII символ вплотную
# к синтаксису оболочки» за одну сессию проявился ЧЕТЫРЬМЯ разными формами, блокер
# знал две из них списком и не сработал ни разу. Класс, описываемый правилом,
# а не перечнем, при списочном сигнале обречён ловиться постфактум столько раз,
# сколько у него форм.
#
# `LC_ALL=C` обязателен: сопоставление идёт по БАЙТАМ. Иначе предикат «есть не-ASCII»
# сам зависел бы от локали — GNU grep отвергает кириллический диапазон в C.UTF-8,
# и проверка против класса совершила бы ошибку этого же класса (так уже было).
#
# Compositors: {"all_of": [...]}, {"any_of": [...]} — may nest one level inside a signal.
#
# Contract of ds_evaluate:
#   ds_evaluate <pattern_file> <tool_name> <tool_input_json> <prompt_text>
#   Exit 0 + signal name on stdout  → a signal matched
#   Exit 1 + no output              → no signal matched (or pattern has none)
#
# This library has NO state of its own. Throttling, logging, injection — all in
# blocker-tier-check.sh.

set -uo pipefail

# jq is a hard dep. Without it, return no-match so the system degrades gracefully.
_ds_jq_available() {
    command -v jq >/dev/null 2>&1
}

# Extract detection_signals JSON array from pattern file YAML frontmatter.
# Echoes JSON (either a non-empty array or `[]`).
ds_extract_signals() {
    local pattern_file="$1"
    [ -f "$pattern_file" ] || { printf '[]\n'; return 0; }
    _ds_jq_available || { printf '[]\n'; return 0; }
    local fm
    fm=$(awk '/^---$/{n++; if (n==2) exit; next} n==1{print}' "$pattern_file")
    local block
    block=$(printf '%s\n' "$fm" | awk '
        BEGIN { in_block = 0 }
        /^detection_signals:[[:space:]]*\|[[:space:]]*$/ { in_block = 1; next }
        in_block {
            if ($0 ~ /^[^[:space:]]/) { exit }
            print
        }
    ')
    if [ -z "$block" ]; then
        printf '[]\n'
        return 0
    fi
    local json
    json=$(printf '%s\n' "$block" | jq -c '.' 2>/dev/null)
    if [ -z "$json" ] || [ "$json" = "null" ]; then
        printf '[]\n'
    else
        printf '%s\n' "$json"
    fi
}

# Quick boolean: does pattern declare `blocker: true` in frontmatter?
ds_has_blocker_flag() {
    local pattern_file="$1"
    [ -f "$pattern_file" ] || return 1
    awk '
        /^---$/ { n++; if (n == 2) exit; next }
        n == 1 && /^blocker:[[:space:]]*true[[:space:]]*$/ { found = 1; exit }
        END { exit (found ? 0 : 1) }
    ' "$pattern_file"
}

# Evaluate one node (either a composition or a base matcher). 0 = match, 1 = no match.
# Arguments: <node_json> <tool_name> <tool_input_json> <prompt>
# ds_code_only <tool_input> → та же полезная нагрузка без содержимого комментариев.
#
# Повод (D56). Сигналы сопоставляют содержимое правки подстрокой, и блокер переносимости
# дважды за сессию загорелся на КОММЕНТАРИИ — на тексте, где `date -j` и `stat -f`
# перечислены как запрещённые. То есть страж сработал на пояснении к правилу, а не на его
# нарушении. Это `pattern-guard-scope-blindness` внутри самого блокера; для команд тот же
# класс уже закрыт `command-scope-lib.sh` (вырезает кавычки и heredoc), здесь — эквивалент
# для содержимого правки.
#
# Правило комментария оболочки: решётка в начале строки, возможно после отступа. Решётка
# ВНУТРИ кода (`grep -c "#" f`) комментария не открывает, и код после неё обязан уцелеть —
# иначе страж начнёт пропускать настоящие нарушения, что хуже ложных срабатываний.
#
# Нагрузка приходит одной строкой (`jq -c`), перевод строки в ней — два символа `\n`,
# поэтому границей служит он, а не настоящий конец строки.
ds_code_only() {
    # Границей строки служит последовательность `\n`, а НЕ «любая обратная косая».
    # Первая версия резала `#` до ближайшей косой — и под ASCII-экранированием кириллица
    # (`\u0413…`) обрывала вырезание на первом же символе комментария, оставляя запрещённую
    # команду видимой. Проверка поймала это только потому, что гоняет обе кодировки.
    printf '%s' "${1:-}" | awk '{
        n = split($0, a, /\\n/)
        out = ""
        for (i = 1; i <= n; i++) {
            s = a[i]
            sub(/(^|")[[:space:]]*#.*$/, "\"", s)   # решётка в начале строки или значения
            out = out s (i < n ? "\\n" : "")
        }
        print out
    }'
}

# Убрать закавыченные куски команды: это аргументы-строки, а не исполняемое.
# Повод измерен 2026-08-28: ветвь сигналов по Bash сработала на первом же живом вызове,
# где слово стояло ВНУТРИ кавычек пробы, а не запускалось. Подстрока не различает
# исполнение и упоминание, и на этом ломается любой стопор: отказ приходит там, где
# ничего не происходит, и его начинают обходить не думая.
#
# Тело heredoc НЕ трогаем намеренно: код, записываемый в файл, будет исполняться — это
# тоже использование. Для него отдельный предикат `heredoc_body_regex` (D79).
#
# Потолок назван: вложенные и экранированные кавычки снимаются грубо, одним проходом.
# Цена ошибки несимметрична — лишний пропуск дешевле ложного отказа, поэтому грубость
# смещена в сторону пропуска.
ds_unquoted_command() {
    # Разбор идёт по ВСЕМУ тексту сразу, а не построчно: кавычки в командах переносятся
    # через строки — сообщение коммита, тело `-m "…"`. Построчный проход оставлял такую
    # прозу видимой, и на ней 28 августа 2026 пришёл единственный ложный отказ замера по
    # 2342 вызовам: слово «timeout» в русской фразе сообщения коммита было прочитано как
    # вызов отсутствующего инструмента.
    # Смещение сохранено прежнее: непарная кавычка теперь съест хвост команды, то есть
    # даст ПРОПУСК, а не ложный отказ. Пропуск здесь дешевле.
    printf '%s' "${1:-}" | awk 'BEGIN { RS = "\001" } {
        s = $0
        gsub(/\047[^\047]*\047/, " ", s)
        gsub(/"[^"]*"/, " ", s)
        printf "%s", s
    }'
}

# Вид команды «только оболочка»: тело heredoc вырезано, комментарии сняты, кавычки сняты.
# Зачем отдельный вид. Нормализацию до 28 августа 2026 выбирала библиотека один раз на все
# предикаты, а предмет у них разный: «исполняется ли токен» и «правильно ли построен вызов»
# требуют РАЗНЫХ видов одного текста. Из одного общего вида вышли обе семьи ложных отказов
# замера по 2342 вызовам: 18 отказов на цикл, записываемый в bash-файл (там он верен), и
# 14 на `sed -i ''` — верную форму BSD, у которой снятие кавычек стирает значащий аргумент.
ds_shell_only() {
    printf '%s' "${1:-}" | awk '
        !inside && /<<-?[ ]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*'"'"'?"?/ {
            line = $0
            if (match(line, /<<-?[ ]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*'"'"'?"?/)) {
                mark = substr(line, RSTART, RLENGTH)
                gsub(/^<<-?[ ]*/, "", mark); gsub(/['"'"'"]/, "", mark)
                inside = 1
            }
            print line
            next
        }
        inside && $0 == mark { inside = 0; next }
        inside { next }
        { print }
    '
}

ds_evaluate_node() {
    local node="$1" tool_name="$2" tool_input="$3" prompt="$4"
    _ds_jq_available || return 1
    local key
    key=$(printf '%s' "$node" | jq -r 'keys_unsorted[0] // empty' 2>/dev/null)
    [ -z "$key" ] && return 1

    case "$key" in
        all_of|any_of|none_of)
            local sub_count
            sub_count=$(printf '%s' "$node" | jq -r ".${key} | length" 2>/dev/null)
            [ -z "$sub_count" ] && return 1
            [ "$sub_count" -eq 0 ] && return 1
            local i sub res filter
            for (( i = 0; i < sub_count; i++ )); do
                filter=".${key}[${i}]"
                sub=$(printf '%s' "$node" | jq -c "$filter" 2>/dev/null)
                if [ -z "$sub" ]; then
                    case "$key" in all_of) return 1 ;; none_of) continue ;; *) continue ;; esac
                fi
                ds_evaluate_node "$sub" "$tool_name" "$tool_input" "$prompt"
                res=$?
                case "$key" in
                    all_of)  [ "$res" -ne 0 ] && return 1 ;;
                    any_of)  [ "$res" -eq 0 ] && return 0 ;;
                    none_of) [ "$res" -eq 0 ] && return 1 ;;   # совпало исключение — узел ложен
                esac
            done
            case "$key" in any_of) return 1 ;; *) return 0 ;; esac
            ;;
        tool_matches)
            local match
            match=$(printf '%s' "$node" | jq -r --arg t "$tool_name" '.tool_matches | index($t) != null' 2>/dev/null)
            [ "$match" = "true" ] && return 0
            return 1
            ;;
        file_path_regex)
            local regex file_path
            regex=$(printf '%s' "$node" | jq -r '.file_path_regex' 2>/dev/null)
            [ -z "$regex" ] && return 1
            file_path=$(printf '%s' "$tool_input" | jq -r '.file_path // empty' 2>/dev/null)
            [ -z "$file_path" ] && return 1
            grep -qE -- "$regex" <<< "$file_path" && return 0
            return 1
            ;;
        tool_input_regex)
            local rx
            rx=$(printf '%s' "$node" | jq -r '.tool_input_regex' 2>/dev/null)
            [ -z "$rx" ] && return 1
            # LC_ALL=C — сопоставление по байтам, см. пояснение в шапке.
            ds_code_only "$tool_input" | LC_ALL=C grep -qE -- "$rx" && return 0
            return 1
            ;;
        heredoc_target_regex)
            # КУДА пишет heredoc, а не что упомянуто в команде. Область признака обязана
            # относиться к файлу, который СОЗДАЁТСЯ, — иначе она берётся оттуда, где на неё
            # удобно смотреть. Замер 28 августа 2026: отказ прилетел на запись пробника в
            # песочницу только потому, что в той же команде стоял путь запуска стража.
            # Правило было верным по букве и ложным по сути, а ложный отказ хуже пропуска:
            # его начинают обходить не думая.
            #
            # Цель ищется на строке, открывающей тело: «> файл», «>> файл», «tee файл».
            # Путь через переменную не раскрывается — сравнивается его текст, поэтому
            # «$REPO/hooks/foo.sh» совпадает с образцом дерева, а «$SP/probe.sh» нет.
            # КОНТРПРИМЕР: цель, целиком спрятанная в переменной («> "$OUT"»), не
            # опознаётся — признак промолчит, и это известно.
            # Цель ищется ТОЛЬКО в части строки ПОСЛЕ маркера heredoc. Перенаправление,
            # стоящее до маркера, к телу heredoc не относится: в
            # `git show HEAD:hooks/x.sh > /tmp/x.sh && python3 - <<'PY'` первый вывод
            # уходит во временный файл, а телом heredoc кормится python — но признак,
            # читавший строку целиком, видел путь `hooks/x.sh` и отказывал в чтении из
            # архива git. Поймано на себе 29 августа 2026, третье проявление одного рода
            # (D113): предмет признака берётся оттуда, где на него удобно смотреть.
            local trx targets
            trx=$(printf '%s' "$node" | jq -r '.heredoc_target_regex' 2>/dev/null)
            [ -z "$trx" ] && return 1
            targets=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null | awk '
                /<<-?[ ]*'"'"'?"?[A-Za-z_]/ {
                    line = $0
                    if (match(line, /<<-?[ ]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*/)) {
                        line = substr(line, RSTART + RLENGTH)
                    }
                    n = split(line, w, /[[:space:]]+/)
                    for (i = 1; i <= n; i++) {
                        if (w[i] ~ /^>>?$/ || w[i] == "tee") { if (i < n) print w[i+1] }
                        else if (w[i] ~ /^>>?[^>]/) { t = w[i]; sub(/^>>?/, "", t); print t }
                    }
                }')
            [ -z "$targets" ] && return 1
            LC_ALL=C grep -qE -- "$trx" <<< "$targets" && return 0
            return 1
            ;;
        heredoc_body_regex)
            # Тело heredoc в команде Bash (D79). Зачем отдельный матчер, а не
            # `tool_input_regex`: у Bash `tool_input` это командная строка ЦЕЛИКОМ, и
            # регулярка, писанная под содержимое файла, горит на любом `grep` по тому же
            # образцу — ровно тот класс ложных срабатываний, что разобран в D25. Тело
            # heredoc — это то, что реально ЗАПИСЫВАЕТСЯ в файл, а не то, что ищется.
            #
            # Повод: замер 2026-08-26 — 45% правок файлов идут командами оболочки
            # (1357 против 1675 файловыми инструментами), а blocker-tier знания слушали
            # только Edit/Write, то есть на половине правок были выключены по построению.
            #
            # Разбор простой намеренно: строка `<<MARK` или `<<'MARK'` открывает тело,
            # одинокий MARK закрывает. Вложенных heredoc не бывает в наших командах, а
            # угадывать сложные случаи дороже, чем пропустить их (ponytail: ceiling
            # назван — при вложенных телах матчер вернёт больше, чем нужно, и это лучше
            # молчания).
            local hrx body
            hrx=$(printf '%s' "$node" | jq -r '.heredoc_body_regex' 2>/dev/null)
            [ -z "$hrx" ] && return 1
            body=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null | awk '
                /<<-?[A-Za-z_'"'"'"][A-Za-z0-9_]*'"'"'?"?/ && !inside {
                    line = $0
                    if (match(line, /<<-?[ ]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*'"'"'?"?/)) {
                        mark = substr(line, RSTART, RLENGTH)
                        gsub(/^<<-?[ ]*/, "", mark); gsub(/['"'"'"]/, "", mark)
                        inside = 1
                    }
                    next
                }
                inside && $0 == mark { inside = 0; next }
                inside { print }
            ')
            [ -z "$body" ] && return 1
            # Комментарии из тела снимаются: строка, где запрещённая команда ПЕРЕЧИСЛЕНА
            # как запрещённая («GNU не знает date -j»), нарушением не является. Тот же
            # класс уже закрыт для содержимого правок (`ds_code_only`, D56) — здесь он
            # доехал только 29 августа 2026, после третьего ложного отказа подряд (D113).
            # НАЗВАННЫЙ ПРЕДЕЛ: строковые литералы в теле НЕ снимаются — код, записываемый
            # в файл, исполняется, и `CMD="date -j"` там настоящее использование. Поэтому
            # токен внутри кавычек-ПОДПИСИ (фикстура теста, образец в assert) по-прежнему
            # ловится; отличить подпись от вызова по тексту нельзя.
            # Условие снятия: предел держится, пока роль строки в теле определяется только
            # её текстом. Появится разбор записываемого файла по синтаксису языка — роль
            # станет наблюдаемой, и предел уйдёт вместе с угадыванием.
            body=$(ds_code_only "$body")
            [ -z "$body" ] && return 1
            printf '%s' "$body" | LC_ALL=C grep -qE -- "$hrx" && return 0
            return 1
            ;;
        file_size_min_lines)
            local threshold file_path line_count
            threshold=$(printf '%s' "$node" | jq -r '.file_size_min_lines' 2>/dev/null)
            [ -z "$threshold" ] && return 1
            file_path=$(printf '%s' "$tool_input" | jq -r '.file_path // empty' 2>/dev/null)
            if [ -n "$file_path" ] && [ -f "$file_path" ]; then
                line_count=$(wc -l < "$file_path" 2>/dev/null | tr -d ' ')
            else
                line_count=0
            fi
            [ "${line_count:-0}" -ge "$threshold" ] && return 0
            return 1
            ;;
        prompt_contains)
            local needle
            needle=$(printf '%s' "$node" | jq -r '.prompt_contains' 2>/dev/null)
            [ -z "$needle" ] && return 1
            grep -qF -- "$needle" <<< "$prompt" && return 0
            return 1
            ;;
        command_uses)
            local needle cmd stripped
            needle=$(printf '%s' "$node" | jq -r '.command_uses' 2>/dev/null)
            [ -z "$needle" ] && return 1
            cmd=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null)
            [ -z "$cmd" ] && return 1
            # Вид оболочки: лексема в теле heredoc — содержимое будущего файла, а не вызов.
            stripped=$(ds_unquoted_command "$(ds_code_only "$(ds_shell_only "$cmd")")")
            grep -qF -- "$needle" <<< "$stripped" && return 0
            return 1
            ;;
        tool_input_contains)
            local needle
            needle=$(printf '%s' "$node" | jq -r '.tool_input_contains' 2>/dev/null)
            [ -z "$needle" ] && return 1
            grep -qF -- "$needle" <<< "$(ds_code_only "$tool_input")" && return 0
            return 1
            ;;
        shell_regex)
            # Образец по тому, что исполнит ОБОЛОЧКА: без тела heredoc, без кавычек.
            # Для вопроса «эта команда сломана здесь и сейчас». КОНТРПРИМЕР: тот же дефект,
            # записанный в файл, сюда не попадёт — на запись есть отдельные признаки.
            local rx cmd view
            rx=$(printf '%s' "$node" | jq -r '.shell_regex' 2>/dev/null)
            [ -z "$rx" ] && return 1
            cmd=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null)
            [ -z "$cmd" ] && return 1
            view=$(ds_unquoted_command "$(ds_code_only "$(ds_shell_only "$cmd")")")
            LC_ALL=C grep -qE -- "$rx" <<< "$view" && return 0
            return 1
            ;;
        raw_command_regex)
            # Образец по команде КАК НАПИСАНА: ничего не снято. Для вопроса «правильно ли
            # построен вызов», где кавычки значимы: `sed -i ''` верен на BSD, `sed -i s/a/b/`
            # падает, и различает их ровно пустая строка. КОНТРПРИМЕР: слово в кавычках
            # сюда попадёт — этот вид не отличает упоминание от исполнения, и признак,
            # которому нужно такое различение, должен брать shell_regex.
            local rrx rcmd
            rrx=$(printf '%s' "$node" | jq -r '.raw_command_regex' 2>/dev/null)
            [ -z "$rrx" ] && return 1
            rcmd=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null)
            [ -z "$rcmd" ] && return 1
            LC_ALL=C grep -qE -- "$rrx" <<< "$(ds_shell_only "$rcmd")" && return 0
            return 1
            ;;
        command_regex)
            # То же, что command_uses, но образцом. Нужен там, где дефект — ФОРМА, а не
            # лексема: «for X in $VAR» ловится правилом, «for X in $(cmd)» законно, и  # mb-ok: показ формы
            # фиксированной подстрокой их не развести. Сопоставление идёт по РАСКАВЫЧЕННОЙ
            # команде: слово внутри строки-аргумента — упоминание, а не исполнение.
            local rx cmd stripped
            rx=$(printf '%s' "$node" | jq -r '.command_regex' 2>/dev/null)
            [ -z "$rx" ] && return 1
            cmd=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null)
            [ -z "$cmd" ] && return 1
            stripped=$(ds_unquoted_command "$(ds_code_only "$cmd")")
            LC_ALL=C grep -qE -- "$rx" <<< "$stripped" && return 0
            return 1
            ;;
        command_absent)
            # Правило о МИРЕ, а не о тексте: названного исполняемого на этой машине нет,
            # значит вызов упадёт здесь и сейчас (код 127), а не «когда-нибудь на другой
            # системе». На машине, где инструмент есть, признак молчит сам — список имён
            # не нужно ни сужать, ни отключать под Linux.
            #
            # Повод: `timeout` вызывался 6 раз за корпус в 2342 вызова и на macOS
            # отсутствует; один раз код 127 был почти прочитан как «зависания нет».
            local tool_bin cmd stripped
            tool_bin=$(printf '%s' "$node" | jq -r '.command_absent' 2>/dev/null)
            [ -z "$tool_bin" ] && return 1
            command -v "$tool_bin" >/dev/null 2>&1 && return 1   # инструмент есть — не признак
            cmd=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null)
            [ -z "$cmd" ] && return 1
            # Вид оболочки: имя в теле heredoc — содержимое будущего файла, а не вызов.
            stripped=$(ds_unquoted_command "$(ds_code_only "$(ds_shell_only "$cmd")")")
            # Имя обязано стоять в позиции КОМАНДЫ: начало строки либо после ; & | (.
            # Одного пробела слева мало — на нём `grep -r timeout hooks/` получил отказ
            # за упоминание слова аргументом (замер 28 августа 2026, первый прогон).
            # КОНТРПРИМЕР: `xargs timeout ...` и `env timeout ...` не ловятся — имя стоит
            # аргументом обёртки, и отличить его от упоминания нечем.
            LC_ALL=C grep -qE -- "(^|[;&|(])[[:space:]]*${tool_bin}([[:space:]]|$)" <<< "$stripped" && return 0
            return 1
            ;;
        os_is)
            # bsd | gnu. Флаг, который валится на BSD, на GNU законен — и наоборот.
            # Без этого различия один признак не может нести отказ: половина того, что он
            # ловит, здесь работает правильно.
            local want kernel
            want=$(printf '%s' "$node" | jq -r '.os_is' 2>/dev/null)
            [ -z "$want" ] && return 1
            kernel=$(uname -s 2>/dev/null || echo unknown)
            case "$kernel" in
                Darwin|*BSD*) [ "$want" = "bsd" ] && return 0 ;;
                Linux)        [ "$want" = "gnu" ] && return 0 ;;
            esac
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Evaluate one named signal. Extracts the all_of/any_of branch and delegates.
# Arguments: <signal_json> <tool_name> <tool_input_json> <prompt>
ds_evaluate_signal() {
    local signal="$1" tool_name="$2" tool_input="$3" prompt="$4"
    _ds_jq_available || return 1
    local op
    op=$(printf '%s' "$signal" | jq -r 'if has("all_of") then "all_of" elif has("any_of") then "any_of" elif has("none_of") then "none_of" else empty end' 2>/dev/null)
    [ -z "$op" ] && return 1
    local composition
    composition=$(printf '%s' "$signal" | jq -c "{${op}: .${op}}" 2>/dev/null)
    [ -z "$composition" ] && return 1
    ds_evaluate_node "$composition" "$tool_name" "$tool_input" "$prompt"
}

# Main entry. Evaluates every signal in pattern; on first match echoes name and exits 0.
# Arguments: <pattern_file> <tool_name> <tool_input_json> <prompt>
ds_evaluate() {
    local pattern_file="$1" tool_name="$2" tool_input="$3" prompt="$4"
    local signals
    signals=$(ds_extract_signals "$pattern_file")
    [ "$signals" = "[]" ] && return 1
    local count
    count=$(printf '%s' "$signals" | jq -r '. | length' 2>/dev/null)
    [ -z "$count" ] || [ "$count" -eq 0 ] && return 1
    local i signal name
    for (( i = 0; i < count; i++ )); do
        signal=$(printf '%s' "$signals" | jq -c ".[$i]" 2>/dev/null)
        [ -z "$signal" ] && continue
        name=$(printf '%s' "$signal" | jq -r '.name // ""' 2>/dev/null)
        if ds_evaluate_signal "$signal" "$tool_name" "$tool_input" "$prompt"; then
            printf '%s\n' "$name"
            return 0
        fi
    done
    return 1
}
