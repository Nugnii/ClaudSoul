#!/usr/bin/env bash
# affected-tests.sh — набор тестов перед коммитом: тесты по именам изменённых файлов, ВСЕ сканеры дерева и тесты, где
#   стоит текст, который правка убрала.
# en: prints the test set to run before a commit: tests naming the changed files, every tree scanner, and tests that
#     still carry a string the change removed.
#
# Результат: в наборе перед коммитом есть тесты, которые выборка по импортам пропускает, — сканеры дерева и спеки со
#            старым текстом интерфейса; красное у них видно до коммита, а не в CI релиза
# Проверка результата: bash scripts/affected-tests.sh --self-test даёт 0
#
# Повод (D1296, 15 ноября 2026, ProjectA; решение владельца «в ClaudSoul, для всех проектов»). Трижды за две сессии набор,
# отобранный по импортам изменённого модуля или только по `tests/unit`, пропустил красное: реестры-сканеры b283/b365,
# сканер кабинета после B647 и e2e-спека `task-create-modal.spec.ts:71` после словаря B645 (CI релиза v2.143.0 красный).
# Знание `pattern-affected-test-set-by-imports-misses-scanners-and-e2e` трижды держалось текстом.
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ. В ClaudSoul выбор держит `hooks/tests/run_all.sh --changed`: реестр «всегда» (`always-run.tsv`,
# тесты, чей предмет — дерево) плюс второй шаг по карте зависимостей. Он остаётся: реестр измерен на этом дереве, карта
# есть только здесь. Этот скрипт — для проектов без карты: сканер узнаётся ПРИЗНАКОМ в тексте теста, а не строкой реестра,
# и хук `affected-tests-reminder.sh` ClaudSoul не судит.
#
# Три правила набора:
#   · по имени — тест, где стоит имя изменённого файла без расширения (у `index` — имя каталога, у общих имён вроде
#     `page`, `route`, `utils` и короче четырёх букв — «каталог/имя»); изменённый тест входит сам;
#   · сканер дерева — тест, который читает каталоги сам (`readdirSync`, `glob`, `os.walk`, `rglob`, `git ls-files`,
#     `grep -r`, `git grep`, `find … -name` — b552 обходит роуты `grep -rlE`, скептик D1296 H1) либо
#     относительным импортом подключает помощника, который их читает (`../support/prisma-data-scan` у b365, реестр мест
#     показа у adv-cabsess — оба проявления повода шли через помощника): зависимость от правки в импортах не видна по
#     построению, поэтому входят ВСЕ сканеры;
#   · старый текст — тест, где строкой целиком (в кавычках, разметке, `/…/`) стоит литерал или текст разметки, исчезнувший
#     из изменённых файлов (`git diff HEAD`: был в удалённых строках и не вернулся в добавленных): e2e и тесты отрисовки
#     ищут подпись, а не модуль.
# ponytail: признак сканера — словарь вызовов и ОДИН уровень относительных импортов JS/TS, а не разбор кода. Потолок —
#   помощник помощника, `source` в тестах оболочки и импорт пакетом в питоне; путь дальше — замыкание импортов.
# ponytail: имя ищется подстрокой с границами, без графа импортов: общее имя тянет лишние тесты (набор шире, не уже) —
#   правка одного из 31 роута `[id]/route.ts` ProjectA тянет 183 теста по имени. Путь дальше — граф импортов проекта.
#
# След: набор, собранный для нынешних изменений, пишется отпечатком в `$STATE_DIR/affected-tests-<ключ дерева>.json`;
# `--was-run` отвечает, собирался ли набор для того же отпечатка. Отпечаток — `git diff HEAD` и неотслеживаемые файлы.
# НАЗВАННЫЙ ПРЕДЕЛ: след говорит «набор собран», а не «набор прогнан» — запуск тестов проекта скрипт не видит.
# Условие снятия: у проекта появится журнал прогона тестов, который можно сверить с набором.
# Проверка снятия: `grep -q "^# ЖУРНАЛ ПРОГОНА:" scripts/affected-tests.sh`
#
# Вызов:  affected-tests.sh [--root <каталог>] [файл…]   — без файлов берутся изменённые против HEAD и неотслеживаемые
#         affected-tests.sh --was-run [--root <каталог>] — 0 собран для нынешних изменений либо тестов нет · 1 нет · 2 не git
#         affected-tests.sh --self-test
# Коды:   0 — набор напечатан (пустой — законный ответ); 2 — не git-репозиторий либо разбор не отработал.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "affected-tests: нет python3" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "affected-tests: нет git" >&2; exit 2; }
AT_SELF="$0" exec python3 - "$@" <<'PY'
import hashlib, json, os, re, subprocess, sys, tempfile

GENERIC = {"page", "route", "layout", "main", "utils", "util", "types", "constants", "helpers", "config", "mod", "lib",
           "styles", "api", "app", "server", "client"}
TEST_NAME = re.compile(r"^test_.*\.(py|sh)$|_test\.py$|\.(test|spec)\.[cm]?[jt]sx?$")
SCAN = re.compile(r"readdirSync|readdir\(|opendirSync|globSync|glob\.sync|fast-glob|walkSync|os\.walk\(|os\.listdir\(|"
                  r"\.rglob\(|\.iterdir\(|git ls-files|git grep|\bgrep\s+-[A-Za-z]*[rR]|\bfind\s+\S+\s+-(?:name|type)\b")
LIT = re.compile(r"""(["'`])((?:\\.|(?!\1).)*?)\1""")
MARKUP = re.compile(r">([^<>{}]+)<")
LETTER = re.compile(r"[^\W\d_]")
IMPORT = re.compile(r"""(?:from\s+|require\(\s*|import\(\s*|import\s+)["'](\.{1,2}/[^"']+)["']""")
EXTS = ("", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", "/index.ts", "/index.tsx", "/index.js")
# Старый текст судится СТРОКОЙ ЦЕЛИКОМ — в кавычках, в разметке или в /…/, а не подстрокой: подпись «Invoice» иначе
# совпадала с именем модели в коде 296 тестов ProjectA (замер 15 ноября 2026 на правке словаря B645, 8a0dce21).
# Якорь регэкспа (`/^Далее/`, `/Далее$/`) и подстановка шаблона (`` `Далее ${n}` ``) — тоже граница (16 спек ProjectA).
DELIM_L, DELIM_R = r"(?:[\"'`>]|/\^?)", r"(?:[\"'`<]|\$?/|\s*\$\{)"


def git(root, *a):
    # Пути без кавычек и восьмеричных кодов: иначе имя с кириллицей не совпадает ни с файлом, ни с `.md` (скептик D1296, M1).
    return subprocess.run(["git", "-C", root, "-c", "core.quotepath=off", *a], capture_output=True, text=True,
                          errors="replace")


def toplevel(d):
    p = git(d, "rev-parse", "--show-toplevel")
    return p.stdout.strip() if p.returncode == 0 else ""


def listed(root, *a):
    return [x for x in git(root, *a).stdout.split("\n") if x]


def changed_paths(root):
    """Изменённое против HEAD (в рабочем дереве и в индексе) и неотслеживаемое; переименование — двумя путями: старое
    имя называют тесты (H2). Правка только в индексе — тоже правка: коммит берёт индекс (L1)."""
    return sorted(set(listed(root, "diff", "HEAD", "--name-only", "--no-renames"))
                  | set(listed(root, "diff", "--cached", "--name-only", "--no-renames"))
                  | set(listed(root, "ls-files", "--others", "--exclude-standard")))


def fingerprint(root):
    """Вершина и содержимое изменённых путей в рабочем дереве. От индекса не зависит: `git add` между набором и
    коммитом отпечаток не меняет (прежний — `git diff HEAD` плюс неотслеживаемые — менял на каждом новом файле, M2)."""
    h = hashlib.sha256(git(root, "rev-parse", "-q", "--verify", "HEAD").stdout.strip().encode())
    for f in changed_paths(root):
        h.update(b"\0" + f.encode() + b"\0")
        try:
            h.update(open(os.path.join(root, f), "rb").read())
        except OSError:
            h.update("\0<нет файла>".encode())
    return h.hexdigest()


def state_path(root):
    d = os.environ.get("STATE_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "hooks", "state")
    return os.path.join(d, "affected-tests-%s.json" % hashlib.sha1(root.encode()).hexdigest()[:12])


def texts(lines):
    out = set()
    for ln in lines:
        for s in [m.group(2) for m in LIT.finditer(ln)] + [m.group(1) for m in MARKUP.finditer(ln)]:
            s = s.strip()
            if len(s) >= 3 and LETTER.search(s):
                out.add(s)
    return out


def gone_text(root, f):
    rm, add = [], []
    for ln in git(root, "diff", "HEAD", "--no-renames", "-U0", "--", f).stdout.split("\n"):
        if ln.startswith("-") and not ln.startswith("---"):
            rm.append(ln[1:])
        elif ln.startswith("+") and not ln.startswith("+++"):
            add.append(ln[1:])
    return texts(rm) - texts(add)


def name_rules(f):
    """Правила «тест называет файл»: в каждом — выражения, совпасть должны все. Общее имя — «каталог/имя» либо оба
    куска в кавычках (путь, собранный `path.join` по частям: `adv-b510-r2-sites-4`, скептик D1296, L4)."""
    parts = f.split("/")
    base, parent = parts[-1], (parts[-2] if len(parts) > 1 else "")
    stem = base.split(".")[0]
    word = lambda k: re.compile(r"(?<![\w-])" + re.escape(k) + r"(?![\w-])")
    quoted = lambda k: re.compile(r"[\"'`]" + re.escape(k) + r"[\"'`]")
    if stem in ("index", "__init__"):
        return [(word(parent or stem),)]
    if (stem in GENERIC or len(stem) < 4) and parent:
        return [(word(parent + "/" + stem),), (quoted(parent), quoted(base))]
    return [(word(stem),)] if stem else []


def helper_scans(root, test, src, cache):
    """Подключает ли тест относительным импортом помощника, который сам читает каталоги."""
    for m in IMPORT.finditer(src):
        rel = os.path.normpath(os.path.join(os.path.dirname(test), m.group(1)))
        for p in (rel + e for e in EXTS):
            if os.path.isfile(os.path.join(root, p)):
                if p not in cache:
                    try:
                        cache[p] = bool(SCAN.search(open(os.path.join(root, p), encoding="utf-8", errors="replace").read()))
                    except OSError:
                        cache[p] = False
                if cache[p]:
                    return True
                break
    return False


def select(root, changed):
    tests = [f for f in listed(root, "ls-files", "-co", "--exclude-standard") if TEST_NAME.search(os.path.basename(f))]
    body = {}
    for t in tests:
        try:
            body[t] = open(os.path.join(root, t), encoding="utf-8", errors="replace").read()
        except OSError:
            body[t] = ""
    rules = [r for f in changed if f not in body for r in name_rules(f)]
    gone = set()
    for f in changed:
        if f not in body:
            gone |= gone_text(root, f)
    pick = {"имя": set(f for f in changed if f in body), "сканер": set(), "текст": set()}
    helpers = {}
    for t, s in body.items():
        if any(all(x.search(s) for x in r) for r in rules):
            pick["имя"].add(t)
        if SCAN.search(s) or helper_scans(root, t, s, helpers):
            pick["сканер"].add(t)
        if any(re.search(DELIM_L + re.escape(g) + DELIM_R, s) for g in gone):
            pick["текст"].add(t)
    return pick, len(tests), len(gone)


def main(argv):
    root, files, mode = "", [], "set"
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--root" and i + 1 < len(argv):
            root = argv[i + 1]; i += 2; continue
        if a in ("--was-run", "--self-test"):
            mode = a[2:]
        else:
            files.append(a)
        i += 1
    if mode == "self-test":
        return self_test()
    top = toplevel(root or os.getcwd())
    if not top:
        print("affected-tests: не git-репозиторий: %s" % (root or os.getcwd()), file=sys.stderr)
        return 2
    sp = state_path(top)
    if mode == "was-run":
        if not any(TEST_NAME.search(os.path.basename(f)) for f in listed(top, "ls-files", "-co", "--exclude-standard")):
            return 0   # тестов в проекте нет — собирать нечего
        try:
            rec = json.load(open(sp))
        except (OSError, ValueError):
            return 1
        return 0 if rec.get("fingerprint") == fingerprint(top) else 1
    if not files:
        files = changed_paths(top)
    else:
        files = [os.path.relpath(os.path.abspath(f), top) if os.path.exists(f) else f for f in files]
    pick, n_tests, n_gone = select(top, files)
    out = sorted(set().union(*pick.values()))
    for t in out:
        print(t)
    print("затронутых тестов: %d из %d (по имени %d, сканеры дерева %d, со старым текстом %d; изменённых файлов %d, "
          "исчезнувших строк текста %d)" % (len(out), n_tests, len(pick["имя"]), len(pick["сканер"]), len(pick["текст"]),
                                             len(files), n_gone), file=sys.stderr)
    try:
        os.makedirs(os.path.dirname(sp), exist_ok=True)
        json.dump({"fingerprint": fingerprint(top), "root": top, "tests": out}, open(sp, "w"), ensure_ascii=False)
    except OSError as exc:
        print("affected-tests: след не записан (%s)" % exc, file=sys.stderr)
    return 0


def self_test():
    """Мир на фикстуре — по ноге на каждое правило набора и каждое условие следа (круг скептика D1296: прежняя
    самопроверка не краснела на 8 мутантах из 15). Правки: подпись «Воронка» → «Канбан» в словаре (подпись «Задачи» не
    меняется), страница `app/tasks/page.tsx`, модуль-каталог `lib/funnel/index.ts`, переименование `git mv`, файл с
    кириллицей в имени, новый неотслеживаемый файл."""
    me = os.environ["AT_SELF"]
    bad, legs = [], [0]
    def leg(ok, why):
        legs[0] += 1
        if not ok:
            bad.append(why)
    with tempfile.TemporaryDirectory() as top:
        d = os.path.join(top, "repo")   # след — вне судимого дерева: иначе запись следа меняет отпечаток
        def w(p, s, root=None):
            f = os.path.join(root or d, p)
            os.makedirs(os.path.dirname(f), exist_ok=True)
            open(f, "w", encoding="utf-8").write(s)
        F = {
            "web/lib/labels.ts": "export const L = { funnel: 'Воронка', tasks: 'Задачи' };\n",
            "web/lib/other.ts": "export const x = 1;\n",
            "web/lib/old-name.ts": "export const o = 1;\n",
            "web/lib/funnel/index.ts": "export const f = 1;\n",
            "web/lib/словарь.ts": "export const D = 'Старое';\n",
            "web/app/tasks/page.tsx": "export default function P() { return null; }\n",
            "web/tests/unit/labels.test.ts": "import { L } from '../../lib/labels';\n",
            "web/tests/unit/labelsx.test.ts": "import { y } from '../../lib/labelsExtra';\n",
            "web/tests/unit/registry.test.ts": "import fs from 'fs';\nfs.readdirSync('web/app');\n",
            "web/tests/unit/grep-scan.test.ts": "execSync(\"grep -rlE 'withX' app\");\n",
            "web/tests/unit/other.test.ts": "import { x } from '../../lib/other';\n",
            "web/tests/unit/old-name.test.ts": "import { o } from '../../lib/old-name';\n",
            "web/tests/unit/funnel.test.ts": "import { f } from '../../lib/funnel';\n",
            "web/tests/unit/dict.test.ts": "expect(D).toBe('Старое');\n",
            "web/tests/unit/tasks-page.test.ts": "readFileSync(path.join(ROOT, 'web', 'app', 'tasks', 'page.tsx'));\n",
            "web/tests/unit/sub.test.ts": "const s = 'ВоронкаПлюс';\n",
            "web/tests/support/places.ts": "import fs from 'fs';\nexport const P = fs.readdirSync('web/app');\n",
            "web/tests/unit/places.test.ts": "import { P } from '../support/places';\n",
            "web/tests/e2e/funnel.spec.ts": "await page.getByText('Воронка').click();\n",
            "web/tests/e2e/anchored.spec.ts": "await page.getByRole('button', { name: /^Воронка$/ }).click();\n",
            "web/tests/e2e/tasks.spec.ts": "await page.getByText('Задачи').click(); await page.goto('/x');\n",
        }
        for k, v in F.items():
            w(k, v)
        env = dict(os.environ, STATE_DIR=os.path.join(top, "st"), GIT_CONFIG_GLOBAL=os.devnull)
        def g(*a, root=None):
            return subprocess.run(["git", "-C", root or d, *a], capture_output=True, env=env)
        def commit(root=None):
            g("add", "-A", root=root)
            g("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "base", root=root)
        g("init", "-q"); commit()
        run = lambda *a, root=None: subprocess.run(["bash", me, "--root", root or d, *a], capture_output=True, text=True, env=env)
        w("web/lib/labels.ts", "export const L = { funnel: 'Канбан', tasks: 'Задачи' };\n")
        w("web/app/tasks/page.tsx", "export default function P() { return 1; }\n")
        w("web/lib/funnel/index.ts", "export const f = 2;\n")
        w("web/lib/словарь.ts", "export const D = 'Новое';\n")
        # Переименование простым `mv` с `git add -N`: индекс его не знает, и старое имя видно только в `git diff HEAD
        # --no-renames` (с распознаванием переименований — один новый путь). `git mv` видит и список индекса.
        os.rename(os.path.join(d, "web/lib/old-name.ts"), os.path.join(d, "web/lib/new-name.ts"))
        g("add", "-N", "web/lib/new-name.ts")
        w("web/lib/new.ts", "export const n = 1;\n")
        leg(run("--was-run").returncode == 1, "след до набора: --was-run не 1")
        p = run()
        got = set(p.stdout.split())
        want = {"web/tests/unit/labels.test.ts": "по имени", "web/tests/unit/registry.test.ts": "сканер",
                "web/tests/unit/grep-scan.test.ts": "сканер через grep -r",
                "web/tests/unit/places.test.ts": "сканер через помощника",
                "web/tests/e2e/funnel.spec.ts": "старый текст", "web/tests/e2e/anchored.spec.ts": "старый текст в /^…$/",
                "web/tests/unit/old-name.test.ts": "старое имя после git mv",
                "web/tests/unit/funnel.test.ts": "каталог модуля index",
                "web/tests/unit/dict.test.ts": "старый текст файла с кириллицей в имени",
                "web/tests/unit/tasks-page.test.ts": "общее имя page по кускам пути"}
        for t, why in want.items():
            leg(t in got, "не вошёл (%s): %s" % (why, t))
        for t, why in {"web/tests/unit/other.test.ts": "посторонний", "web/tests/unit/labelsx.test.ts": "имя без границы",
                       "web/tests/unit/sub.test.ts": "старый текст подстрокой",
                       "web/tests/e2e/tasks.spec.ts": "невернувшийся текст и голое page"}.items():
            leg(t not in got, "вошёл (%s): %s" % (why, t))
        leg(p.returncode == 0, "код набора %d" % p.returncode)
        leg(run("--was-run").returncode == 0, "след после набора: --was-run не 0")
        w("web/lib/new.ts", "export const n = 2;\n")
        leg(run("--was-run").returncode == 1, "след после правки неотслеживаемого: --was-run не 1")
        run()
        g("add", "-A")
        leg(run("--was-run").returncode == 0, "след после git add: --was-run не 0 (отпечаток зависит от индекса)")
        w("web/lib/other.ts", "export const x = 2;\n")
        leg(run("--was-run").returncode == 1, "след после новой правки: --was-run не 1")
        # Правка только в индексе (рабочее дерево вернули к HEAD): коммит её унесёт, отпечаток обязан её видеть.
        x = os.path.join(top, "ix")
        w("lib/a.ts", "export const a = 1;\n", root=x); w("tests/a.test.ts", "import { a } from '../lib/a';\n", root=x)
        g("init", "-q", root=x); commit(root=x)
        run(root=x)
        leg(run("--was-run", root=x).returncode == 0, "чистое дерево после набора: --was-run не 0")
        w("lib/a.ts", "export const a = 2;\n", root=x); g("add", "lib/a.ts", root=x)
        w("lib/a.ts", "export const a = 1;\n", root=x)
        leg(run("--was-run", root=x).returncode == 1, "правка только в индексе: --was-run не 1")
        e = os.path.join(top, "empty")
        w("README.md", "# x\n", root=e); g("init", "-q", root=e); commit(root=e)
        w("README.md", "# y\n", root=e)
        leg(run("--was-run", root=e).returncode == 0, "проект без тестов: --was-run не 0")
    if bad:
        print("самопроверка: КРАСНО — " + "; ".join(bad), file=sys.stderr)
        return 1
    print("самопроверка: %d из %d — правила набора, границы, след и проект без тестов" % (legs[0], legs[0]))
    return 0


sys.exit(main(sys.argv[1:]))
PY
