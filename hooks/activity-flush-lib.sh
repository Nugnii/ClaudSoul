#!/usr/bin/env bash
# activity-flush-lib.sh — v1.6.0: парсит transcript сессии и пишет activity-секцию в .claude-docs/session-activity.md.
#
# ПРЕФИКСЫ: activity_
# Объявление пространства имён (11 сентября 2026, D390). Функция этой библиотеки
# носит один из названных префиксов; имя с ведущим `_` считается внутренним и под
# правило не подпадает. Сверяет `hooks/lib-prefix-guard.sh` при записи файла.
# Список собран ИЗ ФАКТА, а не придуман: он фиксирует нынешнее состояние, чтобы
# разнобой не рос дальше — из 21 библиотеки с 3+ функциями лишь 10 держали 80%+
# имён под одним префиксом, а объявления не было ни у одной из 29.
#
# Источник данных: Claude Code transcript JSONL. Считаем tool_use по именам,
# извлекаем file_path из Edit/Write/MultiEdit inputs, агрегируем в один блок.
#
# v1.6.0 (Фаза 2 конвейера L1->L2): дополнительно захватываем промпты пользователя
# как семантический substrate для /compile. На уровне текстовых блоков отбрасываем
# инжекты хуков (system-reminder, SESSION REGISTRY, командные маркеры) — чтобы не
# потерять реальный промпт, — каждый усекаем head 120 / tail 40 + маркер <+Nc>
# (гигиена усечки полей из claude-mem). Существующий вывод не меняется.
#
# Контракт:
#   activity_flush <session_id> <transcript_path> <project_cwd>
# Exit codes:
#   0 — запись сделана. Пропускается ТОЛЬКО честно пустая сессия (разбор удался, ходов 0);
#       отказ разбора расшифровки с 5 сентября 2026 пишет блок с пометкой «НЕ ПРОЧИТАНА» —
#       молчание там было неотличимо от «работы не было» (род B)
#   1 — transcript/cwd недоступны
#   2 — session_id не передан
#
# Идемпотентность: РОВНО ОДИН блок на session_id в файле. Свежий вызов вычёркивает
# прежний блок той же сессии и пишет новый — снимок кумулятивный (транскрипт читается
# целиком каждый раз), поэтому последний блок содержит всю сессию.
#
# До 2 сентября 2026 здесь стояло обратное: «повторный вызов даст вторую запись
# (ответственность caller'а — вызывать 1 раз на Stop)». Контракт описывал событие неверно:
# Stop — конец ХОДА, а не сессии, и caller (session-collector) зовёт flush на каждом.
# Цена измерена: 772 блока на 63 сессии, 1,6 МБ, 77% байтов файла — дословный повтор уже
# записанного; худшая сессия дала 45 блоков на 287 КБ при последнем блоке в 12 КБ (D259).
#
# Зачем отдельный файл (а не SESSION.md): SESSION.md — narrative под human/agent
# контролем, activity — машинный лог. Разделение concerns: narrative survives
# даже если activity drift, activity survives даже если /save не вызван.

activity_flush() {
    local sid="${1:-}"
    local transcript="${2:-}"
    local cwd="${3:-}"

    [ -z "$sid" ] && return 2
    [ -n "$transcript" ] && [ -f "$transcript" ] || return 1
    [ -n "$cwd" ] && [ -d "$cwd" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    # Aggregate tool_use counts and files modified in a single jq pass.
    # Output: "total|Read:N Edit:M Bash:K|/path/a.md,/path/b.py|commit_subjects"
    local stats
    stats=$(jq -sr '
        def pick_tools(x):
            (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then
                ($c | map(select(.type == "tool_use") | .name))
            else [] end;
        def pick_files(x):
            (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then
                ($c | map(select(.type == "tool_use" and (.name == "Edit" or .name == "Write" or .name == "MultiEdit"))
                        | .input.file_path // empty) | map(select(. != null and . != "")))
            else [] end;

        # Flatten across all assistant entries.
        ([.[] | select((.message.role // .role // "") == "assistant") | pick_tools(.)] | flatten) as $tools |
        ([.[] | select((.message.role // .role // "") == "assistant") | pick_files(.)] | flatten | unique) as $files |

        ($tools | length) as $total |
        ($tools | group_by(.) | map("\(.[0]):\(length)") | join(" ")) as $by_name |

        "\($total)|\($by_name)|\($files | join(","))"
    ' "$transcript" 2>/dev/null)

    # Пустой вывод означает ТОЛЬКО отказ разбора: выражение выше всегда печатает строку
    # `"\($total)|\($by_name)|…"`, и при нулевой активности она выглядит как `0||`.
    # До 5 сентября 2026 здесь стоял голый `return 0` — «нечего записывать», — и оборванная
    # строка расшифровки уносила активность ЦЕЛОЙ сессии из `.claude-docs/session-activity.md`
    # молча, вместе с материалом для `/compile`. Признак рода B этого не видел: проверку
    # `[ -z "$V" ]` он считает различением, хотя различение здесь вело в благоприятный исход.
    # Отказ НЕ выходит здесь, а доносится флагом до общего пути записи: у файла контракт
    # «один блок на сессию», и свежий блок вычёркивает прежний (строки ниже). Ранний выход
    # с собственной записью давал бы ДВА блока одной сессии — поймано противником по правке
    # 5 сентября 2026. Первая же редакция этой ветки, кроме того, ссылалась на
    # `archive_file`, объявленный `local` девяноста строками ниже.
    local stats_unread=0
    [ -z "$stats" ] && stats_unread=1

    local total by_name files_list
    total=$(echo "$stats" | awk -F'|' '{print $1}')
    by_name=$(echo "$stats" | awk -F'|' '{print $2}')
    files_list=$(echo "$stats" | awk -F'|' '{print $3}')

    [ "$stats_unread" -eq 0 ] && [ "${total:-0}" -eq 0 ] && return 0

    # Git commits during session window (~4h back — conservative)
    local commits=""
    if [ -d "$cwd/.git" ]; then
        commits=$(git -C "$cwd" log --since="4 hours ago" --oneline 2>/dev/null | head -5 | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')
    fi

    # Files modified: shorten to basenames only (avoid full path leak in shared repo)
    local files_short=""
    if [ -n "$files_list" ]; then
        files_short=$(echo "$files_list" | tr ',' '\n' | awk -F/ '{print $NF}' | tr '\n' ' ' | sed 's/ $//')
    fi

    # User prompts (Фаза 2 substrate for /compile): per text-block filtering drops
    # hook-injected boilerplate (so a real prompt with attached injected context is
    # NOT lost), whitespace collapsed, each prompt truncated head 120 / tail 40 with
    # an elision marker. One prompt per output line.
    # Отсев системных ходов. Перечень маркеров — из `hook-input-lib.sh`
    # (`NON_USER_TURN_RE`), а не свой: два перечня расходятся, и это уже случалось
    # дважды за 27 августа 2026. Здесь он дополнен ПОБЛОЧНЫМ шумом — инжектами хуков
    # и `[Image:`, который внутри настоящей реплики со скриншотом встречается и
    # целый ход из-за него выбрасывать нельзя.
    local _hil="${HOOK_INPUT_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook-input-lib.sh}"
    # shellcheck source=/dev/null
    [ -f "$_hil" ] && . "$_hil"
    # Отказ сорса гасился запасным литералом ИЗ ТРЁХ маркеров при шести настоящих (род B,
    # 5 сентября 2026): молча пропадали `<local-command-stdout`, `<command-name>` и
    # `^Base directory for this skill:`, служебные ходы попадали в лог как речь собеседника,
    # и ни число, ни содержимое отчёта не давали это заметить. Копии перечня ХОДОВ здесь
    # больше нет — вторая копия и есть тот дефект, о котором предупреждает комментарий выше.
    # Поблочный шум (`system-reminder`, инжекты хуков, `[Image:`) — ОТДЕЛЬНЫЙ список, он
    # всегда жил здесь и ни у кого не дублируется. Отказ чтения перечня ходов НАЗЫВАЕТСЯ
    # в отчёте, а не подменяется догадкой.
    local noise_unread=""
    [ -z "${NON_USER_TURN_RE:-}" ] && noise_unread=" ⚠️ перечень системных маркеров НЕ ПРОЧИТАН ($_hil) — служебные ходы НЕ отсеяны"
    # Пустой перечень нельзя склеивать через `|`: ведущая черта даёт пустую альтернативу,
    # то есть регексп, совпадающий с ЛЮБОЙ строкой, — отчёт стал бы пустым молча.
    local noise_re="system-reminder|SESSION REGISTRY|Intrusiveness state|hook additional context|<command-message>|<local-command|\\[Image:"
    [ -n "${NON_USER_TURN_RE:-}" ] && noise_re="${NON_USER_TURN_RE}|${noise_re}"

    local prompts
    prompts=$(jq -sr --arg noise "$noise_re" '
        def clean: gsub("[\n\r\t]+";" ") | gsub("  +";" ") | sub("^ +";"") | sub(" +$";"");
        [ .[]
          # Вставки харнесса (isMeta) — не активность собеседника. Текстовый шум-фильтр
          # ниже ловит их по маркерам и половину пропускает: замер 8 сентября 2026 —
          # список маркеров берёт 39 вставок из 74, поле isMeta добавляет ещё 35.
          | select((.message.role // .role // "") == "user" and ((.isMeta // false) | not))
          | (.message.content // .content) as $c
          | ( if ($c|type)=="string" then
                (if ($c | test($noise)) then "" else $c end)
              elif ($c|type)=="array" then
                ($c | map(select(.type=="text") | .text)
                    | map(select(test($noise) | not))
                    | join(" "))
              else "" end )
          | select(type=="string") | clean | select(length > 0)
        ]
        | map(if length > 180 then (.[0:120] + " …<+\(length-120)c>… " + .[-40:]) else . end)
        | .[]
    ' "$transcript" 2>/dev/null)

    # Redact-слой (D61): секреты не ложатся в дословный лог — замена ДО записи,
    # не на публикации. Классы паттернов — из scripts/publish/forbidden.txt (+hf_);
    # прецедент: живой hf_-токен пролежал в session-activity.md десять дней.
    [ -n "$prompts" ] && prompts=$(printf '%s\n' "$prompts" | sed -E \
        -e 's/hf_[A-Za-z0-9]{16,}/[REDACTED-hf]/g' \
        -e 's/sk-[A-Za-z0-9_-]{16,}/[REDACTED-sk]/g' \
        -e 's/gh[pousr]_[A-Za-z0-9]{20,}/[REDACTED-gh]/g' \
        -e 's/github_pat_[A-Za-z0-9_]{20,}/[REDACTED-gh]/g' \
        -e 's/AKIA[0-9A-Z]{16}/[REDACTED-aws]/g' \
        -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED-slack]/g' \
        -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[REDACTED-key]/g')

    local pcount=0
    [ -n "$prompts" ] && pcount=$(printf '%s\n' "$prompts" | grep -c .)

    # Write to archive
    local archive_dir="$cwd/.claude-docs"
    local archive_file="$archive_dir/session-activity.md"
    mkdir -p "$archive_dir" 2>/dev/null || true
    [ -d "$archive_dir" ] || return 0

    # Свежий блок вычёркивает прежний блок ТОЙ ЖЕ сессии: снимок кумулятивен, и прежний
    # блок целиком содержится в новом. Курсор «докуда дошли» заводить не нужно и не стоит —
    # файл состояния в $STATE_DIR жил бы вечно, а транскрипт и так читается целиком.
    # Коммиты СЛИВАЮТСЯ, а не заменяются: `git log --since=4 hours ago` — скользящее окно,
    # ранние хеши из него уходят, и простая замена блока теряла бы их (замер: 499 хешей в
    # 39 сессиях).
    # Имя временного файла УНИКАЛЬНО ($$ + $RANDOM): у двух сессий в одном cwd фиксированный
    # `$archive_file.tmp` — один путь, и два одновременных awk писали бы в него вместе.
    # Гонка не гипотетическая: 21 сессия из 63 идёт чересстрочно, 4 пары соседних блоков
    # разных сессий лежат в одной минуте. НАЗВАННЫЙ ПРЕДЕЛ: уникальное имя защищает от
    # порчи содержимого, но не делает пару «чтение → mv» атомарной — блок, дописанный
    # ДРУГОЙ сессией между ними, потеряется. Условие снятия: если такая потеря будет
    # наблюдена, брать rename-заявку из hooks/lib/injection-log-rotate.py.
    if [ -f "$archive_file" ]; then
        local _tmp="${archive_file}.tmp.$$.${RANDOM:-0}"
        commits=$(printf '%s %s' "$(awk -v s="session ${sid:0:8}" \
            '/^## /{f=index($0,s)>0;next} f && /^- Commits: /{print substr($0,12)}' \
            "$archive_file" 2>/dev/null)" "$commits" \
            | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ $//')
        # Пустые строки схлопываются: у вырезанного блока остаётся его ведущая пустая
        # строка, и без этого они копились внутри сегмента, который сравнивает проверка.
        awk -v s="session ${sid:0:8}" '
            /^## /{skip=index($0,s)>0}
            skip{next}
            NF==0{b=1; next}
            {if(b) print ""; b=0; print}
        ' "$archive_file" > "$_tmp" 2>/dev/null && mv "$_tmp" "$archive_file"
        rm -f "$_tmp" 2>/dev/null || true
    fi

    {
        printf '\n## %s — session %s\n' "$(date '+%Y-%m-%d %H:%M')" "${sid:0:8}"
        if [ "$stats_unread" -eq 1 ]; then
            printf -- '- ⚠️ активность НЕ ПРОЧИТАНА: разбор расшифровки отказал (%s) — это не «работы не было»\n' \
                "${transcript##*/}"
        fi
        # Тревога о непрочитанном перечне стоит ОТДЕЛЬНОЙ строкой, а не хвостом строки
        # `Prompts`: та печатается только при `pcount > 0`, и при нулевом счёте реплик
        # предупреждение исчезало бы ровно тогда, когда отсев сломан сильнее всего.
        [ -n "$noise_unread" ] && printf -- '-%s\n' "$noise_unread"
        printf -- '- Tool calls: %s (%s)\n' "${total:-0}" "${by_name:-none}"
        [ -n "$files_short" ] && printf -- '- Files touched: %s\n' "$files_short"
        [ -n "$commits" ] && printf -- '- Commits: %s\n' "$commits"
        if [ "${pcount:-0}" -gt 0 ]; then
            printf -- '- Prompts (%s):\n' "$pcount"
            printf '%s\n' "$prompts" | sed 's/^/  - /'
        fi
        printf '\n'
    } >> "$archive_file" 2>/dev/null || true

    return 0
}

# When invoked directly: run with argv
if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
    activity_flush "${1:-}" "${2:-}" "${3:-}"
fi
