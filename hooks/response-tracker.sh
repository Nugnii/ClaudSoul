#!/usr/bin/env bash
# response-tracker.sh — PostToolUse: пишет РЕАКЦИЮ агента после того, как система
# en: PostToolUse: records the agent's REACTION after the system warned it about something.
# его о чём-то предупредила.
#
# Зачем. Все остальные логи фиксируют стимул: сработал блокер, инжектнулось знание,
# юзер поправил. Ни один не фиксирует, что агент сделал следующим ходом — архитектура
# признаёт это формулой «детект ≠ комплаенс». Без зависимой переменной вопрос «правило
# меняет поведение или нет» неотвечаем: есть только частота попадания в ситуацию.
#
# Восстановить реакцию из транскриптов можно (см. backfill-compliance.sh), но
# транскрипты живут ограниченное время — 78% событий из логов уже невосстановимы.
# Поэтому пишем онлайн: потолок снимается навсегда.
#
# Дёшево по конструкции: пока в сессии не было ни одного маркера — выходим по двум
# `[ -f ]`, без jq и без записи. Пишем только после первого стимула.
#
# Формат строки: {"ts","sid","tool","file","after"}
#   after — что уже сработало в этой сессии: blocker | knowledge | both
#
# Input: JSON на stdin (PostToolUse). Output: ничего (silent).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

SID=$(resolve_session_id "$INPUT" "" 2>/dev/null || true)
SID="${SID:-${CLAUDE_CODE_SESSION_ID:-$PPID}}"

# --- Гейт: был ли в этой сессии стимул? Два теста файла, дальше не идём. ---
BLOCKER_LOG="$STATE_DIR/blocker-fired-${SID}.jsonl"
KNOWLEDGE_GATE="$STATE_DIR/knowledge_injected_${SID}"
HAS_BLOCKER=false
HAS_KNOWLEDGE=false
[ -s "$BLOCKER_LOG" ] && HAS_BLOCKER=true
[ -f "$KNOWLEDGE_GATE" ] && HAS_KNOWLEDGE=true
if [ "$HAS_BLOCKER" = false ] && [ "$HAS_KNOWLEDGE" = false ]; then
    exit 0
fi

AFTER="knowledge"
if [ "$HAS_BLOCKER" = true ] && [ "$HAS_KNOWLEDGE" = true ]; then AFTER="both"
elif [ "$HAS_BLOCKER" = true ]; then AFTER="blocker"; fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
[ -n "$TOOL" ] || exit 0
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)

# Сборка через jq: пути содержат пробелы и кавычки, printf рождал бы битые строки
# (ровно то, на чём три месяца врал injection-log).
jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$SID" \
       --arg tool "$TOOL" --arg file "$FILE" --arg after "$AFTER" \
   '{ts: $ts, sid: $sid, tool: $tool, file: $file, after: $after}' \
   >> "$STATE_DIR/response-${SID}.jsonl" 2>/dev/null || true

exit 0
