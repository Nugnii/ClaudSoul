#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# probe_D1125 — позднейший отказ пары (ход, вид) не теряется: deferred→touched→deferred сохраняет второй отказ, а повтор
# последнего исхода отбрасывается. Красная (1), пока второй отказ отброшен проверкой «тот же исход уже есть в паре»
# (третий скептик по D1115–D1120, M1: Stop бывает в ходе не единожды, отказ после Stop — самая частая форма).
# Положительный контроль — deferred→touched→recorded. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/root-cause-lib.sh" ] && command -v jq >/dev/null 2>&1 || exit 2
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1125.XXXXXX") || exit 2
out=$(bash -c '. "$1/hooks/root-cause-lib.sh" || exit 2
    i=0; for s in "deferred touched recorded" "deferred touched deferred" "deferred touched deferred deferred"; do
        i=$((i+1)); for o in $s; do rc_log_outcome "$2" a "K$i" streak "$o" x; done
        printf "%s\n" "$(jq -r "select(.key==\"K$i\") | .outcome" "$2/outcome-a.jsonl" | paste -sd, -)"; done' _ "$R" "$S") || exit 2
k1=$(sed -n 1p <<< "$out"); k2=$(sed -n 2p <<< "$out"); k3=$(sed -n 3p <<< "$out")
[ "$k1" = "deferred,touched,recorded" ] || exit 2
[ "$k2" = "deferred,touched,deferred" ] || { echo "deferred→touched→deferred: позднейший отказ потерян ($k2)" >&2; exit 1; }
[ "$k3" = "deferred,touched,deferred" ] || { echo "повтор последнего исхода не отброшен ($k3)" >&2; exit 1; }
echo "позднейший отказ сохранён, повтор отброшен"
exit 0
