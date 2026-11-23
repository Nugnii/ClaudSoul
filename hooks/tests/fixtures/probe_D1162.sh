#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_backfill.sh hooks/backfill-intrusiveness.sh
# Проба D1162: защиту пустого списка у массового реплея судит тест, который исполняется и на macOS, и в CI. Прежде её
# держал ключ `-r` у xargs, а BSD xargs пустой вход воркеру не отдаёт ни с ключом, ни без — мутант «снять `-r`» был
# зелён везде, кроме GNU, где пробу не исполняет никто. Теперь защита — явное условие `[ "$SELECTED" -gt 0 ]`.
#   nocond      — условие снято;
#   noexit      — условие печатает «nothing to replay», но реплей идёт дальше (скептик D1162, M1);
#   afterreplay — условие стоит ниже реплея (M1).
# На каждом `test_backfill.sh` в копии дерева обязан покраснеть (нога T7): код на BSD 0 при любом поведении xargs, нога
# судит ещё и то, что реплей не начинался.
# Контроль — немутированная копия: тест на ней зелёный.
# Код: 0 — контроль зелёный, мутант красный; 1 — мутант прошёл (названо); 2 — нет файлов, мутант не встал или контроль
#   не зелёный (судить мутанта не на чем).
set -u
R="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -f "$R/hooks/backfill-intrusiveness.sh" ] && [ -f "$R/hooks/tests/test_backfill.sh" ] || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1162.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
mk() {   # mk <имя> [<было> <стало>] — копия дерева без набора тестов (8 из 12 МБ), мутант в массовом реплее
    mkdir -p "$W/$1/hooks/tests" && cp "$R"/hooks/*.sh "$W/$1/hooks/" && cp -R "$R/hooks/lib" "$W/$1/hooks/" \
        && cp "$R/hooks/tests/test_backfill.sh" "$W/$1/hooks/tests/" || return 1
    [ $# -eq 1 ] && return 0
    python3 - "$W/$1/hooks/backfill-intrusiveness.sh" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
run() { bash "$W/$1/hooks/tests/test_backfill.sh" >/dev/null 2>&1; echo $?; }
mk cur || exit 2
[ "$(run cur)" = 0 ] || { echo "контроль: test_backfill на немутированной копии не зелёный"; exit 2; }
C='[ "$SELECTED" -gt 0 ] || { echo "--- no transcripts selected, nothing to replay"; exit 0; }'
mk nocond "$C" '' || { echo "мутант nocond не встал"; exit 2; }
mk noexit "$C" '[ "$SELECTED" -gt 0 ] || { echo "--- no transcripts selected, nothing to replay"; }' || { echo "мутант noexit не встал"; exit 2; }
mk afterreplay "$C" '' || { echo "мутант afterreplay не встал"; exit 2; }
python3 - "$W/afterreplay/hooks/backfill-intrusiveness.sh" "$C" <<'PY' || { echo "мутант afterreplay не встал"; exit 2; }
import sys
p, c = sys.argv[1:3]
s = open(p, encoding="utf-8").read()
a = "T1=$(date +%s)"
if s.count(a) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, c + "\n" + a))
PY
bad=0
for m in nocond noexit afterreplay; do
    rc=$(run "$m")
    [ "$rc" != 0 ] || { echo "мутант $m: test_backfill — код 0, пустой список без защиты не судится"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "контроль зелёный, три мутанта защиты пустого списка красят test_backfill"
exit "$bad"
