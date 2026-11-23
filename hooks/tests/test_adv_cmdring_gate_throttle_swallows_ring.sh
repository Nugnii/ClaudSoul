#!/usr/bin/env bash
# СУДИТ: hooks/completion-gate.sh hooks/backlog-lib.sh
# test_adv_cmdring_gate_throttle_swallows_ring.sh — канал «кольцо» completion-gate входит в состав дросселя: новый пропуск по ограде (D503) не гаснет за уже названным красным ☑.
#
# Атака (противник ограды кольца, 1 октября 2026). Ключ дросселя гейта — «состав расхождения»:
# closed-red / open-not-red / closed-form / unchecked / skipped / broken. Канал RINGED в состав
# не входит. Значит сообщение «красный D9100 + пропуск D9101 по кольцу» получает тот же ключ,
# что одно «красный D9100», и при уже названном красном гаснет целиком — пропуск по ограде
# молчит. Тот же дефект, что поймала нога T6a для канала «не проверено» (комментарий у
# `_cg_compose`): без пункта в составе состав схлопывается.
#
# Рамка: ход 1 — красный ☑ D9100, кольца нет; ход 2 — тот же бэклог, команда D9101 уже
# исполняется выше по дереву (ключ ограды в BACKLOG_CMD_RUNNING, как его кладёт исполнитель).
set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
T=$(mktemp -d)   # временное уберёт система
G="$T/g"; mkdir -p "$G/s"
printf -- '- ☑ **D9100** красный пункт\n  **Результат.** проба\n  **Проверка.** `false` → 0\n\n- ☑ **D9101** пункт под кольцом\n  **Результат.** проба\n  **Проверка.** `true` → 0\n' > "$G/BACKLOG.md"
# shellcheck source=../backlog-lib.sh
. "$REPO/hooks/backlog-lib.sh"
command -v backlog_cmd_key >/dev/null 2>&1 || { echo "FAIL [T-lib]: в библиотеке нет backlog_cmd_key"; exit 1; }
# Ключ строит владелец правила (`backlog_cmd_key`): «Проверка» D9101 — команда `true`.
RUNKEY="${BACKLOG_CMD_SEP}$(backlog_cmd_key check D9101 true)"
gate() { printf '{"session_id":"adv-cg-ring","cwd":"/"}' | env "$@" CG_BACKLOG="$G/BACKLOG.md" STATE_DIR="$G/s" bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1; }

# Контроль различения: тот же ход 2 на ЧИСТОМ состоянии называет кольцо — значит гейт пропуск
# видит, и молчание ниже даёт дроссель, а не слепая ограда.
mkdir -p "$T/c"
printf '{"session_id":"adv-cg-ring","cwd":"/"}' | env BACKLOG_CMD_RUNNING="$RUNKEY" CG_BACKLOG="$G/BACKLOG.md" STATE_DIR="$T/c" bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1
AC=$(alerts_of "$T/c" || true)
grep -q 'кольцо' <<< "$AC" && grep -q 'D9101' <<< "$AC" && ok \
    || bad TC "контроль: на чистом состоянии гейт не назвал пропуск D9101 по кольцу — рамка не различает: «${AC}»"

# Ход 1: кольца нет — красный D9100 назван (положительный контроль рамки).
gate BACKLOG_CMD_RUNNING=
A1=$(alerts_of "$G/s" || true)
grep -q 'D9100' <<< "$A1" && ok || bad T0 "ход 1: красный ☑ D9100 не назван — рамка гейта не собралась: «${A1}»"
L1=$(printf '%s' "$A1" | wc -l | tr -d ' ')

# Ход 2: команда D9101 уже исполняется выше по дереву — гейт обязан назвать пропуск.
gate BACKLOG_CMD_RUNNING="$RUNKEY"
A2=$(alerts_of "$G/s" || true)
NEW=$(printf '%s\n' "$A2" | tail -n +"$((L1 + 2))")
grep -q 'кольцо' <<< "$A2" && ok \
    || bad T1 "ход 2: пропуск «Проверки» D9101 по ограде кольца не доставлен — дроссель счёл состав прежним (красный D9100) и погасил сообщение; новые строки очереди: «${NEW}»"

echo "adv cmdring gate throttle swallows ring: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
