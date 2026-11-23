#!/usr/bin/env bash
set -u
# СУДИТ: hooks/backlog-touch-check.sh hooks/tests/test_backlog_readers_agree_hostile.sh hooks/tests/test_backlog_touch_check.sh
# probe_D1224 — свидетели стража правки, снятые SIGKILL посреди прогона, не оставляют каталога в HOME: фикстура лежит
#   во временном каталоге, который убирает исполнитель, а страж судит правку в ней по корню бэклога, а не по форме пути.
#   Рамка настоящая: каждый свидетель идёт с песочными HOME и TMPDIR, снимается SIGKILL, как только его фикстура
#   появилась; затем страж правки на песочном бэклоге под TMPDIR — правка внутри корня бэклога названа, черновик вне
#   корня (тот же TMPDIR) — нет.
#   0 — в HOME каталогов свидетелей нет, страж различает правку в корне и черновик; 1 — каталог остался в HOME либо
#   страж молчит о правке в корне или говорит о черновике; 2 — нет свидетелей или стража, фикстура не появилась за 30 с.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
G="$PWD/hooks/backlog-touch-check.sh"
for f in "$G" hooks/tests/test_backlog_readers_agree_hostile.sh hooks/tests/test_backlog_touch_check.sh hooks/timeout-lib.sh; do [ -f "$f" ] || exit 2; done
# Рамка исполнителя набора (`run_all.sh`, D1198): свой TMPDIR и подмена `mktemp`, без которой голая форма на macOS уходит
# в системный каталог мимо TMPDIR.
# shellcheck source=/dev/null
. hooks/timeout-lib.sh
command -v cmd_tmpdir_shim >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
bad=0
for t in test_backlog_readers_agree_hostile test_backlog_touch_check; do
    H="$W/$t/home"; X="$W/$t/tmp"; mkdir -p "$H" "$X"
    cmd_tmpdir_shim "$X" || exit 2
    PATH="$X/.bin:$PATH" HOME="$H" TMPDIR="$X" bash "hooks/tests/$t.sh" >/dev/null 2>&1 &
    pid=$!
    i=0
    until [ -n "$(find "$H" "$X" -mindepth 1 -maxdepth 1 \( -name '.claudsoul-test-*' -o -name 'tmp.*' -o -name 'mktemp.*' \) 2>/dev/null | head -1)" ]; do
        i=$((i + 1)); [ "$i" -gt 300 ] && { kill -9 "$pid" 2>/dev/null; echo "$t: фикстура не появилась за 30 с"; exit 2; }
        sleep 0.1
    done
    pkill -9 -P "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    left=$(find "$H" -mindepth 1 -maxdepth 1 -name '.claudsoul-test-*' 2>/dev/null | head -1)
    [ -z "$left" ] || { echo "$t: после SIGKILL в HOME остался ${left##*/}"; bad=1; }
done
# Признак стража: правка внутри корня бэклога судится, черновик вне корня — нет, хотя оба во временном каталоге.
B="$W/g/tmp/proj"; mkdir -p "$B" "$W/g/tmp/scratchpad" "$W/g/s"
printf -- '- ☐ **D9001** пункт пробы\n  **Дефект.** тело называет probe-marker.txt\n' > "$B/BACKLOG.md"
: > "$B/.git"; : > "$B/probe-marker.txt"; : > "$W/g/tmp/scratchpad/probe-marker.txt"
touch_out() {  # <правленый файл>
    printf '{"session_id":"probe-d1224","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$B" "$1" \
        | env -u BACKLOG_CHECKS_NESTED CLAUDSOUL_ROOT="$W/none" STATE_DIR="$W/g/s" bash "$G" 2>/dev/null
}
touch_out "$B/probe-marker.txt" | grep -q D9001 || { echo "страж молчит о правке файла, названного пунктом, в корне бэклога под временным каталогом"; bad=1; }
touch_out "$W/g/tmp/scratchpad/probe-marker.txt" | grep -q D9001 && { echo "страж назвал пункт на черновике вне корня бэклога"; bad=1; }
exit "$bad"
