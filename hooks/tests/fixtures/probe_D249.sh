#!/usr/bin/env bash
# СУДИТ: scripts/measurements.tsv
# probe_D249.sh — замер index-freshness различает свежий индекс, отставший, отсутствующий (D249).
#
# Коды: 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
# Рамка: команда замера берётся из реестра и запускается под песочным HOME; живой индекс не читается.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
d=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$d"' EXIT
row=$(awk -F'\t' '$1=="index-freshness"{print $2 "\t" $3; exit}' "$REPO/scripts/measurements.tsv" 2>/dev/null)
[ -n "$row" ] || { echo "РЕЕСТР: строки index-freshness нет"; exit 1; }
period=${row%%$'\t'*}; cmd=${row#*$'\t'}
[ "$period" -le 1 ] 2>/dev/null || { echo "ПЕРИОД: у index-freshness период '$period', ждали не больше 1 дня"; exit 1; }
L="$d/home/.claude/global-lessons"
mkdir -p "$L/_drafts" || exit 2
: > "$L/a.md"; : > "$L/META.md"; : > "$L/_x.md"
touch -t 202601010000 "$L/a.md" "$L/META.md" "$L/_x.md"
m() { HOME="$d/home" bash -c "$cmd" >/dev/null 2>&1; }
m; [ $? -eq 2 ] || { echo "НЕТ-ИНДЕКСА: без knowledge.db код не 2"; exit 1; }
: > "$d/home/.claude/knowledge.db"; touch -t 202601020000 "$d/home/.claude/knowledge.db"
m || { echo "ЛОЖНЫЙ-КРАСНЫЙ: свежий индекс признан отставшим"; exit 1; }
: > "$L/_drafts/b.md"; touch -t 202601030000 "$L/_drafts/b.md" "$L/META.md" "$L/_x.md"
m || { echo "ЛИШНЕЕ: _drafts, META.md и _* потребовали переиндексации"; exit 1; }
: > "$L/c.md"; touch -t 202601030000 "$L/c.md"
m; [ $? -eq 1 ] || { echo "НЕ-ВИДИТ: знание новее индекса не дало код 1"; exit 1; }
exit 0
