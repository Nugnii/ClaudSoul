#!/usr/bin/env bash
# СУДИТ: hooks/paths-lib.sh hooks/rework-detector.sh hooks/impact-inject.sh hooks/bash-write-dispatch.sh hooks/revert-signal.sh hooks/narrative-compose-lib.sh hooks/auto-scanner.sh
# test_project_git.sh — git в чужой папке без программ из её настроек (D515): `project_git`
# и шесть носителей, переведённых на неё (последняя нога гонит пробу пункта: без неё проба жила
# бы только в «Проверке» закрытого пункта, то есть раз в неделю, а не на каждом прогоне).
#
# Нога на каждое условие помощника: fsmonitor; фильтр содержимого из настроек репозитория —
# основной файл, `config.worktree`, `include`; подпись в `log`; фильтр ГЛОБАЛЬНЫХ настроек
# владельца работает (иначе помощник ломал бы git-lfs); вызов из каталога без `-C`; пустой
# набор фильтров под `set -u` на системном bash; фильтр, в имени которого `=` (D1091: `-c ключ=` git делит по первому
# `=`, и такой ключ погашением не задевался). Контроль рамки: голый git в той же песочнице
# запускает все программы — нога, зелёная и на мёртвой рамке, ничего бы не доказывала.
set -uo pipefail
LIB="$(cd "$(dirname "$0")/.." && pwd)/paths-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_GLOBAL="$T/global.cfg" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$T/repo"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

# Программы «из настроек»: каждая оставляет свою метку; фильтры обязаны вернуть содержимое.
for p in loc wt inc glob eq; do printf '%s\n' '#!/bin/sh' "touch \"$T/ran.$p\"" 'cat' > "$T/$p.sh"; done
for p in fsm gpg; do printf '%s\n' '#!/bin/sh' "touch \"$T/ran.$p\"" 'exit 1' > "$T/$p.sh"; done
chmod +x "$T"/*.sh

R="$T/repo"
(
    cd "$R" && git init -q . || exit 1
    for x in f w i g e; do printf 'a\n' > "$x.txt"; done
    git add . && _t=$(git write-tree) || exit 1
    # подписанный коммит собран руками (заголовок gpgsig) — gpg для этого не нужен
    printf 'tree %s\nauthor A <a@example.com> 4102444800 +0000\ncommitter A <a@example.com> 4102444800 +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n ZmFrZQ==\n -----END PGP SIGNATURE-----\n\nsigned\n' "$_t" > "$T/commit.txt"
    _c=$(git hash-object -t commit -w "$T/commit.txt") && git update-ref HEAD "$_c" || exit 1
    git config core.fsmonitor "$T/fsm.sh" && git config filter.loc.clean "$T/loc.sh" || exit 1
    git config core.repositoryformatversion 1 && git config extensions.worktreeConfig true \
        && git config --worktree filter.wt.clean "$T/wt.sh" || exit 1
    printf '[filter "inc"]\n\tclean = %s/inc.sh\n' "$T" > "$T/inc.cfg" && git config include.path "$T/inc.cfg" || exit 1
    git config log.showSignature true && git config gpg.program "$T/gpg.sh" || exit 1
    git config 'filter.e=q.clean' "$T/eq.sh" || exit 1
    printf 'f.txt filter=loc\nw.txt filter=wt\ni.txt filter=inc\ng.txt filter=glob\ne.txt filter=e=q\n' > .gitattributes
    sleep 1; for x in f w i g e; do printf 'b\n' >> "$x.txt"; done
) || { echo "FAIL: песочный репозиторий не собрался"; exit 1; }
printf '[filter "glob"]\n\tclean = %s/glob.sh\n' "$T" > "$GIT_CONFIG_GLOBAL"

reset() { rm -f "$T"/ran.*; }
ran()   { [ -e "$T/ran.$1" ]; }

echo "Контроль рамки: голый git"
# Код голого git не читается намеренно: его исход — метки, их читают строки ниже (D1219).
reset; git -C "$R" status --porcelain >/dev/null 2>&1 || true; git -C "$R" diff --name-only >/dev/null 2>&1 || true; git -C "$R" log -1 >/dev/null 2>&1 || true
_dead=""; for p in fsm loc wt inc glob gpg eq; do ran "$p" || _dead="$_dead $p"; done
if [ -z "$_dead" ]; then ok "голый git запускает все семь программ"
else bad "рамка мертва — голый git не запустил:$_dead"; echo "test_project_git: PASS=$PASS FAIL=$FAIL"; exit 1; fi

. "$LIB" >/dev/null 2>&1
type project_git >/dev/null 2>&1 || { bad "в $LIB нет project_git"; echo "test_project_git: PASS=$PASS FAIL=$FAIL"; exit 1; }

echo "project_git"
reset; OUT=$(project_git -C "$R" status --porcelain 2>/dev/null)
ran fsm && bad "status запустил core.fsmonitor" || ok "status: core.fsmonitor погашен"
grep -q ' M f.txt' <<< "$OUT" && ok "status: вывод верный" || bad "status: вывод испорчен: «${OUT}»"

reset; OUT=$(project_git -C "$R" diff --name-only 2>/dev/null)
ran loc && bad "diff запустил фильтр из основного файла настроек" || ok "diff: фильтр из основного файла погашен"
ran wt  && bad "diff запустил фильтр из config.worktree" || ok "diff: фильтр из config.worktree погашен"
ran inc && bad "diff запустил фильтр из include" || ok "diff: фильтр из include погашен"
ran eq  && bad "diff запустил фильтр с «=» в имени" || ok "diff: фильтр с «=» в имени погашен"
ran glob && ok "diff: фильтр глобальных настроек владельца работает" || bad "diff: погашен и фильтр глобальных настроек владельца"
ran fsm && bad "diff запустил core.fsmonitor" || ok "diff: core.fsmonitor погашен"
grep -qx 'f.txt' <<< "$OUT" && ok "diff: вывод верный" || bad "diff: вывод испорчен: «${OUT}»"

reset; OUT=$(project_git -C "$R" log -1 --oneline 2>/dev/null)
ran gpg && bad "log запустил gpg.program" || ok "log: подпись не проверяется"
grep -q 'signed' <<< "$OUT" && ok "log: вывод верный" || bad "log: вывод испорчен: «${OUT}»"

reset; ( cd "$R" && project_git status --porcelain >/dev/null 2>&1 && project_git diff --name-only >/dev/null 2>&1 )
{ ran fsm || ran loc; } && bad "вызов из каталога без -C запустил программу" || ok "вызов из каталога без -C: программы погашены"

E="$T/empty"; mkdir -p "$E" && git -C "$E" init -q
SYS_BASH=/bin/bash; [ -x "$SYS_BASH" ] || SYS_BASH=bash
RC=$("$SYS_BASH" -c 'set -u; . "$1" >/dev/null 2>&1; project_git -C "$2" status --porcelain >/dev/null 2>&1; echo $?' _ "$LIB" "$E")
[ "$RC" = "0" ] && ok "пустой набор фильтров под set -u ($("$SYS_BASH" -c 'echo $BASH_VERSION'))" || bad "пустой набор фильтров под set -u: код $RC"

# Фильтр из настроек ПОДМОДУЛЯ (D1094): status/diff суперпроекта рекурсируют в подмодуль, и дочерний git исполняет его
# filter.<drv>.clean. Контроль — голый git в суперпроекте ставит метку; смена указателя подмодуля остаётся видна.
SUB="$T/subleak"; mkdir -p "$SUB/marks"
if git -C "$SUB" init -q 2>/dev/null; then :; fi
( mkdir -p "$SUB/subsrc" && cd "$SUB/subsrc" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'aaa\n' > x.txt && git add -A && git commit -qm i
  mkdir -p "$SUB/sup" && cd "$SUB/sup" && git init -q && git config user.email t@t && git config user.name t \
    && git -c protocol.file.allow=always submodule add -q "$SUB/subsrc" sub && git commit -qm add ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_git.sh:$LINENO" >&2; exit 1; }
if [ -d "$SUB/sup/sub" ]; then
    printf 'x.txt filter=s\n' > "$SUB/sup/sub/.gitattributes"
    git -C "$SUB/sup/sub" config filter.s.clean "sh -c 'touch \"$SUB/marks/f\"; cat'"
    sleep 1; printf 'bbb\n' > "$SUB/sup/sub/x.txt"   # грязное рабочее дерево подмодуля, указатель на месте
    # Код голого git не читается намеренно: его исход — метки, их читают строки ниже (D1219).
    rm -f "$SUB/marks/f"; git -C "$SUB/sup" status --porcelain >/dev/null 2>&1 || true
    [ -e "$SUB/marks/f" ] || { bad "контроль подмодуля мёртв — голый git не исполнил фильтр"; }
    if [ -e "$SUB/marks/f" ]; then
        rm -f "$SUB/marks/f"; project_git -C "$SUB/sup" status --porcelain >/dev/null 2>&1
        [ -e "$SUB/marks/f" ] && bad "status исполнил фильтр из настроек подмодуля" || ok "status: фильтр из настроек подмодуля погашен"
        rm -f "$SUB/marks/f"; project_git -C "$SUB/sup" diff --name-only HEAD >/dev/null 2>&1
        [ -e "$SUB/marks/f" ] && bad "diff HEAD исполнил фильтр из настроек подмодуля" || ok "diff HEAD: фильтр из настроек подмодуля погашен"
        # ОБХОД ключом submodule.<имя>.ignore (D1095): -c diff.ignoreSubmodules перебивается им, командная — нет.
        # Атака A — в локальном .git/config; атака B — в ОТСЛЕЖИВАЕМОМ .gitmodules (слабее граница доверия).
        git -C "$SUB/sup" config submodule.sub.ignore none
        rm -f "$SUB/marks/f"; project_git -C "$SUB/sup" status --porcelain >/dev/null 2>&1
        [ -e "$SUB/marks/f" ] && bad "фильтр подмодуля исполнен при submodule.ignore=none в .git/config (D1095)" || ok "подмодуль: submodule.ignore=none в .git/config не включает фильтр"
        git -C "$SUB/sup" config --unset submodule.sub.ignore 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_project_git.sh:$LINENO" >&2; exit 1; }
        git -C "$SUB/sup" config -f "$SUB/sup/.gitmodules" submodule.sub.ignore none
        rm -f "$SUB/marks/f"; project_git -C "$SUB/sup" diff --name-only HEAD >/dev/null 2>&1
        [ -e "$SUB/marks/f" ] && bad "фильтр подмодуля исполнен при submodule.ignore=none в .gitmodules (D1095)" || ok "подмодуль: submodule.ignore=none в .gitmodules не включает фильтр"
        git -C "$SUB/sup" config -f "$SUB/sup/.gitmodules" --unset submodule.sub.ignore 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_project_git.sh:$LINENO" >&2; exit 1; }
        # смена указателя подмодуля остаётся видна (не теряем сигнал ради погашения)
        ( cd "$SUB/sup/sub" && git checkout -q -- x.txt && sleep 1 && printf 'ccc\n' > x.txt && git add x.txt && git -c user.email=t@t -c user.name=t commit -qm moved ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_git.sh:$LINENO" >&2; exit 1; }
        PV=$(project_git -C "$SUB/sup" diff --name-only HEAD 2>/dev/null)
        grep -qx 'sub' <<< "$PV" && ok "смена указателя подмодуля остаётся видна" || bad "смена указателя подмодуля потеряна: «${PV}»"
    fi
else
    echo "  SKIP: подмодуль не собрался (protocol.file.allow?)"
fi

echo "Носители (проба пункта D515)"
PROBE="$(cd "$(dirname "$0")" && pwd)/fixtures/probe_D515.sh"
if command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    POUT=$(CLAUDSOUL_REPO="$(cd "$(dirname "$0")/../.." && pwd)" bash "$PROBE" 2>&1); PRC=$?
    [ "$PRC" = "0" ] && ok "шесть хуков не исполняют программ из чужих настроек" || bad "проба D515: код $PRC — ${POUT}"
else
    echo "  SKIP: проба D515 требует jq и python3"
fi

echo "test_project_git: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL > 0 ))
