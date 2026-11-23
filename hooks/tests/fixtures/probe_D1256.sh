#!/usr/bin/env bash
set -u
# СУДИТ: hooks/lib/open-findings-lib.sh
# probe_D1256 — свод «Поводов разбора без исхода» зовёт довести до исхода только поводы видов с правом на отказ: счёт
#   `of_open_counts` (`hooks/lib/open-findings-lib.sh`) в каталоге состояния, где лежит
#   (с) только `deferred` стоячего вида (`event`) — отложенных 0, ему исход не нужен (отказа он не держал);
#   (п) плюс `deferred` вида с правом на отказ (`rework`) — отложенных 1 (положительный контроль).
# Код: 0 — так; 1 — нет (названо); 2 — нет предмета, python3 или счёт не ответил.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
L="$R/hooks/lib/open-findings-lib.sh"
[ -f "$L" ] && command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
# shellcheck source=/dev/null
. "$L" 2>/dev/null || exit 2
rec() { printf '{"ts":"2026-11-05T19:39:1%sZ","key":"336509584","signal":"%s","outcome":"deferred","ref":"x","v":2}\n' "$1" "$2"; }
mkdir -p "$W/s"
rec 0 event > "$W/s/outcome-d1256.jsonl"
s=$(of_open_counts "$W/s" 2>/dev/null | awk '{print $1}')
rec 1 rework >> "$W/s/outcome-d1256.jsonl"
p=$(of_open_counts "$W/s" 2>/dev/null | awk '{print $1}')
case "${s}${p}" in *[!0-9]*|'') echo "счёт не ответил: «${s}» / «${p}»"; exit 2 ;; esac
miss=""
[ "$s" = 0 ] || miss="$miss стоячий deferred (event) зовётся довести до исхода: отложено $s;"
[ "$p" = 1 ] || miss="$miss deferred вида с правом на отказ (rework) не посчитан ровно один: отложено $p;"
[ -z "$miss" ] && { echo "стоячие поводы исхода не требуют, поводы с правом на отказ считаются (отложено: $s и $p)"; exit 0; }
echo "не держится:$miss"
exit 1
