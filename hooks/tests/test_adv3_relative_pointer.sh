#!/usr/bin/env bash
# test_adv3_relative_pointer.sh — относительный путь в файле-указателе принимается.
#
# Проверка `[ -d "$_cs_pointer" ]` (paths-lib.sh:34) истинна и для относительного пути:
# для «.» — всегда. CLAUDSOUL_ROOT становится относительным, то есть означает РАЗНОЕ
# при каждом запуске хука, потому что хуки стартуют с cwd проекта, а не ClaudSoul.
#
# Достижимость: install.sh:7 — CLAUDSOUL_DIR="${1:-$(cd "$(dirname "$0")" && pwd)}".
# Позиционный аргумент берётся ДОСЛОВНО, без приведения к абсолютному, и install.sh:70
# пишет его в указатель как есть: echo "$CLAUDSOUL_DIR" > "$REPO_POINTER".
# То есть `bash install.sh .` кладёт в ~/.claude/claudsoul-repo одну точку.
#
# bin/resolve-claudsoul-repo.sh такой указатель отвергает: он требует
# [ -d "$path/mcp-server/ingest" ], а не просто [ -d "$path" ].

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/paths-lib.sh"
TMP="$(mktemp -d)"
mkdir -p "$TMP/home/.claude" "$TMP/projA" "$TMP/projB"

# Ровно то, что записал бы `bash install.sh .`
printf '.\n' > "$TMP/home/.claude/claudsoul-repo"

run_from() { ( cd "$1" && env -u CLAUDSOUL_ROOT HOME="$TMP/home" \
    bash -c "source '$LIB'; printf '%s' \"\$CLAUDSOUL_ROOT\"" ); }

a=$(run_from "$TMP/projA")
b=$(run_from "$TMP/projB")

case "$a" in
    /*) ;;
    *)  echo "FAIL [paths-lib.sh:34]: указатель «.» принят как корень — CLAUDSOUL_ROOT=«${a}»."
        echo "     Значение относительное: из $TMP/projA оно указывает на projA,"
        echo "     из $TMP/projB — на projB (получено «${b}»), при одном и том же указателе."
        echo "     Ожидалось: относительный указатель отвергается как битый (откат к дефолту)."
        echo "adv3 relative pointer: 0/1 passed"
        exit 1 ;;
esac

echo "PASS: относительный указатель отвергнут, CLAUDSOUL_ROOT=«${a}»"
echo "adv3 relative pointer: 1/1 passed"
exit 0
