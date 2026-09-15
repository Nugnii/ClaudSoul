#!/usr/bin/env bash
# test_communication_cap.sh — потолок n=1 для знаний об одном собеседнике (D251).
# Ловушка: «нарушений нет» легко получить признаком, который не ловит ничего. Поэтому у
# каждого нарушителя рядом стоит контрпример, который признак обязан пропустить.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/scripts/communication-cap-check.sh"
[ -f "$S" ] || { echo "FAIL: нет $S"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mk() { printf 'type: %s\nconfidence: %s\nscope: %s\nvalid_for: [%s]\ndomain: [%s]\n' \
       "${2:-pattern}" "$3" "$4" "$5" "${6:-communication}" > "$TMP/$1.md"; }

# Нарушители: заявленная односторонность и confidence выше потолка.
mk one-speaker-5   pattern 5 per-speaker primary
mk one-speaker-3   pattern 3 mixed       primary
# Контрпримеры, которые признак обязан ПРОПУСТИТЬ:
mk two-speakers-5  pattern 5 per-speaker "primary, second"   # второй собеседник есть
mk at-cap-2        pattern 2 per-speaker primary             # на потолке, не выше
mk no-scope-5      principle 5 ""        ""  "cognitive_architecture, communication"

OUT=$(LESSONS_DIR="$TMP" bash "$S" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok || bad T1 "код возврата $RC, ждали 1"
grep -q "one-speaker-5" <<< "$OUT" && ok || bad T2 "не назван нарушитель с confidence 5"
grep -q "one-speaker-3" <<< "$OUT" && ok || bad T3 "не назван нарушитель scope=mixed"
grep -q "two-speakers-5" <<< "$OUT" && bad T4 "обвинено знание с ДВУМЯ собеседниками" || ok
grep -q "at-cap-2" <<< "$OUT" && bad T5 "обвинено знание НА потолке" || ok
grep -q "no-scope-5" <<< "$OUT" && bad T6 "обвинено знание без per-speaker scope" || ok

# Чистая база — код 0, и это состояние мира, а не молчание прибора.
rm -f "$TMP/one-speaker-5.md" "$TMP/one-speaker-3.md"
OUT=$(LESSONS_DIR="$TMP" bash "$S" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T7 "чистая база дала $RC"
grep -q "соблюдён" <<< "$OUT" && ok || bad T8 "чистая база молчит вместо утверждения: $OUT"

echo "communication cap: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
