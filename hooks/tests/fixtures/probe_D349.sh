#!/usr/bin/env bash
# СУДИТ: scripts/stop-context-restart.sh
# D349: `--check` сверяет ЗАПИСЬ замера с версией харнесса: та же версия и верный вердикт — 0; чужая версия,
# старая запись, иной вердикт — не 0. Рамка: подставной `claude` в PATH и песочная запись; живая запись и
# живой CLI не читаются (живую версию меряет замер реестра stop-context-restart, период 0).
# 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
S="$R/scripts/stop-context-restart.sh"
[ -f "$S" ] || { echo "рамка: нет $S" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "рамка: нужен jq" >&2; exit 2; }
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/bin" "$d/state" || exit 2
printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' > "$d/bin/claude"; chmod +x "$d/bin/claude"
rec() {  # rec <версия> <вердикт> <возраст-в-днях>
  jq -n --arg v "$1" --arg d "$2" --argjson e "$(( $(date +%s) - $3 * 86400 ))" \
    '{cli_version:$v, verdict:$d, epoch:$e, date:"2026-01-01"}' > "$d/state/rec.json"; }
chk() { PATH="$d/bin:$PATH" STOP_PROBE_RECORD="$d/state/rec.json" STATE_DIR="$d/state" CLAUDSOUL_REPO="$R" bash "$S" --check >/dev/null 2>&1; }
V=additionalContext_restarts_systemMessage_does_not
rec 9.9.9 "$V" 1;        chk; [ $? -eq 0 ] || { echo "запись о нынешней версии с верным вердиктом не принята"; exit 1; }
rec 1.0.0 "$V" 1;        chk; [ $? -eq 1 ] || { echo "запись о ЧУЖОЙ версии принята как свежая"; exit 1; }
rec 9.9.9 "$V" 400;      chk; [ $? -eq 1 ] || { echo "запись старше порога принята"; exit 1; }
rec 9.9.9 other_verdict 1; chk; [ $? -eq 1 ] || { echo "иной вердикт принят"; exit 1; }
exit 0
