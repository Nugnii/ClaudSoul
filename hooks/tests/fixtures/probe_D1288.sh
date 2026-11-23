#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh
# probe_D1288 — отмена коммита правкой не засчитывается: после `git commit` и `git reset --soft HEAD~1` файл снова в
# статусе, но не менялся с прошлого снимка этого репозитория — детектор переработки правку не пишет; дозапись после
# отмены засчитывается, как прежде. Повод (9 ноября 2026, скептик opus по f3bae623, D1287, L1): журнал «edit run run
# edit» — «Второй заход» по нетронутому файлу (корень R6: новая строка статуса несла два состояния).
# Красная (1), пока отмена коммита пишется правкой либо дозапись после неё не засчитана; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/rework-detector.sh"
[ -f "$HOOK" ] || exit 2
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
# Вне /tmp: детектор отбрасывает временное как черновик (тот же довод у probe_D1244.sh и probe_D1287.sh).
W=$(mktemp -d "${HOME}/.claudsoul-probe-D1288.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
P="$W/p"; ST="$W/state"; mkdir -p "$P" "$ST"
( cd "$P" && git init -q && printf 'a\n' > f.sh && git add f.sh && git -c user.name=p -c user.email=p@p commit -qm 0 ) || exit 2
: > "$ST/rework-s.jsonl"
# Вызов-заглушка — запуск скрипта: читающая по роду команда (`true`, `ls`) с D1330 прогоном не считается, а ногам
# ниже нужен прогон между правками.
call() { jq -cn --arg d "$P" '{session_id:"s", tool_name:"Bash", cwd:$d, tool_input:{command:"bash t.sh"}}' \
    | (cd / && env STATE_DIR="$ST" CLAUDE_PROJECT_DIR= bash "$HOOK" >/dev/null 2>&1); }
edits() { grep -c '"kind":"edit".*f\.sh' "$ST/rework-s.jsonl"; }
call                                                    # снимок чистого дерева
printf 'b\n' >> "$P/f.sh"; call
[ "$(edits)" -eq 1 ] || { echo "рамка: первая правка не засчитана ($(edits))" >&2; exit 2; }
( cd "$P" && git -c user.name=p -c user.email=p@p commit -qam 1 ) || exit 2; call
( cd "$P" && git reset -q --soft HEAD~1 ) || exit 2; call
n=$(edits)
[ "$n" -eq 1 ] || { echo "отмена коммита засчитана правкой нетронутого файла: правок $n вместо 1"; exit 1; }
# Время дозаписи — отличимое: в ту же секунду время файла совпало бы с памятью (тот же довод у probe_D1287.sh).
printf 'c\n' >> "$P/f.sh"; touch -t 202101010000 "$P/f.sh"; call
n=$(edits)
[ "$n" -eq 2 ] || { echo "дозапись после отмены коммита не засчитана: правок $n вместо 2"; exit 1; }
exit 0
