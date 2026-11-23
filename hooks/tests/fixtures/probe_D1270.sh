#!/usr/bin/env bash
set -u
# СУДИТ: scripts/root-map.py
# probe_D1270 — полная сверка карты корней (`root-map.py --check`) с непосчитанным корнем отвечает «не измерено» (код 2) и
#   называет корень, а не 0 и «дроби совпадают». Рамка: песочная карта (ROOTS_MAP) из быстрого корня R98 (одна строка
#   носителя, объявлено «1 из 1») и медленного R99 (спит дольше срока ROOT_MAP_PROBE_TIMEOUT=1). Контроли: карта из одного
#   R98 — 0; R98 с неверной дробью рядом с R99 — 1 (расхождение важнее) и R99 назван.
#   0 — все три ответа верны; 1 — нет; 2 — рамка не собралась.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
[ -f scripts/root-map.py ] || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/a/scripts/probes" "$W/b/scripts/probes" "$W/c/scripts/probes"
for d in a b c; do printf '#!/usr/bin/env bash\necho носитель\n' > "$W/$d/scripts/probes/R98.sh"; done
for d in a c; do printf '#!/usr/bin/env bash\nsleep 20\n' > "$W/$d/scripts/probes/R99.sh"; done
r98() { printf '## R98 — быстрый корень\n\n**Признак.** `scripts/probes/R98.sh`\n\n**Дробь.** 1 из %s — проба.\n\n' "$1"; }
r99='## R99 — медленный корень\n\n**Признак.** `scripts/probes/R99.sh`\n\n**Дробь.** 0 из 0 — проба.\n'
{ r98 1; printf "$r99"; } > "$W/a/ROOTS.md"
r98 1 > "$W/b/ROOTS.md"
{ r98 5; printf "$r99"; } > "$W/c/ROOTS.md"
chk() { ROOTS_MAP="$W/$1/ROOTS.md" ROOT_MAP_PROBE_TIMEOUT=1 python3 scripts/root-map.py --check > "$W/$1.out" 2>&1; echo $?; }
bad=0
rc=$(chk a); [ "$rc" = 2 ] && grep -q 'НЕ ПОСЧИТАНЫ у R99' "$W/a.out" \
    || { echo "непосчитанный R99: код $rc, ждали 2 со словами «НЕ ПОСЧИТАНЫ у R99»"; tail -2 "$W/a.out"; bad=1; }
grep -q 'объявленные дроби совпадают' "$W/a.out" && { echo "при непосчитанном корне объявлено совпадение"; bad=1; }
rc=$(chk b); [ "$rc" = 0 ] || { echo "контроль: карта без медленного корня — код $rc, ждали 0"; tail -2 "$W/b.out"; bad=1; }
rc=$(chk c); [ "$rc" = 1 ] && grep -q 'НЕ ПОСЧИТАНЫ у R99' "$W/c.out" \
    || { echo "расхождение рядом с непосчитанным: код $rc, ждали 1 и названный R99"; tail -2 "$W/c.out"; bad=1; }
exit "$bad"
