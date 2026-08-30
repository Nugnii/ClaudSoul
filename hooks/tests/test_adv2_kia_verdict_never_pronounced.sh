#!/usr/bin/env bash
# АТАКА: пункт покидает очередь по вердикту, которого никто не выносил.
#
# knowledge-instrument-audit.sh:76-78 — field() ищет `^ключ:` по ВСЕМУ файлу, без
# границы frontmatter, и берёт ПЕРВОЕ совпадение. Отсюда две дыры разом:
#
#   (а) строка `instrument_verdict: covered` в ТЕЛЕ знания (цитата формата, пример
#       разбора, кусок процедуры) читается как поле знания. Знание, которого никто
#       не разбирал, уходит из очереди в раздел «Оценены: инструментом не станут» —
#       в колонке «Когда» стоит прочерк, потому что разбора не было;
#
#   (б) два поля `instrument_verdict` в шапке: побеждает ПЕРВОЕ. YAML читает
#       дубликат наоборот — последнее. Значит устаревший `covered` выше по файлу
#       побивает действующий `candidate`, и пункт исчезает из работы.
#
# Это ровно D106 наизнанку: «реестр, из которого пункт уходит, ничего не построив,
# не имеет условия выхода — он имеет способ из него исчезнуть» (строки 175-176).
# Способ восстановлен: достаточно процитировать формат в тексте знания.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
FAILED=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s: %s\n' "$1" "$2"; FAILED=1; }

run_case() {  # $1 = каталог, печатает stdout замера в STDOUT/REPORT
    STDOUT=$(LESSONS_DIR="$1/l" STATE_DIR="$1/s" bash "$AUDIT" 2>&1)
    REPORT=$(cat "$1/s/knowledge-instrument.md")
}

# --- (а) вердикт из тела знания ---
A=$(mktemp -d); mkdir -p "$A/l" "$A/s"; trap 'rm -rf "$A" "${B:-}"' EXIT
cat > "$A/l/pattern-quotes-format.md" <<'EOF'
---
outcome: error
status: active
confidence: 4
impact: 4
confirmed_count: 11
description: Разбора не было, вердикта в шапке нет
---
Как пункт покидает очередь: в само знание дописывают поле, например

instrument_verdict: covered

и на следующем прогоне пункта в очереди нет.
EOF
run_case "$A"
echo "--- (а) stdout ---"; printf '%s\n' "$STDOUT"
echo "--- (а) отчёт ---"; grep -A4 'Оценены' <<< "$REPORT"

if grep -q 'очередь на производство: 1' <<< "$STDOUT"; then
    ok "A1 знание осталось в очереди — цитата формата вердиктом не считается"
else
    bad "A1" "знание без вердикта в шапке выведено из очереди строкой из ТЕЛА: $(grep 'очередь на производство' <<< "$STDOUT")"
fi
if grep -q 'pattern-quotes-format' <<< "$(grep -A6 'Оценены' <<< "$REPORT")"; then
    bad "A2" "неразобранное знание значится в разделе «Оценены: инструментом не станут» с вердиктом covered и прочерком в колонке «Когда»"
else
    ok "A2 раздел «Оценены» не приписывает знанию чужой вердикт"
fi

# --- (б) два поля instrument_verdict, действующее — второе ---
B=$(mktemp -d); mkdir -p "$B/l" "$B/s"
cat > "$B/l/pattern-dup-verdict.md" <<'EOF'
---
outcome: error
status: active
confidence: 4
impact: 4
confirmed_count: 11
instrument_verdict: covered     # устаревшая строка, оставлена по недосмотру
instrument_verdict: candidate   # действующий вердикт: выразим, инструмента ещё нет
description: Дубликат ключа, YAML читает последнее значение
---
EOF
run_case "$B"
echo "--- (б) stdout ---"; printf '%s\n' "$STDOUT"

if grep -q 'очередь на производство: 1' <<< "$STDOUT"; then
    ok "B1 действующий (последний) вердикт candidate удержал пункт в очереди"
else
    bad "B1" "победило ПЕРВОЕ поле: устаревший covered вывел из очереди пункт, чей действующий вердикт candidate — $(grep 'очередь на производство' <<< "$STDOUT")"
fi

echo
[ "$FAILED" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL"; exit 1; }
