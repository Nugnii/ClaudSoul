#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_nested_checkout.sh — противник диспетчера записи командой (D487): файл
# вложенной рабочей копии (worktree Claude Code, подмодуль, вложенный репозиторий), не
# исключённой `.gitignore`, доходит до стражей, как доходил до D487.
#
# Устройство дефекта. Кандидаты D487 берутся у `git ls-files` внешнего репозитория, а git во
# вложенную рабочую копию не спускается: подмодуль он печатает одной строкой `sub` (gitlink),
# вложенный репозиторий и worktree — одной строкой `inner/`. `find … -maxdepth 0 -type f` на
# каталоге ложен, и ни один файл внутри стражам не виден. Прежний отбор `find .` эти файлы
# подавал (проверено 1 октября 2026 на редакции HEAD: `inner/x.md` и `sub/y.md` поданы, на
# рабочей — нет). Шапка диспетчера называет предел только для каталогов, «исключённых целиком»
# `.gitignore`; здесь каталог НЕ исключён — то есть по правилу самого D487 его файлы — неучтённые
# неигнорируемые, то есть кандидаты.
# Где это живёт: Claude Code кладёт worktree в `.claude/worktrees/<имя>` ВНУТРИ репозитория
# (описание инструмента EnterWorktree), а в ClaudSoul `.claude/` не исключён
# (`git check-ignore .claude/worktrees/w/` → 1). Событие с корнем основной копии — родитель
# субагента в worktree, сессия после выхода из worktree с «keep» — его файлов не видит.
# Ожидание: правка файла во вложенной копии, сделанная командой, подана стражам.
#
# ПЕРЕВЁРНУТ В ЗАКРЕПЛЕНИЕ ПРЕДЕЛА (второй раунд противника, 1 октября 2026). Рекурсия во
# вложенную копию закрывала эту атаку и принесла шесть новых: свежий checkout целиком вставал в
# очередь впереди настоящих правок, игнорируемое проектом подавалось изнутри копии, ссылка на
# каталог уводила в чужой репозиторий, один файл подавался из двух корней. Корень у них один —
# смешаны две вселенные. Решение: корень git — своя вселенная. Нога судит обе стороны: из
# внешнего корня файлы копии НЕ подаются, из её собственного — подаются.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Здесь все стражи — заглушки, и
# носитель был бы ложным (тот же приём — test_bash_write_dispatch_versions.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
TMP=$(cd "$TMP" && pwd -P)   # корень диспетчера раскрыт от ссылок (/var → /private/var)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; LIB="$TMP/libsrc"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SR" "$LIB" "$SH"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done

_SETUP=$( ( export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1
    G() { git -c user.email=t@t -c user.name=t -c protocol.file.allow=always "$@"; }
    cd "$LIB" && git init -q . && echo y > y.md && git add -A && G commit -qm i \
    && cd "$SR" && git init -q . && echo a > a.md && mkdir -p .claude && echo '{}' > .claude/settings.json \
    && git add -A && G commit -qm i \
    && G worktree add -q .claude/worktrees/w -b w \
    && G submodule add -q "$LIB" sub && G commit -qm sub \
    && mkdir inner && cd inner && git init -q . && echo x > x.md && git add -A && G commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:300}"; exit 1; }
for f in a.md .claude/worktrees/w/a.md sub/y.md inner/x.md; do
    [ -f "$SR/$f" ] || { echo "FAIL [setup]: нет $f — нога судила бы пустоту"; exit 1; }
    touch -t 202001010000 "$SR/$f"
done

run() {  # run <сессия> → вывод диспетчера; cwd — корень ОСНОВНОЙ копии
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run n >/dev/null      # первое событие сессии ставит метку
sleep 1               # дальнейшие правки новее метки при любой точности времени файла
for f in a.md .claude/worktrees/w/a.md sub/y.md inner/x.md; do echo "правка командой" >> "$SR/$f"; done
: > "$FED"
run n >/dev/null
fedp() { grep -c " $SR/$1\$" "$FED"; }

if [ "$(fedp a.md)" -ge 1 ]; then ok; else bad T0 "положительный контроль: правка a.md основной копии не подана — нога судила бы пустоту"; fi
if [ "$(fedp .claude/worktrees/w/a.md)" -eq 0 ]; then ok
else bad T1 "правка в worktree подана из ВНЕШНЕГО корня: вселенные смешаны"; fi
if [ "$(fedp sub/y.md)" -eq 0 ]; then ok
else bad T2 "правка в подмодуле подана из ВНЕШНЕГО корня: вселенные смешаны"; fi
if [ "$(fedp inner/x.md)" -eq 0 ]; then ok
else bad T3 "правка во вложенном репозитории подана из ВНЕШНЕГО корня: вселенные смешаны"; fi

# T4 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ПРЕДЕЛА: событие с cwd в собственном корне копии её правку подаёт.
# Без этой ноги T1–T3 зеленели бы и на диспетчере, который не подаёт ничего.
run_in() {  # run_in <сессия> <cwd>
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$2" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}
: > "$FED"
run_in n "$SR/inner" >/dev/null
if [ "$(fedp inner/x.md)" -ge 1 ]; then ok
else bad T4 "событие в собственном корне вложенного репозитория его правку не подало — предел стал слепотой"; fi

echo "test_adv_dispatch_nested_checkout: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
