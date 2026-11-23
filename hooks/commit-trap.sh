#!/usr/bin/env bash
# commit-trap.sh — ловушки git `commit-msg`, `pre-commit` и `post-commit`: стражи коммита судят тот коммит, который сделает git, — в его репозитории, по его индексу и сообщению, а обход `commit-msg` — по следу прохода.
# en: git `commit-msg`, `pre-commit` and `post-commit` traps: commit guards judge the commit git is about to make — in its repository, by its index and message — and a `commit-msg` bypass by its pass trace.
#
# Результат: коммит в репозиторий с ловушкой судится стражами коммита по его собственному индексу и сообщению; коммит в
# другой репозиторий не получает отказа по состоянию папки сессии и не меняет её индекс (D1022).
# Проверка результата: bash hooks/tests/test_commit_trap.sh даёт 0
#
# Зачем (D1022, решение владельца 21 октября 2026 «Тоже в ловушку git»). Четыре стража коммита стояли на PreToolUse и
# восстанавливали коммит из ТЕКСТА команды: репозиторий — по папке сессии, файлы — по `git add` той же строки, сообщение
# — по `-m`. `git -C <другой> commit` получал отказ по расхождению автотаблиц ClaudSoul, пересборка учёта клала
# `.claude-docs/dep-index.tsv` в индекс папки сессии, а `doc-state:` в файле `-F` не был виден. Универсум форм команды
# открыт (корень R3), а владелец этих фактов — git: его ловушки видят репозиторий, индекс и сообщение готовыми (как суд
# корня в D1021).
#
# ПРЕДШЕСТВЕННИКИ И ИХ СУДЬБА.
#  · `merge-root-gate.sh --commit-msg` (D1021) — ЗОВЁТСЯ первым; его установка `--install` передана сюда и зовёт эту.
#  · `docs-family-check`, `doc-impact-check`, `backlog-vanish-check`, `changelog-reminder` — ЗОВУТСЯ режимом
#    `--commit-msg <файл>` (`doc-impact-check` ещё и `--pre-commit`). На PreToolUse они молчат там, где эта ловушка
#    стоит (`project_commit_trap`, paths-lib.sh), и судят по-прежнему там, где её нет (решение владельца 22 октября 2026
#    «Оставить как сейчас»: в репозитории без ловушки дефект D1022 — названный предел).
#
# Ловушки:
#   commit-msg — стражи по готовому сообщению и индексу; код 1 — коммит не выполнен, причина в stderr; подсказки — в
#                stderr при коде 0 (агент видит их в выводе команды, как прежде видел additionalContext после вызова).
#   pre-commit — пересборка учёта зависимостей в индекс коммита: git строит дерево коммита после pre-commit и до
#                редактора, и `commit-msg` его уже не меняет. Всегда 0.
# Отказ в ловушке — свой код CT_REFUSE_RC (10), а не 1: bash падает кодом 1 сам (`set -u`, нет библиотеки), и упавшая
# подсказка читалась отказом — любой коммит отбивался строкой «Missing throttle-lib.sh» (скептик D1022). Страж с кодом
# вне {0, CT_REFUSE_RC} называется в stderr и коммит не держит. Исключение — суд корня: у него «прибор сломан» — отказ
# (D1021), и любой его ненулевой код держит коммит.
#
#   bash commit-trap.sh --install <репозиторий>  → ставит обе ловушки; 0 · 2 (чужая ловушка, каталог ловушек в рабочем
#                                                   дереве, не репозиторий git). Своей считается ловушка, целиком
#                                                   написанная установкой (вторая строка — её заголовок); чужая с
#                                                   дописанной строкой стража не трогается (скептик D1022: повтор
#                                                   установки затирал её содержимое).
#   bash commit-trap.sh --commit-msg <файл>      → её зовёт git; 0 коммит входит · 1 отказ
#   bash commit-trap.sh --pre-commit             → её зовёт git; 0
#   bash commit-trap.sh --post-commit            → её зовёт git (и при `--no-verify`, и в `cherry-pick`); 0
#
# ОБХОД ЛОВУШКИ (D1023, решение владельца 22 октября 2026 «Только след в git»). Обход ловился словом в команде, а формы
# обхода — открытое множество (псевдоним `ci = commit -n` из настроек). Владелец факта «ловушка судила этот коммит» —
# сама ловушка, поэтому она оставляет СЛЕД, а `post-commit` ловит коммит без следа:
#  · `commit-msg`, пропустив коммит, пишет след прохода «<pid git> <дерево индекса>» (`--git-path claudsoul-trap-pass`);
#  · `post-commit` git исполняет и при `--no-verify`/`-n` (они обходят только `pre-commit` и `commit-msg`) и в
#    `cherry-pick`: нет следа этого же процесса git с этим деревом — обход. Коммит агента (окружение CLAUDECODE или
#    AI_AGENT) суд корня судит готовым (`merge-root-gate.sh --judge-commit`), и непропущенный снимается мягким откатом
#    к прежней вершине (`reset --soft HEAD@{1}`: изменения остаются в индексе). `--no-verify` владельца в терминале —
#    его право: без окружения агента коммит не судится.
# Сверка вершин до и после команды агента (первая редакция D1023) снята: финальный скептик показал, что откат «к
# вершине до команды» уносит законные коммиты параллельной сессии и подтянутую чужую работу, — снимать можно только
# коммит, который сделал этот процесс git, а его знает один `post-commit`.
#
# Пределы: формы, выключающие ВСЕ ловушки разом (`core.hooksPath`, `commit-tree` + `update-ref`, `update-ref` и `push .`
# в main), и намеренная подделка улик агентом (окружение, след) не судятся — агент, решивший обмануть, может переписать
# и сам страж; журнала ссылок нет (`core.logAllRefUpdates=false`, первый коммит) — обход называется, а не снимается:
# прежняя вершина неизвестна, а `HEAD^` при `--amend` унёс бы исходный коммит; стражи-подсказки на обходе молчат —
# `post-commit` судит только корень; `rebase` на main (вершина отсоединена) и слияния ловушки не судят — слияния судит
# PreToolUse merge-root-gate; при `--amend` стражи-подсказки сравнивают индекс с HEAD, а не с HEAD^.
#
# Exit: код вердикта режима.

set -uo pipefail
_HD=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
_p="$_HD/paths-lib.sh"; [ -f "$_p" ] || _p="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$_p" ] && . "$_p" 2>/dev/null
command -v project_git >/dev/null 2>&1 || project_git() { git "$@"; }
: "${COMMIT_TRAP_MARK:=claudsoul-commit-trap}"
# Метка суда корня остаётся в шиме: по ней merge-root-gate на PreToolUse узнаёт, что ловушка стоит (D1021).
ROOT_MARK="claudsoul-merge-root-gate"
GUARDS="merge-root-gate docs-family-check doc-impact-check backlog-vanish-check changelog-reminder"
export CT_REFUSE_RC=10
# Заголовок шима: по нему установка узнаёт СВОЙ файл (вторая строка), а не по метке, которую несёт и совет для чужого.
SHIM_HEAD="# ${COMMIT_TRAP_MARK} ${ROOT_MARK}: стражи коммита судят коммит, который сделает git (D1021, D1022)."

_run() {   # _run <страж> <аргументы...> -> 0 · 1 (отказ); упавший называется
    local g="$1" r; shift
    [ -f "$_HD/$g.sh" ] || return 0
    bash "$_HD/$g.sh" "$@" </dev/null; r=$?
    [ "$r" -eq 0 ] && return 0
    { [ "$r" -eq "$CT_REFUSE_RC" ] || [ "$g" = merge-root-gate ]; } && return 1
    echo "⚠️ страж $g упал в ловушке git (код $r) — его проверка этого коммита не исполнена" >&2
    return 0
}
_git_pid() {   # pid процесса git, позвавшего ловушку: предок с именем git (шим `exec`-ом, чужая ловушка — оболочкой)
    local p=$PPID c i
    for i in 1 2 3 4; do
        c=$(ps -o comm= -p "$p" 2>/dev/null); case "${c##*/}" in git) printf '%s' "$p"; return 0 ;; esac
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); [ -n "$p" ] || break
    done
    return 1
}
_gpath() { project_git -C "$1" rev-parse --path-format=absolute --git-path "$2" 2>/dev/null; }
_agent() { [ -n "${CLAUDECODE:-}${AI_AGENT:-}" ]; }
_own() {   # _own <файл> -> 0, если файл целиком написан установкой (нынешней либо D1021)
    case "$(sed -n 2p "$1" 2>/dev/null)" in
        "# ${COMMIT_TRAP_MARK} ${ROOT_MARK}:"*|"# ${ROOT_MARK}: починка без пункта"*) return 0 ;;
    esac
    return 1
}

case "${1:-}" in
--commit-msg)
    rc=0
    for g in $GUARDS; do _run "$g" --commit-msg "${2:-/dev/null}" || rc=1; done
    # Адреса «файл:строка», которые коммит не тронул, а строку под ними сдвинул (D1251): подсказка в stderr, коммит не
    # держит. Индекс — тот, из которого git соберёт коммит (`GIT_INDEX_FILE`); прибор — у ClaudSoul (ADR-018).
    _lad="${CLAUDSOUL_ROOT:-}/scripts/line-address-drift.py"
    if [ -n "${CLAUDSOUL_ROOT:-}" ] && [ -f "$_lad" ] && command -v python3 >/dev/null 2>&1; then
        _ld=$(python3 "$_lad" --staged 2>/dev/null)
        if [ -n "$_ld" ]; then
            _ldn=$(printf '%s\n' "$_ld" | grep -c .)
            { printf '📍 Коммит сдвинул строки под адресами «файл:строка», которых не тронул (%s) — поправь адрес, если он не датирован (D1251):\n' "$_ldn"
              printf '%s\n' "$_ld" | head -n 20
              [ "$_ldn" -gt 20 ] && printf '  … ещё %s: python3 %s --staged\n' "$((_ldn - 20))" "$_lad"; } >&2
        fi
    fi
    # След прохода (D1023): этот процесс git, это дерево. Дерево — из КОПИИ индекса: `write-tree` над индексом коммита
    # тронул бы его расширения под замком git.
    if [ "$rc" -eq 0 ] && _gp=$(_git_pid); then
        _ix="${GIT_INDEX_FILE:-$(project_git rev-parse --git-path index 2>/dev/null)}"
        case "$_ix" in /*) ;; *) _ix="$PWD/$_ix" ;; esac
        _tc=$(mktemp 2>/dev/null) && cp "$_ix" "$_tc" 2>/dev/null \
            && _tr=$(GIT_INDEX_FILE="$_tc" project_git write-tree 2>/dev/null) && _pf=$(_gpath "$PWD" claudsoul-trap-pass) \
            && printf '%s %s\n' "$_gp" "$_tr" > "$_pf"
        rm -f "$_tc" 2>/dev/null
    fi
    exit $rc ;;
--post-commit)
    ROOT=$(project_git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
    _pf=$(_gpath "$ROOT" claudsoul-trap-pass); _mk=$(cat "$_pf" 2>/dev/null); rm -f "$_pf" 2>/dev/null
    _sha=$(project_git -C "$ROOT" rev-parse -q --verify HEAD 2>/dev/null) || exit 0
    _tr=$(project_git -C "$ROOT" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null)
    # «Проверки» закрытых пунктов архива, задетые коммитом, — фоном, отсоединённым процессом: коммит не ждёт, итог —
    # в очереди напоминаний (D1249, решение владельца 8 ноября 2026). Только из ОСНОВНОГО репозитория ClaudSoul (вершина
    # коммита — корень ClaudSoul по физическому пути): в клоне или рабочей копии `git worktree` фоновый прогон гонялся бы
    # с тем, кто там коммитит (свидетель ловушки — ноги D6, D7b), а «Проверки» архива — о главном дереве.
    _acc="${CLAUDSOUL_ROOT:-}/scripts/archive-checks-after-commit.sh"
    if [ -n "${CLAUDSOUL_ROOT:-}" ] && [ -f "$_acc" ] \
        && [ "$(cd "$ROOT" 2>/dev/null && pwd -P)" = "$(cd "$CLAUDSOUL_ROOT" 2>/dev/null && pwd -P)" ]; then
        # Без GIT_*: ловушка git исполняется с GIT_DIR/GIT_INDEX_FILE коммита, и унаследованные они уводили команды
        # «Проверок» (`git init`, `git config` в песочнице пробы) в этот репозиторий — 8 ноября 2026 проба D515 вписала
        # в его настройки `core.bare = true`, fsmonitor и gpg.program. Тот же снос, что у merge-root-gate.sh (`os.environ.pop`).
        ( cd "$ROOT" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
            -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_PREFIX nohup bash "$_acc" >/dev/null 2>&1 & ) >/dev/null 2>&1
    fi
    # Отметка «чем проверен коммит агента» — критик, тесты или ничем — в журнал состояния, отсоединённым процессом и
    # в любом репозитории с ловушкой; отказа нет, это режим наблюдения (решение владельца 18 ноября 2026, приём из
    # статьи команды Claude Code о проверке). До ветки обхода: отметку получает каждый коммит агента.
    _cst="${CLAUDSOUL_ROOT:-}/scripts/commit-stamp.sh"
    if _agent && [ -n "${CLAUDSOUL_ROOT:-}" ] && [ -f "$_cst" ]; then
        ( cd "$ROOT" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
            -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_PREFIX nohup bash "$_cst" --record "$ROOT" "$_sha" >/dev/null 2>&1 & ) >/dev/null 2>&1
    fi
    _gp=$(_git_pid) && [ "$_mk" = "$_gp $_tr" ] && exit 0
    # `commit-msg` этот коммит не судил — обход. Владелец в терминале — его право (решение владельца 21 октября 2026).
    _agent || exit 0
    _why=$(bash "$_HD/merge-root-gate.sh" --judge-commit "$ROOT" "$_sha" 2>&1 >/dev/null) && exit 0
    # Прежняя вершина — только из журнала ссылок: `HEAD^` при `--amend` не прежняя вершина, и откат к нему унёс бы
    # исходный коммит (скептик D1023, f02b). После удаления ветки `HEAD@{1}` отвечает самим коммитом — это тоже «нет».
    _prev=$(project_git -C "$ROOT" rev-parse -q --verify 'HEAD@{1}' 2>/dev/null) && [ "$_prev" != "$_sha" ] \
        || { printf '⛔ коммит %s вошёл мимо ловушки, и снять его нечем (журнала ссылок нет — прежняя вершина неизвестна):\n%s\nСними сам: git reset --soft <вершина до коммита>.\n' "${_sha}" "${_why}" >&2; exit 0; }
    if project_git -C "$ROOT" reset -q --soft "$_prev" 2>/dev/null; then
        printf '⛔ ОТКАЗ (коммит снят): коммит %s прошёл мимо ловушки git commit-msg (обход), а суд корня его не пропускает:\n%s\nВетка возвращена к %s, изменения остались в индексе. Обход ловушки агенту не даёт пути: сначала пункт с корнем, затем коммит без обхода (D1023).\n' "${_sha}" "${_why}" "${_prev}" >&2
    else
        printf '⛔ коммит %s вошёл мимо ловушки и не снят (reset не прошёл):\n%s\n' "${_sha}" "${_why}" >&2
    fi
    exit 0 ;;
--pre-commit)
    _run doc-impact-check --pre-commit
    exit 0 ;;
--install)
    [ $# -eq 2 ] || { echo "использование: $0 --install <репозиторий>" >&2; exit 2; }
    H=$(project_git -C "$2" rev-parse --path-format=absolute --git-path hooks 2>/dev/null) \
        || { echo "не репозиторий git: $2" >&2; exit 2; }
    # Каталог ловушек внутри рабочего дерева (core.hooksPath на папку проекта) — шим лёг бы файлом проекта с путём этой
    # машины, и ближайший `git add -A` его закоммитил бы (скептик D1021).
    _top=$(cd "$(project_git -C "$2" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null && pwd -P)
    _hd=$(mkdir -p "$H" 2>/dev/null; cd "$H" 2>/dev/null && pwd -P)
    _gd=$(cd "$(project_git -C "$2" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)
    G="$_HD/commit-trap.sh"; Q=${G//\'/\'\\\'\'}
    rc=0
    for t in commit-msg pre-commit post-commit; do
        F="$H/$t"
        # Совет несёт обе метки и адрес после «@ »: по ним PreToolUse узнаёт, что ловушка судит (скептик D1021: без метки
        # дописанная строка судила, а коммиты агента получали вечный отказ «нет ловушки»; скептик D1022: без адреса
        # мёртвая ловушка глушила PreToolUse). Путь вызова — в одинарных кавычках: «.../My Project/».
        if [ "$t" = commit-msg ]; then
            LINE="bash '$Q' --commit-msg \"\$1\" || exit 1  # ${COMMIT_TRAP_MARK} ${ROOT_MARK} @ $G"
        else
            LINE="bash '$Q' --$t  # ${COMMIT_TRAP_MARK} @ $G"
        fi
        case "$_hd/" in "$_gd"/*) ;; "$_top"/*)
            echo "каталог ловушек ${_hd} — внутри рабочего дерева (core.hooksPath): шим лёг бы файлом проекта. Допиши в его $t строку: $LINE" >&2
            rc=2; continue ;;
        esac
        if [ -e "$F" ] && ! _own "$F"; then
            if grep -qF -- "$LINE" "$F" 2>/dev/null; then
                echo "✓ ловушка $t: строка стража уже дописана в чужую ловушку $F — не трогаю"
            else
                echo "в $F стоит чужая ловушка $t — не переписываю. Допиши в неё строку: $LINE" >&2
                rc=2
            fi
            continue
        fi
        printf '%s\n' '#!/bin/sh' "${SHIM_HEAD} Ставит: commit-trap.sh --install" "# ${COMMIT_TRAP_MARK}-target @ $G" \
            "g='${Q}'" '[ -f "$g" ] || exit 0' "exec bash \"\$g\" --$t \"\$@\"" > "$F" && chmod +x "$F" \
            || { echo "ловушка $F не записана" >&2; rc=2; continue; }
        echo "✓ ловушка $t стоит: $F → $G"
    done
    exit $rc ;;
*)
    echo "использование: $0 --install <репозиторий> | --commit-msg <файл> | --pre-commit | --post-commit" >&2
    exit 2 ;;
esac
