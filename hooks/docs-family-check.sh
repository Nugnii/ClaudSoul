#!/usr/bin/env bash
# docs-family-check.sh — PreToolUse blocker-tier для docs family coverage при version bump.
# en: PreToolUse blocker-tier: on a version bump, checks the 5-doc family is covered by the commit.
#
# Closes the knowledge-action gap from case-2026-04-23-memory-without-action-gate:
# feedback memory "обнови документацию = все docs" существовала 4 релиза (v1.5.1-5.4),
# инжектилась в MEMORY.md каждую сессию, но ни разу не активировалась на действие.
# Триггер записи = ключевая фраза «обнови документацию», а не семантическая акция
# version bump. На четырёх релизах делалась эквивалентная акция без фразы — правило спало.
#
# Этот хук даёт action-gate: детектирует version bump в staged diff и проверяет, что
# docs family (architecture.md + PLAN.md + CHANGELOG.md + README.md + project CLAUDE.md)
# в том же diff. Если кого-то нет — silent reminder до коммита.
#
# v1.6.2 rationale (R3 false-positive fix): автоматический sweep `docs/*.md`
# (всех 15+ файлов в `docs/`) удалён после живой валидации на v1.6.1 — у нас
# frozen/archive docs (vision, internal-doc, analysis-levnikolaevich,
# research и т.д.) не требуют bump'а при install-patch релизе. Шум от over-
# reporting ослабляет gate. Живой набор — 5 docs; расширение через
# `DOCS_FAMILY_LIST` env для проектов, где docs/ тоже tracks live state.
#
# Contract:
#   Input  (stdin): {session_id, tool_name, tool_input, cwd}  (PreToolUse JSON)
#   Output (stdout): {hookSpecificOutput: {hookEventName, additionalContext}} или пусто
#   Exit:  always 0 (degrade gracefully)
#
# Silent by design (feedback_silent_correct_decisions.md): additionalContext, не banner.
#
# Throttle: state/docs-family-fired-<SID>.jsonl — per-session, ключ = md5(missing).
# Тот же набор отсутствующих docs не fired дважды; новый diff → новый fire.

set -uo pipefail

# Детект коммита — по ИСПОЛНЯЕМОЙ части команды (single source — command-scope-lib.sh):
# `git commit` в кавычках или в теле heredoc — текст, а не команда.
SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
[ -f "$SCOPE_LIB" ] || SCOPE_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
if [ -f "$SCOPE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$SCOPE_LIB"
else
    is_git_commit() { grep -qE 'git[[:space:]]+commit' <<< "${1:-}"; }
fi

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

# Shared per-session throttle (single source — see throttle-lib.sh).
THROTTLE_LIB="${THROTTLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/throttle-lib.sh}"
if [ -f "$THROTTLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$THROTTLE_LIB"
else
    echo "Missing throttle-lib.sh: $THROTTLE_LIB" >&2; exit 1
fi

# Shared hash helper (single source — see hash-lib.sh).
HASH_LIB="${HASH_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hash-lib.sh}"
if [ -f "$HASH_LIB" ]; then
    # shellcheck source=/dev/null
    source "$HASH_LIB"
else
    echo "Missing hash-lib.sh: $HASH_LIB" >&2; exit 1
fi
DEFAULT_FAMILY="docs/architecture.md PLAN.md README.md CHANGELOG.md CLAUDE.md"
DOCS_FAMILY="${DOCS_FAMILY_LIST:-$DEFAULT_FAMILY}"

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

is_git_commit "$COMMAND" || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# git repo check (directory .git/ or gitlink .git file)
[ -e "$CWD/.git" ] || exit 0

# Staged file list (paths relative to repo root).
#
# Индекс читается ДО того, как отработает `git add` из той же составной команды. При вызове
# `git add -A && git commit -m ...` одной строкой хук видит состояние индекса ДО добавления
# и объявляет отсутствующими файлы, которые в коммит попадут — так он ложно загорелся на
# релизе v1.14.1, где все пять документов семьи были обновлены и вошли в коммит.
# Поэтому к индексу добавляется рабочее дерево: файл, изменённый но ещё не добавленный,
# считается кандидатом в коммит. Ошибка уходит в сторону молчания, а не ложной тревоги.
#
# `core.quotepath=false` обязателен: без него git отдаёт имена вне ASCII в кавычках с
# восьмеричными escape, и ни один фильтр путей ниже их не узнаёт. Повод был живой: два
# скилла из двадцати трёх звались кириллицей и были источниками автотаблиц, которые путь
# A2 обязан видеть. Тот же дефект чинили 22-23.08 в трёх соседних стражах, сюда правка
# не дошла — пять стражей лечили симптом по одному, и ни один не спросил, откуда берётся
# не-ASCII путь. Брался он из правила именования скиллов; 28.08.2026 правило переписали,
# скиллы переименовали (`adversary`, `grilling`), класс дефекта закрыт в корне.
# Строка остаётся страховкой на пути с пробелами и спецсимволами.
STAGED=$(
    { git -C "$CWD" -c core.quotepath=false diff --cached --name-only 2>/dev/null
      git -C "$CWD" -c core.quotepath=false diff --name-only 2>/dev/null
    } | sed 's/^"//; s/"$//' | sort -u
)
[ -z "$STAGED" ] && exit 0

# Version bump detection: added line (starts with '+' not '+++') matching vX.Y[.Z][-suffix].
# Версией считается только то, что меняется в СВОИХ носителях версии — `VERSION`,
# заголовок релиза в `CHANGELOG.md`, строка версии в `README`/`PLAN`. Прежде подходила
# любая тройка чисел в любой добавленной строке, включая версию ЧУЖОГО пакета
# в комментарии: страж требовал обновить пять документов проекта из-за упоминания
# `mcp` 2.0.0. Это тот же класс, что чинили в v1.14.1 у стражей: совпадение с текстом
# вместо совпадения со смыслом.
DIFF=$(git -C "$CWD" diff --cached -- VERSION CHANGELOG.md README.md README.ru.md PLAN.md 2>/dev/null)
[ -z "$DIFF" ] && DIFF=$(git -C "$CWD" diff -- VERSION CHANGELOG.md README.md README.ru.md PLAN.md 2>/dev/null)
#
# Третья поправка того же класса (2026-08-21). Прежде маркером считалась любая версия
# в ДОБАВЛЕННОЙ строке-носителе — без сверки с удалённой. Строка
# `**Current version:** v1.27.0 — 49 active hooks` после работы генератора стала
# `… — 50 active hooks`: номер версии не менялся, менялось число рядом, а страж
# потребовал обновить пять документов под релиз, которого не было.
#
# «Строка с версией изменилась» — не то же, что «версия изменилась». Различает их
# только сравнение с удалёнными строками: бампом считается номер, которого в них нет.
# Новый файл минус-строк не имеет вовсе — там первое появление версии и есть релиз.
_version_lines() {   # $1 — знак диффа (+ или -)
    printf '%s' "$DIFF" \
        | grep -E "^[$1][^$1]" \
        | grep -E "^[$1](v?[0-9]+\.[0-9]+|## \[|\*\*Current version|\| Текущая версия)" \
        | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9]+)?' \
        | sed 's/^v//' \
        | sort -u
}
ADDED_VERSIONS=$(_version_lines '+')
REMOVED_VERSIONS=$(_version_lines '-')

VERSION_MARKER=""
for _v in $ADDED_VERSIONS; do
    grep -Fxq "$_v" <<< "$REMOVED_VERSIONS" && continue
    VERSION_MARKER="v$_v"
    break
done
MISSING=""
append_missing() {
    local item="$1"
    if [ -z "$MISSING" ]; then MISSING="$item"
    else MISSING="$MISSING, $item"; fi
}

# Автогенерируемые таблицы не разошлись с исходниками: регенерируем во временную
# копию и сравниваем. Guarded — генератора в чужом проекте нет, а хук стоит и там.
# Зовётся из двух путей: на бампе версии (A) и на правке источников таблиц (A2).
check_generated_tables() {
    local GEN="$CWD/scripts/regen-readme-skills.sh"
    [ -f "$GEN" ] || return 0
    local doc _tmpd _docs
    # Документы с автотаблицами НАХОДЯТСЯ по маркеру, а не перечисляются: до 30 августа
    # 2026 список был `README.md README.ru.md`, а таблица хуков к тому времени жила в
    # docs/reference.md и docs/reference.ru.md — страж молчал на устаревшей таблице, потому
    # что смотрел не в тот носитель (D212; тот же класс, что D105). Ищется по отслеживаемым
    # файлам, чтобы черновик вне git не судился; без git — по дереву.
    _docs=$(git -C "$CWD" grep -l -e 'HOOKS-TABLE:START' -e 'SKILLS-TABLE:START' -- '*.md' 2>/dev/null \
            || grep -rl -e 'HOOKS-TABLE:START' -e 'SKILLS-TABLE:START' --include='*.md' "$CWD" 2>/dev/null | sed "s#^$CWD/##")
    for doc in $_docs; do
        [ -f "$CWD/$doc" ] || continue
        _tmpd=$(mktemp -d 2>/dev/null) || continue
        # Сравнивается то, что УЙДЁТ В КОММИТ, а не рабочее дерево. Иначе достаточно
        # запустить генератор и не добавить README: страж копировал свежий рабочий файл,
        # гонял генератор по копии, сравнивал сам с собой — совпадение, молчание, а в
        # коммит уезжали новый источник и старая таблица.
        mkdir -p "$_tmpd/$(dirname "$doc")" 2>/dev/null
        if ! git -C "$CWD" show ":$doc" > "$_tmpd/$doc" 2>/dev/null; then
            cp "$CWD/$doc" "$_tmpd/$doc" 2>/dev/null   # не в индексе — судим по дереву
            cp "$CWD/$doc" "$_tmpd/base" 2>/dev/null
        else
            cp "$_tmpd/$doc" "$_tmpd/base" 2>/dev/null
        fi
        README_FILE="$_tmpd/$doc" bash "$GEN" "$CWD" >/dev/null 2>&1 || true
        cmp -s "$_tmpd/$doc" "$_tmpd/base" || \
            append_missing "$doc (автотаблицы устарели — bash scripts/regen-readme-skills.sh)"
        rm -rf "$_tmpd" 2>/dev/null
    done
}

# ── Path A: version bump → полное покрытие docs-family (5 docs). ──────────────
if [ -n "$VERSION_MARKER" ]; then
    # Compute missing: docs-family members that exist in repo but aren't staged.
    for doc in $DOCS_FAMILY; do
        [ -f "$CWD/$doc" ] || continue
        grep -Fxq "$doc" <<< "$STAGED" && continue
        append_missing "$doc"
    done

    # ── Проверка СОДЕРЖАНИЯ, а не только присутствия (v1.12.2) ────────────────
    #
    # Присутствие файла в коммите ничего не доказывает. Живой пример: релиз v1.12.1
    # прошёл этот страж молча, потому что оба README были в diff — а изменена в них
    # была одна строка с номером версии. При этом Roadmap обрывался на v1.7.0,
    # таблица хуков в английском README отстала до 14 записей из 37 и рекламировала
    # уже исправленный дефект, а сам английский README вообще не имел меток
    # генератора и не обновлялся ни разу. Страж молчал, и на его молчание сослались.
    #
    # Три дешёвые проверки содержания. Все guarded: хук стоит и в чужих проектах,
    # где ни генератора, ни этих файлов нет.
    VER_PLAIN="${VERSION_MARKER#v}"

    # 1. Номер выпускаемой версии реально присутствует в документе.
    #
    # Правило самонастраивающееся, потому что хук стоит и в чужих проектах: спрашиваем
    # только с тех файлов, которые УЖЕ вели версии. Если в прошлой ревизии документа был
    # хоть один маркер vX.Y.Z — значит документ версии отслеживает, и новая обязана в нём
    # появиться. Если не вёл никогда — молчим, это не наш жанр документа.
    #
    # Первая версия проверки (v1.12.2) спрашивала только с README, и этого оказалось мало:
    # PLAN.md и docs/architecture.md проходили с любой мелкой правкой при версии
    # позапрошлого релиза. Проверено фикстурой, не рассуждением — контрольный случай
    # показал, что страж на том же дереве загорается, когда файла нет вовсе.
    for doc in $DOCS_FAMILY; do
        [ -f "$CWD/$doc" ] || continue
        # Только те, что уже в коммите: об отсутствующих сказано выше.
        grep -Fxq "$doc" <<< "$STAGED" || continue
        # Документ вёл версии раньше?
        grep -qE 'v?[0-9]+\.[0-9]+\.[0-9]+' \
            <<< "$(git -C "$CWD" show "HEAD:$doc" 2>/dev/null)" || continue
        grep -Fq "$VER_PLAIN" "$CWD/$doc" && continue
        append_missing "$doc (нет упоминания $VERSION_MARKER)"
    done

    # 2. Автогенерируемые таблицы не разошлись с исходниками.
    check_generated_tables

    # 3. Числа документов совпадают с миром — по реестру утверждений (30 августа 2026).
    # Релиз v1.31.0 прошёл этот страж с README, где 176 находок при 185, 52 хука при 54,
    # «пять хуков» при девяти: страж проверял форму (версия, таблицы), правду чисел — никто.
    # Guarded: реестра в чужом проекте нет.
    if [ -f "$CWD/scripts/docs-refresh-claims.sh" ] && [ -f "$CWD/scripts/doc-claims.tsv" ]; then
        _claims_out=$(cd "$CWD" && bash scripts/docs-refresh-claims.sh --check 2>/dev/null); _claims_rc=$?
        if [ "$_claims_rc" -ne 0 ]; then
            _claims_n=$(printf '%s\n' "$_claims_out" | grep -c '^  · ')
            append_missing "числа документов разошлись с миром: ${_claims_n} (bash scripts/docs-refresh-claims.sh run)"
        fi
    fi

    [ -z "$MISSING" ] && exit 0

    # Per-session throttle by hash of missing-set.
    MISSING_HASH=$(hash_value "$MISSING")
    THROTTLE_FILE=$(throttle_file "$STATE_DIR" docs-family "$SESSION_ID")
    _RC_LIB="${RC_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/root-cause-lib.sh}"
    [ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
    # shellcheck source=/dev/null
    [ -f "$_RC_LIB" ] && . "$_RC_LIB"
    if throttle_seen "$THROTTLE_FILE" "$MISSING_HASH"; then
        # Признак совпал, страж промолчал по троттлу — знаменатель (D205).
        command -v rc_note_detection >/dev/null 2>&1 && \
            rc_note_detection "$STATE_DIR" "$SESSION_ID" "docs-family-check" "muted"
        exit 0
    fi
    throttle_mark "$THROTTLE_FILE" "$MISSING_HASH" "$(printf '"marker":"%s"' "$VERSION_MARKER")"
    command -v rc_note_detection >/dev/null 2>&1 && \
        rc_note_detection "$STATE_DIR" "$SESSION_ID" "docs-family-check" "said"

    CONTEXT=$(printf '🛑 Docs family drift: staged diff содержит version bump (%s). Проблемы:\n  %s\n\nПравило: «обнови документацию = все docs» (architecture + PLAN + CHANGELOG + README + project CLAUDE.md).\nЗакрывает case-2026-04-23-memory-without-action-gate (memory без action-gate).\nБез скобок — файла нет в diff. В скобках — файл в diff, но содержание отстало:\nприсутствие файла в коммите ничего не доказывает, на этом страж молчал в v1.12.1.' \
        "$VERSION_MARKER" "$MISSING")

    jq -n --arg ctx "$CONTEXT" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }'
    exit 0
fi

# ── Path A2: изменены ИСТОЧНИКИ автотаблиц — сверить таблицы, версия ни при чём ─
#
# Прежде этот контроль жил только внутри Path A и потому работал раз в релиз.
# Коммит 771e7fc (21.08) внёс расхождение рядовой правкой шапки хука: генератор
# берёт из шапки ТОЛЬКО строку 2, а описание там было разбито надвое. Бампа версии
# в коммите не было — страж промолчал, расхождение прожило сутки и вскрылось
# случайно, регенерацией по другому поводу.
#
# Таблицы расходятся, когда меняются их источники, а не когда выпускают релиз.
# Гейт по источникам, а не «на каждом коммите»: иначе страж горел бы подряд на
# каждой посторонней правке, пока кто-нибудь не запустит генератор.
TABLE_SOURCES=$(printf '%s\n' "$STAGED" \
    | grep -E '^hooks/[^/]+\.sh$|^skills/[^/]+/SKILL\.md$|^README(\.ru)?\.md$')
if [ -n "$TABLE_SOURCES" ]; then
    MISSING=""
    check_generated_tables
    if [ -n "$MISSING" ]; then
        TABLES_HASH=$(hash_value "$MISSING")
        THROTTLE_FILE=$(throttle_file "$STATE_DIR" docs-family-tables "$SESSION_ID")
        if ! throttle_seen "$THROTTLE_FILE" "$TABLES_HASH"; then
            throttle_mark "$THROTTLE_FILE" "$TABLES_HASH" '"path":"A2"'
            CONTEXT=$(printf '📝 Автотаблицы разошлись с источниками:\n  %s\n\nВ коммите изменены файлы, из которых таблицы генерируются, а сами таблицы отстали.\nПрежде это ловилось только на бампе версии — расхождение из 771e7fc так и прожило сутки.' \
                "$MISSING")
            jq -n --arg ctx "$CONTEXT" '{
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    additionalContext: $ctx
                }
            }'
            exit 0
        fi
    fi
fi

# ── Path B: нет version bump, но изменён код в документированном домене ────────
#    (schema.prisma / *-service.ts / route.ts) — а документация НЕ тронута.
#    Закрывает щель: рядовые feat/fix уезжали без обновления доков → docs drift на
#    релизы (единственный прежний гейт — Path A — ловил только commit с бампом версии).
CODE_TOUCHED=$(printf '%s\n' "$STAGED" \
    | grep -E '^web/prisma/schema\.prisma$|^web/lib/[^/]+-service\.ts$|^web/app/api/.*/route\.ts$')
[ -z "$CODE_TOUCHED" ] && exit 0

# Любой модульный док / docs-family в staged снимает флаг (документация учтена).
DOC_TOUCHED=$(printf '%s\n' "$STAGED" \
    | grep -E '^(CHANGELOG|PLAN|README|CLAUDE)\.md$|^docs/architecture\.md$|^\.claude-docs/modules/.*\.md$')
[ -n "$DOC_TOUCHED" ] && exit 0

# Отдельный throttle-ключ от Path A; хэш по набору изменённого кода.
CODE_HASH=$(hash_value "$CODE_TOUCHED")
THROTTLE_FILE=$(throttle_file "$STATE_DIR" docs-family-code "$SESSION_ID")
if throttle_seen "$THROTTLE_FILE" "$CODE_HASH"; then
    exit 0
fi
throttle_mark "$THROTTLE_FILE" "$CODE_HASH" "$(printf '"code_files":%d' "$(printf '%s\n' "$CODE_TOUCHED" | grep -c .)")"

CODE_LIST=$(printf '%s' "$CODE_TOUCHED" | head -6 | tr '\n' ' ')
CONTEXT=$(printf '📝 Doc drift: изменён код в документированном домене, но документация НЕ в staged:\n  %s\n\nПравило §8.4: изменение схемы/сервиса/роута → обнови соответствующий модуль (.claude-docs/modules/) и/или CHANGELOG/PLAN/architecture, либо явно подтверди, что доки не требуют правки.\nЗакрывает щель, из-за которой рядовые feat/fix уезжали без доков (case-2026-07-07-doc-counters-rot-generate-from-source).' \
    "$CODE_LIST")

jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'

exit 0
