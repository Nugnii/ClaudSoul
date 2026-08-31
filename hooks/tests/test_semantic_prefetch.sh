#!/usr/bin/env bash
# test_semantic_prefetch.sh — фоновый предкэш пишет кэш, деградирует молча, fallback его читает.
# en: semantic prefetch writes cache in background, degrades silently, fallback consumes it.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/semantic-prefetch.sh"
LIB="$HOOKS_DIR/knowledge-semantic-fallback-lib.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Стаб MCP: настоящий venv-python не нужен — важен контракт (stdout = JSON-массив).
ROOT="$TMP/root"; mkdir -p "$ROOT/mcp-server/.venv/bin"
touch "$ROOT/mcp-server/cli_search.py"
cat > "$ROOT/mcp-server/.venv/bin/python" << 'PY'
#!/bin/sh
echo '[{"file_path":"/x/pattern-sem.md","name":"sem","type":"pattern","confidence":4,"impact":4}]'
PY
chmod +x "$ROOT/mcp-server/.venv/bin/python"

run() { # $1 sid, $2 env-довесок
    printf '{"session_id":"%s","prompt":"тема запроса","cwd":"%s"}' "$1" "$TMP" \
      | env CLAUDSOUL_ROOT="$ROOT" STATE_DIR="$TMP/state" ${2:-} bash "$HOOK" 2>&1
    printf 'rc=%s' "$?"
}

# --- T1: кэш появляется фоном; сам хук молчит и выходит нулём ---
OUT=$(run ps1)
grep -q 'rc=0' <<< "$OUT" && [ "$(printf '%s' "$OUT" | grep -vc 'rc=0')" = "0" ] \
    && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1 тихий выход]: $OUT"; }
CACHE="$TMP/state/semantic-prefetch-ps1.json"
_i=0; while [ $_i -lt 30 ] && [ ! -s "$CACHE" ]; do sleep 0.1; _i=$((_i+1)); done
grep -q 'pattern-sem' "$CACHE" 2>/dev/null && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T2 кэш]: $(ls "$TMP/state" 2>/dev/null)"; }

# --- T3: SKIP_MCP_FALLBACK=1 → кэша нет ---
run ps3 "SKIP_MCP_FALLBACK=1" >/dev/null
sleep 0.3
[ -f "$TMP/state/semantic-prefetch-ps3.json" ] \
    && { FAIL=$((FAIL+1)); echo "FAIL [T3 выключатель]"; } || PASS=$((PASS+1))

# --- T4: без venv — тихая деградация ---
OUT=$(printf '{"session_id":"ps4","prompt":"x","cwd":"/"}' \
      | env CLAUDSOUL_ROOT="$TMP/novenv" STATE_DIR="$TMP/state" bash "$HOOK" 2>&1; printf 'rc=%s' "$?")
grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4]: $OUT"; }

# --- T4b: хук синхронно оставил маркер реплики рядом с кэшем (D234) ---
[ -f "$CACHE.prompt" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T4b маркер реплики не создан]"; }

# --- T5: fallback читает кэш, записанный ПОСЛЕ маркера этой реплики (без venv) ---
# Маркер уводится в прошлое явно: фон стаба пишет кэш в ту же секунду, что и маркер,
# а посекундный -nt bash 3.2 в этой ситуации счёл бы кэш несвежим.
OLD_TS=$(date -v-20M '+%Y%m%d%H%M' 2>/dev/null || date -d '20 minutes ago' '+%Y%m%d%H%M' 2>/dev/null)
touch -t "${OLD_TS}" "$CACHE.prompt" 2>/dev/null
# shellcheck source=/dev/null
source "$LIB"
ROWS=$(mcp_semantic_fallback "$TMP/novenv" "запрос" 0 0 "" "$CACHE")
grep -q '^99|pattern-sem.md|' <<< "$ROWS" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T5 чтение кэша]: '$ROWS'"; }

# --- T6: пришла новая реплика (маркер моложе кэша) → кэш протух, пусто, не мусор.
# Минуты не важны: свежесть событийная, а не TTL.
touch "$CACHE.prompt"
ROWS=$(mcp_semantic_fallback "$TMP/novenv" "запрос" 0 0 "" "$CACHE")
[ -z "$ROWS" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6 новая реплика]: '$ROWS'"; }

# --- T7: кэш без маркера (предкэш не запускался) → протух, синхронный путь ---
rm -f "$CACHE.prompt"
ROWS=$(mcp_semantic_fallback "$TMP/novenv" "запрос" 0 0 "" "$CACHE")
[ -z "$ROWS" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7 без маркера]: '$ROWS'"; }

echo "semantic-prefetch: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
