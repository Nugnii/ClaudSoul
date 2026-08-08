#!/bin/bash
# paths-lib.sh — v1.0.0
# Единый источник путей ClaudSoul для хуков. Наполняется инкрементально (TASK-003):
# каждая под-часть добавляет сюда одну переменную/функцию, по мере перевода хуков.
#
# До paths-lib эти пути были захардкожены вразнобой по десяткам мест с разными
# именами override-переменных (см. docs/health-audit-2026-06-20.md, F10-F13).
#
# Provides:
#   CLAUDSOUL_ROOT            — корень репозитория проекта (default ~/My Project/ClaudSoul)  [003a]
#   find_project_root [dir]   — поднимается от dir (default $PWD) к ближайшему .git или
#                               CLAUDE.md; печатает его (fallback: сам dir)                  [003b]
#
# Контракт: используем `:=`, поэтому уже заданное окружение (или тест) НЕ
# перезаписывается — lib лишь подставляет дефолт, когда переменная пуста.
# Источать можно многократно (идемпотентно).

: "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"
: "${LESSONS_DIR:=$HOME/.claude/global-lessons}"   # база знаний (была под 3 именами: KNOWLEDGE_DIR/LESSONS_DIR/GLOBAL_LESSONS)
: "${STATE_DIR:=$HOME/.claude/hooks/state}"         # состояние хуков (003e); `:=` уважает env/тест — не перезаписывает заданное

# Единый walk-up для определения корня проекта. До 003b было: каноничная версия
# в session-registry-lib (_sr_detect_project, без параметра), а knowledge-activator
# и session-start использовали сырой cwd без walk-up (F13) — из подпапки проекта
# не находили SESSION.md/CLAUDE.md.
find_project_root() {
    local dir="${1:-$PWD}"
    local start="$dir"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
            printf '%s' "$dir"; return 0
        fi
        dir="$(dirname "$dir")"
    done
    printf '%s' "$start"
}

# Единый парсинг session_id из payload-JSON хука (F3). Унифицирует ТОЛЬКО парсинг —
# fallback передаётся аргументом, поэтому контракт каждого хука сохраняется:
#   resolve_session_id "$INPUT"        → SID или "unknown" (для хуков, что продолжают)
#   resolve_session_id "$INPUT" ""     → SID или "" (для хуков, что делают exit при пустом)
resolve_session_id() {
    # ${2-unknown} (без `:`) — fallback по умолчанию только когда аргумент НЕ передан;
    # явный пустой `""` сохраняется (контракт exit-style хуков).
    local input="$1" fallback="${2-unknown}" sid
    sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
    printf '%s' "${sid:-$fallback}"
}
