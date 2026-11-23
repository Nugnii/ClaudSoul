#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh scripts/backlog-archive.sh
# test_adv_cmdring_path_alias.sh — ключ ограды кольца (D503) один у бэклога под любым его именем: символическая ссылка на файл и другой регистр букв (macOS) не открывают исполнение «Проверки» внутри её же исполнения.
#
# Атака (противник ограды кольца, 1 октября 2026). `backlog_cmd_filekey` приводит физически только
# КАТАЛОГ (`cd … && pwd -P`), имя файла берёт как есть, а `pwd -P` оболочки bash регистр не
# приводит (замер того же дня: `cd "/Users/user/my project/claudsoul" && pwd -P` отдаёт
# строчные, `git rev-parse --show-toplevel` — канонические). Один бэклог под двумя именами —
# два ключа: архиватор на одном имени исполняет «Проверку», та зовёт архиватор на втором имени,
# и он исполняет её снова — внутри её же исполнения. Обещание ограды (1) нарушено на каждом
# лишнем имени по уровню.
#
# Наблюдатель — сама «Проверка»: сколько записей с её «#ID#check» уже лежит в
# BACKLOG_CMD_RUNNING (под любым путём). Один — законный запуск; два и больше — вложенный.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
export CLAUDSOUL_LOCK_TRIES=5
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"

# leg <имя> <каталог> <путь второго имени>: архиватор на BACKLOG.md, «Проверка» зовёт его на втором имени
leg() {
    local name="$1" d="$2" alias="$3" depths max
    cat > "$d/again.sh" <<EOF
k=\$(printf '%s' "\${BACKLOG_CMD_RUNNING:-}" | tr '\037' '\n' | grep -c '#D9001#check\$')
echo "\$k" >> "$d/depth"
echo x >> "$d/cnt"
[ "\$(wc -l < "$d/cnt")" -ge 4 ] && exit 0
env -u BACKLOG_CHECKS_NESTED BACKLOG_FILE="$alias" BACKLOG_ARCHIVE="$d/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" check >/dev/null 2>&1
exit 0
EOF
    printf -- '- ☑ **D9001** проба второго имени\n  **Результат.** проба\n  **Проверка.** `bash %s/again.sh` → 0\n' "$d" > "$d/BACKLOG.md"
    BACKLOG_FILE="$d/BACKLOG.md" BACKLOG_ARCHIVE="$d/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" check >/dev/null 2>&1 || true  # архиватор `check` отвечает не-нулём на кольцо — предмет ноги: глубину читает строка ниже (D1261)
    depths=$(tr '\n' ' ' < "$d/depth" 2>/dev/null || true)
    grep -qx '1' "$d/depth" 2>/dev/null && ok || bad "${name}-0" "рамка: «Проверка» не исполнилась с одним ключом (глубины: ${depths})"
    max=$(sort -n "$d/depth" 2>/dev/null | tail -1)
    [ "${max:-0}" -le 1 ] && ok \
        || bad "$name" "«Проверка» D9001 исполнилась внутри своего же исполнения через второе имя бэклога ${alias} (записей её ключа в BACKLOG_CMD_RUNNING до ${max}; глубины: ${depths})"
}

# L1 — символическая ссылка на файл (переносимо).
L1="$T/l1"; mkdir -p "$L1"
ln -s "$L1/BACKLOG.md" "$L1/BL-alias.md"
leg L1 "$L1" "$L1/BL-alias.md"

# L2 — тот же каталог другим регистром букв (только на нечувствительной к регистру ФС).
L2="$T/Ring2"; mkdir -p "$L2"
if [ -d "$T/ring2" ]; then
    leg L2 "$L2" "$T/ring2/BACKLOG.md"
else
    echo "SKIP [L2]: ФС чувствительна к регистру — второго имени у каталога нет"
fi

echo "adv cmdring path alias: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
