#!/usr/bin/env bash
# СУДИТ: hooks/tests/drift-check.sh scripts/measurements.tsv
# probe_D243.sh — сверщик «репозиторий → установленное» называет хук, чья работающая копия отстала
# (D243: в установленном completion-gate.sh не было маркера BACKLOG_CHECKS_NESTED), а срок замера
# install-drift в реестре заменяет повод, которого D203 не дал.
#
# Коды: 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
# Рамка: песочные CLAUDE_HOME и HOME с копией хуков репозитория; живая установка не читается.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
d=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$d"' EXIT
[ -f "$REPO/hooks/tests/drift-check.sh" ] && [ -f "$REPO/hooks/completion-gate.sh" ] || { echo "РАМКА: нет сверщика или completion-gate.sh"; exit 2; }
mkdir -p "$d/home" "$d/c/hooks" || exit 2
h="$REPO/hooks"; cp "$h"/*.sh "$d/c/hooks/" || exit 2
run() { HOME="$d/home" CLAUDE_HOME="$d/c" CLAUDSOUL_REPO="$REPO" bash "$REPO/hooks/tests/drift-check.sh" 2>&1; }
# 1) копия точная: пара «хуки» OK, иначе сверщик краснит на ровном месте
out=$(run); grep -q '^OK|хуки|' <<<"$out" || { echo "ЛОЖНЫЙ-DRIFT: точная копия хуков не OK"; exit 1; }
# 2) отстающая копия (в ней нет маркера шторма): пара DRIFT, имя файла названо, код 1
sed -i.bak 's/BACKLOG_CHECKS_NESTED/BACKLOG_CHECKS_GONE/g' "$d/c/hooks/completion-gate.sh" && rm -f "$d/c/hooks/completion-gate.sh.bak"
cmp -s "$REPO/hooks/completion-gate.sh" "$d/c/hooks/completion-gate.sh" && { echo "РАМКА: мутация не изменила копию"; exit 2; }
out=$(run); rc=$?
grep -q '^DRIFT|хуки|.*completion-gate.sh' <<<"$out" || { echo "НЕ-НАЗВАН: отставший completion-gate.sh не назван в паре «хуки»"; exit 1; }
[ "$rc" -eq 1 ] || { echo "КОД: DRIFT дал код $rc, ждали 1"; exit 1; }
# 3) срок вместо повода: замер install-drift в реестре с периодом не больше суток
awk -F'\t' '$1=="install-drift" && $2+0>=1 && $2+0<=1 && $3 ~ /drift-check\.sh/ {f=1} END{exit !f}' "$REPO/scripts/measurements.tsv" || { echo "РЕЕСТР: строки install-drift с периодом 1 нет"; exit 1; }
exit 0
