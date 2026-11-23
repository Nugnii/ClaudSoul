#!/usr/bin/env bash
# СУДИТ: scripts/reader-field-sweep.py
# D359: сверщик читателей состояния на песочном состоянии и песочном «дереве»: чистое — 0,
# читатель просит .file у записей с .path — 1 и названо, семейство без записей — 1 («не сверено»).
# Живое состояние ~/.claude и живые хуки не читаются. 0 — держится; 1 — нарушено; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
RFS="$R/scripts/reader-field-sweep.py"
[ -f "$RFS" ] || { echo "рамка: нет прибора" >&2; exit 2; }
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/repo/hooks" "$d/state" "$d/sessions" || exit 2
SID=0123abcd-1111-2222-3333-444444444444
printf '{"path":"a.sh","ts":1}\n{"path":"b.sh","ts":2}\n' > "$d/state/alpha-$SID.jsonl"
printf '{"session_id":"s"}\n' > "$d/sessions/last-session.json"
run() { ( cd "$d/repo" && RFS_REPO="$d/repo" STATE_DIR="$d/state" SR_SESSIONS_DIR="$d/sessions" python3 "$RFS" --check 2>&1 ); }
printf 'A="$STATE/alpha-${SID}.jsonl"\np=$(jq -r %s "$A")\n' "'.path'" > "$d/repo/hooks/good.sh"
out=$(run); rc=$?
[ "$rc" -eq 0 ] || { echo "чистое дерево не дало 0: rc=$rc"; exit 1; }
printf 'A="$STATE/alpha-${SID}.jsonl"\nf=$(jq -r %s "$A")\n' "'.file'" > "$d/repo/hooks/bad.sh"
out=$(run); rc=$?
{ [ "$rc" -eq 1 ] && grep -q 'hooks/bad.sh:2 просит .file у alpha' <<<"$out"; } || { echo "РАСХОЖДЕНИЕ .file/.path не названо: rc=$rc"; exit 1; }
rm -f "$d/repo/hooks/bad.sh"
printf 'G="$STATE/ghost-${SID}.jsonl"\ng=$(jq -r %s "$G")\n' "'.x'" > "$d/repo/hooks/ghost.sh"
out=$(run); rc=$?
{ [ "$rc" -eq 1 ] && grep -q 'ghost.sh:2 просит .x у ghost' <<<"$out"; } || { echo "семейство без записей не держит красное («не сверено»): rc=$rc"; exit 1; }
exit 0
