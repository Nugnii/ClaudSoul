#!/usr/bin/env bash
# test_compile_reminder.sh — счёт сессий сырья выводится из последней консолидации,
# а не живёт отдельным файлом.
#
# Повод (D40). Было два дефекта, и порознь они не чинятся.
#
# ПЕРВЫЙ: `state_dir` был жёстко прописан как `$HOME/...` мимо `STATE_DIR`, поэтому любой
# тест со своим каталогом состояния всё равно инкрементировал ЖИВОЙ счётчик. Замер на
# момент починки: `compile-pending` = 140 при ПЯТИ настоящих сессиях — завышение в 28 раз.
# Прежняя версия этого теста изолировалась подменой `HOME` — приём работал ровно потому,
# что библиотека брала `$HOME`, то есть тест подстраивался под дефект вместо того, чтобы
# его показать.
#
# ВТОРОЙ: обнулить счётчик мог только человек, вспомнивший чекбокс в `skills/compile/
# SKILL.md`. Ни одна строка кода `compile_reminder_reset` не вызывала, и на прогоне
# 2026-07-28 сброс был пропущен.
#
# Поэтому главный случай здесь — T5: `last_compiled` сдвигается вперёд, и счёт падает
# САМ, без единого вызова сброса.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/compile-reminder-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$1" <<< "$2"; }
assert_has()   { if has "$2" "$1"; then ok; else bad "$3" "нет '$2' в '$1'"; fi; }
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "ожидалась тишина, получено '$1'"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"
CS="$TMP/_compile-state.json"
printf '{"last_compiled": "2026-07-20T12:00:00+02:00"}' > "$CS"

export STATE_DIR="$STATE" COMPILE_STATE_FILE="$CS"
# shellcheck source=/dev/null
source "$LIB"

_n() { ls "$STATE" 2>/dev/null | grep -c '^compile-counted-' || true; }
_unmute() { rm -f "$STATE"/compile-reminded-* 2>/dev/null || true; }
_age() { touch -t "$2" "$STATE/compile-counted-$1"; }   # состарить маркер сессии

# --- T1: первая сессия учтена, нуджа ниже порога нет ---
assert_empty "$(compile_reminder_check "sid-1")" "T1a: нет нуджа ниже порога"
[ "$(_n)" = "1" ] && ok || bad "T1b" "маркер сессии не создан (маркеров: $(_n))"

# --- T2: та же сессия считается один раз (Stop срабатывает многократно) ---
compile_reminder_check "sid-1" >/dev/null
[ "$(_n)" = "1" ] && ok || bad "T2" "повторный вызов той же сессии создал второй маркер"

# --- T3: разные сессии копятся до порога ---
for s in 2 3 4; do compile_reminder_check "sid-$s" >/dev/null; done
OUT=$(compile_reminder_check "sid-5")
assert_has "$OUT" "пора /compile" "T3a: нудж на пороге"
assert_has "$OUT" "5 сессий"      "T3b: нудж называет число"

# --- T4: нудж раз в сессию ---
assert_empty "$(compile_reminder_check "sid-5")" "T4: повторного нуджа в той же сессии нет"

# --- T5: ГЛАВНОЕ — консолидация обнуляет счёт САМА, без вызова сброса ---
# Состарить накопленные маркеры, затем сдвинуть last_compiled ПОЗЖЕ них.
for s in 1 2 3 4 5; do _age "sid-$s" 202607251200; done
printf '{"last_compiled": "2026-07-30T12:00:00+02:00"}' > "$CS"
_unmute
assert_empty "$(compile_reminder_check "sid-6")" \
    "T5: после консолидации счёт упал сам (сброс руками НЕ вызывался)"

# --- T6: накопление начинается заново и снова доходит до порога ---
for s in 7 8 9; do compile_reminder_check "sid-$s" >/dev/null; done
_unmute
assert_has "$(compile_reminder_check "sid-10")" "пора /compile" "T6: счёт копится после консолидации заново"

# --- T7: отрицательный контроль на T5 — вернуть метку в прошлое, счёт обязан ожить ---
# Без него T5 не отличим от «счёт всегда ноль».
printf '{"last_compiled": "2026-01-01T00:00:00+02:00"}' > "$CS"
_unmute
assert_has "$(compile_reminder_check "sid-11")" "пора /compile" \
    "T7 отрицательный контроль: со старой меткой считаются все маркеры"

# --- T8: пустой sid — ничего не делает ---
BEFORE=$(_n)
compile_reminder_check "" ; rc=$?
[ "$rc" -eq 0 ] && ok || bad "T8a" "пустой sid вернул $rc"
[ "$(_n)" = "$BEFORE" ] && ok || bad "T8b" "пустой sid создал маркер"

# --- T9: порог из окружения ---
compile_reminder_reset; _unmute
assert_empty "$(COMPILE_REMINDER_THRESHOLD=2 compile_reminder_check "sid-12a")" "T9a: ниже своего порога 2"
_unmute
assert_has "$(COMPILE_REMINDER_THRESHOLD=2 compile_reminder_check "sid-12b")" "пора /compile" "T9b: нудж на своём пороге 2"

# --- T10: изоляция — библиотека не пишет в живой каталог состояния ---
# Прежний тест доказать это не мог: он подменял HOME, а библиотека брала HOME.
LIVE="$HOME/.claude/hooks/state"
if [ -d "$LIVE" ]; then
    L_BEFORE=$(ls "$LIVE" 2>/dev/null | grep -c '^compile-counted-' || true)
    compile_reminder_check "sid-isolation-probe" >/dev/null
    L_AFTER=$(ls "$LIVE" 2>/dev/null | grep -c '^compile-counted-' || true)
    [ "$L_BEFORE" = "$L_AFTER" ] && ok \
        || bad "T10" "при заданном STATE_DIR библиотека всё равно писала в живой каталог ($L_BEFORE → $L_AFTER)"
else
    ok   # живого каталога нет (чистая машина) — доказывать нечего
fi

# --- T11: отдельного файла-счётчика больше не существует ---
# Он и был источником вранья: жил своей жизнью и обнулялся только вручную.
[ -f "$STATE/compile-pending" ] && bad "T11" "файл-счётчик вернулся — счёт снова может разойтись с реальностью" || ok

# --- T12: старые маркеры убираются по возрасту, а не копятся вечно ---
touch -t 202401010000 "$STATE/compile-counted-ancient"
COMPILE_MARKER_TTL_DAYS=30 compile_reminder_check "sid-13" >/dev/null
[ -f "$STATE/compile-counted-ancient" ] && bad "T12" "маркер старше TTL не убран" || ok

echo ""
echo "Compile reminder tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
