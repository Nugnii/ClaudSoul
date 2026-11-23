#!/usr/bin/env bash
# СУДИТ: hooks/impact-inject.sh
# probe_D516.sh — impact-inject не исполняет прибор карты, найденный в папке сессии (D516, брат D514).
#
# D514 закрыл исполнение скрипта проекта, найденного по папке сессии, на Stop. impact-inject
# (Pre- и PostToolUse) делал то же: `scripts/project-graph.py` брался из корня папки сессии и
# исполнялся python3 на каждом Bash и Edit — достаточно открыть сессию в каталоге, где лежит
# файл с этим именем. Правило записано в `.claude/rules/claudsoul-hooks.md`: адрес инструмента
# ClaudSoul берётся у ClaudSoul, а не у проекта сессии.
#
# Контроль: тот же хук при адресе, НАЗВАННОМ владельцем (CLAUDSOUL_ROOT = песочный репозиторий),
# прибор исполняет — рамка жива. Предмет: владелец назвал другой адрес — прибор из папки сессии
# молчит в обеих ветках хука (Bash и Edit).
# Код: 0 — прибор из папки сессии не исполнен; 1 — исполнен; 2 — проба не исполнима либо контроль мёртв.
set -uo pipefail
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX CG_LOCAL_BACKLOG
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/impact-inject.sh"
[ -f "$HOOK" ] || { echo "проба не исполнима: нет hooks/impact-inject.sh в $REPO"; exit 2; }
for _t in jq python3 git; do command -v "$_t" >/dev/null 2>&1 || { echo "проба не исполнима: нет $_t"; exit 2; }; done

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/home" "$W/other" "$W/proj/scripts"
( cd "$W/proj" && git init -q . && printf 'a\n' > a.md && git add a.md \
    && git -c user.email=t@t -c user.name=t commit -qm init && printf 'b\n' >> a.md ) >/dev/null 2>&1 \
    || { echo "проба не исполнима: git не собрал песочный репозиторий"; exit 2; }
P=$(cd "$W/proj" && pwd -P) || exit 2
printf '%s\n' 'import pathlib' "pathlib.Path('$W/ran').touch()" > "$P/scripts/project-graph.py"

_hook() {   # <каталог сессии> <CLAUDSOUL_ROOT> <метка> <tool_name> [ПЕРЕМЕННАЯ=значение …]
    local d="$1" own="$2" tag="$3" tool="$4"; shift 4
    rm -f "$W/ran"
    jq -cn --arg c "$d" --arg s "d516$tag" --arg t "$tool" --arg f "$d/a.md" \
        '{session_id:$s, tool_name:$t, cwd:$c, tool_input:{file_path:$f, command:"true"}}' \
      | ( cd "$d" && env HOME="$W/home" STATE_DIR="$W/st.$tag" CLAUDSOUL_ROOT="$own" CLAUDSOUL_REPO= \
            PATHS_LIB="$REPO/hooks/paths-lib.sh" "$@" bash "$HOOK" >/dev/null 2>&1 )
}
_foreign() {   # <каталог> — чужой репозиторий: тот же прибор под тем же именем, правка в дереве
    mkdir -p "$1/scripts" && ( cd "$1" && git init -q . && printf 'a\n' > a.md && git add a.md \
        && git -c user.email=t@t -c user.name=t commit -qm init && printf 'b\n' >> a.md ) >/dev/null 2>&1 \
        && cp "$P/scripts/project-graph.py" "$1/scripts/" && (cd "$1" && pwd -P)
}

# контроль: главная копия владельца — прибор исполняется в обеих ветках
for _tool in Bash Edit; do
    _hook "$P" "$P" "ctl$_tool" "$_tool"
    [ -e "$W/ran" ] || { echo "контроль $_tool мёртв: хук не исполнил прибор и по адресу, названному владельцем"; exit 2; }
done
# контроль: worktree владельца — тоже его копия, прибор исполняется
( cd "$P" && git add scripts/project-graph.py && git -c user.email=t@t -c user.name=t commit -qm tool \
    && git worktree add -q "$W/wt" ) >/dev/null 2>&1 || { echo "проба не исполнима: worktree не собрался"; exit 2; }
WT=$(cd "$W/wt" && pwd -P) || exit 2
printf 'c\n' >> "$WT/a.md"
_hook "$WT" "$P" ctlwt Bash
[ -e "$W/ran" ] || { echo "контроль worktree мёртв: хук не исполнил прибор в worktree владельца"; exit 2; }

BAD=""; N=0
# предмет: владелец назвал другой адрес — обе ветки
for _tool in Bash Edit; do
    _hook "$P" "$W/other" "subj$_tool" "$_tool"; N=$((N+1))
    [ -e "$W/ran" ] && BAD="${BAD}чужой-адрес-${_tool} "
done
# предмет: адрес владельца пуст (paths-lib не нашёлся): `git -C ""` остаётся в текущем каталоге, то
# есть в папке сессии. Ветка Edit: до прибора она git не зовёт, кроме rev-parse, и без paths-lib
# доходит до него (замер на da9a802c и ecc3248d); ветка Bash без paths-lib обрывается раньше.
_hook "$P" "" nolib Edit PATHS_LIB="$W/none.sh"; N=$((N+1))
[ -e "$W/ran" ] && BAD="${BAD}пустой-адрес-владельца "
# предмет: подделка `.git/commondir` — чужая папка называет общим каталогом git каталог владельца
# (скептик D516 обошёл ею первую редакцию, сверявшую общий каталог git)
F1=$(_foreign "$W/f1") || { echo "проба не исполнима: чужой репозиторий не собрался"; exit 2; }
printf '%s\n' "$P/.git" > "$F1/.git/commondir"
_hook "$F1" "$P" forge Edit; N=$((N+1))
[ -e "$W/ran" ] && BAD="${BAD}подделка-commondir "
# предмет: GIT_COMMON_DIR в окружении хука бьёт `-C` — указывает на каталог git самой чужой папки
F2=$(_foreign "$W/f2") || { echo "проба не исполнима: чужой репозиторий не собрался"; exit 2; }
_hook "$F2" "$P" envcd Edit GIT_COMMON_DIR="$F2/.git"; N=$((N+1))
[ -e "$W/ran" ] && BAD="${BAD}GIT_COMMON_DIR "
# предмет: `core.worktree` в настройках чужой папки уводит её корень в копию владельца (скептик D518)
F3="$W/f3"; git init -q "$F3" && git -C "$F3" config core.worktree "$P" && F3=$(cd "$F3" && pwd -P) \
    || { echo "проба не исполнима: папка с core.worktree не собралась"; exit 2; }
_hook "$F3" "$P" corewt Bash; N=$((N+1))
[ -e "$W/ran" ] && BAD="${BAD}core.worktree "
if [ -n "$BAD" ]; then echo "прибор из папки сессии исполнен: impact-inject — ${BAD}"; exit 1; fi
echo "прибор из папки сессии не исполнен: случаев проверено $N"
exit 0
