#!/usr/bin/env bash
# СУДИТ: scripts/state-prune.sh scripts/state-size.sh
# probe_D252.sh — уборщик состояния режет посессионное за окном, щадит очередь долга, файл без сессии и копии
# без флага, а замер объёма краснеет на превышении порога (D252).
#
# Коды: 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
# Рамка: песочные STATE_DIR, HOME и SR_SESSIONS_DIR; живой каталог состояния не читается.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
d=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$d"' EXIT
P="$REPO/scripts/state-prune.sh"; Z="$REPO/scripts/state-size.sh"
[ -f "$P" ] && [ -f "$Z" ] || { echo "РАМКА: нет state-prune.sh или state-size.sh"; exit 2; }
ST="$d/state"; mkdir -p "$ST" "$d/.claude/sessions" || exit 2
sid() { printf '%08x-1111-2222-3333-%012x' "$1" "$1"; }
for i in $(seq 1 70); do : > "$ST/session-speaker_$(sid "$i")"; done
for i in $(seq 1 70); do : > "$ST/disagreement-pending-$(sid "$i").jsonl"; done
for i in 1 2 3 4 5; do : > "$ST/thing.jsonl.bak.10000$i"; done
: > "$ST/injection-log.jsonl"
cnt() { find "$ST" -maxdepth 1 -type f -name "$1" | wc -l | tr -d ' '; }
run() { STATE_DIR="$ST" HOME="$d" SR_SESSIONS_DIR="$d/.claude/sessions" bash "$P" "$@" >/dev/null 2>&1; }
run; [ "$(cnt 'session-speaker_*')" = 70 ] || { echo "СУХОЙ-УДАЛИЛ: сухой прогон тронул файлы"; exit 1; }
run --apply
[ "$(cnt 'session-speaker_*')" = 60 ] || { echo "ОКНО: осталось $(cnt 'session-speaker_*') из 70, ждали 60"; exit 1; }
[ "$(cnt 'disagreement-pending-*')" = 70 ] || { echo "ОЧЕРЕДЬ: тронута очередь незакрытого долга"; exit 1; }
[ -f "$ST/injection-log.jsonl" ] || { echo "БЕЗ-СЕССИИ: удалён файл без идентификатора сессии"; exit 1; }
[ "$(cnt 'thing.jsonl.bak.*')" = 5 ] || { echo "КОПИИ: удалены без --include-backups"; exit 1; }
run --apply --include-backups
[ "$(cnt 'thing.jsonl.bak.*')" = 3 ] || { echo "КОПИИ: после флага осталось $(cnt 'thing.jsonl.bak.*'), ждали 3"; exit 1; }
# замер объёма: порог превышен — 1, не превышен — 0
STATE_DIR="$ST" STATE_MAX_FILES=1 bash "$Z" >/dev/null 2>&1; [ $? -eq 1 ] || { echo "ПОРОГ: превышение числа файлов не дало 1"; exit 1; }
STATE_DIR="$ST" STATE_MAX_FILES=100000 STATE_MAX_MB=100000 bash "$Z" >/dev/null 2>&1 || { echo "ПОРОГ: под порогом не 0"; exit 1; }
exit 0
