#!/usr/bin/env bash
# test_adv4_cg_maxruns_false_green.sh
# АТАКА (прожарка 31.08, класс «не понял → зелёный»): completion-gate прогоняет проверки
# лишь у первых CG_MAX=3 ☑-пунктов; красное D204 четвёртым не называлось, вывод был пуст
# И писался зелёный OKF — файл кэшировался «прошедшим» навсегда.
#
# КОНТРАКТ ПОСЛЕ ПОЧИНКИ (лимит — осознанный предел, закреплён зелёным тестом):
#   · за лимитом красное хуком НЕ называется — неотвратимость держит архиватор (без лимита);
#   · но частичное покрытие даёт статус «partial», и зелёный кэш НЕ пишется:
#     файл перечитывается каждым Stop, «всё чисто навсегда» невозможно;
#   · в пределах лимита (CG_MAX=4) красное D204 называется.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/completion-gate.sh"
TMP=$(mktemp -d)
mkdir -p "$TMP/state"
BL="$TMP/BACKLOG.md"

cat > "$BL" <<'EOF'
# BACKLOG

### D201 ☑ зелёное a
**Проверка.** `true` → 0

### D202 ☑ зелёное b
**Проверка.** `true` → 0

### D203 ☑ зелёное c
**Проверка.** `true` → 0

### D204 ☑ КРАСНОЕ за порогом CG_MAX
**Проверка.** `false` → 0
EOF

RC=0

# --- 1. Частичное покрытие: кэш НЕ пишется (прежний дефект — писался) ---
OUT=$(printf '{"session_id":"adv4","cwd":"/"}' \
      | env CG_BACKLOG="$BL" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
if ls "$TMP/state"/completion-gate-*.ok >/dev/null 2>&1; then
    echo "RED: OKF записан при частичном покрытии — красное D204 закэшировано зелёным навсегда"
    RC=1
else
    echo "PASS: частичное покрытие кэша не получает — файл перечитается следующим Stop"
fi
# Служебная строка статуса не должна утекать собеседнику
if grep -q 'CG_STATUS' <<< "$OUT"; then
    echo "RED: служебный статус утёк в systemMessage: [$OUT]"
    RC=1
else
    echo "PASS: статус-канал внутренний"
fi

# --- 2. В пределах лимита красное называется ---
OUT=$(printf '{"session_id":"adv4b","cwd":"/"}' \
      | env CG_BACKLOG="$BL" STATE_DIR="$TMP/state" CG_MAX=4 bash "$HOOK" 2>/dev/null)
if grep -q 'D204' <<< "$OUT"; then
    echo "PASS: в пределах лимита красное ☑ D204 названо"
else
    echo "RED: CG_MAX=4, а красное D204 не названо: [$OUT]"
    RC=1
fi

echo "temp: $TMP (уберёт система)"
exit "$RC"
