#!/usr/bin/env bash
# test_derived_counts_inventory.sh — инвентарь производных чисел в документах
# состояния: поверхности находятся ПЕРЕЧИСЛЕНИЕМ, а не ожогами стражей.
#
# Корень (2026-08-08): счётные фразы всплывали по одной — 4-е место в CLAUDE.md,
# потом канонные строки README — каждый раз постфактум, срабатыванием стража.
# Этот тест греп-ит все документы состояния по всем счётным фразам и сверяет
# каждое найденное число с count-stats. Новая поверхность с фразой из списка
# попадает под сверку автоматически; новая ФРАЗА добавляется в PATTERNS здесь.
#
# Хроники (CHANGELOG, SESSION, BACKLOG*, архивы) сознательно вне охвата:
# исторические числа там легитимны.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

eval "$(bash "$ROOT/scripts/count-stats.sh" 2>/dev/null | grep -E '^(hooks|libs|skills|hook_test_files)=')"

# Фраза → эталон. Формат: "ERE-паттерн|имя эталона".
PATTERNS=(
    '[0-9]+ active hooks|hooks'
    '[0-9]+ активн(ый|ых) хук(а|ов)?|hooks'
    '[0-9]+ библиотек|libs'
    '[0-9]+ файл(а|ов)? тестов хуков|hook_test_files'
    '[0-9]+ skills|skills'
    '[0-9]+ скилл(а|ов)?|skills'
)

STATE_DOCS=("$ROOT/README.md" "$ROOT/README.ru.md" "$ROOT/CLAUDE.md")
while IFS= read -r f; do STATE_DOCS+=("$f"); done < <(ls "$ROOT/.claude-docs/modules/"*.md 2>/dev/null)

scan() { # file → 0 чисто, 1 расхождения (печатает их)
    local file="$1" dirty=0 entry re key truth m num
    for entry in "${PATTERNS[@]}"; do
        re="${entry%|*}"; key="${entry##*|}"
        truth=$(eval "printf '%s' \"\$$key\"")
        while IFS= read -r m; do
            [ -n "$m" ] || continue
            num=$(printf '%s' "$m" | grep -oE '^[0-9]+')
            if [ "$num" != "$truth" ]; then
                echo "  $file: «${m}» ≠ ${key}=${truth}"
                dirty=1
            fi
        done < <(grep -hoE "$re" "$file" 2>/dev/null)
    done
    return "$dirty"
}

# --- T1: все документы состояния согласованы с count-stats ---
DIRTY=""
for f in "${STATE_DOCS[@]}"; do
    [ -f "$f" ] || continue
    OUT=$(scan "$f") || DIRTY="$DIRTY$OUT"$'\n'
done
if [ -z "$DIRTY" ]; then ok
else bad "T1: дрейф производных чисел" $'\n'"$DIRTY  (правь генератором: scripts/count-stats.sh --patch-claude-md)"; fi

# --- T2: сам сканер ловит враньё (негативный контроль — детектор не завязан
#         только на успех) ---
FIX=$(mktemp)
echo "здесь 9999 активных хуков и 21 скилл" > "$FIX"
if scan "$FIX" >/dev/null; then bad "T2" "фикстура с 9999 прошла как чистая"
else ok; fi
rm -f "$FIX"

echo "test_derived_counts_inventory: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
