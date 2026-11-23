#!/usr/bin/env bash
# СУДИТ: hooks/lib/write_targets.py
# probe_D1123 — значение ключа у `touch`/`mkdir` не цель записи. Красная (1), пока `touch -t 202601010000 a.txt` даёт
# целью и `202601010000`, `mkdir -m 755 d` — `755`, а `touch -r ref.txt b.txt` числит записью читаемый `ref.txt`
# (карта связей внесла узел «202601010000», 26 октября 2026). Положительный контроль — цели без ключей. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/lib/write_targets.py" ] && command -v python3 >/dev/null 2>&1 || exit 2
python3 -I - "$R/hooks/lib" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
try:
    import write_targets as w
except Exception:
    sys.exit(2)
if w.targets("touch a.txt b.txt") != ["a.txt", "b.txt"] or w.targets("mkdir -p d") != ["d"]:
    sys.exit(2)
cases = {"touch -t 202601010000 a.txt": ["a.txt"], "mkdir -m 755 d": ["d"], "touch -r ref.txt b.txt": ["b.txt"]}
bad = [f"{c} → {w.targets(c)}" for c, want in cases.items() if w.targets(c) != want]
if bad:
    print("значение ключа взято целью записи: " + "; ".join(bad), file=sys.stderr)
    sys.exit(1)
print("значения ключей — не цели")
PY
