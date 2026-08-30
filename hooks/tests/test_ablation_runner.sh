#!/usr/bin/env bash
# test_ablation_runner.sh — обвязка теневых троек: снимок (неизменяемость, hash),
# env-diff манифеста трёх плеч, dry-run активатора (одноразовость),
# shadow-run --smoke по каждому плечу.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AB="$ROOT/scripts/ablation"
[ -f "$AB/snapshot.sh" ] || { echo "FAIL: snapshot.sh not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "expected empty: $1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ABLATION_DIR="$TMP/abl"

# Фикстуры: git-репо задачи, runtime (реальные хуки репозитория), база знаний.
git -C "$TMP" init -q repo && (cd "$TMP/repo" && echo hi > f.txt && git add f.txt \
    && git -c user.email=t@t -c user.name=t commit -qm init)
mkdir -p "$TMP/runtime" "$TMP/lessons"
cp -R "$ROOT/hooks" "$TMP/runtime/hooks"
cp "$ROOT/rules/CLAUDE.md" "$TMP/runtime/CLAUDE.md"
echo '{}' > "$TMP/runtime/settings.json"
printf -- "---\nname: тест\n---\nтело\n" > "$TMP/lessons/pattern-test-fixture.md"
export CLAUDSOUL_RUNTIME="$TMP/runtime"
export LESSONS_DIR="$TMP/lessons"

ID=$(bash "$AB/journal.sh" register "починить f.txt в репо")
bash "$AB/journal.sh" classify "$ID" eligible "тест" bugfix low

# --- T1: снимок создаёт пакет с manifest и hash-ами ---
TS=$(bash "$AB/snapshot.sh" "$ID" "$TMP/repo")
assert_contains "$TS" "T" "T1: snapshot_ts напечатан"
M=$(cat "$ABLATION_DIR/packages/$ID/manifest.json")
assert_contains "$M" '"repo_head"' "T1b: manifest с HEAD"
assert_contains "$M" '"sha256"' "T1c: hash-и в manifest"
assert_contains "$M" '"core_runtime"' "T1d: hash runtime плеча Core"
[ -f "$ABLATION_DIR/packages/$ID/core-runtime.tar" ] && ok || bad "T1e" "core-runtime.tar не собран"

# --- T2: снимок неизменяем — повтор запрещён ---
OUT=$(bash "$AB/snapshot.sh" "$ID" "$TMP/repo" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T2" "повторный снимок прошёл"
assert_contains "$OUT" "неизменяем" "T2b: причина названа"

# --- T3: env-diff — vanilla с хуками грязна, пустая чиста ---
mkdir -p "$TMP/h1/.claude/hooks" && touch "$TMP/h1/.claude/hooks/x.sh"
OUT=$(bash "$AB/env-diff.sh" vanilla "$TMP/h1" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3" "vanilla с хуками прошла"
assert_contains "$OUT" "infrastructure_failure" "T3b: класс исхода назван"
mkdir -p "$TMP/h2"
bash "$AB/env-diff.sh" vanilla "$TMP/h2" >/dev/null 2>&1 && ok || bad "T3c" "чистая vanilla не прошла"

# --- T4: env-diff — full без знаний грязна ---
mkdir -p "$TMP/h3/.claude/hooks" && touch "$TMP/h3/.claude/hooks/x.sh" \
    && touch "$TMP/h3/.claude/CLAUDE.md" && echo '{}' > "$TMP/h3/.claude/settings.json"
OUT=$(bash "$AB/env-diff.sh" full "$TMP/h3" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T4" "full без базы знаний прошла"

# --- T4b: env-diff — core двусторонне: без знаний грязна, с хуками грязна, чистая проходит ---
mkdir -p "$TMP/c1/.claude/core" && touch "$TMP/c1/.claude/core/inject.py" \
    && echo '{}' > "$TMP/c1/.claude/settings.json"
OUT=$(bash "$AB/env-diff.sh" core "$TMP/c1" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T4b" "core без базы знаний прошла"
mkdir -p "$TMP/c2/.claude/core" "$TMP/c2/.claude/global-lessons" "$TMP/c2/.claude/hooks"
touch "$TMP/c2/.claude/core/inject.py" "$TMP/c2/.claude/hooks/x.sh"
echo '{}' > "$TMP/c2/.claude/settings.json"
OUT=$(bash "$AB/env-diff.sh" core "$TMP/c2" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T4c" "core с протёкшими хуками прошла"
assert_contains "$OUT" "протекли хуки" "T4d: протечка policy названа"
mkdir -p "$TMP/c3/.claude/core" "$TMP/c3/.claude/global-lessons"
touch "$TMP/c3/.claude/core/inject.py"; echo '{}' > "$TMP/c3/.claude/settings.json"
bash "$AB/env-diff.sh" core "$TMP/c3" >/dev/null 2>&1 && ok || bad "T4e" "чистая core не прошла"

# --- T5: dry-run пишет предзадачный признак, повтор запрещён ---
OUT=$(bash "$AB/dry-run-activator.sh" "$ID")
assert_contains "$OUT" '"would_surface"' "T5: признак вычислен"
assert_contains "$(cat "$ABLATION_DIR/journal.jsonl")" '"e":"dry_run"' "T5b: событие в журнале"
OUT=$(bash "$AB/dry-run-activator.sh" "$ID" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T5c" "повторный dry-run прошёл"

# --- T6: shadow-run --smoke строит песочницы обоих плеч без запуска агента ---
OUT=$(bash "$AB/shadow-run.sh" "$ID" vanilla --smoke)
assert_contains "$OUT" "env-diff чист" "T6: vanilla smoke"
assert_contains "$OUT" "claude" "T6b: команда плеча напечатана"
OUT=$(bash "$AB/shadow-run.sh" "$ID" full --smoke)
assert_contains "$OUT" "env-diff чист" "T6c: full smoke (runtime+знания из снимка)"
[ -f "$ABLATION_DIR/runs/$ID/full/home/.claude/hooks/knowledge-activator.sh" ] \
    && ok || bad "T6d" "runtime не распакован в full-песочницу"
# Core: та же база знаний, инжектор — есть; policy — нет. Обе стороны проверяются,
# потому что плечо задано и наличием знаний, и отсутствием структуры над ними.
OUT=$(bash "$AB/shadow-run.sh" "$ID" core --smoke)
assert_contains "$OUT" "env-diff чист" "T6e: core smoke"
CH="$ABLATION_DIR/runs/$ID/core/home/.claude"
[ -d "$CH/global-lessons" ]     && ok || bad "T6f" "в core-песочнице нет базы знаний"
[ -f "$CH/core/inject.py" ]     && ok || bad "T6g" "в core-песочнице нет инжектора"
[ -f "$CH/settings.json" ]      && ok || bad "T6h" "в core-песочнице нет settings.json"
[ ! -d "$CH/hooks" ]            && ok || bad "T6i" "в core-песочницу протекли хуки"
[ ! -f "$CH/CLAUDE.md" ]        && ok || bad "T6j" "в core-песочницу протекли глобальные правила"
OUT=$(bash "$AB/shadow-run.sh" "$ID" ядро --smoke 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T6k" "запускалка приняла несуществующее плечо"

# --- T7: повторный прогон того же плеча запрещён (повтор пары — целиком, §9) ---
OUT=$(bash "$AB/shadow-run.sh" "$ID" full --smoke 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T7" "повторный прогон плеча прошёл"

echo "test_ablation_runner: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
