#!/usr/bin/env bash
# test_adv3_bump_na_confidence_breaks_journal.sh — журнал обязан оставаться разбираемым.
#
# Результат: строка, записанная в disagreement-outcomes.jsonl, разбирается как JSON —
# при любом исходе и при любом содержимом поля confidence в знании.
# Проверка результата: bash hooks/tests/test_adv3_bump_na_confidence_breaks_journal.sh даёт 0
#
# Атака — асимметрия ветвей. Ветка confirmed/contradicted значение confidence ПРОВЕРЯЕТ
# (строки 431-432: `case ... *[!0-9]* -> CONF_NOW=0`), ветка not_applicable /
# applicable_not_followed берёт его тем же awk (строка 164) и НЕ проверяет. Значение едет
# в JSON без кавычек (`"confidence":%s`, строка 123), поэтому нечисловое поле даёт битую
# строку. Тот же awk не ограничен frontmatter, то есть подхватывает и строку тела.
#
# Цена. five-whys-gate.sh:113 читает ВЕСЬ этот файл через `jq -s` и на ошибке разбора
# получает `|| printf '0'` — сигнал «одно знание подтвердилось за сессию дважды» после
# одной битой строки замолкает НАВСЕГДА и молча. Ровно этот механизм отказа описан в
# комментарии самого скрипта (строки 71-74) как повод завести общую очистку причины.
#
# Достижимость: нужен файл, у которого первая строка `^confidence:` нечисловая. В боевом
# LESSONS_DIR такой лежит — knowledge/META.md (`confidence: 1-5`), в одном каталоге со
# знаниями; из обычного хода /learn Step 4e такой вход не приходит.
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
export CLAUDE_CODE_SESSION_ID="adv3-conf"
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

cat > "$LESSONS_DIR/pattern-conf.md" <<'EOF'
---
name: pattern-conf
type: pattern
confidence: 1-5
impact: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
---

тело
EOF

OUT=$(bash "$BUMP" pattern-conf not_applicable "знание было не про то" 2>&1); RC=$?
JOURNAL="$STATE_DIR/disagreement-outcomes.jsonl"

echo "--- код возврата: $RC"
echo "--- вывод: $OUT"
echo "--- журнал:"; sed 's/^/    /' "$JOURNAL" 2>/dev/null

if [ "$RC" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: rc=$RC"; fi

LINE=$(cat "$JOURNAL" 2>/dev/null)
if grep -Eq '"confidence":(-?[0-9]+|"[^"]*"|null),' <<< "$LINE"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL [битый JSON]: поле confidence записано без кавычек и не числом:"
    grep -o '"confidence":[^,]*' <<< "$LINE" | sed 's/^/    /'
fi

if command -v jq >/dev/null 2>&1; then
    if jq -se 'length >= 1' "$JOURNAL" >/dev/null 2>&1; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL [jq не разбирает журнал]: так же его читает five-whys-gate.sh:113,"
        echo "  и на ошибке разбора сигнал повтора становится нулём навсегда:"
        jq -s '.' "$JOURNAL" 2>&1 | sed 's/^/    /' | head -3
    fi
else
    echo "SKIP: jq отсутствует, проверка разбора пропущена"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
