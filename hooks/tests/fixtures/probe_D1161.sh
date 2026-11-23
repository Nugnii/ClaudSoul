#!/usr/bin/env bash
# СУДИТ: hooks/tests/fixtures/probe_D1105.sh hooks/five-whys-gate.sh
# Проба D1161: проба D1105 держит три живых обещания пункта — каждый мутант стража в копии дерева её краснит:
#   readdeny  — чтение при поводе отбивается (признак записи взведён для всех вызовов);
#   bashwrite — Bash-запись при поводе не судится (признак записи у Bash снят);
#   jwrite    — повод пишется в журнал `.seen` только на записи (на чтении строки `live|…` не ложатся; мутант «журнала
#               нет вовсе» был шире обещания — его ловила и проба, смотрящая журнал после записи, скептик D1161 M1).
# Четвёртого обещания («подсказка на записи без права на отказ») нет с D1151: запись без права тоже молчит, мутант
# «подсказки нет никогда» совпадает с кодом. Контроль — немутированная копия: проба D1105 на ней 0.
# Код: 0 — контроль зелёный, все три мутанта красны (код 1); 1 — нет (названо); 2 — нет стража, пробы, мутант не встал
#   или контроль не зелёный (судить мутантов не на чем).
set -u
R="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
P="$R/hooks/tests/fixtures/probe_D1105.sh"
[ -f "$R/hooks/five-whys-gate.sh" ] && [ -f "$P" ] || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1161.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
mk() {   # mk <имя> [<было> <стало>] — копия дерева, мутант в стороже
    mkdir -p "$W/$1" && cp -R "$R/hooks" "$W/$1/" || return 1
    [ $# -eq 1 ] && return 0
    python3 - "$W/$1/hooks/five-whys-gate.sh" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
run() { CLAUDSOUL_REPO="$W/$1" bash "$P" >/dev/null 2>&1; echo $?; }
mk cur || exit 2
[ "$(run cur)" = 0 ] || { echo "контроль: проба D1105 на немутированной копии не зелёная"; exit 2; }
mk readdeny 'IS_WRITE=0
case "$TOOL_NAME" in' 'IS_WRITE=1
case "$TOOL_NAME" in' || { echo "мутант readdeny не встал"; exit 2; }
mk bashwrite 'is_write_command "$_cmd" && IS_WRITE=1' 'false && IS_WRITE=1' || { echo "мутант bashwrite не встал"; exit 2; }
mk jwrite '[ -n "$_tok" ] && rc_occasion_note "$SEEN_FILE"' '[ -n "$_tok" ] && [ "$IS_WRITE" -eq 1 ] && rc_occasion_note "$SEEN_FILE"' || { echo "мутант jwrite не встал"; exit 2; }
bad=0
for m in readdeny bashwrite jwrite; do
    rc=$(run "$m")
    [ "$rc" = 1 ] || { echo "мутант $m: проба D1105 — код $rc, а не 1"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "контроль зелёный, три мутанта красят пробу D1105"
exit "$bad"
