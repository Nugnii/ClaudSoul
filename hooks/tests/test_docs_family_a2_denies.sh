#!/usr/bin/env bash
# СУДИТ: hooks/docs-family-check.sh scripts/regen-readme-skills.sh
# test_docs_family_a2_denies.sh — Path A2 ОТКАЗЫВАЕТ, а не советует, и отказывает КАЖДЫЙ раз.
#
# Результат: расхождение автотаблиц не может уехать в коммит — вызов отклоняется, и повтор
#            той же команды отклоняется тоже
# Проверка результата: bash hooks/tests/test_docs_family_a2_denies.sh даёт 0
#
# Повод (18 сентября 2026, D462). Прежде A2 печатал additionalContext и exit 0 — говорил и
# отпускал вызов. Замер зондом по журналу и дереву: срабатываний четыре, коммитов в окнах
# ±180 с восемь, дерево каждого разложено `git archive`, генератор прогнан в копию и сравнён.
# Расхождение УЦЕЛЕЛО после коммита в 4 случаях из 8 (d6b9eb6, ed4a6cc, 7e59461, 47c6915);
# ложных срабатываний 0 из 4 — за каждым шёл починочный коммит вдогонку. Ключ 01bea065 стоит
# в журнале дважды, 13 и 18 сентября: расхождение прожило пять дней при двух предупреждениях.
#
# НОГА T3 — ГЛАВНАЯ. Дроссель гасил повтор: для подсказки это тишина вместо шума, для отказа
# это дыра, потому что повтором расхождение и уезжало. Гашение снято, журнал оставлен.
#
# РАМКА ЗАДАЁТСЯ, А НЕ НАСЛЕДУЕТСЯ: гейт прогоняет «Проверку» пункта с BACKLOG_CHECKS_NESTED=1,
# а предмет теста — хук. Под маркером посторонние Stop-хуки молчат, здесь это не мешает, но
# рамку задаём явно, чтобы тест не зависел от того, кто его позвал.
# Корень дерева — тоже (D1366): `scripts/regen-readme-skills.sh` без аргумента берёт CLAUDSOUL_REPO раньше своего
# каталога, и под сверщиком архива после коммита (переменная на клон) нога T5 сводила таблицы песочницы по навыкам клона.
set -uo pipefail
unset BACKLOG_CHECKS_NESTED CLAUDSOUL_REPO

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
HOOK="$HOOKS_DIR/docs-family-check.sh"
GEN="$REPO_ROOT/scripts/regen-readme-skills.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
[ -f "$GEN" ]  || { echo "FAIL: нет $GEN"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

PASS=0; FAIL=0; DENIED=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_repo() {
    local repo="$TMP/repo"
    rm -rf "$repo"; mkdir -p "$repo/scripts" "$repo/hooks" "$repo/skills"
    cp "$GEN" "$repo/scripts/regen-readme-skills.sh"
    printf '#!/usr/bin/env bash\n# demo-hook.sh — PreToolUse: демонстрационный хук.\nexit 0\n' \
        > "$repo/hooks/demo-hook.sh"
    mkdir -p "$repo/skills/normal"
    printf -- '---\nname: normal\ndescription: описание до правки\n---\n\n**Type:** worker\n' \
        > "$repo/skills/normal/SKILL.md"
    {
        echo "# Demo"
        echo "<!-- SKILLS-TABLE:START -->"
        echo "<!-- SKILLS-TABLE:END -->"
        echo "<!-- HOOKS-TABLE:START -->"
        echo "<!-- HOOKS-TABLE:END -->"
    } > "$repo/README.md"
    ( cd "$repo" && bash scripts/regen-readme-skills.sh "$repo" >/dev/null 2>&1 )
    ( cd "$repo" && git init -q . \
        && git config user.email a2@test && git config user.name a2 \
        && git add -A && git commit -qm init )
    printf '%s' "$repo"
}

stage_skill_edit() {   # правка источника таблиц: описание изменено, таблица отстала
    local repo="$1"
    printf -- '---\nname: normal\ndescription: ОПИСАНИЕ ИЗМЕНЕНО, таблица отстала\n---\n\n**Type:** worker\n' \
        > "$repo/skills/normal/SKILL.md"
    ( cd "$repo" && git add -A )
}

stage_unrelated_edit() {   # правка НЕ источника таблиц
    local repo="$1"
    printf 'заметка\n' > "$repo/NOTES.md"
    ( cd "$repo" && git add -A )
}

run_hook() {   # $1 репозиторий; $2 — «keep», чтобы НЕ сбрасывать состояние (проверка дросселя)
    local repo="$1" keep="${2:-}"
    [ "$keep" = "keep" ] || { rm -rf "$TMP/state"; mkdir -p "$TMP/state"; }
    mkdir -p "$TMP/state" "$TMP/home"
    printf '{"session_id":"a2test","tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' \
        "$repo" \
        | env HOME="$TMP/home" STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$repo" bash "$HOOK" 2>/dev/null
}

is_deny() { grep -qF '"permissionDecision":"deny"' <<< "$1"; }

ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# --- T1: расхождение → ОТКАЗ, а не подсказка ----------------------------------------
REPO=$(make_repo); stage_skill_edit "$REPO"
OUT1=$(run_hook "$REPO")
if is_deny "$OUT1"; then ok; DENIED=$((DENIED + 1)); else
    bad T1 "расхождение не отклонено (подсказка вместо отказа?): ${OUT1:-<пусто>}"; fi

# --- T2: выход ИСПОЛНИМ, а не просто упомянут ---------------------------------------
# Первая редакция ноги искала имя скрипта в тексте и была зелёной на НЕИСПОЛНИМОЙ команде:
# `$MISSING` несёт «файл (пояснение)», и скобки пояснения ломали `for`. Страж требовал
# действия и не давал способа. Здесь команда ВЫНИМАЕТСЯ из отказа и ЗАПУСКАЕТСЯ.
EXIT_CMD=$(printf '%s' "$OUT1" \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d["hookSpecificOutput"]["permissionDecisionReason"])
except Exception:
    pass' 2>/dev/null | grep -E '^[[:space:]]*for d in' | sed 's/^[[:space:]]*//')
if [ -z "$EXIT_CMD" ]; then
    bad T2 "в причине отказа нет команды выхода: ${OUT1:-<пусто>}"
else
    ( cd "$REPO" && eval "$EXIT_CMD" >/dev/null 2>&1 ); _rc=$?
    cp "$REPO/README.md" "$TMP/after.md" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_docs_family_a2_denies.sh:$LINENO" >&2; exit 1; }
    ( cd "$REPO" && bash scripts/regen-readme-skills.sh >/dev/null 2>&1 )
    if [ "$_rc" -ne 0 ]; then
        bad T2 "команда выхода не исполнилась (код $_rc): $EXIT_CMD"
    elif cmp -s "$REPO/README.md" "$TMP/after.md"; then ok
    else bad T2 "команда выхода исполнилась, но таблицы не свелись: $EXIT_CMD"; fi
fi

# --- T3 (ГЛАВНАЯ): ПОВТОР того же вызова отклоняется СНОВА ---------------------------
# Дроссель гасил повтор — для отказа это дыра: именно повтором расхождение уезжало.
OUT2=$(run_hook "$REPO" keep)
if is_deny "$OUT2"; then ok; DENIED=$((DENIED + 1)); else
    bad T3 "повтор прошёл молча — дроссель гасит отказ: ${OUT2:-<пусто>}"; fi

# --- T4: журнал срабатываний ведётся (по нему считается замер) -----------------------
if ls "$TMP/state"/docs-family-tables-fired-*.jsonl >/dev/null 2>&1; then ok; else
    bad T4 "журнал срабатываний не записан — замер считать будет нечем"; fi

# --- T5: таблицы СВЕДЕНЫ → молчит ----------------------------------------------------
REPO=$(make_repo); stage_skill_edit "$REPO"
( cd "$REPO" && README_FILE=README.md bash scripts/regen-readme-skills.sh >/dev/null 2>&1 && git add -A )
OUT3=$(run_hook "$REPO")
is_deny "$OUT3" && bad T5 "отказ на сведённых таблицах — ложное срабатывание: $OUT3" || ok

# --- T6: в staged НЕ источник таблиц → молчит ----------------------------------------
REPO=$(make_repo); stage_unrelated_edit "$REPO"
OUT4=$(run_hook "$REPO")
is_deny "$OUT4" && bad T6 "отказ на правке, не трогающей источники таблиц: $OUT4" || ok

# --- T7: ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ — отказ вообще случался ------------------------------
# Без него T5 и T6 зеленеют на вырезанном блоке: у них ожидаемый исход И ЕСТЬ молчание.
[ "$DENIED" -ge 2 ] && ok || bad T7 "отказ случился $DENIED раз(а) — ноги молчания зеленеют от неработающего блока"

echo "docs-family A2 denies: $PASS passed, $FAIL failed (отказов $DENIED)"
exit $(( FAIL != 0 ))
