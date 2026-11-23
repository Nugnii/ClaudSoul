#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# test_rc_snapshot_compressed.sh — D1314: снимок стража разбора лежит сжатым, а сверка по нему та же.
#
# Что доказывается (нога на каждое условие):
#   · писатель кладёт `.snap-<cksum>.blob.gz`, несжатого `.blob` нет, текст восстанавливается побайтно, файл меньше
#     текста; cksum — от несжатого текста, повтор того же текста второго файла не кладёт;
#   · прежний `.blob` того же текста засчитывается снимком — писатель рядом `.gz` не кладёт;
#   · читатель бэклога: пункт не менялся — 1, изменился — 0, пункта в снимке не было — 0; то же на прежней форме `.blob`;
#     снимка нет — 2, сжатый снимок испорчен — 2 (а не «пункта не было»);
#   · читатель архива: номер был в архиве на момент повода — 4, не был — 0;
#   · читатель базы знаний: имя, которого не было в снимке, — новая запись (0); бывшее — отказ с причиной.
# Повод: до D1314 полные копии бэклога (~100 КБ) клались без сжатия — 173 МБ из 200 в каталоге состояния; читатель
# снимка знаний до этого свидетеля не судился ни одной ногой.

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/root-cause-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
command -v gzip >/dev/null 2>&1 || { echo "SKIP: нет gzip"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_eq() { if [ "$1" = "$2" ]; then ok; else bad "$3" "ожидалось «$2», получено «$1»"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP" LESSONS_DIR="$TMP/lessons"
mkdir -p "$TMP/st" "$TMP/proj" "$LESSONS_DIR"
# shellcheck source=/dev/null
. "$LIB" || { echo "FAIL: библиотека не подключилась"; exit 1; }
_rc_need_backlog_lib || { echo "FAIL: нет backlog-lib.sh"; exit 1; }

P="$TMP/proj"; B="$TMP/st/five-whys-s1"; PC="$(cd "$P" && pwd -P)/BACKLOG.md"
item() { printf '%s\n' "- ☐ **$1** $2" "  **Корень.** R5 — пример." "  **Проверка.** \`true\` → 0" ''; }
{ echo '# BACKLOG'; echo; for i in $(seq 9100 9160); do item "D$i" "пункт номер $i о том же самом"; done; item D9001 "предмет сверки"; } > "$P/BACKLOG.md"

# ── 1. Писатель ───────────────────────────────────────────────────────────────
C=$(_rc_snap_put "$B" < "$P/BACKLOG.md")
assert_eq "$C" "$(cksum < "$P/BACKLOG.md" | awk '{print $1}')" "W1 id — cksum несжатого текста"
[ -f "$B.snap-$C.blob.gz" ] && ok || bad W2 "сжатого снимка нет"
[ ! -e "$B.snap-$C.blob" ] && ok || bad W3 "лёг несжатый .blob"
gzip -dc "$B.snap-$C.blob.gz" 2>/dev/null | cmp -s - "$P/BACKLOG.md" && ok || bad W4 "текст не восстановился побайтно"
[ "$(wc -c < "$B.snap-$C.blob.gz")" -lt "$(wc -c < "$P/BACKLOG.md")" ] && ok || bad W5 "сжатый снимок не меньше текста"
C2=$(_rc_snap_put "$B" < "$P/BACKLOG.md")
assert_eq "$C2:$(ls "$TMP/st" | grep -c '\.snap-')" "$C:1" "W6 тот же текст — тот же снимок, второго файла нет"
# Сбой gzip (скептик D1314, M2): под окончательным именем ничего не ложится, id не отдаётся, временного хвоста нет —
# иначе читатель навсегда получал бы «снимка нет», а писатель уже не перезаписал бы мусор.
mkdir -p "$TMP/fakebin"; printf '%s\n' '#!/bin/sh' 'printf "обрыв"' 'exit 1' > "$TMP/fakebin/gzip"; chmod +x "$TMP/fakebin/gzip"
printf 'текст для сбоя gzip\n' > "$TMP/fail.txt"; CF=$(cksum < "$TMP/fail.txt" | awk '{print $1}')
ID=$(PATH="$TMP/fakebin:$PATH" _rc_snap_put "$B" < "$TMP/fail.txt")
assert_eq "$ID:$(ls "$TMP/st" | grep -c "snap-$CF")" ":0" "W9 сбой gzip — нет ни id, ни файла, ни временного хвоста"
# Обрыв записи во временный файл писателя (скептик D1314, M3): снимка нет, а не снимок усечённого текста.
ID=$( trap '' XFSZ; ulimit -f 1; _rc_snap_put "$B" < "$P/BACKLOG.md" 2>/dev/null )
assert_eq "$ID" "" "W10 обрыв записи — id не отдан"
printf 'старый текст\n' > "$TMP/old.txt"; CO=$(cksum < "$TMP/old.txt" | awk '{print $1}')
cp "$TMP/old.txt" "$B.snap-$CO.blob"
assert_eq "$(_rc_snap_put "$B" < "$TMP/old.txt")" "$CO" "W7 прежний .blob засчитан снимком"
[ ! -e "$B.snap-$CO.blob.gz" ] && ok || bad W8 "рядом с прежним .blob лёг .gz того же текста"

# Сверка строки — три исхода: есть, нет, не сверить (скептик D1314, M1: «не сверить» не должно читаться как «нет»).
assert_eq "$(_rc_has_line $'case-a\ncase-b' case-b; echo $?)" 0 "H1 строка есть"
assert_eq "$(_rc_has_line $'case-a\ncase-b' case-c; echo $?)" 1 "H2 строки нет"
mkdir -p "$TMP/fakeawk"; printf '%s\n' '#!/bin/sh' 'exit 3' > "$TMP/fakeawk/awk"; chmod +x "$TMP/fakeawk/awk"
assert_eq "$(PATH="$TMP/fakeawk:$PATH" _rc_has_line case-a case-a; echo $?)" 2 "H3 сверка не запустилась — 2, а не «нет»"
# D1319: текст больше 128 КБ (предел одной строки окружения у Linux) сверяется; ответ awk — слово, а не код.
BIG=$(seq -f "pattern-%07g-knowledge-record-name" 1 4500)
assert_eq "$(_rc_has_line "$BIG" pattern-0004499-knowledge-record-name; echo $?)" 0 "H4 строка есть в тексте 180 КБ"
assert_eq "$(_rc_has_line "$BIG" pattern-0004500-knowledge-record-name; echo $?)" 0 "H5 последняя строка текста сверяется"
assert_eq "$(_rc_has_line "$BIG" pattern-0004501-knowledge-record-name; echo $?)" 1 "H6 строки нет в тексте 180 КБ"
assert_eq "$(_rc_has_line "$BIG" pattern-0004500; echo $?)" 1 "H7 часть строки — не строка"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$TMP/fakeawk/awk"
assert_eq "$(PATH="$TMP/fakeawk:$PATH" _rc_has_line case-a case-a; echo $?)" 2 "H8 awk ответил 0 без слова — 2, а не «есть»"

# ── 2. Читатель бэклога ───────────────────────────────────────────────────────
echo "snapbl|S1|$PC|$C|" >> "$B.seen"
NOW=$(backlog_item_block "$P/BACKLOG.md" D9001 | tail -n +2)
fresh() { _rc_block_fresh_snap "$P/BACKLOG.md" "$1" "$2" "$B" "$3"; echo $?; }
assert_eq "$(fresh D9001 "$NOW" S1)" 1 "R1 пункт не менялся — прежний"
assert_eq "$(fresh D9001 "$NOW"$'\n''  **Проявление.** `x.sh:1` — ещё.' S1)" 0 "R2 пункт изменился — свежий"
assert_eq "$(fresh D9002 '  новый' S1)" 0 "R3 пункта в снимке не было — свежий"
# Прежняя форма: тот же снимок несжатым `.blob`.
gzip -dc "$B.snap-$C.blob.gz" > "$B.snap-$C.blob" && rm -f "$B.snap-$C.blob.gz"
assert_eq "$(fresh D9001 "$NOW" S1)" 1 "R4 прежний .blob — пункт не менялся"
assert_eq "$(fresh D9001 "$NOW"$'\n''  ещё' S1)" 0 "R5 прежний .blob — пункт изменился"
rm -f "$B.snap-$C.blob"
assert_eq "$(fresh D9001 "$NOW" S1)" 2 "R6 снимка нет — 2"
printf 'не gzip' > "$B.snap-$C.blob.gz"
assert_eq "$(fresh D9001 "$NOW" S1)" 2 "R7 испорченный снимок — 2, а не «пункта не было»"
rm -f "$B.snap-$C.blob.gz"

# ── 3. Читатель архива ────────────────────────────────────────────────────────
CE=$(printf '# BACKLOG\n' | _rc_snap_put "$B")
CA=$(printf '%s\n' D9005 D9006 | _rc_snap_put "$B")
printf '%s\n' "snapbl|S2|$PC|$CE|" "snaparch|S2|$PC|$CA|" >> "$B.seen"
assert_eq "$(_rc_block_fresh_snap "$TMP/proj/BACKLOG-archive.md" D9005 '' "$B" S2; echo $?)" 4 "A1 номер был в архиве — 4"
assert_eq "$(_rc_block_fresh_snap "$TMP/proj/BACKLOG-archive.md" D9007 '' "$B" S2; echo $?)" 0 "A2 номера в архиве не было — 0"
# Временный файл не пишется (bash 3.2 кладёт here-string во временный файл; скептик D1314, M1): сверка не «нет», а отказ.
# Бэклога на момент повода не было (`absent`) — сверка блока временного файла не берёт и доходит до читателя архива.
printf '%s\n' "snapbl|S6|$PC|absent|" "snaparch|S6|$PC|$CA|" >> "$B.seen"
assert_eq "$( trap '' XFSZ; ulimit -f 0; _rc_block_fresh_snap "$TMP/proj/BACKLOG-archive.md" D9005 '' "$B" S6; echo $? )" 4 "A3 запись запрещена — номер из архива всё равно 4"
# Снимок архива записан в журнал, а файла нет (скептик D1314, M2): пункт из архива — по-прежнему 4, а не «свежий».
printf '%s\n' "snapbl|S4|$PC|$CE|" "snaparch|S4|$PC|1|" >> "$B.seen"
assert_eq "$(_rc_block_fresh_snap "$TMP/proj/BACKLOG-archive.md" D9005 '' "$B" S4; echo $?)" 4 "A4 снимка архива нет — 4, а не свежий"

# ── 4. Читатель базы знаний ───────────────────────────────────────────────────
: > "$LESSONS_DIR/case-old-one.md"; : > "$LESSONS_DIR/case-new-one.md"
CK=$(printf '%s\n' case-old-one | _rc_snap_put "$B")
echo "snaples|S3|$CK|" >> "$B.seen"
CTX="x|y|$P||discovery:z@100@S3|$B"
OUT=$(cd "$P" && rc_record_verdict knowledge discovery "case-new-one" "$CTX"); RC=$?
assert_eq "$RC" 0 "K1 имени не было в снимке — новая запись ($OUT)"
OUT=$(cd "$P" && rc_record_verdict knowledge discovery "case-old-one" "$CTX"); RC=$?
assert_eq "$RC" 1 "K2 имя было в снимке — отказ"
grep -q 'было в базе до того' <<< "$OUT" && ok || bad K3 "причина отказа не названа: $OUT"
# Временный файл не пишется (скептик D1314, M1): бывшее имя не принимается за новое.
OUT=$( trap '' XFSZ; ulimit -f 0; cd "$P" && rc_record_verdict knowledge discovery "case-old-one" "$CTX" 2>&1 ); RC=$?
assert_eq "$RC" 1 "K4 запись запрещена — бывшее имя по-прежнему отказ ($OUT)"
# Снимок знаний записан в журнал, а файла нет (скептик D1314, M2): отказ, а не «новая запись».
echo "snaples|S5|1|" >> "$B.seen"
OUT=$(cd "$P" && rc_record_verdict knowledge discovery "case-new-one" "x|y|$P||discovery:z@100@S5|$B"); RC=$?
assert_eq "$RC" 1 "K5 снимка знаний нет — отказ"
grep -q 'снимка базы знаний на момент повода нет' <<< "$OUT" && ok || bad K6 "причина «снимка нет» не названа: $OUT"

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: $PASS"
    exit 0
fi
echo "FAIL: $FAIL (PASS: $PASS)"
exit 1
