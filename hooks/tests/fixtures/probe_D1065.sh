set -u
# СУДИТ: hooks/backlog-lib.sh
# probe_D1065.sh — читатель бэклога под писателем с усечением: сколько чтений `backlog_open_items` дали не то число
#   открытых. Писатель — `open(path, 'w').write` раз в 10 мс, как пишут пересчёт показаний и архиватор; inode файла
#   при этом не меняется (замена переименованием откатана — ограда кольца ключует бэклог по inode).
#   0 — ни одного неверного чтения; 1 — есть; 2 — нет библиотеки, python3 либо фикстура не разобралась.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
L="$PWD/hooks/backlog-lib.sh"
[ -f "$L" ] && command -v python3 >/dev/null 2>&1 || exit 2
. "$L" 2>/dev/null || exit 2
W=$(mktemp -d) || exit 2
python3 - "$W/B.md" <<'PY' || exit 2
import sys
body = ['# BACKLOG\n\n']
for i in range(300):   # ~90 КБ, как живой бэклог: окно записи того же порядка
    body.append(f'- ☐ **D{9000 + i}** пункт {i} ' + 'описание ' * 30 + '\n'
                f'  **Проверка возврата:** решение — пункт описывает наличный дефект.\n\n')
open(sys.argv[1], 'w').write(''.join(body))
PY
want=$(backlog_open_items "$W/B.md" 2>/dev/null | grep -c .)
[ "$want" = 300 ] || exit 2
python3 - "$W/B.md" <<'PY' &
import sys, time
p = sys.argv[1]; a = open(p).read(); b = a.replace('\n\n', '\n\n\n', 1)
end = time.time() + 7; i = 0
while time.time() < end:
    open(p, 'w').write((a, b)[i % 2]); i += 1; time.sleep(0.01)
PY
wp=$!
n=0; bad=0; end=$(( $(date +%s) + 6 ))
while [ "$(date +%s)" -lt "$end" ]; do
    c=$(backlog_open_items "$W/B.md" 2>/dev/null | grep -c .); n=$((n + 1)); [ "$c" = "$want" ] || bad=$((bad + 1))
done
wait "$wp" 2>/dev/null
echo "чтений $n, неверных $bad"
[ "$bad" = 0 ]
