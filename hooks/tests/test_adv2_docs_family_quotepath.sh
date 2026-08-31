#!/usr/bin/env bash
# test_adv2_docs_family_quotepath.sh — Path A2 в docs-family-check.sh не видит
# источники автотаблиц с не-ASCII именами.
#
# Атака. TABLE_SOURCES фильтрует `$STAGED` регуляркой `^skills/[^/]+/SKILL\.md$`,
# а $STAGED собирается `git diff --cached --name-only` БЕЗ `-c core.quotepath=false`.
# git по умолчанию отдаёт такой путь в кавычках с восьмеричными escape:
#   "skills/\320\277\321\200\320\276\321\202\320\270\320\262\320\275\320\270\320\272/SKILL.md"
# Фильтр его не узнаёт → check_generated_tables не зовётся → расхождение таблиц
# уезжает в коммит молча. Это тот же дефект D69, который в этой же сессии починили
# у quality-gate-check и skill-review-check, а здесь — нет.
#
# У проекта два таких скилла из 23: `противник`, `грилинг`.
#
# Контроль в том же тесте: скилл с ASCII-именем на той же фикстуре страж ловит,
# значит фикстура валидна и молчание вызвано именно именем.
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

# ── фикстура: минимальный репозиторий с генератором таблиц ────────────────────
make_repo() {
    local repo="$TMP/repo"
    rm -rf "$repo"; mkdir -p "$repo/scripts" "$repo/hooks" "$repo/skills"
    cp "$GEN" "$repo/scripts/regen-readme-skills.sh"
    printf '#!/usr/bin/env bash\n# demo-hook.sh — PreToolUse: демонстрационный хук.\nexit 0\n' \
        > "$repo/hooks/demo-hook.sh"
    for name in normal противник; do
        mkdir -p "$repo/skills/$name"
        printf -- '---\nname: %s\ndescription: описание до правки\n---\n\n**Type:** worker\n' \
            "$name" > "$repo/skills/$name/SKILL.md"
    done
    {
        echo "# Demo"
        echo "<!-- SKILLS-TABLE:START -->"
        echo "<!-- SKILLS-TABLE:END -->"
        echo "<!-- HOOKS-TABLE:START -->"
        echo "<!-- HOOKS-TABLE:END -->"
    } > "$repo/README.md"
    ( cd "$repo" && bash scripts/regen-readme-skills.sh "$repo" >/dev/null 2>&1 )
    ( cd "$repo" && git init -q . \
        && git config user.email adv@test && git config user.name adv \
        && git add -A && git commit -qm init )
    printf '%s' "$repo"
}

# Правит описание скилла $1 и ставит правку в индекс — таблица README устаревает.
stage_skill_edit() {
    local repo="$1" name="$2"
    printf -- '---\nname: %s\ndescription: ОПИСАНИЕ ИЗМЕНЕНО, таблица отстала\n---\n\n**Type:** worker\n' \
        "$name" > "$repo/skills/$name/SKILL.md"
    ( cd "$repo" && git add -A )
}

run_hook() {
    local repo="$1"
    rm -rf "$TMP/state"; mkdir -p "$TMP/state" "$TMP/home"
    printf '{"session_id":"adv2-%s","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' \
        "$RANDOM" "$repo" \
        | env HOME="$TMP/home" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

check() {  # check <label> <output> <expect-fire:yes|no>
    local label="$1" out="$2" expect="$3"
    local fired=no
    grep -qF 'Автотаблицы разошлись' <<< "$out" && fired=yes
    if [ "$fired" = "$expect" ]; then
        PASS=$((PASS + 1)); echo "PASS [$label]"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: ожидалось fired=$expect, получено fired=$fired"
        echo "       вывод хука: ${out:-<пусто>}"
    fi
}

# ── контроль: ASCII-имя ловится ───────────────────────────────────────────────
REPO=$(make_repo)
stage_skill_edit "$REPO" normal
check "контроль: skills/normal/SKILL.md — страж видит расхождение" "$(run_hook "$REPO")" yes

# ── атака: кириллическое имя ──────────────────────────────────────────────────
REPO=$(make_repo)
stage_skill_edit "$REPO" противник
check "атака: skills/противник/SKILL.md — страж обязан увидеть то же расхождение" \
    "$(run_hook "$REPO")" yes

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
