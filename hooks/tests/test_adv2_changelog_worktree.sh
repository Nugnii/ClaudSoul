#!/usr/bin/env bash
# test_adv2_changelog_worktree.sh — CHANGELOG_TOUCHED гасит напоминание по грязному
# рабочему дереву, даже когда CHANGELOG.md заведомо не может попасть в коммит.
#
# Атака. Гашение расширили на `git diff --name-only` (рабочее дерево), чтобы не терять
# случай `git add -A && git commit`. Но «файл правлен» и «файл уйдёт в этот коммит» —
# разные утверждения. Команда с явным pathspec их разводит однозначно:
#     git commit -m "fix" hooks/demo.sh
# такой коммит содержит РОВНО hooks/demo.sh, что бы ни лежало в индексе и в дереве.
# Правленый, но не добавленный CHANGELOG.md гасит стража — и код уезжает без записи.
# Команда хуку известна целиком (`$COMMAND`), pathspec в ней виден.
#
# Второй случай: обычный `git commit -m` при staged-коде и CHANGELOG.md, который
# правлен, но не добавлен — коммит опять уходит без CHANGELOG, страж опять молчит.
#
# Контроль: тот же коммит при ЧИСТОМ CHANGELOG.md — страж срабатывает.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/changelog-reminder.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_repo() {   # make_repo <dirty_changelog: yes|no>
    local repo="$TMP/repo"
    rm -rf "$repo"; mkdir -p "$repo/hooks"
    printf '# Changelog\n\n## [Unreleased]\n' > "$repo/CHANGELOG.md"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/hooks/demo.sh"
    ( cd "$repo" && git init -q . && git config user.email adv@test && git config user.name adv \
        && git add -A && git commit -qm init )
    # правка кода — в индексе
    printf '#!/usr/bin/env bash\n# новое поведение\nexit 0\n' > "$repo/hooks/demo.sh"
    ( cd "$repo" && git add hooks/demo.sh )
    # правка CHANGELOG — только в рабочем дереве, в индекс НЕ добавлена
    if [ "$1" = "yes" ]; then
        printf '# Changelog\n\n## [Unreleased]\n- заготовка под будущий коммит\n' > "$repo/CHANGELOG.md"
    fi
    printf '%s' "$repo"
}

run_hook() {   # run_hook <repo> <command>
    rm -rf "$TMP/state"; mkdir -p "$TMP/state" "$TMP/home"
    printf '{"session_id":"adv2-%s","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' \
        "$RANDOM" "$2" "$1" \
        | env HOME="$TMP/home" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

check() {   # check <label> <output>
    local label="$1" out="$2"
    if grep -qF 'CHANGELOG' <<< "$out"; then
        PASS=$((PASS + 1)); echo "PASS [$label]"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: страж промолчал"
        echo "       вывод хука: ${out:-<пусто>}"
    fi
}

# ── контроль: CHANGELOG.md чист, коммит только с кодом ───────────────────────
REPO=$(make_repo no)
check "контроль: чистый CHANGELOG, git commit -m — страж напоминает" \
    "$(run_hook "$REPO" 'git commit -m fix')"

# ── атака 1: коммит с явным pathspec ─────────────────────────────────────────
REPO=$(make_repo yes)
OUT=$(run_hook "$REPO" 'git commit -m fix hooks/demo.sh')
( cd "$REPO" && git commit -qm fix hooks/demo.sh )
COMMITTED=$( cd "$REPO" && git show --name-only --format= HEAD )
if grep -qxF 'CHANGELOG.md' <<< "$COMMITTED"; then
    echo "SETUP-FAIL: CHANGELOG.md всё же попал в коммит — предпосылка теста неверна"
    FAIL=$((FAIL + 1))
else
    check "атака 1: git commit -m fix hooks/demo.sh — коммит без CHANGELOG ($(printf '%s' "$COMMITTED" | tr '\n' ' '))" "$OUT"
fi

# ── атака 2: обычный коммит, CHANGELOG правлен но не добавлен ────────────────
REPO=$(make_repo yes)
OUT=$(run_hook "$REPO" 'git commit -m fix')
( cd "$REPO" && git commit -qm fix )
COMMITTED=$( cd "$REPO" && git show --name-only --format= HEAD )
if grep -qxF 'CHANGELOG.md' <<< "$COMMITTED"; then
    echo "SETUP-FAIL: CHANGELOG.md всё же попал в коммит — предпосылка теста неверна"
    FAIL=$((FAIL + 1))
else
    check "атака 2: git commit -m fix — коммит без CHANGELOG ($(printf '%s' "$COMMITTED" | tr '\n' ' '))" "$OUT"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
