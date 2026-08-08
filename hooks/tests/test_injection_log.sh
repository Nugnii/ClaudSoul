#!/usr/bin/env bash
# test_injection_log.sh — контракт «писатель ↔ читатель» injection-log.jsonl.
#
# Тестируется одним файлом намеренно: писатель (knowledge-activator) и читатель
# (metrics-collector) делят схему записи, и рассинхрон схемы — ровно тот класс
# бага, который прожил здесь три месяца незамеченным (jq обрывался на битой
# строке, hit_rate считался по 285 строкам из 7665 и выглядел правдоподобно).
#
# Покрывает две регрессии:
#   W2/W3 — `|` внутри name/description сдвигал поля (143 битые строки на одном
#           знании «grep без || true убивает скрипт»);
#   R1    — голый `jq -r '.file'` умирал на первой битой строке.
# Плюс контрольную группу (ранги 4-6, injected:false) и её обратную совместимость.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTIVATOR="$HOOK_DIR/knowledge-activator.sh"
COLLECTOR="$HOOK_DIR/metrics-collector.sh"
REPO_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
[ -f "$ACTIVATOR" ] || { echo "FAIL: $ACTIVATOR not found"; exit 1; }
[ -f "$COLLECTOR" ] || { echo "FAIL: $COLLECTOR not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: ожидалось '$expected', получено '$actual'"; fi
}
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if printf '%s' "$haystack" | grep -qF "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: не найдено '$needle'"; fi
}
assert_json_valid() {
    local file="$1" label="$2"
    local bad=0 line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        printf '%s' "$line" | jq -e . >/dev/null 2>&1 || bad=$((bad + 1))
    done < "$file"
    if [ "$bad" -eq 0 ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: $bad невалидных строк JSON"; fi
}

STATE="$TMP/home/.claude/hooks/state"
LOG="$STATE/injection-log.jsonl"

# --- фикстуры писателя -------------------------------------------------------

setup_home() {
    rm -rf "$TMP/home"
    mkdir -p "$TMP/home/.claude/global-lessons" "$STATE"
}

# Знание, матчащее общий контекст. $1 — суффикс имени, $2 — name, $3 — description.
make_knowledge() {
    local slug="$1" name="$2" desc="$3"
    cat > "$TMP/home/.claude/global-lessons/pattern-${slug}.md" <<KF
---
name: $name
description: $desc
type: pattern
confidence: 4
impact: 4
domain: [devops]
situation: deploying_to_production
trigger: deploy_command
tags: [deploy, rsync, database, exclude]
---
Body.
KF
}

# Сброс cooldown-гейта: иначе второе срабатывание в той же сессии подавляется.
reset_gate() { rm -f "$STATE"/knowledge_injected_* 2>/dev/null || true; }

run_activator() {
    local sid="${1:-test-inj-fixed}" root="${2:-$REPO_ROOT}"
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"/tmp/proj","tool_input":{"command":"rsync deploy database to production server"}}' "$sid" | \
    env HOME="$TMP/home" CLAUDE_CODE_SESSION_ID="$sid" STATE_DIR="$STATE" \
        CLAUDSOUL_ROOT="$root" SKIP_MCP_FALLBACK=1 bash "$ACTIVATOR" 2>/dev/null
}

# === W1: логируется top-6, инжектится top-3 ===
setup_home
for i in 1 2 3 4 5 6 7; do make_knowledge "cand$i" "cand $i" "desc $i"; done
OUT=$(run_activator)
assert_eq "6" "$({ grep -c '' "$LOG" 2>/dev/null || echo 0; })" "W1a: в логе ровно 6 строк (top-6)"
assert_eq "1 2 3 4 5 6" "$(jq -r '.rank' "$LOG" | tr '\n' ' ' | sed 's/ $//')" "W1b: ранги 1..6"
assert_eq "3" "$(jq -r 'select(.injected == true) | .file' "$LOG" | grep -c '' || echo 0)" "W1c: injected=true ровно у трёх"
assert_eq "3" "$(printf '%s' "$OUT" | grep -o '(confidence:' | grep -c '' || echo 0)" "W1d: в сообщение попали 3 знания, не 6"

# === W2: `|` в name/description не ломает JSON (регрессия 143 битых строк) ===
setup_home
make_knowledge "pipename" 'grep без || true убивает скрипт, а ещё: двоеточие' 'desc с "кавычкой", запятой: и | трубой'
run_activator >/dev/null
assert_json_valid "$LOG" "W2a: все строки валидный JSON при | , : \" в полях"
assert_eq "pattern-pipename.md" "$(jq -r '.file' "$LOG" | head -1)" "W2b: .file не съехал"
assert_eq "4" "$(jq -r '.confidence' "$LOG" | head -1)" "W2c: confidence — число из frontmatter, не мусор"
assert_eq "4" "$(jq -r '.impact' "$LOG" | head -1)" "W2d: impact — число из frontmatter"

# === W3: тот же дефект по пути MCP-fallback ===
setup_home
STUB="$TMP/stubroot"
mkdir -p "$STUB/mcp-server/.venv/bin"
touch "$STUB/mcp-server/cli_search.py"
cat > "$STUB/mcp-server/.venv/bin/python" <<'PYEOF'
#!/usr/bin/env bash
echo '[{"file_path":"/x/pattern-mcp-hit.md","name":"a || b, c: d","type":"pattern","confidence":4,"impact":4}]'
PYEOF
chmod +x "$STUB/mcp-server/.venv/bin/python"
printf '{"session_id":"test-inj-mcp","tool_name":"Bash","cwd":"/tmp/proj","tool_input":{"command":"frobnicate the wibblefitz quux"}}' | \
    env HOME="$TMP/home" CLAUDE_CODE_SESSION_ID="test-inj-mcp" STATE_DIR="$STATE" \
        CLAUDSOUL_ROOT="$STUB" bash "$ACTIVATOR" >/dev/null 2>&1
if [ -s "$LOG" ]; then
    assert_json_valid "$LOG" "W3a: MCP-путь пишет валидный JSON при || в name"
    assert_eq "mcp" "$(jq -r '.via' "$LOG" | head -1)" "W3b: via=mcp"
    assert_eq "99" "$(jq -r '.score' "$LOG" | head -1)" "W3c: score=99 (синтетический маркер)"
else
    FAIL=$((FAIL + 1)); echo "FAIL [W3]: MCP-fallback ничего не записал"
fi

# === W4: новые поля привязки ===
setup_home
make_knowledge "fields" "fields" "desc"
run_activator "sid-abc-123" >/dev/null
assert_eq "sid-abc-123" "$(jq -r '.session_id' "$LOG" | head -1)" "W4a: session_id из payload"
assert_eq "keyword" "$(jq -r '.via' "$LOG" | head -1)" "W4b: via=keyword"
assert_eq "1" "$(jq -r 'select(.project != null and .project != "") | .file' "$LOG" | grep -c '' || echo 0)" "W4c: project заполнен"

# === W5: тай-брейк детерминирован в сессии и перетасован между сессиями ===
setup_home
for i in 1 2 3 4 5 6; do make_knowledge "tie$i" "tie $i" "same score"; done
run_activator "sid-tie-A" >/dev/null
ORDER_A1=$(jq -r '.file' "$LOG" | tr '\n' ' ')
: > "$LOG"; reset_gate
run_activator "sid-tie-A" >/dev/null
ORDER_A2=$(jq -r '.file' "$LOG" | tr '\n' ' ')
assert_eq "$ORDER_A1" "$ORDER_A2" "W5a: одинаковая сессия → одинаковый порядок"
DIFF_FOUND=no
for s in B C D E; do
    : > "$LOG"; reset_gate
    run_activator "sid-tie-$s" >/dev/null
    [ "$(jq -r '.file' "$LOG" | tr '\n' ' ')" != "$ORDER_A1" ] && DIFF_FOUND=yes && break
done
assert_eq "yes" "$DIFF_FOUND" "W5b: другая сессия → порядок в ничейной группе меняется"

# === W6: кандидатов меньше шести → пишем сколько есть, все injected ===
setup_home
make_knowledge "solo" "solo" "desc"
run_activator >/dev/null
assert_eq "1" "$({ grep -c '' "$LOG" 2>/dev/null || echo 0; })" "W6a: один кандидат → одна строка"
assert_eq "true" "$(jq -r '.injected' "$LOG" | head -1)" "W6b: единственный кандидат injected"

# --- читатель ----------------------------------------------------------------

setup_reader() {   # $1 — содержимое лога (heredoc через stdin)
    rm -rf "$TMP/rhome"
    mkdir -p "$TMP/rhome/.claude/global-lessons" "$TMP/rhome/.claude/hooks/state"
    for n in "$@"; do
        printf -- '---\ntype: pattern\nconfidence: 4\nimpact: 4\nconfirmed_count: 1\ncontradicted_count: 0\nstatus: active\n---\nx\n' \
            > "$TMP/rhome/.claude/global-lessons/$n"
    done
}
run_collector() {
    env HOME="$TMP/rhome" LESSONS_DIR="$TMP/rhome/.claude/global-lessons" \
        STATE_DIR="$TMP/rhome/.claude/hooks/state" bash "$COLLECTOR" >/dev/null 2>&1
    cat "$TMP/rhome/.claude/hooks/state/metrics.md"
}
RLOG() { echo "$TMP/rhome/.claude/hooks/state/injection-log.jsonl"; }

# === R1: битая строка ПЕРВОЙ — старый парсер отдал бы ноль ===
setup_reader pattern-a.md pattern-b.md pattern-c.md
cat > "$(RLOG)" <<'EOF'
{"date":"2026-04-16T14:12:25","file":"pattern-a.md","score":2,"confidence":5,"impact":4|false|0}
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":3,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"pattern-b.md","score":2,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"pattern-c.md","score":4,"confidence":4,"impact":4}
EOF
M=$(run_collector)
assert_contains "$M" "Уникальных знаний инжектировано: 3" "R1a: битая первая строка не обрывает разбор"
assert_contains "$M" "Битых строк в injection-log: 1" "R1b: битая строка посчитана и видна"
assert_contains "$M" "| hit_rate | 100% |" "R1c: hit_rate считается (не n/a)"

# === R2: ловушка 341% — в логе не только pattern/principle ===
setup_reader pattern-a.md pattern-b.md
cat > "$(RLOG)" <<'EOF'
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":3,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"pattern-b.md","score":3,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"case-x.md","score":99,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"relation-y.md","score":99,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"fact-z.md","score":99,"confidence":4,"impact":4}
EOF
M=$(run_collector)
assert_contains "$M" "| hit_rate | 100% |" "R2a: hit_rate не превышает 100%"
assert_contains "$M" "Из них pattern/principle: 2 из 2" "R2b: знаменатель и числитель по одному множеству"
assert_contains "$M" "Уникальных знаний инжектировано: 5" "R2c: общее число уникальных — все типы"

# === R3: обратная совместимость с записями без поля injected ===
setup_reader pattern-a.md pattern-b.md
cat > "$(RLOG)" <<'EOF'
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":3,"confidence":4,"impact":4}
{"date":"2026-06-01T10:00:00","file":"pattern-b.md","score":2,"confidence":4,"impact":4,"rank":4,"injected":false}
EOF
M=$(run_collector)
assert_contains "$M" "Инжекций (из лога): 1" "R3a: injected:false не считается инжектом"
assert_contains "$M" "Из них pattern/principle: 1 из 2" "R3b: контрольная группа не завышает hit_rate"
assert_contains "$M" "pattern-b.md" "R3c: невиденное знание попало в never_injected"

# === R4: призрак — знание из лога удалено с диска ===
setup_reader pattern-a.md
cat > "$(RLOG)" <<'EOF'
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":3,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"pattern-deleted.md","score":3,"confidence":4,"impact":4}
EOF
M=$(run_collector)
assert_contains "$M" "| hit_rate | 100% |" "R4: удалённое знание не раздувает hit_rate"

# === R5: средний score без синтетической 99 ===
setup_reader pattern-a.md
cat > "$(RLOG)" <<'EOF'
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":2,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":4,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":6,"confidence":4,"impact":4}
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":99,"confidence":4,"impact":4}
EOF
M=$(run_collector)
assert_contains "$M" "Средний score инжекции: 4.0" "R5: score=99 не размазывает среднее"

# === R6: чистый лог — строки про битые нет ===
setup_reader pattern-a.md
cat > "$(RLOG)" <<'EOF'
{"date":"2026-05-01T10:00:00","file":"pattern-a.md","score":3,"confidence":4,"impact":4}
EOF
M=$(run_collector)
if printf '%s' "$M" | grep -qF "Битых строк"; then
    FAIL=$((FAIL + 1)); echo "FAIL [R6]: на чистом логе не должно быть строки про битые"
else PASS=$((PASS + 1)); fi

# === E2E: писатель → читатель на одной схеме ===
setup_home
make_knowledge "e2e" "e2e knowledge" "desc"
run_activator >/dev/null
rm -rf "$TMP/rhome"
mkdir -p "$TMP/rhome/.claude/global-lessons" "$TMP/rhome/.claude/hooks/state"
cp "$TMP/home/.claude/global-lessons/pattern-e2e.md" "$TMP/rhome/.claude/global-lessons/"
cp "$LOG" "$(RLOG)"
M=$(run_collector)
assert_contains "$M" "| hit_rate | 100% |" "E2E-a: запись писателя читается читателем"
if printf '%s' "$M" | grep -qF "Битых строк"; then
    FAIL=$((FAIL + 1)); echo "FAIL [E2E-b]: писатель произвёл битые строки"
else PASS=$((PASS + 1)); fi

echo ""
echo "injection-log tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
