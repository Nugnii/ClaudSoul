#!/usr/bin/env bash
# test_backlog_recheck.sh — перепроверка закрытых пунктов обязана краснеть на откате.
#
# Повод. Закрытия делятся на два вида, и держатся по-разному: за одним стоит тест, и он
# гоняется каждый прогон; за другим — разовое действие (лог вычищен, ссылки восстановлены,
# поле задокументировано), и оно не проверяет себя ничем. Замер 2026-07-29: из 28 закрытых
# пунктов долга 11 держались тестом, 17 — разовым действием. Второй вид может тихо
# откатиться, а пункт останется помеченным «сделано».
#
# Что проверяет этот тест: что сама перепроверка не декоративна. Каждый инвариант ставится
# в положение отката, и скрипт обязан это назвать. Без такой проверки зелёный итог
# «все держатся» означал бы либо порядок, либо неспособность заметить беспорядок —
# а различить их снаружи нельзя.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/backlog-recheck.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: не найден $SCRIPT"; exit 1; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Изолированная копия дерева: продукт и рабочая база не трогаются.
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX/scripts" "$SANDBOX/knowledge" "$SANDBOX/skills/entity" "$SANDBOX/skills/ingest"
cp "$SCRIPT" "$SANDBOX/scripts/"
cp "$REPO/knowledge/META.md" "$SANDBOX/knowledge/" 2>/dev/null
cp "$REPO/skills/entity/SKILL.md" "$SANDBOX/skills/entity/" 2>/dev/null
cp "$REPO/skills/ingest/SKILL.md" "$SANDBOX/skills/ingest/" 2>/dev/null
printf '# BACKLOG\n\n- ☐ **X1** заглушка\n' > "$SANDBOX/BACKLOG.md"

LESS="$TMP/lessons"; STAT="$TMP/state"
mkdir -p "$LESS" "$STAT"
cp "$REPO/knowledge/META.md" "$LESS/" 2>/dev/null
printf '{"date":"2026-07-01T10:00:00Z","file":"pattern-a.md","score":5}\n' > "$STAT/injection-log.jsonl"
cat > "$LESS/pattern-shell-portability.md" <<'SP'
---
name: проба
blocker: true
detection_signals: |
  [
    {
      "name": "probe",
      "all_of": [{"tool_matches": ["Edit"]}]
    }
  ]
---
тело
SP
cat > "$LESS/pattern-target.md" <<'PT'
---
name: мишень
source_cases:
  - case-linked.md
---
тело
PT
printf -- '---\nname: связанный\n---\n- confirms: pattern-target.md\n' > "$LESS/case-linked.md"

run() { CLAUDSOUL_REPO="$SANDBOX" LESSONS_DIR="$LESS" STATE_DIR="$STAT" bash "$SANDBOX/scripts/backlog-recheck.sh" 2>&1; }

# --- T1: на согласованном состоянии всё держится ---
OUT=$(run); RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'все держатся'; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T1]: ожидался зелёный итог, получено rc=$RC: $(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"; fi

# --- T2..T5: каждый инвариант ставится в положение отката и обязан быть назван ---
# Обе стороны обязательны: без этих случаев зелёный T1 не отличим от неспособности заметить.
break_and_check() { # $1=что ломаем (команда) $2=подстрока в отчёте $3=имя случая
    eval "$1"
    o=$(run); rc=$?
    if [ "$rc" -ne 0 ] && printf '%s' "$o" | grep -qF "$2"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: откат не назван (rc=$rc). Отчёт: $(printf '%s' "$o" | grep '✗' | head -1)"; fi
}

# лог инжектов снова содержит нечитаемую строку
break_and_check "printf 'не json\\n' >> '$STAT/injection-log.jsonl'" "нечитаемых строк" "T2 битая строка в логе"
python3 - "$STAT/injection-log.jsonl" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text("".join(l for l in p.read_text().splitlines(True) if l.startswith("{")))
PY

# ссылка кейс → паттерн снова односторонняя
break_and_check "python3 -c \"
import pathlib
p = pathlib.Path('$LESS/pattern-target.md'); t = p.read_text()
p.write_text(t.replace('  - case-linked.md', '  - case-other.md'))\"" "односторонних ссылок" "T3 односторонняя ссылка"
python3 -c "
import pathlib
p = pathlib.Path('$LESS/pattern-target.md'); t = p.read_text()
p.write_text(t.replace('  - case-other.md', '  - case-linked.md'))"

# из описания скилла пропала фраза автовызова
break_and_check "python3 -c \"
import pathlib
p = pathlib.Path('$SANDBOX/skills/ingest/SKILL.md'); t = p.read_text()
p.write_text(t.replace('добавь в базу знаний', 'внеси'))\"" "пропала фраза" "T4 фраза автовызова вырезана"
cp "$REPO/skills/ingest/SKILL.md" "$SANDBOX/skills/ingest/" 2>/dev/null

# у блокера опустели сигналы детекции
break_and_check "python3 -c \"
import pathlib, re
p = pathlib.Path('$LESS/pattern-shell-portability.md'); t = p.read_text()
p.write_text(re.sub(r'detection_signals: \|\n(?:  .*\n)+', 'detection_signals: []\n', t))\"" "detection_signals" "T5 блокер без сигналов"

echo ""
echo "backlog recheck tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
