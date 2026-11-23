#!/usr/bin/env bash
# СУДИТ: hooks/lib/write_targets.py
# probe_D1136 — цели записи touch: значение BSD-ключа `-A` — не цель, цель после `--` не теряется. Красная (1), пока
# `touch -A 01 f.md` даёт цель «01», а `touch -- -x.md` — пусто (фильтр «не начинается с дефиса» срезает операнд после
# `--`; четвёртый скептик, L2). Положительный контроль — `touch a.txt`. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/lib/write_targets.py" ] && command -v python3 >/dev/null 2>&1 || exit 2
python3 -I - "$R/hooks/lib" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
try:
    import write_targets as w
except Exception:
    sys.exit(2)
if w.targets("touch a.txt") != ["a.txt"]:
    sys.exit(2)
cases = {"touch -A 01 f.md": ["f.md"], "touch -- -x.md": ["-x.md"]}
bad = [f"{c} → {w.targets(c)}" for c, want in cases.items() if w.targets(c) != want]
if bad:
    print("цели touch разобраны неверно: " + "; ".join(bad), file=sys.stderr)
    sys.exit(1)
print("ключ -A и операнд после -- разобраны")
PY
