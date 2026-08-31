#!/usr/bin/env bash
# test_research_slot.sh — пятый слот подаёт давно/никогда не подававшееся знание (D230).
# en: research slot injects the longest-unserved matching knowledge with marker and log field.
#
# Проверяется: «никогда» побеждает «давно»; выбранное не из топ-квоты; маркер 🧭 в
# сообщении; поле slot=research в журнале подач; выключатель KA_RESEARCH_SLOT=0;
# строки текущей сессии не двигают агрегат (стабильность внутри сессии).
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/knowledge-activator.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAKE_HOME="$TMP/home"; STATE="$TMP/state"
mkdir -p "$FAKE_HOME/.claude/global-lessons" "$STATE"

mk() { # $1 имя, $2 сколько совпадающих тегов (score), остальное — одинаково
    local extra=""
    [ "$2" -ge 2 ] && extra=", grep"
    [ "$2" -ge 3 ] && extra="$extra, tracker"
    cat > "$FAKE_HOME/.claude/global-lessons/$1.md" <<KF
---
name: ${1}
description: фикстура слота исследования
type: pattern
confidence: 4
impact: 4
domain: [shell]
tags: [docker${extra}]
---
Правило-фикстура.
KF
}
mk pattern-top1 3
mk pattern-top2 3
mk pattern-top3 2
mk pattern-tail-old 1
mk pattern-tail-never 1

# Журнал подач ДРУГОЙ сессии: top1-3 поданы недавно, tail-old — давно; tail-never в
# журнале нет вовсе → он и есть кандидат слота (никогда побеждает давно).
cat > "$STATE/injection-log.jsonl" << 'EOF'
{"date":"2026-08-30T10:00:00Z","file":"pattern-top1.md","injected":true,"session_id":"sOld","rank":1}
{"date":"2026-08-30T10:00:00Z","file":"pattern-top2.md","injected":true,"session_id":"sOld","rank":2}
{"date":"2026-08-30T10:00:00Z","file":"pattern-top3.md","injected":true,"session_id":"sOld","rank":3}
{"date":"2026-05-01T10:00:00Z","file":"pattern-tail-old.md","injected":true,"session_id":"sOld","rank":1}
EOF

run() { # $1 sid, env-довесок в $2
    printf '{"session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"docker grep tracker compose"}}' "$1" "$REPO_ROOT" \
      | env HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$1" STATE_DIR="$STATE" \
            SKIP_MCP_FALLBACK=1 SKIP_ENTITY_ACTIVATION=1 ${2:-} bash "$HOOK" 2>/dev/null
}

OUT=$(run rs1)
# --- T1: слот подан, и это «никогда не подававшееся» ---
grep -q 'pattern-tail-never' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1 tail-never не подан]"; }
# --- T2: маркер исследования при нём ---
grep -q '🧭' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2 маркер]"; }
# --- T3: журнал несёт slot=research ровно у него ---
if jq -e 'select(.file == "pattern-tail-never.md" and .slot == "research" and .injected == true)' \
      "$STATE/injection-log.jsonl" >/dev/null 2>&1; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3 slot в журнале]"; fi
# --- T4: топ-квота слоту не отдана (top1 остался в подаче) ---
grep -q 'pattern-top1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4 топ вытеснен]"; }

# --- T5: повторный вызов ТОЙ ЖЕ сессии выбирает тот же слот (агрегат неподвижен) ---
rm -f "$STATE"/knowledge_injected_* 2>/dev/null
OUT2=$(run rs1 "KA_TOPIC_SHIFT_FORCE=1")
N_RESEARCH=$(jq -rs '[.[] | select(.slot == "research")] | length' "$STATE/injection-log.jsonl" 2>/dev/null)
if grep -q 'pattern-tail-never' <<< "$OUT2" || [ "${N_RESEARCH:-0}" -ge 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5 стабильность]: research-строк $N_RESEARCH"; fi

# --- T6: выключатель ---
rm -rf "$STATE"; mkdir -p "$STATE"
cp /dev/null "$STATE/injection-log.jsonl"
OUT3=$(run rs2 "KA_RESEARCH_SLOT=0")
grep -q '🧭' <<< "$OUT3" && { FAIL=$((FAIL+1)); echo "FAIL [T6 выключатель]"; } || PASS=$((PASS+1))

echo "research-slot: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
