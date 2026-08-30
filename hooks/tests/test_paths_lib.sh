#!/usr/bin/env bash
# test_paths_lib.sh — характеризующий тест для общего paths-lib.sh.
# Наполняется инкрементально вместе с TASK-003. Сейчас покрывает CLAUDSOUL_ROOT (003a)
# и порядок его резолва env → ~/.claude/claudsoul-repo → дефолт (D72).
# Ключевой контракт: lib уважает уже заданное окружение (тесты переопределяют пути),
# а без env даёт канонический дефолт.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATHS_LIB="${PATHS_LIB:-$HOOKS_DIR/paths-lib.sh}"

[ -f "$PATHS_LIB" ] || { echo "FAIL: $PATHS_LIB not found"; exit 1; }

PASS=0
FAIL=0
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}

# --- CLAUDSOUL_ROOT: порядок резолва env → файл-указатель → дефолт ---
# HOME подменяется в каждом подоболочечном прогоне: на машине автора настоящий
# ~/.claude/claudsoul-repo существует, и без подмены тест дефолта проверял бы не то,
# что называет. Порядок повторяет bin/resolve-claudsoul-repo.sh — единственное отличие
# в том, что здесь нет проверки на mcp-server/ingest: хуку корень нужен и без MCP.
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.claude"

got=$(unset CLAUDSOUL_ROOT; HOME="$FAKE_HOME"; source "$PATHS_LIB"; printf '%s' "$CLAUDSOUL_ROOT")
assert_eq "$got" "$FAKE_HOME/My Project/ClaudSoul" "T1: CLAUDSOUL_ROOT default when no pointer"

# --- CLAUDSOUL_ROOT: файл-указатель, записанный install.sh, побеждает дефолт (D72) ---
mkdir -p "$FAKE_HOME/elsewhere/ClaudSoul"
echo "$FAKE_HOME/elsewhere/ClaudSoul" > "$FAKE_HOME/.claude/claudsoul-repo"
got=$(unset CLAUDSOUL_ROOT; HOME="$FAKE_HOME"; source "$PATHS_LIB"; printf '%s' "$CLAUDSOUL_ROOT")
assert_eq "$got" "$FAKE_HOME/elsewhere/ClaudSoul" "T1b: pointer file wins over default"

# --- CLAUDSOUL_ROOT: env сильнее указателя (явный override остаётся сильнейшим) ---
got=$(export CLAUDSOUL_ROOT="/explicit"; HOME="$FAKE_HOME"; source "$PATHS_LIB"; printf '%s' "$CLAUDSOUL_ROOT")
assert_eq "$got" "/explicit" "T1c: env beats pointer file"

# --- CLAUDSOUL_ROOT: указатель на несуществующий каталог откатывается к дефолту ---
# Иначе битый указатель тихо увёл бы все пути в никуда — тот же класс молчаливой смерти,
# ради которого пункт и заводился.
echo "$FAKE_HOME/no/such/dir" > "$FAKE_HOME/.claude/claudsoul-repo"
got=$(unset CLAUDSOUL_ROOT; HOME="$FAKE_HOME"; source "$PATHS_LIB"; printf '%s' "$CLAUDSOUL_ROOT")
assert_eq "$got" "$FAKE_HOME/My Project/ClaudSoul" "T1d: stale pointer falls back to default"

# --- CLAUDSOUL_ROOT: пустой указатель тоже откатывается ---
: > "$FAKE_HOME/.claude/claudsoul-repo"
got=$(unset CLAUDSOUL_ROOT; HOME="$FAKE_HOME"; source "$PATHS_LIB"; printf '%s' "$CLAUDSOUL_ROOT")
assert_eq "$got" "$FAKE_HOME/My Project/ClaudSoul" "T1e: empty pointer falls back to default"
rm -f "$FAKE_HOME/.claude/claudsoul-repo"

# --- CLAUDSOUL_ROOT: env override is respected (not overwritten by lib) ---
got=$(export CLAUDSOUL_ROOT="/custom/soul"; source "$PATHS_LIB"; printf '%s' "$CLAUDSOUL_ROOT")
assert_eq "$got" "/custom/soul" "T2: CLAUDSOUL_ROOT env override respected"

# --- LESSONS_DIR: default + override (003d) ---
got=$(unset LESSONS_DIR; source "$PATHS_LIB"; printf '%s' "$LESSONS_DIR")
assert_eq "$got" "$HOME/.claude/global-lessons" "T2b: LESSONS_DIR default"
got=$(export LESSONS_DIR="/custom/lessons"; source "$PATHS_LIB"; printf '%s' "$LESSONS_DIR")
assert_eq "$got" "/custom/lessons" "T2c: LESSONS_DIR env override respected"

# --- STATE_DIR: default + override (003e) ---
got=$(unset STATE_DIR; source "$PATHS_LIB"; printf '%s' "$STATE_DIR")
assert_eq "$got" "$HOME/.claude/hooks/state" "T2d: STATE_DIR default"
got=$(export STATE_DIR="/custom/state"; source "$PATHS_LIB"; printf '%s' "$STATE_DIR")
assert_eq "$got" "/custom/state" "T2e: STATE_DIR env override respected (not clobbered)"

# --- sourcing twice is idempotent (no clobber on second source) ---
got=$(export CLAUDSOUL_ROOT="/once"; source "$PATHS_LIB"; source "$PATHS_LIB"; printf '%s' "$CLAUDSOUL_ROOT")
assert_eq "$got" "/once" "T3: idempotent re-source keeps value"

# --- find_project_root (003b): walk up to .git / CLAUDE.md ---
source "$PATHS_LIB"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/proj/.git" "$TMP/proj/sub/deep"
assert_eq "$(find_project_root "$TMP/proj/sub/deep")" "$TMP/proj" "T4: walk up to .git from subdir"

mkdir -p "$TMP/proj2/sub"; : > "$TMP/proj2/CLAUDE.md"
assert_eq "$(find_project_root "$TMP/proj2/sub")" "$TMP/proj2" "T5: walk up to CLAUDE.md from subdir"

# no marker anywhere up to / → fallback to the start dir
mkdir -p "$TMP/orphan/x"
got=$(find_project_root "$TMP/orphan/x")
assert_eq "$got" "$TMP/orphan/x" "T6: fallback to start dir when no marker"

# root itself is a project root
assert_eq "$(find_project_root "$TMP/proj")" "$TMP/proj" "T7: dir with .git is its own root"

# --- resolve_session_id (003c): unify parse, keep fallback per caller ---
if command -v jq >/dev/null 2>&1; then
    assert_eq "$(resolve_session_id '{"session_id":"abc123"}')" "abc123" "T8: parses session_id"
    assert_eq "$(resolve_session_id '{}')" "unknown" "T9: default fallback when absent"
    assert_eq "$(resolve_session_id '{}' '')" "" "T10: empty fallback for exit-style hooks"
    assert_eq "$(resolve_session_id 'not json')" "unknown" "T11: invalid json → fallback"
    assert_eq "$(resolve_session_id '{"session_id":"x"}' '')" "x" "T12: valid sid ignores fallback"
else
    PASS=$((PASS + 5))
fi

echo ""
echo "paths-lib tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
