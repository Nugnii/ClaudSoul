#!/usr/bin/env bash
# test_docs_family_staged_in_same_command.sh — страж автотаблиц учитывает `git add` из ТОЙ ЖЕ
# команды, что и коммит.
#
# Повод (D314). `hooks/docs-family-check.sh` берёт содержимое документа из ИНДЕКСА
# (`git show ":$doc"`), а стоит на PreToolUse, то есть срабатывает ДО команды. На составной
# форме `git add … && git commit …` — обычной форме коммита — в момент проверки `git add`
# ещё не выполнен, и страж читает ПРЕЖНЮЮ версию документа, хотя источник и таблица уже
# согласованы в том, что уйдёт в коммит. Наблюдение 5 сентября 2026: страж сказал
# «docs/reference.md, docs/reference.ru.md — автотаблицы устарели» на коммите 9645054, где
# обе таблицы были перегенерированы и добавлены той же командой; ручная сверка ПОСЛЕ
# коммита дала «СОВПАДАЕТ» у обоих.
#
# Почему это не мелочь: ложная тревога у стража, чьё сообщение выглядит как находка, учит
# не читать его — и следующая настоящая пропускается тем же движением.
#
# ЧТО ИСКЛЮЧЕНО. Не сравнивать рабочее дерево вместо индекса: от этого страж и уходил
# (комментарий `docs-family-check.sh:175-178` — «достаточно запустить генератор и не добавить
# README»). Предмет наблюдения — то, что УЙДЁТ в коммит: индекс ∪ файлы, которые добавит
# `git add` из этой же команды. Квантор здесь безопасен, в отличие от D309: лишний файл в
# объединении глушит стража ТОЛЬКО при условии, что рабочее дерево совпало с выводом
# генератора, — а это и есть условие правильности; пропущенный файл оставляет прежнее
# (шумное) поведение, то есть ошибка в эту сторону не создаёт тихой лжи.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/docs-family-check.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"

run_with() {
    local sid="$1" cwd="$2" command="$3"
    jq -cn --arg sid "$sid" --arg cwd "$cwd" --arg cmd "$command" \
        '{session_id: $sid, tool_name: "Bash", tool_input: {command: $cmd}, cwd: $cwd}' \
      | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null
}
assert_contains() {
    if grep -q -- "$2" <<< "$1"; then PASS=$((PASS+1));
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет «$2» в: ${1:0:300}"; fi
}
assert_not_contains() {
    if grep -q -- "$2" <<< "$1"; then FAIL=$((FAIL+1)); echo "FAIL [$3]: лишнее «$2» в: ${1:0:300}";
    else PASS=$((PASS+1)); fi
}

# Репозиторий с рабочим генератором таблиц и одним хуком-источником — форма взята у
# соседнего теста (test_docs_family_check.sh, seed_tables), чтобы фикстуры не разошлись.
seed() {
    local r="$1"
    rm -rf "$r"; mkdir -p "$r/hooks" "$r/scripts" "$r/docs"
    git -C "$r" init -q 2>/dev/null
    git -C "$r" config user.email "t@e"; git -C "$r" config user.name "t"
    printf '#!/usr/bin/env bash\n# foo.sh — описание в одну строку.\n' > "$r/hooks/foo.sh"
    cat > "$r/scripts/regen-readme-skills.sh" <<'GEN'
#!/usr/bin/env bash
ROOT="${1:-.}"
F="${README_FILE:-$ROOT/README.md}"
BODY=$(for h in "$ROOT"/hooks/*.sh; do sed -n '2p' "$h"; done)
awk -v body="$BODY" '
  /HOOKS-TABLE:START/ { print; print body; skip = 1; next }
  /HOOKS-TABLE:END/   { skip = 0 }
  !skip               { print }
' "$F" > "$F.new" && mv "$F.new" "$F"
GEN
    printf '# Readme v1.0.0\n\n<!-- HOOKS-TABLE:START -->\n<!-- HOOKS-TABLE:END -->\n' > "$r/README.md"
    README_FILE="$r/README.md" bash "$r/scripts/regen-readme-skills.sh" "$r"
    printf '# Plan\n' > "$r/PLAN.md"; printf '# Claude\n' > "$r/CLAUDE.md"
    printf '# Changelog\n' > "$r/CHANGELOG.md"; printf '# Arch\n' > "$r/docs/architecture.md"
    git -C "$r" add . >/dev/null 2>&1
    git -C "$r" commit -q -m seed 2>/dev/null
}

# Источник изменён, генератор прогнан — рабочее дерево согласовано, индекс ещё нет.
drift_but_regenerated() {
    local r="$1"
    printf '#!/usr/bin/env bash\n# foo.sh — описание стало другим.\n' > "$r/hooks/foo.sh"
    README_FILE="$r/README.md" bash "$r/scripts/regen-readme-skills.sh" "$r"
}

# --- T1. Документ добавляется ТОЙ ЖЕ командой → страж молчит --------------------
R1="$TMP/r1"; seed "$R1"; drift_but_regenerated "$R1"
OUT=$(run_with s1 "$R1" "git add hooks/foo.sh README.md && git commit -m 'правка'")
assert_not_contains "$OUT" "автотаблицы устарели" "T1: README добавляется той же командой → тишина"

# --- T2. Отрицательный контроль: документ НЕ добавляется → страж говорит --------
# Без него зелёный T1 неотличим от стража, который замолчал вообще обо всём.
R2="$TMP/r2"; seed "$R2"; drift_but_regenerated "$R2"
OUT=$(run_with s2 "$R2" "git add hooks/foo.sh && git commit -m 'правка'")
assert_contains "$OUT" "автотаблицы устарели" "T2: README вне команды → страж говорит"

# --- T3. `git add -A` тоже добавляет документ → тишина --------------------------
R3="$TMP/r3"; seed "$R3"; drift_but_regenerated "$R3"
OUT=$(run_with s3 "$R3" "git add -A && git commit -m 'правка'")
assert_not_contains "$OUT" "автотаблицы устарели" "T3: git add -A покрывает документ → тишина"

# --- T4. Настоящий дрейф не глушится: генератор НЕ прогнан ----------------------
# Самая важная нога: правка не имеет права превратить стража в молчуна. Здесь рабочее
# дерево с таблицей РАСХОДИТСЯ, и `git add -A` не должен этого скрывать.
R4="$TMP/r4"; seed "$R4"
printf '#!/usr/bin/env bash\n# foo.sh — описание стало другим.\n' > "$R4/hooks/foo.sh"
OUT=$(run_with s4 "$R4" "git add -A && git commit -m 'правка без генератора'")
assert_contains "$OUT" "автотаблицы устарели" "T4: таблица не перегенерирована → страж говорит даже при git add -A"

# --- T5. Обычный коммит без git add в команде: прежнее поведение цело ------------
R5="$TMP/r5"; seed "$R5"; drift_but_regenerated "$R5"
git -C "$R5" add hooks/foo.sh README.md >/dev/null 2>&1
OUT=$(run_with s5 "$R5" "git commit -m 'уже добавлено руками'")
assert_not_contains "$OUT" "автотаблицы устарели" "T5: файлы добавлены заранее → тишина, как и было"

echo "docs-family staged in same command: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
