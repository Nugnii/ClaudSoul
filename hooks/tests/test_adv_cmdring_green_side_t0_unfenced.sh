#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_backlog_green_side.sh hooks/backlog-lib.sh
# test_adv_cmdring_green_side_t0_unfenced.sh — отрицательный контроль T0 свидетеля зелёной стороны не исполняет «Проверку» D307 внутри её же исполнения (ограда кольца D503).
#
# Атака (противник ограды кольца, 1 октября 2026). Свидетель сверяет ключ кольца только в
# цикле по пунктам; нога T0 до цикла исполняет «Проверку» D307 через `run_check … D307` без
# сверки — ключ дописывается, но не проверяется. Если «Проверка» D307 (прямо или через тест)
# зовёт свидетеля, каждый уровень снова исполняет её из T0: кольцо «свидетель → T0 → «Проверка»
# D307 → свидетель» ограда не останавливает, ключ D307 копится в BACKLOG_CMD_RUNNING по разу на
# уровень.
#
# Наблюдатель — сама «Проверка»: она считает, сколько раз её ключ уже лежит в
# BACKLOG_CMD_RUNNING. Один — законный запуск (ключ кладёт запустивший); два и больше — она
# исполняется внутри своего же исполнения. Предохранитель «четыре входа» держит кольцо конечным.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
T=$(mktemp -d)   # временное уберёт система
S="$T/gs"; mkdir -p "$S/hooks/tests"
cp "$REPO/hooks/backlog-lib.sh" "$S/hooks/"
cp "$REPO/hooks/tests/test_backlog_green_side.sh" "$S/hooks/tests/"
cat > "$S/again.sh" <<EOF
k=\$(printf '%s' "\${BACKLOG_CMD_RUNNING:-}" | tr '\037' '\n' | grep -c '#D307#check\$')
echo "\$k" >> "$S/depth"
echo x >> "$S/cnt"
[ "\$(wc -l < "$S/cnt")" -ge 4 ] && exit 1
bash "$S/hooks/tests/test_backlog_green_side.sh" > /dev/null 2>&1
exit 1
EOF
printf -- '- ☐ **D307** проба кольца через отрицательный контроль\n  **Проверка.** `bash %s/again.sh` → 0\n' "$S" > "$S/BACKLOG.md"
bash "$S/hooks/tests/test_backlog_green_side.sh" > "$S/outer.out" 2>&1

DEPTHS=$(tr '\n' ' ' < "$S/depth" 2>/dev/null || true)
grep -qx '1' "$S/depth" 2>/dev/null && ok \
    || bad T0 "рамка: «Проверка» D307 ни разу не исполнилась с одним ключом — свидетель не дошёл до неё (глубины: ${DEPTHS})"
MAX=$(sort -n "$S/depth" 2>/dev/null | tail -1)
[ "${MAX:-0}" -le 1 ] && ok \
    || bad T1 "«Проверка» D307 исполнилась внутри своего же исполнения: её ключ лежал в BACKLOG_CMD_RUNNING до ${MAX} раз (глубины по запускам: ${DEPTHS}) — нога T0 свидетеля ограду не сверяет"

echo "adv cmdring green side t0 unfenced: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
