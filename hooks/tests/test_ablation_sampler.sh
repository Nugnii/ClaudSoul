#!/usr/bin/env bash
# test_ablation_sampler.sh — сэмплер ablation: детерминизм HMAC, commitment,
# гварды (eligible-только, без повторов, свежесть pulse). Всё оффлайн, фикстуры.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
JOURNAL="$ROOT/scripts/ablation/journal.sh"
SAMPLER="$ROOT/scripts/ablation/sampler.py"
[ -f "$SAMPLER" ] || { echo "FAIL: $SAMPLER not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "expected empty: $1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ABLATION_DIR="$TMP/abl"

# Фикстурная соль + её commitment (переопределяем протокольный).
printf 'testsalt\n' > "$TMP/salt.txt"
export ABLATION_SALT="$TMP/salt.txt"
export ABLATION_COMMITMENT=$(python3 -c "import hashlib;print(hashlib.sha256(b'testsalt').hexdigest())")

# Фикстурный pulse: outputValue детерминированный.
OV=$(python3 -c "print('ab'*32)")
printf '{"pulse":{"outputValue":"%s","timeStamp":"2026-08-08T16:00:00.000Z","statusCode":0}}' "$OV" > "$TMP/pulse.json"

ID=$(bash "$JOURNAL" register "тестовая задача")
SNAP="2026-08-08T15:00:00Z"

# --- T1: до классификации решение запрещено ---
OUT=$(python3 "$SAMPLER" decide --task-id "$ID" --snapshot-ts "$SNAP" --beacon-file "$TMP/pulse.json" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T1" "решение без eligible прошло"
assert_contains "$OUT" "не классифицирована eligible" "T1b: причина названа"

# --- T2: решение детерминировано и совпадает с независимым пересчётом ---
bash "$JOURNAL" classify "$ID" eligible "тест" bugfix low
OUT=$(python3 "$SAMPLER" decide --task-id "$ID" --snapshot-ts "$SNAP" --beacon-file "$TMP/pulse.json")
EXPECTED=$(python3 - "$ID" "$OV" << 'EOF'
import hmac, hashlib, sys, json
tid, ov = sys.argv[1], sys.argv[2]
r = hmac.new(b"testsalt", b"claudsoul-ablation-v1\x00" + tid.encode() + b"\x00" + bytes.fromhex(ov), hashlib.sha256).digest()
print(json.dumps({"task_id": tid, "selected": int.from_bytes(r, "big") % 4 == 0}))
EOF
)
[ "$OUT" = "$EXPECTED" ] && ok || bad "T2" "решение != независимый пересчёт: $OUT vs $EXPECTED"
assert_contains "$(cat "$ABLATION_DIR/journal.jsonl")" "\"e\":\"sampler\"" "T2b: событие в журнале"
[ -f "$ABLATION_DIR/beacon-$ID.json" ] && ok || bad "T2c" "pulse не сохранён"

# --- T3: повторное решение запрещено ---
OUT=$(python3 "$SAMPLER" decide --task-id "$ID" --snapshot-ts "$SNAP" --beacon-file "$TMP/pulse.json" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3" "повторное решение прошло"

# --- T4: verify пересчитывает журнал без расхождений ---
python3 "$SAMPLER" verify >/dev/null 2>&1 && ok || bad "T4" "verify нашёл расхождение на честном журнале"

# --- T5: pulse не позже заморозки — pending (отказ) ---
ID2=$(bash "$JOURNAL" register "вторая")
bash "$JOURNAL" classify "$ID2" eligible "тест" feature low
OUT=$(python3 "$SAMPLER" decide --task-id "$ID2" --snapshot-ts "2026-08-08T17:00:00Z" --beacon-file "$TMP/pulse.json" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T5" "pulse старше заморозки принят"
assert_contains "$OUT" "pending" "T5b: задача остаётся pending"

# --- T6: statusCode != 0 — отказ ---
printf '{"pulse":{"outputValue":"%s","timeStamp":"2026-08-08T16:00:00.000Z","statusCode":1}}' "$OV" > "$TMP/bad.json"
OUT=$(python3 "$SAMPLER" decide --task-id "$ID2" --snapshot-ts "$SNAP" --beacon-file "$TMP/bad.json" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T6" "statusCode=1 принят"

# --- T7: сломанный commitment — решение не вычисляется ---
OUT=$(ABLATION_COMMITMENT="deadbeef" python3 "$SAMPLER" decide --task-id "$ID2" --snapshot-ts "$SNAP" --beacon-file "$TMP/pulse.json" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T7" "подменённая соль прошла commitment"
assert_contains "$OUT" "commitment" "T7b: причина названа"

echo "test_ablation_sampler: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
