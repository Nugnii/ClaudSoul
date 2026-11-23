#!/usr/bin/env bash
# playwright-cli-guard.sh — PreToolUse: блокирует одноразовые Playwright-скрипты, подсказывает на чтение снимка прогона, вынуждая использовать CLI (codegen / test / show-trace), и отказывает в правке спеки, упавшей на элементе страницы, пока её снимок не прочитан.
# en: PreToolUse: blocks throwaway Playwright scripts, hints on reading a run's screenshot, forcing the CLI instead (codegen / test / show-trace), and refuses editing a spec that failed on a page element until its error-context snapshot is read.
#
# До 2 сентября 2026 текст отказа отсылал к скиллу `/playwright-cli`, которого установщик
# не ставит и в репозитории нет (D260): на чистой машине оставался бы отказчик, посылающий
# к несуществующему. Отказ теперь называет команды CLI — они есть везде, где есть
# playwright.
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
#   - Read: снимок прогона (*.png), прочитанный как картинка, — ПОДСКАЗКА, не отказ (с 12 октября 2026).
#     Снимок прогона — PNG новее отметки последнего запуска Playwright В ЭТОЙ сессии (ветка Bash ставит
#     отметку `state/playwright-run-<сессия>` на любой запуск `playwright …` и `test:e2e`) либо лежащий в
#     test-results/ или playwright-report/. Раз на прогон: ключ дедупа — токен прогона в отметке.
#     Повод — поправка владельца в ProjectA: «Ты почему-то используешь снимки вместо cli… Он всегда основной и
#     это прописано в правилах разработки»; полностраничный снимок при открытом всплывающем окне нарисовал
#     сдвиг вёрстки на 161px, которого на странице нет, — три лишних захода на спецификацию.
#     Чем решалось раньше и судьба каждого: правило глобального CLAUDE.md (Step 1 и 4) остаётся, его строка
#     «Take a screenshot» переписана — снимок вложение, не доказательство (иначе правило спорило бы с этой
#     веткой); этот же хук расширен, а не заведён второй — у факта «обход Playwright CLI» один владелец.
#     Замер по корпусу (`scripts/signal-precision-corpus.py`, Read.file_path): путь test-results/,
#     playwright-report/, shots* — 44 чтения из 2599, все 44 — снимки прогонов; признак «новее отметки» по
#     корпусу не мерится (время файла на момент вызова не восстановимо). Журнал чтений
#     (`state/playwright-shot-reads.tsv`) снят 7 ноября 2026 (D1229): читателя у него не было с заведения, а вердикта
#     «чтение законно» запись не несёт — потребитель был бы прибором без результата (тот же довод, что у снятого следа
#     канарейки, ROOTS.md R2). Условие перевода в отказ мерится заново, когда вопрос поднимут: зонд на метке прогона.
#     НАЗВАННЫЙ ПРЕДЕЛ: подсказка PreToolUse приходит вместе с результатом чтения, то есть после него;
#     картинка владельца, положенная после прогона, тоже получит подсказку (текст это называет).
#     Условие снятия: харнесс начнёт доставлять подсказку PreToolUse до исполнения вызова.
#     Условие перевода в отказ: замер, где ни одно чтение снимка прогона не было законным.
#   - Write/Edit/MultiEdit `*.spec.*`: проверка этой спеки в последнем прогоне упала НА ЭЛЕМЕНТЕ страницы, а её снимок
#     `error-context.md` не прочитан — ОТКАЗ до чтения (с 22 ноября 2026, D1356, решение владельца «Оба»: печать снимка
#     в выводе прогона ставит ProjectA, отказ — ClaudSoul). Признак и замер — hooks/lib/playwright_snapshot.py; корпус:
#     29 правок упавшей спеки вслепую, после 15 та же проверка упала снова. Чем решалось раньше: ветка Read выше
#     подсказывает про PNG-снимок — предмет иной (картинка как доказательство), обе ветки нужны; знание
#     pattern-fixture-form-not-taken-from-the-world держало правило текстом и остаётся его объяснением.
#     НАЗВАННЫЙ ПРЕДЕЛ: прогон не из расшифровки (терминал владельца, CI) не виден — правка проходит.
#
# Что НЕ трогает (правильный путь):
#   - playwright test | codegen | show-trace | show-report | install | --version
#   - файлы под web/tests/, /e2e/, *.spec.*, *.test.*, /__tests__/ (живущие тесты)
#   - вызовы playwright CLI напрямую
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
    if grep -Eq '(chromium|firefox|webkit)[[:space:]]*\.[[:space:]]*launch[[:space:]]*\(' <<< "$text"; then
        return 0
    fi
    # import bare playwright + навигация page.goto — драйвинг страницы вручную
    if grep -Eq "(from[[:space:]]+['\"]playwright['\"]|require\\([[:space:]]*['\"]playwright['\"])" <<< "$text" \
       && grep -Eq '\.goto[[:space:]]*\(' <<< "$text"; then
        return 0
    fi
    return 1
}

REASON='🛑 playwright-cli-guard: одноразовый Playwright-скрипт — запрещено.
Используй CLI, а не пиши scratch:
  • записать действия → playwright codegen <url>  (даёт рабочие селекторы, лечит боль Ant Design)
  • прогнать → playwright test web/tests/...
  • разобрать падение → playwright show-trace / UI mode / --debug
Если нужен ПОСТОЯННЫЙ тест — положи его в web/tests/ как *.spec.ts (тогда хук пропустит).
Отключить разово: env PLAYWRIGHT_CLI_GUARD_OFF=1.'

emit_deny() {   # emit_deny [текст] [nomark]
    # Маркер сработавшего стража: его читает cross-hook recall gate (`blocker-tier-check.sh`, список GUARD_FIRED_MARKERS) —
    # до D530 читатель ждал его, а писателя не было, и напоминание после отказа не приходило никогда.
    # Маркер значит «поймана импровизация» (одноразовый скрипт): recall gate отвечает на него знанием
    # pattern-inside-out-blindness. Отказ по непрочитанному снимку (D1356) — не импровизация, поэтому зовётся с
    # `nomark` (скептик D1356, L6: иначе следующая запись получала напоминание не о том).
    [ -n "${2:-}" ] || { mkdir -p "$STATE_DIR" 2>/dev/null \
        && printf '{"ts":%s,"tool":"%s"}\n' "$(date +%s)" "$TOOL_NAME" >> "$STATE_DIR/playwright-cli-guard-fired-$SID.jsonl" 2>/dev/null; }
    jq -n --arg ctx "${1:-$REASON}" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $ctx
        }
    }'
    exit 0
}

HINT='🎭 playwright-cli-guard: снимок прогона Playwright прочитан как картинка.
Проверку интерфейса доказывает Playwright CLI — это правило разработки (глобальный CLAUDE.md, Step 1 и 4;
в проектах — «проверка глазами (Playwright)»):
  • утверждения `npx playwright test` — видимость, классы, размеры, прокрутка (замер через evaluate);
  • разбор странного — `--trace on`, затем `npx playwright show-trace <trace.zip>`;
  • показать владельцу — `--headed`.
Снимок — вложение для владельца, а не доказательство: полностраничный снимок при открытом всплывающем окне
рисует сдвиг вёрстки, которого на странице нет (ProjectA, 12 октября 2026).
Картинка не из прогона (её прислал владелец) — продолжай.'

emit_hint() {
    jq -n --arg ctx "$HINT" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
    exit 0
}

# --- Правка упавшей спеки до чтения её снимка (D1356) ---
# Признак и его замер — hooks/lib/playwright_snapshot.py. Расшифровка — того, кто правит (`resolve_actor_transcript`,
# hooks/paths-lib.sh): у помощника своя, родительская его прогонов не содержит. Три состояния прибора: библиотеки,
# python или расшифровки нет — молчим (другая машина, не отказ); прибор сломался (код ≥ 2) — говорим подсказкой, иначе
# молчание читалось бы «снимок прочитан»; ответил пусто — молчим.
SNAP_LIB="${SNAP_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/playwright_snapshot.py}"
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
snapshot_gate() {
    local spec="$1" tr out rc
    [ -f "$SNAP_LIB" ] && [ -f "$PATHS_LIB" ] && command -v python3 >/dev/null 2>&1 || return 0
    # shellcheck source=/dev/null
    source "$PATHS_LIB" 2>/dev/null
    command -v resolve_actor_transcript >/dev/null 2>&1 || return 0
    tr=$(resolve_actor_transcript "$INPUT")
    [ -n "$tr" ] && [ -f "$tr" ] || return 0
    out=$(python3 "$SNAP_LIB" "$tr" "$spec" 2>/dev/null); rc=$?
    # Любой ненулевой код — сбой, а не «прочитано»: необработанное исключение python давало 1 (скептик D1356, L5).
    if [ "$rc" -ne 0 ]; then
        jq -n --arg ctx "🎭 playwright-cli-guard: проверка «снимок упавшего прогона прочитан» не смогла прочитать расшифровку (код $rc) — правка пропущена без суждения." \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
        exit 0
    fi
    [ -n "$out" ] || return 0
    # Строка `?<TAB>путь` — род падения срезан хвостом вывода, а снимка на диске нет (D1359): судить нечем, поэтому
    # подсказка, а не отказ, и один раз на набор путей — правка той же спеки следом её не повторяет.
    local deny hint seen
    deny=$(printf '%s\n' "$out" | grep -v $'^?\t')
    if [ -z "$deny" ]; then
        hint=$(printf '%s\n' "$out" | sed -n $'s/^?\t//p')
        seen="$STATE_DIR/playwright-snap-hint-$SID"
        [ "$(cat "$seen" 2>/dev/null)" = "$hint" ] && return 0
        mkdir -p "$STATE_DIR" 2>/dev/null
        printf '%s\n' "$hint" > "$seen" 2>/dev/null
        jq -n --arg ctx "🎭 playwright-cli-guard: проверка этой спеки в последнем прогоне упала, но род падения в выводе не виден (вывод обрезан — например, \`| tail\`), а снимок на диске не найден:
$(printf '%s\n' "$hint" | sed 's/^/  • /')
Если падение на элементе страницы — правь по снимку, а не по памяти: прогони снова без обрезки вывода и прочитай снимок." \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
        exit 0
    fi
    emit_deny "🛑 playwright-cli-guard: проверка этой спеки в последнем прогоне упала на элементе страницы, а снимок страницы
с момента падения не прочитан:
$(printf '%s\n' "$deny" | sed 's/^/  • /')
Путь — как его напечатал прогон (относительно папки, где шёл прогон). В снимке DOM в момент падения: есть ли узел, какой
у него текст, что его перекрыло. Прочитай снимок (Read или cat) — правка пройдёт сама.
Почему отказ, а не подсказка: замер 22 ноября 2026 — из 29 правок упавшей спеки без чтения снимка после 15 та же
проверка упала снова (D1356). Падение не на элементе (значение, журнал, геометрия) этот отказ не ловит.
Отключить разово: env PLAYWRIGHT_CLI_GUARD_OFF=1." nomark
}

STATE_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}"
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null | tr -cd 'A-Za-z0-9_-')
[ -z "$SID" ] && SID="nosession"
RUN_MARK="$STATE_DIR/playwright-run-$SID"

case "$TOOL_NAME" in
    Read)
        FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
        grep -Eqi '\.png$' <<< "$FILE_PATH" || exit 0
        # Снимок прогона: новее отметки запуска Playwright в этой сессии либо в выходных каталогах Playwright.
        if [ -f "$RUN_MARK" ] && [ "$FILE_PATH" -nt "$RUN_MARK" ]; then
            RUN=$(cat "$RUN_MARK" 2>/dev/null)
        elif grep -Eq '/(test-results|playwright-report)/' <<< "$FILE_PATH"; then
            RUN="output-dir"
        else
            exit 0
        fi
        SEEN="$STATE_DIR/playwright-shot-seen-$SID"
        [ "$(cat "$SEEN" 2>/dev/null)" = "$RUN" ] && exit 0
        printf '%s\n' "$RUN" > "$SEEN" 2>/dev/null
        emit_hint
        ;;


    Write|Edit|MultiEdit)
        FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
        [ -z "$FILE_PATH" ] && exit 0
        # только скриптовые расширения
        grep -Eq '\.(ts|tsx|js|jsx|mjs|cjs)$' <<< "$FILE_PATH" || exit 0
        # спека Playwright, упавшая на элементе страницы, — сперва её снимок (D1356)
        grep -Eq '\.spec\.(ts|tsx|js|jsx|mjs|cjs)$' <<< "$FILE_PATH" && snapshot_gate "$FILE_PATH"
        # живущие тесты — разрешены
        grep -Eq '(/tests?/|/e2e/|/__tests__/|\.(spec|test)\.)' <<< "$FILE_PATH" && exit 0

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

        # Запуск Playwright в этой сессии — отметка для ветки Read: снимок новее неё снят прогоном. Токен (время и
        # pid) отличает прогоны друг от друга — по нему дедуп подсказки «раз на прогон».
        if grep -Eq '(^|[^[:alnum:]_.-])playwright([[:space:]]|$)|test:e2e' <<< "$(executable_part "$COMMAND")"; then
            mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s-%s\n' "$(date +%s)" "$$" > "$RUN_MARK" 2>/dev/null
        fi

        # правильный путь — не мешаем
        grep -Eq 'playwright[[:space:]]+(test|codegen|show-trace|show-report|install|--version|-V)' <<< "$NORM" && exit 0

        # heredoc/inline скрипт с launch — но только если его кто-то ИСПОЛНЯЕТ.
        # Дважды заблокировал реальную работу: `cat > file <<EOF ... launch( ... EOF`
        # — тело heredoc уходит в файл, а не в интерпретатор. Один раз это была запись
        # собственного теста этого хука, второй — запись раздела BACKLOG про этот дефект.
        # executable_part вырезает кавычки и тела heredoc, поэтому имя интерпретатора
        # найдётся только там, где оно действительно команда, а не текст.
        if grep -Eq '(^|[[:space:];&|`(])(python3?|node|deno|bun|npx|ts-node|tsx)([[:space:]]|$)' \
             <<< "$(executable_part "$COMMAND")"; then
            is_scratch_playwright "$COMMAND" && emit_deny
        fi
        # node -e / --eval с playwright|chromium
        if grep -Eq '(^|[[:space:];&|`])node[[:space:]].*(-e|--eval)' <<< "$NORM" \
           && grep -Eq '(playwright|chromium|firefox|webkit)' <<< "$NORM"; then
            emit_deny
        fi
        ;;
esac

exit 0
