#!/usr/bin/env bash
# knowledge-capture-reminder.sh — PostToolUse[Bash]: напоминает собрать материал в черновики базы знаний, когда за сессию накопилось N коммитов без захвата.
# en: PostToolUse[Bash]: reminds to collect material after N commits without a draft.
#
# Закрывает щель между двумя существующими триггерами захвата знаний:
#   error-tracker  (gated на retry: attempts >= 2)
#   session-collector (gated на Stop)
# Длинная УСПЕШНАЯ непрерывная сессия проваливается мимо обоих — знания теряются.
# Incident: за 18-коммитную сессию /project-health не захвачено ни одного знания,
# пока не указал пользователь (см. _drafts/session-2026-06-20-...; урок 1).
#
# Логика: считает `git commit` за сессию; на каждом окне THRESHOLD коммитов
# проверяет, появился ли новый черновик в _drafts/ с прошлой проверки
# (find -newer marker). Нет нового черновика → silent inject напоминания.
# Уровень 2 embedded-ness (механизм, не текстовое правило —
# principle-knowledge-in-the-world: правило, которое держится только памятью, не держится).
#
# Input  (stdin): {session_id, tool_name, tool_input} (PostToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
# Exit:  always 0 (degrade gracefully).

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
if [ -f "$PATHS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PATHS_LIB"
else
    : "${STATE_DIR:=$HOME/.claude/hooks/state}"
    : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"
fi

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
# Только реальные коммиты.
is_git_commit "$COMMAND" || exit 0

if command -v resolve_session_id >/dev/null 2>&1; then
    SID=$(resolve_session_id "$INPUT" "unknown" 2>/dev/null || echo unknown)
else
    SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)
fi
[ -z "$SID" ] && SID="unknown"

THRESHOLD="${KCR_THRESHOLD:-5}"
STATE="$STATE_DIR/knowledge-capture-${SID}"
MARKER="$STATE_DIR/knowledge-capture-marker-${SID}"
DRAFTS="$LESSONS_DIR/_drafts"

# Состояние: "count last_reminded"
count=0; last_reminded=0
if [ -f "$STATE" ]; then
    read -r count last_reminded < "$STATE" 2>/dev/null || { count=0; last_reminded=0; }
fi
case "$count" in ''|*[!0-9]*) count=0 ;; esac
case "$last_reminded" in ''|*[!0-9]*) last_reminded=0 ;; esac

count=$((count + 1))

# Точка отсчёта ставится на ПЕРВОМ засчитанном коммите сессии, а не при первой проверке
# окна. Иначе у первого окна нет базы для сравнения, и «новых записей нет» было бы
# утверждением из ничего — ровно то, что чинилось в этом же файле.
[ -f "$MARKER" ] || touch "$MARKER" 2>/dev/null

# Окно ещё не набрано с прошлого напоминания → просто сохранить счётчик.
if [ "$count" -lt "$THRESHOLD" ] || [ $((count - last_reminded)) -lt "$THRESHOLD" ]; then
    printf '%s %s\n' "$count" "$last_reminded" > "$STATE"
    exit 0
fi

# Окно достигнуто. Был ли захват знания с прошлой проверки (marker)?
#
# Считается ЛЮБАЯ новая запись знания, а не только черновик. Прежняя версия смотрела
# исключительно в `_drafts/`, и за сессию 2026-07-29 трижды сообщила «материал не захвачен»,
# когда в базу было записано три готовых кейса — прямо в `global-lessons/`, минуя черновики.
# Буквально верно, по существу нет: измерялась папка черновиков, а не захват. Черновик —
# один из путей записи, а не сам захват (тот же класс, что чинился весь тот день:
# детектор смотрит на прокси вместо предмета).
captured=false
if [ -f "$MARKER" ] && [ -d "$LESSONS_DIR" ]; then
    # Ответ берётся у подстановки, а не у конвейера. Прежняя форма
    # `find … | grep -q .` под `pipefail` возвращает 141: grep выходит по первой
    # строке, find получает SIGPIPE — и хук отвечает «ничего не захвачено» ровно
    # тогда, когда захвачено МНОГО (BACKLOG D50, механизм доказан замером в D59).
    for _pat in 'case-*.md' 'pattern-*.md' 'principle-*.md' 'entity-*.md' 'fact-*.md' 'relation-*.md'; do
        if [ -n "$(find "$LESSONS_DIR" -maxdepth 1 -name "$_pat" -newer "$MARKER" -print 2>/dev/null)" ]; then
            captured=true; break
        fi
    done
    if [ "$captured" = "false" ] && [ -d "$DRAFTS" ]; then
        [ -n "$(find "$DRAFTS" -name '*.md' -newer "$MARKER" -print 2>/dev/null)" ] && captured=true
    fi
fi

# Продвинуть окно и обновить marker в любом случае (это окно проверено).
printf '%s %s\n' "$count" "$count" > "$STATE"
touch "$MARKER" 2>/dev/null

[ "$captured" = "true" ] && exit 0      # захват был — не напоминаем

# Поручение сказать, а не статус — по той же причине, что в compile-reminder-lib.sh:
# замер 2026-08-21 показал 2 озвучивания на 45 приходов в контекст.
MSG="🧠 Захват знаний — СКАЖИ собеседнику одной строкой: за сессию ${count} коммитов, новых записей в базе знаний нет; накопился материал — записать кейс через /learn либо собрать в _drafts/, пока контекст свеж."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
