set -u
# СУДИТ: hooks/session-collector.sh
# probe_D1101.sh — счёт «открытых N» сборщика на Stop (`_bl_open_count`) под писателем бэклога с усечением: сколько
#   чтений дали не то число. Представитель восьми читателей BACKLOG.md вне библиотеки (D1101): они читают файл сами,
#   мимо `backlog_stable_copy` (D1065). 0 — ни одного неверного чтения; 1 — есть; 2 — нет сборщика, функции или python3.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
H="$PWD/hooks/session-collector.sh"
[ -f "$H" ] && command -v python3 >/dev/null 2>&1 || exit 2
FN=$(sed -n '/^_bl_open_count() {/,/^}/p' "$H")
[ -n "$FN" ] || exit 2
# Рамка настоящего хука: библиотека обязана подключаться ДО первого счёта — иначе в хуке `backlog_read` ещё нет,
# и счёт идёт запасной веткой `cat`, хотя здесь, где библиотека подключена пробой, он был бы цел.
_src=$(grep -n '^[[:space:]]*\. "\$_BLL"' "$H" | head -1 | cut -d: -f1)
_call=$(grep -n 'BACKLOG_OPEN=$(_bl_open_count' "$H" | head -1 | cut -d: -f1)
[ -n "$_call" ] || exit 2
{ [ -n "$_src" ] && [ "$_src" -lt "$_call" ]; } || { echo "библиотека подключается после первого счёта (строка ${_src:-нет} против ${_call})"; exit 1; }
[ -f "$PWD/hooks/backlog-lib.sh" ] && . "$PWD/hooks/backlog-lib.sh" 2>/dev/null
eval "$FN"
W=$(mktemp -d) || exit 2
python3 - "$W/B.md" <<'PY' || exit 2
import sys
body = ['# BACKLOG\n\n']
for i in range(300):
    body.append(f'- ☐ **D{9000 + i}** пункт {i} ' + 'описание ' * 30 + '\n\n')
open(sys.argv[1], 'w').write(''.join(body))
PY
want=$(_bl_open_count "$W/B.md")
[ "$want" = 300 ] || exit 2
python3 - "$W/B.md" <<'PY' &
import sys, time
p = sys.argv[1]; a = open(p).read(); b = a.replace('\n\n', '\n\n\n', 1)
end = time.time() + 6; i = 0
while time.time() < end:
    open(p, 'w').write((a, b)[i % 2]); i += 1; time.sleep(0.01)
PY
wp=$!
n=0; bad=0; end=$(( $(date +%s) + 5 ))
while [ "$(date +%s)" -lt "$end" ]; do
    c=$(_bl_open_count "$W/B.md"); n=$((n + 1)); [ "$c" = "$want" ] || bad=$((bad + 1))
done
wait "$wp" 2>/dev/null
echo "чтений $n, неверных $bad"
[ "$bad" = 0 ]
