#!/usr/bin/env bash
# СУДИТ: lib/claude-md-merge.sh hooks/tests/test_defect_registry_cache.sh
# D376: sync_claude_md берёт замок на файле цели (with_lock <цель>) и сливает под ним; тест кэша
# реестра правит пробный репозиторий, а не рабочее дерево. Замок — шпион (STATE_LOCK_LIB), HOME песочный.
# 0 — держится; 1 — нарушено (слово в stdout); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
[ -f "$R/lib/claude-md-merge.sh" ] || { echo "рамка: нет lib/claude-md-merge.sh" >&2; exit 2; }
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/home" || exit 2
cat > "$d/spy.sh" <<'X'
with_lock() { printf '%s\n' "$1" >> "$SPY_LOG"; local k="$1"; shift; "$@"; }
X
printf '# мастер\nстрока\n' > "$d/master.md"
printf 'мои правки\n' > "$d/target.md"
: > "$d/spy.log"
( export HOME="$d/home" SPY_LOG="$d/spy.log" STATE_LOCK_LIB="$d/spy.sh"
  . "$R/lib/claude-md-merge.sh" 2>/dev/null
  sync_claude_md "$d/target.md" "$d/master.md" ) >/dev/null 2>&1 || { echo "рамка: слияние не отработало" >&2; exit 2; }
[ "$(cat "$d/spy.log")" = "$d/target.md" ] || { echo "НЕТ замка на цели: шпион видел «$(cat "$d/spy.log")»"; exit 1; }
grep -q 'мои правки' "$d/target.md" && grep -q 'строка' "$d/target.md" || { echo "слияние под замком потеряло содержимое"; exit 1; }
# тест кэша реестра не правит рабочее дерево: пробный репозиторий, а не $ROOT/$VF
T="$R/hooks/tests/test_defect_registry_cache.sh"
grep -q 'TMP_PROBE=$(mktemp -d)' "$T" || { echo "тест кэша без пробного репозитория"; exit 1; }
grep -Eq '\$ROOT/\$VF|"\$ROOT/\$\{?VF' "$T" && { echo "тест кэша снова правит файл рабочего дерева \$ROOT/\$VF"; exit 1; }
exit 0
