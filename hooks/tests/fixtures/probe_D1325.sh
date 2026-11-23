#!/usr/bin/env bash
# СУДИТ: hooks/tests/fixtures/adversary-recall/2026-11-18-head.tsv hooks/tests/fixtures/adversary-recall/2026-11-18-triage.tsv
# probe_D1325.sh — у каждой атаки критиков замера полноты 18 ноября 2026 есть исход разбора.
#
# Проверка результата: bash hooks/tests/fixtures/probe_D1325.sh → 0 — каждая атака таблицы перепрогона названа в
#   разборе (`<случай>/<тест>` ⇥ исход: D<N> | не дефект | предел <почему> | показалось); 1 — есть без исхода;
#   2 — не измерено (нет таблицы перепрогона).
# Сами тесты атак — архив вне репозитория (`.claude-docs/adversary-recall/2026-11-18-attacks.tar.gz`, каталог закрыт
# .gitignore): в них абсолютные пути машины, а двоичный архив прошёл бы мимо чистки при публикации.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
H="$REPO/hooks/tests/fixtures/adversary-recall/2026-11-18-head.tsv"
T="$REPO/hooks/tests/fixtures/adversary-recall/2026-11-18-triage.tsv"
[ -f "$H" ] || { echo "нет таблицы перепрогона — не измерено"; exit 2; }
list=$(awk -F'\t' '!/^#/ && NF >= 2 { print $1 "/" $2 }' "$H" | sort -u)
total=$(grep -c . <<< "$list")
[ "$total" -gt 0 ] || { echo "таблица перепрогона пуста — не измерено"; exit 2; }
done_=$(awk -F'\t' '!/^#/ && $2 != "" { print $1 }' "$T" 2>/dev/null | sort -u)
left=$(comm -23 <(printf '%s\n' "$list") <(printf '%s\n' "$done_"))
n=$(grep -c . <<< "$left")
[ "$n" = 0 ] && { echo "разобраны все $total"; exit 0; }
echo "без исхода разбора: $n из $total"
exit 1
