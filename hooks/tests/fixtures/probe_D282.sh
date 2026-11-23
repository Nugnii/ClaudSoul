#!/usr/bin/env bash
# СУДИТ: scripts/instrument-result-measured.sh
# probe_D282.sh — сверщик называет инструмент измеренным только при свидетеле, красном на заглушке `exit 0`;
# тест «только код 0» и инструмент без кандидатов не засчитываются; --check называет устаревший снимок кодом 1 (D282).
#
# Коды: 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
# Рамка: песочный git-репозиторий из двух инструментов, IRM_ROOT и STATE_DIR в нём; живое дерево и снимок не читаются.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
d=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$d"' EXIT
IRM="$REPO/scripts/instrument-result-measured.sh"
[ -f "$IRM" ] || { echo "РАМКА: нет instrument-result-measured.sh"; exit 2; }
FX="$d/fx"; mkdir -p "$FX/scripts" "$FX/hooks/tests" "$d/state" || exit 2
export IRM_ROOT="$FX" STATE_DIR="$d/state" SUITE_BASELINE_FILE="$d/нет-базиса" IRM_TIMEOUT=5
hdr() { printf '#!/usr/bin/env bash\n# %s\n# Результат: печать ok\n# Проверка результата: %s даёт 0\n' "$1" "$2"; }
{ hdr good.sh "bash hooks/tests/test_good.sh"; echo 'echo ok'; } > "$FX/scripts/good.sh"
printf '#!/usr/bin/env bash\nout=$(bash "$(dirname "$0")/../../scripts/good.sh")\n[ "$out" = ok ] || { echo "FAIL: good.sh молчит"; exit 1; }\nexit 0\n' > "$FX/hooks/tests/test_good.sh"
{ hdr weak.sh "bash scripts/weak.sh"; echo 'echo ok'; } > "$FX/scripts/weak.sh"
printf '#!/usr/bin/env bash\nbash "$(dirname "$0")/../../scripts/weak.sh" >/dev/null\nexit $?\n' > "$FX/hooks/tests/test_weak.sh"
chmod +x "$FX"/scripts/* "$FX"/hooks/tests/*
git init -q "$FX" && git -C "$FX" add -A || exit 2
out=$(bash "$IRM" 2>&1); rc=$?
case "$out" in *"измерен "*"scripts/good.sh"*) ;; *) echo "НЕ-ИЗМЕРЕН: инструмент со свидетелем по поведению не назван измеренным"; exit 1 ;; esac
grep -q '^НЕ ИЗМЕРЕН .*scripts/weak.sh' <<<"$out" || { echo "ЗАСЧИТАН: тест «только код 0» признан свидетелем"; exit 1; }
[ "$rc" -eq 1 ] || { echo "КОД: при неизмеренном инструменте код $rc, ждали 1"; exit 1; }
# слабого убираем из дерева: дальше --check судит только good.sh (иначе его НЕ ИЗМЕРЕН краснил бы за него)
git -C "$FX" rm -q -f scripts/weak.sh hooks/tests/test_weak.sh || exit 2
bash "$IRM" --check >/dev/null 2>&1 || { echo "ЛОЖНЫЙ-КРАСНЫЙ: --check при свежем снимке единственного измеренного не 0"; exit 1; }
echo '# правка' >> "$FX/scripts/good.sh"; git -C "$FX" add -A
out=$(bash "$IRM" --check 2>&1); rc=$?
grep -q '^УСТАРЕЛ .*scripts/good.sh' <<<"$out" && [ "$rc" -eq 1 ] || { echo "УСТАРЕЛ: правка инструмента не обесценила снимок (код $rc)"; exit 1; }
exit 0
