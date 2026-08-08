#!/usr/bin/env bash
# test_knowledge_activator.sh — характеризующий тест knowledge-activator.sh.
#
# Хук НЕ имел своего теста (988 строк, горячий путь L1→L2 broadcast). Этот тест
# фиксирует наблюдаемый контракт ПЕРЕД рефактором (разрез по слоям domain-graph /
# semantic-fallback / startup-context), чтобы рефактор не сломал поведение незаметно.
#
# Контролируемое окружение: фейковый HOME + минимальная global-lessons + фикс.
# CLAUDE_CODE_SESSION_ID (делает gate-файл детерминированным) → first-fire/cooldown
# воспроизводимы. cli_search / domains отсутствуют → graceful degradation (часть
# контракта). Ассерты — по сути (наличие секций, всплытие знания), не по форме.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/knowledge-activator.sh"
REPO_ROOT="$(cd "$HOOK_DIR/.." && pwd)"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if printf '%s' "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: не найдено '$needle'"
    fi
}

assert_empty() {
    local val="$1" label="$2"
    if [ -z "$val" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: ожидалось пусто, получено '${val:0:80}...'"
    fi
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: ожидалось '$expected', получено '$actual'"
    fi
}

setup_home() {
    rm -rf "$TMP/home"
    mkdir -p "$TMP/home/.claude/global-lessons" "$TMP/home/.claude/hooks/state"
    cat > "$TMP/home/.claude/global-lessons/pattern-deploy-safety.md" <<'KF'
---
name: deploy-safety
type: pattern
confidence: 4
impact: 4
domain: [devops]
situation: deploying_to_production
trigger: deploy_command
tags: [deploy, rsync, database, exclude]
---
Never copy DB/caches/env on deploy.
KF
}

run_activator() {
    local input="$1"
    local root="${2:-$REPO_ROOT}"
    printf '%s' "$input" | env \
        HOME="$TMP/home" \
        CLAUDE_CODE_SESSION_ID="test-ka-fixed" \
        STATE_DIR="$TMP/home/.claude/hooks/state" \
        CLAUDSOUL_ROOT="$root" \
        bash "$HOOK" 2>/dev/null
}

INPUT_MATCH='{"session_id":"test-ka-fixed","tool_name":"Bash","cwd":"/tmp/proj","tool_input":{"command":"rsync deploy database to production server"}}'

# === T1-T4: первое срабатывание с совпадающим знанием ===
setup_home
OUT=$(run_activator "$INPUT_MATCH")
RC=$?
assert_eq "0" "$RC" "T1: first-fire exit 0"
assert_contains "$OUT" '"hookEventName": "PreToolUse"' "T2: валидный PreToolUse-конверт"
assert_contains "$OUT" "pattern-deploy-safety" "T3: совпадающее знание всплыло (путь скоринга домен-графа)"
assert_contains "$OUT" "ПУНКТ 0" "T4: Пункт 0 (demand-first) инжектится на первом срабатывании"

# === T5: повтор в окне cooldown → подавлено ===
OUT2=$(run_activator "$INPUT_MATCH")
assert_empty "$OUT2" "T5: cooldown подавляет повторное срабатывание"

# === T6: graceful — нет базы знаний → exit 0, пусто ===
setup_home
rm -rf "$TMP/home/.claude/global-lessons"
OUT3=$(run_activator "$INPUT_MATCH")
RC3=$?
assert_eq "0" "$RC3" "T6: нет global-lessons → exit 0 (graceful)"
assert_empty "$OUT3" "T6b: нет global-lessons → пустой вывод"

# === T7: первое срабатывание, секция релевантного знания присутствует ===
setup_home
OUT4=$(run_activator "$INPUT_MATCH")
assert_contains "$OUT4" "Relevant knowledge" "T7: секция 'Relevant knowledge' присутствует"

# === T8: семантический откат MCP при слабом keyword-скоринге (мост L1↔L2) ===
setup_home
STUB="$TMP/stubroot"
mkdir -p "$STUB/mcp-server/.venv/bin"
touch "$STUB/mcp-server/cli_search.py"
cat > "$STUB/mcp-server/.venv/bin/python" <<'PYEOF'
#!/usr/bin/env bash
echo '[{"file_path":"/x/pattern-mcp-hit.md","name":"mcp-hit","type":"pattern","confidence":4,"impact":4}]'
PYEOF
chmod +x "$STUB/mcp-server/.venv/bin/python"
INPUT_NOMATCH='{"session_id":"test-ka-fixed","tool_name":"Bash","cwd":"/tmp/proj","tool_input":{"command":"frobnicate the wibblefitz quux"}}'
OUT5=$(run_activator "$INPUT_NOMATCH" "$STUB")
assert_contains "$OUT5" "mcp-hit" "T8: семантический откат MCP всплывает при слабом keyword-скоринге"

echo ""
echo "knowledge-activator tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
