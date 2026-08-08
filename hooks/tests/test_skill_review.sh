#!/usr/bin/env bash
# test_skill_review.sh — skill-review-check.sh coverage.
# Contract integrity (frontmatter/Type/DoD/Version/Last Updated/line count/no Changes).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/skill-review-check.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}
assert_empty() {
    local actual="$1" label="$2"
    if [ -z "$actual" ] || [ "$actual" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected empty, got: $actual"; fi
}
assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then
        FAIL=$((FAIL + 1)); echo "FAIL [$label]: unexpected '$needle' in output:"; echo "$haystack"
    else PASS=$((PASS + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

new_repo() {
    local repo="$1"
    rm -rf "$repo"
    mkdir -p "$repo/skills/demo"
    git -C "$repo" init -q 2>/dev/null
    git -C "$repo" config user.email "t@e"
    git -C "$repo" config user.name "t"
    echo "# Seed" > "$repo/README.md"
    git -C "$repo" add README.md >/dev/null 2>&1
    git -C "$repo" commit -q -m "seed" 2>/dev/null
}

# Writes a valid SKILL.md (contract-compliant) baseline.
write_valid_skill() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'EOF'
---
name: demo
description: "demo skill for tests"
user-invocable: true
---

# Demo

**Type:** worker

## Step 1
Do stuff.

## Definition of Done

- [x] Criterion met

**Version:** 1.0.0
**Last Updated:** 2026-04-23
EOF
}

run_with() {
    local sid="$1" cwd="$2" command="$3" tool="${4:-Bash}"
    local payload
    payload=$(jq -cn \
        --arg sid "$sid" --arg cwd "$cwd" --arg cmd "$command" --arg tool "$tool" \
        '{session_id: $sid, tool_name: $tool, tool_input: {command: $cmd}, cwd: $cwd}')
    printf '%s' "$payload" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null
}

# ============================================================================
# T1: tool_name != Bash → skip
# ============================================================================
REPO="$TMP/repo1"
new_repo "$REPO"
OUT=$(run_with "sid1" "$REPO" "git commit -m test" "Edit")
assert_empty "$OUT" "T1: non-Bash tool → skip"

# ============================================================================
# T2: Bash но не git commit → skip
# ============================================================================
OUT=$(run_with "sid2" "$REPO" "ls -la")
assert_empty "$OUT" "T2: Bash без git commit → skip"

# ============================================================================
# T3: git commit но staged пуст (no SKILL.md) → skip
# ============================================================================
OUT=$(run_with "sid3" "$REPO" "git commit -m test")
assert_empty "$OUT" "T3: git commit без staged SKILL.md → skip"

# ============================================================================
# T4: staged docs-only (не SKILL.md) → skip
# ============================================================================
echo "more" >> "$REPO/README.md"
git -C "$REPO" add README.md
OUT=$(run_with "sid4" "$REPO" "git commit -m docs")
assert_empty "$OUT" "T4: staged docs-only → skip"
git -C "$REPO" reset -q HEAD
git -C "$REPO" checkout -q -- .

# ============================================================================
# T5: valid SKILL.md → skip (contract OK)
# ============================================================================
write_valid_skill "$REPO/skills/demo/SKILL.md"
git -C "$REPO" add skills/demo/SKILL.md
OUT=$(run_with "sid5" "$REPO" "git commit -m 'add valid skill'")
assert_empty "$OUT" "T5: valid contract → skip"
git -C "$REPO" reset -q HEAD
rm -rf "$REPO/skills/demo"

# ============================================================================
# T6: missing frontmatter (no --- on line 1) → fire
# ============================================================================
REPO6="$TMP/repo6"
new_repo "$REPO6"
mkdir -p "$REPO6/skills/nofm"
cat > "$REPO6/skills/nofm/SKILL.md" <<'EOF'
# No Frontmatter

**Type:** worker

## Definition of Done
- [x] x

**Version:** 1.0.0
**Last Updated:** 2026-04-23
EOF
git -C "$REPO6" add skills/nofm/SKILL.md
OUT=$(run_with "sid6" "$REPO6" "git commit -m no-fm")
assert_contains "$OUT" "Skill-review" "T6a: missing_frontmatter → fire"
assert_contains "$OUT" "missing_frontmatter" "T6b: violation label in inject"
assert_contains "$OUT" "skills/nofm/SKILL.md" "T6c: skill path in inject"

# ============================================================================
# T7: missing name field → fire
# ============================================================================
REPO7="$TMP/repo7"
new_repo "$REPO7"
mkdir -p "$REPO7/skills/noname"
cat > "$REPO7/skills/noname/SKILL.md" <<'EOF'
---
description: "no name field here"
user-invocable: true
---

**Type:** worker

## Definition of Done
- [x] x

**Version:** 1.0.0
**Last Updated:** 2026-04-23
EOF
git -C "$REPO7" add skills/noname/SKILL.md
OUT=$(run_with "sid7" "$REPO7" "git commit -m no-name")
assert_contains "$OUT" "missing_name" "T7: missing_name → fire"

# ============================================================================
# T8: description too long → fire
#
# Порог — платформенный лимит 1024, а не прежние 200. Те 200 были самоограничением из
# чужого репозитория, и подгонка под них однажды вырезала из описаний фразы автовызова.
# Фикстура берёт заведомо больше лимита, а не «больше выдуманного числа».
# ============================================================================
REPO8="$TMP/repo8"
new_repo "$REPO8"
mkdir -p "$REPO8/skills/longdesc"
LONG_DESC=$(printf 'a%.0s' {1..1100})
cat > "$REPO8/skills/longdesc/SKILL.md" <<EOF
---
name: longdesc
description: "$LONG_DESC"
user-invocable: true
---

**Type:** worker

## Definition of Done
- [x] x

**Version:** 1.0.0
**Last Updated:** 2026-04-23
EOF
git -C "$REPO8" add skills/longdesc/SKILL.md
OUT=$(run_with "sid8" "$REPO8" "git commit -m long-desc")
assert_contains "$OUT" "desc_too_long" "T8: desc_too_long → fire"

# ============================================================================
# T9: missing user-invocable → fire
# ============================================================================
REPO9="$TMP/repo9"
new_repo "$REPO9"
mkdir -p "$REPO9/skills/noui"
cat > "$REPO9/skills/noui/SKILL.md" <<'EOF'
---
name: noui
description: "no user-invocable"
---

**Type:** worker

## Definition of Done
- [x] x

**Version:** 1.0.0
**Last Updated:** 2026-04-23
EOF
git -C "$REPO9" add skills/noui/SKILL.md
OUT=$(run_with "sid9" "$REPO9" "git commit -m no-ui")
assert_contains "$OUT" "missing_user_invocable" "T9: missing_user_invocable → fire"

# ============================================================================
# T10: missing **Type:** worker → fire
# ============================================================================
REPO10="$TMP/repo10"
new_repo "$REPO10"
mkdir -p "$REPO10/skills/notype"
cat > "$REPO10/skills/notype/SKILL.md" <<'EOF'
---
name: notype
description: "no type"
user-invocable: true
---

# NoType

## Definition of Done
- [x] x

**Version:** 1.0.0
**Last Updated:** 2026-04-23
EOF
git -C "$REPO10" add skills/notype/SKILL.md
OUT=$(run_with "sid10" "$REPO10" "git commit -m no-type")
assert_contains "$OUT" "missing_type" "T10: missing_type → fire"

# ============================================================================
# T11: missing ## Definition of Done → fire
# ============================================================================
REPO11="$TMP/repo11"
new_repo "$REPO11"
mkdir -p "$REPO11/skills/nodod"
cat > "$REPO11/skills/nodod/SKILL.md" <<'EOF'
---
name: nodod
description: "no DoD"
user-invocable: true
---

**Type:** worker

## Step 1
stuff

**Version:** 1.0.0
**Last Updated:** 2026-04-23
EOF
git -C "$REPO11" add skills/nodod/SKILL.md
OUT=$(run_with "sid11" "$REPO11" "git commit -m no-dod")
assert_contains "$OUT" "missing_dod" "T11: missing_dod → fire"

# ============================================================================
# T12: missing **Version:** in tail → fire
# ============================================================================
REPO12="$TMP/repo12"
new_repo "$REPO12"
mkdir -p "$REPO12/skills/nover"
cat > "$REPO12/skills/nover/SKILL.md" <<'EOF'
---
name: nover
description: "no version"
user-invocable: true
---

**Type:** worker

## Definition of Done
- [x] x

**Last Updated:** 2026-04-23
EOF
git -C "$REPO12" add skills/nover/SKILL.md
OUT=$(run_with "sid12" "$REPO12" "git commit -m no-ver")
assert_contains "$OUT" "missing_version" "T12: missing_version → fire"

# ============================================================================
# T13: missing **Last Updated:** in tail → fire
# ============================================================================
REPO13="$TMP/repo13"
new_repo "$REPO13"
mkdir -p "$REPO13/skills/nolu"
cat > "$REPO13/skills/nolu/SKILL.md" <<'EOF'
---
name: nolu
description: "no last-updated"
user-invocable: true
---

**Type:** worker

## Definition of Done
- [x] x

**Version:** 1.0.0
EOF
git -C "$REPO13" add skills/nolu/SKILL.md
OUT=$(run_with "sid13" "$REPO13" "git commit -m no-lu")
assert_contains "$OUT" "missing_last_updated" "T13: missing_last_updated → fire"

# ============================================================================
# T14: >400 lines → fire with too_long
# ============================================================================
REPO14="$TMP/repo14"
new_repo "$REPO14"
mkdir -p "$REPO14/skills/huge"
{
    echo "---"
    echo "name: huge"
    echo "description: huge"
    echo "user-invocable: true"
    echo "---"
    echo ""
    echo "**Type:** worker"
    echo ""
    echo "## Definition of Done"
    echo "- [x] x"
    echo ""
    for i in $(seq 1 500); do echo "Line $i filler content here"; done
    echo "**Version:** 1.0.0"
    echo "**Last Updated:** 2026-04-23"
} > "$REPO14/skills/huge/SKILL.md"
git -C "$REPO14" add skills/huge/SKILL.md
OUT=$(run_with "sid14" "$REPO14" "git commit -m huge")
assert_contains "$OUT" "too_long" "T14: too_long → fire"

# ============================================================================
# T15: **Changes:** section present → fire
# ============================================================================
REPO15="$TMP/repo15"
new_repo "$REPO15"
mkdir -p "$REPO15/skills/withchanges"
cat > "$REPO15/skills/withchanges/SKILL.md" <<'EOF'
---
name: withchanges
description: "has changes section"
user-invocable: true
---

**Type:** worker

## Definition of Done
- [x] x

**Changes:**
- v1.0.1: bugfix
- v1.0.0: initial

**Version:** 1.0.1
**Last Updated:** 2026-04-23
EOF
git -C "$REPO15" add skills/withchanges/SKILL.md
OUT=$(run_with "sid15" "$REPO15" "git commit -m with-changes")
assert_contains "$OUT" "has_changes_section" "T15: has_changes_section → fire"

# ============================================================================
# T16: per-session dedup — same violations → skip second time
# ============================================================================
OUT=$(run_with "sid15" "$REPO15" "git commit -m retry")
assert_empty "$OUT" "T16: same session same violations → dedup"

# ============================================================================
# T17: cross-session — new session fires again
# ============================================================================
OUT=$(run_with "sid15-other" "$REPO15" "git commit -m retry-new-session")
assert_contains "$OUT" "Skill-review" "T17: cross-session independence"

# ============================================================================
# T18: valid JSON output with hookEventName
# ============================================================================
REPO18="$TMP/repo18"
new_repo "$REPO18"
mkdir -p "$REPO18/skills/partial"
cat > "$REPO18/skills/partial/SKILL.md" <<'EOF'
---
description: "partial"
---

Body.
EOF
git -C "$REPO18" add skills/partial/SKILL.md
OUT=$(run_with "sid18" "$REPO18" "git commit -m partial")
echo "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 \
    && { PASS=$((PASS+1)); } \
    || { FAIL=$((FAIL+1)); echo "FAIL [T18]: invalid JSON or wrong hookEventName: $OUT"; }

# ============================================================================
# T19: multiple SKILL.md — mixed (one valid, one invalid) → only invalid in inject
# ============================================================================
REPO19="$TMP/repo19"
new_repo "$REPO19"
write_valid_skill "$REPO19/skills/good/SKILL.md"
mkdir -p "$REPO19/skills/bad"
cat > "$REPO19/skills/bad/SKILL.md" <<'EOF'
---
name: bad
description: "bad"
user-invocable: true
---

Body without type/dod/version.
EOF
git -C "$REPO19" add skills/good/SKILL.md skills/bad/SKILL.md
OUT=$(run_with "sid19" "$REPO19" "git commit -m mixed")
assert_contains "$OUT" "skills/bad/SKILL.md" "T19a: bad skill in inject"
assert_not_contains "$OUT" "skills/good/SKILL.md" "T19b: good skill not in inject"

# ============================================================================
# T20: empty/garbage input → silent
# ============================================================================
OUT=$(printf '' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T20a: empty input → silent"

OUT=$(printf 'not-json' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T20b: garbage input → silent"

# ============================================================================
# T21: не git repo → skip
# ============================================================================
NONGIT="$TMP/nongit"
mkdir -p "$NONGIT"
OUT=$(run_with "sid21" "$NONGIT" "git commit -m x")
assert_empty "$OUT" "T21: не git repo → skip"

# ============================================================================
# T22: compound command (git add && git commit) → detected
# ============================================================================
REPO22="$TMP/repo22"
new_repo "$REPO22"
mkdir -p "$REPO22/skills/comp"
cat > "$REPO22/skills/comp/SKILL.md" <<'EOF'
---
description: "compound test"
---
Body.
EOF
git -C "$REPO22" add skills/comp/SKILL.md
OUT=$(run_with "sid22" "$REPO22" "git add . && git commit -m x")
assert_contains "$OUT" "Skill-review" "T22: compound command matches"

# ============================================================================
# T23: SKILL.md не в корне skills/*/SKILL.md (nested) → skip
# ============================================================================
REPO23="$TMP/repo23"
new_repo "$REPO23"
mkdir -p "$REPO23/skills/demo/references"
cat > "$REPO23/skills/demo/references/SKILL.md" <<'EOF'
Not a real skill.
EOF
git -C "$REPO23" add skills/demo/references/SKILL.md
OUT=$(run_with "sid23" "$REPO23" "git commit -m nested")
assert_empty "$OUT" "T23: nested SKILL.md (skills/X/Y/SKILL.md) → skip"

# ============================================================================
# T24-T26: область — ИНДЕКС, а не рабочее дерево (D42)
# ============================================================================
# Шапка хука заявляет областью staged diff, а `check_contract` читал `$CWD/$rel`.
# Проба на подложенном случае показала промах: переименованное в индексе поле оставалось
# незамеченным, потому что рабочий файл был цел. `quality-gate-check.sh:107` делает это
# правильно (`git show ":$rel"`) — асимметрия двух стражей по одному предмету.
REPO24="$TMP/repo24"
new_repo "$REPO24"
write_valid_skill "$REPO24/skills/demo/SKILL.md"
git -C "$REPO24" add skills/demo/SKILL.md >/dev/null 2>&1
git -C "$REPO24" commit -q -m "valid skill" 2>/dev/null

# В ИНДЕКС кладём сломанное, рабочий файл оставляем целым.
cp "$REPO24/skills/demo/SKILL.md" "$TMP/keep-valid.md"
printf 'нет frontmatter вовсе\n' > "$REPO24/skills/demo/SKILL.md"
git -C "$REPO24" add skills/demo/SKILL.md >/dev/null 2>&1
cp "$TMP/keep-valid.md" "$REPO24/skills/demo/SKILL.md"     # рабочий файл снова целый

OUT=$(run_with "sid24" "$REPO24" "git commit -m broken-in-index")
assert_contains "$OUT" "missing_frontmatter" "T24: нарушение В ИНДЕКСЕ поймано, хотя рабочий файл цел"

# Обратная сторона: сломан рабочий файл, а в индекс уходит целый — молчим.
REPO25="$TMP/repo25"
new_repo "$REPO25"
write_valid_skill "$REPO25/skills/demo/SKILL.md"
git -C "$REPO25" add skills/demo/SKILL.md >/dev/null 2>&1
printf 'мусор только в рабочем дереве\n' > "$REPO25/skills/demo/SKILL.md"
OUT=$(run_with "sid25" "$REPO25" "git commit -m clean-in-index")
assert_empty "$OUT" "T25: правка вне индекса не считается нарушением коммита"

# ============================================================================
# T26-T28: сплошной обход (D42)
# ============================================================================
# Хук видит только staged diff, поэтому скилл, которого давно не касаются, не проверялся
# НИКОГДА. Класс уже кусал: коммит c662f0a сообщает, что четыре нарушения длины описания
# пролежали месяцами именно потому, что файлы не попадали в коммит.
REPO26="$TMP/repo26"
new_repo "$REPO26"
write_valid_skill "$REPO26/skills/demo/SKILL.md"
OUT=$(CLAUDSOUL_REPO="$REPO26" bash "$SCRIPT" sweep < /dev/null 2>&1); RC=$?
assert_contains "$OUT" "нарушений нет" "T26: здоровое дерево — обход молчит"
[ "$RC" -eq 0 ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T26b]: здоровый обход вернул $RC"; }

mkdir -p "$REPO26/skills/broken"
printf 'без контракта\n' > "$REPO26/skills/broken/SKILL.md"
OUT=$(CLAUDSOUL_REPO="$REPO26" bash "$SCRIPT" sweep < /dev/null 2>&1); RC=$?
assert_contains "$OUT" "skills/broken/SKILL.md" "T27: нарушитель назван поимённо"
[ "$RC" -ne 0 ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T27b]: обход с нарушением вернул 0"; }

# T28: обход НЕ зависит от git — иначе он проверял бы то же, что и staged-путь.
# Без этого случая «обход» мог бы молча пропускать всё в дереве без индекса.
rm -rf "$REPO26/.git"
OUT=$(CLAUDSOUL_REPO="$REPO26" bash "$SCRIPT" sweep < /dev/null 2>&1)
assert_contains "$OUT" "skills/broken/SKILL.md" "T28: обход работает и без git — он про файлы, не про коммит"

# T29: у обхода есть срок — иначе это снова обязанность, которую надо вспомнить.
if grep -q '^skill-contract' "$HOOKS_DIR/../scripts/measurements.tsv" 2>/dev/null; then
    PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T29]: обхода нет в реестре замеров"; fi


echo ""
echo "=================================="
echo "skill-review-check: $PASS passed, $FAIL failed"
echo "=================================="
[ "$FAIL" -eq 0 ]
