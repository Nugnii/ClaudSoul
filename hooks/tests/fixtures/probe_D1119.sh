#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# probe_D1119 — переходы пары (ход, род) после `touched` (D1111) не теряют снятие и отказ. Красная (1), пока
# deferred→touched→chain-spoken теряет цепочку, произнесённую после Stop того же хода, а touched→deferred теряет отказ
# (скептик D1108, L3). Положительный контроль: deferred→touched→recorded сохраняет все три. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/root-cause-lib.sh" ] && command -v jq >/dev/null 2>&1 || exit 2
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1119.XXXXXX") || exit 2
out=$(bash -c '. "$1/hooks/root-cause-lib.sh" || exit 2
    i=0; for s in "deferred touched recorded" "deferred touched chain-spoken" "touched deferred"; do
        i=$((i+1)); for o in $s; do rc_log_outcome "$2" a "K$i" streak "$o" x; done
        printf "%s\n" "$(jq -r "select(.key==\"K$i\") | .outcome" "$2/outcome-a.jsonl" | paste -sd, -)"; done' _ "$R" "$S") || exit 2
k1=$(printf '%s\n' "$out" | sed -n 1p); k2=$(printf '%s\n' "$out" | sed -n 2p); k3=$(printf '%s\n' "$out" | sed -n 3p)
[ "$k1" = "deferred,touched,recorded" ] || exit 2
case "$k2" in *chain-spoken*) ;; *) echo "deferred→touched→chain-spoken: цепочка потеряна ($k2)" >&2; exit 1 ;; esac
case "$k3" in *deferred*) ;; *) echo "touched→deferred: отказ потерян ($k3)" >&2; exit 1 ;; esac
echo "переходы после touched сохраняют снятие и отказ"
exit 0
