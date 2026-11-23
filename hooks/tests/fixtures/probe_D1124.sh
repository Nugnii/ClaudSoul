#!/usr/bin/env bash
# СУДИТ: hooks/completion-gate.sh hooks/backlog-lib.sh
# probe_D1124 — completion-gate на нечитаемом бэклоге говорит «не читается», а не молчит, будто проверять нечего. Красная
# (1), пока нечитаемый бэклог даёт тишину (брат D1121: «не прочитан» и «пуст» — одно значение у потребителя
# `backlog_read`). Положительный контроль — тот же бэклог читаемым: закрытый пункт с красной «Проверкой» назван. Рамка — 2.
. "$(dirname "$0")/../alerts-read.sh"
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/completion-gate.sh"; [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 || exit 2
[ "$(id -u)" -ne 0 ] || exit 2
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1124.XXXXXX") || exit 2
mkdir -p "$T/state"; BL="$T/BACKLOG.md"
printf '%s\n' '# BACKLOG' '' '- ☑ **D2000** закрытый' '  **Корень.** R6 — два состояния.' '  **Проверка.** `false` → 0' \
    '  **Показание.** «Проверка» 0.' > "$BL"
run() { alerts_clear "$T/state"; rm -f "$T/state"/completion-gate-* 2>/dev/null
    printf '{"session_id":"p1124","cwd":"%s"}' "$T" | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$BL" CG_LOCAL_BACKLOG="" \
        STATE_DIR="$T/state" bash "$HOOK" >/dev/null 2>&1
    alerts_of "$T/state"; }
grep -q 'D2000' <<< "$(run)" || exit 2
chmod 000 "$BL"; cat "$BL" >/dev/null 2>&1 && { chmod 644 "$BL"; exit 2; }
out=$(run); chmod 644 "$BL"
grep -q 'не читается\|не прочитан' <<< "$out" || { echo "нечитаемый бэклог — тишина, как будто проверять нечего" >&2; exit 1; }
echo "нечитаемый бэклог назван"
exit 0
