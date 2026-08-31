#!/usr/bin/env bash
# test_instrument_queue_age.sh — у пункта очереди «знание → инструмент» есть срок и выход.
#
# Результат: пункт, простоявший дольше порога, роняет замер; вердикт candidate не выпускает.
# Проверка результата: bash hooks/tests/test_instrument_queue_age.sh даёт 0
#
# Зачем (D106). Очередь имела условие выхода (`instrument_verdict`), но не имела срока, и
# один из вердиктов — `candidate` — выпускал пункт, ничего не построив: он означает «признак
# выразим, но инструмента ещё нет». `pattern-subject-of-measurement-mismatch` простоял так с
# 29 июля 2026 в таблице «инструментом не станут», при 28 подтверждениях и impact 5.
#
# Реестр, из которого можно исчезнуть, не построив, — это не условие выхода, а способ
# перестать быть видимым.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
[ -f "$AUDIT" ] || { echo "FAIL: $AUDIT не найден"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LES="$TMP/lessons"; ST="$TMP/state"; mkdir -p "$LES" "$ST"

ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Знание, годное в очередь: pattern, outcome error, подтверждений ≥ порога.
mk() {
    cat > "$LES/$1.md" <<KN
---
type: pattern
confidence: 4
impact: 5
confirmed_count: 9
contradicted_count: 0
outcome: error
status: active
${2:-}
description: "проба"
---

# Тело
KN
}

run() { bash "$AUDIT" 2>&1; }
export LESSONS_DIR="$LES" STATE_DIR="$ST"

# --- T1: свежий пункт очереди замер не роняет ---
mk pattern-fresh
OUT=$(run); RC=$?
[ "$RC" = "0" ] && ok || bad T1 "свежая очередь дала код $RC"
grep -q "очередь на производство: 1" <<< "$OUT" && ok || bad T1b "пункт не попал в очередь: $OUT"

# --- T2: вердикт-ОТКАЗ выпускает из очереди ---
mk pattern-refused 'instrument_verdict: inexpressible   # у проявлений нет признака'
OUT=$(run)
grep -q "очередь на производство: 1" <<< "$OUT" && ok || bad T2 "отказной вердикт не выпустил: $OUT"

# --- T3: КОНТРПРИМЕР — candidate НЕ выпускает: он означает «выразим, но не построен» ---
mk pattern-candidate 'instrument_verdict: candidate   # выразим, инструмента нет'
OUT=$(run)
grep -q "очередь на производство: 2" <<< "$OUT" && ok || bad T3 "candidate выпущен из очереди: $OUT"

# --- T4: просроченный пункт роняет замер кодом 1 (находка), а не ≥2 (отказ) ---
python3 - "$ST/knowledge-instrument-queue.json" <<'PY'
import json, sys, datetime, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
old = (datetime.date.today() - datetime.timedelta(days=99)).isoformat()
d["pattern-fresh"] = old
p.write_text(json.dumps(d))
PY
OUT=$(run); RC=$?
[ "$RC" = "1" ] && ok || bad T4 "просрочка дала код $RC вместо 1"
grep -q "ПРОСРОЧЕНО" <<< "$OUT" && ok || bad T4b "просрочка не названа: $OUT"
grep -q "99 дн. — pattern-fresh" <<< "$OUT" && ok || bad T4c "возраст не назван: $OUT"

# --- T5: покинувший очередь теряет отметку — вернувшись, считает срок заново ---
mk pattern-fresh 'instrument_verdict: covered   # уже покрыт другим гейтом'
run >/dev/null 2>&1
python3 - "$ST/knowledge-instrument-queue.json" <<'PY'
import json, sys, pathlib
d = json.loads(pathlib.Path(sys.argv[1]).read_text())
raise SystemExit(0 if "pattern-fresh" not in d else 1)
PY
[ $? = 0 ] && ok || bad T5 "отметка входа пережила выход из очереди"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
