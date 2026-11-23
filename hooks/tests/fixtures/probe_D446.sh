#!/usr/bin/env bash
# СУДИТ: scripts/root-map.py
# probe_D446.sh — D446: прибор карты корней сверяет объявленную дробь корня с носителями его пробы и отвечает
# тремя разными словами: «сходится» / «РАСХОЖДЕНИЕ» / «НЕ ПОСЧИТАНЫ»; шапка пробы `# мест: N` носителем не считается.
# Судится ПРИБОР на песочной карте и песочной пробе, а не живая ROOTS.md: число носителей живого дерева
# растёт с деревом, его мерит замер реестра `root-map-drift` (scripts/measurements.tsv).
# Коды: 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
RM="$R/scripts/root-map.py"
[ -f "$RM" ] || { echo "рамка: нет $RM" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "рамка: нужен python3" >&2; exit 2; }
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/scripts/probes" || exit 2
printf 'echo "# мест: 3"\necho a.sh:1\necho b.sh:2\necho c.sh:3\n' > "$d/scripts/probes/R1.sh"
roots() {  # roots <дробь> <путь пробы>
  printf '# карта\n\n## R1 — проба\n\n**Признак.** `%s`\n**Дробь.** %s\n' "$2" "$1" > "$d/ROOTS.md"; }
say() { ( cd "$d" && CLAUDSOUL_REPO="$d" python3 "$RM" --root R1 2>&1 ); }
roots '1 из 3' scripts/probes/R1.sh; out=$(say)
{ grep -q 'сходится' <<<"$out" && ! grep -q 'РАСХОЖДЕНИЕ' <<<"$out"; } || { echo "объявленное 1 из 3 при трёх носителях не названо «сходится» (шапка проба считается носителем?): ${out:0:200}"; exit 1; }
roots '1 из 2' scripts/probes/R1.sh; out=$(say)
grep -q 'РАСХОЖДЕНИЕ' <<<"$out" || { echo "объявленное 1 из 2 при трёх носителях не названо РАСХОЖДЕНИЕМ: ${out:0:200}"; exit 1; }
roots '1 из 3' scripts/probes/нет.sh; out=$(say)
{ grep -q 'НЕ ПОСЧИТАНЫ\|НЕ ИЗМЕРЕНО' <<<"$out" && ! grep -q 'сходится' <<<"$out"; } || { echo "отсутствующая проба не названа «не измерено»: ${out:0:200}"; exit 1; }
exit 0
