#!/usr/bin/env bash
# test_quality_gate.sh — quality-gate-check.sh coverage.
# Изоляция через STATE_DIR + tmp git repo per test.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/quality-gate-check.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in output:"; echo "$haystack"; fi
}
assert_empty() {
    local actual="$1" label="$2"
    if [ -z "$actual" ] || [ "$actual" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected empty, got: $actual"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

# --- Setup helper: tmp git repo with skills/ tree ---
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

# Write a SKILL.md. Режимы соответствуют таблице «Обязательное» в docs/skill-contract.md.
#
# Главное про `valid`: чекбоксы Definition of Done в нём ПУСТЫЕ — ровно как предписывает
# контракт и как выглядят все 21 живой скилл. До v1.12.1 фикстура «complete» ставила
# `- [x]`, чего нет ни в одном реальном файле, и тест закреплял инверсию: страж горел
# на соблюдении контракта, а тест это подтверждал.
#
# $2 = valid | no_dod | no_version | no_updated | bad_type | changes_section | reference
write_skill() {
    local path="$1" mode="$2"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'EOF'
---
name: demo
description: "demo"
---

# Demo

**Type:** worker

## Step 1
Do stuff.

## Definition of Done

- [ ] First criterion
- [ ] Second criterion

**Version:** 1.0.0
**Last Updated:** 2026-04-23
EOF
    case "$mode" in
        valid) ;;
        no_dod)
            grep -v 'Definition of Done' "$path" | grep -v '^- \[ \]' > "$path.t" && mv "$path.t" "$path" ;;
        no_version)
            grep -v '^\*\*Version:\*\*' "$path" > "$path.t" && mv "$path.t" "$path" ;;
        no_updated)
            grep -v '^\*\*Last Updated:\*\*' "$path" > "$path.t" && mv "$path.t" "$path" ;;
        bad_type)
            sed 's/^\*\*Type:\*\* worker$/**Type:** helper/' "$path" > "$path.t" && mv "$path.t" "$path" ;;
        changes_section)
            printf '\n**Changes:** что-то поменяли\n' >> "$path" ;;
        reference)
            # reference — пассивная справка, требование DoD для неё номинально.
            sed 's/^\*\*Type:\*\* worker$/**Type:** reference/' "$path" \
                | grep -v 'Definition of Done' | grep -v '^- \[ \]' > "$path.t" && mv "$path.t" "$path" ;;
    esac
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
# T3: git commit но staged пуст → skip (R3 guard — no SKILL.md touched)
# ============================================================================
OUT=$(run_with "sid3" "$REPO" "git commit -m test")
assert_empty "$OUT" "T3: git commit без staged → skip"

# ============================================================================
# T4: staged docs-only (не SKILL.md) → skip (R3 guard)
# ============================================================================
echo "more" >> "$REPO/README.md"
git -C "$REPO" add README.md
OUT=$(run_with "sid4" "$REPO" "git commit -m docs")
assert_empty "$OUT" "T4: staged docs-only без SKILL.md → skip (R3 guard)"
git -C "$REPO" reset -q HEAD
git -C "$REPO" checkout -q -- .

# ============================================================================
# T5: контракт соблюдён, чекбоксы ПУСТЫЕ → молчать
#
# Регрессия на инверсию v1.5.6-v1.12.0: страж считал `- [ ]` признаком незавершённой
# работы и горел на каждом коммите со SKILL.md. Но контракт предписывает пустые
# чекбоксы — это runtime-чеклист исполнения скилла, а не задачи автора. Незакрыты
# во всех 21 живом скилле, ноль отмеченных примерно из 150.
# ============================================================================
write_skill "$REPO/skills/demo/SKILL.md" valid
git -C "$REPO" add skills/demo/SKILL.md
OUT=$(run_with "sid5" "$REPO" "git commit -m 'add demo skill'")
assert_empty "$OUT" "T5: пустые чекбоксы DoD — это норма контракта, не нарушение"
git -C "$REPO" reset -q HEAD
git -C "$REPO" checkout -q -- . 2>/dev/null || true
rm -rf "$REPO/skills/demo"

# ============================================================================
# T6: нарушения контракта → fire, с названной причиной
# ============================================================================
write_skill "$REPO/skills/demo/SKILL.md" no_version
git -C "$REPO" add skills/demo/SKILL.md
OUT=$(run_with "sid6" "$REPO" "git commit -m 'add demo skill'")
assert_contains "$OUT" "Quality-gate" "T6a: нет Version → fire"
assert_contains "$OUT" "skills/demo/SKILL.md" "T6b: путь скилла в inject"
assert_contains "$OUT" "нет **Version:**" "T6c: причина названа"

# ============================================================================
# T7: per-session dedup — тот же набор нарушений → skip
# ============================================================================
OUT=$(run_with "sid6" "$REPO" "git commit -m 'retry'")
assert_empty "$OUT" "T7: same session same problems → dedup"

# ============================================================================
# T8: другая сессия — fire снова
# ============================================================================
OUT=$(run_with "sid8" "$REPO" "git commit -m 'retry in new session'")
assert_contains "$OUT" "Quality-gate" "T8: cross-session independence"

# ============================================================================
# T9: CWD не git repo → skip
# ============================================================================
NONGIT="$TMP/nongit"
mkdir -p "$NONGIT"
OUT=$(run_with "sid9" "$NONGIT" "git commit -m x")
assert_empty "$OUT" "T9: не git repo → skip"

# ============================================================================
# T10: валидный JSON output
# ============================================================================
OUT=$(run_with "sid10" "$REPO" "git commit -m demo")
echo "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 \
    && { PASS=$((PASS+1)); } \
    || { FAIL=$((FAIL+1)); echo "FAIL [T10]: invalid JSON or wrong hookEventName: $OUT"; }

# ============================================================================
# T11: несколько SKILL.md — оба нарушают → оба в inject
# ============================================================================
REPO11="$TMP/repo11"
new_repo "$REPO11"
write_skill "$REPO11/skills/alpha/SKILL.md" no_version
write_skill "$REPO11/skills/beta/SKILL.md" no_dod
git -C "$REPO11" add skills/alpha/SKILL.md skills/beta/SKILL.md
OUT=$(run_with "sid11" "$REPO11" "git commit -m 'add two skills'")
assert_contains "$OUT" "skills/alpha/SKILL.md" "T11a: alpha в inject"
assert_contains "$OUT" "skills/beta/SKILL.md" "T11b: beta в inject"

# ============================================================================
# T12: один валидный, один нарушающий → только нарушающий в inject
# ============================================================================
REPO12="$TMP/repo12"
new_repo "$REPO12"
write_skill "$REPO12/skills/good/SKILL.md" valid
write_skill "$REPO12/skills/bad/SKILL.md" no_version
git -C "$REPO12" add skills/good/SKILL.md skills/bad/SKILL.md
OUT=$(run_with "sid12" "$REPO12" "git commit -m 'mixed'")
assert_contains "$OUT" "skills/bad/SKILL.md" "T12a: нарушающий в inject"
grep -Fq "skills/good/SKILL.md" <<< "$OUT" \
    && { FAIL=$((FAIL+1)); echo "FAIL [T12b]: валидный SKILL.md попал в inject"; } \
    || PASS=$((PASS+1))

# ============================================================================
# T18: остальные пункты контракта
# ============================================================================
REPO18="$TMP/repo18"
new_repo "$REPO18"
check_mode() {
    local mode="$1" needle="$2" label="$3"
    rm -rf "$REPO18/skills/x"
    write_skill "$REPO18/skills/x/SKILL.md" "$mode"
    git -C "$REPO18" add skills/x/SKILL.md
    local out; out=$(run_with "sid18-$mode" "$REPO18" "git commit -m t")
    assert_contains "$out" "$needle" "$label"
    git -C "$REPO18" reset -q HEAD
}
check_mode no_dod       "нет секции ## Definition of Done" "T18a: отсутствующая секция DoD"
check_mode no_updated   "нет **Last Updated:**"            "T18b: отсутствует Last Updated"
check_mode bad_type     "не из четырёх допустимых"         "T18c: Type вне словаря"
check_mode changes_section "**Changes:** запрещена"        "T18d: запрещённая секция Changes"

# === T19: reference без DoD → молчать (требование для него номинально) ===
rm -rf "$REPO18/skills/x"
write_skill "$REPO18/skills/x/SKILL.md" reference
git -C "$REPO18" add skills/x/SKILL.md
OUT=$(run_with "sid19" "$REPO18" "git commit -m t")
assert_empty "$OUT" "T19: reference без DoD — не нарушение"
git -C "$REPO18" reset -q HEAD

# ============================================================================
# T20: тело изменено, Version и Last Updated прежние → fire
#
# Главный практический сигнал стража. Ровно этот дрейф ловился руками: процедуру
# скилла правят, а версию в конце файла забывают.
# ============================================================================
REPO20="$TMP/repo20"
new_repo "$REPO20"
write_skill "$REPO20/skills/y/SKILL.md" valid
git -C "$REPO20" add skills/y/SKILL.md
git -C "$REPO20" commit -q -m "skill v1"

printf '\nНовый шаг процедуры.\n' >> "$REPO20/skills/y/SKILL.md"
git -C "$REPO20" add skills/y/SKILL.md
OUT=$(run_with "sid20" "$REPO20" "git commit -m 'правка без бампа'")
assert_contains "$OUT" "тело изменено, Version и Last Updated прежние" "T20a: дрейф версии пойман"

# Бампнули версию → молчит
sed -i.bak 's/^\*\*Version:\*\* 1.0.0$/**Version:** 1.1.0/' "$REPO20/skills/y/SKILL.md"
rm -f "$REPO20/skills/y/SKILL.md.bak"
git -C "$REPO20" add skills/y/SKILL.md
OUT=$(run_with "sid20b" "$REPO20" "git commit -m 'правка с бампом'")
assert_empty "$OUT" "T20b: после бампа версии страж молчит"

# ============================================================================
# T13: SKILL.md без DoD секции → fire
# Инверсия v1.12.1: раньше отсутствие секции означало «нечего проверять» и страж
# молчал. Но контракт требует секцию — её отсутствие и есть нарушение, тогда как
# незакрытые чекбоксы внутри неё нарушением не являются.
# ============================================================================
REPO13="$TMP/repo13"
new_repo "$REPO13"
write_skill "$REPO13/skills/nodod/SKILL.md" no_dod
git -C "$REPO13" add skills/nodod/SKILL.md
OUT=$(run_with "sid13" "$REPO13" "git commit -m 'no dod skill'")
assert_contains "$OUT" "нет секции ## Definition of Done" "T13: отсутствие секции DoD — нарушение"

# ============================================================================
# T14: git commit в compound команде → детектится
# ============================================================================
REPO14="$TMP/repo14"
new_repo "$REPO14"
write_skill "$REPO14/skills/comp/SKILL.md" no_version
git -C "$REPO14" add skills/comp/SKILL.md
OUT=$(run_with "sid14" "$REPO14" "git add . && git commit -m x")
assert_contains "$OUT" "Quality-gate" "T14: compound command matches"

# ============================================================================
# T15: empty/garbage input → silent
# ============================================================================
OUT=$(printf '' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T15a: empty input → empty output"

OUT=$(printf 'not-json' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T15b: garbage input → empty output"

# ============================================================================
# T16: только не-SKILL.md staged (например skills/demo/references/checks.md) → skip
# ============================================================================
REPO16="$TMP/repo16"
new_repo "$REPO16"
mkdir -p "$REPO16/skills/demo/references"
echo "# Checks" > "$REPO16/skills/demo/references/checks.md"
git -C "$REPO16" add skills/demo/references/checks.md
OUT=$(run_with "sid16" "$REPO16" "git commit -m 'update checks'")
assert_empty "$OUT" "T16: skills/*/references/*.md без SKILL.md → skip"

# ============================================================================
# T17: несколько нарушений в одном файле перечисляются все
# Раньше здесь считались незакрытые чекбоксы — число, которое ничего не значило,
# потому что во всех живых скиллах они незакрыты по предписанию контракта.
# ============================================================================
REPO17="$TMP/repo17"
new_repo "$REPO17"
mkdir -p "$REPO17/skills/triple"
cat > "$REPO17/skills/triple/SKILL.md" <<'EOF'
---
name: triple
---

## Definition of Done

- [ ] One
- [ ] Two
EOF
git -C "$REPO17" add skills/triple/SKILL.md
OUT=$(run_with "sid17" "$REPO17" "git commit -m triple")
assert_contains "$OUT" "нет **Type:**" "T17a: отсутствующий Type назван"
assert_contains "$OUT" "нет **Version:**" "T17b: отсутствующий Version назван"
assert_contains "$OUT" "нет **Last Updated:**" "T17c: отсутствующий Last Updated назван"

# ============================================================================
# Скилл с именем вне ASCII виден стражу.
#
# Имена каталогов у скиллов проекта наполовину русские (`противник`, `грилинг`).
# Git отдаёт такие пути в кавычках с восьмеричными escape
# ("skills/\320\277\321\200\320\276.../SKILL.md"), фильтр `^skills/[^/]+/SKILL\.md$`
# их не узнаёт — и страж молчал на двух живых скиллах из двадцати трёх. Молчание
# было структурно независимо от того, соблюдён ли контракт.
# Тот же дефект чинили в code-review-reminder 22.08; здесь он жил дальше.
# ============================================================================
REPO_NA="$TMP/repo-nonascii"
new_repo "$REPO_NA"
write_skill "$REPO_NA/skills/противник/SKILL.md" no_dod
git -C "$REPO_NA" add -A >/dev/null 2>&1
OUT=$(run_with "sid-nonascii" "$REPO_NA" "git commit -m x")
assert_contains "$OUT" "Definition of Done" "TNA: скилл с кириллицей в имени проверяется на контракт"

# Контрольный случай: тот же скилл, контракт соблюдён → страж молчит.
REPO_NA2="$TMP/repo-nonascii-ok"
new_repo "$REPO_NA2"
write_skill "$REPO_NA2/skills/противник/SKILL.md" valid
git -C "$REPO_NA2" add -A >/dev/null 2>&1
OUT=$(run_with "sid-nonascii-ok" "$REPO_NA2" "git commit -m x")
assert_empty "$OUT" "TNA2: тот же путь, контракт соблюдён → молчит"

echo ""
echo "=================================="
echo "quality-gate-check: $PASS passed, $FAIL failed"
echo "=================================="
[ "$FAIL" -eq 0 ]
