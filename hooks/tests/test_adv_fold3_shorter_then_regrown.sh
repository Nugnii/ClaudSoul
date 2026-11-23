#!/usr/bin/env bash
# СУДИТ: hooks/lib/transcript_window.py hooks/hook-input-lib.sh
# test_adv_fold3_shorter_then_regrown.sh — противник свёртки, раунд 3 (D498): файл, переписанный на месте КОРОЧЕ, отвергается только в момент вызова — запись «только вперёд» не даёт заменить устаревшее состояние, и когда файл дорастает до прежней точки, свёртка снова берёт накопленное по прежнему содержимому.
#
# Обещание (transcript_window.py, turn_offset/fold; коммит 680446a4): «Файл, переписанный короче
# точки, и после догона короче — он отвергается, как прежде». Названный предел модуля касается
# файла «переписанного на месте тем же inode и НЕ КОРОЧЕ прежнего». Здесь файл короче: вызов
# это видит и сворачивает с нуля верно, но put() пишет только вперёд (`h[1] >= end` → не
# писать), и прежнее состояние — с концом дальше нынешнего файла — остаётся. Дописанное до
# прежней точки делает его снова «годным»: накопленное по прежнему содержимому плюс хвост.
# То же правило у метки начала хода (`_write_mark`, `cur[1] >= end`).
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
F="$T/t.jsonl"; ST="$T/st"; mkdir -p "$ST"
case "$F|$ST|$TMPDIR" in "$T"/*"|$T"/*"|$T"/*) ;; *) echo "FAIL [K0]: путь записи вне каталога теста"; exit 1 ;; esac

CNT='reduce inputs as $r (($a[0] // 0); . + (if $r.x then 1 else 0 end))'
fold() { STATE_DIR="$1" bash -c '. "$1/hook-input-lib.sh"; transcript_fold "$2" cnt session jq -cn "$3" --slurpfile a' _ "$HOOKS" "$F" "$CNT"; }
X12='{"x":false}
'
ino() { python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$F"; }

# Прежнее содержимое: пять записей с x — свёртка накопила 5.
# Длины строк выбраны так, что прежняя точка (5 × 24 = 120 байт) ложится на границу строки
# нового содержимого (строки по 12 байт): иначе дельта начиналась бы с обрывка строки, шаг падал
# бы на разборе и запасной путь давал верный ответ — ценой полного прохода на КАЖДОМ вызове.
for _ in 1 2 3 4 5; do printf '%s\n' '{"x":true,"p":"aaaaaa"}'; done > "$F"
I0=$(ino)
V0=$(fold "$ST")
[ "$V0" = 5 ] && ok || bad K1 "прогрев дал «${V0}», ожидалось 5"
E0=$(head -1 "$ST"/transcript-fold-cnt-* 2>/dev/null | awk '{print $2}')   # прежняя точка свёртки

# Файл переписан на месте тем же inode и КОРОЧЕ: две записи без x.
: > "$F"; printf '%s\n' '{"x":false}' '{"x":false}' >> "$F"
[ "$(ino)" = "$I0" ] && ok || bad K2 "inode сменился — тест не о том"
V1=$(fold "$ST")
[ "$V1" = 0 ] && ok || bad K3 "вызов на коротком файле дал «${V1}», ожидалось 0 (отвергнуть прежнее состояние)"

# Файл дописан (только вперёд) дальше прежней точки — записи без x.
while [ "$(wc -c < "$F")" -le 300 ]; do printf '%s\n' '{"x":false}' >> "$F"; done
[ "${#X12}" = 12 ] && [ -n "$E0" ] && [ "$E0" -gt 0 ] 2>/dev/null && [ $(( E0 % ${#X12} )) -eq 0 ] && ok \
    || bad K5 "прежняя точка ${E0:-?} не на границе строки нового содержимого — тест не о том"
V2=$(fold "$ST")
COLD=$(fold "$(mktemp -d "$T/cold.XXXX")")
[ "$COLD" = 0 ] && ok || bad K4 "холодная свёртка дала «${COLD}», ожидалось 0"
# Предмет: тёплая свёртка равна холодной — прежнее содержимое, отвергнутое на коротком файле,
# не возвращается, когда файл дорастает.
[ "$V2" = "$COLD" ] && ok \
    || bad S1 "после дописывания свёртка дала «${V2}» вместо «${COLD}»: состояние прежнего содержимого (отвергнутое на коротком файле) снова принято"

# Брат того же правила — метка начала хода (`_write_mark`, `cur[1] >= end`): окно хода после
# короткой перезаписи и дорастания начинается с начала хода ПРЕЖНЕГО содержимого.
G="$T/g.jsonl"; SG="$T/sg"; mkdir -p "$SG"
case "$G|$SG" in "$T"/*"|$T"/*) ;; *) echo "FAIL [K0]: путь записи вне каталога теста"; exit 1 ;; esac
u() { printf '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
a() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
win() { STATE_DIR="$1" bash -c '. "$1/hook-input-lib.sh"; transcript_turn_window "$2"' _ "$HOOKS" "$G"; }
{ a "aaaaaaaaaa"; a "bbbbbbbbbb"; u "прежняя реплика"; a "cccccccccc"; } > "$G"
win "$SG" >/dev/null                                    # метка: начало хода — прежняя реплика
: > "$G"; u "новая реплика" >> "$G"                     # тот же inode, короче
win "$SG" >/dev/null                                    # вызов видит короткий файл
while [ "$(wc -c < "$G")" -le 600 ]; do a "dddddddddd" >> "$G"; done
WW=$(win "$SG" | cksum); WC=$(win "$(mktemp -d "$T/coldw.XXXX")" | cksum)
[ "$WW" = "$WC" ] && ok \
    || bad S2 "окно хода после короткой перезаписи и дорастания отличается от холодного: метка прежнего содержимого снова принята"

echo "test_adv_fold3_shorter_then_regrown: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
