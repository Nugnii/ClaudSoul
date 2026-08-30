#!/usr/bin/env bash
# test_partial_read_guard.sh — маркер о неполном чтении обязан появляться там, где
# неполнота НЕВИДИМА, и молчать там, где сказать нечего.
#
# Главный случай здесь — не явный `limit`, а его отсутствие: инструмент Read без
# параметров молча обрезает файл на 2000 строк и возвращает результат, ничем не
# отличимый от полного. Явное частичное чтение модель хотя бы заказывала сама;
# обрезку по умолчанию она не заказывала и не видит. Если тест проверит только случай
# с limit, он будет зелёным ровно на той половине, где проблемы нет.
#
# Вторая половина проверки — тишина. Хук на каждом чтении большого файла превратился бы
# в фон, а фон не читают. Поэтому повтор того же файла в той же сессии обязан молчать,
# и это проверяется наравне с срабатыванием.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/partial-read-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: не найден $HOOK"; exit 1; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"

ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
# Имя по конвенции проекта: по нему проверки тишины находит test_guards_provable.sh.
assert_silent() {
    if [ -z "$1" ]; then ok "$2"; else bad "$2 — ожидалась тишина, получено: $1"; fi
}

call() {  # call <sid> <file> [offset] [limit]
    local sid="$1" f="$2" off="${3:-0}" lim="${4:-0}"
    local ti="{\"file_path\":\"$f\""
    [ "$off" -gt 0 ] && ti="$ti,\"offset\":$off"
    [ "$lim" -gt 0 ] && ti="$ti,\"limit\":$lim"
    ti="$ti}"
    printf '{"session_id":"%s","tool_name":"Read","tool_input":%s}' "$sid" "$ti" | bash "$HOOK" 2>/dev/null
}

SMALL="$TMP/small.txt"; printf 'a %s\n' $(seq 1 50)   > "$SMALL"
BIG="$TMP/big.txt";     printf 'b %s\n' $(seq 1 900)  > "$BIG"
HUGE="$TMP/huge.txt";   printf 'c %s\n' $(seq 1 3000) > "$HUGE"

# --- 1. Главный случай: обрезка по умолчанию, параметров не задавали.
out=$(call s1 "$HUGE")
if grep -q "2000 из 3000" <<<"$out"; then
    ok "молчаливая обрезка на 2000 строк названа числом"
else
    bad "обрезка по умолчанию не поймана"; printf '%s\n' "$out" | head -3
fi
grep -q "ОТСУТСТВИИ" <<<"$out" \
    && ok "сказано, какой именно вывод делать нельзя" \
    || bad "маркер есть, запрета на вывод об отсутствии нет"

# --- 2. Явное частичное чтение.
out=$(call s2 "$BIG" 1 40)
grep -q "40 из 900" <<<"$out" && ok "явный limit посчитан верно" \
                              || bad "явный limit посчитан неверно: $out"
grep -q "860" <<<"$out" && ok "непрочитанный остаток назван числом" \
                        || bad "остаток не назван"

# --- 3. Файл прочитан целиком — говорить нечего.
out=$(call s3 "$SMALL")
assert_silent "$out" "маленький файл целиком → тишина"
out=$(call s4 "$BIG" 1 900)
assert_silent "$out" "явный limit, покрывающий весь файл → тишина"

# --- 4. Повтор в той же сессии молчит, другая сессия — говорит.
out=$(call s5 "$BIG" 1 40); [ -n "$out" ] || bad "первое чтение в сессии промолчало"
out=$(call s5 "$BIG" 300 40)
assert_silent "$out" "повтор того же файла в сессии → тишина (не фон)"
out=$(call s6 "$BIG" 1 40)
[ -n "$out" ] && ok "в другой сессии маркер снова появляется" \
              || bad "тишина протекла в соседнюю сессию"

# --- 5. Чужие инструменты и нестрочные файлы.
out=$(printf '{"session_id":"s7","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$HUGE" | bash "$HOOK" 2>/dev/null)
assert_silent "$out" "не-Read инструмент игнорируется"
IMG="$TMP/pic.PNG"; printf 'x\n' > "$IMG"
out=$(call s8 "$IMG" 1 1)
assert_silent "$out" "картинка не меряется строками (и .PNG в верхнем регистре тоже)"
out=$(call s9 "$TMP/нет-такого.txt" 1 10)
assert_silent "$out" "несуществующий файл — молча"

# --- 6. Последняя строка без перевода строки — тоже строка.
NL="$TMP/nonl.txt"; printf 'd %s\n' $(seq 1 2999) > "$NL"; printf 'd 3000' >> "$NL"
out=$(call s10 "$NL")
grep -q "из 3000" <<<"$out" && ok "хвост без перевода строки сосчитан" \
                            || bad "потеряна последняя строка: $out"

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
