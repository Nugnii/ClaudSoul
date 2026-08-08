#!/usr/bin/env bash
# test_rework_detector.sh — детектор третьего захода на тот же файл.
#
# Отрицательный контроль обязателен по построению (правило v1.12.4): проверка,
# про которую не показано, что она способна упасть, ничего не доказывает. Поэтому
# у каждого случая есть пара — вход, на котором детектор ОБЯЗАН молчать.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/rework-detector.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 200)"; fi
}
assert_empty() {
    if [ -z "$1" ] || [ "$1" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; fi
}

edit() { # sid, path
    jq -cn --arg s "$1" --arg p "$2" \
        '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$p}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
run() { # sid
    jq -cn --arg s "$1" '{session_id:$s, tool_name:"Bash", tool_input:{command:"bash test.sh"}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
mkdir -p "$TMP/state"

# === T1: правка → прогон → правка → прогон → правка = третий заход, горит ===
OUT=$(edit s1 /repo/test_x.sh); assert_empty "$OUT" "T1a: первая правка → тишина"
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh); assert_empty "$OUT" "T1b: вторая правка → тишина"
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh)
assert_contains "$OUT" "Переработка" "T1c: третья правка в цепочке → горит"
assert_contains "$OUT" "test_x.sh" "T1d: назван файл"
assert_contains "$OUT" "Почему предыдущая правка не сработала" "T1e: даны вопросы разбора"

# === T2: три правки ПОДРЯД без прогонов — обычное дописывание, не переработка ===
OUT=$(edit s2 /repo/doc.md); assert_empty "$OUT" "T2a: первая → тишина"
OUT=$(edit s2 /repo/doc.md); assert_empty "$OUT" "T2b: вторая подряд → тишина"
OUT=$(edit s2 /repo/doc.md)
assert_empty "$OUT" "T2c: третья подряд без прогонов → тишина (не переработка)"

# === T3: правки РАЗНЫХ файлов с прогонами — не цепочка ===
edit s3 /repo/a.sh >/dev/null; run s3 >/dev/null
edit s3 /repo/b.sh >/dev/null; run s3 >/dev/null
OUT=$(edit s3 /repo/c.sh)
assert_empty "$OUT" "T3: разные файлы → тишина"

# === T4: повторное срабатывание по тому же файлу подавлено ===
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh)
assert_empty "$OUT" "T4: второй раз по тому же файлу в сессии → тишина (throttle)"

# === T5: другая сессия считается независимо ===
edit s5 /repo/test_x.sh >/dev/null; run s5 >/dev/null
edit s5 /repo/test_x.sh >/dev/null; run s5 >/dev/null
OUT=$(edit s5 /repo/test_x.sh)
assert_contains "$OUT" "Переработка" "T5: новая сессия — свой счёт"

# === T6: порог настраивается ===
OUT=$(jq -cn '{session_id:"s6", tool_name:"Edit", tool_input:{file_path:"/repo/z.sh"}}' \
    | env STATE_DIR="$TMP/state" REWORK_THRESHOLD=1 bash "$HOOK" 2>/dev/null)
assert_contains "$OUT" "Переработка" "T6: порог 1 → горит с первой правки"

# === T8: файлы-хроники исключены (калибровка D18) ===
edit s8 /repo/CHANGELOG.md >/dev/null; run s8 >/dev/null
edit s8 /repo/CHANGELOG.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/CHANGELOG.md)
assert_empty "$OUT" "T8: CHANGELOG.md — хроника, детектор молчит"
edit s8 /repo/sub/SESSION.md >/dev/null; run s8 >/dev/null
edit s8 /repo/sub/SESSION.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/sub/SESSION.md)
assert_empty "$OUT" "T8b: SESSION.md во вложенной папке — тоже хроника"
OUT=$(jq -cn '{session_id:"s8", tool_name:"Edit", tool_input:{file_path:"/repo/BACKLOG-archive.md"}}' \
    | env STATE_DIR="$TMP/state" REWORK_THRESHOLD=1 bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T8c: BACKLOG-archive.md исключён даже при пороге 1"

# === T7: мусор на входе не роняет хук ===
OUT=$(printf 'not-json' | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null); RC=$?
assert_empty "$OUT" "T7a: мусор → тишина"
if [ "$RC" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [T7b]: rc=$RC"; fi

echo ""
echo "=================================="
echo "rework-detector: $PASS passed, $FAIL failed"
echo "=================================="
[ "$FAIL" -eq 0 ]
