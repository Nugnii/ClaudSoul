#!/usr/bin/env bash
# test_backlog_vanish.sh — характеризующий тест стража исчезающих пунктов долга.
# Повод: дважды за час 2026-08-26 правка одного пункта заменой ДИАПАЗОНА уносила
# соседние (D83/D85/D86, затем снова D83/D86). Тест держит три случая: пропажа
# ловится, закрытие с переездом в архив законно, обычный коммит молчит.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/backlog-vanish-check.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }

PASS=0; FAIL=0
assert_contains() {
    if grep -q -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $1"; fi
}
assert_empty() {
    if [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина, получено: $1"; fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q . 2>/dev/null; git config user.email t@t; git config user.name t
{
  printf -- '- ☐ **D10** первый\n'
  printf -- '- ☐ **D11** второй\n'
  printf -- '- ☐ **D12** третий\n'
} > BACKLOG.md
printf 'архив\n' > BACKLOG-archive.md
git add -A && git commit -qm base

run() { printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | bash "$HOOK" 2>/dev/null; }

# 1. Пункт исчез бесследно — страж называет его.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
OUT=$(run)
assert_contains "$OUT" "D11" "исчезнувший пункт назван поимённо"
assert_contains "$OUT" "не найдены в архиве" "объяснено, что это не закрытие"

# 2. Пункт закрыт и уехал в архив — законно, тишина.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf -- 'архив\n- ☑ **D11** второй\n' > BACKLOG-archive.md
OUT=$(run)
assert_empty "$OUT" "переезд в архив нарушением не считается"

# 3. Пункт остался, но помечен закрытым в самом файле — тишина.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☑ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf 'архив\n' > BACKLOG-archive.md
OUT=$(run)
assert_empty "$OUT" "закрытый на месте пункт нарушением не считается"

# 4. Ничего не менялось — тишина (иначе страж станет фоном).
git checkout -q -- BACKLOG.md 2>/dev/null || true
OUT=$(run)
assert_empty "$OUT" "без изменений молчит"

# 5. Не git commit — не наше дело.
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "чужая команда игнорируется"

# --- Дубликат номера: один D у двух пунктов ---
# Повод 2026-08-26: две сессии работали параллельно, обе взяли следующий свободный номер,
# и D89 достался сразу пункту про fragile (закрыт, уехал в архив) и пункту про вставку
# чужого текста (открыт). Номер — единственный способ сослаться на пункт из CHANGELOG,
# коммита и соседнего пункта.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf -- 'архив\n- ☑ **D11** другой пункт с тем же номером\n' > BACKLOG-archive.md
OUT=$(run)
assert_contains "$OUT" "Один номер у двух пунктов" "дубликат номера назван"
assert_contains "$OUT" "D11" "дубликат назван поимённо"

# Открытая копия пункта в архиве — не коллизия, а след переноса летописи.
# Живой случай: при архивации туда уехали заголовки D59/D20/D23/D50 со статусом ☐, при
# том что сами пункты либо закрыты отдельной записью, либо продолжают жить в рабочем
# файле. Первая версия проверки объявила открытый D20 продублированным «архивным» —
# страж поймал сам себя на первом же коммите после появления.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf -- 'архив\n- ☐ **D11** старая открытая копия того же пункта\n' > BACKLOG-archive.md
OUT=$(run)
assert_empty "$OUT" "открытая копия в архиве коллизией не считается"

# Тот же набор без дубликата — тишина.
printf -- 'архив\n- ☑ **D09** закрытый\n' > BACKLOG-archive.md
OUT=$(run)
assert_empty "$OUT" "без дубликатов молчит"


# ── Объявлено закрытым в сообщении, а метка осталась открытой ─────────────────
# Повод измерен на себе 2026-08-27. Коммит 6b127b7 в сообщении: «D97 закрыт удалением
# дубля»; работа сделана в том же коммите (таблица мостов удалена из architecture.md);
# строка `- ☐ **D97**` не тронута. Итог: счёт открытого показывал 9 вместо 8, а
# backlog-recheck.sh — он перепроверяет ЗАКРЫТОЕ — единственный реально закрытый пункт
# не проверял вовсе.
run_msg() {
    jq -cn --arg c "git commit -m \"$1\"" \
        '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null
}

{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf 'архив\n' > BACKLOG-archive.md

OUT=$(run_msg 'chore(backlog): D11 закрыт удалением дубля')
assert_contains "$OUT" "D11" "заявленный закрытым пункт с меткой ☐ назван"
assert_contains "$OUT" "объявлен закрытым" "объяснено расхождение носителей"

# Обратный порядок слов ловится тоже.
OUT=$(run_msg 'chore: закрыт пункт D11')
assert_contains "$OUT" "D11" "порядок «закрыт D11» ловится"

# Метка переведена — тишина.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☑ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
OUT=$(run_msg 'chore(backlog): D11 закрыт удалением дубля')
assert_empty "$OUT" "переведённая метка нарушением не считается"

# Упоминание без объявления о закрытии — не повод. Иначе «D90 переписан» в одном
# сообщении с «D97 закрыт» поднимал бы тревогу по обоим.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
OUT=$(run_msg 'chore(backlog): D12 закрыт, D11 переписан')
assert_contains "$OUT" "D12" "закрытый назван"
if grep -q 'D11' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [упомянутый без «закрыт» не назван]: D11 попал в вывод: $OUT"
else PASS=$((PASS+1)); fi

# Пункт уже уехал в архив закрытым — в рабочем файле его нет, тревоги нет.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf -- 'архив\n- ☑ **D11** второй\n' > BACKLOG-archive.md
OUT=$(run_msg 'chore(backlog): D11 закрыт')
assert_empty "$OUT" "закрытый и уехавший в архив пункт тревоги не даёт"

# Команда, которая САМА закрывает пункт перед коммитом, тревоги не вызывает.
# Поймано на себе 28 августа 2026: закрытие пункта и коммит идут одной командой, а
# PreToolUse срабатывает ДО её начала — на момент проверки метка ещё «☐», хотя через
# секунду станет «☑». При обычном порядке работы страж кричал бы всегда.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; } > BACKLOG.md
printf 'архив\n' > BACKLOG-archive.md
OUT=$(jq -cn '{tool_name:"Bash", tool_input:{command:"python3 - <<PY\n# правит BACKLOG.md\nPY\ngit add -A && git commit -m \"chore: D11 закрыт\""}}' | bash "$HOOK" 2>/dev/null)
if grep -q 'объявлен закрытым' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [своя правка в той же команде]: тревога на команде, которая сама закрывает пункт: $OUT"
else PASS=$((PASS+1)); fi

# А коммит БЕЗ правки долга в той же команде — тревога остаётся.
OUT=$(jq -cn '{tool_name:"Bash", tool_input:{command:"git commit -m \"chore: D11 закрыт\""}}' | bash "$HOOK" 2>/dev/null)
if grep -q 'объявлен закрытым' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [чистый коммит]: тревога пропала там, где правки нет: $OUT"; fi

echo ""
echo "backlog-vanish tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
