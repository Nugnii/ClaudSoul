#!/usr/bin/env bash
# СУДИТ: scripts/knowledge-coverage.sh
# probe_D248.sh — замер покрытия раскладывает базу по названным причинам и краснеет только на остатке без причины (D248).
#
# Коды: 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
# Рамка: песочные LESSONS_DIR и STATE_DIR с шестью записями; живая база и журнал подач не читаются.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
d=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$d"' EXIT
S="$REPO/scripts/knowledge-coverage.sh"
[ -f "$S" ] || { echo "РАМКА: нет knowledge-coverage.sh"; exit 2; }
mkdir -p "$d/l" "$d/s" || exit 2
rec() { printf -- '---\nconfirmed_count: %s\ncontradicted_count: 0\n---\n%s\n' "$2" "${3:-тело}" > "$d/l/$1.md"; }
today=$(date +%Y-%m-%d)
rec case-2026-01-01-served 5
rec pattern-par 5 "родитель упоминает case-2026-01-03-child"
rec case-2026-01-02-low 0
rec case-2026-01-03-child 0
rec "case-$today-young" 0
printf '{"file":"case-2026-01-01-served.md","injected":true}\n{"file":"pattern-par.md"}\n' > "$d/s/injection-log.jsonl"
rec case-2026-01-04-high 50
run() { LESSONS_DIR="$d/l" STATE_DIR="$d/s" bash "$S" 2>&1; }
out=$(run); rc=$?
[ "$rc" -eq 1 ] && grep -q 'case-2026-01-04-high' <<<"$out" || { echo "НЕ-КРАСНЕЕТ: запись выше медианы без подачи и родителя не названа (код $rc)"; exit 1; }
for n in low child; do grep -q "case-2026-01-0[23]-$n" <<<"$out" && { echo "ЛИШНЕЕ: объяснённая запись $n названа необъяснённой"; exit 1; }; done
grep -q "case-$today-young" <<<"$out" && { echo "ЛИШНЕЕ: молодая запись названа необъяснённой"; exit 1; }
rec pattern-par 5 "родитель упоминает case-2026-01-03-child и case-2026-01-04-high"
out=$(run); rc=$?
[ "$rc" -eq 0 ] || { echo "ЛОЖНЫЙ-КРАСНЫЙ: все записи объяснены, код $rc"; exit 1; }
LESSONS_DIR="$d/нет" STATE_DIR="$d/s" bash "$S" >/dev/null 2>&1; [ $? -eq 2 ] || { echo "НЕТ-БАЗЫ: без базы код не 2"; exit 1; }
exit 0
