#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh
# probe_D1287 — на чистом дереве детектор переработки сохраняет снимок мира, и первая правка после него засчитывается.
# Снимок пишется группой `{ …; } > tmp && mv … || rm`, и её последней командой стояло `[ -n "$_rw_now" ] && printf`:
# без изменённых файлов группа отвечала 1 — тем же кодом, что сбой записи (корень R6), — `mv` пропускался, снимок не
# сохранялся, и следующий вызов молчал, как первый. Повод — CI 9 ноября 2026 по 0cfd2550: ноги D449 свидетеля красные
# на чистой копии; у автора D1244 (475b1cc7) дерево было грязным, и свидетель, судивший живое дерево, был зелёным.
# Красная (1), пока правка после вызова на чистом дереве не засчитана; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/rework-detector.sh"
[ -f "$HOOK" ] || exit 2
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
# Вне /tmp: детектор отбрасывает временное как черновик (тот же довод у probe_D1244.sh).
W=$(mktemp -d "${HOME}/.claudsoul-probe-D1287.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
P="$W/p"; ST="$W/state"; mkdir -p "$P" "$ST"
( cd "$P" && git init -q && printf 'a\n' > f.sh && git add f.sh && git -c user.name=p -c user.email=p@p commit -qm 0 ) || exit 2
: > "$ST/rework-s.jsonl"; : > "$ST/rework-c.jsonl"
call() {  # call <сессия> [каталог, по умолчанию P]
    jq -cn --arg s "$1" --arg d "${2:-$P}" '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:"true"}}' \
        | (cd / && env STATE_DIR="$ST" CLAUDE_PROJECT_DIR= bash "$HOOK" >/dev/null 2>&1)
}
edits() { grep -c '"kind":"edit".*f\.sh' "$ST/rework-$1.jsonl"; }
# Положительный контроль: на ГРЯЗНОМ дереве снимок пишется, и следующая правка засчитывается — рамка умеет ответить «да».
printf 'b\n' >> "$P/f.sh"; call c; printf 'b2\n' >> "$P/f.sh"; call c   # правка — содержимым: ключ — хеш (D1291)
[ "$(edits c)" -eq 1 ] || { echo "рамка: правка на грязном дереве не засчитана — снимок мира не работает" >&2; exit 2; }
printf 'a\n' > "$P/f.sh"
[ -z "$(git -C "$P" status --porcelain --untracked-files=no)" ] || { echo "рамка: дерево не вернулось к чистому" >&2; exit 2; }
call s
[ -f "$ST/rework-world-s.txt" ] || { echo "на чистом дереве снимок мира не сохранён"; exit 1; }
printf 'c\n' >> "$P/f.sh"; call s
n=$(edits s)
[ "$n" -eq 1 ] || { echo "первая правка после чистого дерева не засчитана ($n)"; exit 1; }
# Обрыв записи посредине не подменяет целый снимок обрезанным (скептик opus, M1): снимок — 60 строк чужого репозитория O
# и метка P; вызов из чистого P с пределом размера файла. Прежде последней командой группы на чистом дереве стояла
# `[ -z … ]` с кодом 0 всегда, и оборванная запись шла в `mv`.
printf 'a\n' > "$P/f.sh"
[ -z "$(git -C "$P" status --porcelain --untracked-files=no)" ] || { echo "рамка: дерево P не вернулось к чистому" >&2; exit 2; }
O="$W/o"; mkdir -p "$O"
( cd "$O" && git init -q && for i in $(seq 1 60); do printf 'a\n' > "file_with_a_long_name_number_$i.sh"; done && git add . \
    && git -c user.name=p -c user.email=p@p commit -qm 0 && for i in $(seq 1 60); do printf 'b\n' >> "file_with_a_long_name_number_$i.sh"; done ) || exit 2
: > "$ST/rework-e.jsonl"; call e "$O"; call e "$P"; cp "$ST/rework-world-e.txt" "$W/snap" 2>/dev/null || exit 2
[ "$(wc -c < "$W/snap")" -gt 4096 ] || { echo "рамка: снимок меньше предела записи — обрыва не будет" >&2; exit 2; }
( trap '' XFSZ; ulimit -f 2; head -c 8192 /dev/zero > "$W/big" ) 2>/dev/null
[ "$(wc -c < "$W/big")" -lt 8192 ] || { echo "рамка: предел размера файла не действует" >&2; exit 2; }
jq -cn --arg d "$P" '{session_id:"e", tool_name:"Bash", cwd:$d, tool_input:{command:"true"}}' \
    | (cd / && trap '' XFSZ && ulimit -f 2 && env STATE_DIR="$ST" CLAUDE_PROJECT_DIR= bash "$HOOK" >/dev/null 2>&1)
cmp -s "$W/snap" "$ST/rework-world-e.txt" || { echo "оборванная запись подменила снимок обрезанным"; exit 1; }
exit 0
