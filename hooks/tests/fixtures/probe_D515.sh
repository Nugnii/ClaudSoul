#!/usr/bin/env bash
# СУДИТ: hooks/rework-detector.sh hooks/impact-inject.sh hooks/bash-write-dispatch.sh hooks/revert-signal.sh hooks/narrative-compose-lib.sh hooks/auto-scanner.sh
# probe_D515.sh — хуки, срабатывающие без команды git от агента, не исполняют программ из
# настроек чужого репозитория (D515, брат пути C из D514).
#
# D514 закрыл путь C флагом у одного `git log`. Замер 5 октября 2026 (git 2.54.0): `status`,
# `diff`, `ls-files` исполняют `core.fsmonitor`; `diff --name-only` — ещё и фильтр содержимого
# `filter.<драйвер>.clean` из настроек репозитория; `log` при `log.showSignature` — `gpg.program`.
# Песочный репозиторий несёт все три, и каждый носитель гоняется настоящим входом.
#
# Контроль у каждого хука свой: обёртка `git` первой на PATH пишет журнал вызовов, и хук обязан
# позвать git с подкомандой своего предмета; нет такого вызова — контроль мёртв (код 2), а не
# зелёный. Контроль рамки общий: голый git в песочном репозитории запускает все три программы.
#
# Судит дерево `CLAUDSOUL_REPO` (по умолчанию — то, где лежит проба), в песочнице.
# Код: 0 — ни один хук не исполнил чужую программу; 1 — исполнил (носители названы);
#      2 — проба здесь не исполнима либо контроль мёртв.
set -uo pipefail
# Пробу зовёт «Проверка» пункта, то есть гейт и архиватор: снять их ограду вложенного прогона.
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX CG_LOCAL_BACKLOG

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
H="$REPO/hooks"
for _f in rework-detector.sh impact-inject.sh bash-write-dispatch.sh revert-signal.sh narrative-compose-lib.sh auto-scanner.sh; do
    [ -f "$H/$_f" ] || { echo "проба не исполнима: нет hooks/$_f в $REPO"; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "проба не исполнима: нет jq"; exit 2; }
REAL_GIT=$(command -v git) || { echo "проба не исполнима: нет git"; exit 2; }
# Песочный репозиторий — ТОЛЬКО свой: унаследованные GIT_DIR/GIT_INDEX_FILE (проба, запущенная из ловушки git) уводили
# `git init` и `git config` ниже в репозиторий вызывающего — 8 ноября 2026 в настройки ClaudSoul легли `core.bare = true`,
# fsmonitor и gpg.program этой пробы (D1249).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX

# Песочница с корнем ${HOME}, а не голым mktemp: `rework-detector.sh` отбрасывает пути `*/tmp/*`
# (род M), а на раннере CI голый mktemp и есть /tmp. На пути к предмету пробы это исключение не
# стоит — его ловил бы контроль обёртки git, — но рамка не должна зависеть от этого везения.
# Дефиса в имени нет: автосканер восстанавливает путь проекта, читая каждый дефис как «/».
W=$(mktemp -d "${HOME}/.probeD515.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/home" "$W/evil"
BAD=""

# Обёртка git: журнал вызовов, затем настоящий git.
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\n' \"\$*\" >> \"$W/gitlog\"" "exec \"$REAL_GIT\" \"\$@\"" > "$W/bin/git"
chmod +x "$W/bin/git"
# Программы «из настроек»: каждая оставляет свою метку. Фильтр обязан вернуть содержимое.
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.fsmonitor\"" 'exit 1' > "$W/fsm.sh"
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.filter\"" 'cat' > "$W/clean.sh"
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.gpg\"" 'exit 1' > "$W/gpg.sh"
chmod +x "$W/fsm.sh" "$W/clean.sh" "$W/gpg.sh"

# Песочный «чужой» репозиторий: подписанный коммит руками (заголовок gpgsig, тема fix:, дата
# 2100 год — окна «за N дней» он проходит всегда), затем настройки и правка отслеживаемого файла.
(
    cd "$W/evil" && HOME="$W/home" "$REAL_GIT" init -q . >/dev/null 2>&1 || exit 2
    printf 'a\n' > f.txt && "$REAL_GIT" add f.txt && _t=$("$REAL_GIT" write-tree) || exit 2
    printf 'tree %s\nauthor A <a@example.com> 4102444800 +0000\ncommitter A <a@example.com> 4102444800 +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n ZmFrZQ==\n -----END PGP SIGNATURE-----\n\nfix: probe\n' "$_t" > "$W/commit.txt"
    _c=$("$REAL_GIT" hash-object -t commit -w "$W/commit.txt") && "$REAL_GIT" update-ref HEAD "$_c" || exit 2
    "$REAL_GIT" config core.fsmonitor "$W/fsm.sh" && "$REAL_GIT" config filter.evil.clean "$W/clean.sh" \
        && "$REAL_GIT" config log.showSignature true && "$REAL_GIT" config gpg.program "$W/gpg.sh" || exit 2
    printf 'f.txt filter=evil\n' > .gitattributes
    sleep 1; printf 'b\n' >> f.txt
) || { echo "проба не исполнима: git не собрал песочный репозиторий"; exit 2; }

_reset() { rm -f "$W/ran.fsmonitor" "$W/ran.filter" "$W/ran.gpg" "$W/gitlog"; }
_ran() { local r=""; for p in fsmonitor filter gpg; do [ -e "$W/ran.$p" ] && r="$r$p,"; done; printf '%s' "${r%,}"; }

# Контроль рамки: голый git здесь запускает все три программы.
_reset
( cd "$W/evil" && "$REAL_GIT" status --porcelain && "$REAL_GIT" diff --name-only && "$REAL_GIT" log -1 --oneline ) >/dev/null 2>&1
[ "$(_ran)" = "fsmonitor,filter,gpg" ] || { echo "контроль рамки мёртв: голый git запустил только [$(_ran)]"; exit 2; }
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
EVIL=$(cd "$W/evil" && pwd -P) || exit 2
# Что вносят хуки в песочный репозиторий: дневник с двумя записями (старт сессии), пустой
# прибор карты (без него impact-inject молчит: «другой проект»).
printf '%s\n' '# Session Log' '## 2026-10-04 — a' '- x' '## 2026-10-05 — b' '- y' > "$EVIL/SESSION.md"
mkdir -p "$EVIL/scripts" "$W/lessons" && : > "$EVIL/scripts/project-graph.py"
command -v python3 >/dev/null 2>&1 || { echo "проба не исполнима: нет python3"; exit 2; }

# Один прогон хука: свой каталог состояния, обёртка git первой на PATH, песочный HOME.
_run() {   # <метка> <подкоманда-предмет> <команда…> — stdin хука берётся из $PAYLOAD
    local tag="$1" sub="$2"; shift 2
    _reset; mkdir -p "$W/st.$tag"
    ( cd "$EVIL" && printf '%s' "$PAYLOAD" | PATH="$W/bin:$PATH" HOME="$W/home" STATE_DIR="$W/st.$tag" \
        CLAUDSOUL_ROOT="$REPO" "$@" >/dev/null 2>&1 )
    grep -qE "(^| )$sub( |\$)" "$W/gitlog" 2>/dev/null \
        || { echo "контроль $tag мёртв: хук не позвал git $sub"; exit 2; }
    local r; r=$(_ran); [ -n "$r" ] && BAD="${BAD}${tag} (${r}) "
    return 0
}

# 1. rework-detector — PostToolUse; без журнала сессии выходит до git, журнал заводится заранее.
mkdir -p "$W/st.rework" && : > "$W/st.rework/rework-d515rw.jsonl"
PAYLOAD=$(jq -cn --arg c "$EVIL" '{session_id:"d515rw", tool_name:"Bash", cwd:$c, tool_input:{command:"true"}}')
_run rework status bash "$H/rework-detector.sh"

# 2. impact-inject — PostToolUse[Bash]: изменённое против HEAD и неотслеживаемое, затем учёт карты.
#    С D516 хук работает только в репозитории, чей адрес назвал владелец, — песочница названа им
#    (CLAUDSOUL_ROOT), иначе хук молчит раньше git. Программы из настроек репозитория гасятся и тут.
PAYLOAD=$(jq -cn --arg c "$EVIL" '{session_id:"d515ii", tool_name:"Bash", cwd:$c}')
_run impact diff env CLAUDSOUL_ROOT="$EVIL" bash "$H/impact-inject.sh"
grep -qE '(^| )ls-files( |$)' "$W/gitlog" || { echo "контроль impact мёртв: хук не позвал git ls-files"; exit 2; }

# 3. bash-write-dispatch — PostToolUse[Bash], первое событие пары «сессия+корень»: diff против HEAD.
#    Стражей после git не зовём: их работа к предмету не относится.
PAYLOAD=$(jq -cn --arg c "$EVIL" '{session_id:"d515bw", tool_name:"Bash", cwd:$c}')
_run dispatch diff env BASH_DISPATCH_MAX_RUNS=0 bash "$H/bash-write-dispatch.sh"

# 4. revert-signal — PostToolUse[Bash] на `git commit`: история правок «fix:».
PAYLOAD=$(jq -cn --arg c "$EVIL" '{tool_name:"Bash", tool_input:{command:"git commit -m x"}, cwd:$c}')
_run revert log bash "$H/revert-signal.sh"

# 5. narrative-compose-lib — старт сессии; функция библиотеки вызывается напрямую.
PAYLOAD=""
_run narrative log bash -c '. "$1" >/dev/null 2>&1; narrative_compose "$2" 3 14 "$3"' _ "$H/narrative-compose-lib.sh" "$EVIL" "$W/lessons"

# 6. auto-scanner — по расписанию, целиком подпроцессом: проект из реестра сессий песочницы.
case "$EVIL" in *-*) echo "проба не исполнима: в пути песочницы дефис — автосканер его не восстановит"; exit 2 ;; esac
mkdir -p "$W/projects/$(printf '%s' "$EVIL" | tr '/' '-')"
_run scanner status env PROJECTS_DIR="$W/projects" LESSONS_DIR="$W/lessons" \
    FSRS_SESSION_REGISTRY="$W/none.jsonl" bash "$H/auto-scanner.sh"

if [ -n "$BAD" ]; then echo "программы из настроек чужого репозитория исполнены: ${BAD}"; exit 1; fi
echo "программы из настроек чужого репозитория не исполнены: хуков проверено 6"
exit 0
