#!/usr/bin/env bash
set -u
# СУДИТ: scripts/guard-edition-exposures.sh scripts/instrument-result-measured.sh
# probe_D1226 — у `scripts/guard-edition-exposures.sh` есть свидетель, красный на выпотрошенном инструменте: сверка
#   инструментов (`instrument-result-measured.sh`) называет его измеренным. Рамка настоящая: прибор сверки на дереве
#   (копия индекса git), снимок — в песочном каталоге состояния.
#   0 — инструмент измерен; 1 — не измерен; 2 — нет прибора сверки или инструмента, прибор не дал строки.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
I="$PWD/scripts/instrument-result-measured.sh"
for f in "$I" scripts/guard-edition-exposures.sh; do [ -f "$f" ] || exit 2; done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
out=$(STATE_DIR="$W" bash "$I" scripts/guard-edition-exposures.sh 2>/dev/null)
line=$(printf '%s\n' "$out" | grep 'guard-edition-exposures.sh' | head -1)
[ -n "$line" ] || exit 2
case "$line" in "измерен "*) exit 0 ;; *) echo "$line"; exit 1 ;; esac
