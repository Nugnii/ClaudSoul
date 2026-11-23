#!/usr/bin/env bash
# СУДИТ: hooks/doc-impact-check.sh
# probe_D518.sh — doc-impact-check не исполняет код из чужой папки сессии (D518, брат D517).
#
# На `git commit` агента страж брал прибор индекса `scripts/dep-index.py` из корня папки сессии и
# исполнял его python3, если рядом лежал `.claude-docs/dep-index.tsv`: защитой было допущение «в чужом
# проекте файла с таким именем нет». Тем же ходом он читал полный патч голым git — внешний diff из
# настроек папки сессии исполнялся до того, как команда агента пройдёт права.
#
# Случаи: чужой проект с прибором и индексом; он же с внешним diff; он же с clean-фильтром и fsmonitor
# (их исполнили бы голые вызовы git, стой гейт ниже них). Атаки скептика D518 на сверку копии владельца:
# чужой репозиторий на пути устаревшей записи worktree владельца; адрес владельца — не корень git внутри
# чужого репозитория; `core.worktree` чужой папки, уводящий корень в копию владельца. Контроли: прибор
# исполняется в копии владельца, в её подкаталоге и в её привязанном worktree; голый git в чужом проекте
# запускает внешний diff, clean-фильтр и fsmonitor. Мёртвый контроль даёт код 2, а не зелёный.
# Код: 0 — код из папки сессии не исполнен; 1 — исполнен; 2 — проба не исполнима либо контроль мёртв.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/doc-impact-check.sh"
[ -f "$HOOK" ] || { echo "проба не исполнима: нет hooks/doc-impact-check.sh в $REPO"; exit 2; }
for _t in jq git python3; do command -v "$_t" >/dev/null 2>&1 || { echo "проба не исполнима: нет $_t"; exit 2; }; done

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/home"
for _m in ext cln fsm; do
    printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.$_m\"" 'cat "${1:-/dev/null}" 2>/dev/null; exit 0' > "$W/$_m.sh"; chmod +x "$W/$_m.sh"
done

_proj() {   # <каталог> — проект с прибором индекса, индексом и правкой хука в рабочем дереве
    mkdir -p "$1/scripts" "$1/.claude-docs" || return 1
    printf '%s\n' 'import pathlib' "pathlib.Path('$W/ran.idx').touch()" > "$1/scripts/dep-index.py"
    : > "$1/.claude-docs/dep-index.tsv"; printf 'echo x\n' > "$1/a.sh"
    ( cd "$1" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 || return 1
    printf 'echo y\n' > "$1/a.sh"
    (cd "$1" && pwd -P)
}
_hook() {   # <каталог сессии> <CLAUDSOUL_ROOT> <метка> — один `git commit` агента из папки сессии
    rm -f "$W"/ran.*
    jq -cn --arg c "$1" --arg s "d518$3" \
        '{session_id:$s, tool_name:"Bash", tool_input:{command:"git commit -m x"}, cwd:$c}' \
      | ( cd "$1" && env -u DEP_INDEX_TOOL HOME="$W/home" STATE_DIR="$W/st.$3" CLAUDSOUL_ROOT="$2" \
            CLAUDSOUL_REPO= PATHS_LIB="$REPO/hooks/paths-lib.sh" bash "$HOOK" >/dev/null 2>&1 )
}
_ran() { local r="" m; for m in idx ext cln fsm; do [ -e "$W/ran.$m" ] && r="$r$m,"; done; printf '%s' "${r%,}"; }

O=$(_proj "$W/owner") || { echo "проба не исполнима: проект владельца не собрался"; exit 2; }
FI=$(_proj "$W/fi") || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
FX=$(_proj "$W/fx") || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
git -C "$FX" config diff.external "$W/ext.sh"
FF=$(_proj "$W/ff") || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
printf 'a.sh filter=cf\n' > "$FF/.gitattributes"; git -C "$FF" config filter.cf.clean "$W/cln.sh"
git -C "$FF" config core.fsmonitor "$W/fsm.sh"

# контроль рамки: голый git в чужих проектах запускает внешний diff, clean-фильтр и fsmonitor
rm -f "$W"/ran.*; git -C "$FX" diff </dev/null >/dev/null 2>&1; git -C "$FF" diff --name-only </dev/null >/dev/null 2>&1
[ "$(_ran)" = "ext,cln,fsm" ] || { echo "контроль рамки мёртв: голый git запустил [$(_ran)]"; exit 2; }
# контроли: копия владельца, её подкаталог и её привязанный worktree — прибор индекса исполняется
mkdir -p "$O/sub"; OWT="$W/owt"
git -C "$O" worktree add -q "$OWT" >/dev/null 2>&1 && printf 'echo z\n' > "$OWT/a.sh" && OWT=$(cd "$OWT" && pwd -P) \
    || { echo "проба не исполнима: worktree владельца не собрался"; exit 2; }
for _k in "$O:копия" "$O/sub:подкаталог" "$OWT:worktree"; do
    _hook "${_k%%:*}" "$O" "ctl${_k##*:}"
    [ "$(_ran)" = "idx" ] || { echo "контроль мёртв: ${_k##*:} владельца — исполнено [$(_ran)]"; exit 2; }
done
# атаки скептика D518 на сверку копии владельца
git -C "$O" worktree add -q "$W/stale" >/dev/null 2>&1 && mv "$W/stale" "$W/stale.gone" \
    && FK=$(_proj "$W/stale") || { echo "проба не исполнима: устаревшая запись worktree не собралась"; exit 2; }
FL=$(_proj "$W/fl") && mkdir -p "$FL/inner" || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
FJ="$W/fj"; git init -q "$FJ" && git -C "$FJ" config core.worktree "$O" && FJ=$(cd "$FJ" && pwd -P) \
    || { echo "проба не исполнима: папка с core.worktree не собралась"; exit 2; }

BAD=""; N=0
for _c in "$FI|$O|прибор" "$FX|$O|внешний-diff" "$FF|$O|фильтр-и-fsmonitor" "$FK|$O|устаревший-worktree" \
          "$FL|$FL/inner|адрес-не-корень" "$FJ|$O|core.worktree"; do
    _d="${_c%%|*}"; _r="${_c#*|}"; _r="${_r%%|*}"; _l="${_c##*|}"; N=$((N+1))
    _hook "$_d" "$_r" "s$N"
    R=$(_ran); [ -n "$R" ] && BAD="${BAD}${_l}(${R}) "
done
if [ -n "$BAD" ]; then echo "код из папки сессии исполнен: doc-impact-check — ${BAD}"; exit 1; fi
echo "код из папки сессии не исполнен: случаев проверено $N"
exit 0
