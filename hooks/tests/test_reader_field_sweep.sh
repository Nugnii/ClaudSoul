#!/usr/bin/env bash
# test_reader_field_sweep.sh — читатель, просящий поле, которого писатель не кладёт, назван;
# население и сверка считаются одним кодом, «не сверено» держит проверку красной.
#
# Предмет (D359). До 12 сентября 2026 население считал отдельный grep, а сверка открывала
# только `*.jsonl` — «1 из 5» сравнивало разные множества. Ноги: положительный контроль
# (T1), вложенный путь поля в одиночном json (T2/T3), чтение вне состояния исключено (T4),
# семейство без живых записей — «не сверено», и это красно (T5), python-читатель по
# переменной из json.loads (T6), чистое дерево — код 0 (T7), пустое состояние — отказ (T8).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
RFS="$ROOT/scripts/reader-field-sweep.py"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/hooks/lib" "$R/scripts" "$TMP/state" "$TMP/sessions"
SID=0123abcd-1111-2222-3333-444444444444
printf '{"path":"a.sh","ts":1}\n{"path":"b.sh","ts":2}\n' > "$TMP/state/alpha-$SID.jsonl"
printf '{"state":{"current":"idle","reasons":["x"]},"budget":{}}\n' > "$TMP/state/intr-$SID.json"
printf '{"session_id":"s"}\n' > "$TMP/sessions/last-session.json"
run() { ( cd "$R" && RFS_REPO="$R" STATE_DIR="$TMP/state" SR_SESSIONS_DIR="$TMP/sessions" python3 "$RFS" "$@" 2>&1 ); }

# Фикстура «всё чисто»: два shell-читателя и один python-читатель, поля живые.
cat > "$R/hooks/good.sh" <<'H'
A="$STATE/alpha-${SID}.jsonl"
I="$STATE_DIR/intr-${SESSION_ID}.json"
p=$(jq -r '.path' "$A")
c=$(jq -r '.state.current // "idle"' "$I")
H
cat > "$R/hooks/lib/reg.sh" <<'H'
LAST="$SR_SESSIONS_DIR/last-session.json"
s=$(jq -r '.session_id' "$LAST")
H
cat > "$R/scripts/z.py" <<'P'
import json, os
STATE = os.environ.get("STATE_DIR")
for line in open(os.path.join(STATE, "alpha-*.jsonl")):
    rec = json.loads(line)
    print(rec.get("path"), rec["ts"])
P

# T7 (сначала — база): чистое дерево даёт код 0 и итог «не сверено 0».
out=$(run --check); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'сверено 5, не сверено 0' <<< "$out"; then ok
else bad "T7" "чистое дерево: rc=$rc, «$(tail -2 <<< "$out" | tr '\n' ' ')»"; fi

# T1: ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ — читатель просит .file у записей с .path (сцена 7 сентября).
printf 'A="$STATE/alpha-${SID}.jsonl"\nf=$(jq -r %s "$A")\n' "'.file'" > "$R/hooks/badreader.sh"
out=$(run --check); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'hooks/badreader.sh:2 просит .file у alpha' <<< "$out" && grep -q '^РАСХОЖДЕНИЕ' <<< "$out"; then ok
else bad "T1" "расхождение не названо: rc=$rc, «$(head -3 <<< "$out" | tr '\n' ' ')»"; fi
rm -f "$R/hooks/badreader.sh"

# T2/T3: вложенный путь поля в одиночном json — живой проходит, выдуманный краснеет.
printf 'I="$STATE_DIR/intr-${SESSION_ID}.json"\nm=$(jq -r %s "$I")\n' "'.state.mood'" > "$R/hooks/nested.sh"
out=$(run --check); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'nested.sh:2 просит .state.mood у intr' <<< "$out"; then ok
else bad "T3" "выдуманный вложенный путь не назван: «$(head -2 <<< "$out" | tr '\n' ' ')»"; fi
grep -q 'good.sh:4' <<< "$out" && bad "T2" "живой вложенный путь .state.current назван расхождением" || ok
rm -f "$R/hooks/nested.sh"

# T4: чтение файла ВНЕ каталогов состояния — не население, а названное исключение.
printf 'SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"\nh=$(jq -r %s "$SETTINGS")\n' "'.hooks'" > "$R/hooks/outside.sh"
out=$(run --check); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'вне состояния 1' <<< "$out" && grep -q 'сверено 5, не сверено 0' <<< "$out"; then ok
else bad "T4" "чтение вне состояния попало в население: rc=$rc, «$(tail -1 <<< "$out")»"; fi
rm -f "$R/hooks/outside.sh"

# T5: семейство без живых записей — «не сверено», и это КРАСНО даже при нуле расхождений:
# «не смотрели» не равно «чисто».
printf 'G="$STATE/ghost-${SID}.jsonl"\ng=$(jq -r %s "$G")\n' "'.x'" > "$R/hooks/ghost.sh"
out=$(run --check); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'ghost.sh:2 просит .x у ghost — живых записей семейства нет' <<< "$out" && grep -q 'не сверено 1' <<< "$out" && grep -q '^ЧИСТО' <<< "$out"; then ok
else bad "T5" "семейство без записей не удержало красное: rc=$rc, «$(tail -2 <<< "$out" | tr '\n' ' ')»"; fi
rm -f "$R/hooks/ghost.sh"

# T6: python-читатель — поле у переменной из json.loads, которого в семействе нет.
printf 'import json\nfor line in open("alpha-*.jsonl"):\n    rec = json.loads(line)\n    print(rec.get("nope"))\n' > "$R/scripts/bad.py"
out=$(run --check); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'scripts/bad.py:4 просит .nope у alpha' <<< "$out"; then ok
else bad "T6" "python-читатель выдуманного поля не назван: rc=$rc, «$(head -2 <<< "$out" | tr '\n' ' ')»"; fi
rm -f "$R/scripts/bad.py"

# T9: поле, которое писатель начал класть ПОЗЖЕ, живёт только в хвосте файла: голова из
# старых записей не должна объявлять его выдуманным (сцена intrusiveness-history: 95 старых
# записей без `boundary`, 4628 с ним).
{ for i in $(seq 1 60); do printf '{"path":"old%s.sh"}\n' "$i"; done; printf '{"path":"new.sh","boundary":"stop"}\n'; } > "$TMP/state/grown-$SID.jsonl"
printf 'G="$STATE/grown-${SID}.jsonl"\nb=$(jq -r %s "$G")\n' "'.boundary'" > "$R/hooks/tailfield.sh"
out=$(run --check); rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'tailfield.sh' <<< "$out"; then ok
else bad "T9" "поле из хвоста файла названо выдуманным: rc=$rc, «$(head -2 <<< "$out" | tr '\n' ' ')»"; fi
rm -f "$R/hooks/tailfield.sh" "$TMP/state/grown-$SID.jsonl"

# T8: пустое состояние — отказ прибора (2), а не «чисто».
out=$( cd "$R" && RFS_REPO="$R" STATE_DIR="$TMP/empty" SR_SESSIONS_DIR="$TMP/empty2" python3 "$RFS" --check 2>&1 ); rc=$?
if [ "$rc" -eq 2 ] && grep -q '^BROKEN' <<< "$out"; then ok
else bad "T8" "пустое состояние не дало отказ: rc=$rc, «${out}»"; fi

echo ""
echo "reader-field-sweep: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
