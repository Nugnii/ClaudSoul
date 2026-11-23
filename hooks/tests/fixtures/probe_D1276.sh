#!/usr/bin/env bash
# СУДИТ: hooks/timeout-lib.sh scripts/root-map.py scripts/backlog-refresh-readings.sh
# probe_D1276 — срок ожидания без базиса растёт с нагрузкой машины у одного владельца расчёта (`deadline_under_load`,
# `hooks/timeout-lib.sh`): срок пробы корня у `scripts/root-map.py` (её исполняет ловушка коммита) и срок команды
# показания у `scripts/backlog-refresh-readings.sh`. Повод (8–9 ноября 2026): постоянные 120 с под нагрузкой 15–24 —
# ловушка отбила две починки R6 (проба R6 шла 137 с), показание D408 трижды уходило в «НЕ ИЗМЕРЕНО» (корень R1).
# Нагрузка подставлена своей командой `uptime` в PATH: 20 — срок равен расчёту владельца (480 с), 0,4 — прежние 120 с.
# Красная (1), пока какой-то потребитель держит свою постоянную; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
for f in hooks/timeout-lib.sh scripts/root-map.py scripts/backlog-refresh-readings.sh; do [ -f "$R/$f" ] || exit 2; done
command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1276.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
load() { printf '#!/bin/sh\necho "0:01  up 1 day, 3 users, load averages: %s 1.00 1.00"\n' "$1" > "$W/bin/uptime"; chmod +x "$W/bin/uptime"; }
want() { ( . "$R/hooks/timeout-lib.sh"; PATH="$W/bin:$PATH" deadline_under_load 120 ); }
# Срок пробы корня — расчёт владельца, но не выше потолка внешнего срока стража слияния (280 с, скептик opus Н5).
want_probe() { local w; w=$(want); [ "$w" -gt 280 ] 2>/dev/null && w=280; printf '%s' "$w"; }
probe_t() {
    ( cd "$R" && PATH="$W/bin:$PATH" env -u ROOT_MAP_PROBE_TIMEOUT python3 -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("rm_probe", sys.argv[1]); m = importlib.util.module_from_spec(s)
s.loader.exec_module(m); print(int(m.probe_timeout()))' "$R/scripts/root-map.py" 2>/dev/null )
}
reading_t() {
    printf '%s\n' '# B' '' '- ☐ **D9001** проба срока показания' '  **Показание.** `printenv READING_TIMEOUT`' \
        '  **Последнее показание (2026-01-01).** нет' > "$W/B.md"
    ( cd "$W" && PATH="$W/bin:$PATH" env -u READING_TIMEOUT ${READING_TIMEOUT_CONTROL:+READING_TIMEOUT=$READING_TIMEOUT_CONTROL} BACKLOG_FILE="$W/B.md" CLAUDSOUL_REPO="$R" STATE_DIR="$W/st" \
        bash "$R/scripts/backlog-refresh-readings.sh" run >/dev/null 2>&1 )
    sed -n 's/.*\*\*Последнее показание[^*]*\*\* *//p' "$W/B.md"
}
# Положительный контроль рамки показания: явный срок доходит до команды — иначе «не дошёл» неотличим от «не выставлен».
load 0.40
[ "$(READING_TIMEOUT_CONTROL=77 reading_t)" = 77 ] || { echo "рамка: явный READING_TIMEOUT=77 до команды показания не дошёл" >&2; exit 2; }
bad=0
for l in 20.00 0.40; do
    load "$l"; w=$(want)
    [ -n "$w" ] || exit 2
    p=$(probe_t); r=$(reading_t)
    [ -n "$p" ] || { echo "рамка: срок пробы корня не прочитан" >&2; exit 2; }
    wp=$(want_probe)
    [ "$p" = "$wp" ] || { echo "нагрузка $l: срок пробы корня $p с, расчёт владельца $wp с"; bad=1; }
    [ "$r" = "$w" ] || { echo "нагрузка $l: срок команды показания «${r}», расчёт владельца $w с"; bad=1; }
done
exit "$bad"
