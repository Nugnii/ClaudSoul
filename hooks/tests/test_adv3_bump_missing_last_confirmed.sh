#!/usr/bin/env bash
# test_adv3_bump_missing_last_confirmed.sh — «ставит last_confirmed» должно означать «ставит».
#
# Результат: после успешного `confirmed` в знании стоит last_confirmed сегодняшним числом —
# независимо от того, было поле в файле до вызова или нет. Либо вызов отказывает.
# Проверка результата: bash hooks/tests/test_adv3_bump_missing_last_confirmed.sh даёт 0
#
# Атака. Отсутствующие поля скрипт умеет создавать: счётчик (ветка MISSING_FIELD, строка 389),
# provenance_log и source_cases (состояние "absent", строки 306-313). Четвёртое поле,
# last_confirmed, только ПЕРЕПИСЫВАЕТСЯ (строка 366) и не создаётся никогда. Знание без него
# получает confirmed_count++, зелёную галочку и код 0 — а даты подтверждения как не было,
# так и нет. Заголовок самого скрипта (строка 20) и skills/learn/SKILL.md:83 обещают обратное.
#
# Достижимость, замер по боевой базе 2026-08-29: у всех 289 записей операционного контура
# (тех, где есть confirmed_count) поле last_confirmed стоит — из документированного хода
# /learn Step 4a такой вход сегодня не приходит. Достижимо на 105 записях энциклопедического
# контура (entity/relation/fact): у них нет ни счётчика, ни даты, и вызов создаёт первое,
# молча не создавая второго — второй сценарий ниже воспроизводит именно эту форму.
#
# Цена. hooks/fsrs-lib.sh:41 на пустом last_confirmed возвращает 0 дней просрочки, то есть
# статус fresh навсегда: затухание для такой записи не наступает никогда, и санкционированный
# способ подтверждения этого не чинит.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUMP="$HOOKS_DIR/knowledge-counter-bump.sh"
[ -f "$BUMP" ] || { echo "FAIL: $BUMP не найден"; exit 1; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

unset CLAUDE_STATE_DIR
export LESSONS_DIR="$TMP/lessons"
export STATE_DIR="$TMP/state"
export CLAUDE_CODE_SESSION_ID="adv3-lc"
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

TODAY=$(date '+%Y-%m-%d')

check() { # <файл> <метка>
    local k="$1" label="$2" out rc after
    out=$(bash "$BUMP" "$(basename "$k" .md)" confirmed "подтвердилось на деле" 2>&1); rc=$?
    after=$(cat "$k")
    echo "--- [$label] rc=$rc: $out"
    if [ "$rc" -ne 0 ]; then
        PASS=$((PASS+1)); return
    fi
    if grep -Fq "last_confirmed: $TODAY" <<< "$after"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL [$label]: скрипт отчитался успехом, но last_confirmed в знании нет."
        echo "  frontmatter после вызова:"
        sed -n '1,24p' "$k" | sed 's/^/    /'
    fi
}

# 1. Операционная форма: счётчик есть, даты нет.
cat > "$LESSONS_DIR/pattern-nolc.md" <<'EOF'
---
name: pattern-nolc
type: pattern
confidence: 4
impact: 4
confirmed_count: 2
contradicted_count: 0
status: active
---

тело
EOF
check "$LESSONS_DIR/pattern-nolc.md" "счётчик без даты"

# 2. Форма энциклопедического контура: нет ни счётчика, ни даты (105 таких в боевой базе).
cat > "$LESSONS_DIR/entity-nolc.md" <<'EOF'
---
name: Тестовая сущность
type: entity
entity_type: product
status: active
confidence: 1
aliases: []
created: '2026-04-21'
last_updated: '2026-04-21'
---

тело
EOF
check "$LESSONS_DIR/entity-nolc.md" "ни счётчика, ни даты"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
