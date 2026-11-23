#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh
# test_backlog_stable_read.sh — читатель бэклога судит цельность копии, а не верит первому чтению (D1065).
# Результат: обрезанное первое чтение повторяется, и ответ считается по целому файлу; файл, не устоявшийся ни за одну
#            пару чтений, — код 2 и сообщение, а не молчаливое «открытых 0»; временные копии не остаются.
# Проверка результата: bash hooks/tests/test_backlog_stable_read.sh даёт 0
#
# Писатель посреди записи здесь подменён подложным `cat` (первые вызовы отдают одну шапку — то, что видит читатель
# после усечения): гонка с настоящим писателем недетерминирована и долга, её мерит проба
# `hooks/tests/fixtures/probe_D1065.sh`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../backlog-lib.sh
. "$ROOT/hooks/backlog-lib.sh" 2>/dev/null || { echo "FAIL: нет $ROOT/hooks/backlog-lib.sh"; exit 1; }
command -v backlog_stable_copy >/dev/null 2>&1 || { echo "FAIL: в библиотеке нет backlog_stable_copy"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система
B="$TMP/B.md"
printf '# BACKLOG\n\n- \342\230\220 **D1** один\n\n- \342\230\220 **D2** два\n\n- \342\230\221 **D3** три\n' > "$B"
mkdir -p "$TMP/bin" "$TMP/tmpd"
# Подложный cat: вызов с номером ≤ CAT_FAIL падает, ≤ CAT_EMPTY отдаёт пусто, ≤ CAT_TORN (либо каждый нечётный при
# CAT_ALT=1) отдаёт только шапку файла.
cat > "$TMP/bin/cat" <<'SH'
#!/bin/sh
c=0; [ -f "$CAT_STATE" ] && c=$(/bin/cat "$CAT_STATE"); c=$((c + 1)); echo "$c" > "$CAT_STATE"
for a; do f=$a; done
[ "$c" -le "${CAT_FAIL:-0}" ] && exit 1
[ "$c" -le "${CAT_EMPTY:-0}" ] && exit 0
if [ "$c" -le "${CAT_TORN:-0}" ] || { [ "${CAT_ALT:-0}" = 1 ] && [ $((c % 2)) = 1 ]; }; then
    /usr/bin/head -1 "$f"; exit 0
fi
exec /bin/cat "$@"
SH
chmod +x "$TMP/bin/cat"
open_n() { backlog_open_items "$B" 2>/dev/null | grep -c .; }

# --- T1: без помех — два открытых, контроль рамки ---
[ "$(open_n)" = 2 ] && ok || bad T1 "открытых $(open_n), ожидалось 2 — рамка мертва"

# --- T2: первое чтение обрезано — повтор, ответ по целому файлу ---
rm -f "$TMP/st"
N2=$(PATH="$TMP/bin:$PATH" CAT_STATE="$TMP/st" CAT_TORN=1 TMPDIR="$TMP/tmpd" open_n)
[ "$N2" = 2 ] && ok || bad T2 "обрезанное первое чтение принято: открытых $N2, ожидалось 2"
[ "$(/bin/cat "$TMP/st" 2>/dev/null)" -ge 3 ] 2>/dev/null && ok \
    || bad T2b "повтора не было: вызовов cat $(/bin/cat "$TMP/st" 2>/dev/null) — подлог не сработал"

# --- T3: файл не устоялся ни за одну пару — код 2 и сообщение, а не «открытых 0» ---
rm -f "$TMP/st"
ERR=$( { PATH="$TMP/bin:$PATH" CAT_STATE="$TMP/st" CAT_ALT=1 TMPDIR="$TMP/tmpd" backlog_open_items "$B" > "$TMP/out3"; echo "rc=$?"; } 2>&1)
case "$ERR" in *"не устоялся"*"rc=2"*) ok ;; *) bad T3 "неустоявшийся файл не назван: $ERR" ;; esac
[ ! -s "$TMP/out3" ] && ok || bad T3b "из неустоявшегося файла выданы строки: $(head -2 "$TMP/out3")"
rm -f "$TMP/st"
PATH="$TMP/bin:$PATH" CAT_STATE="$TMP/st" CAT_ALT=1 TMPDIR="$TMP/tmpd" backlog_ids "$B" >/dev/null 2>&1; RC4=$?
[ "$RC4" = 2 ] && ok || bad T3c "backlog_ids на неустоявшемся файле: код $RC4, ожидался 2"

# --- T5-T7 (D1100): отказ копии — не «файл пишут»; пустая пара чтений до записи не принимается ---
# T5: TMPDIR не существует — копии нет, читается сам файл, как до D1065 (прежде: код 2 без сообщения, «0»).
N5=$(TMPDIR="$TMP/нет-такого" open_n); R5=$(TMPDIR="$TMP/нет-такого" bash -c ". '$ROOT/hooks/backlog-lib.sh'; backlog_open_items '$B' >/dev/null 2>&1; echo \$?")
{ [ "$N5" = 2 ] && [ "$R5" = 0 ]; } && ok || bad T5 "без TMPDIR: открытых $N5 (ждали 2), код $R5 (ждали 0)"
# T6: копия не пишется (первый cat падает) — сам файл, сразу, без 20 пар и без «не устоялся».
rm -f "$TMP/st"
E6=$( { PATH="$TMP/bin:$PATH" CAT_STATE="$TMP/st" CAT_FAIL=1 TMPDIR="$TMP/tmpd" backlog_open_items "$B" | grep -c .; } 2>&1)
case "$E6" in 2) ok ;; *) bad T6 "копия не пишется: «${E6}» (ждали 2 открытых без сообщения)" ;; esac
[ "$(/bin/cat "$TMP/st" 2>/dev/null)" = 1 ] && ok || bad T6b "после отказа копии были повторы: вызовов cat $(/bin/cat "$TMP/st")"
# T7: оба чтения пусты (окно усечения), затем файл записан — пустая копия не принята.
rm -f "$TMP/st"
N7=$(PATH="$TMP/bin:$PATH" CAT_STATE="$TMP/st" CAT_EMPTY=2 TMPDIR="$TMP/tmpd" open_n)
[ "$N7" = 2 ] && ok || bad T7 "пустая пара чтений принята: открытых $N7, ожидалось 2"

# --- T4: временные копии не остаются ---
[ -z "$(ls -A "$TMP/tmpd")" ] && ok || bad T4 "остались временные копии: $(ls "$TMP/tmpd" | head -3)"

echo "backlog stable read: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
