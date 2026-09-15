#!/usr/bin/env bash
# test_timeout_lib.sh — свидетель библиотеки срока (D369).
# Результат: команда в срок отдаёт свой код; команда дольше срока снимается деревом и отвечает 124,
#            не оставляя сирот; kill_tree убирает внуков; быстрая команда не платит секунду ожидания.
# Проверка результата: bash hooks/tests/test_timeout_lib.sh даёт 0
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/hooks/timeout-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
. "$LIB"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система (D360)
# T1: свой код возврата проходит как есть
run_with_timeout 5 true; [ $? -eq 0 ] && ok || bad "T1" "true дал не 0"
run_with_timeout 5 bash -c 'exit 3'; [ $? -eq 3 ] && ok || bad "T1b" "код команды не прошёл наружу"
# T2: дольше срока — 124, быстро, без сирот
MARK="sleep 30.$$"
T0=$(date +%s)
run_with_timeout 1 bash -c "$MARK; echo x"; RC=$?
T1=$(( $(date +%s) - T0 ))
[ "$RC" -eq 124 ] && ok || bad "T2" "срыв срока дал $RC, ожидался 124"
[ "$T1" -le 3 ] && ok || bad "T2b" "срок 1 с, а ждали $T1 с"
sleep 0.3; if pgrep -f "$MARK" >/dev/null 2>&1; then bad "T2c" "после снятия остался сирота: $(pgrep -fl "$MARK" | head -1)"; pkill -9 -f "$MARK"; else ok; fi
# T3: kill_tree убирает внуков — трёхуровневая фикстура пишет pid внука в файл
cat > "$TMP/victim.sh" <<EOF
#!/usr/bin/env bash
bash -c 'sleep 40.$$ & echo \$! > "$TMP/grandchild"; wait' &
wait
EOF
bash "$TMP/victim.sh" >/dev/null 2>&1 & VP=$!
for _ in $(seq 1 40); do [ -s "$TMP/grandchild" ] && break; sleep 0.1; done
GC=$(cat "$TMP/grandchild" 2>/dev/null)
kill_tree "$VP"; sleep 0.5
if [ -n "$GC" ] && kill -0 "$GC" 2>/dev/null; then kill -9 "$GC" 2>/dev/null; bad "T3" "внук (pid $GC) пережил kill_tree"; else ok; fi
# T4: быстрая команда не ждёт секунду — десять вызовов укладываются в 3 с
T0=$(date +%s); for _ in 1 2 3 4 5 6 7 8 9 10; do run_with_timeout 5 true; done; T1=$(( $(date +%s) - T0 ))
[ "$T1" -le 3 ] && ok || bad "T4" "десять быстрых команд шли $T1 с — опрос не десятыми долями"
# T5: нечисловой срок — умолчание 30, а не падение
run_with_timeout abc true; [ $? -eq 0 ] && ok || bad "T5" "нечисловой срок уронил вызов"
echo "timeout lib: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
