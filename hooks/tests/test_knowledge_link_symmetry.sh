#!/usr/bin/env bash
# test_knowledge_link_symmetry.sh — встречная ссылка появляется механизмом, не памятью автора.
#
# Результат: после записи кейса со ссылкой на паттерн этот кейс перечислен в `source_cases`
#            паттерна; несуществующий адресат не заводится
# Проверка результата: bash hooks/tests/test_knowledge_link_symmetry.sh даёт 0
#
# Повод (D208). Закрытие D12 восстановило 22 односторонние ссылки руками и поставило
# проверку, приняв её за поддержание. Замер 29 августа 2026: закрытие не удержалось — три
# односторонние ссылки, две созданы в тот же день. Проверка ловит позже и в другом контуре.
#
# КОНТРПРИМЕРЫ, все проверяются ниже:
#   · ссылка на НЕСУЩЕСТВУЮЩИЙ файл не создаёт его и не правит ничего (опечатка);
#   · ссылка, уже имеющая встречную, не дублируется;
#   · файл вне рабочей базы знаний (копия seed, чужой каталог) не трогается;
#   · кейс без ссылок — тишина.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/knowledge-link-symmetry.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
# Хелперы конвенционные: прувер `test_guards_provable.sh` распознаёт доказательства по
# СИГНАТУРАМ (assert_contains/assert_empty), а ручной `if grep` доказательством срабатывания
# не считает — по нему не отличить теста, который что-то проверяет, от теста тишины.
assert_contains() {  # <вывод> <подстрока> <метка>
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 200)"; fi
}
assert_empty() {     # <вывод> <метка>
    if [ -z "${1//[[:space:]]/}" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; fi
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
LESSONS="$TMP/lessons"; mkdir -p "$LESSONS"

mk_pattern() {  # <имя> [с полем source_cases?]
    if [ "${2:-yes}" = "yes" ]; then
        printf -- '---\nname: p\ntype: pattern\nsource_cases:\nrelated: []\n---\n\n# P\n' > "$LESSONS/$1"
    else
        printf -- '---\nname: p\ntype: pattern\nrelated: []\n---\n\n# P\n' > "$LESSONS/$1"
    fi
}
mk_case() {     # <имя> <цель|->
    if [ "$2" = "-" ]; then
        printf -- '---\nname: c\ntype: case\nedges: []\n---\n\n# C\n' > "$LESSONS/$1"
    else
        printf -- '---\nname: c\ntype: case\nedges:\n  - specializes: %s\n---\n\n# C\n' "$2" > "$LESSONS/$1"
    fi
}
run() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$LESSONS/$1" \
        | LESSONS_DIR="$LESSONS" bash "$HOOK" 2>/dev/null; }

# --- T1: встречная ссылка дописана ---
mk_pattern "pattern-a.md"
mk_case "case-one.md" "pattern-a.md"
OUT=$(run "case-one.md")
assert_contains "$(cat "$LESSONS/pattern-a.md")" "case-one.md" "T1: встречная ссылка дописана"
assert_contains "$OUT" "дописана" "T1b: механизм назвал свою правку"
# YAML не сломан: поле осталось внутри frontmatter
if python3 -c "
import sys,re
t=open('$LESSONS/pattern-a.md').read()
fm=t.split('---')[1]
sys.exit(0 if 'case-one.md' in fm else 1)"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1c]: ссылка легла вне frontmatter — YAML сломан"; fi

# --- T2: КОНТРПРИМЕР — повтор не дублируется ---
run "case-one.md" >/dev/null
N=$(grep -c 'case-one.md' "$LESSONS/pattern-a.md")
if [ "$N" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: ссылка продублирована ($N раз)"; fi

# --- T3: паттерн БЕЗ поля source_cases — поле заводится корректно ---
mk_pattern "pattern-b.md" "no"
mk_case "case-two.md" "pattern-b.md"
run "case-two.md" >/dev/null
if grep -q 'source_cases:' "$LESSONS/pattern-b.md" && grep -q 'case-two.md' "$LESSONS/pattern-b.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: поле не заведено: $(cat "$LESSONS/pattern-b.md")"; fi

# --- T4: КОНТРПРИМЕР — несуществующий адресат не создаётся ---
mk_case "case-three.md" "pattern-nonexistent.md"
OUT4=$(run "case-three.md")
assert_empty "$OUT4" "T4: несуществующий адресат не объявлен"
[ ! -f "$LESSONS/pattern-nonexistent.md" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4b]: несуществующий адресат создан"; }

# --- T5: КОНТРПРИМЕР — кейс без ссылок → тишина ---
mk_case "case-four.md" "-"
OUT5=$(run "case-four.md")
assert_empty "$OUT5" "T5: кейс без ссылок — тишина"

# --- T6: КОНТРПРИМЕР — файл вне рабочей базы не трогается ---
OTHER="$TMP/other"; mkdir -p "$OTHER"
cp "$LESSONS/case-one.md" "$OTHER/case-one.md"
OUT6=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$OTHER/case-one.md" \
       | LESSONS_DIR="$LESSONS" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT6" "T6: файл вне рабочей базы не тронут"

# --- T7: чтение и прочие инструменты не трогаются ---
OUT7=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$LESSONS/case-one.md" \
       | LESSONS_DIR="$LESSONS" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT7" "T7: чтение не трогается"

echo "knowledge link symmetry: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
