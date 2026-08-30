#!/usr/bin/env bash
# test_adv3_relpath_hang.sh — find_project_root зацикливается на относительном пути.
#
# dirname "foo"  -> "."   и   dirname "." -> "."
# Условие выхода из цикла — `[ -n "$dir" ] && [ "$dir" != "/" ]` — на "." никогда
# не выполняется. Функция крутится вечно, если в текущем каталоге нет .git/CLAUDE.md.
#
# Достижимость: hooks/knowledge-activator.sh:608 и :735 вызывают
#   find_project_root "${CWD:-$PWD}", где CWD=$(jq -r '.cwd // ""') — БЕЗ проверки -d.
# hooks/session-start.sh:89 и hooks/pre-compact-handoff.sh:36 проверяют [ -d "$CWD" ],
# но `[ -d "." ]` истинно всегда — относительный путь проходит этот фильтр.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/paths-lib.sh"
TMP="$(mktemp -d)"
mkdir -p "$TMP/plain/sub"

cat > "$TMP/probe.sh" <<'EOF'
source "$1"
cd "$2" || exit 3
find_project_root "sub/deeper"
EOF

# Сторож: без него падающий тест повесил бы прогон навсегда.
bash "$TMP/probe.sh" "$LIB" "$TMP/plain" > "$TMP/out" 2>&1 &
probe=$!
( sleep 5; kill -9 "$probe" 2>/dev/null ) > /dev/null 2>&1 &
watchdog=$!
wait "$probe" 2>/dev/null; rc=$?
kill "$watchdog" 2>/dev/null

if [ "$rc" -eq 0 ]; then
    echo "PASS: find_project_root вернулся, отдал «$(cat "$TMP/out")»"
    echo "adv3 relpath hang: 1/1 passed"
    exit 0
fi

echo "FAIL [paths-lib.sh:find_project_root]: относительный путь «sub/deeper» из каталога"
echo "     без .git/CLAUDE.md не завершает walk-up — процесс убит сторожем (rc=$rc,"
echo "     137 = SIGKILL). Ожидалось: вернуть стартовый путь, как для абсолютного случая."
echo "adv3 relpath hang: 0/1 passed"
exit 1
