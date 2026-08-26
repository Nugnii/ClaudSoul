#!/usr/bin/env bash
# test_ablation_finish.sh — финишные компоненты запускалки: парсер транскриптов,
# заморозка фазы (тег + read-only runtime), связка outputValue↔signature.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AB="$ROOT/scripts/ablation"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "expected empty: $1"; fi; }

TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export ABLATION_DIR="$TMP/abl"
mkdir -p "$ABLATION_DIR"

# --- T1: парсер — токены из result.json, команды/ошибки из транскриптов ---
RUN="$ABLATION_DIR/runs/t-x/full"
mkdir -p "$RUN/home/.claude/projects/p1"
printf '{"usage":{"input_tokens":100,"output_tokens":200},"num_turns":5,"duration_ms":1234}' > "$RUN/result.json"
cat > "$RUN/home/.claude/projects/p1/t.jsonl" << 'EOF'
{"message":{"content":[{"type":"tool_use","name":"Bash"},{"type":"text","text":"x"}]}}
{"message":{"content":[{"type":"tool_result","is_error":true}]}}
{"message":{"content":[{"type":"tool_use","name":"Edit"},{"type":"tool_use","name":"Read"}]}}
EOF
OUT=$(python3 "$AB/parse-transcript.py" t-x full)
assert_contains "$OUT" '"tokens_in": 100' "T1: токены входа"
assert_contains "$OUT" '"all_commands": 3' "T1b: все вызовы"
assert_contains "$OUT" '"failed_commands": 1' "T1c: упавшие"
assert_contains "$(tail -1 "$ABLATION_DIR/journal.jsonl")" '"e":"arm_metrics"' "T1d: событие в журнале"

# --- T2: freeze-policy — тег + read-only runtime + манифест ---
# Идентичность — в конфиг фикстурного репо: git tag -a внутри freeze-policy
# требует её так же, как commit; на CI глобального gitconfig нет (поймано
# красным прогоном 31267492512 — локальная рамка проверки маскировала).
git -C "$TMP" init -q crepo && git -C "$TMP/crepo" config user.email t@t \
    && git -C "$TMP/crepo" config user.name t \
    && (cd "$TMP/crepo" && echo x > f && git add f && git commit -qm init)
mkdir -p "$TMP/rt/hooks" && echo '#!/bin/bash' > "$TMP/rt/hooks/h.sh" \
    && echo rules > "$TMP/rt/CLAUDE.md" && echo '{}' > "$TMP/rt/settings.json"
OUT=$(CLAUDSOUL_RUNTIME="$TMP/rt" bash "$AB/freeze-policy.sh" testphase "$TMP/crepo")
assert_contains "$OUT" "ablation-testphase" "T2: тег создан"
git -C "$TMP/crepo" rev-parse -q --verify refs/tags/ablation-testphase >/dev/null && ok || bad "T2b" "тега нет в репо"
[ -f "$ABLATION_DIR/frozen-runtime-testphase.manifest" ] && ok || bad "T2c" "манифеста нет"
if ( echo test > "$ABLATION_DIR/frozen-runtime-testphase/CLAUDE.md" ) 2>/dev/null; then
    bad "T2d" "frozen runtime записываем — read-only не сработал"
else ok; fi
assert_contains "$(tail -1 "$ABLATION_DIR/journal.jsonl")" '"e":"phase_frozen"' "T2e: событие фазы"

# --- T3: вторая фаза при активной — отказ; после close — грязное дерево — отказ ---
OUT=$(CLAUDSOUL_RUNTIME="$TMP/rt" bash "$AB/freeze-policy.sh" phase2 "$TMP/crepo" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3" "вторая фаза при активной прошла"
assert_contains "$OUT" "уже идёт фаза" "T3a: причина — активная фаза"
bash "$AB/phase.sh" close testphase >/dev/null
echo dirty >> "$TMP/crepo/f"
OUT=$(CLAUDSOUL_RUNTIME="$TMP/rt" bash "$AB/freeze-policy.sh" phase2 "$TMP/crepo" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3b" "заморозка грязного дерева прошла"
assert_contains "$OUT" "грязное" "T3c: причина названа"

# --- T4: verify-pulse — честная связка OK, сфабрикованная ловится ---
SIG="ab"; for i in 1 2 3 4 5 6; do SIG="$SIG$SIG"; done   # 128 hex = 64 байта
OVOK=$(python3 -c "import hashlib;print(hashlib.sha512(bytes.fromhex('$SIG')).hexdigest())")
printf '{"outputValue":"%s","signatureValue":"%s","timeStamp":"x","statusCode":0}' "$OVOK" "$SIG" > "$ABLATION_DIR/beacon-t1.json"
python3 "$AB/sampler.py" verify-pulse >/dev/null 2>&1 && ok || bad "T4" "честный pulse не прошёл"
printf '{"outputValue":"%s","signatureValue":"%s","timeStamp":"x","statusCode":0}' "deadbeef" "$SIG" > "$ABLATION_DIR/beacon-t2.json"
OUT=$(python3 "$AB/sampler.py" verify-pulse 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T4b" "сфабрикованный outputValue прошёл"
assert_contains "$OUT" "РАСХОЖДЕНИЕ" "T4c: расхождение названо"

echo "test_ablation_finish: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
