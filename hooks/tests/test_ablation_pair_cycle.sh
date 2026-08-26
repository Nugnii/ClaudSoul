#!/usr/bin/env bash
# test_ablation_pair_cycle.sh — чекер вне песочниц + жизненный цикл пары:
# hash-реестр, классификация исходов, аннулирование целиком, повтор, максимум 2.

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
J="$ABLATION_DIR/journal.jsonl"

ID=$(bash "$AB/journal.sh" register "задача с чекером")
bash "$AB/journal.sh" classify "$ID" eligible "тест" bugfix low

# Чекер: успех, если в work лежит done.txt
cat > "$TMP/chk.sh" << 'EOF'
#!/usr/bin/env bash
[ -f "$1/done.txt" ] && exit 0
exit 1
EOF

fake_arm_run() { # id arm
    printf '{"e":"arm_run","id":"%s","arm":"%s","started":"x","ended":"x","raw_outcome":"finished"}\n' "$1" "$2" >> "$J"
    mkdir -p "$ABLATION_DIR/runs/$1/$2/work"
}

# --- T1: регистрация чекера, hash в журнале, повтор запрещён ---
bash "$AB/checker.sh" register "$ID" "$TMP/chk.sh" && ok || bad "T1" "register упал"
assert_contains "$(cat "$J")" '"e":"checker_registered"' "T1b: hash зафиксирован"
OUT=$(bash "$AB/checker.sh" register "$ID" "$TMP/chk.sh" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T1c" "повторная регистрация прошла"

# --- T2: run до arm_run — отказ ---
OUT=$(bash "$AB/checker.sh" run "$ID" full 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T2" "классификация без прогона прошла"

# --- T3: исходы обоих плеч: full success, vanilla objective_failure ---
fake_arm_run "$ID" full; touch "$ABLATION_DIR/runs/$ID/full/work/done.txt"
fake_arm_run "$ID" vanilla
OUT=$(bash "$AB/checker.sh" run "$ID" full)
assert_contains "$OUT" "success" "T3: full=success"
OUT=$(bash "$AB/checker.sh" run "$ID" vanilla)
assert_contains "$OUT" "objective_failure" "T3b: vanilla=objective_failure"
OUT=$(bash "$AB/checker.sh" run "$ID" full 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3c" "повторная классификация плеча прошла"

# --- T4: изменённый чекер = infrastructure_failure ---
ID2=$(bash "$AB/journal.sh" register "задача с испорченным чекером")
bash "$AB/journal.sh" classify "$ID2" eligible "тест" bugfix low
bash "$AB/checker.sh" register "$ID2" "$TMP/chk.sh"
fake_arm_run "$ID2" full
chmod u+w "$ABLATION_DIR/checkers/$ID2.sh" && echo "# tamper" >> "$ABLATION_DIR/checkers/$ID2.sh"
OUT=$(bash "$AB/checker.sh" run "$ID2" full 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T4" "испорченный чекер прошёл"
assert_contains "$(tail -1 "$J")" "infrastructure_failure" "T4b: исход infrastructure в журнале"

# --- T5: complete первой пары → строка pairs.jsonl со стратой из dry_run ---
printf '{"e":"dry_run","id":"%s","ts":"x","would_surface":true,"knowledge":[]}\n' "$ID" >> "$J"
bash "$AB/pair.sh" complete "$ID" >/dev/null && ok || bad "T5" "complete упал"
LINE=$(tail -1 "$ABLATION_DIR/pairs.jsonl")
assert_contains "$LINE" '"full":1' "T5b: full=1"
assert_contains "$LINE" '"vanilla":0' "T5c: vanilla=0"
assert_contains "$LINE" '"stratum_surface":true' "T5d: страта из dry_run"
OUT=$(bash "$AB/pair.sh" complete "$ID" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T5e" "повторный complete прошёл"

# --- T6: infrastructure не завершается — только annul; повтор после annul работает ---
OUT=$(bash "$AB/pair.sh" complete "$ID2" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T6" "complete с infrastructure прошёл"
bash "$AB/pair.sh" annul "$ID2" "checker tamper" >/dev/null
[ ! -d "$ABLATION_DIR/runs/$ID2" ] && ok || bad "T6b" "runs не удалены при annul"
# восстановить честный чекер тем же содержимым — hash снова сходится
cp "$TMP/chk.sh" "$TMP/chk2.sh"; cat "$TMP/chk.sh" > "$ABLATION_DIR/checkers/$ID2.sh" 2>/dev/null || {
    chmod u+w "$ABLATION_DIR/checkers/$ID2.sh"; cat "$TMP/chk.sh" > "$ABLATION_DIR/checkers/$ID2.sh"; }
fake_arm_run "$ID2" full; touch "$ABLATION_DIR/runs/$ID2/full/work/done.txt"
fake_arm_run "$ID2" vanilla; touch "$ABLATION_DIR/runs/$ID2/vanilla/work/done.txt"
OUT=$(bash "$AB/checker.sh" run "$ID2" full)
assert_contains "$OUT" "success" "T6c: повтор плеча после annul работает"
bash "$AB/checker.sh" run "$ID2" vanilla >/dev/null
bash "$AB/pair.sh" complete "$ID2" >/dev/null && ok || bad "T6d" "complete после повтора упал"

# --- T7: третья попытка исключает пару ---
ID3=$(bash "$AB/journal.sh" register "вечно падающая инфраструктура")
bash "$AB/pair.sh" annul "$ID3" x >/dev/null
bash "$AB/pair.sh" annul "$ID3" x >/dev/null
OUT=$(bash "$AB/pair.sh" annul "$ID3" x)
assert_contains "$OUT" "исключена" "T7: >2 повторов = исключение"
assert_contains "$(cat "$J")" '"e":"pair_excluded"' "T7b: событие исключения"

echo "test_ablation_pair_cycle: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
