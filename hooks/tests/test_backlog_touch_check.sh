#!/usr/bin/env bash
# test_backlog_touch_check.sh — правка файла из открытого пункта долга не проходит молча.
#
# Результат: при правке файла, названного в ОТКРЫТОМ пункте, агент видит пункт до правки;
#            на закрытых пунктах, хрониках и чужих файлах — тишина
# Проверка результата: bash hooks/tests/test_backlog_touch_check.sh даёт 0
#
# Повод — требование владельца 29 августа 2026: «при починке чего-то должна проходить
# сверка с бэклогом не была ли там эта проблема и не решили ли мы её».
#
# КОНТРПРИМЕРЫ, все проверяются ниже:
#   · файл не упомянут ни в одном пункте → тишина;
#   · упомянут в ЗАКРЫТОМ пункте → тишина (закрытое уезжает в архив, чинить нечего);
#   · хроника (CHANGELOG/SESSION/BACKLOG) → тишина, повторная правка там норма жанра;
#   · повторная правка того же файла по тому же пункту → одно напоминание за сессию.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/backlog-touch-check.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
# Хелперы — той же формы, что у соседних тестов стражей: прувер `test_guards_provable.sh`
# распознаёт доказательства по СИГНАТУРАМ (assert_contains/assert_empty), а ручной
# `if grep` доказательством срабатывания не считает — и правильно: по нему не отличить
# теста, который что-то проверяет, от теста, который проверяет тишину пустого файла.
assert_contains() {  # <вывод> <подстрока> <метка>
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 200)"; fi
}
assert_empty() {     # <вывод> <метка>
    if [ -z "${1//[[:space:]]/}" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; fi
}
# Фикстура — ВНЕ /tmp намеренно: страж отбрасывает `*/tmp/*` как временное, а `mktemp -d` на
# Linux даёт именно /tmp — на macOS (/var/folders/…) фикстура молчала о дефекте, CI покраснел
# 30 августа 2026 (case-2026-08-29-fixture-easier-than-world-hides-the-defect, второй случай).
TMP=$(mktemp -d "${HOME}/.claudsoul-test-touch.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"
# ПРОБЕЛ В ПУТИ — намеренно. Живой путь проекта его содержит («~/My Project/ClaudSoul»),
# а `mktemp -d` даёт путь без пробелов: первая редакция стража хранила носители списком
# через пробел, была зелёной на всех проверках ниже и молчала на настоящем дереве, потому
# что расширение рвало путь на два несуществующих. Фикстура без пробела не отличает
# работающий страж от немого.
PROJ="$TMP/my proj"; mkdir -p "$PROJ/hooks"
printf '# CLAUDE\n' > "$PROJ/CLAUDE.md"
: > "$PROJ/hooks/target.sh"
: > "$PROJ/hooks/other.sh"

cat > "$PROJ/BACKLOG.md" <<'BL'
# Долг

**Легенда статусов:** ☐ todo · ◐ in-progress · ☑ done · ⊘ waived

### D200 ☐ Страж молчит на пустом входе

**Дефект.** `hooks/target.sh` выходит нулём, не сказав ничего.
**Условие возврата.** Проверка называет число.

### D201 ☑ Старая беда уже закрыта

**Дефект.** `hooks/other.sh` считал не то.
BL

run() {  # <file_path> [sid]
    jq -cn --arg f "$1" --arg s "${2:-s1}" --arg c "$PROJ" \
        '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$f}, cwd:$c}' \
    | STATE_DIR="$STATE" CLAUDSOUL_ROOT="$TMP/nonexistent" bash "$HOOK" 2>/dev/null
}

# --- T1: файл назван в ОТКРЫТОМ пункте → пункт назван до правки ---
OUT=$(run "$PROJ/hooks/target.sh")
assert_contains "$OUT" "D200" "T1: открытый пункт назван до правки"
assert_contains "$OUT" "возьми пункт в работу" "T1b: назван исполнимый исход (D111)"

# --- T2: КОНТРПРИМЕР — повтор по той же паре (файл, пункт) молчит ---
OUT2=$(run "$PROJ/hooks/target.sh")
assert_empty "$OUT2" "T2: повтор по той же паре молчит"

# --- T3: КОНТРПРИМЕР — файл из ЗАКРЫТОГО пункта → тишина ---
OUT3=$(run "$PROJ/hooks/other.sh" s2)
assert_empty "$OUT3" "T3: закрытый пункт не будит стража"

# --- T4: КОНТРПРИМЕР — файл не упомянут нигде → тишина ---
: > "$PROJ/hooks/unrelated.sh"
OUT4=$(run "$PROJ/hooks/unrelated.sh" s3)
assert_empty "$OUT4" "T4: файл вне пунктов — тишина"

# --- T5: КОНТРПРИМЕР — хроника молчит даже при упоминании ---
printf '### D202 ☐ Хроника\n\n**Дефект.** CHANGELOG.md растёт.\n' >> "$PROJ/BACKLOG.md"
OUT5=$(run "$PROJ/CHANGELOG.md" s4)
assert_empty "$OUT5" "T5: хроника не будит стража"

# --- T6: другой инструмент (чтение) не трогается ---
OUT6=$(jq -cn --arg c "$PROJ" '{session_id:"s5", tool_name:"Read", tool_input:{file_path:"'"$PROJ"'/hooks/target.sh"}, cwd:$c}' \
    | STATE_DIR="$STATE" CLAUDSOUL_ROOT="$TMP/nonexistent" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT6" "T6: чтение не трогается"

# --- T7: ОБРЫВ СВЯЗИ — нет backlog-lib → тишина, а не своя копия признака ---
OUT7=$(jq -cn --arg c "$PROJ" '{session_id:"s6", tool_name:"Edit", tool_input:{file_path:"'"$PROJ"'/hooks/target.sh"}, cwd:$c}' \
    | HOME="$TMP/nohome" STATE_DIR="$STATE" BL_LIB="$TMP/no-lib.sh" CLAUDSOUL_ROOT="$TMP/nonexistent" bash "$HOOK" 2>&1); RC7=$?
assert_empty "$OUT7" "T7: без backlog-lib — тишина, а не своя копия признака"
[ "$RC7" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7b]: ненулевой код без библиотеки: $RC7"; }

# --- T8: второй бэклог (ClaudSoul) виден из чужого проекта ---
CS="$TMP/claudsoul"; mkdir -p "$CS"
cat > "$CS/BACKLOG.md" <<'BL2'
### D300 ◐ Кросс-проектный долг

**Дефект.** `scripts/faraway.py` считает не то.
BL2
mkdir -p "$PROJ/scripts"; : > "$PROJ/scripts/faraway.py"
OUT8=$(jq -cn --arg c "$PROJ" '{session_id:"s7", tool_name:"Edit", tool_input:{file_path:"'"$PROJ"'/scripts/faraway.py"}, cwd:$c}' \
    | STATE_DIR="$STATE" CLAUDSOUL_ROOT="$CS" bash "$HOOK" 2>/dev/null)
assert_contains "$OUT8" "D300" "T8: долг ClaudSoul виден из чужого проекта"

echo "backlog touch check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
