#!/usr/bin/env bash
# test_knowledge_staleness.sh — линтер мёртвых ссылок находит исчезнувший носитель и молчит на живом.
# en: knowledge staleness linter flags vanished carriers and stays silent on live references.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/knowledge-staleness.sh"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; mkdir -p "$L"

run() { LESSONS_DIR="$L" CLAUDSOUL_REPO_DIR="$REPO" CLAUDE_HOOKS_DIR="$TMP/nohooks" HOME="$TMP" bash "$SCRIPT" 2>&1; printf 'rc=%s' "$?"; }

# --- T1: пустая база → код 0 ---
OUT=$(run)
grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1]: $OUT"; }

# --- T2: живая ссылка (hooks/root-cause-lib.sh существует) → молчит ---
printf -- '---\nname: alive\n---\nПравило опирается на hooks/root-cause-lib.sh и всё.\n' > "$L/pattern-alive.md"
OUT=$(run)
grep -q 'rc=0' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2 живой носитель]: $OUT"; }

# --- T3: мёртвая ссылка → кандидат, код 1 ---
printf -- '---\nname: dead\n---\nСм. hooks/vanished-mechanism-xyz.sh — его давно снесли.\n' > "$L/pattern-dead.md"
OUT=$(run)
grep -q 'pattern-dead.md.*vanished-mechanism-xyz.sh' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T3 кандидат]: $OUT"; }
grep -q 'находки, не сбой' <<< "$OUT" && grep -q 'rc=1' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4 код]: $OUT"; }

# --- T5: generic-пример чужого домена (deploy.sh) кандидатом не считается ---
printf -- '---\nname: alien\n---\nВ том проекте deploy.sh делал не то.\n' > "$L/pattern-alien.md"
OUT=$(run)
grep -q 'pattern-alien' <<< "$OUT" && { FAIL=$((FAIL+1)); echo "FAIL [T5 пример засчитан]: $OUT"; } || PASS=$((PASS+1))

echo "knowledge-staleness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
