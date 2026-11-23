#!/usr/bin/env bash
# archive-checks-after-commit.sh — после коммита прогоняет «Проверки» закрытых пунктов архива, задетые файлами коммита.
# en: after a commit, re-runs the archived items' checks that the commit's files touch; a red one is named on the next reply.
#
# Результат: коммит, ломающий «Проверку» закрытого пункта, назван на следующей реплике, а не недельным замером (D1249).
# Проверка результата: bash hooks/tests/fixtures/probe_D1249.sh даёт 0
#
# Зачем (D1249). «Проверки» архива прогонял только недельный замер (`scripts/measurements.tsv`, период 7), а набор
# гоняет `hooks/tests/test_*.sh` — коммит, ломающий пробу закрытого пункта, проходил зелёным, и поломка всплывала через
# неделю знаком «?». Решение владельца 8 ноября 2026: прогон фоном ПОСЛЕ коммита — коммит не ждёт, итог — в очереди
# напоминаний (`state/pending-alerts.txt`, её показывают на следующей реплике). Зовёт ловушка git `post-commit`
# (`hooks/commit-trap.sh --post-commit`) отсоединённым процессом; `--sync` — прогон на месте (проба, ручной вызов).
#
# Выбор номеров: закрытый пункт архива (☑), у которого проба `hooks/tests/fixtures/probe_D<N>.sh` объявляет в строке
# `# СУДИТ:` файл коммита (по имени) либо подключает или исполняет его кодом (D1312), либо строка «Проверка» называет
# путь файла коммита. Исполнитель — владелец
# сверки архива по номерам, `hooks/tests/fixtures/probe_D1196.sh` (ручка `PROBE_ARCHIVE_IDS`); он судит только ☑ —
# пункт ⊘ (не делается) инварианта не объявляет, и выбранный ⊘ давал код 2 «в архиве нет закрытых пунктов» без прогона
# (скептик opus по 2fda3705, H1: 23 из 200 коммитов).
# Судится СНИМОК коммита — клон с общими объектами на вершине `HEAD`, а не рабочая копия: незакоммиченная правка или
# правка во время прогона иначе винилась бы коммиту (скептик, M2; клон меньше секунды).
# НАЗВАННЫЙ ПРЕДЕЛ: прогон, начатый при уже идущем прогоне, пропускается молча — следующий коммит
# задетые файлы назовёт снова; проба, подключающая файл через переменную (`L="$R/x.sh"; . "$L"`), не выбирается.
# Условие снятия: учёт зависимостей начнёт знать пробы (`.claude-docs/dep-index.tsv`) — выбор пойдёт по его рёбрам.
#
# Код: 0 всегда (прибор ловушки коммита не роняет); в `--sync` — код исполнителя (0 держатся, 1 красны, 2 не измерено),
# 3 — нечего судить.
set -uo pipefail
MODE="${1:-}"
# Переменные git коммита — не наши: из ловушки git приходят GIT_DIR/GIT_INDEX_FILE, и «Проверки», делающие `git init` и
# `git config` в своей песочнице, писали бы в этот репозиторий (8 ноября 2026: проба D515 вписала `core.bare = true`).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$ROOT/BACKLOG-archive.md" ] && [ -f "$ROOT/hooks/tests/fixtures/probe_D1196.sh" ] || exit 0
STATE_DIR="${STATE_DIR:-$HOME/.claude/hooks/state}"
SHA=$(git -C "$ROOT" rev-parse -q --verify HEAD 2>/dev/null) || exit 0
# select_ids <дерево> — номера закрытых пунктов архива дерева с исполнимой «Проверкой», задетых файлами FILES. Граница
# пункта и «исполнима ли Проверка» — у исполнителя (`scripts/backlog-recheck.sh --archive --list`, D1283, корень R1): своё
# выражение отбора не считало границей заголовки `### D109 ☑ …` старого вида — «блок» D104 вбирал «Проверки» десятков
# старых пунктов, и D104 выбирался по чужим путям; D447 выбирался по `# СУДИТ:` пробы, а исполнимой «Проверки» у пункта нет.
select_ids() {
    local root="$1" list
    # Исполнитель без перечня (старая редакция) флаг `--list` пропустил бы и начал исполнять весь архив — около часа.
    grep -qF 'AC_LIST' "$root/scripts/backlog-recheck.sh" 2>/dev/null || return 0
    list=$(cd "$root" && BACKLOG_RECHECK_ARCHIVE="$root/BACKLOG-archive.md" CLAUDSOUL_REPO="$root" \
        bash "$root/scripts/backlog-recheck.sh" --archive --list 2>/dev/null) || return 0
    # Пробы «только в рабочем дереве» судят то, чего в клоне коммита нет по построению (неотслеживаемый снимок карты,
    # журнал прибора по пути дерева): клон давал «не держатся» без поломки (скептик opus по D1295, M2). Перечень — у
    # владельца маркера, прибора свидетелей; прибор без режима (старая редакция) начал бы полный прогон — тогда не спрашиваем.
    local rt=""
    grep -qF -- '--realtree' "$root/scripts/behavior-condition-probe.sh" 2>/dev/null \
        && rt=$(cd "$root" && CLAUDSOUL_REPO="$root" bash "$root/scripts/behavior-condition-probe.sh" --realtree 2>/dev/null)
    # Перечень и файлы коммита — потоками, а не окружением (D1315): у Linux одна строка окружения или аргумента не длиннее
    # 128 КБ (MAX_ARG_STRLEN), перечень архива — 196 КБ, и `python3` не запускался вовсе («Argument list too long»).
    REALTREE="$rt" python3 - "$root" <(printf '%s' "$list") <(printf '%s' "$FILES") <<'PY'
import glob, os, re, sys
root = sys.argv[1]
def stream(p):
    with open(p, encoding="utf-8", errors="replace") as fh:
        return fh.read()
# Документ выбора не даёт — то же правило, что у выборки набора (`hooks/tests/run_all.sh`, D1203): BACKLOG.md правится
# почти в каждом коммите, и его имя в «Проверках» гнало бы архив на каждый коммит; учёт — выход прибора, а не механизм.
commit = [f for f in stream(sys.argv[3]).split("\n") if f and f != ".claude-docs/dep-index.tsv"]
files = [f for f in commit if not f.endswith(".md")]
bases = {os.path.basename(f) for f in files}
# Для строки «СУДИТ» документ — такой же предмет, как код (D1338, корень R3): предмет объявила сама проба, и довод
# «имя документа в „Проверках“ гнало бы архив на каждый коммит» к ней не относится — он о пути по тексту «Проверки».
# Прежде один отсев `*.md` стоял перед обоими путями, и правка документа, объявленного пробой, не судилась никем
# (a5ae4806 правил только `BACKLOG-archive.md`, D1122 его судит — прибор отвечал «нечего судить»).
judged = {os.path.basename(f) for f in commit}
cmds = {}
for ln in stream(sys.argv[2]).split("\n"):
    if "\t" in ln:
        n, c = ln.split("\t", 1)
        cmds.setdefault(n, []).append(c)
ids = {n for n, cs in cmds.items() if any(f in c for c in cs for f in files)}
EXEC = re.compile(r"(?:^|[;&|({!]|\bthen|\bdo)\s*(?:\.|source|bash|sh|python3?|cp)\s")
for p in glob.glob(os.path.join(root, "hooks/tests/fixtures/probe_D*.sh")):
    mm = re.search(r"probe_(D\d+)[a-z]?\.sh$", p)   # бывают и `probe_D488b.sh`
    n = mm.group(1) if mm else ""
    if n not in cmds:   # исполнителю нечего мерить: нет закрытого пункта с исполнимой «Проверкой»
        continue
    try:
        text = open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    for s in re.findall(r"(?m)^#\s*СУДИТ:\s*(.+)$", text[:4000]):
        if judged & {os.path.basename(w) for w in s.split()}:
            ids.add(n)
    # И по КОДУ пробы (D1312, корень R3): проба, ПОДКЛЮЧАЮЩАЯ или ИСПОЛНЯЮЩАЯ изменённый файл, зависит от него, даже если
    # строка «СУДИТ» его не называет — правка `alerts-read.sh` не перепроверяла D441, D514, D1231 (скептик D1309).
    # Зависимость — только строка кода с командой `.`, `source`, `bash`, `sh`, `python`, `cp` (копия в песочницу, чтобы
    # исполнить); прочее упоминание — данные: путь в присваивании, текст сообщения, подделка в песочнице. Первая редакция
    # брала любое упоминание, и 40% добавок были данными, а проба D1249 выбирала сама себя за файл, который правит в
    # клоне, — «не измерено» на каждом таком коммите (скептик opus по 02a4ba72, H1, H2). Имя — целиком, с границей
    # (`my-x.sh`, `x.sh.bak` — не `x.sh`); комментарий, и хвостовой тоже, — не зависимость. Цена (200 коммитов): 69
    # запусков сверх объявленных против 344 у первой редакции.
    dep = "\n".join(re.sub(r"\s#\s.*$", "", l) for l in text.split("\n")
                    if not re.match(r"\s*#", l) and EXEC.search(l))
    if any(re.search(r"(?<![\w.-])" + re.escape(b) + r"(?![\w.-])", dep) for b in bases):
        ids.add(n)
rt =[w for w in os.environ.get("REALTREE", "").split("\n") if w]
ids = {n for n in ids if not any(w in c for c in cmds.get(n, []) for w in rt)}
print(" ".join(sorted(ids, key=lambda x: int(x[1:]) if x[1:].isdigit() else 0)))
PY
}
# `--select <файл>…` — только выбор номеров по дереву рабочей копии, без исполнения (проба D1283, ручной вызов).
if [ "$MODE" = --select ]; then
    shift; FILES=$(printf '%s\n' "$@"); select_ids "$ROOT"; exit 0
fi
if [ "$MODE" != --sync ]; then
    # Отдельным процессом, а не подоболочкой: замок пишет владельцем `$$`, а в подоболочке это номер уже вышедшего
    # родителя — живой прогон выглядел бы брошенным.
    ( nohup bash "$0" --sync >/dev/null 2>&1 & ) >/dev/null 2>&1
    exit 0
fi
# Замок с владельцем (`hooks/state-lock-lib.sh`): брошенный убитым прогоном срывается по живости владельца, а не
# держит прибор немым навсегда (скептик, M1). Одна попытка — идущий прогон не ждут; потолок живого — десять порогов.
. "$ROOT/hooks/state-lock-lib.sh" 2>/dev/null || exit 0
mkdir -p "$STATE_DIR" 2>/dev/null
LK="$STATE_DIR/archive-checks-after-commit"
CLAUDSOUL_LOCK_TRIES=1 CLAUDSOUL_LOCK_STALE_S=360 lock_acquire "$LK" || exit 0
S=$(mktemp -d) || { lock_release "$LK"; exit 0; }
trap 'lock_release "$LK"; rm -rf "$S"' EXIT
git clone -q --shared --no-checkout "$ROOT" "$S/repo" 2>/dev/null \
    && git -C "$S/repo" checkout -q --detach "$SHA" 2>/dev/null || exit 0
ARCH="$S/repo/BACKLOG-archive.md"; EXE="$S/repo/hooks/tests/fixtures/probe_D1196.sh"
[ -f "$ARCH" ] && [ -f "$EXE" ] || exit 0
FILES=$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r --root "$SHA" 2>/dev/null)
[ -n "$FILES" ] || exit 0
IDS=$(select_ids "$S/repo")
[ -n "$IDS" ] || exit 3
# Журнала нет намеренно: читателя у него не было (род G, реестр родов 8 ноября 2026) — выход прибора один, строка
# напоминания. Пропущенный при идущем прогоне коммит не записывается (названный предел в шапке).
out=$(cd "$S/repo" && CLAUDSOUL_REPO="$S/repo" PROBE_ARCHIVE_IDS="$IDS" bash "$EXE" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
    _ac_msg=$(printf '⚠️ Архивные «Проверки», задетые коммитом %s, не держатся (код %d): %s — повтор: PROBE_ARCHIVE_IDS="%s" bash hooks/tests/fixtures/probe_D1196.sh' \
        "${SHA:0:8}" "$rc" "$(printf '%s' "$out" | grep -v '^[[:space:]]*$' | tail -1)" "$IDS")
    # Адресат — проект коммита, а не первая сессия системы (D1304): общую очередь снимает реплика любой сессии, и строка о
    # коммите в ClaudSoul доставалась сессии другого проекта. Без библиотеки — общая очередь, как прежде.
    # shellcheck source=/dev/null
    [ -f "$ROOT/hooks/paths-lib.sh" ] && . "$ROOT/hooks/paths-lib.sh" 2>/dev/null
    if command -v project_alert >/dev/null 2>&1; then project_alert "$STATE_DIR" "$ROOT" "$_ac_msg"
    else printf '%s\n' "$_ac_msg" >> "$STATE_DIR/pending-alerts.txt" 2>/dev/null; fi
fi
exit "$rc"
