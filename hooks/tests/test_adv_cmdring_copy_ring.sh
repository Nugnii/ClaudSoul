#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh scripts/backlog-archive.sh
# test_adv_cmdring_copy_ring.sh — ограда кольца (D503) останавливает кольцо, идущее через свежую копию бэклога на каждом уровне («копия дерева» — обычная рамка свидетелей).
#
# Атака (противник ограды кольца, 1 октября 2026). Ключ ограды — физический путь бэклога. Свидетель,
# который собирает рамку копией (бэклог или дерево в `mktemp -d`) и зовёт исполнителя на копии,
# даёт каждому уровню НОВЫЙ путь, значит новый ключ: «Проверка» того же пункта с тем же текстом
# исполняется на каждом уровне внутри своего же исполнения, и дна у кольца нет — его держит лишь
# предохранитель теста. Маркер BACKLOG_CHECKS_NESTED свидетель снимает (D334, D461), ключ ограды
# проходит мимо. Предел объявленного ключа («другой бэклог законен»), а кольцо — то самое.
#
# Наблюдатель — сама «Проверка»: сколько записей с её «#D9001#check» (под любым путём) уже
# лежит в BACKLOG_CMD_RUNNING. Предохранитель «четыре входа» держит кольцо конечным.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
export CLAUDSOUL_LOCK_TRIES=5
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"
A="$T/a"; mkdir -p "$A/c0"
cat > "$A/again.sh" <<EOF
k=\$(printf '%s' "\${BACKLOG_CMD_RUNNING:-}" | tr '\037' '\n' | grep -c '#D9001#check\$')
echo "\$k" >> "$A/depth"
echo x >> "$A/cnt"
[ "\$(wc -l < "$A/cnt")" -ge 4 ] && exit 0
d=\$(mktemp -d "$A/cXXXXXX")
cp "$A/c0/BACKLOG.md" "\$d/BACKLOG.md"
env -u BACKLOG_CHECKS_NESTED BACKLOG_FILE="\$d/BACKLOG.md" BACKLOG_ARCHIVE="\$d/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" check >/dev/null 2>&1
exit 0
EOF
printf -- '- ☑ **D9001** проба кольца через копию\n  **Результат.** проба\n  **Проверка.** `bash %s/again.sh` → 0\n' "$A" > "$A/c0/BACKLOG.md"
BACKLOG_FILE="$A/c0/BACKLOG.md" BACKLOG_ARCHIVE="$A/c0/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" check >/dev/null 2>&1 || true  # архиватор `check` отвечает не-нулём на кольцо — предмет ноги: глубину читает строка ниже (D1261)

DEPTHS=$(tr '\n' ' ' < "$A/depth" 2>/dev/null || true)
grep -qx '1' "$A/depth" 2>/dev/null && ok || bad T0 "рамка: «Проверка» не исполнилась с одним ключом (глубины: ${DEPTHS})"
MAX=$(sort -n "$A/depth" 2>/dev/null | tail -1)
[ "${MAX:-0}" -le 1 ] && ok \
    || bad T1 "«Проверка» D9001 исполнилась внутри своего же исполнения через копии бэклога: её ключ (под разными путями) лежал в BACKLOG_CMD_RUNNING до ${MAX} раз (глубины: ${DEPTHS}); остановил предохранитель теста, не ограда"

echo "adv cmdring copy ring: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
