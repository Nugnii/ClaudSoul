#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh scripts/outcome.sh
# probe_D1213 — отказ исхода различает «пункт был в бэклоге и не менялся» и «пункт лежал в архиве уже на момент повода».
# Красная (1), пока для пункта, лежавшего в архиве до повода, отказ советует дописку (дописка в архивный блок свежести
# не даёт никогда, `_rc_block_fresh_snap`) или принимает её; пока у пункта бэклога, не менявшегося с повода, пропал
# совет дописки; пока дописка к пункту, унесённому в архив ПОСЛЕ повода без изменений, не снимает отказ; пока совет
# отказа архивному пункту не исполним — новый пункт со ссылкой и новая запись знания судятся ИСПОЛНЕНИЕМ, а не словами
# (скептик opus по 3ec8907a, M2: мутанты «совета нет», «верни в BACKLOG.md», «допиши в архивный блок» проходили). Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
export LESSONS_DIR="$SB/lessons"; mkdir -p "$LESSONS_DIR" || exit 2
why() {   # <sid> <исход> <вид> <чем> <каталог> — причина отказа команды исхода в stdout; код как у неё
    ( cd "$5" && DIS_SESSION="$1" STATE_DIR="$ST" bash "$OUTCMD" "$2" "$3" "$4" 2>&1 >/dev/null )
}
ci() { ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm "$2" ); }
closed() {   # <файл> <ID> <адрес> — закрытый пункт (☑ — архиватор уносит только такие) с теми же строками, что у `item`
    printf '%s\n' "- ☑ **$2** находка" "  **Повод.** \`$3\` ломается." '  **Корень.** R6 — два состояния.' >> "$1"
}
MORE='  **Проявление.** `hooks/x.sh:5` — тот же признак.'
# (а) пункт лежал в архиве до повода: дописка по совету отказа не засчитывается — совета быть не должно
P="$SB/a"; gproj "$P" || exit 2
printf '%s\n' '# Архив' '' > "$P/BACKLOG-archive.md"; closed "$P/BACKLOG-archive.md" D9961 "hooks/x.sh:3"; ci "$P" arch || exit 2
TA="$SB/ta.jsonl"; mk_tr "$TA" "$FINDING"
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TA" "$P")")" = deny ] || exit 2
printf '%s\n' "$MORE" >> "$P/BACKLOG-archive.md"
W=$(why s1 debt discovery D9961 "$P"); rc=$?
[ "$rc" -eq 0 ] && { echo "(а) дописка в архивный блок пункта, лежавшего в архиве до повода, приняла исход" >&2; exit 1; }
[ "$rc" -eq 3 ] || exit 2
grep -q 'допиши' <<< "$W" && { echo "(а) отказ советует дописку пункту, лежавшему в архиве до повода: $W" >&2; exit 1; }
grep -q 'найден в архиве' <<< "$W" || { echo "(а) отказ не называет состояние «в архиве, в снимке бэклога нет»: $W" >&2; exit 1; }
grep -q 'новый пункт' <<< "$W" && grep -q 'запись знания' <<< "$W" || { echo "(а) отказ не советует новый пункт и новое знание: $W" >&2; exit 1; }
item "$P/BACKLOG.md" D9970 "hooks/x.sh:3"; printf '%s\n' '  Продолжение архивного D9961.' >> "$P/BACKLOG.md"
W=$(why s1 debt discovery "D9970 (со ссылкой на D9961)" "$P") || { echo "(а) совет исполнен — новый пункт со ссылкой, а исход не принят: $W" >&2; exit 1; }
# (б) пункт бэклога, не менявшийся с повода: совет дописки исполним и остаётся
P="$SB/b"; gproj "$P" || exit 2
item "$P/BACKLOG.md" D9962 "hooks/x.sh:3"; ci "$P" item || exit 2
TB="$SB/tb.jsonl"; mk_tr "$TB" "$FINDING"
[ "$(dec "$(cw s2 "$P/hooks/x.sh" "$TB" "$P")")" = deny ] || exit 2
W=$(why s2 debt discovery D9962 "$P"); rc=$?
[ "$rc" -eq 0 ] && { echo "(б) неменявшийся пункт бэклога принят без дописки" >&2; exit 1; }
[ "$rc" -eq 3 ] || exit 2
grep -q 'допиши в него проявление' <<< "$W" || { echo "(б) у неменявшегося пункта бэклога пропал совет дописки: $W" >&2; exit 1; }
# (в) пункт был в бэклоге на момент повода и унесён в архив без изменений: совет прежний, и дописка его снимает
P="$SB/c"; gproj "$P" || exit 2
closed "$P/BACKLOG.md" D9963 "hooks/x.sh:3"; ci "$P" closed || exit 2
TC="$SB/tc.jsonl"; mk_tr "$TC" "$FINDING"
[ "$(dec "$(cw s3 "$P/hooks/x.sh" "$TC" "$P")")" = deny ] || exit 2
printf '%s\n' '# BACKLOG' '' > "$P/BACKLOG.md"
printf '%s\n' '# Архив' '' > "$P/BACKLOG-archive.md"; closed "$P/BACKLOG-archive.md" D9963 "hooks/x.sh:3"
W=$(why s3 debt discovery D9963 "$P"); rc=$?
[ "$rc" -eq 0 ] && { echo "(в) пункт, унесённый в архив после повода без изменений, принят без дописки" >&2; exit 1; }
[ "$rc" -eq 3 ] || exit 2
grep -q 'допиши в него проявление' <<< "$W" || { echo "(в) у пункта, унесённого в архив после повода, пропал совет дописки: $W" >&2; exit 1; }
printf '%s\n' "$MORE" >> "$P/BACKLOG-archive.md"
W=$(why s3 debt discovery D9963 "$P") || { echo "(в) дописка к пункту, унесённому в архив после повода, не сняла отказ: $W" >&2; exit 1; }
# (г) тот же совет второй дорогой: новая запись знания снимает повод пункта из архива
P="$SB/d"; gproj "$P" || exit 2
printf '%s\n' '# Архив' '' > "$P/BACKLOG-archive.md"; closed "$P/BACKLOG-archive.md" D9964 "hooks/x.sh:3"; ci "$P" arch || exit 2
TD="$SB/td.jsonl"; mk_tr "$TD" "$FINDING"
[ "$(dec "$(cw s4 "$P/hooks/x.sh" "$TD" "$P")")" = deny ] || exit 2
W=$(why s4 debt discovery D9964 "$P"); [ $? -eq 3 ] || exit 2
grep -q 'запись знания' <<< "$W" || { echo "(г) отказ не советует новое знание: $W" >&2; exit 1; }
printf '%s\n' '---' 'name: case-2026-11-05-d1213-probe' '---' > "$LESSONS_DIR/case-2026-11-05-d1213-probe.md"
W=$(why s4 knowledge discovery case-2026-11-05-d1213-probe "$P") || { echo "(г) совет исполнен — новое знание, а исход не принят: $W" >&2; exit 1; }
echo "архивный пункт назван архивным, совет исполним"
exit 0
