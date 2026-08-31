#!/usr/bin/env bash
# test_periodic_digests.sh — v1.5.3-alpha: проверка knowledge-audit-digest и bridge-health-digest.
# Изоляция через LESSONS_DIR/BRIDGES_DIR/HISTORY_DIR/STATE_DIR env vars.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT_SCRIPT="$HOOKS_DIR/knowledge-audit-digest.sh"
BRIDGE_SCRIPT="$HOOKS_DIR/bridge-health-digest.sh"
FSRS_LIB="$HOOKS_DIR/fsrs-lib.sh"

[ -f "$AUDIT_SCRIPT" ] || { echo "FAIL: $AUDIT_SCRIPT not found"; exit 1; }
[ -f "$BRIDGE_SCRIPT" ] || { echo "FAIL: $BRIDGE_SCRIPT not found"; exit 1; }

# Фикстуры рассчитаны на календарные дни: реестр сессий пиннится в несуществующий,
# иначе на машине с живым реестром дни ОПЫТА (D234) сжимают 200 дней в несколько
# и «просрочка» фикстуры исчезает (в CI реестра нет — расходились среды).
export FSRS_SESSION_REGISTRY="/nonexistent/registry.jsonl"

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not found"; fi
}
assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' unexpectedly present"
    else PASS=$((PASS + 1)); fi
}
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Isolate all audit-digest runs from production cross-contour log by default.
# Tests that specifically cover the discovery path override this.
export DISCOVERY_DISABLED=1

# --- knowledge-audit-digest tests ---
LESSONS_DIR="$TMP/lessons"
HISTORY_DIR="$TMP/lessons/_audit-history"
STATE_DIR="$TMP/state"
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

# Fixture knowledge files
make_knowledge() {
    local path="$1" conf="$2" contr="$3" impact="$4" last_conf="$5" status="${6:-active}"
    cat > "$path" <<EOF
---
name: test-$path
type: case
outcome: error
confidence: 3
impact: $impact
confirmed_count: $conf
contradicted_count: $contr
last_confirmed: $last_conf
status: $status
domain: [test]
---

Body
EOF
}

TODAY=$(date +%Y-%m-%d)
OLD=$(date -v-200d +%Y-%m-%d 2>/dev/null || date -d "200 days ago" +%Y-%m-%d)

make_knowledge "$LESSONS_DIR/case-fresh1.md"  3 0 2 "$TODAY" active
make_knowledge "$LESSONS_DIR/case-fresh2.md"  5 1 3 "$TODAY" active
make_knowledge "$LESSONS_DIR/pattern-p1.md"   2 0 2 "$TODAY" active
make_knowledge "$LESSONS_DIR/principle-pr1.md" 4 0 4 "$TODAY" active
make_knowledge "$LESSONS_DIR/case-old.md"     1 0 1 "$OLD" active
make_knowledge "$LESSONS_DIR/case-deprecated.md" 2 0 2 "$TODAY" deprecated

# Run digest
LESSONS_DIR="$LESSONS_DIR" HISTORY_DIR="$HISTORY_DIR" STATE_DIR="$STATE_DIR" FSRS_LIB="$FSRS_LIB" \
    bash "$AUDIT_SCRIPT" >/dev/null 2>&1
RC=$?

assert_eq "$RC" "0" "T1: digest returns 0"

YEAR=$(date +%G)
WEEK=$(date +%V)
DIGEST_FILE="$HISTORY_DIR/audit-${YEAR}-W${WEEK}.md"

[ -f "$DIGEST_FILE" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T2]: digest file not written"; }

OUT=$(cat "$DIGEST_FILE" 2>/dev/null)
assert_contains "$OUT" "Total:** 6" "T3: total = 6"
assert_contains "$OUT" "Cases: 4" "T4: cases = 4"
assert_contains "$OUT" "Patterns: 1" "T5: patterns = 1"
assert_contains "$OUT" "Principles: 1" "T6: principles = 1"
assert_contains "$OUT" "Active: 5" "T7: active = 5"
assert_contains "$OUT" "Deprecated: 1" "T8: deprecated = 1"
assert_contains "$OUT" "depth_ratio" "T9: depth_ratio metric present"
assert_contains "$OUT" "avg_reliability" "T10: avg_reliability metric present"

# old case (200d since last_conf, impact=1, cc=1) — stability = 7*(1+0.5)*1 = 10.5→11 days;
# overdue ≈ 189 days → critical.
assert_contains "$OUT" "case-old.md" "T11: critical overdue knowledge surfaced"
assert_contains "$OUT" "critical" "T12: critical bucket present"

# --- Trend test: second run bumps file count, trend line appears ---
make_knowledge "$LESSONS_DIR/case-new.md" 1 0 1 "$TODAY" active

# Fake previous digest by creating a file with earlier week number
PREV_WEEK_FILE="$HISTORY_DIR/audit-${YEAR}-W01.md"
printf '# Knowledge Audit — %s-W01\n\n**Total:** 5\n' "$YEAR" > "$PREV_WEEK_FILE"

LESSONS_DIR="$LESSONS_DIR" HISTORY_DIR="$HISTORY_DIR" STATE_DIR="$STATE_DIR" FSRS_LIB="$FSRS_LIB" \
    bash "$AUDIT_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "0" "T13rc: второй прогон дожил (смерть раньше читалась как «total не вырос», D220)"

OUT2=$(cat "$DIGEST_FILE" 2>/dev/null)
assert_contains "$OUT2" "Total:** 7" "T13: total incremented to 7 on second run"
assert_contains "$OUT2" "since last audit" "T14: trend line present"

# Hint written because we have trend now
HINT_FILE="$STATE_DIR/audit-hint.txt"
if [ -f "$HINT_FILE" ]; then
    HINT=$(cat "$HINT_FILE")
    if grep -q "knowledge audit" <<< "$HINT"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL [T15]: hint content unexpected: $HINT"
    fi
else
    # Accept: if there are no overdue AND no prev-digest trend changed sign — hint may be absent.
    # Our fixture creates a trend line, so hint SHOULD be written.
    FAIL=$((FAIL + 1)); echo "FAIL [T15]: hint file not written"
fi

# --- Empty lessons dir → digest with total=0 ---
EMPTY_DIR="$TMP/empty"
mkdir -p "$EMPTY_DIR/_audit-history"
LESSONS_DIR="$EMPTY_DIR" HISTORY_DIR="$EMPTY_DIR/_audit-history" STATE_DIR="$STATE_DIR" FSRS_LIB="$FSRS_LIB" \
    bash "$AUDIT_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "0" "T16: empty dir returns 0"
EMPTY_DIGEST="$EMPTY_DIR/_audit-history/audit-${YEAR}-W${WEEK}.md"
assert_contains "$(cat "$EMPTY_DIGEST" 2>/dev/null)" "Total:** 0" "T17: empty total = 0"

# --- Missing lessons dir → exit 1 ---
LESSONS_DIR="$TMP/nonexistent" bash "$AUDIT_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "1" "T18: missing lessons dir returns 1"

# --- Engineering escalation tests (v1.5.5-alpha+1) ---
# Embedded defense against recursive inside-out-blindness: pattern with
# blocker:true + escalation_threshold reached → digest emits section,
# hint gets 🛠️ prefix and priority over overdue/trend.

make_escalation_pattern() {
    local path="$1" blocker="$2" threshold="$3" conf="$4" hint="${5:-}"
    local threshold_line=""
    [ -n "$threshold" ] && threshold_line="escalation_threshold: $threshold"
    local hint_line=""
    [ -n "$hint" ] && hint_line="escalation_hint: \"$hint\""
    cat > "$path" <<EOF
---
name: test-$(basename "$path" .md)
type: pattern
outcome: error
confidence: 4
impact: 5
confirmed_count: $conf
contradicted_count: 0
last_confirmed: $TODAY
blocker: $blocker
$threshold_line
$hint_line
status: active
domain: [test]
---

Body
EOF
}

ESC_DIR="$TMP/esc"
ESC_HIST="$ESC_DIR/_audit-history"
ESC_STATE="$TMP/esc-state"
mkdir -p "$ESC_DIR" "$ESC_HIST" "$ESC_STATE"

# Triggers escalation: blocker=true, cc(15) >= threshold(15)
make_escalation_pattern "$ESC_DIR/pattern-triggers.md" true 15 15 "next defense layer needed"
# Below threshold: cc(3) < threshold(10) — no escalation
make_escalation_pattern "$ESC_DIR/pattern-below.md" true 10 3 "should not fire"
# Not a blocker: threshold valid but blocker=false — no escalation
make_escalation_pattern "$ESC_DIR/pattern-not-blocker.md" false 5 10 "should not fire"
# Blocker without threshold — no escalation
make_escalation_pattern "$ESC_DIR/pattern-no-threshold.md" true "" 20 ""

LESSONS_DIR="$ESC_DIR" HISTORY_DIR="$ESC_HIST" STATE_DIR="$ESC_STATE" FSRS_LIB="$FSRS_LIB" \
    bash "$AUDIT_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "0" "T18a: escalation digest returns 0"

ESC_DIGEST="$ESC_HIST/audit-${YEAR}-W${WEEK}.md"
OUT_ESC=$(cat "$ESC_DIGEST" 2>/dev/null)
# Ассерты исключения — по секции эскалации, а не по всему дайджесту: с v1.11 рядом
# живёт секция «Знание о себе», где перечислены ВСЕ pattern/principle без фильтра,
# и проверка «нет во всём файле» проверяла бы не то, что задумано.
OUT_ESC_SECTION=$(printf '%s\n' "$OUT_ESC" | awk '/^## ⚠️ Engineering escalation/{f=1;next} /^## /{f=0} f')

assert_contains "$OUT_ESC" "Engineering escalation needed" "T18b: escalation section present"
assert_contains "$OUT_ESC_SECTION" "pattern-triggers" "T18c: over-threshold pattern surfaced"
assert_contains "$OUT_ESC_SECTION" "next defense layer needed" "T18d: escalation_hint rendered"
assert_not_contains "$OUT_ESC_SECTION" "pattern-below" "T18e: below-threshold pattern excluded"
assert_not_contains "$OUT_ESC_SECTION" "pattern-not-blocker" "T18f: non-blocker excluded"
assert_not_contains "$OUT_ESC_SECTION" "pattern-no-threshold" "T18g: blocker without threshold excluded"

# Новая секция v1.11: счётчики по консолидированному слою, без фильтра «про агента».
OUT_SELF=$(printf '%s\n' "$OUT_ESC" | awk '/^## Знание о себе/{f=1;next} /^## /{f=0} f')
assert_contains "$OUT_SELF" "pattern-triggers" "T18j: секция «Знание о себе» перечисляет знания"
assert_contains "$OUT_SELF" "pattern-not-blocker" "T18k: и не-blocker тоже (фильтра нет намеренно)"
HINT_SELF=$(cat "$ESC_STATE/audit-hint.txt" 2>/dev/null || true)
assert_not_contains "$HINT_SELF" "Знание о себе" "T18l: отчёт о себе НЕ уходит в hint (правило hold-out)"

ESC_HINT="$ESC_STATE/audit-hint.txt"
if [ -f "$ESC_HINT" ]; then
    HINT_ESC=$(cat "$ESC_HINT")
    if grep -q "Engineering escalation" <<< "$HINT_ESC"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL [T18h]: hint missing escalation prefix: $HINT_ESC"
    fi
else
    FAIL=$((FAIL + 1)); echo "FAIL [T18h]: escalation hint file not written"
fi

# Priority test: escalation + overdue → escalation wins hint
ESC_PRI_DIR="$TMP/esc-pri"
ESC_PRI_HIST="$ESC_PRI_DIR/_audit-history"
ESC_PRI_STATE="$TMP/esc-pri-state"
mkdir -p "$ESC_PRI_DIR" "$ESC_PRI_HIST" "$ESC_PRI_STATE"

make_escalation_pattern "$ESC_PRI_DIR/pattern-escalates.md" true 5 10 "priority check"
# Add 6 overdue critical cases (would normally generate ⚠️ hint)
for i in 1 2 3 4 5 6; do
    make_knowledge "$ESC_PRI_DIR/case-overdue-$i.md" 1 0 1 "$OLD" active
done

# CLAUDSOUL_ROOT уводится в пустой каталог: иначе в подсказку попадают посторонние
# сигналы живого проекта (просроченные замеры, открытые пункты долга), и случай начинает
# мерить состояние машины, а не приоритет эскалации над накопительным сигналом.
ESC_PRI_EMPTY="$TMP/esc-pri-empty-root"
mkdir -p "$ESC_PRI_EMPTY"
LESSONS_DIR="$ESC_PRI_DIR" HISTORY_DIR="$ESC_PRI_HIST" STATE_DIR="$ESC_PRI_STATE" FSRS_LIB="$FSRS_LIB" \
    CLAUDSOUL_ROOT="$ESC_PRI_EMPTY" \
    bash "$AUDIT_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "0" "ESC-PRI-rc: прогон дожил (D220)"

ESC_PRI_HINT="$ESC_PRI_STATE/audit-hint.txt"
if [ -f "$ESC_PRI_HINT" ]; then
    HINT_PRI=$(cat "$ESC_PRI_HINT")
    # Проверяется ПОРЯДОК, а не подавление. Прежде здесь стояло «Knowledge audit отсутствует»
    # — то есть тест закреплял поведение «сработал первый подходящий, остальные не
    # показываются никогда». Цена этого измерена: эскалация занимала единственный слот
    # 12 недель подряд (W20…W31), вытесняя сигнал о просрочке знаний при 44-87% просроченных.
    # Подсказка теперь складывается из сигналов по приоритету, поэтому вторая строка
    # законна — важно, что эскалация идёт ПЕРВОЙ.
    if [ "$(printf '%s' "$HINT_PRI" | head -1 | grep -c 'Engineering escalation')" = "1" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL [T18i]: priority wrong: $HINT_PRI"
    fi
else
    FAIL=$((FAIL + 1)); echo "FAIL [T18i]: priority hint not written"
fi

# --- Periodic cross-contour discovery integration (Phase 5.0 / v1.6 prerequisite) ---
# knowledge-audit-digest.sh invokes mcp-server Python to refresh
# cross-contour-discoveries.jsonl weekly. Test isolates log via env var.
# Skips when venv/module not available (CI without Python deps).

DISCOVERY_PYTHON="${DISCOVERY_PYTHON:-$HOME/My Project/ClaudSoul/mcp-server/.venv/bin/python}"
DISCOVERY_MODULE_DIR="${DISCOVERY_MODULE_DIR:-$HOME/My Project/ClaudSoul/mcp-server}"

if [ -x "$DISCOVERY_PYTHON" ] && [ -d "$DISCOVERY_MODULE_DIR/ingest" ]; then
    DISC_LESSONS="$TMP/disc-lessons"
    DISC_HIST="$DISC_LESSONS/_audit-history"
    DISC_STATE="$TMP/disc-state"
    DISC_LOG="$TMP/disc-cross-contour.jsonl"
    mkdir -p "$DISC_LESSONS" "$DISC_HIST" "$DISC_STATE"

    # Entity fixture with unique name that will be matched in knowledge body.
    cat > "$DISC_LESSONS/entity-xyzzycorp.md" <<'EOF'
---
name: XyzzyCorp
type: entity
aliases: []
---

Some body.
EOF

    # Knowledge fixture mentioning the entity name.
    cat > "$DISC_LESSONS/case-xyzzy-mention.md" <<'EOF'
---
name: xyzzy-mention
type: case
outcome: success
confidence: 2
impact: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-04-24
status: active
---

Встретил XyzzyCorp при ретроспективе — паттерн повторяется.
EOF

    DISCOVERY_DISABLED=0 \
    LESSONS_DIR="$DISC_LESSONS" HISTORY_DIR="$DISC_HIST" STATE_DIR="$DISC_STATE" FSRS_LIB="$FSRS_LIB" \
    CLAUDSOUL_CROSS_CONTOUR_LOG="$DISC_LOG" \
    DISCOVERY_PYTHON="$DISCOVERY_PYTHON" DISCOVERY_MODULE_DIR="$DISCOVERY_MODULE_DIR" \
        bash "$AUDIT_SCRIPT" >/dev/null 2>&1
    RC=$?
    assert_eq "$RC" "0" "T-DISC-1: audit with discovery returns 0"

    if [ -f "$DISC_LOG" ]; then
        PASS=$((PASS + 1))
        LOG_CONTENT=$(cat "$DISC_LOG")
        assert_contains "$LOG_CONTENT" "entity-xyzzycorp.md" "T-DISC-3: entity file recorded"
        assert_contains "$LOG_CONTENT" "case-xyzzy-mention.md" "T-DISC-4: knowledge file recorded"
        assert_contains "$LOG_CONTENT" "XyzzyCorp" "T-DISC-5: matched token recorded"
    else
        FAIL=$((FAIL + 1)); echo "FAIL [T-DISC-2]: cross-contour log not written"
    fi

    # DISCOVERY_DISABLED=1 → no log write even when Python is available.
    DISC_LOG_OFF="$TMP/disc-off.jsonl"
    DISCOVERY_DISABLED=1 \
    LESSONS_DIR="$DISC_LESSONS" HISTORY_DIR="$DISC_HIST" STATE_DIR="$DISC_STATE" FSRS_LIB="$FSRS_LIB" \
    CLAUDSOUL_CROSS_CONTOUR_LOG="$DISC_LOG_OFF" \
        bash "$AUDIT_SCRIPT" >/dev/null 2>&1
    RC=$?
    assert_eq "$RC" "0" "T-DISC-6rc: прогон дожил — смерть давала тот же исход, что подавление лога (D220)"
    if [ -f "$DISC_LOG_OFF" ]; then
        FAIL=$((FAIL + 1)); echo "FAIL [T-DISC-6]: DISCOVERY_DISABLED=1 did not suppress log"
    else
        PASS=$((PASS + 1))
    fi
else
    echo "SKIP [T-DISC-*]: venv or module not available ($DISCOVERY_PYTHON)"
fi

# --- bridge-health-digest tests ---
BRIDGES_DIR="$TMP/bridges"
B_HISTORY="$TMP/bridges-history"
B_STATE="$TMP/b-state"
mkdir -p "$BRIDGES_DIR" "$B_HISTORY" "$B_STATE"

make_bridge() {
    local path="$1" status="$2"
    cat > "$path" <<EOF
---
name: Bridge $(basename "$path" .md)
layers: [L2, L3]
status: $status
version: 1.0.0
---

Body
EOF
}

make_bridge "$BRIDGES_DIR/L2-L3-test.md"   implemented
make_bridge "$BRIDGES_DIR/L2-L4-test.md"   designed
make_bridge "$BRIDGES_DIR/L2-L5-test.md"   implemented
make_bridge "$BRIDGES_DIR/L3-L4-test.md"   implicit
make_bridge "$BRIDGES_DIR/L4-L5-test.md"   designed

BRIDGES_DIR="$BRIDGES_DIR" HISTORY_DIR="$B_HISTORY" STATE_DIR="$B_STATE" \
    bash "$BRIDGE_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "0" "T19: bridge digest returns 0"

YEAR_B=$(date +%Y)
MONTH_B=$(date +%m)
B_DIGEST="$B_HISTORY/health-${YEAR_B}-${MONTH_B}.md"
[ -f "$B_DIGEST" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T20]: bridge digest not written"; }

OUT_B=$(cat "$B_DIGEST" 2>/dev/null)
assert_contains "$OUT_B" "Total bridges:** 5" "T21: total bridges = 5"
assert_contains "$OUT_B" "Implemented:** 2" "T22: 2 implemented"
assert_contains "$OUT_B" "Designed:** 2" "T23: 2 designed"
assert_contains "$OUT_B" "Implicit:** 1" "T24: 1 implicit"
assert_contains "$OUT_B" "L2-L3-test" "T25: implemented bridge listed"
assert_contains "$OUT_B" "L2-L4-test" "T26: designed bridge listed"

# Hint: 2 designed < 3 threshold, and no trend → hint file should NOT exist
B_HINT="$B_STATE/bridge-hint.txt"
if [ -f "$B_HINT" ]; then
    FAIL=$((FAIL + 1)); echo "FAIL [T27]: bridge-hint should not exist when designed<3 and no trend"
else
    PASS=$((PASS + 1))
fi

# Add 2 more designed bridges → hint should appear
make_bridge "$BRIDGES_DIR/L5-L6-test.md" designed
make_bridge "$BRIDGES_DIR/L6-L7-test.md" designed
BRIDGES_DIR="$BRIDGES_DIR" HISTORY_DIR="$B_HISTORY" STATE_DIR="$B_STATE" \
    bash "$BRIDGE_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "0" "T28rc: bridge-дайджест дожил (D220)"

if [ -f "$B_HINT" ] && grep -q "designed but not implemented" "$B_HINT"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T28]: bridge-hint should appear with 4 designed"
fi

# Missing bridges dir → exit 1
BRIDGES_DIR="$TMP/nonexistent-bridges" bash "$BRIDGE_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "1" "T29: missing bridges dir returns 1"

# --- D89: fragile взводится по 3+ перекройкам правила (отдельный каталог) ---
# Каталог свой, чтобы фикстуры не смещали счётчики активных/всего в проверках выше:
# дайджест считает знания, и четыре лишних файла меняли бы чужие ожидания.
D89_DIR="$TMP/d89"; D89_HIST="$D89_DIR/_audit-history"
mkdir -p "$D89_DIR"
# Фикстуры для D89: флаг fragile взводится по 3+ перекройкам правила.
# Правило META объявляло это автоматическим и не исполнялось никем — на 2026-08-26
# единственное знание базы с тремя перекройками несло fragile: false.
make_rewritten() { # путь, число записей modification_history, текущее значение fragile
    local path="$1" n="$2" frag="$3" i
    {
        printf -- '---\n'
        printf 'name: rewritten\ntype: pattern\noutcome: error\nconfidence: 3\nimpact: 3\n'
        printf 'confirmed_count: 4\ncontradicted_count: 0\nlast_confirmed: %s\n' "$(date +%Y-%m-%d)"
        [ "$frag" != "absent" ] && printf 'fragile: %s\n' "$frag"
        printf 'status: active\ndomain: [test]\nmodification_history:\n'
        i=0; while [ "$i" -lt "$n" ]; do
            printf -- '  - date: 2026-0%s-01\n    kind: narrowed\n    reason: "сузили"\n' "$((i+1))"
            i=$((i+1))
        done
        printf -- '---\n\nBody\n'
    } > "$path"
}
make_rewritten "$D89_DIR/pattern-rw3.md" 3 false     # ровно порог, поле есть
make_rewritten "$D89_DIR/pattern-rw4.md" 4 absent    # выше порога, поля нет
make_rewritten "$D89_DIR/pattern-rw2.md" 2 false     # ниже порога — не трогать
make_rewritten "$D89_DIR/pattern-rwt.md" 3 true      # уже взведён — не дублировать

LESSONS_DIR="$D89_DIR" HISTORY_DIR="$D89_HIST" STATE_DIR="$STATE_DIR" FSRS_LIB="$FSRS_LIB" \
    bash "$AUDIT_SCRIPT" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "0" "D89rc: прогон дожил (D220)"

assert_eq "1" "$(grep -c '^fragile: true$' "$D89_DIR/pattern-rw3.md")" "D89: поле false переключено на true"
assert_eq "1" "$(grep -c '^fragile: true$' "$D89_DIR/pattern-rw4.md")" "D89: отсутствующее поле добавлено"
assert_eq "0" "$(grep -c '^fragile: false$' "$D89_DIR/pattern-rw4.md")" "D89: и не осталось false рядом"
assert_eq "1" "$(grep -c '^fragile: false$' "$D89_DIR/pattern-rw2.md")" "D89: ниже порога знание не тронуто"
assert_eq "1" "$(grep -c '^fragile: true$' "$D89_DIR/pattern-rwt.md")" "D89: уже взведённый не продублирован"
assert_eq "1" "$(grep -c '^status: active$' "$D89_DIR/pattern-rw4.md")" "D89: вставка не съела соседнюю строку"

echo ""
echo "Periodic digests tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
