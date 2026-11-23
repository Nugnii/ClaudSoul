#!/usr/bin/env bash
# merge-root-gate.sh — PreToolUse[Bash] на `git merge` в main/master и ловушка git `commit-msg` судимых репозиториев: починка без пункта и корня, с пробой не на нуле или с молча изменённым ожиданием теста в главную ветку не входит — ни слиянием, ни прямым коммитом в любой форме команды.
# en: PreToolUse[Bash] on `git merge` into main/master plus a git `commit-msg` trap in judged repositories — refuses a fix that enters the main branch, by merge or by a direct commit in any command form, without a backlog item carrying a root card, with a root probe not at zero and no named limit, or with test expectations changed without a stated reason.
#
# Результат: в main/master проекта с картой корней (ROOTS.md и BACKLOG.md в корне репозитория) вливается только диапазон, где каждый названный пункт несёт корень с карточкой, чек-листом зависимостей и пробой на нуле либо названным пределом, а ожидания тестов не изменены молча; прямой коммит починки (тема fix…/perf…) входит на тех же условиях в любой форме команды — его судит ловушка git `commit-msg` по готовому сообщению и индексу, и тема называет пункт
# Проверка результата: bash hooks/tests/test_merge_root_gate.sh даёт 0
#
# Зачем (решение владельца 9 октября 2026, 00:15: механизмы, которые нельзя проскочить, а не
# правила текстом). Замер ProjectA за 05–08.10.2026: из 10 починок корень записан в ROOTS.md у
# одной; карты «что держится на старом поведении» перед правкой не было ни разу — регрессии
# ловил скептик; находки скептика заводились новыми пунктами (58% новых пунктов), а не
# закрывались в той же ветке; ожидание денежного теста подогнано под дефект (1290 → 1290,02 в
# `web/tests/unit/b189-multi-source-sell-rate.test.ts`, ветка fix/fundsell). Текстом контракт
# карточки стоял в шапке ROOTS.md проекта (уровень 1); здесь он исполняется в той точке, где
# его последствие одно и необратимо, — в слиянии в главную ветку.
#
# ПРЕДШЕСТВЕННИКИ И ИХ СУДЬБА (docs/development.md, «сперва узнай, ЧЕМ вопрос решался раньше»).
#  · `scripts/root-map.py` — ЗОВЁТСЯ: разбор карточки (`parse`) и исполнение пробы
#    (`carriers_of`: носитель — непустая строка не с `#`, код вне {0,1} — прибор сломан) берутся
#    у владельца импортом, своего разбора ROOTS.md здесь нет.
#  · `hooks/backlog-lib.sh` — ЗОВЁТСЯ: пункт и его строка `**Корень.**` берутся у
#    `backlog_open_items` (единственный владелец разбора пункта на поля), со всеми метками.
#  · `hooks/command-scope-lib.sh` — ЗОВЁТСЯ: «это `git merge`?» спрашивается у `is_git_subcommand`.
#  · `hooks/five-whys-gate.sh` — ОБА НУЖНЫ: он требует РАЗБОР в ходе до правки (текст хода), этот —
#    ЗАПИСАННЫЙ результат разбора в мире (карточка, проба) в момент слияния.
#  · `hooks/completion-gate.sh` (Stop) — ОБА НУЖНЫ: он судит «Проверку» пункта на границе хода,
#    этот — связь пункта с корнем и состояние кроны корня на границе ветки.
#  · `backlog-touch-check`, `backlog-vanish-check`, `backlog-open-write-guard` — ОБА НУЖНЫ: их
#    предметы — правка файла из пункта, бесследная пропажа пункта, красная «Проверка» открытого.
#  · `scripts/defect-class-carriers.py` — НЕ ПЕРЕСЕКАЮТСЯ: реестр родов дефекта самого ClaudSoul,
#    а не карта корней проекта.
#  · Реакций на `git merge` в дереве до этого хука не было (git grep по hooks, scripts, lib).
#
# ПРИЗНАКИ (диапазон `<цель>..<ветка>`, текст ветки берётся снимком `git archive` — рабочая копия
# и сама ветка не трогаются) И ПРЕДЕЛ КАЖДОГО:
#  (а) меняется код (не только `*.md`, `.claude-docs/**`, `docs/**`), а ни одна ТЕМА коммита
#      (первая строка сообщения) не называет пункт → «нет пункта». Тема, а не тело: тело
#      пересказывает причины и ссылается на чужие пункты («внесено правкой B437» в пилоте R32 —
#      по телу пилот требовал бы корня у B437). Пределы: пункт — токен темы, который есть пунктом
#      в BACKLOG.md/BACKLOG-archive.md ветки; пункт, названный только в теле, не назван; темы
#      коммитов-слияний не читаются (они пересказывают чужие ветки); номер несуществующего пункта
#      названием не считается.
#  (б) у названного пункта строка `**Корень.** R<N>` с корнем из ROOTS.md ветки либо
#      `**Корень.** не дефект — <причина>`. Судится ЗНАЧЕНИЕ у владельца разбора: первое слово строки,
#      а у «не дефект» — оба слова. Префиксом «не» засчитывалось «нет — разбор не проводился» (D1020),
#      первым словом «не» — «не заведён» и «не разобран» (корня нет). Предел: второй корень в той же
#      строке не проверяется, причина «не дефект» не читается.
#  (в) у карточки корня поле `**Зависимости` (чек-лист регрессии). Предел: судится наличие поля,
#      не его полнота.
#  (г) проба корня (путь — поле «Признак», как у `root-map.py`) печатает носителей, а поля
#      `**Предел` в карточке нет → отказ; проба не объявлена, не найдена, упала (код вне {0,1})
#      или не уложилась в 120 с → отказ словами «прибор сломан». При названном «Пределе» на СЛИЯНИИ
#      проба исполняется и прощается только таймаут; на КОММИТЕ не исполняется вовсе — её ответ вердикт
#      не решает, а проба R5 ClaudSoul дольше 120 с; здоровье пробы — у замера root-map-drift.
#      Проба исполняется в снимке, и снимок — репозиторий git с одним коммитом своего содержимого
#      (переменные GIT_* и глобальные настройки git вызывающего до него не доходят): пробы карты зовут
#      `git grep`, `git rev-parse`, `git archive HEAD`. `CLAUDSOUL_REPO` пробы — снимок,
#      `CLAUDE_PROJECT_DIR` — судимый проект. Предел: в снимке только учтённые git файлы (без
#      node_modules и .env) и один коммит истории; неучтённую зависимость проба берёт из
#      CLAUDE_PROJECT_DIR (R125 ProjectA этого не умеет и получает «прибор сломан»); назван «Предел» —
#      носители больше не судятся, правдивость предела не проверяется.
#  (д) в тест-файле (`*.test.*`, `*.spec.*`, `test_*.py`), который коммит ветки ИЗМЕНИЛ (не
#      создал), удалена строка с числовым литералом внутри ожидания (`expect(`, `toBe(`,
#      `toEqual(`, `toStrictEqual(`, `toBeCloseTo(`, `assert` — до закрытия скобок), а ни одно
#      сообщение диапазона не несёт строку `Ожидание изменено: <причина>` → отказ с файл:строка.
#      Покоммитно, а не от merge-base: у fix/fundsell тест-файл создан в ветке (1290) и ПОДОГНАН
#      в ней же (1290,02) — от merge-base он «новый» и не виден. Не считаются: новые файлы,
#      строка, перенесённая без изменения в том же коммите, строка, вернувшаяся в итоговый файл
#      ветки, `it.fails`/`test.fails`, комментарий. Пределы: скобки считаются без учёта строк;
#      ожидание длиннее 80 строк обрезается; правка внутри коммита-слияния (разрешение
#      конфликта) не видна; одно «Ожидание изменено:» покрывает весь диапазон.
#
# ОБХОДЫ, КОТОРЫХ ХУК НЕ ВИДИТ (названы, не закрыты): `git pull`, `git push . ветка:main`,
# `git reset --hard ветка` на main, `gh pr merge`, переменная или подстановка вместо имени ветки,
# `bash -c "git merge …"`, `git switch main && git merge X` с другой ветки (ветка читается до
# переключения — 39 из 256 слияний ProjectA), `if`/`for`/`{` перед git. Слияние с upstream своей же ветки
# (`git merge origin/main` на main, голый `git merge`) — синхронизация, а не вливание починки: не
# судится; `git fetch && git merge FETCH_HEAD` судится как вливание (ложный отказ синхронизации).
#
# ПРЯМОЙ КОММИТ В MAIN (D1019, D1021). В ClaudSoul с 9 октября 119 коммитов прямо в main и ни одного слияния: страж,
# стоявший на одном `git merge`, не видел пути, которым работа входит в главную ветку, — 13 починок вошли без пункта.
# Тот же суд (а)–(д) — над тем, что войдёт в коммит, и судит его ЛОВУШКА GIT `commit-msg` (`--commit-msg <файл>`), а
# не текст команды: у git готовы сообщение (после редактора; комментарии снимает `git stripspace`) и индекс, который
# станет деревом коммита, вместе с `-a`, путями и `git add` той же строки (git отдаёт его ловушке в GIT_INDEX_FILE).
# Пять редакций разбора текста команды и шесть кругов проверки находили каждый раз новую форму (`bash -c`, `eval`,
# `-am"…"`, `\`, `if`, `git add && git commit` одной командой): универсум форм открыт, а владелец этих фактов — git
# (D1021, корень R3). Судится ПОЧИНКА — тема `fix…`/`perf…` (регистр не важен): тип коммита — заявление автора о его
# роли. Тема — как у git (`format_subject`): первый абзац, строки через пробел; режим очистки сообщения git ловушке не
# сообщает, поэтому оно читается дважды — со снятыми строками-комментариями и без, и пункт обязан быть назван в
# каждом прочтении, где тема — починка. Основа — HEAD, при `--amend` (и сокращениях `--am`…`--amen`) — HEAD^:
# `--amend` узнаётся в аргументах предка-git. Коммит незаконченного слияния судится, как любой. Ручные коммиты
# владельца судятся тоже. Ставит и зовёт ловушку общая ловушка стражей коммита `commit-trap.sh` (D1022); `--install`
# здесь передаёт работу ей.
# PreToolUse на коммите судит обход ловушки (решение владельца 21 октября 2026, «Ловушки git» — по слову): ключи
# коммита `--no-verify` и его сокращения, `-n`; `core.hooksPath` в настройках вызова (любой регистр); настройки git,
# переопределённые окружением вызова или `export` (`GIT_CONFIG_*`, `HOME`, `XDG_CONFIG_HOME`); псевдоним, который
# разворачивается в коммит с обходом (`-c alias.…`, `git config alias.…`). И коммит в судимом main, где ловушки
# нет, — отказ с командой установки.
# Пределы: ловушку не исполняют `cherry-pick`, `revert`, `rebase`, `am`, `commit-tree` и слияние — слияние судит
# PreToolUse выше, прочие не судятся; обход формой вне перечня слов (псевдоним, заданный не агентом; настройка в
# файле, подключённом `include.path`) проходит — универсум форм обхода открыт (корень R3), а слово — решение
# владельца; `--amend` без этого слова в аргументах git (графическая оболочка, нет `ps`) судится от HEAD; `--no-verify`
# владельца в терминале — его право, по слову ловится только агент; слово `--no-verify` в сообщении `-m` даёт ложный
# отказ (сообщение — файлом `-F`); починку под типом `feat:`/`chore:`/`fixup!` страж не судит; без python3 в PATH
# ловушка молчит («инструмента нет»); (д) узнаёт тесты по именам JS/TS и Python. Повтор на истории: из 65 починок
# main с 9 октября остановлены были бы 59 — 13 без пункта, 46 с корнем «нет — …» или вне карты.
#
# ТРИ СОСТОЯНИЯ ПРИБОРА. Нет jq/python3, библиотек или `root-map.py` у ClaudSoul — «инструмента
# здесь нет»: молчание, код 0 (в ловушке коммит входит). Цель не main/master, нет ROOTS.md или BACKLOG.md в корне — не
# наш предмет: молчание. Снимок не извлёкся, git ответил ошибкой, разбор упал — «прибор сломан»:
# ОТКАЗ словами (в ловушке — код 1, коммит не выполнен), потому что молчание читалось бы «чисто».
#
# Цена: снимок ветки (`git archive | tar`, ProjectA 39 МБ — около секунды), его коммит в свой репозиторий (`git add`
# снимка) и пробы названных корней (120 с каждая на свободной машине, под нагрузкой до 280 с — `probe_timeout` в
# `scripts/root-map.py`, D1276; при регистрации хуку нужен `timeout` больше — у него 300 с; проба R6 ClaudSoul в снимке
# идёт около минуты, под нагрузкой 32–49 — 193 с).
#
# Сухой прогон (тот же разбор без `git merge`):
#   bash merge-root-gate.sh --check <репозиторий> <цель> <ветка>  → 0 пропуск · 1 отказ · 2 прибор сломан
# Ловушка коммита (D1021):
#   bash merge-root-gate.sh --install <репозиторий>   → то же, что commit-trap.sh --install; 0 · 2 (чужая ловушка, не git)
#   bash merge-root-gate.sh --commit-msg <файл>       → её зовёт git; 0 коммит входит · 1 отказ, причина в stderr
#   bash merge-root-gate.sh --judge-commit <репозиторий> <коммит> → тот же суд над ГОТОВЫМ коммитом судимого main (дерево
#        коммита, его сообщение, основа — родитель); 0 · 1 отказ · 2 прибор сломан, причина в stderr. Зовёт сверка обхода
#        ловушки (`commit-trap.sh --post-commit`; D1023).
#
# Input  (stdin): {tool_name:"Bash", tool_input:{command}, cwd} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{permissionDecision:"deny", permissionDecisionReason}} либо пусто
# Exit:  0 (в режимах --check, --install, --commit-msg — код вердикта).

set -uo pipefail
_HD=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
for _l in paths-lib.sh backlog-lib.sh command-scope-lib.sh; do
    _p="$_HD/$_l"; [ -f "$_p" ] || _p="$HOME/.claude/hooks/$_l"
    # shellcheck source=/dev/null
    [ -f "$_p" ] && . "$_p" 2>/dev/null
done
# git в чужой папке — через project_git (D519): голый git исполняет программы из её настроек.
command -v project_git >/dev/null 2>&1 || project_git() { git "$@"; }
export -f project_git
RM="${CLAUDSOUL_ROOT:-}/scripts/root-map.py"

# _snap_repo <каталог снимка> — снимок становится репозиторием git с одним коммитом своего содержимого. Пробы карты
# пишутся под root-map.py, а он исполняет их в настоящем репозитории: `git grep`, `git rev-parse`, `git archive HEAD`.
# В голом каталоге проба R6 ClaudSoul падала, и законный коммит получал «прибор сломан», а R2 и R3 печатали пусто, и
# пустота читалась нулём носителей (финальный скептик D1019). Ловушки git снимка отключены, автор свой. Предел: у
# снимка один коммит истории; пробы, читающей историю, нет ни в ClaudSoul, ни в ProjectA (0 из 134, 21 октября 2026).
# Окружение и глобальные настройки git вызывающего до снимка не доходят (волна проверки D1019): переменные GIT_* бьют
# `-C`, и с GIT_DIR снимок ложился коммитом «snapshot» в чужой репозиторий; глобальные core.hooksPath и
# init.templateDir исполняли чужие ловушки в снимке; core.autocrlf и core.safecrlf меняли или роняли `git add`;
# фоновое обслуживание после коммита гонялось с уборкой каталога.
_snap_repo() (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    _sg() { project_git -C "$1" -c core.hooksPath=/dev/null -c init.templateDir= -c core.autocrlf=false \
        -c core.safecrlf=false -c gc.auto=0 -c maintenance.auto=false "${@:2}" 2>/dev/null; }
    _sg "$1" init -q && _sg "$1" add -A -f \
        && _sg "$1" -c commit.gpgsign=false -c user.name=snapshot -c user.email=snapshot@localhost \
            commit -q --no-verify --allow-empty -m snapshot
)

# merge_root_check <репозиторий> <цель> <ветка> → причины отказа в stdout; 0 пропуск · 1 отказ · 2 сломан
merge_root_check() {
    local repo="$1" tgt="$2" br="$3" T rc r
    # Пустой диапазон — «пропуск» только у РАЗРЕШИМЫХ концов: `rev-list` по ветке, которой нет,
    # тоже молчит, и сухой прогон отвечал «пропуск» на опечатку (D524, ProjectA 11 октября 2026).
    for r in "$tgt" "$br"; do
        project_git -C "$repo" rev-parse -q --verify "${r}^{commit}" >/dev/null 2>&1 \
            || { echo "  · ${r}: git не разрешает эту ссылку — прибор сломан, проверено ничего"; return 2; }
    done
    [ -n "$(project_git -C "$repo" rev-list --no-merges -n1 "$tgt..$br" 2>/dev/null)" ] || return 0
    T=$(mktemp -d 2>/dev/null) || { echo "  · временный каталог не создан — прибор сломан"; return 2; }
    trap 'rm -rf "$T"' TERM INT HUP  # срыв по сроку не оставляет снимок (ProjectA — около 100 МБ); SIGKILL не ловится
    mkdir -p "$T/snap"
    if ! project_git -C "$repo" archive --format=tar "$br" 2>/dev/null | tar -x -C "$T/snap" 2>/dev/null; then
        echo "  · снимок ветки ${br} не извлёкся (git archive | tar) — прибор сломан, проверено ничего"
        rm -rf "$T"; return 2
    fi
    _snap_repo "$T/snap" || { echo "  · снимок ветки ${br} не стал репозиторием git (пробы карты зовут git) — прибор сломан, проверено ничего"; rm -rf "$T"; return 2; }
    # Все пункты с их корнем — у владельца разбора: «открытыми» на время вызова названы все метки.
    ( BACKLOG_OPEN_MARKS="${BACKLOG_OPEN_MARKS}${BACKLOG_DONE_MARKS}"
      for _f in BACKLOG.md BACKLOG-archive.md; do backlog_open_items "$T/snap/$_f"; done ) \
        | cut -f1,5 > "$T/items.tsv"
    MODE=merge REPO="$repo" TGT="$tgt" BR="$br" SNAP="$T/snap" ITEMS="$T/items.tsv" _mrg_judge
    rc=$?
    rm -rf "$T"
    return $rc
}

# commit_root_check <репозиторий> <флаги: M (--amend) либо -> <файл сообщения> → причины отказа; 0 пропуск · 1 отказ ·
# 2 сломан. Прямой коммит в main судится теми же признаками, что слияние (D1019): в ClaudSoul с 9 октября 2026 119
# коммитов прямо в main и ни одного слияния — страж на одном `git merge` не видел пути, которым работа входит в главную
# ветку. Судится ПОЧИНКА — тема `fix…`/`perf…` (тип коммита — заявление автора о его роли): из 88 коммитов main с
# кодом без пункта в теме были 16, из них 13 починок, а три прочих — релиз, документы, тесты. Зовётся из ловушки git
# `commit-msg` (D1021): индекс, который git отдаёт ей в GIT_INDEX_FILE, — ровно дерево будущего коммита, с `-a`,
# путями и `git add` той же команды; он и есть снимок (`checkout-index`).
commit_root_check() {
    local repo="$1" flags="$2" mf="$3" T code subj base
    T=$(mktemp -d 2>/dev/null) || { echo "  · временный каталог не создан — прибор сломан"; return 2; }
    trap 'rm -rf "$T"' TERM INT HUP  # срыв по сроку не оставляет снимок; SIGKILL не ловится
    # Сообщение — в ДВУХ прочтениях: со снятыми строками-комментариями (`git stripspace`, знак — из настроек git) и
    # без снятия. Какое из них станет сообщением коммита, решает режим очистки git (редактор, `--cleanup`,
    # commit.cleanup), а его git ловушке не сообщает: снятие всегда съедало тему «fix: …» при `core.commentChar=f`, а
    # git её сохранял (финальный скептик D1021). Поэтому тема — починка, если она починка хоть в одном прочтении, а
    # пункт назван, если он назван в КАЖДОМ прочтении, где тема — починка.
    project_git -C "$repo" stripspace --strip-comments < "$mf" > "$T/strip" 2>/dev/null \
        || { echo "  · сообщение коммита не прочитано (git stripspace) — прибор сломан"; rm -rf "$T"; return 2; }
    # Сообщение и тема идут дальше ФАЙЛАМИ, а не окружением: окружение больше 1 МБ не проходит в exec (ARG_MAX),
    # и законный коммит с длинным сообщением получал «прибор сломан» (финальный скептик D1019).
    # Тема — как у git (pretty.c, format_subject): первый абзац после ведущих пустых строк, строки через пробел.
    # Первая строка вместо абзаца отказывала теме, перенесённой на вторую строку, хотя git и путь слияния (`%s`)
    # видят в ней пункт. Код python: 0 — починка (тема в SUBJF), 3 — не починка.
    TOK="${BACKLOG_ID_TOKEN_RE:-[A-Za-z]+-?[0-9][A-Za-z0-9.-]*}" python3 - "$mf" "$T/strip" "$T/msg" "$T/subj" <<'PY' 2>/dev/null
import itertools, os, re, sys
raw_p, strip_p, msg_p, subj_p = sys.argv[1:5]
dec = lambda p: open(p, "rb").read().decode("utf-8", "replace")
lines = lambda m: (l.rstrip(" \t\r\v\f") for l in m.split("\n"))
subject = lambda m: " ".join(itertools.takewhile(bool, itertools.dropwhile(lambda l: not l, lines(m))))
FIX = re.compile(r"^\s*(fix|perf)(\([^)]*\))?!?:", re.I)
raw, strip = dec(raw_p), dec(strip_p)
open(msg_p, "w", encoding="utf-8").write(strip)
fixes = sorted({s for s in (subject(strip), subject(raw)) if FIX.match(s)})
if not fixes:
    sys.exit(3)
common = set.intersection(*({t.rstrip(".-") for t in re.findall(os.environ["TOK"], s)} for s in fixes))
open(subj_p, "w", encoding="utf-8").write(fixes[0] if len(fixes) == 1 else " ".join(sorted(common)))
PY
    case $? in
        0) ;;
        3) rm -rf "$T"; return 0 ;;
        *) echo "  · тема коммита не прочитана — прибор сломан"; rm -rf "$T"; return 2 ;;
    esac
    # Основа — то, на что ляжет коммит: HEAD, а при --amend — HEAD^ (переписывается сам HEAD); без HEAD — пусто.
    base=$(project_git -C "$repo" rev-parse -q --verify HEAD 2>/dev/null) || base=""
    case "$flags" in *M*) base=$(project_git -C "$repo" rev-parse -q --verify 'HEAD^' 2>/dev/null) || base="" ;; esac
    # Готовый коммит (D1023: сверка после обхода ловушки) судится от своего родителя: флаг «B:<родитель>».
    case "$flags" in B:*) base="${flags#B:}" ;; esac
    # Имена — без экранирования: иначе документ с именем не-ASCII приходит как "docs/\321…" и считается кодом.
    code=$(project_git -C "$repo" -c core.quotePath=false diff --cached --name-only ${base:+"$base"} 2>/dev/null)
    [ -n "$code" ] || { rm -rf "$T"; return 0; }
    printf '%s\n' "$code" > "$T/code"
    mkdir -p "$T/snap"
    if ! project_git -C "$repo" checkout-index -a -f --prefix="$T/snap/" 2>/dev/null; then
        echo "  · снимок индекса не извлёкся (git checkout-index) — прибор сломан, проверено ничего"
        rm -rf "$T"; return 2
    fi
    _snap_repo "$T/snap" || { echo "  · снимок коммита не стал репозиторием git (пробы карты зовут git) — прибор сломан, проверено ничего"; rm -rf "$T"; return 2; }
    ( BACKLOG_OPEN_MARKS="${BACKLOG_OPEN_MARKS}${BACKLOG_DONE_MARKS}"
      for _f in BACKLOG.md BACKLOG-archive.md; do backlog_open_items "$T/snap/$_f"; done ) \
        | cut -f1,5 > "$T/items.tsv"
    MODE=commit REPO="$repo" SNAP="$T/snap" ITEMS="$T/items.tsv" CODEF="$T/code" MSGF="$T/msg" SUBJF="$T/subj" \
        DIFFARGS="--cached ${base:-HEAD}" BASE="${base:-HEAD}" _mrg_judge
    local rc=$?
    rm -rf "$T"
    return $rc
}

# _mrg_judge — признаки (а)–(д) над снимком SNAP и пунктами ITEMS. Окружение: MODE=merge (диапазон TGT..BR) либо
# MODE=commit (файлами: CODEF — файлы коммита, MSGF — его сообщение, SUBJF — тема; DIFFARGS — откуда дифф,
# BASE — основа коммита).
_mrg_judge() {
    RM="$RM" TOK="${BACKLOG_ID_TOKEN_RE:-[A-Za-z]+-?[0-9][A-Za-z0-9.-]*}" python3 - <<'PY'
import base64, importlib.util, os, re, subprocess, sys
from pathlib import Path

E = os.environ
MODE = E.get("MODE", "merge")
REPO, SNAP = E["REPO"], Path(E["SNAP"])
TGT, BR = E.get("TGT", ""), E.get("BR", "")


def git(*a, ok_missing=False):
    p = subprocess.run(["bash", "-c", 'project_git "$@"', "_", "-C", REPO, *a],
                       capture_output=True, encoding="utf-8", errors="replace")
    if p.returncode:
        if ok_missing:
            return None
        raise RuntimeError(f"git {' '.join(a)}: {p.stderr.strip()[:200]}")
    return p.stdout


NOT_CODE = re.compile(r"(\.md$|^\.claude-docs/|^docs/)")


def main():
    out = []
    if MODE == "commit":
        rd = lambda k: open(E[k], encoding="utf-8").read()
        code = [f for f in rd("CODEF").splitlines() if f and not NOT_CODE.search(f)]
        msgs, full, rng = rd("SUBJF"), rd("MSGF"), None
    else:
        rng = f"{TGT}..{BR}"
        base = git("merge-base", TGT, BR).strip()
        code = [f for f in git("-c", "core.quotePath=false", "diff", "--name-only", base, BR).splitlines()
                if f and not NOT_CODE.search(f)]
        # Пункт называет ТЕМА коммита: тело пересказывает причины и ссылается на чужие пункты
        # («внесено правкой B437» в пилоте R32) — ссылка там не заявка на починку.
        msgs, full = git("log", "--no-merges", "--format=%s", rng), None
    items = {}
    for line in open(E["ITEMS"], encoding="utf-8", errors="replace"):
        i, _, r = line.rstrip("\n").partition("\t")
        if i and (r or i not in items):
            items[i] = r
    named = sorted({t.rstrip(".-") for t in re.findall(E["TOK"], msgs)} & set(items))

    # (а) код без пункта
    if code and not named and MODE == "commit":
        out.append(f"нет пункта: починка меняет код ({len(code)} файл., напр. {code[0]}), а тема коммита не "
                   "называет пункт бэклога. Почини: сначала разбор — пункт с «**Корень.** R<N>» из карты корней "
                   "(либо «не дефект — <причина>»), затем коммит с номером пункта в теме.")
    elif code and not named:
        out.append(f"нет пункта: меняется код ({len(code)} файл., напр. {code[0]}), а ни одно сообщение "
                   "коммита не называет пункт бэклога. Почини: назови пункт в сообщении коммита ветки "
                   "(пустой коммит `git commit --allow-empty -m '… (B<N>)'` тоже годится).")

    # (б) у каждого названного пункта — корень
    need = {}
    for i in named:
        r = items[i]
        # «не дефект — …»: владелец разбора (backlog_open_items) отдаёт значение «не дефект» двумя словами, и
        # сравнивается ЗНАЧЕНИЕ, а не начало строки. Префикс «не» засчитывал «нет — разбор не проводился» (D1020,
        # 38 пунктов долга и архива ClaudSoul), первое слово «не» — «не заведён» и «не разобран» (7 пунктов ProjectA,
        # 1 blalb: корня нет). Строчными, как в форме: «Не …» в долге — отрицание в разборе (2 из 2).
        if r == "не дефект":
            continue
        m = re.match(r"R\d+", r)
        if not m and r.lower() == "нет":
            out.append(f"{i}: «**Корень.** нет — …» — это не корень, а его отсутствие. Почини: разбор «почему» до "
                       "корня и строка `**Корень.** R<N>` (карточка в ROOTS.md — до кода) либо "
                       "`**Корень.** не дефект — <причина>`.")
        elif not m and r:
            out.append(f"{i}: «**Корень.** {r} …» — не корень: корень — `**Корень.** R<N>` с карточкой в ROOTS.md "
                       "либо `**Корень.** не дефект — <причина>`; «не заведён», «не разобран», «гипотеза» значат, что "
                       "корня ещё нет. Почини: разбор «почему» до корня и строка `**Корень.**` с ним.")
        elif not m:
            out.append(f"{i}: нет строки `**Корень.** R<N>` (либо `**Корень.** не дефект — <причина>`). "
                       "Почини: карточка корня в ROOTS.md ДО кода (поля — шапка карты, образец R32 ProjectA), "
                       "строка `**Корень.**` в пункте.")
        else:
            need.setdefault(m.group(), []).append(i)

    if need:
        cards = {}
        if (SNAP / "ROOTS.md").is_file():
            os.environ["ROOTS_MAP"] = str(SNAP / "ROOTS.md")
            # Корень пробы — снимок: строка входа каждой пробы идёт в `CLAUDSOUL_REPO`, если он задан, и иначе
            # проба судила бы настоящее дерево. Переменные GIT_* бьют `-C` и увели бы её git в чужой репозиторий.
            os.environ["CLAUDSOUL_REPO"] = str(SNAP)
            # Неучтённые зависимости (node_modules) в снимок не попадают; проба тянет их из проекта по
            # CLAUDE_PROJECT_DIR (так ProjectA R124 и R126). Переменная окружения — проект СЕССИИ, а хук может судить
            # чужой репозиторий (`git -C …`), поэтому здесь — судимый (волна проверки D1019: R125 ProjectA).
            os.environ["CLAUDE_PROJECT_DIR"] = REPO
            spec = importlib.util.spec_from_file_location("root_map", E["RM"])
            rm = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(rm)
            cards = {c["id"]: c for c in rm.parse((SNAP / "ROOTS.md").read_text(encoding="utf-8"))}
        for R, its in sorted(need.items()):
            who = ", ".join(its)
            c = cards.get(R)
            if not c:
                out.append(f"{who}: корень {R} не найден в ROOTS.md ветки. Почини: заведи карточку {R}.")
                continue
            raw = c["raw"]
            body = " ".join(raw.values())
            # (в) чек-лист регрессии
            if not any(k.startswith("зависимости") for k in raw) and "**Зависимости" not in body:
                out.append(f"{R} ({who}): в карточке нет поля `**Зависимости (чек-лист регрессии).**` — что "
                           "держится на нынешнем поведении (вызывающие, читатели, тесты с числами, инварианты). "
                           "Почини: впиши поле и прогони список после правки.")
            # (г) проба корня. На КОММИТЕ при названном «Пределе» проба не исполняется: её ответ вердикт не решает,
            # а цена реальна — проба R5 ClaudSoul дольше 120 с, каждая починка пункта R5 ждала бы две минуты, и
            # потомки пробы жили после вердикта (волна проверки D1019). Здоровье пробы — у замера root-map-drift
            # (scripts/measurements.tsv, `root-map.py --check`). На СЛИЯНИИ проба исполняется и при пределе, и
            # прощается только таймаут; текст таймаута — у владельца пробы, scripts/root-map.py, carriers_of.
            has_limit = any(k.startswith("предел") for k in raw) or "**Предел" in body
            if has_limit and MODE == "commit":
                continue
            gitv = {k: os.environ.pop(k) for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
                                                    "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES")
                    if k in os.environ}
            try:
                cars, why = rm.carriers_of(c)
            finally:
                os.environ.update(gitv)
            if why and has_limit and "не уложилась" in why:
                continue
            if why:
                out.append(f"{R} ({who}): проба корня не исполнилась — {why}. Прибор сломан, ноль носителей не "
                           f"доказан. Почини пробу (поле «Признак» — путь `scripts/probes/{R}.sh`).")
            elif cars and not has_limit:
                show = "; ".join(x.strip() for x in cars[:3]) + (f"; … ещё {len(cars) - 3}" if len(cars) > 3 else "")
                out.append(f"{R} ({who}): проба корня не дошла до нуля ({len(cars)} носит.: {show}), и предел не "
                           "назван. Почини в ЭТОЙ ветке — находки того же корня не уходят новым пунктом; "
                           "либо назови в карточке `**Предел.**` — что осталось и почему.")

    # (д) ожидания тестов
    if full is None:
        full = git("log", "--format=%B", rng)
    if not re.search(r"(?m)^\s*Ожидание изменено:\s*\S", full):
        hits = expectation_hits(rng) if MODE == "merge" else staged_expectation_hits()
        if hits:
            show = "\n      ".join(hits[:8]) + (f"\n      … и ещё {len(hits) - 8}" if len(hits) > 8 else "")
            where = "в сообщении коммита" if MODE == "commit" else "в сообщении коммита ветки"
            out.append("ожидание теста изменено без объявления — удалена строка с числом внутри ожидания:\n      "
                       f"{show}\n    Почини: верни ожидание, если оно подогнано под дефект; если меняется "
                       f"поведение — строка `Ожидание изменено: <причина>` {where}.")
    for o in out:
        print(f"  · {o}")
    return 1 if out else 0


TEST = re.compile(r"(\.(test|spec)\.[A-Za-z0-9]+|^test_[^/]*\.py)$")
EXPECT = re.compile(r"expect\s*\(|\.to(Be|Equal|StrictEqual|BeCloseTo)\s*\(|\bassert")
NUM = re.compile(r"(?<![\w.$])\d+(?:\.\d+)?")
FAILS = re.compile(r"\b(it|test)\.fails\b")


def nums(t):
    return tuple(float(x) for x in NUM.findall(t))


def spans(lines):
    """Номера строк (с 1) внутри ожиданий: от строки с `expect(`/`assert` до закрытия скобок,
    с продолжением цепочки `.toBe(` на следующей строке. Скобки — без учёта строк-литералов."""
    inside, i = set(), 0
    while i < len(lines):
        if not EXPECT.search(lines[i]):
            i += 1
            continue
        depth, j = 0, i
        while j < len(lines) and j - i < 80:
            ln = lines[j]
            depth += sum(ln.count(ch) for ch in "([{") - sum(ln.count(ch) for ch in ")]}")
            inside.add(j + 1)
            if depth <= 0 and not (j + 1 < len(lines) and lines[j + 1].lstrip().startswith(".")):
                break
            j += 1
        i = j + 1
    return inside


def expectation_hits(rng):
    hits = []
    for c in git("rev-list", "--reverse", "--no-merges", rng).split():
        for f in git("diff-tree", "-r", "--no-commit-id", "--name-only", "--diff-filter=M", c).splitlines():
            if not TEST.search(f.rsplit("/", 1)[-1]):
                continue
            old = (git("show", f"{c}^:{f}", ok_missing=True) or "").split("\n")
            final = {l.strip() for l in (git("show", f"{BR}:{f}", ok_missing=True) or "").split("\n")}
            inside = spans(old)
            rem, added, ln, hunk = [], set(), 0, False
            for d in git("diff", "-U0", f"{c}^", c, "--", f).split("\n"):
                m = re.match(r"@@ -(\d+)", d)
                if m:
                    ln, hunk = int(m.group(1)), True
                elif hunk and d.startswith("-"):
                    rem.append((ln, d[1:]))
                    ln += 1
                elif hunk and d.startswith("+"):
                    added.add(nums(d[1:]))
            for n, t in rem:
                s = t.strip()
                # Судятся ЗНАЧЕНИЯ, а не текст: та же последовательность чисел в добавленной
                # строке того же коммита — переименование или перенос (`nbpRateOf(…)).toBe(1)`
                # → `sellRateOf(…)).toBe(1)`), ожидание не менялось.
                if (n in inside and nums(t) and nums(t) not in added and not FAILS.search(t)
                        and not s.startswith(("//", "#")) and s not in final):
                    hits.append(f"{f}:{n} (коммит {c[:8]}): {s[:100]}")
    return hits


def staged_expectation_hits():
    """(д) для прямого коммита: изменённые (не новые) тест-файлы коммита против HEAD; итог — снимок индекса."""
    hits = []
    for f in open(E["CODEF"], encoding="utf-8").read().splitlines():
        if not f or not TEST.search(f.rsplit("/", 1)[-1]):
            continue
        old_t, snap_f = git("show", f"{E.get('BASE', 'HEAD')}:{f}", ok_missing=True), SNAP / f
        if old_t is None or not snap_f.is_file():
            continue  # новый либо удалённый файл не считается — как у слияния
        old = old_t.split("\n")
        final = {l.strip() for l in snap_f.read_text(encoding="utf-8", errors="replace").split("\n")}
        inside = spans(old)
        rem, added, ln, hunk = [], set(), 0, False
        for d in git("diff", "-U0", *E.get("DIFFARGS", "--cached").split(), "--", f).split("\n"):
            m = re.match(r"@@ -(\d+)", d)
            if m:
                ln, hunk = int(m.group(1)), True
            elif hunk and d.startswith("-"):
                rem.append((ln, d[1:]))
                ln += 1
            elif hunk and d.startswith("+"):
                added.add(nums(d[1:]))
        for n, t in rem:
            s = t.strip()
            if (n in inside and nums(t) and nums(t) not in added and not FAILS.search(t)
                    and not s.startswith(("//", "#")) and s not in final):
                hits.append(f"{f}:{n} (в коммите): {s[:100]}")
    return hits


try:
    sys.exit(main())
except Exception as e:  # прибор сломан — говорить, а не молчать
    print(f"  · страж слияния упал ({e.__class__.__name__}: {str(e)[:200]}) — проверено ничего, прибор сломан")
    sys.exit(2)
PY
}

_tools_here() {
    command -v python3 >/dev/null 2>&1 && command -v backlog_open_items >/dev/null 2>&1 && [ -f "$RM" ]
}
# main/master с картой корней и бэклогом — единственное место, где страж судит. Вне его молчание — и это не
# «чисто», а «предмета нет»: прежде неразобранная команда коммита отбивалась в любом проекте (скептик D1019).
_judged_repo() {  # _judged_repo <каталог> → корень репозитория в stdout, если он судится
    local r c
    r=$(project_git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
    c=$(project_git -C "$r" symbolic-ref --short -q HEAD 2>/dev/null)
    case "$c" in main|master) ;; *) return 1 ;; esac
    [ -f "$r/ROOTS.md" ] && [ -f "$r/BACKLOG.md" ] || return 1
    printf '%s' "$r"
}
# Ловушка git — файл `commit-msg` с меткой TRAP_MARK в каталоге ловушек репозитория (`--git-path hooks` учитывает
# core.hooksPath). Метка отличает свою ловушку от чужой: чужую установка не переписывает.
TRAP_MARK="claudsoul-merge-root-gate"
_trap_file() { local h; h=$(project_git -C "$1" rev-parse --path-format=absolute --git-path hooks 2>/dev/null) && printf '%s/commit-msg' "$h"; }
# Ловушка общей установки (метка claudsoul-commit-trap) спрашивается у `project_commit_trap`: он сверяет, что файл по
# адресу шима на месте (скептик D1022: шим в убранный worktree выходил с 0, а метка говорила «ловушка стоит»).
_has_trap() { local f; f=$(_trap_file "$1") && [ -x "$f" ] && grep -q "$TRAP_MARK" "$f" 2>/dev/null || return 1
    grep -q "${COMMIT_TRAP_MARK:-claudsoul-commit-trap}" "$f" 2>/dev/null || return 0
    command -v project_commit_trap >/dev/null 2>&1 || return 0
    project_commit_trap "$1" commit-msg; }

# Установка ловушки — у общей ловушки стражей коммита (D1022): она ставит commit-msg и pre-commit и зовёт этот страж.
if [ "${1:-}" = "--install" ]; then
    [ -f "$_HD/commit-trap.sh" ] || { echo "инструмента нет: $_HD/commit-trap.sh" >&2; exit 2; }
    exec bash "$_HD/commit-trap.sh" "$@"
fi

# Ловушка git `commit-msg` (D1021): git зовёт её из корня рабочего дерева с файлом сообщения и с GIT_INDEX_FILE (в
# связанном worktree и с GIT_DIR) — индексом будущего коммита. Код 1 — коммит не выполнен, причина — в stderr.
if [ "${1:-}" = "--commit-msg" ]; then
    _tools_here || exit 0
    ROOT=$(_judged_repo "$PWD") || exit 0
    # Коммит незаконченного слияния судится, как любой: слияние судило вливаемую ветку, а в индекс после него можно
    # положить и свой код (скептик D1021: `git merge --no-commit` документов, затем код и «fix: …» без пункта). Тема
    # «Merge …» не починка и не судится.
    # Относительный GIT_INDEX_FILE (`.git/index`) git даёт от корня рабочего дерева — от него же идут все `-C "$ROOT"`.
    # `--amend` переписывает HEAD, и основа коммита — HEAD^; git ловушке этого не говорит, а его аргументы — у предка-git:
    # общей ловушки стражей (`commit-trap.sh`, D1022) — деда, а в чужой ловушке, дописавшей её вызов, — прадеда. git
    # принимает и сокращения: `--am`, `--ame`, `--amen`.
    FL=-; _p=$PPID
    for _ in 1 2 3; do
        case " $(ps -o args= -p "$_p" 2>/dev/null) " in *" --am "*|*" --ame "*|*" --amen "*|*" --amend "*) FL=M; break ;; esac
        _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' '); [ -n "$_p" ] || break
    done
    OUT=$(commit_root_check "$ROOT" "$FL" "${2:-/dev/null}"); rc=$?
    [ "$rc" -eq 0 ] && exit 0
    CUR=$(project_git -C "$ROOT" symbolic-ref --short -q HEAD 2>/dev/null)
    WHAT="и коммит не держит корень"
    [ "$rc" -eq 2 ] && WHAT="и страж не смог его проверить (прибор сломан — это не «чисто»)"
    printf '⛔ ОТКАЗ (коммит не выполнен): починка входит в %s (%s) прямым коммитом, %s:\n%s\n%s\n' "$CUR" "$ROOT" "$WHAT" "$OUT" \
        "Сначала разбор «почему» до корня, затем пункт с корнем из карты и коммит с номером пункта в теме. Решение владельца 9 октября 2026 (починка входит в главную ветку с корнем) действует и на прямом коммите — D1019, D1021." >&2
    exit 1
fi

# Суд готового коммита (D1023): коммит вошёл мимо `commit-msg` (обход ловушки), и сверка спрашивает, пропустил бы его
# суд. Индекс — временный, из дерева коммита; сообщение — сохранённое git (после очистки); основа — родитель.
if [ "${1:-}" = "--judge-commit" ]; then
    [ $# -eq 3 ] || { echo "использование: $0 --judge-commit <репозиторий> <коммит>" >&2; exit 2; }
    _tools_here || exit 0
    ROOT=$(_judged_repo "$2") || exit 0
    _jt=$(mktemp -d 2>/dev/null) || { echo "временный каталог не создан — прибор сломан" >&2; exit 2; }
    project_git -C "$ROOT" log -1 --format=%B "$3" > "$_jt/msg" 2>/dev/null \
        && GIT_INDEX_FILE="$_jt/idx" project_git -C "$ROOT" read-tree "$3" 2>/dev/null \
        || { echo "коммит $3 не прочитан — прибор сломан" >&2; rm -rf "$_jt"; exit 2; }
    # Без родителя основа — пустое дерево: пустая основа сравнила бы коммит с HEAD, то есть с ним самим (скептик D1023, b11).
    _par=$(project_git -C "$ROOT" rev-parse -q --verify "$3^" 2>/dev/null) \
        || _par=$(project_git -C "$ROOT" hash-object -t tree /dev/null 2>/dev/null)
    OUT=$(GIT_INDEX_FILE="$_jt/idx" commit_root_check "$ROOT" "B:$_par" "$_jt/msg"); rc=$?
    rm -rf "$_jt"
    [ "$rc" -eq 0 ] || printf '%s\n' "$OUT" >&2
    exit "$rc"
fi

if [ "${1:-}" = "--check" ]; then
    [ $# -eq 4 ] || { echo "использование: $0 --check <репозиторий> <цель> <ветка>" >&2; exit 2; }
    _tools_here || { echo "инструмента нет: python3, backlog-lib.sh или ${RM}" >&2; exit 2; }
    OUT=$(merge_root_check "$2" "$3" "$4"); rc=$?
    case $rc in
        0) echo "✓ ${3}..${4}: пропуск — пункты названы, корни на месте, ожидания тестов не тронуты молча" ;;
        1) printf '⛔ %s..%s: отказ\n%s\n' "$3" "$4" "$OUT" ;;
        *) printf '⚠️ %s..%s: прибор сломан\n%s\n' "$3" "$4" "$OUT" ;;
    esac
    exit $rc
fi

command -v jq >/dev/null 2>&1 || exit 0
_tools_here || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)" = Bash ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
# Слово обхода ловушки — в любой форме команды (`bash -c '… --no-verify …'`): «это коммит?» по исполняемой части его
# не видит, и такая команда идёт в разбор целиком.
if command -v is_git_subcommand >/dev/null 2>&1; then
    is_git_subcommand merge "$CMD" || is_git_subcommand commit "$CMD" \
        || grep -qiE -- '--no-veri|hookspath|GIT_CONFIG|alias\.' <<< "$CMD" || exit 0
else
    case "$CMD" in *git*merge*|*git*commit*) ;; *) exit 0 ;; esac
fi
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

# Вызовы в команде, по строке на вызов: «merge<TAB>каталог<TAB>ветка» и «commit<TAB>каталог<TAB>обход» (обход — 1,
# если вызов обходит ловушку git: `--no-verify`, `-n`, `core.hooksPath`, настройки git окружением, псевдоним с
# обходом; иначе 0). Сообщение и файлы коммита здесь не читаются — их судит ловушка git (D1021). Цель берётся из
# ИСХОДНОЙ строки (command-scope-lib: вырезанный текст теряет пути в кавычках); `cd X` и `-C X` двигают каталог;
# обёртки `time`, `env`, `command`, `nice`, `nohup`, `exec` снимаются.
# ТЕЛА ВСТРОЕННОГО ТЕКСТА — ДАННЫЕ: они вынимаются ДО разбора кавычек. Прежде апостроф в сообщении («fix(D469): …
# Traceback'ом …») ронял shlex, и страж отказывал законному коммиту в любом проекте — финальный скептик D1019
# насчитал 44 таких из 3821 настоящей команды коммита. Терминатор — строка-маркер целиком, как у владельца разбора
# команды (`executable_part`, command-scope-lib.sh). Не разобралась даже без тел (непарные кавычки в самой команде) —
# «__unparsed__».
# Команда идёт в разборщик дескриптором 3, а не окружением: окружение больше 1 МБ не проходит в exec (ARG_MAX), и
# длинная команда оставалась неразобранной молча. Упавший разборщик — «__unparsed__» с причиной: прибор сломан.
UNPWHY="непарные кавычки вне встроенного текста"
# Разборщик — функцией, а не внутри `$( )`: bash 3.2 сканирует встроенный текст в `$( )` на кавычки, и непарный
# апостроф или обратная кавычка в коде разборщика ломали хук целиком (трижды за 21 октября 2026).
_calls() {
    CWD="$CWD" python3 - 3<<< "$CMD" <<'PY'
import os, re, shlex
cmd, d = open(3, encoding="utf-8", errors="surrogateescape").read()[:-1], os.environ["CWD"]
VAL = {"-m", "-F", "-s", "-X", "--file", "--strategy", "--strategy-option", "--into-name"}
GLOBAL1 = {"--no-pager", "-P", "-p", "--paginate", "--no-replace-objects", "--bare", "--literal-pathspecs"}
WRAP = {"time", "command", "nice", "nohup", "exec", "builtin", "export", "local"}
HD = re.compile(r"<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.S)
ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
VARRE = re.compile(r"(?<!\\)\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")
res = lambda base, p: os.path.normpath(os.path.join(base, os.path.expanduser(p)))

bodies = []  # (позиция открытия, тег, тело) в порядке строки


def _cut(m):
    # Тег открытия помечается номером тела (`<<'EOF'` → `<<'EOF__HD3'`), и тело ищется по номеру: по одному тегу
    # судилось первое тело с ним во всей команде, и при более раннем `cat > f <<'EOF'` законный коммит получал отказ
    # по чужому тексту (волна проверки D1019).
    k = len(bodies)
    bodies.append((m.start(), m.group(2), m.group(3)))
    head = m.group(0)[: m.group(0).index("\n") + 1]
    return head.replace(m.group(2), f"{m.group(2)}__HD{k}", 1)


stripped = HD.sub(_cut, cmd)


def uncomment(s):
    # Комментарий bash — `#` в начале слова вне кавычек, до конца строки; перевод строки остаётся разделителем.
    # shlex съедал комментарий ВМЕСТЕ с переводом строки, и следующая команда приклеивалась к предыдущей:
    # `git add a  # в индекс` ⏎ `git commit -m "fix: x"` давал один вызов `git add …` (финальный скептик D1019).
    out, i, n, q = [], 0, len(s), ""
    while i < n:
        c = s[i]
        if q:
            if c == "\\" and q != "'" and i + 1 < n:
                out.append(c); i += 1; c = s[i]
            elif c == q[-1]:
                q = ""
        elif c == "\\" and i + 1 < n:
            out.append(c); i += 1; c = s[i]
        elif c == "$" and s[i + 1:i + 2] == "'":
            q = "$'"; out.append(c); i += 1; c = s[i]
        elif c in "'\"":
            q = c
        elif c == "#" and (i == 0 or s[i - 1] in " \t\n;&|()"):
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        out.append(c); i += 1
    return "".join(out)


plain = uncomment(stripped)

try:
    lx = shlex.shlex(plain, posix=True, punctuation_chars=";&|()\n")
    lx.whitespace = " \t\r"
    lx.commenters = ""  # комментарии сняты выше (uncomment): shlex съедал вместе с ними перевод строки
    # Слова режутся по пробелам: без этого знаки вне «буквенных» шли отдельными токенами — `<<<` распадался на
    # три «<», `<<'EOF'` давал «EOF» в пути коммита, `$'…'` отрывал «$» от текста. Разделители `;&|()` и
    # перевод строки режутся по-прежнему. Предел: слитная `-F -<файл` остаётся одним словом.
    lx.whitespace_split = True
    toks = list(lx)
except ValueError:
    print("__unparsed__")
    raise SystemExit
segs, cur, sep = [], [], ""
for t in toks:
    if t and set(t) <= set(";&|()\n"):
        segs.append((cur, sep)); cur, sep = [], t
    else:
        cur.append(t)
segs.append((cur, sep))

env = {"HOME": os.path.expanduser("~")}


def expand(v):
    if v is None:
        return None
    miss = []

    def sub(m):
        n = m.group(1) or m.group(2)
        if n in env:
            return env[n]
        miss.append(n)
        return m.group(0)
    out = VARRE.sub(sub, v)
    return None if miss else out


# Коммит судит ловушка git `commit-msg` (D1021) — сообщение и индекс у неё готовы. Здесь — только обход ловушки
# (решение владельца «Ловушки git»: ловится по слову): `--no-verify` и его сокращения, которые git принимает
# (`--no-verif`, `--no-veri`), короткий `-n` в ключах коммита, в том числе слитых (`-nm` — да; `-mn`, `-uno` — нет:
# после `m`, `u` идёт значение), `core.hooksPath` в настройках вызова (ключи настроек git регистр не различают),
# переопределённые настройки git окружением (`GIT_CONFIG_*`, `HOME`, `XDG_CONFIG_HOME`) и псевдоним, разворачивающийся
# в коммит с обходом (`-c alias.ci='commit -n'`, `git config alias.ci 'commit -n'`). Находки скептика D1021.
CVAL_SHORT = set("mFcCtuS")
NOVERIFY = re.compile(r"--no-ver(?:i(?:fy?)?)?$")
NOVERIFY_WORD = r"--no-veri(?:fy?)?(?![\w-])|hookspath|GIT_CONFIG"
ENV_CFG = lambda n: n.upper().startswith("GIT_CONFIG") or n in ("HOME", "XDG_CONFIG_HOME")
exported = set()  # `export X=…` той же команды — окружение всех следующих вызовов


def bypass(gargs, args, env_names=()):
    if any("hookspath" in a.lower() for a in gargs) or any(NOVERIFY.match(a) for a in args):
        return 1
    if any(ENV_CFG(n) for n in set(env_names) | exported):
        return 1
    for a in args:
        if a == "--":
            break
        if re.match(r"^-[A-Za-z]+$", a):
            for ch in a[1:]:
                if ch == "n":
                    return 1
                if ch in CVAL_SHORT:
                    break
    return 0


def alias_bypass(v):
    """Значение псевдонима git, разворачивающееся в коммит с обходом ловушки."""
    try:
        w = shlex.split(v.lstrip("!"))
    except ValueError:
        w = v.lstrip("!").split()
    return "commit" in w and bypass([], w[w.index("commit") + 1:]) == 1


commits = []
for k, (s, sep) in enumerate(segs):
    lead, seg_env = True, set()  # seg_env — присваивания перед командой этого вызова (`HOME=… git commit`)
    for ti, t in enumerate(s):  # присваивания той же команды: `R=…; git -C "$R" merge …`, `export SP=…`
        m = ASSIGN.match(t)
        if lead and m:
            (exported if s[0] == "export" else seg_env).add(m.group(1))
            raw = m.group(2)
            v = None if re.search(r"(?<!\\)(?:\$\(|\x60)", raw) else expand(raw)  # \x60 — обратная кавычка
            if v is not None:
                env[m.group(1)] = v
            else:
                env.pop(m.group(1), None)
            continue
        lead = t in ("export", "local")
    while s and (ASSIGN.match(s[0]) or s[0] in WRAP):
        s = s[1:]
    if s and s[0] == "env":
        s = s[1:]
        while s and (ASSIGN.match(s[0]) or s[0].startswith("-")):
            if ASSIGN.match(s[0]):
                seg_env.add(ASSIGN.match(s[0]).group(1))
            s = s[1:]
    if not s:
        continue
    if s[0] == "cd" and len(s) > 1 and s[1] != "-":
        d = res(d, expand(s[1]) or s[1]); continue
    if os.path.basename(s[0]) != "git":
        continue
    i, gd = 1, d
    while i < len(s):
        a = s[i]
        if a == "-C" and i + 1 < len(s):
            gd = res(gd, expand(s[i + 1]) or s[i + 1]); i += 2
        elif a == "-c" and i + 1 < len(s):
            i += 2
        elif a in GLOBAL1 or a.startswith(("--git-dir=", "--work-tree=")):
            i += 1
        else:
            break
    aliases = [s[x + 1].split("=", 1)[1] for x in range(1, i - 1)
               if s[x] == "-c" and re.match(r"(?i)alias\.[^=]+=", s[x + 1])]
    if i + 2 < len(s) and s[i] == "config" and any(re.match(r"(?i)alias\.", a) for a in s[i + 1:]):
        aliases.append(s[-1])
    if any(alias_bypass(v) for v in aliases):
        commits.append((gd, 1))
        continue
    if i < len(s) and s[i] == "commit":
        commits.append((gd, bypass(s[1:i], s[i + 1:], seg_env)))
        continue
    if i >= len(s) or s[i] != "merge":
        continue
    args = s[i + 1:]
    if {"--abort", "--continue", "--quit", "--skip"} & set(args):
        continue
    j, br = 0, []
    while j < len(args):
        a = args[j]
        if a in VAL:
            j += 2; continue
        if not a.startswith("-"):
            br.append(a)
        j += 1
    for b in br:
        print(f"merge\t{gd}\t{b}")
# Слово обхода вне разобранного вызова (`bash -c "git commit --no-verify …"`, `eval …`) — по тексту команды без тел
# встроенного текста, и только если разобранного коммита нет вовсе, а в тексте есть `git … commit`: у разобранного
# коммита обход судится по его ключам, а слово в `grep -- --no-verify` или в имени `commit-msg` — не обход (скептик
# D1021: ложные отказы командам, которые не коммит). Коммит в нём судится в каталоге команды.
# Широта «git … commit» — страховка поверх разборщика: на незнакомом глобальном ключе (`--no-optional-locks`, `-p` в
# `bash -c`) он вызов коммитом не считает, и ловит его только это слово (скептик D1025: сужение до перечня ключей открыло
# обход). Освобождается одно: вхождение `git`, чья подкоманда — заведомо читающая (`git grep 'commit…--no-verify'`
# получал отказ, D1025). Подкоманда — первое слово после `git`, кроме `-C`/`-c` со значением, ключей разборщика (`GLOBAL1`)
# и ключей `--x=…`; незнакомое слово и незнакомый ключ освобождения не дают.
READ_SUB = {"grep", "log", "show", "diff", "blame", "status", "shortlog", "reflog", "describe", "ls-files", "ls-tree",
            "rev-list", "rev-parse", "cat-file", "help", "whatchanged"}


def commit_word_runs(text):
    for g in re.finditer(r"\bgit\b", text):
        seg = re.split(r"[\n;&|]", text[g.end():], maxsplit=1)[0]
        c = re.search(r"\bcommit\b(?![-\w])", seg)
        if not c:
            continue
        toks, sub, j = [t.strip("'\"\\") for t in seg[:c.start()].split()], "", 0
        while j < len(toks):
            if toks[j] in ("-C", "-c"):
                j += 2
            elif not toks[j] or toks[j] in GLOBAL1 or (toks[j].startswith("--") and "=" in toks[j]):
                j += 1
            elif toks[j].startswith("-"):
                break  # ключ вне перечня мог взять значение словом (`--namespace log`) — освобождения нет (скептик D1025)
            else:
                sub = toks[j]; break
        if sub not in READ_SUB:
            return True
    return False


SHELLS_C = ("bash", "sh", "zsh")
NESTED_BAN = re.compile(r"(?i)\b(?:pushd|popd|eval|exec|source|alias|function|OLDPWD|GIT_DIR|GIT_WORK_TREE|worktree)\b"
                        r"|--git-dir|--work-tree|(?:^|\s)-C(?:\s|$)|&&\s*\.\s")   # `. файл` — только в начале звена: `git init .` законен
NESTED_HEADS = {"git", "printf", "echo", "touch", "mkdir", "true", ":"}   # подготовка временного репозитория
NESTED_STEP = r"[^;&|()\n\x60]+"          # простая команда звена: без разделителей, скобок и обратных кавычек
NESTED_SHAPE = re.compile(
    r"^\s*(?:(?P<var>[A-Za-z_][A-Za-z0-9_]*)=\$\(mktemp -d\)\s*(?:;|&&)\s*)?"
    r"cd\s+(?:\"(?P<q>[^\"\x60\\]+)\"|(?P<b>[A-Za-z0-9_./$\{\}-]+))"
    r"(?P<rest>(?:\s*&&\s*" + NESTED_STEP + r")+)\s*$")


def nested_commit_dirs():
    """Каталоги, в которых судить коммит из скрипта `bash -c '…'`: список путей (пустой — коммит доказуемо не в
    судимый репозиторий), либо `None` — не доказано, судим в каталоге команды, как прежде (D1342).

    Прежде такой коммит судился в каталоге команды всегда, и подготовка временного репозитория (скрипт вида
    `R=$(mktemp -d); cd "$R" && git init … && … git commit …` внутри `bash -c`) получала отказ «коммит в main».
    Первая починка спросила каталог у владельца разбора команд и открыла обходы (скептик opus по db409435: 2 новых и
    19 унаследованных форм): у владельца «каталог неизвестен» значит пропуск, у защитного стража обязан значить отказ.
    Поэтому здесь не разбор, а БЕЛЫЙ СПИСОК одной формы, в которой каталог коммита доказуем по тексту:
      · вся команда — один вызов `bash|sh|zsh -c '<скрипт>'`, без окружения и соседних команд;
      · скрипт — `cd <цель>` и дальше только звенья через `&&` (сбой `cd` обрывает цепочку — коммит не уйдёт в каталог
        команды); перед `cd` — не более одного `ИМЯ=$(mktemp -d)`;
      · цель — литеральный абсолютный путь (судится он) либо та самая переменная `mktemp` (временный каталог — не
        судится);
      · звено начинается с `git`, `printf`, `echo`, `touch`, `mkdir` или `true`; в звеньях нет второго `cd`,
        `pushd`/`popd`, `eval`, `-C`, `--git-dir`, `GIT_DIR`, `worktree`, псевдонимов и функций.
    Всё остальное — `None`. НАЗВАННЫЙ ПРЕДЕЛ: законный коммит в чужой каталог иной формы (с `;` после `cd`, с
    `$HOME`, с несколькими командами до `cd`) по-прежнему получает отказ; обойти — выполнить без `bash -c` либо
    привести к форме выше. Условие снятия: такая форма встретится в отказах стража дважды.
    """
    if len(toks) != 3 or os.path.basename(toks[0]) not in SHELLS_C or toks[1] != "-c":
        return None
    m = NESTED_SHAPE.match(toks[2])
    if not m or NESTED_BAN.search(m.group("rest")) or re.search(r"\bcd\b|chdir", m.group("rest")):
        return None
    # Каждое звено начинается с разрешённой программы: вложенная оболочка, интерпретатор, `find -execdir`, `make -C`
    # увели бы коммит в другой каталог мимо `cd` (`sh -c "cd <репозиторий> && git commit …"` — «&&» в кавычках делит
    # текст на звенья так же, как настоящий, и слово `cd` там ловит запрет выше).
    for step in m.group("rest").split("&&")[1:]:
        words = step.split()
        while words and ASSIGN.match(words[0]):
            words = words[1:]
        if not words or words[0] not in NESTED_HEADS:
            return None
    var, target = m.group("var"), m.group("q") or m.group("b")
    if var is not None and target in ("$" + var, "${" + var + "}"):
        return [] if len(re.findall(r"(?<![A-Za-z0-9_])" + re.escape(var) + r"=", toks[2])) == 1 else None
    if var is None and target.startswith("/") and not re.search(r"[$\x60*?\[\]{}~]", target):
        return [os.path.normpath(target)]
    return None


if (not commits and re.search(NOVERIFY_WORD, plain, re.I)
        and commit_word_runs(plain)):
    nd = nested_commit_dirs()
    for x in ([os.environ["CWD"]] if nd is None else nd):
        commits.append((x, 1))
for gd, b in commits:
    print(f"commit\t{gd}\t{b}")
PY
}
CALLS=$(_calls) || { CALLS="__unparsed__"; UNPWHY="разборщик команды упал — прибор сломан"; }
[ -n "$CALLS" ] || exit 0

_deny() {
    jq -cn --arg m "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$m}}'
    exit 0
}
_hint() {
    jq -cn --arg m "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}'
    exit 0
}
if grep -qx '__unparsed__' <<< "$CALLS"; then
    # Слияние — прежний договор: отказ словами, что вливается, неизвестно. Коммит — подсказка в судимом репозитории.
    if command -v is_git_subcommand >/dev/null 2>&1 && is_git_subcommand merge "$CMD"; then
        _deny "⛔ ОТКАЗ (слияние не выполнено): команда содержит \`git merge\`, но её не удалось разобрать (${UNPWHY}) — какая ветка вливается, неизвестно, и проверить корень нечем. Выполни слияние отдельной простой командой: git -C <репозиторий> merge <ветка>."
    fi
    if command -v is_git_subcommand >/dev/null 2>&1 && is_git_subcommand commit "$CMD" && JR=$(_judged_repo "$CWD"); then
        CALLS="commit	${CWD}	$(grep -qiE -- '--no-veri|hookspath|GIT_CONFIG' <<< "$CMD" && echo 1 || echo 0)"
    else
        exit 0
    fi
fi

# Прямой коммит в main/master судит ловушка git `commit-msg` (D1021). Здесь — только её обход и её отсутствие: в обоих
# случаях коммит вошёл бы без суда пункта и корня.
CMSG=""
while IFS="$(printf '\t')" read -r kind dir nv; do
    [ "$kind" = commit ] || continue
    ROOT=$(_judged_repo "$dir") || continue
    if [ "$nv" = 1 ]; then
        CMSG="${CMSG:+$CMSG
}коммит в main (${ROOT}) обходит ловушку git: в команде \`--no-verify\`, \`-n\` или \`core.hooksPath\` — ловушка commit-msg не исполнится, и починка вошла бы без суда пункта и корня. Убери обход; если это слово — в тексте сообщения, передай сообщение файлом: git commit -F <файл>."
    elif ! _has_trap "$ROOT"; then
        CMSG="${CMSG:+$CMSG
}в судимом репозитории ${ROOT} нет ловушки git commit-msg стража корня — коммит в main вошёл бы без суда пункта и корня. Поставь её: bash '${_HD}/commit-trap.sh' --install '${ROOT}'"
    fi
done <<< "$CALLS"
[ -z "$CMSG" ] || _deny "⛔ ОТКАЗ (коммит не выполнен): ${CMSG}
Решение владельца 21 октября 2026 («Ловушки git», D1021): коммит в main судит ловушка git, а обход ловушки ловится по слову."

MSG=""
while IFS="$(printf '\t')" read -r kind dir br; do
    [ "$kind" = merge ] || continue
    [ -n "$br" ] || continue
    ROOT=$(project_git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || continue
    CUR=$(project_git -C "$ROOT" symbolic-ref --short -q HEAD 2>/dev/null)
    case "$CUR" in main|master) ;; *) continue ;; esac
    [ -f "$ROOT/ROOTS.md" ] && [ -f "$ROOT/BACKLOG.md" ] || continue
    project_git -C "$ROOT" rev-parse -q --verify "${br}^{commit}" >/dev/null 2>&1 || continue
    # Синхронизация с upstream своей же ветки — не вливание починки.
    case "$(project_git -C "$ROOT" rev-parse --symbolic-full-name "$br" 2>/dev/null)" in
        refs/remotes/*/"$CUR") continue ;;
    esac
    OUT=$(merge_root_check "$ROOT" HEAD "$br"); rc=$?
    [ "$rc" -eq 0 ] && continue
    N=$(project_git -C "$ROOT" rev-list --no-merges --count "HEAD..$br" 2>/dev/null)
    WHAT="и слияние не держит корень"
    [ "$rc" -eq 2 ] && WHAT="и страж слияния не смог его проверить (прибор сломан — это не «чисто»)"
    MSG="${MSG:+$MSG
}в ${CUR} (${ROOT}) вливается ${br} — ${N:-?} коммит(ов), ${WHAT}:
${OUT}"
done <<< "$CALLS"
[ -n "$MSG" ] || exit 0
_deny "⛔ ОТКАЗ (слияние не выполнено): ${MSG}
Сухой прогон того же разбора после починки: bash $(printf "'%s'" "$(printf '%s' "$_HD" | sed "s/'/'\\\\''/g")")/merge-root-gate.sh --check <репозиторий> HEAD <ветка>. Решение владельца 9 октября 2026: в главную ветку починка входит с корнем — карточка до кода, чек-лист зависимостей, проба на нуле или названный предел, ожидания тестов не подгоняются."
