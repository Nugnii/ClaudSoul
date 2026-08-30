#!/usr/bin/env bash
# test_adv3_bump_dash_trigger_case.sh — в source_cases попадает имя кейса, а не остаток от него.
#
# Результат: аргумент кейса, который не удалось разобрать, приводит к отказу; в source_cases
# родителя не появляется элемент без имени.
# Проверка результата: bash hooks/tests/test_adv3_bump_dash_trigger_case.sh даёт 0
#
# Атака. Имя кейса нормализуется через `basename "$TRIGGER_CASE"` (строка 237) без `--`.
# Аргумент, начинающийся с дефиса, basename принимает за ключ: он печатает usage в stderr,
# на stdout не даёт ничего, и `_tc` становится пустым. Следующая строка дописывает суффикс,
# и в source_cases уезжает элемент `.md` — имя файла, которого не бывает. Скрипт при этом
# печатает зелёную галочку и возвращает 0.
#
# Цена. source_cases — половина ребра кейс -> паттерн (knowledge/META.md, «Связь пишется в
# двух файлах»), и проверка симметрии (mcp-server/tests/test_knowledge_link_symmetry.py)
# получает ссылку на несуществующий кейс, а настоящий кейс так и остаётся не привязанным —
# то есть возвращается дефект D12, ради которого ветку и заводили.
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
export CLAUDE_CODE_SESSION_ID="adv3-dash"
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

K="$LESSONS_DIR/pattern-dash.md"
cat > "$K" <<'EOF'
---
name: pattern-dash
type: pattern
confidence: 4
impact: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-01-01
source_cases:
  - case-old.md
status: active
---

тело
EOF

OUT=$(bash "$BUMP" pattern-dash confirmed "подтвердилось" "-n-case.md" 2>&1); RC=$?
FILE_AFTER=$(cat "$K")

echo "--- код возврата: $RC"
echo "--- вывод: $OUT"
echo "--- source_cases после вызова:"
awk '/^source_cases:/{f=1} f && /^status:/{exit} f' "$K" | sed 's/^/    /'

if grep -Eq '^[[:space:]]*-[[:space:]]*\.md[[:space:]]*$' <<< "$FILE_AFTER"; then
    FAIL=$((FAIL+1))
    echo "FAIL [битая ссылка]: в source_cases внесён элемент '.md' — имя кейса потеряно целиком."
else
    PASS=$((PASS+1))
fi

if [ "$RC" -eq 0 ] && ! grep -Fq "case-old.md" <<< "$FILE_AFTER"; then
    FAIL=$((FAIL+1)); echo "FAIL: прежний кейс потерян"
else
    PASS=$((PASS+1))
fi

# Разобрать имя не удалось -> честный исход это отказ, а не зелёная галочка.
if [ "$RC" -ne 0 ] || ! grep -Fq "confirmed_count++" <<< "$OUT"; then
    PASS=$((PASS+1))
else
    if grep -Fq "case-old.md" <<< "$FILE_AFTER" && grep -Eq '^[[:space:]]*-[[:space:]]*\.md' <<< "$FILE_AFTER"; then
        FAIL=$((FAIL+1))
        echo "FAIL [ложный успех]: basename отверг аргумент (см. вывод выше), а скрипт"
        echo "  отчитался успехом и записал в знание ссылку без имени."
    else
        PASS=$((PASS+1))
    fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
