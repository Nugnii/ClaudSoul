#!/usr/bin/env bash
set -u
# СУДИТ: hooks/tool-gate-check.sh
# probe_D1259 — хук-режим подсказки о вызове инструмента без гейта судит предмет из шапки (`hooks/*.sh`), а не каталог
#   любого правленного файла под `hooks/`:
#   (к) правка `<песочница>/hooks/x.sh` с вызовом без гейта — подсказка называет `x.sh` (положительный контроль);
#   (п) правка `<песочница>/hooks/tests/fixtures/y.sh` с тем же вызовом — подсказка молчит: тесты и пробы не предмет.
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
H="$R/hooks/tool-gate-check.sh"
[ -f "$H" ] && command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hooks/tests/fixtures" || exit 2
printf '%s\n' 'X="$ROOT/scripts/nope.py"' 'python3 "$X"' > "$T/hooks/x.sh"
printf '%s\n' 'X="$ROOT/scripts/nope.py"' 'python3 "$X"' > "$T/hooks/tests/fixtures/y.sh"
said() { jq -cn --arg f "$1" '{tool_name:"Edit", tool_input:{file_path:$f}}' | bash "$H" 2>/dev/null; }
k=$(said "$T/hooks/x.sh")
case "$k" in *x.sh*) ;; *) echo "рамка: правка hooks/x.sh с вызовом без гейта не названа" >&2; exit 2 ;; esac
p=$(said "$T/hooks/tests/fixtures/y.sh")
[ -z "$p" ] && { echo "правка файла под hooks/tests/ подсказки не поднимает; hooks/x.sh судится"; exit 0; }
echo "правка hooks/tests/fixtures/y.sh подняла подсказку на каталог проб"
exit 1
