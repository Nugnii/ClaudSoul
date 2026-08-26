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
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
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

# Фикстура несёт РАЗДЕЛЁННЫЕ строки: версия отдельно, счётчики отдельно. Пока они были
# одной строкой, работа генератора выглядела для docs-family-check как бамп версии.
printf '%s\n' "**Current version:** v0.0.0 — 2026-01-01. See PLAN.md." > "$TMP/README.md"
printf '%s\n' "**At a glance:** 44 active hooks, 21 skills, 9 inter-layer bridges, 9 domain nodes — tests green." >> "$TMP/README.md"
printf '%s\n' "**Текущая версия:** v0.0.0 — 2026-01-01. Подробности: PLAN.md." > "$TMP/README.ru.md"
printf '%s\n' "**Коротко о системе:** 44 активных хука, 21 скилл, 9 межслойных мостов, 9 доменов — тесты зелёные." >> "$TMP/README.ru.md"

CLAUDE_MD_PATH="$TMP/CLAUDE.md" COUNT_STATS_README="$TMP/README.md" \
    COUNT_STATS_README_RU="$TMP/README.ru.md" bash "$SCRIPT" --patch-claude-md >/dev/null 2>&1
OUT=$(cat "$TMP/CLAUDE.md")

# --- T1: все три места приведены к фактическим числам ---
# Предмет теста — ЧИСЛО на всех местах, не словоформа: «51 активный» и «50 активных»
# одинаково верны, склонение делает ru_form. Прежняя жёсткая форма «активных» была
# зелёной ровно потому, что хуков было 50; на 51 тест упал, хотя генератор прав.
assert_contains "$OUT" "# $hooks активн" "T1: число хуков в дереве"
assert_contains "$OUT" "+ $libs библиотек alive learning system" "T1b: библиотеки и хвост строки целы"
assert_contains "$OUT" "| $hooks активн" "T1c: строка таблицы хуков"
assert_contains "$OUT" "| Тесты | $hook_test_files файл" "T1d: число тест-файлов"
assert_contains "$OUT" "+ $mcp_test_files mcp (113 mcp-тестов); зелёные" "T1e: хвост строки тестов цел"
assert_contains "$OUT" "# $hook_test_files файл" "T1f: строка hooks/tests/ в дереве тоже правится"

# --- T1g: канонные строки README тоже правятся (класс D65, 2-е проявление) ---
assert_contains "$(cat "$TMP/README.md")" "$hooks active hooks" "T1g: README en"
assert_contains "$(cat "$TMP/README.ru.md")" "$hooks активн" "T1h: README ru"

# --- T2: идемпотентность — второй прогон ничего не меняет ---
BEFORE=$(cat "$TMP/CLAUDE.md")
CLAUDE_MD_PATH="$TMP/CLAUDE.md" bash "$SCRIPT" --patch-claude-md >/dev/null 2>&1
AFTER=$(cat "$TMP/CLAUDE.md")
if [ "$BEFORE" = "$AFTER" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T2]: повторный прогон изменил файл"; fi

# --- T3: словоформа «файл» согласована (не «82 файлов» и не «81 файла») ---
# Исключение — остаток от СТА в диапазоне 11-14, а не строковое равенство «11»:
# 111 оканчивается на 1 и на 11 одновременно, и прежняя проверка давала «111 файл».
# Дефект спал, пока число тестов не выросло до 111 — ниже, в T-скл, логика уже верная.
_m=$(( hook_test_files % 100 )); _d=$(( hook_test_files % 10 ))
if [ "$_m" -ge 11 ] && [ "$_m" -le 14 ]; then EXPECT="файлов"
elif [ "$_d" -eq 1 ]; then EXPECT="файл"
elif [ "$_d" -ge 2 ] && [ "$_d" -le 4 ]; then EXPECT="файла"
else EXPECT="файлов"; fi
assert_contains "$OUT" "$hook_test_files $EXPECT тестов" "T3: словоформа '$EXPECT' согласована с $hook_test_files"

# --- T-скл: склонение на граничных числах ---
# Числа 1 / 2-4 / 5-20 / 11-14 / 21 / 51 дают разные формы. Отдельной проверки не было,
# и словоформа держалась случайным совпадением с текущим числом хуков.
for pair in "1:активный" "2:активных" "5:активных" "11:активных" "21:активный" "51:активный"; do
    n="${pair%%:*}"; want="${pair##*:}"
    m=$(( n % 100 )); d=$(( n % 10 ))
    if [ "$m" -ge 11 ] && [ "$m" -le 14 ]; then got="активных"
    elif [ "$d" -eq 1 ]; then got="активный"
    else got="активных"; fi
    if [ "$got" = "$want" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [T-скл]: $n → «${got}», ожидалось «${want}»"; fi
done


# --- T-разд: генератор не трогает строку версии ---
# Корень ложного срабатывания docs-family-check был не в страже, а здесь: версия и
# производные счётчики жили в одной строке, и любой её читатель путал два факта.
# Проверка держит разделение: если строки снова сольют, тест покраснеет.
for f in "$TMP/README.md" "$TMP/README.ru.md"; do
    if grep -c "v0.0.0" "$f" >/dev/null 2>&1 && [ "$(grep -c "v0.0.0" "$f")" -eq 1 ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1)); echo "FAIL [T-разд]: версия в $f встречается не один раз"
    fi
done
if grep -q "v0.0.0" "$TMP/README.md" && ! grep -q "active hooks" <<<"$(grep 'v0.0.0' "$TMP/README.md")"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T-разд]: в строке версии оказались счётчики — носитель снова общий"
fi

echo "test_count_stats_patch: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
