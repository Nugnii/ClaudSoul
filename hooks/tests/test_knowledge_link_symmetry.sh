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
# Отметка свежести — общее состояние; своя на прогон, иначе тест читал бы чужую, а
# оболочечная ветка отсеклась бы сторожем и T9 позеленел бы, ничего не проверив.
export CLAUDSOUL_STATE_DIR="$TMP/state"; mkdir -p "$CLAUDSOUL_STATE_DIR"

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

# --- T8: ФОРМА, КОТОРУЮ ПРОИЗВОДИТ МИР — поточный список `source_cases: [a.md]` ---
# Повод (5 сентября 2026). Фикстуры выше умеют ровно две формы — блочную пустую и
# отсутствие поля. Мир производит третью: 10 родителей из 50 в рабочей базе несут
# поточную. На ней хук уходил в ветку «поля нет» и заводил ВТОРОЙ ключ `source_cases`;
# YAML при этом валиден, `yaml.safe_load` берёт ПОСЛЕДНИЙ ключ и молчит — прежние кейсы
# исчезали из графа. Тот же род был закрыт у соседа-писателя (`knowledge-counter-bump.sh`,
# ветка на строках 511-518) за 12 часов до того, как этот хук внёс его заново.
# ПРОВЕРКА ИДЁТ РАЗБОРОМ, А НЕ ПОДСТРОКОЙ: подстрока видит имя и в испорченном файле —
# именно поэтому три прибора были зелёными на порче (`backlog-recheck.sh:97`,
# `test_knowledge_link_symmetry.py:47`, `test_knowledge_frontmatter_valid.py`).
printf -- '---\nname: p\ntype: pattern\nsource_cases: [case-zero.md]\nrelated: []\n---\n\n# P\n' > "$LESSONS/pattern-flow.md"
mk_case "case-flow.md" "pattern-flow.md"
run "case-flow.md" >/dev/null
KEYS=$(grep -c '^source_cases:' "$LESSONS/pattern-flow.md")
if [ "$KEYS" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8: поточный список — ключ остался один]: ключей $KEYS"; fi

if python3 -c "
import sys, yaml
m = yaml.safe_load(open('$LESSONS/pattern-flow.md').read().split('---')[1]) or {}
sc = m.get('source_cases') or []
sys.exit(0 if 'case-zero.md' in sc and 'case-flow.md' in sc else 1)"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8b: разбор видит и прежний кейс, и новый]: $(grep -n 'source_cases' "$LESSONS/pattern-flow.md" | tr '\n' ' ')"; fi

# --- T8c: поточный ПУСТОЙ список `source_cases: []` — та же ветка, отдельная форма ---
printf -- '---\nname: p\ntype: pattern\nsource_cases: []\nrelated: []\n---\n\n# P\n' > "$LESSONS/pattern-flowempty.md"
mk_case "case-flowempty.md" "pattern-flowempty.md"
run "case-flowempty.md" >/dev/null
if python3 -c "
import sys, yaml
m = yaml.safe_load(open('$LESSONS/pattern-flowempty.md').read().split('---')[1]) or {}
sys.exit(0 if 'case-flowempty.md' in (m.get('source_cases') or []) else 1)"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8c: пустой поточный список]: $(grep -n 'source_cases' "$LESSONS/pattern-flowempty.md" | tr '\n' ' ')"; fi
# Разбора мало: на дубле `yaml.safe_load` берёт последний ключ и отвечает ПРАВИЛЬНО,
# хотя файл испорчен. Число ключей — единственное, что отличает здоровый файл от
# испорченного, когда терять ещё нечего (список был пуст).
KE=$(grep -c '^source_cases:' "$LESSONS/pattern-flowempty.md")
if [ "$KE" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8c2: пустой поточный — ключ остался один]: ключей $KE"; fi

# --- T8d: КОНТРПРИМЕР — поточный список, НЕ закрытый в строке, не правится вовсе ---
# Построчная правка такую форму не осилит; молчаливая порча хуже отказа. Тот же
# контрпример объявлен и проверен у соседа (`knowledge-counter-bump.sh:382-390`).
printf -- '---\nname: p\ntype: pattern\nsource_cases: [\n  case-zero.md,\n]\nrelated: []\n---\n\n# P\n' > "$LESSONS/pattern-open.md"
mk_case "case-open.md" "pattern-open.md"
run "case-open.md" >/dev/null
KO=$(grep -c '^source_cases:' "$LESSONS/pattern-open.md")
if [ "$KO" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8d: незакрытый поточный список не получил второго ключа]: ключей $KO"; fi

# --- T9: ПРАВКА ЧЕРЕЗ ОБОЛОЧКУ — предмет механизма есть изменение файла, а не имя инструмента ---
# Повод (5 сентября 2026). Кейс `case-2026-09-05-fix-carries-the-genus-it-repairs.md` записан
# heredoc-ом через Bash; хук стоял на matcher `Write|Edit|MultiEdit` и не был вызван вовсе —
# закрытие D12 откатилось. Знание об этом роде лежало в базе за два дня ДО рождения хука
# (`case-2026-08-27-tool-name-detection-blind-to-work-mode.md`, confirmed_count 4).
printf -- '---\nname: p\ntype: pattern\nsource_cases:\nrelated: []\n---\n\n# P\n' > "$LESSONS/pattern-sh.md"
mk_case "case-sh.md" "pattern-sh.md"
OUT9=$(printf '{"tool_name":"Bash","tool_input":{"command":"cd ~/.claude/global-lessons && cat > case-sh.md <<EOF"}}' \
       | LESSONS_DIR="$LESSONS" bash "$HOOK" 2>/dev/null)
assert_contains "$(cat "$LESSONS/pattern-sh.md")" "case-sh.md" "T9: правка оболочкой тоже даёт встречную ссылку"

# --- T9b: КОНТРПРИМЕР — оболочечный вызов, ничего не менявший в базе, молчит ---
OUT9B=$(printf '{"tool_name":"Bash","tool_input":{"command":"echo ничего"}}' \
        | LESSONS_DIR="$LESSONS" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT9B" "T9b: оболочка без новых асимметрий — тишина"

# --- T10: имя кейса УЖЕ ЕСТЬ в файле родителя, но не в source_cases ---
# Форма, на которой подстрочная проверка молчит, а разбор находит работу: имя лежит в
# `provenance_log.trigger_case`. Именно так 5 сентября 2026 приборы инварианта D12
# показывали 1 нарушение при 18 настоящих. Без этой ноги возврат хука к подстроке
# (`case_name in parent_text`) не был бы замечен: мутация давала 17 passed.
printf -- '---\nname: p\nsource_cases:\n  - case-someone.md\nprovenance_log:\n  - trigger_case: case-mention.md\nrelated: []\n---\n\n# P\n' > "$LESSONS/pattern-mention.md"
mk_case "case-mention.md" "pattern-mention.md"
run "case-mention.md" >/dev/null
if python3 -c "
import sys, yaml
m = yaml.safe_load(open('$LESSONS/pattern-mention.md').read().split('---')[1]) or {}
sys.exit(0 if 'case-mention.md' in (m.get('source_cases') or []) else 1)"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T10: упоминание в provenance_log за симметрию не считается]: $(grep -n 'case-mention' "$LESSONS/pattern-mention.md" | tr '\n' ' ')"; fi

echo "knowledge link symmetry: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
