#!/usr/bin/env bash
# test_d509_grep_q_large_body.sh — лист образца видит совпадение и в теле больше буфера трубы.
#
# Брат корня раунда 3 противника D509: лист `heredoc_body_regex` решал по статусу
# `printf … | grep -q`. На теле больше буфера трубы (64 КБ на macOS) с совпадением в начале
# `grep -q` выходит рано, `printf` получает SIGPIPE, и под pipefail статус 141 читался как «нет
# совпадения» — в прежней и в новой редакции одинаково (3 из 3 прогонов, 3 октября 2026).
# Отрицательный контроль: то же большое тело без образца — совпадения нет.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: ждали [$2], получили [$3]"; FAIL=1; fi; }

T=$(mktemp -d)
{ echo "date -j"; i=0; while [ "$i" -lt 5000 ]; do printf '%0100d\n' 0; i=$((i + 1)); done; } > "$T/body"
{ i=0; while [ "$i" -lt 5000 ]; do printf '%0100d\n' 0; i=$((i + 1)); done; } > "$T/clean"
for kind in body clean; do
    jq -cn --rawfile b "$T/$kind" '{command: ("cat > hooks/a.sh <<EOF\n" + $b + "EOF")}' > "$T/$kind.json"
done
run() { bash -c '. "$1"; ds_evaluate_node "{\"heredoc_body_regex\":\"date -j\"}" Bash "$(cat "$2")" ""; echo "rc=$?"' _ "$LIB" "$1"; }

check "совпадение в начале тела больше 64 КБ" "rc=0" "$(run "$T/body.json")"
check "контроль: то же тело без образца" "rc=1" "$(run "$T/clean.json")"

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
