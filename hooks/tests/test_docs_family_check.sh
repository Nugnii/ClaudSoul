#!/usr/bin/env bash
# test_docs_family_check.sh — docs-family-check.sh coverage.
# Изоляция через STATE_DIR + tmp git repo per test.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/docs-family-check.sh"

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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

# --- Setup helper: new tmp git repo ---
new_repo() {
    local repo="$1"
    rm -rf "$repo"
    mkdir -p "$repo"
    git -C "$repo" init -q 2>/dev/null
    git -C "$repo" config user.email "t@e"
    git -C "$repo" config user.name "t"
    # Seed initial commit so diff --cached shows staged changes, not whole tree
    echo "# Init" > "$repo/README.md"
    echo "# Plan" > "$repo/PLAN.md"
    echo "# Changelog" > "$repo/CHANGELOG.md"
    echo "# Claude" > "$repo/CLAUDE.md"
    mkdir -p "$repo/docs"
    echo "# Arch" > "$repo/docs/architecture.md"
    git -C "$repo" add . >/dev/null 2>&1
    git -C "$repo" commit -q -m "seed" 2>/dev/null
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
# T3: git commit но staged пуст → skip
# ============================================================================
OUT=$(run_with "sid3" "$REPO" "git commit -m test")
assert_empty "$OUT" "T3: git commit без staged → skip"

# ============================================================================
# T4: staged без version marker → skip
# ============================================================================
echo "new content" >> "$REPO/README.md"
git -C "$REPO" add README.md
OUT=$(run_with "sid4" "$REPO" "git commit -m test")
assert_empty "$OUT" "T4: staged без version marker → skip"
git -C "$REPO" reset -q HEAD
git -C "$REPO" checkout -q -- .

# ============================================================================
# T5: version bump и вся docs family в stage → skip
# ============================================================================
for f in README.md PLAN.md CHANGELOG.md CLAUDE.md docs/architecture.md; do
    echo "v1.2.3-alpha update" >> "$REPO/$f"
done
git -C "$REPO" add . >/dev/null 2>&1
OUT=$(run_with "sid5" "$REPO" "git commit -m 'release v1.2.3'")
assert_empty "$OUT" "T5: full docs family staged → skip"
git -C "$REPO" reset -q HEAD
git -C "$REPO" checkout -q -- .

# ============================================================================
# T6: version bump с missing docs/architecture.md → fire
# ============================================================================
echo "v1.2.4-alpha bump" >> "$REPO/README.md"
echo "v1.2.4" >> "$REPO/CHANGELOG.md"
git -C "$REPO" add README.md CHANGELOG.md
OUT=$(run_with "sid6" "$REPO" "git commit -m 'release v1.2.4'")
assert_contains "$OUT" "Docs family drift" "T6a: version bump без полного family → fire"
assert_contains "$OUT" "docs/architecture.md" "T6b: architecture.md в missing"
assert_contains "$OUT" "PLAN.md" "T6c: PLAN.md в missing"
assert_contains "$OUT" "CLAUDE.md" "T6d: CLAUDE.md в missing"

# ============================================================================
# T7: per-session dedup — тот же diff → skip
# ============================================================================
OUT=$(run_with "sid6" "$REPO" "git commit -m 'release v1.2.4 retry'")
assert_empty "$OUT" "T7: same session same missing → dedup"

# ============================================================================
# T8: другая сессия — fire снова
# ============================================================================
OUT=$(run_with "sid8" "$REPO" "git commit -m 'release v1.2.4'")
assert_contains "$OUT" "Docs family drift" "T8: cross-session independence"

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
git -C "$REPO" reset -q HEAD
git -C "$REPO" checkout -q -- .
echo "v1.2.5-alpha" >> "$REPO/README.md"
git -C "$REPO" add README.md
OUT=$(run_with "sid10" "$REPO" "git commit -m v1.2.5")
echo "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 \
    && { PASS=$((PASS+1)); } \
    || { FAIL=$((FAIL+1)); echo "FAIL [T10]: invalid JSON or wrong hookEventName: $OUT"; }

# ============================================================================
# T11 (v1.6.2 — R3 false-positive fix): extras в docs/*.md НЕ учитываются по
# умолчанию. Frozen/archive docs (research, vision, analysis-*) не требуют
# bump'а при install-patch релизе. Расширение — через DOCS_FAMILY_LIST env.
# ============================================================================
REPO11="$TMP/repo11"
new_repo "$REPO11"
echo "# Extra doc" > "$REPO11/docs/research.md"
git -C "$REPO11" add docs/research.md
git -C "$REPO11" commit -q -m "add research doc"
echo "v1.3.0-alpha" >> "$REPO11/README.md"
echo "v1.3.0" >> "$REPO11/CHANGELOG.md"
echo "v1.3.0" >> "$REPO11/PLAN.md"
echo "v1.3.0" >> "$REPO11/CLAUDE.md"
echo "v1.3.0" >> "$REPO11/docs/architecture.md"
git -C "$REPO11" add README.md CHANGELOG.md PLAN.md CLAUDE.md docs/architecture.md
OUT=$(run_with "sid11" "$REPO11" "git commit -m v1.3.0")
echo "$OUT" | grep -Fq "docs/research.md" \
    && { FAIL=$((FAIL+1)); echo "FAIL [T11a]: docs/research.md не должен быть в missing при default DOCS_FAMILY (R3 false-positive)"; } \
    || PASS=$((PASS+1))
# При полном default family в stage — silent
assert_empty "$OUT" "T11b: full default family staged → silent, frozen docs/*.md игнорируются"

# ============================================================================
# T12: отсутствие jq/git — graceful exit (симулируем через empty command)
# ============================================================================
# Не можем легко мокнуть jq/git. Проверим что на broken JSON не падает.
OUT=$(printf '' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T12: empty input → empty output"

OUT=$(printf 'not-json' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T13: garbage input → empty output"

# ============================================================================
# T14: git commit в середине команды (compound) детектится
# ============================================================================
REPO14="$TMP/repo14"
new_repo "$REPO14"
echo "v1.4.0-alpha" >> "$REPO14/README.md"
git -C "$REPO14" add README.md
OUT=$(run_with "sid14" "$REPO14" "git add . && git commit -m x")
assert_contains "$OUT" "Docs family drift" "T14: compound command matches"

# ============================================================================
# T15: custom DOCS_FAMILY_LIST работает
# ============================================================================
REPO15="$TMP/repo15"
new_repo "$REPO15"
echo "v1.5.0" >> "$REPO15/README.md"
git -C "$REPO15" add README.md
payload=$(jq -cn \
    --arg sid "sid15" --arg cwd "$REPO15" --arg cmd "git commit -m x" \
    '{session_id: $sid, tool_name: "Bash", tool_input: {command: $cmd}, cwd: $cwd}')
OUT=$(printf '%s' "$payload" | \
    STATE_DIR="$STATE_DIR" DOCS_FAMILY_LIST="README.md CHANGELOG.md" \
    bash "$SCRIPT" 2>/dev/null)
assert_contains "$OUT" "CHANGELOG.md" "T15a: custom family — CHANGELOG в missing"
# PLAN.md не должен быть — не в custom list
echo "$OUT" | grep -Fq "PLAN.md" \
    && { FAIL=$((FAIL+1)); echo "FAIL [T15b]: PLAN.md появился в missing вне custom list"; } \
    || PASS=$((PASS+1))

# ============================================================================
# T16 (v1.6.2): DOCS_FAMILY_LIST расширяется на docs/*.md для проектов,
# которые хотят отслеживать конкретные docs/ файлы как live.
# ============================================================================
REPO16="$TMP/repo16"
new_repo "$REPO16"
echo "# Narrative" > "$REPO16/docs/narrative-design.md"
git -C "$REPO16" add docs/narrative-design.md
git -C "$REPO16" commit -q -m "add narrative design"
echo "v1.6.0" >> "$REPO16/README.md"
git -C "$REPO16" add README.md
payload16=$(jq -cn \
    --arg sid "sid16" --arg cwd "$REPO16" --arg cmd "git commit -m x" \
    '{session_id: $sid, tool_name: "Bash", tool_input: {command: $cmd}, cwd: $cwd}')
OUT=$(printf '%s' "$payload16" | \
    STATE_DIR="$STATE_DIR" DOCS_FAMILY_LIST="README.md docs/architecture.md docs/narrative-design.md" \
    bash "$SCRIPT" 2>/dev/null)
assert_contains "$OUT" "docs/narrative-design.md" "T16: custom DOCS_FAMILY_LIST ловит docs/narrative-design.md как live"

# ============================================================================
# T17-T19: проверка СОДЕРЖАНИЯ, а не только присутствия файла в коммите (v1.12.2)
#
# Релиз v1.12.1 прошёл этот страж молча: оба README были в diff, а изменена в них
# была одна строка с номером версии. Roadmap при этом обрывался на v1.7.0,
# английский README вообще не имел меток генератора и не обновлялся ни разу.
# Присутствие файла в коммите ничего не доказывает.
# ============================================================================
REPO17="$TMP/repo17"
new_repo "$REPO17"
# README должен УЖЕ вести версии, иначе с него нечего спрашивать: правило
# самонастраивающееся, чужой проект может держать README без номеров вовсе (см. T22).
echo "# Readme v1.8.0" > "$REPO17/README.md"
git -C "$REPO17" add README.md >/dev/null 2>&1
git -C "$REPO17" commit -q -m "readme с версией" 2>/dev/null

# Все члены семейства в diff, но README не упоминает выпускаемую версию.
printf '# Changelog\n\n## [1.9.0] - 2026-07-29\n' > "$REPO17/CHANGELOG.md"
echo "# Readme без номера новой версии, только v1.8.0" > "$REPO17/README.md"
echo "# Plan 1.9.0" > "$REPO17/PLAN.md"
echo "# Claude 1.9.0" > "$REPO17/CLAUDE.md"
echo "# Arch 1.9.0" > "$REPO17/docs/architecture.md"
git -C "$REPO17" add . >/dev/null 2>&1
OUT=$(run_with "sid17" "$REPO17" "git commit -m release")
assert_contains "$OUT" "нет упоминания" "T17: README в diff, но без номера версии → fire"

# T18: тот же коммит, но README номер несёт → страж молчит.
REPO18="$TMP/repo18"
new_repo "$REPO18"
printf '# Changelog\n\n## [1.9.0] - 2026-07-29\n' > "$REPO18/CHANGELOG.md"
echo "# Readme v1.9.0" > "$REPO18/README.md"
echo "# Plan 1.9.0" > "$REPO18/PLAN.md"
echo "# Claude 1.9.0" > "$REPO18/CLAUDE.md"
echo "# Arch 1.9.0" > "$REPO18/docs/architecture.md"
git -C "$REPO18" add . >/dev/null 2>&1
OUT=$(run_with "sid18" "$REPO18" "git commit -m release")
assert_empty "$OUT" "T18: номер версии на месте, автотаблиц нет → молчит"

# T19: есть метки автотаблицы, содержимое устарело → fire.
# Генератора в фикстуре нет — проверяем, что отсутствие генератора не роняет хук
# и не порождает ложную тревогу (страж стоит и в чужих проектах).
REPO19="$TMP/repo19"
new_repo "$REPO19"
printf '# Changelog\n\n## [1.9.0] - 2026-07-29\n' > "$REPO19/CHANGELOG.md"
printf '# Readme v1.9.0\n\n<!-- HOOKS-TABLE:START -->\nстарое\n<!-- HOOKS-TABLE:END -->\n' > "$REPO19/README.md"
echo "# Plan 1.9.0" > "$REPO19/PLAN.md"
echo "# Claude 1.9.0" > "$REPO19/CLAUDE.md"
echo "# Arch 1.9.0" > "$REPO19/docs/architecture.md"
git -C "$REPO19" add . >/dev/null 2>&1
OUT=$(run_with "sid19" "$REPO19" "git commit -m release")
assert_empty "$OUT" "T19: нет scripts/regen — ложной тревоги не создаём"

# ============================================================================
# T20-T22: содержание проверяется у ВСЕХ версионных документов, не только README
#
# Первая версия проверки содержания (v1.12.2) спрашивала только с README. Собеседник
# спросил «а плана и архитектуры?» — фикстура показала, что нет: PLAN.md и
# architecture.md проходили с любой мелкой правкой при версии позапрошлого релиза.
# Контрольный случай (файла нет в коммите вовсе) на том же дереве загорался, то есть
# фикстура была валидна, а молчание означало реальную дыру.
# ============================================================================
seed_versioned() {
    local r="$1" ver="$2"
    rm -rf "$r"; mkdir -p "$r/docs"
    git -C "$r" init -q 2>/dev/null
    git -C "$r" config user.email "t@e"; git -C "$r" config user.name "t"
    printf '# Readme v%s\n' "$ver" > "$r/README.md"
    printf '# Plan\n\n| Текущая версия | v%s |\n' "$ver" > "$r/PLAN.md"
    printf '# Arch\n\n> Покрывает через v%s\n' "$ver" > "$r/docs/architecture.md"
    printf '# Claude\n' > "$r/CLAUDE.md"
    printf '# Changelog\n' > "$r/CHANGELOG.md"
    git -C "$r" add . >/dev/null 2>&1
    git -C "$r" commit -q -m seed 2>/dev/null
}

REPO20="$TMP/repo20"
seed_versioned "$REPO20" "1.0.0"
printf '# Changelog\n\n## [1.1.0] - 2026-07-29\n' > "$REPO20/CHANGELOG.md"
printf '# Readme v1.1.0\n' > "$REPO20/README.md"
printf '# Claude\n\nправка\n' > "$REPO20/CLAUDE.md"
# PLAN и arch в коммите, но версия в них прежняя
printf '# Plan\n\n| Текущая версия | v1.0.0 |\n\nправка\n' > "$REPO20/PLAN.md"
printf '# Arch\n\n> Покрывает через v1.0.0\n\nправка\n' > "$REPO20/docs/architecture.md"
git -C "$REPO20" add . >/dev/null 2>&1
OUT=$(run_with "sid20" "$REPO20" "git commit -m release")
assert_contains "$OUT" "PLAN.md (нет упоминания" "T20a: устаревший PLAN.md пойман"
assert_contains "$OUT" "docs/architecture.md (нет упоминания" "T20b: устаревшая architecture.md поймана"

# T21: версии в них обновлены → страж молчит
REPO21="$TMP/repo21"
seed_versioned "$REPO21" "1.0.0"
printf '# Changelog\n\n## [1.1.0] - 2026-07-29\n' > "$REPO21/CHANGELOG.md"
printf '# Readme v1.1.0\n' > "$REPO21/README.md"
printf '# Claude\n\nправка\n' > "$REPO21/CLAUDE.md"
printf '# Plan\n\n| Текущая версия | v1.1.0 |\n' > "$REPO21/PLAN.md"
printf '# Arch\n\n> Покрывает через v1.1.0\n' > "$REPO21/docs/architecture.md"
git -C "$REPO21" add . >/dev/null 2>&1
OUT=$(run_with "sid21" "$REPO21" "git commit -m release")
assert_empty "$OUT" "T21: версии обновлены во всех документах → молчит"

# T22: документ, который НИКОГДА не вёл версий, не требуют — хук стоит и в чужих
# проектах, где PLAN.md может быть обычным списком задач без номеров.
REPO22="$TMP/repo22"
seed_versioned "$REPO22" "1.0.0"
printf '# Plan без версий\n\nсписок задач\n' > "$REPO22/PLAN.md"
git -C "$REPO22" add . >/dev/null 2>&1
git -C "$REPO22" commit -q -m "plan без версий" 2>/dev/null
printf '# Changelog\n\n## [1.1.0] - 2026-07-29\n' > "$REPO22/CHANGELOG.md"
printf '# Readme v1.1.0\n' > "$REPO22/README.md"
printf '# Claude\n\nправка\n' > "$REPO22/CLAUDE.md"
printf '# Plan без версий\n\nсписок задач\n\nещё пункт\n' > "$REPO22/PLAN.md"
printf '# Arch\n\n> Покрывает через v1.1.0\n' > "$REPO22/docs/architecture.md"
git -C "$REPO22" add . >/dev/null 2>&1
OUT=$(run_with "sid22" "$REPO22" "git commit -m release")
assert_empty "$OUT" "T22: документ без истории версий не требуют"

echo ""
echo "=================================="
echo "docs-family-check: $PASS passed, $FAIL failed"
echo "=================================="
[ "$FAIL" -eq 0 ]
