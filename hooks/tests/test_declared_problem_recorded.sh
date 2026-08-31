#!/usr/bin/env bash
# test_declared_problem_recorded.sh — названная проблема обязана лечь в носитель (D103).
#
# Повод — поправка собеседника 28 августа 2026: «ты сейчас декларируешь проблему и не
# записываешь её и если я ничего не скажу, не замечу, то она будет повторяться». И там же:
# «если не взялся сразу, то должен был в бэклог записать. А вдруг бы я вкладку закрыл?»
#
# Признак НЕ новый перечень слов: гейт разбора уже отличает находку и ведёт журнал
# срабатываний. Сигнал — «в сессии была находка», проверка — «менялся ли носитель».
# Заводить второй словарь означало бы повторить D102 в тот же день.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/declared-problem-recorded.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
S="$TMP/state"; B="$TMP/repo"; K="$TMP/lessons"
mkdir -p "$S" "$B" "$K"
printf 'долг\n' > "$B/BACKLOG.md"

run() { printf '{"session_id":"%s","hook_event_name":"Stop"}' "$1" \
        | STATE_DIR="$S" DPR_BACKLOG="$B/BACKLOG.md" DPR_LESSONS="$K" bash "$HOOK" 2>/dev/null; }

# 1. Поводов разбора нет — тишина, что бы ни лежало в носителях.
# Прежде здесь лежало `repeat:x` и ожидалась тишина: предмет стража был сужен до находки
# (`discovery:`), и шесть остальных сродов не проверялись — при 195 срабатываниях из 231.
# С 29 августа 2026 повод любого срода требует исхода, поэтому «поводов нет» задаётся
# журналом БЕЗ сродов, а не журналом с чужим сродом.
printf 'turn:1|\n' > "$S/five-whys-s1.seen"; touch "$S/probe-s1"
[ -z "$(run s1 | tr -d '[:space:]')" ] && ok || bad "без поводов" "шум там, где поводов не было"

# 2. Повод был, носители НЕ менялись — гейт говорит.
printf 'turn:1|discovery:123|\n' > "$S/five-whys-s2.seen"; touch "$S/probe-s2"
sleep 1; : # носители старше маркеров сессии не становятся
OUT=$(run s2)
grep -qi "не оставил следа" <<< "$OUT" && ok || bad "объявлено без записи" "молчит там, где находка не записана: $OUT"

# 3. Находка была И долг менялся после начала сессии — тишина.
printf 'turn:1|discovery:123|\n' > "$S/five-whys-s3.seen"; touch "$S/probe-s3"
sleep 1; printf 'долг\n- новый пункт\n' > "$B/BACKLOG.md"
[ -z "$(run s3 | tr -d '[:space:]')" ] && ok || bad "долг записан" "ругается, хотя долг менялся: $(run s3)"

# 4. Находка была И знание записано — тишина.
printf 'turn:1|discovery:456|\n' > "$S/five-whys-s4.seen"; touch "$S/probe-s4"
sleep 1; printf 'знание\n' > "$K/case-новое.md"
[ -z "$(run s4 | tr -d '[:space:]')" ] && ok || bad "знание записано" "ругается, хотя знание записано: $(run s4)"

echo ""
echo "declared problem recorded tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
