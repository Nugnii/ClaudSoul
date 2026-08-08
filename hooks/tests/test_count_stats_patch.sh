#!/usr/bin/env bash
# test_count_stats_patch.sh — count-stats --patch-claude-md: числа в CLAUDE.md
# приводит к фактам сам скрипт (D65), идемпотентно, со словоформами.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/count-stats.sh"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if echo "$haystack" | grep -Fq "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in: $haystack"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Фактические числа — из самого скрипта (единый источник).
eval "$(bash "$SCRIPT" 2>/dev/null | grep -E '^(hooks|libs|hook_test_files|mcp_test_files)=')"

# Фикстура с устаревшими числами и словоформами.
cat > "$TMP/CLAUDE.md" << 'EOF'
├── hooks/                 # 44 активных хука + 25 библиотек alive learning system + tests/
| Хуки alive learning system | 44 активных + 25 библиотек |
| Тесты | 79 файлов тестов хуков + 20 mcp (113 mcp-тестов); зелёные |
└── hooks/tests/           # 79 файлов тестов хуков + 20 mcp (см. секцию 5)
EOF

printf '%s\n' "**Current version:** v0.0.0 — 44 active hooks, 21 skills." > "$TMP/README.md"
printf '%s\n' "**Текущая версия:** v0.0.0 — 44 активных хука, 21 скилл." > "$TMP/README.ru.md"

CLAUDE_MD_PATH="$TMP/CLAUDE.md" COUNT_STATS_README="$TMP/README.md" \
    COUNT_STATS_README_RU="$TMP/README.ru.md" bash "$SCRIPT" --patch-claude-md >/dev/null 2>&1
OUT=$(cat "$TMP/CLAUDE.md")

# --- T1: все три места приведены к фактическим числам ---
assert_contains "$OUT" "# $hooks активных" "T1: число хуков в дереве"
assert_contains "$OUT" "+ $libs библиотек alive learning system" "T1b: библиотеки и хвост строки целы"
assert_contains "$OUT" "| $hooks активных + $libs библиотек |" "T1c: строка таблицы хуков"
assert_contains "$OUT" "| Тесты | $hook_test_files файл" "T1d: число тест-файлов"
assert_contains "$OUT" "+ $mcp_test_files mcp (113 mcp-тестов); зелёные" "T1e: хвост строки тестов цел"
assert_contains "$OUT" "# $hook_test_files файл" "T1f: строка hooks/tests/ в дереве тоже правится"

# --- T1g: канонные строки README тоже правятся (класс D65, 2-е проявление) ---
assert_contains "$(cat "$TMP/README.md")" "$hooks active hooks" "T1g: README en"
assert_contains "$(cat "$TMP/README.ru.md")" "$hooks активных" "T1h: README ru"

# --- T2: идемпотентность — второй прогон ничего не меняет ---
BEFORE=$(cat "$TMP/CLAUDE.md")
CLAUDE_MD_PATH="$TMP/CLAUDE.md" bash "$SCRIPT" --patch-claude-md >/dev/null 2>&1
AFTER=$(cat "$TMP/CLAUDE.md")
if [ "$BEFORE" = "$AFTER" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T2]: повторный прогон изменил файл"; fi

# --- T3: словоформа «файл» согласована (не «82 файлов» и не «81 файла») ---
case "$hook_test_files" in
    *1) [ "$hook_test_files" != "11" ] && EXPECT="файл" || EXPECT="файлов" ;;
    *2|*3|*4) case "$hook_test_files" in 12|13|14) EXPECT="файлов" ;; *) EXPECT="файла" ;; esac ;;
    *) EXPECT="файлов" ;;
esac
assert_contains "$OUT" "$hook_test_files $EXPECT тестов" "T3: словоформа '$EXPECT' согласована с $hook_test_files"

echo "test_count_stats_patch: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
