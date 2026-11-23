#!/usr/bin/env bash
# СУДИТ: scripts/regen-seed.py
# probe_D250.sh — прибор seed: пересборка делает seed равным рабочей базе, а --check это видит (D250).
#
# Коды: 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
# Рамка: копия прибора в песочном «репозитории», песочная база LESSONS_DIR из четырёх файлов;
# живые knowledge/ и ~/.claude/global-lessons не читаются и не пишутся.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
d=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$d"' EXIT
[ -f "$REPO/scripts/regen-seed.py" ] || { echo "РАМКА: нет regen-seed.py"; exit 2; }
mkdir -p "$d/r/scripts" "$d/r/knowledge" "$d/l" || exit 2
cp "$REPO/scripts/regen-seed.py" "$d/r/scripts/" || exit 2
mk() { printf -- '---\nname: %s\nscope: %s\nconfirmed_count: 7\ncontradicted_count: 2\nsource_session: abc-123\n---\nтело %s\n' "$1" "$2" "$3" > "$d/l/$1.md"; }
mk pattern-p-universal universal 1
mk pattern-p-local project 1
mk principle-p-all universal 1
mk principle-p-speaker per-speaker 1
run() { LESSONS_DIR="$d/l" python3 "$d/r/scripts/regen-seed.py" "$@" 2>&1; }
run --check >/dev/null; rc=$?
[ "$rc" -eq 1 ] || { echo "ЧЕК-ПУСТОЙ: seed пуст, а --check дал $rc, ждали 1"; exit 1; }
run >/dev/null || { echo "РАМКА: пересборка упала"; exit 2; }
run --check >/dev/null || { echo "НЕ-СОВПАЛ: после пересборки --check не 0"; exit 1; }
[ -f "$d/r/knowledge/pattern-p-universal.md" ] && [ -f "$d/r/knowledge/principle-p-all.md" ] || { echo "НЕ-ПЕРЕНЕСЕНО: universal-паттерн или принцип не в seed"; exit 1; }
[ ! -e "$d/r/knowledge/pattern-p-local.md" ] && [ ! -e "$d/r/knowledge/principle-p-speaker.md" ] || { echo "УТЕЧКА: не-universal попал в seed"; exit 1; }
k1=confirmed_count; k2=source_session; grep -q "^$k1: 1\$" "$d/r/knowledge/pattern-p-universal.md" && grep -q "^$k2: \"\"\$" "$d/r/knowledge/pattern-p-universal.md" || { echo "СЧЁТЧИКИ: счётчики или source_session не сброшены"; exit 1; }
mk pattern-p-universal universal 2
out=$(run --check); rc=$?
[ "$rc" -eq 1 ] && grep -q 'расходится: pattern-p-universal.md' <<<"$out" || { echo "НЕ-ВИДИТ: правка рабочей базы не названа (код $rc)"; exit 1; }
exit 0
