#!/usr/bin/env bash
# СУДИТ: hooks/lib/state_archive.py scripts/doc-figures.sh hooks/disagreement-lib.sh hooks/lib/open-findings-lib.sh scripts/violation-class.sh hooks/knowledge-counter-bump.sh
# test_state_archive_readers — D1008: каждое число, которое семь семейств каталога состояния публикуют «за всё время»,
# одно и то же до и после переноса ВСЕХ файлов семейств в архив (`hooks/lib/state_archive.py`); открытый ключ
# перенесённого файла закрывается и по названной сессии, и по всем.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SA="$REPO/hooks/lib/state_archive.py"
BUMP="$REPO/hooks/knowledge-counter-bump.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S="$T/state"; mkdir -p "$S" "$T/lessons"
A=11111111-1111-1111-1111-111111111111; B=22222222-2222-2222-2222-222222222222; C=33333333-3333-3333-3333-333333333333
printf '%s\n' '{"ts":"2026-09-01T00:00:00Z","token":"x","status":"surfaced"}' '{"ts":"2026-10-02T00:00:00Z","token":"y","status":"pending"}' > "$S/output-violations-$A.jsonl"
printf '%s' '{"ts":"2026-10-03T00:00:00Z","token":"z","status":"surfaced"}' > "$S/output-violations-$B.jsonl"
printf '%s\n' '{"key":"k1"}' '{"key":"k2"}' > "$S/blocker-fired-$A.jsonl"
printf '%s\n' '{"key":"k3"}' > "$S/blocker-fired-$A.agent-x1.jsonl"
printf '%s\n' '{"key":"k4"}' > "$S/blocker-fired-$B.jsonl"
printf '%s\n' '{"key":"t1"}' 'битая' '{"key":"t2"}' > "$S/trust-guard-fired-$C.jsonl"
printf '%s\n' '{"date":"2026-10-01T00:00:00Z","key":"pattern-all","outcome":"pending","confidence":3,"tool":"Bash"}' \
    '{"date":"2026-10-01T00:00:00Z","key":"pattern-closed","outcome":"pending","confidence":2,"tool":"Edit"}' \
    '{"date":"2026-10-02T00:00:00Z","key":"pattern-closed","outcome":"confirmed"}' > "$S/disagreement-pending-$A.jsonl"
printf '%s\n' '{"date":"2026-10-01T00:00:00Z","key":"pattern-exp","outcome":"pending","confidence":1,"tool":"failure"}' \
    '{"date":"2026-10-09T00:00:00Z","key":"pattern-exp","outcome":"not_applicable","expired":true,"age_days":8}' > "$S/disagreement-pending-$B.jsonl"
printf '%s\n' '{"date":"2026-10-05T00:00:00Z","key":"pattern-arc","outcome":"pending","confidence":3,"tool":"Bash"}' > "$S/disagreement-pending-$C.jsonl"
printf '%s\n' '{"guard":"g","act":"said","sig":"pattern-x:s@y"}' '{"guard":"g","act":"muted","sig":"pattern-x:s@y"}' > "$S/detection-$A.jsonl"
printf '%s\n' "{\"session\":\"$A\",\"knowledge\":\"pattern-x.md\",\"outcome\":\"applicable_not_followed\"}" \
    "{\"session\":\"$B\",\"knowledge\":\"pattern-z.md\",\"outcome\":\"applicable_not_followed\"}" > "$S/disagreement-outcomes.jsonl"
printf '%s\n' '{"ts":"2026-10-01T00:00:00Z","key":"11","signal":"rework","outcome":"deferred","ref":"r"}' \
    '{"ts":"2026-10-01T00:00:00Z","key":"12","signal":"correction","outcome":"looked"}' > "$S/outcome-$A.jsonl"
printf '%s\n' 'turn:11|rework:aa|' 'turn:12|correction:bb|' 'turn:13|discovery:cc|' > "$S/five-whys-$A.seen"
printf '%s\n' 'turn:21|event:dd|' > "$S/five-whys-$B.seen"
touch -t 202610010000 "$S/five-whys-$A.seen"; touch -t 202610020000 "$S/five-whys-$B.seen"
numbers() {
    local k
    for k in findings_total findings_2026-10 blocker_markers blocker_sessions trust_guard_firings; do
        printf '%s=%s\n' "$k" "$(STATE_DIR="$S" bash "$REPO/scripts/doc-figures.sh" "$k" 2>&1)"
    done
    printf 'dis_stats=%s\n' "$(bash -c '. "$1/hooks/disagreement-lib.sh"; dis_stats "$2"' _ "$REPO" "$S" 2>/dev/null)"
    # Читатель — подстановкой, а не трубой: страж после `| sed` судил бы sed, и отказ читателя был бы нем (скептик D1194, H2).
    _o=$(bash -c '. "$1/hooks/disagreement-lib.sh"; dis_scan_open "$2"' _ "$REPO" "$S" 2>/dev/null) \
        || echo "читатель dis_scan_open вышел не нулём: hooks/tests/test_state_archive_readers.sh:44" >&2
    [ -z "$_o" ] || printf '%s\n' "$_o" | sed 's/^/open=/'
    printf 'of=%s\n' "$(bash -c '. "$1/hooks/lib/open-findings-lib.sh"; of_open_counts "$2"' _ "$REPO" "$S" 2>/dev/null)"
    _o=$(bash -c '. "$1/hooks/lib/open-findings-lib.sh"; of_open_list "$2"' _ "$REPO" "$S" 2>/dev/null) \
        || echo "читатель of_open_list вышел не нулём: hooks/tests/test_state_archive_readers.sh:48" >&2
    [ -z "$_o" ] || printf '%s\n' "$_o" | sort | sed 's/^/oflist=/'
    STATE_DIR="$S" bash "$REPO/scripts/violation-class.sh" 2>&1 | sed 's/^/vc=/'
}
before=$(numbers)
# T1 — положительный контроль: числа не пусты и те, что задуманы фикстурой.
for want in 'findings_total=3' 'findings_2026-10=2' 'blocker_markers=4' 'blocker_sessions=2' 'trust_guard_firings=2' \
            'dis_stats=1 1 2' "open=$A|pattern-all|" "open=$C|pattern-arc|" 'нарушений (applicable_not_followed): 2'; do
    grep -qF -- "$want" <<<"$before" && ok || bad T1 "нет «${want}» в: ${before}"
done
grep -qE '^of=[1-9]' <<<"$before" && ok || bad T1 "свод поводов пуст: $(grep '^of=' <<<"$before")"
# T2 — перенос ВСЕХ файлов семейств в архив не меняет ни одного числа.
for fam in output-violations blocker-fired trust-guard-fired disagreement-pending detection outcome five-whys; do
    names=$(ls "$S" | grep -E "^$fam-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(\.agent-[A-Za-z0-9_-]+)?\.(jsonl|seen)$")
    # shellcheck disable=SC2086
    python3 "$SA" archive "$S" "$fam" $names >/dev/null || bad T2 "перенос $fam упал"
done
[ -z "$(ls "$S" | grep -E -- '-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')" ] && ok || bad T2 "живые файлы остались: $(ls "$S")"
after=$(numbers)
[ "$after" = "$before" ] && ok || bad T2 "числа разошлись после переноса: $(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
# T3 — открытый ключ перенесённого файла закрывается: по названной сессии и по всем; воссозданный файл и архив
# читаются вместе — ключ уходит из очереди.
printf -- '---\nname: проба\nconfidence: 3\nimpact: 3\nconfirmed_count: 0\ncontradicted_count: 0\nstatus: active\n---\nтело\n' > "$T/lessons/pattern-arc.md"
cp "$T/lessons/pattern-arc.md" "$T/lessons/pattern-all.md"
o1=$(PATHS_LIB=/nonexistent LESSONS_DIR="$T/lessons" CLAUDE_STATE_DIR="$S" DIS_SESSION="$C" bash "$BUMP" pattern-arc not_applicable "проба архива" 2>&1)
grep -q 'погашено записей: 1' <<<"$o1" && ok || bad T3 "по сессии не погашено: $o1"
o2=$(PATHS_LIB=/nonexistent LESSONS_DIR="$T/lessons" CLAUDE_STATE_DIR="$S" DIS_ALL=1 bash "$BUMP" pattern-all not_applicable "проба архива" 2>&1)
grep -q 'погашено записей: 1' <<<"$o2" && ok || bad T3 "по всем не погашено: $o2"
open_now=$(bash -c '. "$1/hooks/disagreement-lib.sh"; dis_scan_open "$2"' _ "$REPO" "$S" 2>/dev/null)
[ -z "$open_now" ] && ok || bad T3 "ключи остались открытыми: $open_now"
# T3b — закрытый ключ второй раз не гасится: последняя строка — живого файла (исход), а не архива (pending); обратный
# порядок закрыл бы его снова (скептик D1008, L3; род D85).
o3=$(PATHS_LIB=/nonexistent LESSONS_DIR="$T/lessons" CLAUDE_STATE_DIR="$S" DIS_SESSION="$C" bash "$BUMP" pattern-arc not_applicable "повтор" 2>&1)
grep -q 'погашено записей: 0' <<<"$o3" && ok || bad T3b "закрытый ключ погашен повторно: $o3"
# T4 — под zsh читатели из установки видят архив (скептик D1008, H1: путь к библиотеке из `$0` внутри функции —
# имя функции; `/learn` зовёт `dis_scan_open` через Bash-инструмент, то есть zsh). Установка — копия хуков.
if command -v zsh >/dev/null 2>&1; then
    H="$T/home"; mkdir -p "$H/.claude/hooks/lib"
    cp "$REPO"/hooks/*.sh "$H/.claude/hooks/"; cp -R "$REPO/hooks/lib/." "$H/.claude/hooks/lib/"
    zb=$(bash -c '. "$1/hooks/disagreement-lib.sh"; dis_stats "$2"' _ "$REPO" "$S" 2>/dev/null)
    zz=$(HOME="$H" zsh -c '. "$1/.claude/hooks/disagreement-lib.sh"; dis_stats "$2"' _ "$H" "$S" 2>/dev/null)
    [ -n "$zb" ] && [ "$zz" = "$zb" ] && ok || bad T4 "dis_stats под zsh «${zz}», под bash «${zb}»"
    ob=$(bash -c '. "$1/hooks/lib/open-findings-lib.sh"; of_open_counts "$2"' _ "$REPO" "$S" 2>/dev/null)
    oz=$(HOME="$H" zsh -c '. "$1/.claude/hooks/lib/open-findings-lib.sh"; of_open_counts "$2"' _ "$H" "$S" 2>/dev/null)
    [ -n "$ob" ] && [ "$oz" = "$ob" ] && ok || bad T4 "свод под zsh «${oz}», под bash «${ob}»"
else
    echo "SKIP T4: нет zsh"
fi
# T5 — неполное чтение — `n/a`, а не число поменьше (род B).
chmod 000 "$S/archive/output-violations.tsv"
nv=$(STATE_DIR="$S" bash "$REPO/scripts/doc-figures.sh" findings_total 2>/dev/null)
chmod 644 "$S/archive/output-violations.tsv"
[ "$nv" = "n/a" ] && ok || bad T5 "нечитаемый архив дал число «${nv}», а не n/a"
# T5b — нечитаемый архив у остальных читателей: `archived` и `violation-class` — код 2, `dis_stats` — код 2 без чисел
# (второй скептик D1008, M-1 и L-2).
chmod 000 "$S/archive/detection.tsv" "$S/archive/disagreement-pending.tsv"
python3 "$SA" archived "$S" detection >/dev/null 2>&1; r1=$?
STATE_DIR="$S" bash "$REPO/scripts/violation-class.sh" >/dev/null 2>&1; r2=$?
ds=$(bash -c '. "$1/hooks/disagreement-lib.sh"; dis_stats "$2"' _ "$REPO" "$S" 2>/dev/null); r3=$?
chmod 644 "$S/archive/detection.tsv" "$S/archive/disagreement-pending.tsv"
[ "$r1" = 2 ] && ok || bad T5b "archived при нечитаемом архиве — код $r1"
[ "$r2" = 2 ] && ok || bad T5b "violation-class при нечитаемом архиве — код $r2"
[ "$r3" = 2 ] && [ -z "$ds" ] && ok || bad T5b "dis_stats при нечитаемом архиве — код $r3, «${ds}»"
echo "test_state_archive_readers: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
