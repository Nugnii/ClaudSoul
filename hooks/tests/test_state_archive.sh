#!/usr/bin/env bash
# test_state_archive — архив строк семейств каталога состояния (D1008): строки «архив + живые файлы» одни и те же до и
# после переноса; снимки и чужие файлы не члены; воссозданный файл читается вместе с архивом; отказ на чужом имени.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SA="$REPO/hooks/lib/state_archive.py"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
A=11111111-1111-1111-1111-111111111111; B=22222222-2222-2222-2222-222222222222
printf '%s\n' '{"k":1}' '{"k":2}' > "$T/blocker-fired-$A.jsonl"
printf '%s\n' '{"k":3}' > "$T/blocker-fired-$B.agent-x1.jsonl"
printf '%s' '{"k":4}' > "$T/blocker-fired-$B.jsonl"                 # без перевода строки в конце
printf '%s\n' 'turn:1|' > "$T/five-whys-$A.seen"
printf '%s\n' 'snap' > "$T/five-whys-$A.snap-1.blob"                # снимок — не член
printf '%s\n' '{"k":9}' > "$T/blocker-fired-nosid.jsonl"            # без UUID — не член
printf '%s\n' '{"k":8}' > "$T/blocker-fired-$A.jsonl.bak.1"         # резервная копия — не член
lines() { python3 "$SA" lines "$T" "$1" | sort; }
before=$(lines blocker-fired)
# T1 — живые члены: три файла, четыре строки, имя файла первым полем; без UUID не берётся.
[ "$(wc -l <<<"$before" | tr -d ' ')" = 4 ] && ok || bad T1 "строк не 4: $before"
grep -q "^blocker-fired-$B.agent-x1.jsonl	[0-9]*	{\"k\":3}$" <<<"$before" && ok || bad T1 "формат строки: $before"
grep -q 'nosid' <<<"$before" && bad T1 "файл без UUID стал членом" || ok
grep -q '\.bak\.' <<<"$before" && bad T1 "резервная копия стала членом" || ok
# T2 — снимок `.snap-` не член.
[ "$(lines five-whys | wc -l | tr -d ' ')" = 1 ] && ok || bad T2 "снимок стал членом: $(lines five-whys)"
# T3 — перенос не меняет строк и удаляет файлы.
n=$(python3 "$SA" archive "$T" blocker-fired "blocker-fired-$A.jsonl" "blocker-fired-$B.jsonl")
[ "$n" = 2 ] && ok || bad T3 "перенесено не 2: $n"
[ ! -e "$T/blocker-fired-$A.jsonl" ] && [ ! -e "$T/blocker-fired-$B.jsonl" ] && ok || bad T3 "файл остался"
[ "$(lines blocker-fired)" = "$before" ] && ok || bad T3 "строки разошлись после переноса"
[ -f "$T/archive/blocker-fired.tsv" ] && ok || bad T3 "архива нет"
# T4 — воссозданный файл: его новые строки читаются вместе с архивом.
printf '%s\n' '{"k":5}' > "$T/blocker-fired-$A.jsonl"
[ "$(lines blocker-fired | wc -l | tr -d ' ')" = 5 ] && ok || bad T4 "воссозданный файл не прочитан"
# T5 — чужое имя — отказ (код 2), архив не тронут.
sz=$(wc -c < "$T/archive/blocker-fired.tsv")
python3 "$SA" archive "$T" blocker-fired "blocker-fired-nosid.jsonl" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ "$(wc -c < "$T/archive/blocker-fired.tsv")" = "$sz" ] && [ -e "$T/blocker-fired-nosid.jsonl" ] && ok \
    || bad T5 "чужое имя принято: код $rc"
# T6 — уборка дросселя архива не видит: он не в корне каталога.
[ -z "$(find "$T" -maxdepth 1 -name '*-fired-*' | grep archive)" ] && ok || bad T6 "архив в корне каталога"
# T7 — расширение по семейству: `.seen` у `output-violations` и `.jsonl` у `five-whys` — не члены (скептик D1008, L4).
printf '%s\n' '{"x":1}' > "$T/output-violations-$A.seen"; printf '%s\n' 'turn:9|' > "$T/five-whys-$B.jsonl"
[ -z "$(python3 "$SA" lines "$T" output-violations)" ] && ok || bad T7 "чужое расширение стало членом output-violations"
[ "$(lines five-whys | wc -l | tr -d ' ')" = 1 ] && ok || bad T7 "чужое расширение стало членом five-whys"
# T8 — чужое имя посреди списка: не переносится НИЧЕГО (скептик, L1).
C=33333333-3333-3333-3333-333333333333
printf '%s\n' 'turn:1|' > "$T/five-whys-$C.seen"
python3 "$SA" archive "$T" five-whys "five-whys-$C.seen" "five-whys-$B.jsonl" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ -e "$T/five-whys-$C.seen" ] && ok || bad T8 "часть списка перенесена до отказа: код $rc"
# T9 — нечитаемый файл: `lines` — код 2 и имя в stderr; перенос его не удаляет (род B).
chmod 000 "$T/five-whys-$C.seen"
err=$(python3 "$SA" lines "$T" five-whys 2>&1 >/dev/null); rc=$?
[ "$rc" = 2 ] && grep -q "five-whys-$C.seen" <<<"$err" && ok || bad T9 "нечитаемый файл не назван: код $rc, «${err}»"
python3 "$SA" archive "$T" five-whys "five-whys-$C.seen" >/dev/null 2>&1; rc=$?
chmod 644 "$T/five-whys-$C.seen"
[ "$rc" = 2 ] && [ -e "$T/five-whys-$C.seen" ] && ok || bad T9 "нечитаемый файл удалён или отказ не назван: код $rc"
# T10 — отказ удаления после дописи: архив возвращается к прежнему размеру, файл цел (скептик, M3).
sz=$(wc -c < "$T/archive/blocker-fired.tsv")
chmod 555 "$T"
python3 "$SA" archive "$T" blocker-fired "blocker-fired-$A.jsonl" >/dev/null 2>&1; rc=$?
chmod 755 "$T"
[ "$rc" = 2 ] && [ "$(wc -c < "$T/archive/blocker-fired.tsv")" = "$sz" ] && [ -e "$T/blocker-fired-$A.jsonl" ] && ok \
    || bad T10 "отказ удаления оставил строки в архиве: код $rc, размер $(wc -c < "$T/archive/blocker-fired.tsv") из ${sz}"
# T11 — нечитаемый файл посреди списка остаток не держит: годные перенесены, сбойный цел и назван, код 2, в выводе —
# число перенесённых (второй скептик D1008, L-1).
D=44444444-4444-4444-4444-444444444444; E=55555555-5555-5555-5555-555555555555
printf '%s\n' 'turn:4|' > "$T/five-whys-$D.seen"; printf '%s\n' 'turn:5|' > "$T/five-whys-$E.seen"
chmod 000 "$T/five-whys-$C.seen"
out=$(python3 "$SA" archive "$T" five-whys "five-whys-$D.seen" "five-whys-$C.seen" "five-whys-$E.seen" 2>"$T/err"); rc=$?
chmod 644 "$T/five-whys-$C.seen"
[ "$rc" = 2 ] && [ "$out" = 2 ] && [ ! -e "$T/five-whys-$D.seen" ] && [ ! -e "$T/five-whys-$E.seen" ] \
    && [ -e "$T/five-whys-$C.seen" ] && grep -q "five-whys-$C.seen" "$T/err" && ok \
    || bad T11 "остаток не перенесён: код $rc, вывод «${out}», $(cat "$T/err")"
echo "test_state_archive: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
