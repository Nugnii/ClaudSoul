set -u
# СУДИТ: scripts/project-graph.py
# probe_D1092.sh — показание вердикта D1092: сколько файлов с входящими рёбрами карточка называет «не знает»,
#   не считая файлов с неуникальным базовым именем — их рёбра упоминаний ложные, они строятся по имени
#   (`scripts/project-graph.py:1011`). 0 — «не знает» не прячет ни одного живого стоящего; иначе 1; нет прибора — 2.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
[ -f scripts/project-graph.py ] || exit 2
python3 - <<'PY'
import importlib.util, sys, os, json, collections, subprocess
sp = importlib.util.spec_from_file_location('pg', 'scripts/project-graph.py')
pg = importlib.util.module_from_spec(sp)
try:
    sp.loader.exec_module(pg)
except SystemExit:
    pass
# Карту даёт владелец (`load`: свежий кэш либо сборка), а не файл кэша (D1295, 15 ноября 2026): модуль подгружается без
# `main`, сборки не было, и проба держалась на кэше, оставленном живой копией, — в чистом снимке (кэш под .gitignore) код 2.
try:
    g = pg.load()
except Exception:
    sys.exit(2)   # владелец карты не ответил — судить нечем, а не «найдено»
if not g:
    sys.exit(2)
names = collections.Counter(os.path.basename(f) for f in
                            subprocess.run(['git', 'ls-files', '*.sh', '*.py'], capture_output=True, text=True).stdout.split())
up = {e['target'] for e in g['edges']}
files = [n['key'] for n in g['nodes'] if n['id'] in up and n.get('key') and os.path.isfile(n['key'])]
# Положительный контроль (скептик opus по D1295, M1): карта без рёбер давала «с входящими 0» и код 0 — пустая
# популяция читалась «никого не прячет». Ноль файлов с входящими — рамка не собралась, а не «чисто».
if not files:
    print('рамка: у карты ни одного файла с входящими рёбрами — судить нечем')
    sys.exit(2)
unk = [k for k in files if not pg.kind_known(k)]
hidden = [k for k in unk if names[os.path.basename(k)] <= 1]
print(f'с входящими {len(files)}; «не знает» при входящих {len(unk)}; из них с уникальным именем {len(hidden)}'
      + (': ' + ', '.join(hidden[:5]) if hidden else ''))
sys.exit(0 if not hidden else 1)
PY
