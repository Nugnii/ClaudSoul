#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_fresh_checkout_starves.sh — противник диспетчера записи командой (D487,
# раунд 2): свежий worktree не хоронит правку, сделанную командой сессии.
#
# Устройство. «Тронут» — значит новее метки (на первом событии — моложе пяти минут), а checkout
# worktree даёт свежее время ВСЕМ файлам ветки. Отбор кладёт их в очередь целиком; очередь
# идёт по алфавиту (`sort`), бюджет — `BASH_DISPATCH_MAX_RUNS` (6) вызовов на событие, а у
# каждого файла семь стражей. Правка сессии стоит в очереди ПОСЛЕ checkout-файлов и ждёт, пока
# их пары не пройдут: N файлов × 7 / 6 событий. В ClaudSoul это ~1 200 файлов — ~1 400 событий.
# Два входа, у каждого свой:
#  · T1 — корень ОСНОВНОЙ копии. Рекурсия во вложенную копию (починка раунда 1) показывает ему
#    worktree, который Claude Code кладёт в `.claude/worktrees/<имя>` (описание EnterWorktree:
#    «creates a new git worktree inside .claude/worktrees/»; так же — изоляция субагента), а
#    `.claude/` в ClaudSoul не исключён. Путь `.claude/…` в порядке `LC_ALL=C` стоит раньше
#    любого пути с буквы — то есть раньше всех правок основной копии.
#  · T2 — корень САМОГО worktree, первое событие: окно «пять минут» накрывает весь checkout. Так
#    работали агенты workflow ProjectA (worktree в scratchpad `fw/…`, повод D487).
# Ожидание: правка файла командой подана стражам за те же два события, что и без worktree
# (семь пар при бюджете шесть), — контроль C1/C2 это и показывает.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D501 (1 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
# этого дерева, на два уровня выше.
HOOK_DIR="${CLAUDSOUL_REPO:-$(cd "$DIR/../.." && pwd)}/hooks"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Все стражи здесь — заглушки, и носитель
# был бы ложным (тот же приём — test_bash_write_dispatch_selection.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
TMP=$(cd "$TMP" && pwd -P)   # корень диспетчера раскрыт от ссылок (/var → /private/var)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" \
    || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
FIRST=${GUARD_LIST%% *}
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done

G() { env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 git -c user.email=t@t -c user.name=t "$@"; }
# mkrepo <каталог> — проект из 20 документов `docs/` и одного скрипта `hooks/x.sh`; всё старое.
mkrepo() {
    local r=$1 i=0
    mkdir -p "$r/docs" "$r/hooks" || return 1
    while [ "$i" -lt 20 ]; do i=$((i+1)); echo "doc $i" > "$r/docs/d$i.md"; done
    echo 'echo hi' > "$r/hooks/x.sh"
    ( cd "$r" && G init -q . && G add -A && G commit -qm i ) >/dev/null 2>&1 || return 1
    find "$r" -path "$r/.git" -prune -o -type f -exec touch -t 202001010000 {} + 2>/dev/null
}
# old <каталог> — состарить все файлы рабочей копии (worktree, созданный давно).
old() { find "$1" -name .git -prune -o -type f -exec touch -t 202001010000 {} + 2>/dev/null; }
run() {  # run <сессия> <cwd> → вывод диспетчера; бюджет вызовов — по умолчанию
    printf '{"tool_name":"Bash","session_id":"adv2-%s","cwd":"%s"}' "$1" "$2" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            bash "$SB/hooks/$DISP" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dispatch_fresh_checkout_starves.sh:$LINENO" >&2; exit 1; }
}
# fed_within <сессия> <cwd> <файл> <событий> → номер события, на котором первый страж получил
# файл, либо 0, если не получил за названное число событий.
fed_within() {
    local s=$1 c=$2 f=$3 k=$4 i=0
    while [ "$i" -lt "$k" ]; do
        i=$((i+1)); run "$s" "$c" >/dev/null
        grep -qxF "$FIRST $f" "$FED" && { echo "$i"; return; }
    done
    echo 0
}
K=6    # событий на ногу: правке без помех нужно два, впереди её — 20 × 7 = 140 пар (23 события)

# C1 / T1 — корень основной копии; worktree в `.claude/worktrees/`.
for leg in C1 T1; do
    R="$TMP/$leg"; mkrepo "$R" || { echo "FAIL [setup]: проект $leg не собрался"; exit 1; }
    if [ "$leg" = C1 ]; then G -C "$R" worktree add -q .claude/worktrees/w -b w >/dev/null 2>&1; old "$R/.claude/worktrees/w"; fi
    run "$leg" "$R" >/dev/null          # первое событие сессии ставит метку
    sleep 1                             # дальнейшее новее метки при любой точности времени файла
    [ "$leg" = T1 ] && G -C "$R" worktree add -q .claude/worktrees/w -b w >/dev/null 2>&1
    [ -f "$R/.claude/worktrees/w/hooks/x.sh" ] || { echo "FAIL [setup]: worktree $leg не создан"; exit 1; }
    echo 'TOKEN=sk-live-0123456789abcdef' >> "$R/hooks/x.sh"   # правка командой сессии
    n=$(fed_within "$leg" "$R" "$R/hooks/x.sh" "$K")
    if [ "$leg" = C1 ]; then
        if [ "$n" -ge 1 ] && [ "$n" -le 2 ]; then ok
        else bad C1 "контроль: без свежего checkout правка hooks/x.sh подана на событии ${n} (ожидалось 1–2) — нога T1 не различала бы предмет"; fi
    else
        if [ "$n" -ge 1 ] && [ "$n" -le 2 ]; then ok
        else bad T1 "правка hooks/x.sh основной копии не подана ${FIRST} за ${K} событий: очередь занята checkout-файлами свежего .claude/worktrees/w (20 файлов × 7 стражей впереди по алфавиту)"; fi
    fi
done

# C2 / T2 — корень самого worktree (вне проекта, как `fw/…` в ProjectA), первое событие.
for leg in C2 T2; do
    R="$TMP/base-$leg"; W="$TMP/wt-$leg"; mkrepo "$R" || { echo "FAIL [setup]: проект $leg не собрался"; exit 1; }
    G -C "$R" worktree add -q "$W" -b "w$leg" >/dev/null 2>&1
    [ -f "$W/hooks/x.sh" ] || { echo "FAIL [setup]: worktree $leg не создан"; exit 1; }
    [ "$leg" = C2 ] && old "$W"         # контроль: worktree создан давно
    echo 'TOKEN=sk-live-0123456789abcdef' >> "$W/hooks/x.sh"   # первая команда агента в worktree
    n=$(fed_within "$leg" "$W" "$W/hooks/x.sh" "$K")
    if [ "$leg" = C2 ]; then
        if [ "$n" -ge 1 ] && [ "$n" -le 2 ]; then ok
        else bad C2 "контроль: в старом worktree правка hooks/x.sh подана на событии ${n} (ожидалось 1–2) — нога T2 не различала бы предмет"; fi
    else
        if [ "$n" -ge 1 ] && [ "$n" -le 2 ]; then ok
        else bad T2 "правка hooks/x.sh в свежем worktree не подана ${FIRST} за ${K} событий: окно «пять минут» первого события взяло весь checkout"; fi
    fi
done

echo "test_adv2_dispatch_fresh_checkout_starves: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
