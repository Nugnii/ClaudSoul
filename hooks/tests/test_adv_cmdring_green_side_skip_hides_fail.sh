#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_backlog_green_side.sh hooks/backlog-lib.sh hooks/completion-gate.sh
# test_adv_cmdring_green_side_skip_hides_fail.sh — ограда кольца (D503) в свидетеле зелёной стороны отменяет только ИСПОЛНЕНИЕ «Проверки», а не суждения без исполнения («нет фикстуры»).
#
# Атака (противник ограды кольца, 1 октября 2026). Свидетель сверяет ключ кольца ПЕРВЫМ делом в
# цикле — раньше, чем `declare -F green_<ID>` и проверка наличия строки «Проверка». Оба суждения
# ничего не исполняют и кольца замкнуть не могут, но под ключом пункта они не выносятся: пункт без
# зелёной стороны получает «SKIP», свидетель выходит 0. До ограды тот же вход давал
# «FAIL [ID]: нет зелёной стороны» и код 1 — кольца там не было, «Проверка» без фикстуры не
# исполняется. Наружу это доходит ложным вердиктом исполнителя уровнем выше: completion-gate
# читает «Проверку» ОТКРЫТОГО пункта зелёной и требует закрывать пункт.
#
# Рамка: копия свидетеля и библиотеки в своём дереве (как нога R6 test_backlog_cmd_ring.sh);
# открытый D9301 без green_D9301, его «Проверка» зовёт свидетеля (так звала «Проверка» D499).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
T=$(mktemp -d)   # временное уберёт система
S="$T/gs"; mkdir -p "$S/hooks/tests" "$S/state"
cp "$REPO/hooks/backlog-lib.sh" "$S/hooks/"
cp "$REPO/hooks/tests/test_backlog_green_side.sh" "$S/hooks/tests/"
# Предохранитель: даже если свидетель исполнит «Проверку» снова, кольцо конечно (четыре входа).
cat > "$S/w.sh" <<EOF
echo x >> "$S/cnt"
[ "\$(wc -l < "$S/cnt")" -ge 4 ] && exit 1
bash "$S/hooks/tests/test_backlog_green_side.sh" > "$S/inner.out" 2>&1
rc=\$?
echo "\$rc" > "$S/inner.rc"
exit "\$rc"
EOF
printf -- '- ☐ **D9301** «Проверка» зовёт свидетеля зелёной стороны\n  **Проверка.** `bash %s/w.sh` → 0\n' "$S" > "$S/BACKLOG.md"

# Контроль различения: прямой прогон свидетеля (ключа нет) судит пункт без фикстуры красным.
D_OUT=$(bash "$S/hooks/tests/test_backlog_green_side.sh" 2>&1); D_RC=$?
{ [ "$D_RC" != 0 ] && grep -q 'FAIL \[D9301\]' <<< "$D_OUT"; } && ok \
    || bad TC "контроль: прямой прогон свидетеля не назвал D9301 без зелёной стороны (rc $D_RC): «${D_OUT}»"

# Исполнитель уровнем выше — completion-gate: открытый пункт, его «Проверка» зовёт свидетеля.
printf '{"session_id":"adv-gs-skip","cwd":"/"}' | CG_BACKLOG="$S/BACKLOG.md" STATE_DIR="$S/state" \
    bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_cmdring_green_side_skip_hides_fail.sh:$LINENO" >&2; exit 1; }
N=0; [ -f "$S/cnt" ] && N=$(wc -l < "$S/cnt" | tr -d ' ')
[ "$N" = 1 ] && ok || bad T0 "рамка: «Проверка» D9301 исполнилась $N раз (ожидалось 1)"
IN=$(cat "$S/inner.out" 2>/dev/null || true)
IRC=$(cat "$S/inner.rc" 2>/dev/null || echo нет)
grep -q 'FAIL \[D9301\]' <<< "$IN" && ok \
    || bad T1 "вложенный свидетель не вынес «нет зелёной стороны» D9301 — суждение без исполнения отменено оградой кольца: «${IN}»"
[ "$IRC" != 0 ] && ok \
    || bad T2 "вложенный свидетель вышел 0 (rc ${IRC}) при пункте без зелёной стороны — пропуск прочитан как «проверено, чисто»"
. "$REPO/hooks/tests/alerts-read.sh"; AL=$(alerts_of "$S/state")   # все три канала (D1304, D1309): о главном бэклоге гейт говорит в канал проекта
if grep -q 'D9301' <<< "$AL" && grep -q 'не красная' <<< "$AL"; then
    bad T3 "completion-gate объявил «Проверку» ОТКРЫТОГО D9301 не красной (зовёт закрывать пункт), хотя у пункта нет зелёной стороны: «${AL}»"
else
    ok
fi

# Нога W — исполнитель уровнем выше — страж записи открытого пункта (отказ уровня 4). На диске
# открытый D9302 с красной «Проверкой»; запись меняет её на вызов свидетеля. Свидетель читает
# бэклог с диска, видит D9302 под ключом — «SKIP», код 0 — и страж ОТКАЗЫВАЕТ в записи, называя
# «Проверку» зелёной. Без ограды свидетель вынес бы «нет зелёной стороны» и код 1.
W="$T/w"; mkdir -p "$W/hooks/tests" "$W/state"
cp "$REPO/hooks/backlog-lib.sh" "$W/hooks/"
cp "$REPO/hooks/tests/test_backlog_green_side.sh" "$W/hooks/tests/"
cat > "$W/w.sh" <<EOF
echo x >> "$W/cnt"
[ "\$(wc -l < "$W/cnt")" -ge 4 ] && exit 1
bash "$W/hooks/tests/test_backlog_green_side.sh" > "$W/inner.out" 2>&1
EOF
printf -- '- ☐ **D9302** пункт\n  **Проверка.** `false` → 0\n' > "$W/BACKLOG.md"
jq -cn --arg f "$W/BACKLOG.md" --arg c "$(printf -- '- ☐ **D9302** пункт\n  **Проверка.** `bash %s/w.sh` → 0\n' "$W")" \
    '{tool_name:"Write", session_id:"adv-gs-skip", tool_input:{file_path:$f, content:$c}}' > "$W/payload.json"
GOUT=$(STATE_DIR="$W/state" bash "$REPO/hooks/backlog-open-write-guard.sh" < "$W/payload.json" 2>/dev/null)
WIN=$(cat "$W/inner.out" 2>/dev/null || true)
grep -q 'D9302' <<< "$WIN" && ok || bad W0 "рамка: свидетель под стражем записи не дошёл до D9302: «${WIN}»"
if grep -q '"deny"' <<< "$GOUT"; then
    bad W1 "страж записи отказал в законной записи: «Проверка» D9302 прочитана зелёной, потому что свидетель пропустил пункт без зелёной стороны по ключу кольца; отказ: «${GOUT}»"
else
    ok
fi

echo "adv cmdring green side skip hides fail: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
