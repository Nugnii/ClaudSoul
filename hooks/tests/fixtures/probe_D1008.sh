#!/usr/bin/env bash
# СУДИТ: scripts/state-prune.sh hooks/lib/state_archive.py
# СУД: свойство мира
# probe_D1008 <каталог состояния> — хранимые семейства ограничены окном уборки: сверх 60 сессий на семейство лежат
# только сессии, которых уборка и не обязана трогать, — со свежим файлом (моложе 14 дней простоя `state-prune.sh` + 7 дней
# периода замера + сутки запаса). Без уборки сверх окна копятся несвежие — код 1 с именем семейства.
# Судит свойство, а не мгновение: «не больше 60» верно только сразу после уборки (находка 30 октября 2026).
# Каталога нет либо он не прочитан — 2.
S="${1:-$HOME/.claude/hooks/state}"
[ -d "$S" ] || { echo "probe_D1008: нет каталога $S"; exit 2; }
python3 - "$S" <<'PY'
import os, re, sys, time
s = sys.argv[1]; now = time.time(); KEEP, FRESH = 60, (14 + 7 + 1) * 86400
SID = r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
fam = re.compile(r'^(disagreement-pending|output-violations|blocker-fired|trust-guard-fired|detection|outcome|five-whys)-(' + SID + ')')
last, fams = {}, {}
try:
    for e in os.scandir(s):
        if not e.is_file(follow_symlinks=False):
            continue
        t = e.stat(follow_symlinks=False).st_mtime
        for m in re.finditer(SID, e.name):
            last[m.group(0)] = max(last.get(m.group(0), 0), t)
        m = fam.match(e.name)
        if m:
            fams.setdefault(m.group(1), set()).add(m.group(2))
except OSError as x:
    print(f'probe_D1008: каталог не прочитан: {x}'); sys.exit(2)
bad = 0
for f, ss in sorted(fams.items()):
    fresh = sum(1 for x in ss if now - last[x] < FRESH)
    if len(ss) - KEEP > fresh:
        print(f'{f}: сессий {len(ss)}, сверх окна {len(ss) - KEEP}, из них свежих {fresh} — уборка не переносит'); bad = 1
sys.exit(bad)
PY
