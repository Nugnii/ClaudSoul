#!/usr/bin/env bash
set -u
# СУДИТ: scripts/root-map.py scripts/docs-refresh-claims.sh hooks/lib/bounded_run.py
# probe_D1239 — исполнители проб со сроком (`root-map.py` — пробы корней, `docs-refresh-claims.sh` — источники чисел)
#   снимают по сроку дерево команды правилом `hooks/lib/bounded_run.py`: после выхода прибора внука команды нет, а голый
#   `mktemp -d` команды лёг в её собственный TMPDIR, убранный вместе с ней. Рамка: песочная карта (ROOTS_MAP) и песочный
#   реестр чисел; команда пишет номер внука `sleep 30` и создаёт каталог голым `mktemp -d`, затем спит дольше срока 1 с.
#   0 — у обоих внук снят и каталога в TMPDIR вызвавшего нет; 1 — внук жив или каталог остался; 2 — рамка не собралась.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
for f in scripts/root-map.py scripts/docs-refresh-claims.sh hooks/lib/bounded_run.py; do [ -f "$f" ] || exit 2; done
W=$(mktemp -d) || exit 2
trap 'for p in $(cat "$W"/*.pid 2>/dev/null); do kill -9 "$p" 2>/dev/null; done; rm -rf "$W"' EXIT
mkdir -p "$W/m/scripts/probes" "$W/outer"
mk_cmd() {  # <файл> <метка>
    printf '#!/usr/bin/env bash\nbash -c "sleep 30" &\necho $! > "%s/%s.pid"\nd=$(mktemp -d)\necho "$d" > "%s/%s.dir"\nsleep 20\n' \
        "$W" "$2" "$W" "$2" > "$1"
}
mk_cmd "$W/m/scripts/probes/R99.sh" rm
printf '## R99 — проба пробы\n\n**Признак.** `scripts/probes/R99.sh`\n\n**Дробь.** 0 из 0 — проба.\n' > "$W/m/ROOTS.md"
mk_cmd "$W/figures.sh" drc
printf 'doc.md\t^(\\d+)\tkey\t\tпроба\n' > "$W/claims.tsv"
printf '1\n' > "$W/m/doc.md"
alive() { kill -0 "$(cat "$W/$1.pid" 2>/dev/null)" 2>/dev/null; }
leftover() { d=$(cat "$W/$1.dir" 2>/dev/null); [ -n "$d" ] && [ -d "$d" ]; }
bad=0
TMPDIR="$W/outer" ROOTS_MAP="$W/m/ROOTS.md" ROOT_MAP_PROBE_TIMEOUT=1 python3 scripts/root-map.py --check --root R99 >/dev/null 2>&1
[ -f "$W/rm.pid" ] || { echo "рамка: проба корня не запустилась"; exit 2; }
alive rm && { echo "root-map.py: внук пробы жив после срока"; bad=1; }
leftover rm && { echo "root-map.py: каталог пробы остался ($(cat "$W/rm.dir"))"; bad=1; }
TMPDIR="$W/outer" CLAUDSOUL_REPO="$W/m" DOC_CLAIMS_FILE="$W/claims.tsv" DOC_FIGURES="$W/figures.sh" DOC_FIGURES_TIMEOUT=1 \
    bash scripts/docs-refresh-claims.sh check >/dev/null 2>&1
[ -f "$W/drc.pid" ] || { echo "рамка: источник числа не запустился"; exit 2; }
alive drc && { echo "docs-refresh-claims.sh: внук источника жив после срока"; bad=1; }
leftover drc && { echo "docs-refresh-claims.sh: каталог источника остался ($(cat "$W/drc.dir"))"; bad=1; }
exit "$bad"
