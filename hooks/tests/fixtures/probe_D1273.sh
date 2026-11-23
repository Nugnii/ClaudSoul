#!/usr/bin/env bash
# СУДИТ: scripts/knowledge-instrument-audit.sh
# probe_D1273 — у каждого знания с `confirmed_count ≥ 5` есть признак либо вердикт, и в очереди «знание → инструмент» нет
# просроченных. Повод — откат D326 (8 ноября 2026, D1242): 27 из 58 таких знаний без `detection_signals`,
# `signal_verdict` и `instrument_verdict`, а прибор `scripts/knowledge-instrument-audit.sh` неделями называл 9 просроченных
# (61 дн.) и отвечал 1 — пункта не было (корень R5).
# Первая нога — «Проверка» D326 из архива дословно по смыслу (её владелец — тот пункт); вторая — строка прибора
# «ПРОСРОЧЕНО в очереди». Раздел прибора «уровень не помог» (гейт стоит, нарушения идут) — другой предмет, его не судит.
# Красная (1), пока есть знание без признака и вердикта либо просроченное в очереди; 2 — нет базы или прибора.
# Положительный контроль второй ноги (D1295, 15 ноября 2026): прибор обязан назвать итогом «хранится N» с N > 0.
#   Молчащий прибор не печатает и «ПРОСРОЧЕНО», и проба была зелена на выпотрошенном предмете.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
L="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
[ -d "$L" ] && [ -f "$R/scripts/knowledge-instrument-audit.sh" ] && [ -f "$R/hooks/frame-control-lib.sh" ] || exit 2
. "$R/hooks/frame-control-lib.sh"
command -v python3 >/dev/null 2>&1 || exit 2
bad=0
python3 - "$L" <<'PY' || bad=1
import glob, os, re, sys
hi = []
for f in glob.glob(os.path.join(sys.argv[1], "*.md")):
    s = open(f, errors="replace").read()
    m = re.search(r"^confirmed_count:\s*(\d+)", s, re.M)
    if m and int(m.group(1)) >= 5:
        hi.append((f, s))
miss = [os.path.basename(f) for f, s in hi if not re.search(r"^detection_signals:|^signal_verdict:|^instrument_verdict:", s, re.M)]
if miss:
    print("без признака и вердикта: %d из %d — %s" % (len(miss), len(hi), ", ".join(sorted(miss)[:5])))
    sys.exit(1)
PY
O=$(mktemp "${TMPDIR:-/tmp}/probe-D1273.XXXXXX") || exit 2   # отчёт прибора — не в живое состояние
out=$(LESSONS_DIR="$L" KIA_OUTPUT="$O" bash "$R/scripts/knowledge-instrument-audit.sh" 2>&1); rc=$?
rm -f "$O"
[ "$rc" -ge 2 ] && exit 2
n=$(printf '%s\n' "$out" | sed -n 's/^знание → инструмент: хранится \([0-9][0-9]*\),.*/\1/p' | head -1)
frame_require_nonempty "$n" "знаний у прибора «знание → инструмент»" "итог «хранится N» в выводе прибора" || exit $?
if printf '%s\n' "$out" | grep -q 'ПРОСРОЧЕНО в очереди'; then
    printf '%s\n' "$out" | grep -A3 'ПРОСРОЧЕНО в очереди'
    bad=1
fi
exit "$bad"
