#!/usr/bin/env bash
set -u
# СУДИТ: hooks/rework-detector.sh hooks/tests/test_rework_detector.sh hooks/tests/test_rework_rerun_streak.sh
# probe_D1268 — детектор переработки судит правку во временном каталоге по КОРНЮ сессии (поле `cwd`), а не по форме пути:
#   цель `…/tmp/proj/t.sh` при каталоге сессии `…/tmp/proj` — файл проекта (правка → прогон → правка даёт «Второй заход»),
#   при чужом каталоге сессии и при соседнем префиксе (`…/tmp/pro`) — черновик (тишина); то же у файлового инструмента
#   (Edit). Свидетели детектора не кладут фикстуру в настоящий HOME ни одним написанием (`${HOME}`, `$HOME`, `~/`).
#   0 — так; 1 — нет; 2 — нет детектора или jq.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
H="$PWD/hooks/rework-detector.sh"
[ -f "$H" ] && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
P="$W/tmp/proj"; mkdir -p "$P" "$W/other"; T="$P/t.sh"; printf 'x\n' > "$T"
hk() {  # <sid> <команда> <каталог сессии>
    jq -cn --arg s "$1" --arg c "$2" --arg d "$3" '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' \
        | STATE_DIR="$W/st" bash "$H" 2>/dev/null
}
chain() {  # <sid> <каталог сессии> → вывод второй правки
    mkdir -p "$W/st"
    jq -cn --arg s "$1" '{session_id:$s, tool_name:"Edit", tool_input:{file_path:"/repo/seed.sh"}}' \
        | STATE_DIR="$W/st" bash "$H" >/dev/null 2>&1
    hk "$1" "printf one > $T" "$2" >/dev/null
    hk "$1" "bash test.sh" "$2" >/dev/null
    hk "$1" "printf two > $T" "$2"
}
bad=0
grep -q 'Второй заход' <<< "$(chain in "$P")" || { echo "цель во временном каталоге внутри каталога сессии не судится как файл проекта"; bad=1; }
grep -q 'Второй заход' <<< "$(chain out "$W/other")" && { echo "цель во временном каталоге вне каталога сессии судится как файл проекта"; bad=1; }
grep -q 'Второй заход' <<< "$(chain pre "$W/tmp/pro")" && { echo "соседний префикс каталога сессии принят за корень цели"; bad=1; }
ed() { jq -cn --arg s "$1" --arg p "$2" --arg d "$3" '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$p}, cwd:$d}' \
        | STATE_DIR="$W/st" bash "$H" 2>/dev/null; }
echain() { ed "$1" /repo/seed.sh "$2" >/dev/null; ed "$1" "$T" "$2" >/dev/null; hk "$1" "bash test.sh" "$2" >/dev/null; ed "$1" "$T" "$2"; }
grep -q 'Второй заход' <<< "$(echain ein "$P")" || { echo "Edit во временном каталоге внутри каталога сессии не судится"; bad=1; }
grep -q 'Второй заход' <<< "$(echain eout "$W/other")" && { echo "Edit во временном каталоге вне каталога сессии судится как файл проекта"; bad=1; }
for f in hooks/tests/test_rework_detector.sh hooks/tests/test_rework_rerun_streak.sh; do
    grep -qE '^[^#]*mktemp[^#|;]*("?\$\{?HOME\}?|~/)' "$f" && { echo "$f кладёт фикстуру в HOME"; bad=1; }
done
exit "$bad"
