#!/usr/bin/env bash
set -u
# СУДИТ: ROOTS.md scripts/root-map.py
# probe_D1236 — объявленные дроби корней R1, R2 и R3 карты `ROOTS.md` сходятся с командами их проб: владелец сверки —
#   `scripts/root-map.py --check --root <R>` (0 — совпали, 1 — расхождение, 2 — прибор не отработал).
#   0 — все три сходятся; 1 — хоть одна разошлась (вывод сверки печатается); 2 — нет карты или прибора, прибор сломан.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
for f in ROOTS.md scripts/root-map.py; do [ -f "$f" ] || exit 2; done
bad=0
for r in R1 R2 R3; do
    out=$(python3 scripts/root-map.py --check --root "$r" 2>&1); rc=$?
    case "$rc" in
        # Код 0 засчитывается только со словами сверки (D1222: выпотрошенный прибор отвечал 0, и проба зеленела —
        # она верила одному коду): «✓ дробь сходится» печатает лишь честная сверка корня.
        0) printf '%s\n' "$out" | grep -q '✓ дробь сходится' \
               || { echo "сверка $r ответила 0 без строки «дробь сходится» — не судила"; bad=1; } ;;
        1) printf '%s\n' "$out" | grep 'РАСХОЖДЕНИЕ'; bad=1 ;;
        *) echo "сверка $r не отработала (код $rc)"; exit 2 ;;
    esac
done
exit "$bad"
