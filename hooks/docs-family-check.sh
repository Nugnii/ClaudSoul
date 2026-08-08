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

# Match "git commit" as distinct command invocation.
# Covers: start-of-line, after space/semicolon/&&/pipe/backtick.
echo "$COMMAND" | grep -qE '(^|[[:space:]]|;|&|\||\$\()git[[:space:]]+commit([[:space:]]|$)' || exit 0

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
STAGED=$(
    { git -C "$CWD" diff --cached --name-only 2>/dev/null
      git -C "$CWD" diff --name-only 2>/dev/null
    } | sort -u
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
VERSION_MARKER=$(printf '%s' "$DIFF" \
    | grep -E '^\+[^+]' \
    | grep -E '^\+(v?[0-9]+\.[0-9]+|## \[|\*\*Current version|\| Текущая версия)' \
    | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9]+)?' \
    | head -1)
# ── Path A: version bump → полное покрытие docs-family (5 docs). ──────────────
if [ -n "$VERSION_MARKER" ]; then
    # Compute missing: docs-family members that exist in repo but aren't staged.
    MISSING=""
    append_missing() {
        local item="$1"
        if [ -z "$MISSING" ]; then MISSING="$item"
        else MISSING="$MISSING, $item"; fi
    }
    for doc in $DOCS_FAMILY; do
        [ -f "$CWD/$doc" ] || continue
        echo "$STAGED" | grep -Fxq "$doc" && continue
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
        echo "$STAGED" | grep -Fxq "$doc" || continue
        # Документ вёл версии раньше?
        git -C "$CWD" show "HEAD:$doc" 2>/dev/null \
            | grep -qE 'v?[0-9]+\.[0-9]+\.[0-9]+' || continue
        grep -Fq "$VER_PLAIN" "$CWD/$doc" && continue
        append_missing "$doc (нет упоминания $VERSION_MARKER)"
    done

    # 2. Автогенерируемые таблицы не разошлись с исходниками.
    GEN="$CWD/scripts/regen-readme-skills.sh"
    if [ -f "$GEN" ]; then
        for doc in README.md README.ru.md; do
            [ -f "$CWD/$doc" ] || continue
            grep -q 'HOOKS-TABLE:START\|SKILLS-TABLE:START' "$CWD/$doc" || continue
            _tmpd=$(mktemp -d 2>/dev/null) || continue
            cp "$CWD/$doc" "$_tmpd/$doc" 2>/dev/null
            README_FILE="$_tmpd/$doc" bash "$GEN" "$CWD" >/dev/null 2>&1 || true
            cmp -s "$_tmpd/$doc" "$CWD/$doc" || \
                append_missing "$doc (автотаблицы устарели — bash scripts/regen-readme-skills.sh)"
            rm -rf "$_tmpd" 2>/dev/null
        done
    fi

    [ -z "$MISSING" ] && exit 0

    # Per-session throttle by hash of missing-set.
    MISSING_HASH=$(hash_value "$MISSING")
    THROTTLE_FILE=$(throttle_file "$STATE_DIR" docs-family "$SESSION_ID")
    if throttle_seen "$THROTTLE_FILE" "$MISSING_HASH"; then
        exit 0
    fi
    throttle_mark "$THROTTLE_FILE" "$MISSING_HASH" "$(printf '"marker":"%s"' "$VERSION_MARKER")"

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
