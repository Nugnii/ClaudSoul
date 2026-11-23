#!/usr/bin/env bash
# СУДИТ: scripts/mutation-snapshot.sh
# test_mutation_snapshot.sh — снимок перед мутацией не сталкивается с чужим и не восстанавливает чужое.
#
# Предмет (D344): два агента, снимающие один файл в одной песочнице, не могут перезаписать
# снимок друг друга, а восстановление отказывается от снимка, изменённого после снятия, и
# кладёт содержимое в записанный при снятии путь, а не в файл, названный при откате.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
SNAP="$ROOT/scripts/mutation-snapshot.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export SNAPSHOT_DIR="$TMP/snaps"
mkdir -p "$TMP/work"; F="$TMP/work/guard.sh"; printf 'A\n' > "$F"

# T1: два снятия одного файла — два РАЗНЫХ пути (столкновение невозможно по построению).
S1=$(bash "$SNAP" take "$F"); S2=$(bash "$SNAP" take "$F")
if [ -n "$S1" ] && [ -n "$S2" ] && [ "$S1" != "$S2" ] && [ -f "$S1" ] && [ -f "$S2" ]; then ok
else bad "T1" "снятия дали не два разных пути: «${S1}» / «${S2}»"; fi

# T2: восстановление возвращает содержимое на момент снятия.
printf 'B\n' > "$F"
bash "$SNAP" restore "$S1" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$F")" = "A" ]; then ok
else bad "T2" "восстановление: rc=$rc, содержимое «$(cat "$F")»"; fi

# T3: КОНТРПРИМЕР — снимок, перезаписанный ДРУГИМ агентом, не восстанавливается: отказ,
# файл не тронут. Это и есть сцена 7 сентября 2026 (`guard.orig` с чужим содержимым).
printf 'C\n' > "$F"
printf 'чужое содержимое\n' > "$S2"
err=$(bash "$SNAP" restore "$S2" 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 2 ] && [ "$(cat "$F")" = "C" ] && grep -q 'изменён после снятия' <<< "$err"; then ok
else bad "T3" "чужой снимок восстановлен или отказ не назван: rc=$rc, файл «$(cat "$F")», stderr «${err}»"; fi

# T4: путь восстановления берётся ИЗ ЗАПИСИ, а не из текущего каталога вызова: снимок,
# снятый из одного каталога, восстанавливается из любого другого в тот же файл.
printf 'D\n' > "$F"
( cd "$TMP" && bash "$SNAP" restore "$S1" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$F")" = "A" ]; then ok
else bad "T4" "восстановление из другого каталога: rc=$rc, содержимое «$(cat "$F")»"; fi

# T5: коды `check` различают три состояния: цел (0), изменён (1), записи нет (2).
bash "$SNAP" check "$S1" >/dev/null 2>&1; c0=$?
bash "$SNAP" check "$S2" >/dev/null 2>&1; c1=$?
rm -f "$S1.meta"; bash "$SNAP" check "$S1" >/dev/null 2>&1; c2=$?
if [ "$c0" -eq 0 ] && [ "$c1" -eq 1 ] && [ "$c2" -eq 2 ]; then ok
else bad "T5" "коды check: цел=$c0 (ждали 0), изменён=$c1 (1), без записи=$c2 (2)"; fi

# T6: без записи восстановление отказывает (снимок без .meta — не снимок этого инструмента).
printf 'E\n' > "$F"
bash "$SNAP" restore "$S1" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ] && [ "$(cat "$F")" = "E" ]; then ok
else bad "T6" "снимок без записи восстановлен: rc=$rc, содержимое «$(cat "$F")»"; fi

# T7: снятие несуществующего файла — код 2 и пустой stdout, чтобы `S=$(take …)` не дал пустой
# путь, который потом молча восстановит «ничего».
out=$(bash "$SNAP" take "$TMP/нет-такого" 2>/dev/null); rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then ok
else bad "T7" "снятие несуществующего: rc=$rc, stdout «${out}»"; fi

# T8: hash_file хеширует БАЙТЫ: файлы, различающиеся только завершающим переводом строки,
# дают разные хеши (подстановка `$(cat …)` их бы склеила).
. "$ROOT/hooks/hash-lib.sh"
printf 'x' > "$TMP/h1"; printf 'x\n' > "$TMP/h2"
if [ "$(hash_file "$TMP/h1")" != "$(hash_file "$TMP/h2")" ] && [ "$(hash_file "$TMP/h1")" = "$(hash_file "$TMP/h1")" ]; then ok
else bad "T8" "hash_file не различает файлы, отличные завершающим переводом строки"; fi

echo ""
echo "snapshot: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
