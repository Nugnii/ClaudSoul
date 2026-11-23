#!/usr/bin/env bash
# СУДИТ: hooks/carrier-growth-check.sh
# probe_D1027.sh — у носителя, чей список в строке прибора СОКРАТИЛСЯ, страж прироста носителей не называет прироста (D1027).
#
# Коды: 0 — после строки «судит: a.sh, b.sh» строка того же файла «судит: b.sh» прироста не даёт, а контроль — тот же
#       файл с добавленным предметом «судит: b.sh, c.sh» — прирост даёт; 1 — сокращение названо приростом (дефект
#       D1027: ключ снимка — путь и весь хвост строки, и строка с меньшим списком не находится в снимке);
#       2 — судить нечем: нет стража или jq, либо контроль не назван (страж молчит на всём).
# Повод — 22 октября 2026: починка ложного носителя рода M (из ноги `green_D1026` убрано буквальное имя диспетчера)
# дала на границе хода «прирост носителей» у `test_backlog_green_side.sh`.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/carrier-growth-check.sh"
[ -f "$HOOK" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$T/ans" > "$T/probe.sh"; chmod +x "$T/probe.sh"
say() { printf 'РОД M · носителей: 1\n  · hooks/tests/test_x.sh  судит: %s — песочница голым mktemp -d\n' "$1" > "$T/ans"
        printf '{"session_id":"probe-d1027","cwd":"%s"}' "$T" \
          | STATE_DIR="$T/state" CLAUDSOUL_ROOT="$T" CARRIER_CMD="$T/probe.sh" bash "$HOOK" 2>/dev/null; }
say "a.sh, b.sh" >/dev/null
SHRINK=$(say "b.sh")
CTL=$(say "b.sh, c.sh")
case "$CTL" in *test_x.sh*) ;; *) exit 2 ;; esac
case "$SHRINK" in *test_x.sh*) exit 1 ;; esac
exit 0
