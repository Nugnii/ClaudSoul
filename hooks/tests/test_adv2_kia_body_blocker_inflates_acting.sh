#!/usr/bin/env bash
# АТАКА: пример blocker-поля в ТЕЛЕ знания считается действующим гейтом — головное
# число замера завышается.
#
# knowledge-instrument-audit.sh:131 — `re.search(r"^blocker: true", t, re.M)` по ВСЕМУ
# файлу, без границы frontmatter. Строка 81 так же ищет `detection_signals: |`
# где угодно. Знание, которое ОПИСЫВАЕТ устройство blocker-tier (а такие в базе есть —
# principle-knowledge-in-the-world и вся ветка про уровни укоренённости), приводит
# пример в теле — и попадает в «действует».
#
# «Действует» — то самое число, ради которого замер заведён: доля базы, способная
# стоять на пути действия. Знание из примера ни перед каким действием не проверяется:
# в шапке у него нет ни blocker, ни сигналов, хук его не увидит.
#
# Вторая половина ущерба: в очередь на производство оно тоже не попадает (строка 157
# `continue`) — знание с outcome: error и 12 подтверждениями исчезает из работы,
# потому что процитировало формат.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
FAILED=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s: %s\n' "$1" "$2"; FAILED=1; }

T=$(mktemp -d); L="$T/l"; S="$T/s"; mkdir -p "$L" "$S"
trap 'rm -rf "$T"' EXIT

# Знание О blocker-tier. В шапке blocker нет — гейтом оно не является.
cat > "$L/principle-about-blockers.md" <<'EOF'
---
outcome: error
status: active
confidence: 5
impact: 5
confirmed_count: 12
description: Правило в тексте хрупко; уровни укоренённости знания
---
Четвёртый уровень выглядит так — и это ПРИМЕР В ТЕКСТЕ, а не поля этого знания:

blocker: true
detection_signals: |
  {"tool_input_regex": "rm -rf"}

Ни один хук по этому знанию не сработает: в его шапке нет ни blocker, ни сигналов.
EOF

STDOUT=$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$AUDIT" 2>&1); RC=$?
REPORT=$(cat "$S/knowledge-instrument.md")

echo "--- stdout ---"; printf '%s\n' "$STDOUT"
echo "--- таблица уровней ---"; grep -E '^\| (хранится|\*\*действует)' <<< "$REPORT"
echo "--- очередь ---"; grep -A2 'Очередь на производство' <<< "$REPORT"

if grep -q 'действует 0' <<< "$STDOUT"; then
    ok "T1 знание с примером в теле не засчитано как гейт"
else
    ACT=$(sed -n 's/.*действует \([0-9]*\).*/\1/p' <<< "$STDOUT" | head -1)
    bad "T1" "«действует» = ${ACT:-?}: пример blocker-поля в теле знания посчитан действующим гейтом"
fi

if grep -q '| \*\*действует\*\* (гейт перед действием) | \*\*0\*\*' <<< "$REPORT"; then
    ok "T2 таблица уровней не завышена"
else
    bad "T2" "строка таблицы: $(grep -E '^\| \*\*действует' <<< "$REPORT")"
fi

# T3: знание с outcome: error и 12 подтверждениями обязано стоять в очереди —
# оно не гейт, а описание гейта.
if grep -q 'principle-about-blockers' <<< "$REPORT"; then
    ok "T3 знание видно в очереди на производство"
else
    bad "T3" "знание (outcome: error, 12 подтверждений) исчезло из очереди: ветка is_blocker увела его в «действует» и сделала continue"
fi

echo
[ "$FAILED" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL"; exit 1; }
