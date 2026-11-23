#!/usr/bin/env bash
# СУДИТ: scripts/state-prune.sh hooks/root-cause-lib.sh
# probe_D1117 — снимки стража (`five-whys-<SID>.snap-*`) уходят из состояния вместе с сессией. Красная (1), пока уборка
# хранит их целиком как семейство `five-whys` (скептик D1108, M2): каждый снимок несёт копию бэклога ClaudSoul (~85 КБ),
# поводов в сессии по 30 живым журналам — медиана 21, максимум 94, предела во времени нет. Контроль рамки: файлы
# переработки тех же старых сессий в списке на удаление есть; журнал `.seen` — нет (хранимое семейство). Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/state-prune.sh" ] || exit 2
ST=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1117.XXXXXX") || exit 2
for i in $(seq 1 12); do
    sid=$(printf '%08x-0000-4000-8000-%012x' "$i" "$i")
    : > "$ST/five-whys-$sid.seen"
    head -c 1000 /dev/zero > "$ST/five-whys-$sid.snap-1234$i.blob"     # нынешняя форма снимка (D1115)
    : > "$ST/rework-$sid"
    touch -t 202601010000 "$ST/five-whys-$sid".* "$ST/rework-$sid"
done
out=$(STATE_DIR="$ST" STATE_PRUNE_KEEP=2 STATE_PRUNE_IDLE_DAYS=14 HOME="$ST/home" bash "$R/scripts/state-prune.sh" --dry-run 2>&1)
[ "$(printf '%s\n' "$out" | grep -c 'rework-')" -gt 0 ] || exit 2
[ "$(printf '%s\n' "$out" | grep -c '\.snap-')" -gt 0 ] || { echo "снимки старых сессий уборкой не берутся" >&2; exit 1; }
# Журнал стража хранится целиком, как прежде: его читают сводка незакрытого и замер долей (за всё время).
[ "$(printf '%s\n' "$out" | grep -c '\.seen')" -eq 0 ] || { echo "журнал стража .seen старых сессий ушёл к удалению" >&2; exit 1; }
echo "снимки уходят вместе с сессией"
exit 0
