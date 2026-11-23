#!/usr/bin/env bash
# СУДИТ: scripts/state-prune.sh scripts/state-size.sh
# probe_D1006.sh — сессия в тишине уходит из состояния целиком, включая файлы с ключом после идентификатора;
# свежая и входящая в окно остаются; порог замера стоит у установившегося режима (D1006).
#
# Коды: 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
# Рамка: песочные STATE_DIR, HOME и SR_SESSIONS_DIR; живой каталог состояния не читается.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
d=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$d"' EXIT
P="$REPO/scripts/state-prune.sh"; Z="$REPO/scripts/state-size.sh"
[ -f "$P" ] && [ -f "$Z" ] || { echo "РАМКА: нет state-prune.sh или state-size.sh"; exit 2; }
ST="$d/state"; mkdir -p "$ST" "$d/.claude/sessions" || exit 2
sid() { printf '%08x-1111-2222-3333-%012x' "$1" "$1"; }
# три давно молчащие сессии (разные mtime — ранг) и одна свежая; у каждой файл без ключа и файлы с ключом-хешем
for i in 1 2 3 4; do
  s=$(sid "$i")
  : > "$ST/rework-$s.jsonl"; : > "$ST/module-ctx-$s-aaaa$i$i$i$i.flag"; : > "$ST/module-ctx-$s-bbbb$i$i$i$i.flag"
  if [ "$i" -le 3 ]; then touch -t "20250901000$i" "$ST/"*"$s"*; fi
done
fresh=$(sid 4)
cnt() { find "$ST" -maxdepth 1 -type f -name "*$1*" | wc -l | tr -d ' '; }
run() { STATE_DIR="$ST" HOME="$d" SR_SESSIONS_DIR="$d/.claude/sessions" STATE_PRUNE_KEEP="$1" bash "$P" --apply >/dev/null 2>&1; }
run 10
[ "$(find "$ST" -type f | wc -l | tr -d ' ')" = 12 ] || { echo "ОКНО: сессии внутри окна последних тронуты"; exit 1; }
run 1
for i in 1 2 3; do
  [ "$(cnt "$(sid "$i")")" = 0 ] || { echo "ТИШИНА: молчащая сессия $i осталась ($(cnt "$(sid "$i")") файлов): ключи после идентификатора держат её вечно"; exit 1; }
done
[ "$(cnt "$fresh")" = 3 ] || { echo "СВЕЖАЯ: свежая сессия тронута ($(cnt "$fresh") из 3)"; exit 1; }
# порог замера: установившийся режим 6000 файлов / 160 МБ (объём пересчитан с писателем снимков — D1225, решение
# владельца 7 ноября 2026), а не прежние 3000 / 40
grep -q 'STATE_MAX_FILES:-6000' "$Z" && grep -q 'STATE_MAX_MB:-160' "$Z" || { echo "ПОРОГ: умолчания state-size не 6000 / 160"; exit 1; }
STATE_DIR="$ST" bash "$Z" >/dev/null 2>&1 || { echo "ЗАМЕР: малый каталог под порогом не дал 0"; exit 1; }
exit 0
