#!/usr/bin/env bash
# СУДИТ: hooks/backlog-vanish-check.sh hooks/skill-review-check.sh hooks/quality-gate-check.sh hooks/mechanism-has-consumer.sh hooks/git-add-sweep-guard.sh hooks/code-review-reminder.sh hooks/skill-name-ascii-guard.sh hooks/module-doc-check.sh hooks/changelog-reminder.sh
# probe_D519.sh — хуки на `git commit` / `git add` агента не исполняют программ из настроек чужого
# репозитория (D519, брат D515 по тому же корню).
#
# Девять стражей стоят на PreToolUse[Bash] и срабатывают на СОБСТВЕННОМ коммите или `git add` агента:
# смотрят, что уходит в коммит. Они зовут голый git в папке сессии (поле `cwd` входа; каталог процесса —
# тоже она), а голый git исполняет программы из настроек репозитория этой папки ДО того, как команда
# агента пройдёт права.
#
# Замер 6 октября 2026 (git 2.54.0), какая форма вызова что запускает:
#   core.fsmonitor — `diff --cached` в любой форме (--name-only, --name-status, --numstat), `diff --name-only`,
#                    `show :путь` (и на отсутствующем пути), `ls-files`, `grep`, `add --dry-run`, `status`;
#                    НЕ запускают `rev-parse` и `show HEAD:путь`;
#   filter.<драйвер>.clean — `diff --name-only`, `add --dry-run -A|.` (по изменённому файлу дерева);
#   gpg.program при log.showSignature — `log -1 --format=%ct` (форма с форматом тоже);
#   textconv — только патч, `diff --cached` без флагов: `--numstat` его НЕ запускает, и ни один из девяти
#              хуков патча не читает. Носитель оставлен по заказу пункта: контроль рамки подтверждает его
#              патчем, и хук, начавший читать патч, покраснеет.
# Вызовов голого git в девяти хуках больше, чем названо в пункте: `module-doc-check.sh:70`
# (`diff --cached --name-only`) и `changelog-reminder.sh:94` (`diff --name-only` по дереву — тут исполняется
# и clean-фильтр) тоже в счёте; проба доходит до них.
#
# Что каждому хуку нужно, чтобы дойти до своих вызовов git (песочный репозиторий несёт всё сразу;
# номера строк — на 6 октября 2026, до починки):
#   backlog-vanish-check    `git commit -am x`, пункты в BACKLOG.md на HEAD и в дереве, архива нет: `-a` ведёт
#                           к `ls-files --error-unmatch` (233), неотслеживаемый архив — к `ls-files -s|-u`
#                           (252-253) и `show :BACKLOG-archive.md` (243)
#   skill-review-check      staged skills/foo/SKILL.md: `diff --cached --name-only` (220), затем `show :путь` (234)
#   quality-gate-check      то же: 116 и 127
#   mechanism-has-consumer  НОВЫЙ (статус A) staged scripts/newtool.sh: `diff --cached --diff-filter=A` (51),
#                           затем `git grep` (79); хук ищет только `scripts/*.sh|py`, а не `hooks/`
#   git-add-sweep-guard     `git add -A && git commit`, `add --dry-run` непуст (изменённый f.txt, неотслеживаемые
#                           файлы): 186, затем `status` (204)
#   code-review-reminder    staged код больше 80 строк (newtool.sh, 100): numstat (82); входа без расшифровки
#                           хватает, чтобы «прогона не было» и хук дошёл до `log -1` (201)
#   skill-name-ascii-guard  коммит в репозитории: `diff --cached --name-only` (131); без python3 хук молчит раньше git
#   module-doc-check        каталог .claude-docs/modules в репозитории, новый staged модуль: 64, затем 70
#   changelog-reminder      CHANGELOG.md есть и не в staged, staged-код есть; `git add -A` в команде ведёт к
#                           `diff --name-only` (81) после `diff --cached --name-only` (62)
#
# Контроль у каждого хука свой: обёртка `git` первой на PATH пишет журнал вызовов, и хук обязан позвать git
# КАЖДОЙ из перечисленных форм (строки журнала — аргументы, ERE); нет такого вызова — контроль мёртв (код 2),
# а не зелёный. Контроль рамки общий: голый git в песочном репозитории запускает все четыре программы.
# Выхолощенный хук git не зовёт, поэтому прибор выхолащивания получает от пробы код 2, а не 0.
#
# НАЗВАННЫЙ ПРЕДЕЛ: проба гонит вызовы, достижимые из состояния песочницы и команд выше. Ветки, которым нужна
# иная форма команды (`git -C <путь> commit`, `git commit <пути>`, `git add -u`), приводят к тем же вызовам
# git, но здесь не гоняются. Условие снятия: какая-то из этих форм поведёт хук к ДРУГОМУ вызову git (новая
# подкоманда или иной каталог) — тогда форма гоняется отдельным случаем.
#
# Судит дерево `CLAUDSOUL_REPO` (по умолчанию — то, где лежит проба), в песочнице.
# Код: 0 — ни один хук не исполнил чужую программу; 1 — исполнил (хуки и носители названы);
#      2 — проба здесь не исполнима либо контроль мёртв.
set -uo pipefail
# Пробу зовёт «Проверка» пункта, то есть гейт и архиватор: снять их ограду вложенного прогона.
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX CG_LOCAL_BACKLOG
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
H="$REPO/hooks"
HOOKS="backlog-vanish-check skill-review-check quality-gate-check mechanism-has-consumer git-add-sweep-guard code-review-reminder skill-name-ascii-guard module-doc-check changelog-reminder"
for _f in $HOOKS; do
    [ -f "$H/$_f.sh" ] || { echo "проба не исполнима: нет hooks/$_f.sh в $REPO"; exit 2; }
done
for _t in jq python3; do   # python3: разбор команды в command-scope-lib; без него git-add-sweep-guard и skill-name-ascii-guard молчат раньше git
    command -v "$_t" >/dev/null 2>&1 || { echo "проба не исполнима: нет $_t"; exit 2; }
done
REAL_GIT=$(command -v git) || { echo "проба не исполнима: нет git"; exit 2; }

# Песочница с корнем ${HOME}, а не голым mktemp: на раннере CI голый mktemp и есть /tmp, а часть хуков
# дерева (rework-detector, род M) отбрасывает пути `*/tmp/*`. Среди этих девяти такого исключения нет
# (поиск `/tmp` по ним и по общим библиотекам, 6 октября 2026), но рамка не должна зависеть от везения.
W=$(mktemp -d "${HOME}/.probeD519.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/home" "$W/evil"
BAD=""; N=0

# Обёртка git: журнал вызовов, затем настоящий git.
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\n' \"\$*\" >> \"$W/gitlog\"" "exec \"$REAL_GIT\" \"\$@\"" > "$W/bin/git"
chmod +x "$W/bin/git"
# Программы «из настроек»: каждая оставляет свою метку. Фильтр обязан вернуть содержимое.
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.fsmonitor\"" 'exit 1' > "$W/fsm.sh"
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.filter\"" 'cat' > "$W/clean.sh"
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.gpg\"" 'exit 1' > "$W/gpg.sh"
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/ran.textconv\"" 'cat "$1"' > "$W/tc.sh"
chmod +x "$W/fsm.sh" "$W/clean.sh" "$W/gpg.sh" "$W/tc.sh"

# Песочный «чужой» репозиторий. Подписанный коммит руками (заголовок gpgsig, дата 2100 год), затем
# настройки с четырьмя носителями, затем состояние, которого ждут хуки: в HEAD пункты долга, журнал
# изменений, каталог модульных доков и скилл; в индексе — правка скилла и НОВЫЙ скрипт на 100 строк;
# в дереве — правка f.txt (под clean-фильтром) и неотслеживаемые файлы.
(
    export HOME="$W/home"
    cd "$W/evil" && "$REAL_GIT" init -q . >/dev/null 2>&1 || exit 2
    mkdir -p skills/foo scripts .claude-docs/modules docs
    printf 'a\n' > f.txt
    printf '%s\n' '- ☐ **D1** one' '- ☐ **D2** two' > BACKLOG.md
    printf '%s\n' '# Changelog' '## [Unreleased]' > CHANGELOG.md
    printf 'm\n' > .claude-docs/modules/m.md
    printf '%s\n' '---' 'name: foo' '---' 'body' > skills/foo/SKILL.md
    "$REAL_GIT" add . && _t=$("$REAL_GIT" write-tree) || exit 2
    printf 'tree %s\nauthor A <a@example.com> 4102444800 +0000\ncommitter A <a@example.com> 4102444800 +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n ZmFrZQ==\n -----END PGP SIGNATURE-----\n\nfix: probe\n' "$_t" > "$W/commit.txt"
    _c=$("$REAL_GIT" hash-object -t commit -w "$W/commit.txt") && "$REAL_GIT" update-ref HEAD "$_c" || exit 2
    "$REAL_GIT" config core.fsmonitor "$W/fsm.sh" && "$REAL_GIT" config filter.evil.clean "$W/clean.sh" \
        && "$REAL_GIT" config log.showSignature true && "$REAL_GIT" config gpg.program "$W/gpg.sh" \
        && "$REAL_GIT" config diff.tcd.textconv "$W/tc.sh" || exit 2
    printf '%s\n' 'f.txt filter=evil' 'scripts/newtool.sh diff=tcd' > .gitattributes
    printf 'b\n' >> f.txt
    printf 'more\n' >> skills/foo/SKILL.md
    awk 'BEGIN { for (i = 0; i < 100; i++) print "echo " i }' > scripts/newtool.sh
    "$REAL_GIT" add skills/foo/SKILL.md scripts/newtool.sh || exit 2
    printf 'u\n' > docs/untracked.md
) || { echo "проба не исполнима: git не собрал песочный репозиторий"; exit 2; }
EVIL=$(cd "$W/evil" && pwd -P) || exit 2

_reset() { rm -f "$W"/ran.* "$W/gitlog"; }
_ran() { local r="" p; for p in fsmonitor filter gpg textconv; do [ -e "$W/ran.$p" ] && r="$r$p,"; done; printf '%s' "${r%,}"; }

# Контроль рамки: голый git в песочном репозитории запускает все четыре программы.
_reset
( cd "$EVIL" && export HOME="$W/home" && { "$REAL_GIT" status --porcelain; "$REAL_GIT" diff --name-only
  "$REAL_GIT" log -1 --oneline; "$REAL_GIT" diff --cached; } ) >/dev/null 2>&1
[ "$(_ran)" = "fsmonitor,filter,gpg,textconv" ] || { echo "контроль рамки мёртв: голый git запустил только [$(_ran)]"; exit 2; }

# Один прогон хука: свой каталог состояния, обёртка git первой на PATH, песочный HOME. Вход — PreToolUse[Bash]
# с командой агента и папкой сессии = песочный репозиторий; каталог процесса — тоже он.
# CLAUDSOUL_ROOT — владелец проверяемого дерева, как в probe_D515: этим девяти хукам другой корень не нужен.
_run() {   # <хук> <команда агента> <формы git через ';', каждую хук обязан позвать>
    local hook="$1" cmd="$2" c; local -a ctl
    IFS=';' read -ra ctl <<< "$3"
    _reset; mkdir -p "$W/st.$hook"; N=$((N+1))
    jq -cn --arg c "$EVIL" --arg s "d519$hook" --arg m "$cmd" \
        '{session_id:$s, tool_name:"Bash", tool_input:{command:$m}, cwd:$c}' \
      | ( cd "$EVIL" && PATH="$W/bin:$PATH" HOME="$W/home" STATE_DIR="$W/st.$hook" \
            CLAUDSOUL_ROOT="$REPO" bash "$H/$hook.sh" >/dev/null 2>&1 )
    for c in "${ctl[@]}"; do
        # D1095: project_git вставляет `--ignore-submodules=dirty` за status/diff — форма вызова сменилась, предмет нет;
        # флаг снимается из журнала перед сверкой формы (контроль остаётся: подкоманду хук обязан позвать).
        grep -qE -- "(^| )$c( |\$)" <<< "$(sed 's/ --ignore-submodules=dirty//' "$W/gitlog" 2>/dev/null)" \
            || { echo "контроль $hook мёртв: хук не позвал git $c"; exit 2; }
    done
    local r; r=$(_ran); [ -n "$r" ] && BAD="${BAD}${hook} (${r}) "
    return 0
}

# 1. backlog-vanish-check — `-a` и неотслеживаемый архив проводят через все четыре вызова (см. шапку).
_run backlog-vanish-check 'git commit -am x' 'ls-files --error-unmatch;ls-files -s;ls-files -u;show :BACKLOG[^ ]*'
# 2. skill-review-check и 3. quality-gate-check — staged SKILL.md.
_run skill-review-check 'git commit -m x' 'diff --cached --name-only;show :skills/foo/SKILL.md'
_run quality-gate-check 'git commit -m x' 'diff --cached --name-only;show :skills/foo/SKILL.md'
# 4. mechanism-has-consumer — новый staged scripts/newtool.sh.
_run mechanism-has-consumer 'git commit -m x' 'diff --cached --name-only --diff-filter=A;grep -n'
# 5. git-add-sweep-guard — `git add -A`: непустой dry-run, затем перечень неотслеживаемого.
_run git-add-sweep-guard 'git add -A && git commit -m x' 'add --dry-run;status --porcelain'
# 6. code-review-reminder — крупный staged код, входа без расшифровки.
_run code-review-reminder 'git commit -m x' 'diff --cached --numstat;log -1'
# 7. skill-name-ascii-guard — коммит; staged-путь читается первым же вызовом.
_run skill-name-ascii-guard 'git commit -m x' 'diff --cached --name-only'
# 8. module-doc-check — новый staged модуль при каталоге модульных доков.
_run module-doc-check 'git commit -m x' 'diff --cached --name-status;diff --cached --name-only'
# 9. changelog-reminder — `git add -A` в команде: после индекса хук читает и дерево.
_run changelog-reminder 'git add -A && git commit -m x' 'diff --cached --name-only;diff --name-only'

if [ -n "$BAD" ]; then echo "программы из настроек чужого репозитория исполнены: ${BAD}"; exit 1; fi
echo "программы из настроек чужого репозитория не исполнены: хуков проверено $N"
exit 0
