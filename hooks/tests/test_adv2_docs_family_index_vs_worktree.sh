#!/usr/bin/env bash
# test_adv2_docs_family_index_vs_worktree.sh — check_generated_tables сверяет РАБОЧЕЕ
# ДЕРЕВО, а в коммит уходит ИНДЕКС.
#
# Атака. Функция копирует `$CWD/README.md` (рабочий файл), гоняет по копии генератор и
# сравнивает копию с тем же рабочим файлом. Про содержимое индекса она не спрашивает
# ничего. Значит достаточно регенерировать таблицы и не добавить README в индекс:
#     bash scripts/regen-readme-skills.sh   # рабочий README свеж
#     git add skills/demo/SKILL.md          # README в индекс НЕ добавлен
#     git commit -m ...
# Страж сравнивает свежий README со свежим — молчит. Коммит уносит новый источник и
# СТАРУЮ таблицу: в репозитории ровно то расхождение, ради которого писали Path A2
# («расхождение из 771e7fc прожило сутки»).
#
# Тест доводит до конца: делает коммит и читает README из HEAD.
#
# Контроль: без регенерации на той же фикстуре страж срабатывает.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
HOOK="$HOOKS_DIR/docs-family-check.sh"
GEN="$REPO_ROOT/scripts/regen-readme-skills.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
[ -f "$GEN" ]  || { echo "FAIL: $GEN not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_repo() {
    local repo="$TMP/repo"
    rm -rf "$repo"; mkdir -p "$repo/scripts" "$repo/hooks" "$repo/skills/demo"
    cp "$GEN" "$repo/scripts/regen-readme-skills.sh"
    printf '#!/usr/bin/env bash\n# demo-hook.sh — PreToolUse: демонстрационный хук.\nexit 0\n' \
        > "$repo/hooks/demo-hook.sh"
    printf -- '---\nname: demo\ndescription: описание до правки\n---\n\n**Type:** worker\n' \
        > "$repo/skills/demo/SKILL.md"
    {
        echo "# Demo"
        echo "<!-- SKILLS-TABLE:START -->"
        echo "<!-- SKILLS-TABLE:END -->"
        echo "<!-- HOOKS-TABLE:START -->"
        echo "<!-- HOOKS-TABLE:END -->"
    } > "$repo/README.md"
    ( cd "$repo" && bash scripts/regen-readme-skills.sh "$repo" >/dev/null 2>&1 )
    ( cd "$repo" && git init -q . && git config user.email adv@test && git config user.name adv \
        && git add -A && git commit -qm init )
    printf -- '---\nname: demo\ndescription: ОПИСАНИЕ ИЗМЕНЕНО\n---\n\n**Type:** worker\n' \
        > "$repo/skills/demo/SKILL.md"
    ( cd "$repo" && git add skills/demo/SKILL.md )
    printf '%s' "$repo"
}

run_hook() {
    rm -rf "$TMP/state"; mkdir -p "$TMP/state" "$TMP/home"
    printf '{"session_id":"adv2-%s","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' \
        "$RANDOM" "$1" \
        | env HOME="$TMP/home" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

check() {   # check <label> <output>
    if grep -qF 'Автотаблицы разошлись' <<< "$2"; then
        PASS=$((PASS + 1)); echo "PASS [$1]"
    else
        FAIL=$((FAIL + 1)); echo "FAIL [$1]: страж промолчал"
        echo "       вывод хука: ${2:-<пусто>}"
    fi
}

# ── контроль: README не регенерирован — страж видит расхождение ───────────────
REPO=$(make_repo)
check "контроль: README не регенерирован" "$(run_hook "$REPO")"

# ── атака: README регенерирован, но не добавлен в индекс ──────────────────────
REPO=$(make_repo)
( cd "$REPO" && bash scripts/regen-readme-skills.sh "$REPO" >/dev/null 2>&1 )
OUT=$(run_hook "$REPO")
( cd "$REPO" && git commit -qm "правка источника без таблицы" )
HEAD_README=$( cd "$REPO" && git show HEAD:README.md )
if grep -qF 'ОПИСАНИЕ ИЗМЕНЕНО' <<< "$HEAD_README"; then
    echo "SETUP-FAIL: таблица в HEAD всё же свежая — предпосылка теста неверна"
    FAIL=$((FAIL + 1))
else
    check "атака: коммит уносит новый SKILL.md и старую таблицу в README" "$OUT"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
