#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh
# probe_D1291 — `git stash` и `git stash pop` без правки между ними правкой не засчитываются: файл тот же, что был виден,
# хотя время файла сменилось. Повод (10 ноября 2026, скептик opus по 417c8dc8, D1288, H1; дефект старше D1288): ключ
# строки снимка мира — время файла, а stash/pop переписывают файл; привычная проверка «без моей правки»
# (`git stash -q && bash hooks/tests/…; git stash pop -q`, 54 команды в 587 расшифровках) давала ложный «второй заход»
# после единственной настоящей правки (корень R6: «файл изменился» и «файл переписан тем же содержимым» — одно значение).
# Красная (1), пока stash/pop засчитывается правкой либо дозапись после него не засчитана; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/rework-detector.sh"
[ -f "$HOOK" ] || exit 2
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
# Вне /tmp: детектор отбрасывает временное как черновик (тот же довод у probe_D1287.sh, probe_D1288.sh).
W=$(mktemp -d "${HOME}/.claudsoul-probe-D1291.XXXXXX") || exit 2
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
# Правка с отличимым временем: stash/pop ниже даст время «сейчас», иное, чем у видимой правки.
printf 'b\n' >> "$P/f.sh"; touch -t 202001010000 "$P/f.sh"; call
[ "$(edits)" -eq 1 ] || { echo "рамка: первая правка не засчитана ($(edits))" >&2; exit 2; }
call                                                    # прогон после правки: следующая правка — уже новый заход
( cd "$P" && git stash -q && git stash pop -q ) || exit 2
[ "$(cat "$P/f.sh")" = "$(printf 'a\nb')" ] || { echo "рамка: stash/pop вернул не то содержимое" >&2; exit 2; }
call
n=$(edits)
[ "$n" -eq 1 ] || { echo "stash и pop без правки засчитаны правкой: правок $n вместо 1"; exit 1; }
printf 'c\n' >> "$P/f.sh"; touch -t 202101010000 "$P/f.sh"; call
n=$(edits)
[ "$n" -eq 2 ] || { echo "дозапись после stash/pop не засчитана: правок $n вместо 2"; exit 1; }
# Второе проявление: новый файл написан инструментом Write, прогнан и добавлен `git add` — правка одна, а не две
# (снимок строится без неотслеживаемых файлов, и появление файла в статусе неотличимо от правки).
wr() { jq -cn --arg d "$P" --arg f "$P/n.sh" '{session_id:"s", tool_name:"Write", cwd:$d, tool_input:{file_path:$f}}' \
    | (cd / && env STATE_DIR="$ST" CLAUDE_PROJECT_DIR= bash "$HOOK" >/dev/null 2>&1); }
nedits() { grep -c '"kind":"edit".*n\.sh' "$ST/rework-s.jsonl"; }
printf 'x\n' > "$P/n.sh"; touch -t 202201010000 "$P/n.sh"; wr
[ "$(nedits)" -eq 1 ] || { echo "рамка: запись нового файла не засчитана ($(nedits))" >&2; exit 2; }
call
( cd "$P" && git add n.sh ) || exit 2
call
n=$(nedits)
[ "$n" -eq 1 ] || { echo "git add нового файла без правки засчитан правкой: правок $n вместо 1"; exit 1; }
# Положительный контроль: правка добавленного файла после прогона — правка.
printf 'y\n' >> "$P/n.sh"; touch -t 202301010000 "$P/n.sh"; call
n=$(nedits)
[ "$n" -eq 2 ] || { echo "правка добавленного файла не засчитана: правок $n вместо 2"; exit 1; }
# Скептик opus по a3566bff, H1: первая правка актора — Write нового файла, снимка и журнала ещё нет (живой порядок).
evt() {  # <сессия> <инструмент> <файл или команда>
    if [ "$2" = Bash ]; then jq -cn --arg s "$1" --arg d "$P" --arg c "$3" '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:$c}}'
    else jq -cn --arg s "$1" --arg d "$P" --arg f "$3" '{session_id:$s, tool_name:"Write", cwd:$d, tool_input:{file_path:$f}}'; fi \
        | (cd / && env STATE_DIR="$ST" CLAUDE_PROJECT_DIR= bash "$HOOK" >/dev/null 2>&1); }
printf 'x\n' > "$P/n3.sh"; evt t Write "$P/n3.sh"; evt t Bash true
( cd "$P" && git add n3.sh ) || exit 2
evt t Bash true
n=$(grep -c '"kind":"edit".*n3\.sh' "$ST/rework-t.jsonl")
[ "$n" -eq 1 ] || { echo "git add нового файла после первой правки Write (снимка ещё не было) засчитан правкой: правок $n вместо 1"; exit 1; }
# Скептик opus по a3566bff, H2: новый файл создан оболочкой (форма из перечня), прогнан и добавлен — правка одна.
printf 'x\n' > "$P/n4.sh"; evt s Bash "printf 'x\\n' > n4.sh"
[ "$(grep -c '"kind":"edit".*n4\.sh' "$ST/rework-s.jsonl")" -eq 1 ] || { echo "рамка: создание файла оболочкой не засчитано" >&2; exit 2; }
evt s Bash true
( cd "$P" && git add n4.sh ) || exit 2
evt s Bash true
n=$(grep -c '"kind":"edit".*n4\.sh' "$ST/rework-s.jsonl")
[ "$n" -eq 1 ] || { echo "git add файла, созданного оболочкой, засчитан правкой: правок $n вместо 1"; exit 1; }
exit 0
