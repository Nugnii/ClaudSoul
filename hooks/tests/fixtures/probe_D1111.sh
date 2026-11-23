#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh hooks/lib/open-findings-lib.sh scripts/outcome-share.sh
# probe_D1111 — смена смысла `recorded` (D1107) доведена до зависимых. Красная (1), пока: (а) `touched` поверх `deferred`
# той же пары отбрасывается и отложенное висит в сводке открытого (M7); (б) `recorded` поверх `touched` той же пары
# отбрасывается — сверенный исход хода не попадает в долю «сверен» (M7); (в) замер долей считает прежние `recorded`
# (до D1107 — «носитель тронут») сверенными исходами (M8). Рамка не собралась — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/root-cause-lib.sh" ] && [ -f "$R/hooks/lib/open-findings-lib.sh" ] && [ -f "$R/scripts/outcome-share.sh" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1111.XXXXXX") || exit 2
out=$(bash -c '. "$1/hooks/root-cause-lib.sh" && . "$1/hooks/lib/open-findings-lib.sh" || exit 2
    rc_log_outcome "$2" a K1 streak deferred x; rc_log_outcome "$2" a K1 streak touched x
    rc_log_outcome "$2" a K2 streak touched x;  rc_log_outcome "$2" a K2 streak recorded x
    printf "%s|%s|%s\n" "$(jq -r "select(.key==\"K1\") | .outcome" "$2/outcome-a.jsonl" | paste -sd, -)" \
        "$(jq -r "select(.key==\"K2\") | .outcome" "$2/outcome-a.jsonl" | paste -sd, -)" "$(of_open_counts "$2" | awk "{print \$1}")"' _ "$R" "$S") || exit 2
k1=${out%%|*}; rest=${out#*|}; k2=${rest%%|*}; open=${rest#*|}
[ "$k1" = "deferred,touched" ] || { echo "(а) touched поверх deferred отброшен: K1=$k1" >&2; exit 1; }
[ "$open" = "0" ] || { echo "(а) отложенное висит в сводке открытого: $open" >&2; exit 1; }
[ "$k2" = "touched,recorded" ] || { echo "(б) recorded поверх touched отброшен: K2=$k2" >&2; exit 1; }
# (в) прежняя запись `recorded` (без метки новой редакции) — не «сверен»
L="$S/legacy"; mkdir -p "$L" || exit 2
for i in 1 2 3 4 5 6; do printf '{"ts":"2026-10-01T10:00:0%sZ","key":"%s","signal":"rework","outcome":"recorded","ref":""}\n' "$i" "$i"; done > "$L/outcome-old.jsonl"
rep=$(STATE_DIR="$L" bash "$R/scripts/outcome-share.sh" 2>/dev/null)
printf '%s\n' "$rep" | grep -q 'исход сверен 0%' || { echo "(в) прежние recorded посчитаны сверенными: $(printf '%s\n' "$rep" | grep -o 'исход сверен [0-9]*%' | head -1)" >&2; exit 1; }
echo "смена смысла доведена: переходы пары, сводка открытого, замер долей"
exit 0
