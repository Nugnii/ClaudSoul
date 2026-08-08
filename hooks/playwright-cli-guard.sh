#!/usr/bin/env bash
# playwright-cli-guard.sh — PreToolUse: блокирует одноразовые Playwright-скрипты,
# en: PreToolUse: blocks throwaway Playwright scripts in favour of the /playwright-cli skill.
# вынуждая использовать скилл /playwright-cli (codegen / test / show-trace).
#
# Почему: текстовое правило «используй CLI» — уровень 1 embedded-ness (хрупкий,
# держится только как инструкция, дрейфует). См. principle-knowledge-in-the-world.md.
# Этот хук — уровень 3: механический перехват через harness (permissionDecision:deny),
# а не напоминание, которое агент может проигнорировать.
#
# Contract:
#   Input  (stdin): {session_id, tool_name, tool_input, ...}  (PreToolUse JSON)
#   Output (stdout): {hookSpecificOutput:{hookEventName,permissionDecision:"deny",permissionDecisionReason}}
#                    при совпадении сигнатуры «scratch-скрипт»; пусто иначе.
#   Exit: always 0 (degrade gracefully — никогда не ломаем поток).
#
# Что ловит (= «страдать хернёй»):
#   - Write/Edit/MultiEdit: создание .ts/.js Playwright-скрипта ВНЕ web/tests/
#     (контент содержит chromium/firefox/webkit.launch(  ИЛИ  import playwright + page.goto)
#   - Bash: heredoc/inline скрипт с *.launch( ; node -e/--eval с playwright/chromium
#
# Что НЕ трогает (правильный путь):
#   - playwright test | codegen | show-trace | show-report | install | --version
#   - файлы под web/tests/, /e2e/, *.spec.*, *.test.*, /__tests__/ (живущие тесты)
#   - вызовы самого скилла /playwright-cli
#
# Kill-switch: PLAYWRIGHT_CLI_GUARD_OFF=1 — полностью отключает (на случай ложняка).

set -uo pipefail

[ "${PLAYWRIGHT_CLI_GUARD_OFF:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

# Сужение области поиска до исполняемой части команды (single source — command-scope-lib.sh).
SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
if [ -f "$SCOPE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$SCOPE_LIB"
else
    executable_part() { printf '%s' "${1:-}"; }
fi

# --- Сигнатура «браузер-скрипт» в произвольном тексте (контент файла или команда) ---
is_scratch_playwright() {
    local text="$1"
    # прямой запуск браузера — самый сильный признак одноразового скрипта
    if printf '%s' "$text" | grep -Eq '(chromium|firefox|webkit)[[:space:]]*\.[[:space:]]*launch[[:space:]]*\('; then
        return 0
    fi
    # import bare playwright + навигация page.goto — драйвинг страницы вручную
    if printf '%s' "$text" | grep -Eq "(from[[:space:]]+['\"]playwright['\"]|require\\([[:space:]]*['\"]playwright['\"])" \
       && printf '%s' "$text" | grep -Eq '\.goto[[:space:]]*\('; then
        return 0
    fi
    return 1
}

REASON='🛑 playwright-cli-guard: одноразовый Playwright-скрипт — запрещено.
Используй скилл /playwright-cli, а не пиши scratch:
  • записать действия → playwright codegen <url>  (даёт рабочие селекторы, лечит боль Ant Design)
  • прогнать → playwright test web/tests/...
  • разобрать падение → playwright show-trace / UI mode / --debug
Если нужен ПОСТОЯННЫЙ тест — положи его в web/tests/ как *.spec.ts (тогда хук пропустит).
Отключить разово: env PLAYWRIGHT_CLI_GUARD_OFF=1.'

emit_deny() {
    jq -n --arg ctx "$REASON" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $ctx
        }
    }'
    exit 0
}

case "$TOOL_NAME" in
    Write|Edit|MultiEdit)
        FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
        [ -z "$FILE_PATH" ] && exit 0
        # только скриптовые расширения
        printf '%s' "$FILE_PATH" | grep -Eq '\.(ts|tsx|js|jsx|mjs|cjs)$' || exit 0
        # живущие тесты — разрешены
        printf '%s' "$FILE_PATH" | grep -Eq '(/tests?/|/e2e/|/__tests__/|\.(spec|test)\.)' && exit 0

        CONTENT=$(printf '%s' "$INPUT" | jq -r '
            .tool_input.content
            // .tool_input.new_string
            // ((.tool_input.edits // []) | map(.new_string) | join("\n"))
            // ""' 2>/dev/null)
        [ -z "$CONTENT" ] && exit 0

        is_scratch_playwright "$CONTENT" && emit_deny
        ;;

    Bash)
        COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
        [ -z "$COMMAND" ] && exit 0
        NORM=$(printf '%s' "$COMMAND" | tr -s '[:space:]' ' ')

        # правильный путь — не мешаем
        printf '%s' "$NORM" | grep -Eq 'playwright[[:space:]]+(test|codegen|show-trace|show-report|install|--version|-V)' && exit 0

        # heredoc/inline скрипт с launch — но только если его кто-то ИСПОЛНЯЕТ.
        # Дважды заблокировал реальную работу: `cat > file <<EOF ... launch( ... EOF`
        # — тело heredoc уходит в файл, а не в интерпретатор. Один раз это была запись
        # собственного теста этого хука, второй — запись раздела BACKLOG про этот дефект.
        # executable_part вырезает кавычки и тела heredoc, поэтому имя интерпретатора
        # найдётся только там, где оно действительно команда, а не текст.
        if printf '%s' "$(executable_part "$COMMAND")" \
           | grep -Eq '(^|[[:space:];&|`(])(python3?|node|deno|bun|npx|ts-node|tsx)([[:space:]]|$)'; then
            is_scratch_playwright "$COMMAND" && emit_deny
        fi
        # node -e / --eval с playwright|chromium
        if printf '%s' "$NORM" | grep -Eq '(^|[[:space:];&|`])node[[:space:]].*(-e|--eval)' \
           && printf '%s' "$NORM" | grep -Eq '(playwright|chromium|firefox|webkit)'; then
            emit_deny
        fi
        ;;
esac

exit 0
