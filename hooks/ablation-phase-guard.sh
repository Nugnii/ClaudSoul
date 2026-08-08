#!/usr/bin/env bash
# ablation-phase-guard.sh — фаза замера видима и защищена механически (§6).
# en: while a measurement phase is active, injects a per-session signal and
# guards the installed policy surface from deploys; nobody has to remember.
#
# Родился из вопроса собеседника «мне постоянно нужно помнить, идёт фаза или
# нет?» — по principle-knowledge-in-the-world помнить не должен никто: маркер
# active-phase.json (пишет freeze-policy, снимает phase.sh close) — источник
# истины; этот хук его читает на двух событиях:
#   UserPromptSubmit — раз в сессию: «фаза X активна, правила §6»;
#   PreToolUse (Bash|Edit|Write) — каждый раз: попытка деплоя в УСТАНОВЛЕННУЮ
#   policy (~/.claude/hooks, settings.json, CLAUDE.md, install.sh) во время
#   фазы получает стоп-сигнал. Разработка в репозитории свободна (§6:
#   разрабатывать можно постоянно, активировать — между фазами).
#
# Ограничение названо: Bash-детект ловит классы cp/mv/rm/ln/tee/install.sh —
# экзотический redirect в установленное может пройти мимо; страж — тормоз
# от бытовой инерции, не санкция.
set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
THROTTLE_LIB="${THROTTLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/throttle-lib.sh}"
[ -f "$THROTTLE_LIB" ] || THROTTLE_LIB="$HOME/.claude/hooks/throttle-lib.sh"
[ -f "$THROTTLE_LIB" ] && source "$THROTTLE_LIB"

command -v jq >/dev/null 2>&1 || exit 0

MARKER="${ABLATION_DIR:-$HOME/.claude/ablation}/active-phase.json"
[ -f "$MARKER" ] || exit 0
PHASE=$(jq -r '.phase // "?"' "$MARKER" 2>/dev/null)
SINCE=$(jq -r '.since // "?"' "$MARKER" 2>/dev/null)

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

inject() {
    printf '%s' "$1" | jq -Rs --arg ev "$2" \
        '{hookSpecificOutput: {hookEventName: $ev, additionalContext: .}}'
    exit 0
}

if [ -z "$TOOL" ]; then
    # UserPromptSubmit: сигнал раз в сессию. Содержимое динамическое: обязанность
    # регистрации (протокол §3: запрос регистрируется ДО первого действия) и
    # авто-проверка условия остановки (§13: 20 в очереди либо 8 недель) — обе
    # обязанности сняты с памяти агента механизмом (та же норма, что для владельца).
    [ -n "$SESSION_ID" ] || exit 0
    if command -v throttle_file >/dev/null 2>&1; then
        TF=$(throttle_file "$STATE_DIR" ablation-phase "$SESSION_ID")
        throttle_seen "$TF" session && exit 0
        throttle_mark "$TF" session
    fi
    MSG="🧪 Фаза ablation «${PHASE}» активна (с ${SINCE}). Правила §6: подключать хуки/скиллы, менять activation/пороги/инъекции/MCP — ЗАПРЕЩЕНО до конца фазы; разработка в ветке свободна; база знаний живёт. Закрытие: scripts/ablation/phase.sh close ${PHASE}."

    J="${ABLATION_DIR:-$HOME/.claude/ablation}/journal.jsonl"
    if [ -f "$J" ]; then
        TODAY=$(date -u '+%Y-%m-%d')
        REG_TODAY=$(jq -s --arg d "$TODAY" \
            '[.[] | select(.e=="register" and (.ts | startswith($d)))] | length' "$J" 2>/dev/null || echo 0)
        [ "${REG_TODAY:-0}" -eq 0 ] && MSG="$MSG
⚠ Регистраций сегодня нет — рабочий запрос регистрируется ДО первого действия (§3): scripts/ablation/journal.sh register \"<текст запроса>\"."
        # Условие остановки: константы протокола (§13), не настройки.
        STOP=$(jq -s --arg since "$SINCE" '
            [.[] | select(.e=="queue")] as $q
            | ($q | length) as $n
            | (if $n > 0 then ($q[0].ts | fromdateiso8601) else null end) as $first
            | if $n >= 20 then "очередь \($n) >= 20 задач"
              elif ($first != null and (now - $first) > 4838400) then "8 недель с первой принятой"
              else empty end' "$J" 2>/dev/null | head -1)
        [ -n "$STOP" ] && [ "$STOP" != "null" ] && MSG="$MSG
⏰ Условие закрытия enrollment ДОСТИГНУТО (${STOP}): решение о закрытии — scripts/ablation/phase.sh close ${PHASE}."
    else
        MSG="$MSG
⚠ Журнал задач пуст — рабочий запрос регистрируется ДО первого действия (§3): scripts/ablation/journal.sh register \"<текст запроса>\"."
    fi
    inject "$MSG" "UserPromptSubmit"
fi

# PreToolUse: деплой в установленную policy во время фазы.
DEPLOY_RE="\.claude/(hooks/|settings\.json|CLAUDE\.md)"
case "$TOOL" in
Edit|Write|MultiEdit)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    printf '%s' "$FILE" | grep -qE "^$HOME/$DEPLOY_RE" || exit 0
    ;;
Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    printf '%s' "$CMD" | grep -qE "(cp|mv|rm|ln|tee)[^|;&]*$DEPLOY_RE|install\.sh" || exit 0
    ;;
*)  exit 0 ;;
esac

inject "🧪 СТОП: идёт фаза ablation «${PHASE}» — деплой в установленную policy запрещён до конца фазы (§6): изменение попадёт в снимки будущих пар и испортит treatment. Правку — в ветку (активация после фазы). Критический дефект → amendment-процедура (§6: стоп enrollment → фиксация пар → исправление → новая фаза). Осознанное закрытие фазы: scripts/ablation/phase.sh close ${PHASE}." "PreToolUse"
