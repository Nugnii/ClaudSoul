#!/usr/bin/env bash
# activity-flush-lib.sh — v1.6.0: парсит transcript сессии и пишет activity-секцию в .claude-docs/session-activity.md.
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
#   0 — запись сделана (или активности не было — пустой экспорт пропускается)
#   1 — transcript/cwd недоступны
#   2 — session_id не передан
#
# Идемпотентность: отдельный блок на session_id; повторный вызов для той же
# сессии даст вторую запись (ответственность caller'а — вызывать 1 раз на Stop).
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

    [ -z "$stats" ] && return 0

    local total by_name files_list
    total=$(echo "$stats" | awk -F'|' '{print $1}')
    by_name=$(echo "$stats" | awk -F'|' '{print $2}')
    files_list=$(echo "$stats" | awk -F'|' '{print $3}')

    [ "${total:-0}" -eq 0 ] && return 0

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
    local noise_re="${NON_USER_TURN_RE:-<task-notification|<bash-stdout|<tool-use-error}"
    noise_re="${noise_re}|system-reminder|SESSION REGISTRY|Intrusiveness state|hook additional context|<command-message>|<local-command|\\[Image:"

    local prompts
    prompts=$(jq -sr --arg noise "$noise_re" '
        def clean: gsub("[\n\r\t]+";" ") | gsub("  +";" ") | sub("^ +";"") | sub(" +$";"");
        [ .[]
          | select((.message.role // .role // "") == "user")
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

    {
        printf '\n## %s — session %s\n' "$(date '+%Y-%m-%d %H:%M')" "${sid:0:8}"
        printf -- '- Tool calls: %s (%s)\n' "$total" "${by_name:-none}"
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
