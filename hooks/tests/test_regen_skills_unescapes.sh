#!/usr/bin/env bash
# test_regen_skills_unescapes.sh — значение из YAML-шапки попадает в витрину РАЗЭКРАНИРОВАННЫМ.
#
# Результат: в опубликованных справочниках нет литерального \" из double-quoted скаляра
# Проверка результата: bash hooks/tests/test_regen_skills_unescapes.sh даёт 0
#
# Повод, 7 сентября 2026. Генератор снимал кавычки только с КРАЁВ значения
# (scripts/regen-readme-skills.sh:118-136) и не разворачивал экранирование внутри
# double-quoted YAML-скаляра. На дереве 24 скилла × 3 поля = 72 извлечения, из них 2 дали
# иное значение, чем yaml.safe_load, и оба уже материализовались в витрине:
# docs/reference.md:99 и :118 — там стояло \"update X\" вместо "update X".
# Русская таблица чиста: в ней кавычки-ёлочки, экранировать нечего, поэтому дефект жил
# только на английском плече и потому прожил незамеченным.
#
# КОНТРПРИМЕР: в single-quoted скаляре YAML обратный слэш НЕ экранирует — там \" это два
# настоящих символа, и разворачивать их нельзя.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="$ROOT/scripts/regen-readme-skills.sh"
[ -f "$GEN" ] || { echo "SKIP: нет $GEN"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"; mkdir -p "$REPO/skills/probe-dq" "$REPO/skills/probe-sq" "$REPO/hooks"
cat > "$REPO/skills/probe-dq/SKILL.md" <<'MD'
---
name: probe-dq
description: "Проба: скажи \"привет\" и всё."
description_en: "Probe: say \"hello\" and stop."
---
тело
MD
cat > "$REPO/skills/probe-sq/SKILL.md" <<'MD'
---
name: probe-sq
description: 'Проба два, без экранирования'
description_en: 'Probe two, keep \"as is\" here'
---
тело
MD
TARGET="$TMP/reference.md"
{ printf '<!-- SKILLS-TABLE:START -->\n<!-- SKILLS-TABLE:END -->\n'
  printf '<!-- HOOKS-TABLE:START -->\n<!-- HOOKS-TABLE:END -->\n'; } > "$TARGET"

README_FILE="$TARGET" bash "$GEN" "$REPO" >/dev/null 2>&1
RC=$?
if [ ! -s "$TARGET" ]; then
    bad "T0" "витрина не сгенерирована (rc=$RC)"
else
    ok
    # T1: экранированная кавычка развернулась — СТРОГО в строке double-quoted скилла.
    # Искать по всей витрине нельзя: у single-quoted соседа \" законен (нога T3).
    DQ_ROW=$(grep -m1 'probe-dq' "$TARGET")
    if grep -q '\\"' <<< "$DQ_ROW"; then
        bad "T1" "в строке double-quoted скилла остался обратный слэш: $(printf '%s' "$DQ_ROW" | cut -c1-90)"
    else ok; fi
    # T2: сама кавычка на месте — разворот не съел содержимое
    if grep -q '"hello"' "$TARGET" || grep -q '«hello»' "$TARGET"; then ok
    else bad "T2" "кавычки исчезли вовсе: $(grep -m1 'Probe' "$TARGET" | cut -c1-90)"; fi
    # T3: КОНТРПРИМЕР — в single-quoted скаляре YAML обратный слэш НЕ экранирует: там
    # \" это два настоящих символа, и разворачивать их нельзя. Без этой ноги мутация
    # «разворот безусловный» проходила прибор насквозь (поймано мутацией 7 сентября 2026).
    if grep -q 'Probe two, keep \\"as is\\" here' "$TARGET"; then ok
    else bad "T3" "single-quoted значение искажено разворотом: $(grep -m1 'probe-sq' "$TARGET" | cut -c1-90)"; fi
fi

echo "regen skills unescapes: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
