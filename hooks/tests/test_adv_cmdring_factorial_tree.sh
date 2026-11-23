#!/usr/bin/env bash
# СУДИТ: scripts/backlog-archive.sh hooks/backlog-lib.sh
# test_adv_cmdring_factorial_tree.sh — ограда кольца (D503) держит дерево процессов конечным не только по глубине, но и по объёму: K пунктов, зовущих исполнителя на своём бэклоге, не дают K! исполнений.
#
# Атака (противник ограды кольца, 1 октября 2026). Ключ ограды — пункт, а не исполнитель на
# бэклоге: вложенный исполнитель законно исполняет ВСЕ пункты, кроме уже исполняемых выше по
# своей ветке (обещание (2) ограды). Когда «Проверки» K закрытых пунктов зовут архиватор на том
# же бэклоге (устройство D502, где K был 1), каждая ветка перебирает остаток: число исполнений
# «Проверок» за ОДИН прогон архиватора — сумма размещений, ≈ e·K!. K=4 → 64, K=5 → 325,
# K=6 → 1956, K=8 → 109 600. Кольца нет ни в одной ветке, а дерево — та же бездна, от которой
# ограда заведена (D502: 298 процессов, сироты после срока архиватора).
#
# Ожидание здесь мягкое и названо числом: исполнений не больше K² (многочлен от числа пунктов).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
# Вложенный архиватор ждёт замок держателя: пять проб вместо ста.
export CLAUDSOUL_LOCK_TRIES=5
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
T=$(mktemp -d)   # временное уберёт система
A="$T/a"; mkdir -p "$A/state"
# Журнал отказов архиватора — в песочницу, не в каталог состояния владельца.
export STATE_DIR="$A/state"
K=4
# Предохранитель 200 держит дерево конечным и на дереве хуже ожидаемого.
cat > "$A/again.sh" <<EOF
echo "\$1" >> "$A/cnt"
[ "\$(wc -l < "$A/cnt")" -ge 200 ] && exit 0
env -u BACKLOG_CHECKS_NESTED BACKLOG_FILE="$A/BACKLOG.md" BACKLOG_ARCHIVE="$A/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" check >/dev/null 2>&1
exit 0
EOF
: > "$A/BACKLOG.md"
i=1
while [ "$i" -le "$K" ]; do
    printf -- '- ☑ **D920%s** проба дерева\n  **Результат.** проба\n  **Проверка.** `bash %s/again.sh D920%s` → 0\n\n' "$i" "$A" "$i" >> "$A/BACKLOG.md"
    i=$((i + 1))
done
BACKLOG_FILE="$A/BACKLOG.md" BACKLOG_ARCHIVE="$A/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" check >/dev/null 2>&1 || true  # архиватор `check` отвечает не-нулём на кольцо — предмет ноги: глубину читает строка ниже (D1261)

N=0; [ -f "$A/cnt" ] && N=$(wc -l < "$A/cnt" | tr -d ' ')
PER=$(sort "$A/cnt" 2>/dev/null | uniq -c | awk '{ printf "%s×%s ", $2, $1 }')
# Положительный контроль рамки: каждая «Проверка» исполнилась хотя бы раз.
DISTINCT=$(sort -u "$A/cnt" 2>/dev/null | wc -l | tr -d ' ')
[ "$DISTINCT" = "$K" ] && ok || bad T0 "рамка: исполнились «Проверки» $DISTINCT пунктов из $K"
[ "$N" -le $((K * K)) ] && ok \
    || bad T1 "один прогон архиватора исполнил «Проверки» $N раз при K=$K пунктах (потолок K²=$((K * K))); по пунктам: ${PER}— рост ≈ e·K!, кольца нет, бездна есть"

echo "adv cmdring factorial tree: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
