#!/usr/bin/env bash
# СУДИТ: hooks/completion-gate.sh hooks/backlog-lib.sh
# test_adv2_cmdring_gate_ring_nond_throttle.sh — пропуск «Проверки» по ограде кольца (D503) у пункта вне D-нумерации не гаснет в дросселе completion-gate за пропуском ДРУГОГО такого пункта.
#
# Атака (противник ограды кольца, раунд 2, 1 октября 2026; вход закрытого класса 3 — «пропуск гас в
# дросселе»). Починка прошлого раунда внесла канал в состав дросселя строкой
# `printf 'ring:%s;' "$(_cg_ids "$RINGED")"`, а `_cg_ids` берёт из текста только `\bD[0-9]+\b`.
# Идентификаторы вне D-нумерации шапка backlog-lib.sh объявляет законными («X1», «TASK-003a»,
# «R1.1»), гейт исполняет их «Проверки» без порога, а у бэклога проекта владельца нумерация `B1`..`B30`
# (шапка гейта, блок «Залежавшийся ☐»). У таких пунктов состав канала всегда «ring:;»: пропуск B2
# получает тот же ключ, что уже названный пропуск B1, и гаснет — в очередь не попадает ничего.
#
# Рамка: ход 1 — «Проверка» ☑ B1 уже исполняется выше по дереву (ключ в BACKLOG_CMD_RUNNING, как его
# кладёт исполнитель); ход 2 той же сессии — то же для ☑ B2, а B1 исполняется и зелёный.
set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"
G="$T/g"; mkdir -p "$G/s" "$T/c"
printf -- '- ☑ **B1** первый пункт вне D-нумерации\n  **Результат.** проба\n  **Проверка.** `true` → 0\n\n- ☑ **B2** второй пункт вне D-нумерации\n  **Результат.** проба\n  **Проверка.** `true` → 0\n' > "$G/BACKLOG.md"
# shellcheck source=../backlog-lib.sh
. "$REPO/hooks/backlog-lib.sh"
command -v backlog_cmd_key >/dev/null 2>&1 || { echo "FAIL [T-lib]: в библиотеке нет backlog_cmd_key"; exit 1; }
K1="${BACKLOG_CMD_SEP}$(backlog_cmd_key check B1 true)"
K2="${BACKLOG_CMD_SEP}$(backlog_cmd_key check B2 true)"
gate() {  # <BACKLOG_CMD_RUNNING> <STATE_DIR>
    printf '{"session_id":"adv2-cg-nond","cwd":"/"}' | env BACKLOG_CMD_RUNNING="$1" CG_BACKLOG="$G/BACKLOG.md" STATE_DIR="$2" \
        bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_cmdring_gate_ring_nond_throttle.sh:$LINENO" >&2; exit 1; }
}

# Контроль различения: ход 2 на ЧИСТОМ состоянии называет пропуск B2 — гейт его видит.
gate "$K2" "$T/c"
AC=$(alerts_of "$T/c" || true)
{ grep -q 'кольцо' <<< "$AC" && grep -q 'B2' <<< "$AC"; } && ok \
    || bad TC "контроль: на чистом состоянии гейт не назвал пропуск B2: «${AC}»"

# Ход 1: пропуск B1 назван (положительный контроль рамки).
gate "$K1" "$G/s"
A1=$(alerts_of "$G/s" || true)
{ grep -q 'кольцо' <<< "$A1" && grep -q 'B1' <<< "$A1"; } && ok || bad T0 "ход 1: пропуск B1 не назван — рамка не собралась: «${A1}»"
L1=$(printf '%s\n' "$A1" | grep -c . || true)

# Ход 2: пропуск B2 — новое состояние мира, обязан прозвучать.
gate "$K2" "$G/s"
A2=$(alerts_of "$G/s" || true)
NEW=$(printf '%s\n' "$A2" | grep . | tail -n +"$((L1 + 1))")
grep -q 'B2' <<< "$NEW" && ok \
    || bad T1 "ход 2: пропуск «Проверки» B2 по ограде кольца не доставлен — состав дросселя «ring:;» у пунктов вне D-нумерации один на всех, и он совпал с уже названным B1; новые строки очереди: «${NEW}»"

echo "adv2 cmdring gate ring non-D throttle: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
