#!/usr/bin/env bash
# test_adv_bump_journal_confidence_is_counter.sh — АТАКА: в durable-журнал под именем
# `confidence` пишется НЕ confidence, а confirmed_count.
#
# Ветки confirmed/contradicted берут третий аргумент журнальной функции так (строка 298):
#
#     CONF_NOW=$(show_counters | awk -F': ' '/^confirmed_count/ { print $2 }')
#     CLOSED=$(dis_close_outcome "$OUT_NAME" "$JOURNAL_OUTCOME" "${CONF_NOW:-0}" "$REASON")
#
# а `dis_close_outcome` кладёт его в поле `"confidence":%s` (строка 100). То есть колонка
# уверенности заполняется счётчиком подтверждений. Ветка not_applicable в том же файле
# (строка 141) берёт НАСТОЯЩЕЕ поле — `awk '/^confidence:/{print $2; exit}'`. Одна колонка
# одного журнала означает две разные величины в зависимости от исхода.
#
# Хуже для ветки contradicted: там в «уверенность» уезжает счётчик ПОДТВЕРЖДЕНИЙ,
# к событию отношения не имеющий вовсе.
#
# Достижимость: срабатывает на КАЖДОМ вызове confirmed/contradicted, обходных путей нет.
# Замер боевого журнала ~/.claude/hooks/state/disagreement-outcomes.jsonl на 2026-08-29:
# из 101 записи confirmed_knowledge/outdated_knowledge, чьё знание ещё лежит в базе,
# 55 расходятся с полем confidence своего знания (пример: pattern-verification-frame-
# mismatch — в журнале 3, в знании confidence 4 при confirmed_count 25). Совпадения
# в остальных 46 случайны: обе величины — малые целые.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons" STATE_DIR="$T/state"
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

mk() {
cat > "$LESSONS_DIR/$1" <<'KN'
---
name: проба
confidence: 5
impact: 3
confirmed_count: 11
contradicted_count: 0
provenance_log: []
---
тело
KN
}
mk pattern-conf.md
mk pattern-contra.md
mk pattern-na.md

bash "$SCRIPT" pattern-conf   confirmed      "подтвердилось"  >/dev/null 2>&1
bash "$SCRIPT" pattern-contra contradicted   "разошлось"      >/dev/null 2>&1
bash "$SCRIPT" pattern-na     not_applicable "мимо"           >/dev/null 2>&1

J="$STATE_DIR/disagreement-outcomes.jsonl"
field() { grep "\"knowledge\":\"$1\"" "$J" | sed -n 's/.*"confidence":\([^,]*\),.*/\1/p' | tail -1; }

c_conf=$(field pattern-conf.md)
c_contra=$(field pattern-contra.md)
c_na=$(field pattern-na.md)
echo "знание: confidence=5, confirmed_count=11"
echo "  журнал после confirmed:      confidence=$c_conf"
echo "  журнал после contradicted:   confidence=$c_contra"
echo "  журнал после not_applicable: confidence=$c_na  (эталон — читает настоящее поле)"

rc=0
[ "$c_conf"   = "5" ] || { echo "FAIL: после confirmed в журнале '$c_conf' вместо confidence=5"; rc=1; }
[ "$c_contra" = "5" ] || { echo "FAIL: после contradicted в журнале '$c_contra' вместо confidence=5"; rc=1; }
[ "$c_na"     = "5" ] || { echo "FAIL: ветка not_applicable тоже разошлась — '$c_na'"; rc=1; }

if [ "$rc" -ne 0 ]; then
    echo ""
    echo "Ожидание: поле confidence журнала равно полю confidence знания при любом исходе."
    echo "Факт:     две ветки из трёх пишут туда confirmed_count. Строки журнала:"
    sed 's|^|    |' "$J"
    echo "adv bump journal-confidence-is-counter: КРАСНЫЙ"
else
    echo "adv bump journal-confidence-is-counter: 3/3 passed"
fi
exit "$rc"
