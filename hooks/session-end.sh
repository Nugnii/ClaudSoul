#!/usr/bin/env bash
# session-end.sh — SessionEnd: финализирует сессию в registry при завершении (exit/clear/logout), снимает запись из active/.
# en: SessionEnd: finalises the session in the registry on exit/clear/logout and removes it from active/.
# Fires when a Claude Code session ends. Complements session-collector.sh (Stop):
# Stop fires only after a completed assistant turn, so sessions that never
# conversed (restored VS Code windows, abandoned tabs) stayed registered in
# active/ until the 24h TTL. SessionEnd closes them immediately on clean exit.
#
# Input: JSON on stdin from Claude Code (SessionEnd event)
#   { "session_id": "<uuid>", "reason": "clear|logout|prompt_input_exit|other",
#     "cwd": "<path>", "hook_event_name": "SessionEnd" }
# Output: empty (finalization is silent)

set -euo pipefail

INPUT="$(cat)"

# Resolve stable session_id from payload (UUID) — must match the id used by
# session-start/knowledge-activator at registration, so finalize hits the
# same active/{session_id}.json record.
PAYLOAD_SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$PAYLOAD_SID" ]; then
    export SR_OVERRIDE_SESSION_ID="$PAYLOAD_SID"
fi

# CWD from payload — registry uses it to resolve project name
PAYLOAD_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [ -n "$PAYLOAD_CWD" ] && [ -d "$PAYLOAD_CWD" ]; then
    cd "$PAYLOAD_CWD" || true
fi

# Библиотека ищется СНАЧАЛА рядом с собой, и лишь потом в установленном каталоге.
# Прежде стоял только установленный путь, и на машине без ClaudSoul хук молча
# выходил целиком. Тесты этого не видели: они шли на машине, где установка есть,
# то есть проверяли установленную копию, а не репозиторий.
REGISTRY_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/session-registry-lib.sh"
[ -f "$REGISTRY_LIB" ] || REGISTRY_LIB="$HOME/.claude/hooks/session-registry-lib.sh"
if [ -f "$REGISTRY_LIB" ]; then
    # shellcheck disable=SC1090
    source "$REGISTRY_LIB"
    # No-op if Stop already finalized this session (active file gone) —
    # sr_finalize_session returns 0 when the record is absent.
    sr_finalize_session "" 2>/dev/null || true
fi

exit 0
