#!/usr/bin/env bash
# СУДИТ: hooks/docs-family-check.sh
# probe_D517.sh — docs-family-check не исполняет код из чужой папки сессии (D517, брат D514 и D516).
#
# На `git commit` страж звал генератор автотаблиц `scripts/regen-readme-skills.sh` и сверщик чисел
# `scripts/docs-refresh-claims.sh` из ПАПКИ СЕССИИ — защитой было лишь допущение «в чужом проекте
# файла с таким именем нет». И читал патч голым git: внешний diff и textconv из настроек папки
# сессии исполнялись до того, как команда агента пройдёт права (скептик D517). И считал хеш источника
# производного документа `git hash-object` с фильтрами — clean-фильтр из настроек папки сессии исполнялся.
#
# Случаи: путь A (бамп версии) и путь A2 (правка `hooks/*.sh` без бампа) в чужом проекте; внешний
# diff, textconv, clean-фильтр файла версии (его исполнил бы список файлов и патч, не гаси их `project_git`)
# и clean-фильтр источника производного документа в настройках чужого проекта. Контроли: в копии владельца на пути A исполняются
# генератор и сверщик, на пути A2 — генератор; голый git в чужом проекте запускает внешний diff,
# textconv и оба clean-фильтра. Мёртвый контроль даёт код 2, а не зелёный.
# Код: 0 — код из папки сессии не исполнен; 1 — исполнен; 2 — проба не исполнима либо контроль мёртв.
set -uo pipefail
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX CG_LOCAL_BACKLOG
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/docs-family-check.sh"
[ -f "$HOOK" ] || { echo "проба не исполнима: нет hooks/docs-family-check.sh в $REPO"; exit 2; }
for _t in jq git; do command -v "$_t" >/dev/null 2>&1 || { echo "проба не исполнима: нет $_t"; exit 2; }; done

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/home"
for _m in gen claims ext tc clean cln; do
    printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.$_m\"" 'cat "${1:-/dev/null}" 2>/dev/null; exit 0' > "$W/$_m.sh"
    chmod +x "$W/$_m.sh"
done

_proj() {   # <каталог> <a|a2> — проект с генератором, сверщиком и автотаблицей; a — бамп версии, a2 — правка хука
    mkdir -p "$1/scripts" "$1/hooks" || return 1
    printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.gen\"" > "$1/scripts/regen-readme-skills.sh"
    printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.claims\"" 'exit 0' > "$1/scripts/docs-refresh-claims.sh"
    : > "$1/scripts/doc-claims.tsv"
    printf '%s\n' '# P' '<!-- SKILLS-TABLE:START -->' '<!-- SKILLS-TABLE:END -->' > "$1/README.md"
    printf '1.0.0\n' > "$1/VERSION"; printf 'echo x\n' > "$1/hooks/x.sh"
    ( cd "$1" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 || return 1
    case "$2" in a) printf '1.0.1\n' > "$1/VERSION" ;; a2) printf 'echo y\n' > "$1/hooks/x.sh" ;; esac
    (cd "$1" && pwd -P)
}
_hook() {   # <каталог сессии> <CLAUDSOUL_ROOT> <метка> — один `git commit` агента из папки сессии
    rm -f "$W"/ran.*
    jq -cn --arg c "$1" --arg s "d517$3" \
        '{session_id:$s, tool_name:"Bash", tool_input:{command:"git commit -m x"}, cwd:$c}' \
      | ( cd "$1" && env HOME="$W/home" STATE_DIR="$W/st.$3" CLAUDSOUL_ROOT="$2" CLAUDSOUL_REPO= \
            PATHS_LIB="$REPO/hooks/paths-lib.sh" bash "$HOOK" >/dev/null 2>&1 )
}
_ran() { local r="" m; for m in gen claims ext tc clean cln; do [ -e "$W/ran.$m" ] && r="$r$m,"; done; printf '%s' "${r%,}"; }

O=$(_proj "$W/owner" a) || { echo "проба не исполнима: проект владельца не собрался"; exit 2; }
FA=$(_proj "$W/fa" a) || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
FA2=$(_proj "$W/fa2" a2) || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
FX=$(_proj "$W/fx" a) || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
FT=$(_proj "$W/ft" a) || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
git -C "$FX" config diff.external "$W/ext.sh"
printf 'VERSION diff=tcd\n' > "$FT/.gitattributes"; git -C "$FT" config diff.tcd.textconv "$W/tc.sh"
FH=$(_proj "$W/fh" a) || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
# документ семьи объявлен производным: страж считает хеш его источника, а у источника clean-фильтр
printf '%s\n' '<!-- derived-from: src.md@000000000000 -->' '# P' > "$FH/README.md"; printf 'src\n' > "$FH/src.md"
printf 'src.md filter=evl\n' > "$FH/.gitattributes"; git -C "$FH" config filter.evl.clean "$W/clean.sh"
FC=$(_proj "$W/fc" a) || { echo "проба не исполнима: чужой проект не собрался"; exit 2; }
# файл версии под clean-фильтром: его исполнил бы голый `diff --name-only` и чтение патча
printf 'VERSION filter=cf\n' > "$FC/.gitattributes"; git -C "$FC" config filter.cf.clean "$W/cln.sh"

# контроль рамки: голый git в чужих проектах запускает внешний diff, textconv и оба clean-фильтра
rm -f "$W"/ran.*; git -C "$FX" diff -- VERSION >/dev/null 2>&1; git -C "$FT" diff -- VERSION >/dev/null 2>&1
( cd "$FH" && git hash-object -- "$FH/src.md" ) >/dev/null 2>&1; git -C "$FC" diff --name-only >/dev/null 2>&1
[ "$(_ran)" = "ext,tc,clean,cln" ] || { echo "контроль рамки мёртв: голый git запустил [$(_ran)]"; exit 2; }
# контроль: копия владельца, путь A — генератор и сверщик исполняются
_hook "$O" "$O" ctlA
[ "$(_ran)" = "gen,claims" ] || { echo "контроль пути A мёртв: в копии владельца исполнено [$(_ran)]"; exit 2; }
# контроль: копия владельца, путь A2 (бамп снят, правлен хук) — генератор исполняется
git -C "$O" checkout -q -- VERSION && printf 'echo y\n' > "$O/hooks/x.sh"
_hook "$O" "$O" ctlA2
[ "$(_ran)" = "gen" ] || { echo "контроль пути A2 мёртв: в копии владельца исполнено [$(_ran)]"; exit 2; }

BAD=""; N=0
for _c in "$FA:A" "$FA2:A2" "$FX:внешний-diff" "$FT:textconv" "$FH:производный" "$FC:фильтр-списка"; do
    _d="${_c%%:*}"; _l="${_c##*:}"; N=$((N+1))
    _hook "$_d" "$O" "s$N"
    R=$(_ran); [ -n "$R" ] && BAD="${BAD}${_l}(${R}) "
done
if [ -n "$BAD" ]; then echo "код из папки сессии исполнен: docs-family-check — ${BAD}"; exit 1; fi
echo "код из папки сессии не исполнен: случаев проверено $N"
exit 0
