#!/usr/bin/env bash
# test_adv_bump_reason_backslash_yaml.sh — АТАКА: обратная косая в конце причины делает
# frontmatter знания неразбираемым.
#
# Причина санируется ровно на два символа (строка 171): `tr -d '"' | tr '\n' ' '`.
# Обратная косая не трогается, а пишется она в ДВОЙНЫЕ кавычки (строка 209:
# `reason: \"" reason "\""`), где `\` — начало escape-последовательности YAML.
# Причина, кончающаяся на `\`, даёт `reason: "…C:\"` — закрывающая кавычка съедена,
# скаляр не закрыт, разбор всего frontmatter падает.
#
# Цена не в одном поле: `mcp-server/tests/test_knowledge_frontmatter_valid.py` требует
# разбираемости, а indexer читает знание целиком — знание выпадает из индекса цело.
# Скрипт при этом отчитывается «✅ confirmed_count++» и возвращает 0.
#
# Достижимость: `reason` — свободный текст, который агент передаёт третьим позиционным
# аргументом (skills/learn/SKILL.md Step 4a и Step 4e; hooks/session-collector.sh:142-145
# печатает готовую команду с плейсхолдером `"<почему>"`). Windows-путь, регулярка,
# экранирование в цитате кода — все дают `\`.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: нет pyyaml"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons" STATE_DIR="$T/state"
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

cat > "$LESSONS_DIR/pattern-probe.md" <<'KN'
---
name: проба
confidence: 4
impact: 3
confirmed_count: 2
contradicted_count: 0
last_confirmed: 2026-01-01
provenance_log: []
---
тело
KN

out=$(bash "$SCRIPT" pattern-probe confirmed 'путь был указан как C:\' 2>&1); brc=$?

err=$(python3 - "$LESSONS_DIR/pattern-probe.md" <<'PY'
import sys, yaml
t = open(sys.argv[1], encoding="utf-8").read()
fm = t.split("\n---\n")[0].lstrip("-\n")
try:
    yaml.safe_load(fm)
    print("")
except Exception as e:
    print(str(e).splitlines()[0])
PY
)

rc=0
if [ -n "$err" ]; then
    echo "FAIL: frontmatter не разбирается после записи — $err"
    rc=1
fi
if [ "$brc" -eq 0 ] && [ -n "$err" ]; then
    echo "FAIL: скрипт вернул 0 и напечатал успех, испортив файл: $out"
    rc=1
fi

if [ "$rc" -ne 0 ]; then
    echo ""
    echo "Ожидание: причина с обратной косой записана как данные, frontmatter остаётся валидным."
    echo "Факт:     скаляр не закрыт. Строки provenance_log:"
    sed -n '/provenance_log:/,/^---/p' "$LESSONS_DIR/pattern-probe.md" | sed 's|^|    |'
    echo "adv bump reason-backslash-yaml: КРАСНЫЙ"
else
    echo "adv bump reason-backslash-yaml: 1/1 passed"
fi
exit "$rc"
