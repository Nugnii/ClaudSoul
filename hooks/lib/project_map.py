"""project_map — что в ЭТОМ проекте код, тест, что не смотреть и куда класть карту связей.

Спецификация: `.claude-docs/specs/2026-10-24-project-map-principle/spec.md`, шаг 1б.1 (решение владельца
24 октября 2026: «у каждого проекта свой бэклог и свои связи, функции, модули, скрипты — в проект
имплементируется принцип и там развивается»). Описание устройства живёт в самом проекте —
`<корень>/.claude-docs/project-map.json` — и растёт с ним; без описания действуют умолчания, равные прежним
правилам ClaudSoul.

ВЛАДЕЛЕЦ ОДИН. До этого модуля правило «механизм ли файл» стояло копиями: у учёта (`scripts/dep-index.py`,
MECH_RE/MECH_SKIP/TEST_RE) и у карты (`scripts/project-graph.py`, `_MECH_SKIP`/`_is_mech`/`_TEST_RE`, `node_kind`).
Теперь все зовут этот модуль.

ДОГОВОР ВХОДА (D1068). Описание приходит из чужого репозитория — граница доверия: поле не того типа, неизвестный
ключ или язык, пустой код, версия не 1 — отказ `DescriptorError` с
причиной, а не трейсбек и не молчаливые «механизмов 0». `--repo` — существующий корень git-дерева, одна форма из
двух (`--repo X`, `--repo=X`), без повтора. Код 0 обязан значить «построено для указанного проекта» (R6).
НАЗВАННЫЙ ПРЕДЕЛ шага 1б.1: языки разбора — shell и python; `tsjs` описание объявить может, учёт его не берёт до
шага 1в. `swift` (7 ноября 2026) — связи по именам объявлений верхнего уровня (`import_refs`), без сборки.
"""
import fnmatch
import functools
import json
import os
import re
import subprocess
import unicodedata

DEFAULTS = {
    "version": 1,
    "code": [{"glob": "**/*.sh", "lang": "shell"}, {"glob": "**/*.py", "lang": "python"}],
    "tests": ["**/test/**", "**/tests/**"],
    # `*__init__.py`, а не `__init__.py`: прежнее правило учёта `__init__\.py$` не имело левого якоря (F9).
    "ignore": ["templates/**", "scripts/publish/**", "**/*__init__.py"],
    # Шаг 1б.2: переменные, чьё значение — корень ЭТОГО проекта, и файлы-договоры (данные, которые код читает и пишет).
    # Умолчания общие; свои имена проект называет в описании (у ClaudSoul — `.claude-docs/project-map.json`).
    "repo_vars": ["REPO", "ROOT"],
    "contracts": ["BACKLOG.md", "ROOTS.md", "**/*.tsv", "**/*.json", "**/*.yml", "**/*.yaml", "**/*.toml"],
}
KNOWN_KEYS = ("version", "code", "tests", "ignore", "repo_vars", "contracts", "roots")
KNOWN_LANGS = ("shell", "python", "tsjs", "swift")
SUPPORTED_LANGS = ("shell", "python", "tsjs", "swift")
DESCRIPTOR = os.path.join(".claude-docs", "project-map.json")
INDEX_REL = os.path.join(".claude-docs", "dep-index.tsv")


class DescriptorError(Exception):
    """Описание проекта или корень не годятся: причина названа, учёт и карта не строятся."""


_PATHS_LIB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "paths-lib.sh")


def git(repo, *args):
    """`git -C repo …`, не исполняющий программ из настроек судимого дерева (шаг 1г, D1089).

    Учёт и карта судят и чужой проект (`--repo`), а голый git исполняет его `core.fsmonitor` (`ls-files`, `diff`),
    фильтры содержимого и `gpg.program` (замер D515). У правила уже есть владелец — `project_git` в
    `hooks/paths-lib.sh`; здесь его зовут, а не повторяют: вторая копия перечня погашенных программ разошлась бы с
    первой молча (корень R1). Цена — оболочка на вызов, 19 мс против 7 мс у голого git.
    Внешний diff и textconv настройкой не гасятся (`-c diff.external=` роняет git): вызов diff с содержимым передаёт
    `--no-ext-diff --no-textconv` сам, как `hooks/docs-family-check.sh` (D517).
    Библиотеки нет либо в ней нет функции: модуль лежит в самом судимом дереве (ClaudSoul судит себя, песочница теста с
    копией модуля и заглушкой `paths-lib.sh` как предметом) — голый git, как прежде: настройки этого дерева — владельца
    кода, который сейчас исполняется. Чужое дерево — отказ: исполнять программы его настроек нельзя.
    """
    if os.path.isfile(_PATHS_LIB):
        r = subprocess.run(["bash", "-c", '. "$1" >/dev/null 2>&1; declare -F project_git >/dev/null || exit 97; '
                            'shift; project_git "$@"', "_", _PATHS_LIB, "-C", repo, *args],
                           capture_output=True, text=True)
        if r.returncode != 97:
            return r
    if os.path.realpath(__file__).startswith(os.path.realpath(repo) + os.sep) or _own_git_dir(repo):
        return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    raise DescriptorError(f"{_PATHS_LIB}: нет функции project_git — git в чужом дереве не зову")


def _own_git_dir(repo):
    """Прочтёт ли git этого вызова настройки ТОГО репозитория, где лежит сам модуль.

    Своё дерево бывает двух видов, и нужны оба: модуль лежит ВНУТРИ судимого дерева (выгрузка коммита со своей копией
    прибора — код и так из этого дерева, его настройки не опаснее его кода; проверяется вложенностью у вызывающего) и
    модуль ВНЕ дерева, а git читает настройки его же репозитория (выгрузка индекса с `GIT_DIR` своего репозитория при
    приборе из рабочей копии — нога T24 `test_doc_impact_check.sh`). Здесь второе: судится каталог git. Каталог модуля
    спрашивается без `GIT_*` окружения — иначе унаследованный `GIT_DIR` чужого проекта ответил бы за модуль.
    `rev-parse` программ из настроек не исполняет.
    """
    def common(cwd, env):
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, env=env)
        return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None
    clean = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    mine = common(os.path.dirname(os.path.abspath(__file__)), clean)
    return mine is not None and mine == common(repo, None)


def glob_match(path, pattern):
    """Путь от корня против образца по КОМПОНЕНТАМ: `**` — ноль и более каталогов, прочее — `fnmatchcase` одного имени.

    `*` и `?` не пересекают `/`; скобки — буквально. Первая редакция переводила образец в одно регулярное выражение:
    `*a*a*…*b` откатывался полиномиально (D1070, F5); до неё перебор `**/` рос как факториал (D1068, F11).
    """
    pp = [c.replace("[", "[[]") for c in pattern.split("/")]
    sp = path.split("/")
    memo = {}

    def go(i, j):
        k = (i, j)
        if k not in memo:
            if i == len(pp):
                r = j == len(sp)
            elif pp[i] == "**" and i == len(pp) - 1:
                r = j < len(sp)                 # хвостовой `**` — один и более каталогов, не сам каталог (D1071, F8)
            elif pp[i] == "**":
                r = go(i + 1, j) or (j < len(sp) and go(i, j + 1))
            else:
                r = j < len(sp) and fnmatch.fnmatchcase(sp[j], pp[i]) and go(i + 1, j + 1)
            memo[k] = r
        return memo[k]
    return go(0, 0)


def _str_list(name, v, path):
    if not isinstance(v, list) or not all(isinstance(x, str) and x for x in v):
        raise DescriptorError(f"{path}: поле «{name}» — список непустых строк, а не {type(v).__name__}")
    return v


def load(repo):
    path = os.path.join(repo, DESCRIPTOR)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return dict(DEFAULTS, _source="умолчания")
    except (OSError, ValueError) as e:
        raise DescriptorError(f"{path}: {e}")
    if not isinstance(data, dict):
        raise DescriptorError(f"{path}: ожидался объект JSON")
    unknown = sorted(set(data) - set(KNOWN_KEYS))
    if unknown:
        raise DescriptorError(f"{path}: неизвестные поля {', '.join(unknown)}; допустимы {', '.join(KNOWN_KEYS)}")
    m = dict(DEFAULTS)
    if "code" in data:
        code = data["code"]
        if not isinstance(code, list) or not code:
            raise DescriptorError(f"{path}: поле «code» — непустой список {{glob, lang}}")
        for c in code:
            if not (isinstance(c, dict) and isinstance(c.get("glob"), str) and c["glob"]
                    and c.get("lang") in KNOWN_LANGS and set(c) <= {"glob", "lang"}):
                raise DescriptorError(f"{path}: элемент «code» {c!r} — нужен {{\"glob\": строка, \"lang\": "
                                      f"{' | '.join(KNOWN_LANGS)}}}")
        m["code"] = code
    for k in ("tests", "ignore", "contracts"):
        if k in data:
            m[k] = _str_list(k, data[k], path)
    if "repo_vars" in data:
        m["repo_vars"] = _str_list("repo_vars", data["repo_vars"], path)
        bad = [v for v in m["repo_vars"] if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", v)]
        if bad:
            raise DescriptorError(f"{path}: «repo_vars» — голые имена переменных (REPO, а не $REPO): {bad}")
    if "roots" in data:
        roots = data["roots"]
        if not isinstance(roots, list) or not all(
                isinstance(r, dict) and set(r) == {"dir", "tsconfig"}
                and all(isinstance(r[k], str) and r[k] and not os.path.isabs(r[k]) for k in r) for r in roots):
            raise DescriptorError(f"{path}: «roots» — список {{\"dir\": путь от корня, \"tsconfig\": путь от корня}}")
        m["roots"] = roots
    if "version" in data and type(data["version"]) is not int or data.get("version", 1) != 1:
        raise DescriptorError(f"{path}: «version» {data['version']!r} — эта редакция знает только 1")
    m["_source"] = path
    return m


def is_test(m, path):
    return any(glob_match(path, p) for p in m["tests"])


def code_lang(m, path):
    """Язык файла кода по описанию; None — не код (тест, не смотреть, неизвестный вид либо язык вне разбора)."""
    if is_test(m, path) or any(glob_match(path, p) for p in m["ignore"]):
        return None
    for c in m["code"]:
        if glob_match(path, c["glob"]) and c["lang"] in SUPPORTED_LANGS:
            return c["lang"]
    return None


def is_code(m, path):
    return code_lang(m, path) is not None


def lang_of(m, path):
    """Язык файла по образцам `code`, тест он или нет: импорты разбираются и у тестов (решение владельца 25.10.2026)."""
    for c in m["code"]:
        if glob_match(path, c["glob"]):
            return c["lang"]
    return None


# ИМПОРТЫ (шаг 1в). Ребро — импорт, РАЗРЕШЁННЫЙ в файл дерева (`universe`), а не встреча имени: пакет, путь вне дерева,
# `import(переменная)` ребра не дают. Один владелец правила для учёта (`deps`, `tests`) и карты (`body_deps`).
_JS_NOISE = re.compile(r"""("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)|//[^\n]*|/\*.*?\*/""", re.S)
_JS_SPEC = re.compile(r"""(?:\b(?:import|export)\s+(?:type\s+)?(?:[\w*{}\s,$]+?\s+from\s+)?"""
                      r"""|\b(?:require|import)\s*\(\s*|\b(?:vi|jest)\.(?:mock|doMock)\(\s*)(['"])([^'"\n]+)\1""")
_JS_EXT = (".ts", ".tsx", ".d.ts", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts")


def py_prose_rows(text):
    """Номера строк (с 1, по `\\n`) прозы питона — литерала в тройных кавычках, чей токен ОТКРЫВАЕТ свою строку
    (докстринг, строка-выражение); от строки открытия до строки закрытия. None — разбор не удался (обрывок, синтаксис
    новее интерпретатора): зовущий берёт прежний счёт кавычек.

    Один разбор для карты (`scripts/project-graph.py`, `code_lines`) и учёта (`scripts/dep-index.py`, `code_only`), D1286
    (корень R3): счёт тройных кавычек в строке читал строку, начатую ЗАКРЫВАЮЩЕЙ `'''` SQL-литерала, как начало докстринга
    и выбрасывал остаток файла — у Jurnalist (`tests/conftest.py:119`) пропадали строки 119–525 и с ними рёбра.
    Прежнее правило по смыслу сохранено — проза только та тройная кавычка, что открывает строку: многострочный литерал
    в выражении (`X = '''…`, аргумент) остаётся кодом, как было, и карта с учётом ClaudSoul не сдвигаются.
    f-строка с 3.12 — токены FSTRING_START…FSTRING_END, берутся так же. Двойник по устройству — `_py_string_rows`
    реестра родов (D1267, берёт ВСЕ многострочные литералы): его кэш ключуется текстом самого прибора, копия там своя."""
    import io as _io, tokenize as _tk
    lines = text.split("\n")
    fs_start, fs_end = getattr(_tk, "FSTRING_START", None), getattr(_tk, "FSTRING_END", None)

    def opens_line(tok):
        r, c = tok.start
        return 0 < r <= len(lines) and not lines[r - 1][:c].strip()

    def triple(s):
        body = s.lstrip("rRbBuUfF")
        return body.startswith('"""') or body.startswith("'''")

    rows, stack = set(), []
    try:
        for tok in _tk.generate_tokens(_io.StringIO(text).readline):
            if tok.type == _tk.STRING and opens_line(tok) and triple(tok.string):
                rows.update(range(tok.start[0], tok.end[0] + 1))
            elif fs_start is not None and tok.type == fs_start:
                stack.append(tok if (opens_line(tok) and triple(tok.string)) else None)
            elif fs_end is not None and tok.type == fs_end and stack:
                st = stack.pop()
                if st is not None:
                    rows.update(range(st.start[0], tok.end[0] + 1))
    except (_tk.TokenError, IndentationError, SyntaxError):
        return None
    return rows


def _strip_js_comments(text):
    """Комментарии JS/TS снимаются, строки остаются (`'http://x'` — не комментарий); переводы строк сохраняются."""
    return _JS_NOISE.sub(lambda mo: mo.group(1) or "\n" * mo.group(0).count("\n"), text)


# SWIFT (7 ноября 2026, слово владельца «Swift в карте нет»; выбор владельца — свой разбор по именам, без сборки и новых
# зависимостей). Файл в Swift не называет файл: модуль виден целиком, и `import` называет модуль, а не файл. Поэтому
# ребро A→B — имя, объявленное на верхнем уровне B (тип, `typealias`, функция, глобальная `let`/`var`), названное в
# коде A без комментариев и строк. Имя, объявленное в двух файлах, ребра не даёт никому — как голое имя у учёта
# (`scripts/dep-index.py`, `deps_of`): связь наугад хуже, чем никакой. Имя ЧУЖОГО модуля засчитывается, только если
# файл этот модуль импортирует (`import M`, `@testable import M`); модуль — каталог под `Sources/` или `Tests/` (раскладка
# SwiftPM), вне её — один общий модуль. Повод — замер на blalb 7 ноября 2026: глобальные `data`, `path`, `items`
# исполняемой цели `dictgen` давали ребро шести файлам приложения, которое `dictgen` не импортирует и видеть не может.
# ПОТОЛОК, названный: модификатор доступа не судится (`internal` чужого модуля засчитывается при импорте); члены типов (методы,
# свойства) и вложенные типы не судятся; имя внутри интерполяции строки `"\(Тип.x)"` снимается вместе со строкой;
# вложенный блочный комментарий `/* /* */ */` закрывается первым `*/`; локальная переменная с именем глобальной
# функции даёт ложное ребро. Переход при нехватке точности — индекс компилятора (Periphery, indexstore-db).
# ПРЕДЕЛЫ (частота 0 на blalb 7 ноября 2026, скептик opus по 9dc31762): модуль вне раскладки SwiftPM (Tuist/XcodeGen
# `App/Sources/…`, цели с `path:` в Package.swift) и `@_exported import` не различаются; `##"…"#…"##` закрывается
# первым `"#`, строки внутри интерполяции утекают как код, сырая многострочная строка в начале строки; теряются `public private(set) var`,
# `let (a, b) =`, второе имя в `let a = 1, b = 2`, `macro`, `distributed actor`, атрибут со вложенными скобками;
# `class var`/`class func` с первой колонки дали бы имя `var`/`func`; `propose` при корнях TS теряет `**/Tests/**`;
# `package` в Package.swift вне раскладки; имя, объявленное в двух модулях, выбывает целиком.
_SWIFT_NOISE = re.compile(r'"{3}(?:\\.|[^\\])*?"{3}|#+"(?:[^"\n]|"(?!#))*"#+|"(?:\\.|[^"\\\n])*"|//[^\n]*|/\*.*?\*/', re.S)
_SWIFT_DECL = re.compile(r"^(?:@\w+(?:\([^)\n]*\))?\s+)*(?:(?:public|internal|private|fileprivate|open|package|final|"
                         r"indirect|nonisolated|static|lazy|nonisolated\(unsafe\))\s+)*"
                         r"(?:class|struct|enum|protocol|actor|typealias|func|let|var)\s+`?([A-Za-z_]\w*)", re.M)
_SWIFT_WORD = re.compile(r"\b[A-Za-z_]\w*\b")
_SWIFT_IMPORT = re.compile(r"^[ \t]*(?:@\w+[ \t]+)*import[ \t]+(?:(?:struct|class|enum|protocol|func|var|let|typealias)[ \t]+)?"
                           r"(\w+)", re.M)


def _swift_module(path):
    """Модуль файла по раскладке SwiftPM — каталог под первым `Sources/` или `Tests/`; вне раскладки — пустая строка."""
    parts = path.split("/")
    for i, c in enumerate(parts[:-2]):
        if c in ("Sources", "Tests"):
            return parts[i + 1]
    return ""


def _swift_words(body, modules):
    """Слова кода, способные назвать имя верхнего уровня (D1264): слово после одиночной `.` — член чужого значения
    (`menu.delegate`, `.shared`), а не имя файла; исключение — полное имя `Модуль.Тип`, где перед точкой видимый модуль.
    Диапазон `a...b`/`a..<b` членом не считается. Прежде слово судилось совпадением, а не местом: на blalb ребро
    `AppDelegate.swift` → `main.swift` держалось только на `.delegate`."""
    out = set()
    for mo in _SWIFT_WORD.finditer(body):
        i = mo.start() - 1
        while i >= 0 and body[i] in " \t\n":
            i -= 1
        if i >= 0 and body[i] == "." and not (i > 0 and body[i - 1] == "."):
            j = i - 1
            while j >= 0 and body[j] in " \t\n":
                j -= 1
            k = j
            while k >= 0 and (body[k].isalnum() or body[k] == "_"):
                k -= 1
            # Перед точкой не имя (`center().delegate`, `.red`, `a?.b`) — член: пустой срез совпал бы с модулем «» файла
            # вне раскладки SwiftPM и провёл бы любой член (скептик opus D1264, M1).
            if k == j or body[k + 1:j + 1] not in modules:
                continue
        out.add(mo.group(0))
    return out


def _swift_code(text):
    """Код Swift без комментариев и литералов строк; переводы строк сохраняются (места строк не съезжают)."""
    return _SWIFT_NOISE.sub(lambda mo: "\n" * mo.group(0).count("\n"), text)


@functools.lru_cache(maxsize=None)
def _swift_index(repo, files):
    """{имя: файл} для имён верхнего уровня, объявленных ровно в одном файле из `files` (кортеж путей от корня).

    `private` и `fileprivate` на верхнем уровне видны только своему файлу — в перечень не входят (замер на blalb 7 ноября
    2026: 7 таких имён, чужие файлы называли их 9 раз; новых рёбер это там не дало — те же файлы связаны и другими
    именами, — но совпадение слова с чужим частным именем ребром быть не может)."""
    seen = {}
    for f in files:
        try:
            with open(os.path.join(repo, f), encoding="utf-8", errors="replace") as fh:
                names = {mo.group(1) for mo in _SWIFT_DECL.finditer(_swift_code(fh.read()))
                         if not re.search(r"\b(?:private|fileprivate)\b", mo.group(0))}
        except OSError:
            continue
        for n in names:
            seen.setdefault(n, set()).add(f)
    return {n: next(iter(fs)) for n, fs in seen.items() if len(fs) == 1}


def _read_jsonc(path):
    """tsconfig — JSON с комментариями и висячими запятыми; `"./*"` внутри строки комментарием не считается."""
    with open(path, encoding="utf-8") as f:
        t = _strip_js_comments(f.read())
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", t))


@functools.lru_cache(maxsize=None)
def _ts_aliases(repo, tsconfig):
    """[(образец, [цели от корня проекта])] и каталог baseUrl из tsconfig (с цепочкой относительных `extends`).

    Пути `paths` считаются от `baseUrl`, а без него — от каталога конфига, который их объявил. НАЗВАННЫЙ ПРЕДЕЛ: `extends`
    пакетом (`@tsconfig/node18`) не раскрывается; конфиг, которого нет или который не разбирается, псевдонимов не даёт.
    """
    chain, p = [], os.path.join(repo, tsconfig)
    for _ in range(8):
        try:
            cfg = _read_jsonc(p)
        except (OSError, ValueError):
            break
        chain.append((os.path.dirname(p), cfg.get("compilerOptions") or {}))
        ext = cfg.get("extends")
        if not (isinstance(ext, str) and ext.startswith(".")):
            break
        p = os.path.normpath(os.path.join(os.path.dirname(p), ext if ext.endswith(".json") else ext + ".json"))
    base_url, paths, paths_dir = None, {}, None
    for d, co in reversed(chain):                       # потомок перекрывает предка
        if isinstance(co.get("baseUrl"), str):
            base_url = os.path.normpath(os.path.join(d, co["baseUrl"]))
        if isinstance(co.get("paths"), dict):
            paths, paths_dir = co["paths"], d
    root = base_url or paths_dir
    rel = lambda a: os.path.relpath(a, repo)
    out = [(k, [rel(os.path.normpath(os.path.join(root, v))) for v in vs if isinstance(v, str)])
           for k, vs in paths.items() if isinstance(vs, list)] if root else []
    return out, (rel(base_url) if base_url else None)


def _ts_resolve(m, repo, path, spec, universe):
    bases = []
    if spec.startswith("./") or spec.startswith("../"):
        bases.append(os.path.normpath(os.path.join(os.path.dirname(path), spec)))
    else:
        roots = [r for r in m.get("roots", ()) if r["dir"] in (".", "") or path.startswith(r["dir"].rstrip("/") + "/")]
        if roots:
            aliases, base_url = _ts_aliases(repo, max(roots, key=lambda r: len(r["dir"]))["tsconfig"])
            for k, targets in aliases:
                if "*" in k:
                    pre, suf = k.split("*", 1)
                    if spec.startswith(pre) and spec.endswith(suf) and len(spec) >= len(pre) + len(suf):
                        star = spec[len(pre):len(spec) - len(suf)]
                        bases += [t.replace("*", star, 1) for t in targets]
                elif spec == k:
                    bases += targets
            if base_url is not None:
                bases.append(os.path.normpath(os.path.join(base_url, spec)))
    for b in bases:
        stem, ext = os.path.splitext(b)
        cands = [b] + ([stem + e for e in (".ts", ".tsx", ".mts", ".cts")] if ext in (".js", ".jsx", ".mjs", ".cjs") else [])
        cands += [b + e for e in _JS_EXT] + [b + "/index" + e for e in _JS_EXT]
        for c in cands:
            if c in universe:
                return c
    return None


_PY_IMPORT = re.compile(r"^[ \t]*import[ \t]+([\w.]+(?:[ \t]+as[ \t]+\w+)?(?:[ \t]*,[ \t]*[\w.]+(?:[ \t]+as[ \t]+\w+)?)*)",
                        re.M)
_PY_FROM = re.compile(r"^[ \t]*from[ \t]+(\.*)([\w.]*)[ \t]+import[ \t]+(\([^)]*\)|[^\n#;]+)", re.M)


def _py_module(universe, base, parts):
    p = "/".join(([base] if base else []) + parts)
    for c in (p + ".py", p + "/__init__.py"):
        if c in universe:
            return c
    return None


def _py_resolve_abs(universe, path, parts, by_name):
    """Абсолютный импорт: каталог скрипта (первый в пути поиска), затем корень дерева, затем — для одиночного имени вне
    стандартной библиотеки — единственный модуль с таким именем в дереве (каталог из `sys.path.insert`, которого
    статически не вычислить). Неоднозначное имя ребра не даёт."""
    for base in (os.path.dirname(path), ""):
        hit = _py_module(universe, base, parts)
        if hit:
            return hit
    if len(parts) == 1 and parts[0] not in getattr(__import__("sys"), "stdlib_module_names", ()):
        cands = by_name.get(parts[0] + ".py", [])
        return cands[0] if len(cands) == 1 else None
    return None


def import_refs(m, repo, path, code, universe):
    """Файлы дерева, в которые разрешаются импорты `code` (строки кода файла `path`, комментарии вызывающий снял сам).

    TS/JS: `import … from`, `export … from`, `import '…'`, `require('…')`, `import('…')`, `vi.mock('…')` — относительный
    путь и псевдоним из tsconfig корня (`roots`), подбор расширения и `index.*`. Python: `import a.b`, `from a.b import
    c` (и подмодуль `a/b/c.py`), `from .m import n`, `from . import m`. НАЗВАННЫЕ ПРЕДЕЛЫ: шаблонная строка и
    переменная в `import()`; `python -m` с иным путём поиска; регулярное выражение с кавычкой внутри в JS.
    """
    lang = lang_of(m, path)
    out = set()
    if lang == "tsjs":
        for mo in _JS_SPEC.finditer(_strip_js_comments(code)):
            hit = _ts_resolve(m, repo, path, mo.group(2), universe)
            if hit and hit != path:
                out.add(hit)
    elif lang == "swift":
        # Текст — с диска, а не от вызывающего: тот снимает строки, начатые `#`, а в Swift это код — `#expect(…)` Swift
        # Testing (скептик opus по 9dc31762, H2: на blalb 290 таких строк в 12 тестах из 13, потеряны 2 связи «тест →
        # файл»), `#if`, `#Preview`. Не прочитан — то, что дали.
        try:
            with open(os.path.join(repo, path), encoding="utf-8", errors="replace") as fh:
                code = fh.read()
        except OSError:
            pass
        idx = _swift_index(repo, tuple(sorted(u for u in universe if lang_of(m, u) == "swift")))
        body = _swift_code(code)
        seen = {_swift_module(path)} | set(_SWIFT_IMPORT.findall(body))
        out.update(f for f in (idx.get(w) for w in _swift_words(body, seen)) if f and _swift_module(f) in seen)
    elif lang == "python":
        by_name = {}
        for u in universe:
            if u.endswith(".py"):
                by_name.setdefault(u.rsplit("/", 1)[-1], []).append(u)
        for mo in _PY_IMPORT.finditer(code):
            for item in mo.group(1).split(","):
                hit = _py_resolve_abs(universe, path, item.split()[0].split("."), by_name)
                if hit:
                    out.add(hit)
        for mo in _PY_FROM.finditer(code):
            dots, mod = mo.group(1), mo.group(2)
            names = [n.split()[0] for n in mo.group(3).strip("() \t\n").replace("\n", " ").split(",") if n.strip()]
            parts = [p for p in mod.split(".") if p]
            if dots:
                base = os.path.dirname(path)
                for _ in range(len(dots) - 1):
                    base = os.path.dirname(base)
                target = _py_module(universe, base, parts) if parts else None
                pkg_dir = "/".join(([base] if base else []) + parts)
            else:
                target = _py_resolve_abs(universe, path, parts, by_name) if parts else None
                pkg_dir = target[:-len("/__init__.py")] if target and target.endswith("/__init__.py") else None
            if target:
                out.add(target)
            for n in names:
                if pkg_dir is not None and n != "*":
                    sub = _py_module(universe, pkg_dir, [n])
                    if sub:
                        out.add(sub)
    out.discard(path)
    return out


def is_contract(m, repo, path):
    """Файл-договор: подходит образцу `contracts`, не код (и не тестовый код), не «не смотреть», не кэш карты.

    Данные в каталоге тестов — договоры: реестры `hooks/tests/costly-justified.tsv` и `always-run.tsv` читают механизмы
    (скептик 72d00022, F2: у них оставалось «на нём стоят 0»). Исключён тестовый КОД — файл под образцом `code`.
    """
    if is_code(m, path) or any(glob_match(path, p) for p in m["ignore"]):
        return False
    if is_test(m, path) and any(glob_match(path, c["glob"]) for c in m["code"]):
        return False
    return any(glob_match(path, p) for p in m["contracts"]) and not is_map_output(m, repo, path)


_TOKEN = re.compile(r"[\w.\-/]+")
_RB = r"(?![\w.\-])"                       # правая граница: `BACKLOG.md-old`, `foo.md.bak`, `x.tsv5` — не договор (F8)


@functools.lru_cache(maxsize=None)
def _ref_re(path, repo_vars):
    """Формы, в которых литерал РАЗРЕШАЕТСЯ в путь договора от корня (спецификация §2, урок F1/F3/F8 D1067).

    · путь от корня с левой границей (начало, пробел, кавычка, `=`, `(`, обратная кавычка) — только у пути с `/`:
      у файла в корне путь равен имени, а голое имя ребра не даёт никогда (F1: `rules/CLAUDE.md`, `$dir/CLAUDE.md`);
    · после переменной корня: `$V/…`, `${V}/…`, `${V:-…}/…`, `"$V"/…`; в Python — `V / "…"`, `join(V, "…")`, `{V}/…`,
      а также путь по звеньям — `join(V, "a", "b.tsv")`, `V / "a" / "b.tsv"` (D1075: так учёт читают `project-graph.py:95`);
    · путь объекта git `<ревизия>:<путь>` — он от корня по определению.
    """
    p = re.escape(path)
    vs = "|".join(map(re.escape, repo_vars)) or r"(?!)"
    forms = [r"\$(?:(?:" + vs + r")(?![A-Za-z0-9_])|\{(?:" + vs + r")(?::-[^}\n]*)?\})\"?/" + p,
             r"(?<![A-Za-z0-9_.])(?:" + vs + r")\s*/\s*[\"']" + p,
             r"join\(\s*(?:" + vs + r")\s*,\s*[\"']" + p,
             r"\{(?:" + vs + r")\}/" + p,
             r"(?:^|(?<=[\s\"'=(`]))[\w.~^@{}/\-]+:" + p]
    if "/" in path:
        q = [r"[\"']" + re.escape(x) + r"[\"']" for x in path.split("/")]
        forms += [r"(?:^|(?<=[\s\"'=(`]))" + p,
                  r"join\(\s*(?:" + vs + r")\s*,\s*" + r"\s*,\s*".join(q),
                  r"(?<![A-Za-z0-9_.])(?:" + vs + r")\s*/\s*" + r"\s*/\s*".join(q)]
    return re.compile("(?:" + "|".join(forms) + ")" + _RB)


def contract_refs(m, text, contracts):
    """{договор: [(номер строки, начало, конец)]} — где в `text` литерал разрешается в путь договора из `contracts`.

    Один владелец правила для учёта (колонка `deps`) и карты (`body_deps`, роль ребра): инкремент равен сборке по
    построению (D430). `text` — строки кода, комментарии вызывающий снимает сам.
    НАЗВАННЫЕ ПРЕДЕЛЫ: путь, собранный из переменных (`"$D/$N.tsv"`) или звеньями вперемешку (`join(V, "a/b", "c")`),
    и путь через переменную иного имени, чем в `repo_vars`, ребра не дают — их называет оговорка карточки карты
    (`unresolved_namers`, `scripts/project-graph.py`); роль записи через переменную судит карта (`contract_kind`).
    """
    by_base = {}
    for c in contracts:
        by_base.setdefault(c.rsplit("/", 1)[-1], []).append(c)
    vs = tuple(m.get("repo_vars") or ())
    out = {}
    for i, line in enumerate(text.split("\n")):
        cands = {c for t in _TOKEN.findall(line) for c in by_base.get(t.rsplit("/", 1)[-1], ())}
        for c in cands:
            hit = _ref_re(c, vs).search(line)
            if hit:
                out.setdefault(c, []).append((i, hit.start(), hit.end()))
    return out


def graph_out(m, repo):
    """Куда класть карту: прежнее место ClaudSoul, если каталог дашборда есть; иначе .claude-docs/ проекта.

    Путь записи описание не выбирает (D1070): поле `graph_out` 1б.1 давало чужому репозиторию писать куда угодно —
    через ссылку наружу, поверх файла другим регистром, поверх неотслеживаемого; любая проверка произвольного пути
    дырява, поэтому выбора нет вовсе (в спецификации его и не было).
    """
    legacy = os.path.join(repo, "mcp-server", "visualization")
    if os.path.isdir(legacy):
        return os.path.join(legacy, "project-graph-data.json")
    return os.path.join(repo, ".claude-docs", "project-graph.json")


def safe_output(repo, path):
    """Писать в `path` можно, только если каталог записи после раскрытия ссылок внутри проекта и сам файл не ссылка.

    Брат корня D1070: `.claude-docs` чужого репозитория бывает ссылкой наружу — учёт и карта шли бы по ней.
    """
    real_repo = os.path.realpath(repo)
    d = os.path.dirname(path)
    while not os.path.lexists(d) and os.path.dirname(d) != d:
        d = os.path.dirname(d)
    if os.path.islink(d) and not os.path.exists(d):
        raise DescriptorError(f"запись {path}: {d} — висячая ссылка")      # D1071, F6
    real_dir = os.path.realpath(d)
    if real_dir != real_repo and not real_dir.startswith(real_repo + os.sep):
        raise DescriptorError(f"запись {path}: каталог ведёт вне проекта ({real_dir})")
    for aux in (path, path + ".lock"):               # замок писателя — тоже запись (D1071, F3)
        if os.path.islink(aux):
            raise DescriptorError(f"запись {aux}: ссылка, по ней не пишу")


def rel_path(repo, path, known=()):
    """Путь от корня проекта — один владелец для учёта и карты (D1071, F2: две копии ломались на ссылке в пути).

    Каталоги раскрываются с обеих сторон (`/tmp` и `/private/tmp` на macOS — одно), сам файл — нет: файл-ссылка внутри
    проекта остаётся своим путём. Вне проекта — путь с `..` в начале; судит вызывающий (`outside`).
    Относительный путь — от корня проекта, у учёта и карты одинаково и из любого каталога вызова (D1073): так объявлен
    вход учёта, так его зовут с `--repo` извне и так пути отдаёт git. `..` решает файловая система, а не текст:
    `ссылка/../x` — родитель цели ссылки (`abspath` схлопывал его до `x`). Имя с диска: на нечувствительной к регистру
    системе `X/a.sh` и `.GIT` — те же `x/a.sh` и `.git`, и ключ один.
    ИМЯ, КОТОРОЕ ВЛАДЕЛЕЦ КЛЮЧЕЙ УЖЕ ЗНАЕТ, — КАК ЕСТЬ (D1073, второй круг по скептику). `known` — ключи вызывающего:
    у учёта строки учёта и файлы git, у карты её узлы. Ключ — имя git, а не то, под которым диск видит файл сейчас:
    перевод по диску менял NFC-имя git на NFD с диска и путь файла, удалённого коммитом (`git mv b.sh B.sh`, каталог за
    ссылкой совместимости), на нынешний — и учёт терял зависимых. По диску переводится только незнакомое имя.
    Знакомое сверяется в любой форме входа (третий круг): текстом (`text_rel`: `./`, абсолютный) и после раскрытия
    каталогов (`..`, корень через иной псевдоним) — прежде сверялся только относительный путь без `./`.
    """
    k = _known(text_rel(repo, path), known) if known else None
    if k:                                            # знакомое текстом — без второго `realpath` (L4 четвёртого круга)
        return k
    a = os.path.join(repo, path)                     # абсолютный `path` join отдаёт как есть
    root = os.path.realpath(repo)
    rel = os.path.relpath(os.path.join(os.path.realpath(os.path.dirname(a)), os.path.basename(a)), root)
    if rel == "." or outside(rel):
        return rel
    return _known(rel, known) or _disk_case(root, rel)


def _same(p, st):
    """Путь `p` указывает на тот же каталог, что и `st`."""
    try:
        return os.path.samestat(os.stat(p), st)
    except OSError:
        return False


def _known(p, known):
    """Ключ владельца для `p` (как есть либо NFC-форма) или None."""
    return next((q for q in (p, unicodedata.normalize("NFC", p)) if q in known), None) if p else None


def text_rel(repo, path):
    """Путь от корня ТЕКСТОМ, имена звеньев как даны (D1073, третий круг): `./`, двойная черта и корень (как дан и после
    раскрытия ссылок) снимаются. Звено `..` решает файловая система, но только до ПОСЛЕДНЕГО `..`: кусок до него
    раскрывается `realpath`, хвост остаётся текстом (четвёртый круг, L1/M1 скептика: раскрытие всего каталога уводило
    `docs/../tools/b.sh` за ссылкой совместимости в `bin/b.sh`). None — путь вне корня либо его каталог на диске ведёт
    вне дерева (знакомый узел, чей каталог заменён ссылкой наружу, — не тот файл, L-C скептика): такой путь решает диск.
    """
    root, parts = os.path.realpath(repo), path.split(os.sep)
    if ".." in parts:
        k = len(parts) - 1 - parts[::-1].index("..")
        head = os.path.realpath(os.path.join(repo, os.sep.join(parts[:k + 1]) or os.sep))
        if not (head == root or head.startswith(root + os.sep)):
            return None
        path = os.path.join(os.path.relpath(head, root), *parts[k + 1:])
    t = os.path.normpath(path)
    if os.path.isabs(t):
        # Корень — кратчайший префикс пути, который есть корень как дан, после `realpath` или указывает на него через
        # иной псевдоним (`/var` ↔ `/private/var`): раскрывать весь путь нельзя — ссылка совместимости внутри дерева
        # увела бы `tools/b.sh` в `bin/b.sh`. Псевдоним судит `stat` префикса (L4: `realpath` на каждом префиксе был
        # квадратичен по глубине).
        try:
            rst = os.stat(root)
        except OSError:
            return None
        parts = t.split(os.sep)
        r = next((p for p in (os.sep.join(parts[:i]) for i in range(2, len(parts)))
                  if p in (os.path.abspath(repo), root) or _same(p, rst)), None)
        if r is None:
            return None
        t = t[len(r) + 1:]
    if t == ".":
        return None
    d = os.path.realpath(os.path.join(root, os.path.dirname(t)))
    return t if d == root or d.startswith(root + os.sep) else None


_NAMES = {}


def _names(d):
    """Имена каталога — один `listdir` на каталог за процесс (D1073: на каждом звене каждого пути 5000 имён стоили 7 с).

    Предел: долгоживущий процесс увидит каталог таким, каким застал его впервые; вызывающие — разовые запуски учёта и
    карты. Условие снятия: модуль начнёт звать процесс, живущий дольше одного прогона.
    """
    n = _NAMES.get(d)
    if n is None:
        n = _NAMES[d] = set(os.listdir(d))
    return n


def _disk_case(root, rel):
    """Имена пути так, как они записаны на диске; с первого несуществующего звена — как написаны (D1073)."""
    parts, out, cur = rel.split(os.sep), [], root
    for i, comp in enumerate(parts):
        try:
            st, names = os.lstat(os.path.join(cur, comp)), _names(cur)
        except OSError:
            return os.path.join(*out, *parts[i:])
        if comp not in names:
            key = unicodedata.normalize("NFC", comp).casefold()
            comp = next((n for n in names if unicodedata.normalize("NFC", n).casefold() == key
                         and os.path.samestat(os.lstat(os.path.join(cur, n)), st)), comp)
        out.append(comp)
        cur = os.path.join(cur, comp)
    return os.path.join(*out)


def outside(rel):
    return rel == ".." or rel.startswith(".." + os.sep)


def is_map_output(m, repo, rel):
    """Кэш карты и его замок — не узлы самой карты (F1). Учёт — узел-реестр карты, его сюда не включать.

    Сравнение без регистра (D1073): замка ещё нет на диске, и имя с диска регистр `….json.LOCK` не поправит.
    """
    g = os.path.relpath(graph_out(m, repo), repo).casefold()
    r = rel.casefold()
    return r == g or r.startswith(g + ".lock")


def is_output(m, repo, rel):
    """Выход инструментов (учёт, кэш карты, замок) — не носитель механизмов в учёте (F1)."""
    return rel == INDEX_REL or is_map_output(m, repo, rel)


_TSJS_EXT = ("ts", "tsx", "js", "jsx", "mjs", "cjs", "mts", "cts")


def propose(repo):
    """Описание проекта по его дереву (шаг 1д): языки — по расширениям отслеживаемых файлов, корни TS — по найденным
    `tsconfig.json`. Возвращает dict формата DESCRIPTOR; `/init-project` пишет его, если описания ещё нет.

    Консервативно: shell/python добавляются при наличии таких файлов; `tsjs` — только под каталогами, где лежит
    `tsconfig.json` (корни). Пустой проект (ни одного файла языка) — умолчания shell/python, чтобы описание было валидным.
    Предложение — не истина: это стартовая точка, которую владелец правит руками (`.claude-docs/project-map.json`).
    """
    out = git(repo, "ls-files", "-z")
    files = [f for f in out.stdout.split("\0") if f]
    exts = {f.rsplit(".", 1)[-1] for f in files if "." in f.rsplit("/", 1)[-1]}
    roots = sorted({os.path.dirname(f) for f in files if os.path.basename(f) == "tsconfig.json"})
    code = []
    if any(f.endswith(".sh") for f in files):
        code.append({"glob": "**/*.sh", "lang": "shell"})
    if any(f.endswith(".py") for f in files):
        code.append({"glob": "**/*.py", "lang": "python"})
    swift = any(f.endswith(".swift") for f in files)
    if swift:
        code.append({"glob": "**/*.swift", "lang": "swift"})
    roots_out = []
    for r in roots:
        pre = (r + "/") if r else ""
        here = {f.rsplit(".", 1)[-1] for f in files if f.startswith(pre) and "/" in f[len(pre):] + "/"}
        for e in _TSJS_EXT:
            if e in here and e in exts:
                code.append({"glob": f"{pre}**/*.{e}", "lang": "tsjs"})
        roots_out.append({"dir": r or ".", "tsconfig": f"{pre}tsconfig.json"})
    if not code:
        code = [{"glob": "**/*.sh", "lang": "shell"}, {"glob": "**/*.py", "lang": "python"}]
    m = {"version": 1, "code": code, "tests": list(DEFAULTS["tests"]) + (["**/Tests/**"] if swift else [])}
    if roots_out:
        m["tests"] = list(DEFAULTS["tests"]) + ["**/*.test.ts", "**/*.test.tsx", "**/*.spec.ts"]
        m["roots"] = roots_out
    return m


def repo_arg(argv):
    """`--repo X` либо `--repo=X` — существующий корень git-дерева; снимается из argv. None — флага нет."""
    hits = [i for i, a in enumerate(argv) if a == "--repo" or a.startswith("--repo=")]
    if not hits:
        return None
    if len(hits) > 1:
        raise DescriptorError("--repo указан больше одного раза")
    i = hits[0]
    if argv[i] == "--repo":
        if i + 1 >= len(argv) or argv[i + 1].startswith("-"):
            raise DescriptorError("--repo без пути")
        p = argv[i + 1]
        del argv[i:i + 2]
    else:
        p = argv[i][len("--repo="):]
        del argv[i]
    if not p:
        raise DescriptorError("--repo без пути")
    real = os.path.realpath(p)
    if not os.path.isdir(real):
        raise DescriptorError(f"--repo {p!r}: каталога нет")
    top = git(real, "rev-parse", "--show-toplevel")
    if top.returncode != 0 or os.path.realpath(top.stdout.strip()) != real:
        raise DescriptorError(f"--repo {p!r}: не корень git-дерева")
    return os.path.abspath(p)


if __name__ == "__main__":
    import sys
    # `--propose <repo>` печатает предложенное описание по дереву (шаг 1д, для /init-project); иначе — самопроверка.
    if "--propose" in sys.argv:
        _pi = sys.argv.index("--propose")
        _pr = sys.argv[_pi + 1] if _pi + 1 < len(sys.argv) else os.getcwd()
        try:
            print(json.dumps(propose(_pr), ensure_ascii=False, indent=2))
            sys.exit(0)
        except DescriptorError as _e:
            print(f"project_map: {_e}", file=sys.stderr)
            sys.exit(2)
    m = load(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
    assert glob_match("top-level-probe.sh", "**/*.sh") and glob_match("a/b.sh", "**/*.sh")
    assert glob_match("lib/m.py", "lib/**/*.py") and glob_match("lib/a/b.py", "lib/**/*.py")
    assert not glob_match("other/m.py", "lib/**/*.py") and not glob_match("scripts/sub/x.py", "scripts/*.py")
    assert glob_match("docs/[draft]/x.md", "docs/[draft]/**") and glob_match("a.sh", "**")
    import time; _t = time.time(); glob_match("a" * 40, "*a*a*a*a*a*a*a*a*b"); assert time.time() - _t < 0.5
    assert is_test(DEFAULTS, "hooks/tests/x.sh") and is_test(DEFAULTS, "tests/x.py")
    assert not is_test(DEFAULTS, "hooks/tests_dir/x.sh")
    assert code_lang(DEFAULTS, "templates/x.sh") is None and code_lang(DEFAULTS, "a/__init__.py") is None
    assert code_lang(DEFAULTS, "a/foo__init__.py") is None
    assert not is_test(DEFAULTS, "tests") and is_test(DEFAULTS, "tests/x") and not outside("..odd.sh")
    assert code_lang(DEFAULTS, "scripts/x.py") == "python" and code_lang(DEFAULTS, "web/a.ts") is None
    # Образцы — договоры, которых в дереве нет: сама самопроверка не должна становиться читателем (урок sk1068).
    _c = {"LEDGER.md", "rules/GUIDE.md", "GUIDE.md", "data/r.tsv", "docs/foo.md"}
    _r = lambda s: set(contract_refs(DEFAULTS, s, _c))
    assert _r('B="$REPO/LEDGER.md"') == {"LEDGER.md"} and _r('x=${X:-${ROOT:-/a b}/LEDGER.md}') == {"LEDGER.md"}
    assert _r('cat LEDGER.md') == set() and _r('cat "$dir/GUIDE.md"') == set()            # голое имя, чужая переменная
    assert _r('cat "$REPO/rules/GUIDE.md"') == {"rules/GUIDE.md"}                          # F1: не корневой GUIDE.md
    assert _r('x LEDGER.md-old ЖLEDGER.md docs/foo.md.bak') == set()                      # F8
    assert _r('source data/r.tsv') == {"data/r.tsv"} and _r('git show HEAD:LEDGER.md') == {"LEDGER.md"}
    assert _r('p = ROOT / "LEDGER.md"') == {"LEDGER.md"} and _r('os.path.join(REPO, "data/r.tsv")') == {"data/r.tsv"}
    assert _r('cat x/data/r.tsv') == set() and _r('cat "$HOME/data/r.tsv"') == set()      # хвост чужого пути, F3
    # Swift: имена верхнего уровня, без комментариев и строк; член типа и вложенный тип — не объявления файла.
    _sw = 'import Foundation\n@MainActor\npublic final class Engine {\n    struct Inner {}\n    func run() {}\n}\n' \
          'enum Mode { case a }\nfunc helper() {}\nlet table = 1\n// struct Ghost {}\nlet s = "struct Fake"\n'
    assert set(_SWIFT_DECL.findall(_swift_code(_sw))) == {"Engine", "Mode", "helper", "table", "s"}
    assert "Ghost" not in _swift_code(_sw) and "Fake" not in _swift_code(_sw) and _swift_code(_sw).count("\n") == 11
    assert _swift_module("Sources/App/a.swift") == "App" and _swift_module("Pkg/Tests/T/x/b.swift") == "T"
    assert _swift_module("Package.swift") == "" and _swift_module("Sources/a.swift") == ""
    assert _SWIFT_IMPORT.findall("@testable import Core\nimport struct Foundation.URL\n  import UIKit\n") == ["Core", "Foundation", "UIKit"]
    # Формы, которые свидетель не различал (скептик opus по 9dc31762, M4): атрибут в строке объявления, protocol/actor/
    # typealias, блочный комментарий, многострочная и сырая строки. Тройная кавычка собрана из частей: литерал в коде
    # прятал от рода K точку входа модуля, и он становился «библиотекой» (прирост носителей K на 4, 7 ноября 2026).
    _sw2 = ('@objc public func bridge() {}\nprotocol P {}\nactor A {}\ntypealias T = Int\n/* struct C1 {} */\n'
            'let m = ' + '"' * 3 + '\nstruct C2 {}\n' + '"' * 3 + '\nlet r = #"struct C3 "#\n')
    assert set(_SWIFT_DECL.findall(_swift_code(_sw2))) == {"bridge", "P", "A", "T", "m", "r"}
    print("project_map: самопроверка 0; описание —", m["_source"])
