#!/usr/bin/env bash
# СУДИТ: hooks/name-consumer-notice.sh hooks/lib/name_consumers.py
# Проба D1200: правка, снимающая с файла чтение переменной окружения, называет потребителя, который её ещё задаёт и
# зовёт этот файл. Нога a — сам повод 31 октября 2026 в песочном дереве: `scripts/backlog-recheck.sh` читает
# `${BACKLOG_ARCHIVE:-…}`, проба соседней сессии задаёт `BACKLOG_ARCHIVE` и зовёт сверщик; правка переименовывает чтение
# в `BACKLOG_RECHECK_ARCHIVE` и оставляет старое имя в комментарии, как было в b6f66dbc, — потребитель обязан быть
# назван адресом. Нога b — тот же потребитель НЕУЧТЁННЫМ файлом (D1240). Нога c — законное: чтение ушло в библиотеку,
# которую файл подключает по имени, — тишина. Нога d — правка командой: файл уже переписан на диске, подача диспетчера.
# Второй читатель имени — `scripts/backlog-archive.sh`, как в живом дереве: сверщик его не называет, и он находку гасить
# не вправе (скептик opus по d0deffd0, M1). Нога e — правка и коммит одной командой (`sed -i … && git commit`): подача
# приходит, когда HEAD уже новая редакция, и судит родителя свежего коммита (M3).
# Код: 0 — все ноги сошлись; 1 — названо, какая нет; 2 — не измерено.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../../.." && pwd -P)"
H="$REPO/hooks/name-consumer-notice.sh"
[ -f "$H" ] && [ -f "$REPO/hooks/lib/name_consumers.py" ] || { echo "нет хука D1200"; exit 2; }
command -v git >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { echo "нет git, jq или python3"; exit 2; }
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1200.XXXXXX") || exit 2
trap 'rm -rf "$S"' EXIT
export STATE_DIR="$S/state"
T="$S/t"; mkdir -p "$T/scripts" "$T/hooks/tests/fixtures"
git -C "$T" init -q && git -C "$T" config user.email p@p && git -C "$T" config user.name p || { echo "git init не прошёл"; exit 2; }
printf '#!/usr/bin/env bash\n_ARCH="${BACKLOG_ARCHIVE:-$REPO/BACKLOG-archive.md}"\necho "$_ARCH"\n' > "$T/scripts/backlog-recheck.sh"
printf '#!/usr/bin/env bash\nBACKLOG_ARCHIVE="$S/a.md" bash "$REPO/scripts/backlog-recheck.sh" --archive\n' > "$T/hooks/tests/fixtures/probe_D1198.sh"
printf '#!/usr/bin/env bash\nARCH="${BACKLOG_ARCHIVE:-$REPO/BACKLOG-archive.md}"\n' > "$T/scripts/backlog-archive.sh"
git -C "$T" add -A && git -C "$T" commit -qm base || { echo "коммит песочницы не прошёл"; exit 2; }
F="$T/scripts/backlog-recheck.sh"
OLD='_ARCH="${BACKLOG_ARCHIVE:-$REPO/BACKLOG-archive.md}"'
NEW='# Путь архива — СВОЯ переменная, не `BACKLOG_ARCHIVE`: ту архиватор получает от сборщика
_ARCH="${BACKLOG_RECHECK_ARCHIVE:-$REPO/BACKLOG-archive.md}"'
ask() { # $1 — сессия, $2 — новая строка
    jq -cn --arg f "$F" --arg o "$OLD" --arg n "$2" --arg s "$1" \
        '{hook_event_name:"PreToolUse", tool_name:"Edit", session_id:$s, tool_input:{file_path:$f, old_string:$o, new_string:$n}}' \
        | bash "$H" 2>&1
}
bad=0
out=$(ask a "$NEW")
grep -q 'hooks/tests/fixtures/probe_D1198.sh:2' <<< "$out" || { echo "a: потребитель повода не назван: ${out:0:200}"; bad=1; }

printf 'BACKLOG_ARCHIVE=/x bash scripts/backlog-recheck.sh\n' > "$T/hooks/tests/fixtures/probe_new.sh"
out=$(ask b "$NEW")
grep -q 'hooks/tests/fixtures/probe_new.sh:1' <<< "$out" || { echo "b: неучтённый потребитель не назван: ${out:0:200}"; bad=1; }
rm -f "$T/hooks/tests/fixtures/probe_new.sh"

printf '#!/usr/bin/env bash\n_ARCH="${BACKLOG_ARCHIVE:-x}"\n' > "$T/scripts/archive-path-lib.sh"
out=$(ask c '. "$(dirname "$0")/archive-path-lib.sh"')
[ -z "$out" ] || { echo "c: чтение через подключённую библиотеку сочтено снятием: ${out:0:200}"; bad=1; }
rm -f "$T/scripts/archive-path-lib.sh"

python3 - "$F" "$OLD" "$NEW" <<'PY' || { echo "правка песочницы не прошла"; exit 2; }
import sys; p, o, n = sys.argv[1:4]; s = open(p).read(); open(p, 'w').write(s.replace(o, n, 1))
PY
out=$(jq -cn --arg f "$F" --rawfile c "$F" '{hook_event_name:"PostToolUse", tool_name:"Write", session_id:"d", tool_input:{file_path:$f, content:$c}}' | bash "$H" 2>&1)
grep -q 'hooks/tests/fixtures/probe_D1198.sh:2' <<< "$out" || { echo "d: подача диспетчера не назвала потребителя: ${out:0:200}"; bad=1; }

git -C "$T" commit -qam rename || { echo "коммит переименования не прошёл"; exit 2; }
out=$(jq -cn --arg f "$F" --rawfile c "$F" '{hook_event_name:"PostToolUse", tool_name:"Write", session_id:"e", tool_input:{file_path:$f, content:$c}}' | bash "$H" 2>&1)
grep -q 'hooks/tests/fixtures/probe_D1198.sh:2' <<< "$out" || { echo "e: коммит той же командой спрятал снятие: ${out:0:200}"; bad=1; }

[ "$bad" -eq 0 ] && echo "потребители убранного имени названы: повод при втором читателе, неучтённый файл, правка командой и коммит той же командой; законное молчит"
exit "$bad"
