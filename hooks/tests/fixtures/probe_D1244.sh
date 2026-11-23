#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh
# probe_D1244 — вызов из подкаталога проекта не стирает снимок мира счётчика повторов. Снимок изменённых файлов
# (`rw_world_targets`) строится проверкой `[ -f "$cwd/$путь" ]`, а путь `git status --porcelain` — от корня репозитория:
# из подкаталога ни один путь не находится, снимок пишется пустым, и следующий вызов из корня засчитывает правкой КАЖДЫЙ
# изменённый файл. Повод — 4 ноября 2026, сессия c4287762: вызов из `hooks/tests` и следующий из корня дали шесть
# строк `edit` разом, и страж разбора завёл повод «третий заход» на нетронутый `hooks/impact-inject.sh`.
# Красная (1), пока нетронутый файл после вызова из подкаталога записан правкой; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/rework-detector.sh"
[ -f "$HOOK" ] || exit 2
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
# Вне /tmp: детектор отбрасывает `*/tmp/*` как временное (тот же довод у `test_rework_detector.sh`, D91).
W=$(mktemp -d "${HOME}/.claudsoul-probe-D1244.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
P="$W/p"; ST="$W/state"; mkdir -p "$P/sub" "$ST"
( cd "$P" && git init -q && printf 'a\n' > f.sh && git add f.sh && git -c user.name=p -c user.email=p@p commit -qm 0 ) || exit 2
printf 'b\n' >> "$P/f.sh"
: > "$ST/rework-s.jsonl"; : > "$ST/rework-c.jsonl"
call() {  # call <сессия> <каталог вызова>
    jq -cn --arg s "$1" --arg d "$2" '{session_id:$s, tool_name:"Bash", cwd:$d, tool_input:{command:"true"}}' \
        | (cd / && env STATE_DIR="$ST" CLAUDE_PROJECT_DIR= bash "$HOOK" >/dev/null 2>&1)
}
edits() { grep -c '"kind":"edit".*f\.sh' "$ST/rework-$1.jsonl"; }
# Положительный контроль отдельной сессией: настоящая правка засчитывается вызовом ИЗ ПОДКАТАЛОГА — иначе проба зелена
# вхолостую и у мутанта «вызов из подкаталога пропускается» (скептик opus по 0ef644fd, L5: контроль из корня его не ловил).
# В сессии сценария он не годится: ложная строка правки делает файл «виденным с прогона», и настоящая правка идёт прогоном.
call c "$P"; printf 'c\n' >> "$P/f.sh"; call c "$P/sub"   # правка — содержимым: ключ снимка — хеш, не время (D1291)
[ "$(edits c)" -eq 1 ] || { echo "рамка: настоящая правка из подкаталога не засчитана — снимок мира не работает" >&2; exit 2; }
call s "$P"; call s "$P/sub"; call s "$P"
bad=$(edits s)
[ "$bad" -eq 0 ] || { echo "вызов из подкаталога стёр снимок: нетронутый f.sh записан правкой ($bad)"; exit 1; }
# Вложенный репозиторий (свой `.git` внутри проекта; так же — рабочая копия worktree, чужой проект): вызов из него не
# переписывает снимок корня (скептик opus по 0ef644fd, M1).
I="$P/inner"; mkdir -p "$I"
( cd "$I" && git init -q && printf 'x\n' > g.sh && git add g.sh && git -c user.name=p -c user.email=p@p commit -qm 0 ) || exit 2
printf 'y\n' >> "$I/g.sh"; : > "$ST/rework-n.jsonl"
call n "$P"; call n "$I"; call n "$P"; call n "$I"
nb=$(grep -c '"kind":"edit"' "$ST/rework-n.jsonl")
[ "$nb" -eq 0 ] || { echo "вызов из вложенного репозитория стёр снимок корня: нетронутые файлы записаны правкой ($nb)"; exit 1; }
echo "вызов из подкаталога и из вложенного репозитория снимка не стирает, настоящая правка засчитана"
exit 0
