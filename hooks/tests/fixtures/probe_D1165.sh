#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh hooks/five-whys-gate.sh scripts/outcome.sh
# probe_D1165 — нога зелёной стороны, дописанная следом за записью пункта, не становится первой целью повода: свидетель
# `hooks/tests/test_backlog_green_side.sh` — учёт долга того же жанра, что BACKLOG (D520), и исход «в долг» по новому
# пункту после него принимается. Красная (1), пока:
#   (а) повод «находка» → первая запись при поводе — свидетель зелёной стороны → пункт о hooks/x.sh: исход отбит как
#       «запись о другом» (повод D1165, трижды за сессию 27 октября 2026);
#   (б) контроль: после свидетеля настоящая запись hooks/y.sh остаётся первой целью — пункт о hooks/x.sh отбит;
#   (в) контроль: после свидетеля запись другого теста hooks/tests/test_y.sh — первая цель, пункт о hooks/x.sh отбит.
# Рамка не собралась — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
GS="hooks/tests/test_backlog_green_side.sh"
# (а)
P="$SB/a"; gproj "$P" || exit 2; mkdir -p "$P/hooks/tests" && seq 1 20 > "$P/$GS" || exit 2
TA="$SB/ta.jsonl"; mk_tr "$TA" "$FINDING"
[ "$(dec "$(cw s1 "$P/$GS" "$TA" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9970 "hooks/x.sh:4"
no s1 debt discovery D9970 "$P" || { echo "(а) исход по новому пункту отбит: первой целью стал свидетель зелёной стороны" >&2; exit 1; }
# (б)
P="$SB/b"; gproj "$P" || exit 2; mkdir -p "$P/hooks/tests" && seq 1 20 > "$P/$GS" || exit 2
TB="$SB/tb.jsonl"; mk_tr "$TB" "$FINDING"
[ "$(dec "$(cw s2 "$P/$GS" "$TB" "$P")")" = deny ] || exit 2
[ "$(dec "$(cw s2 "$P/hooks/y.sh" "$TB" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9971 "hooks/x.sh:4"
no s2 debt discovery D9971 "$P" && { echo "(б) пункт о hooks/x.sh принят, хотя первая настоящая запись — hooks/y.sh" >&2; exit 1; }
# (в) прочие тесты — не учёт: исключение ровно свидетеля, а не каталога тестов (скептик D1165, M1 — мутант `*/hooks/tests/*`)
P="$SB/c"; gproj "$P" || exit 2; mkdir -p "$P/hooks/tests" && seq 1 20 > "$P/$GS" && seq 1 20 > "$P/hooks/tests/test_y.sh" || exit 2
TC="$SB/tc.jsonl"; mk_tr "$TC" "$FINDING"
[ "$(dec "$(cw s3 "$P/$GS" "$TC" "$P")")" = deny ] || exit 2
[ "$(dec "$(cw s3 "$P/hooks/tests/test_y.sh" "$TC" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9972 "hooks/x.sh:4"
no s3 debt discovery D9972 "$P" && { echo "(в) пункт о hooks/x.sh принят, хотя первая настоящая запись — тест hooks/tests/test_y.sh" >&2; exit 1; }
echo "свидетель зелёной стороны — учёт, а не цель повода; настоящая запись после него по-прежнему цель"
exit 0
