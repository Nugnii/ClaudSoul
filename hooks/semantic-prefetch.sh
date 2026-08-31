#!/usr/bin/env bash
# semantic-prefetch.sh — UserPromptSubmit: фоновый предкэш семантического поиска по теме реплики.
# en: UserPromptSubmit: background semantic-search prefetch keyed by the prompt topic and cwd.
#
# Дизайн из docs/architecture.md (эволюция MCP-fallback → hybrid): keyword quick-hit +
# MCP background prefetch по cwd+topic. Семантическая дверь активатора открывается на
# PreToolUse, где embedding-задержка платится синхронно; здесь тот же запрос уходит
# ФОНОМ на реплике собеседника, и к моменту вызова инструмента ответ уже лежит в
# state/semantic-prefetch-<SID>.json — fallback читает кэш, предзагруженный для ТЕКУЩЕЙ
# реплики (маркер .prompt, D234: свежесть событийная, не TTL), синхронный вызов
# остаётся запасным путём.
#
# ФОН С ПОЛНОЙ РАЗВЯЗКОЙ ДЕСКРИПТОРОВ — единственный фоновый процесс в hooks/, образца
# не было (стресс-тест плана): унаследованный stdout держал бы UserPromptSubmit открытым
# до конца MCP-вызова, и «фон» молча стал бы синхронной задержкой хода. Поэтому
# </dev/null, вывод в tmp-файл, atomic mv, timeout.
#
# Silent degradation: нет jq / venv / реплики — exit 0 без вывода и без процесса.

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
: "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"

command -v jq >/dev/null 2>&1 || exit 0
[ "${SKIP_MCP_FALLBACK:-0}" = "1" ] && exit 0

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null | head -c 300)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$SID" ] && [ -n "$PROMPT" ] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
CACHE="$STATE_DIR/semantic-prefetch-${SID}.json"

# Маркер реплики (D234): свежесть кэша меряется РЕПЛИКАМИ, не минутами — тема меняется
# ходом диалога, и кэш прошлой реплики может нести прошлую тему независимо от того,
# сколько минут она шла. Маркер трогается синхронно на КАЖДОМ UserPromptSubmit (до
# проверки venv: пропадёт venv — маркер всё равно объявит старый кэш протухшим);
# fallback считает кэш живым, только если тот записан ПОЗЖЕ маркера, то есть
# предзагружен для текущей реплики.
touch "$CACHE.prompt" 2>/dev/null || true

PY="$CLAUDSOUL_ROOT/mcp-server/.venv/bin/python"
CLI="$CLAUDSOUL_ROOT/mcp-server/cli_search.py"
[ -x "$PY" ] && [ -f "$CLI" ] || exit 0

TO=""
if command -v timeout >/dev/null 2>&1; then TO="timeout 10"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout 10"; fi
QUERY="$PROMPT $(basename "${CWD:-/}")"

(
    cd "$CLAUDSOUL_ROOT/mcp-server" 2>/dev/null || exit 0
    $TO "$PY" cli_search.py "$QUERY" 5 2 > "$CACHE.tmp" 2>/dev/null \
        && mv "$CACHE.tmp" "$CACHE" 2>/dev/null \
        || rm -f "$CACHE.tmp" 2>/dev/null
) </dev/null >/dev/null 2>&1 &

exit 0
