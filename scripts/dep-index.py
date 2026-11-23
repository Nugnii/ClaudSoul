#!/usr/bin/env python3
# dep-index.py — карта зависимостей дерева и того, какие документы что описывают.
#
# Результат: у каждого механизма записано, от чего он зависит и кто его описывает
# Проверка результата: python3 scripts/dep-index.py --check даёт 0
#
# Зачем. Правило «изменил механизм — проверь зависимости и обнови их описания» держалось
# на внимательности и не исполнялось: 28 августа 2026 три утверждения в справочниках и
# мастер-копии правил разошлись с деревом, и нашёл это владелец вопросом, а не страж.
# Полный аудит стоит часы работы агента — значит проверка обязана быть АДРЕСНОЙ: из
# изменённых файлов вывести короткий список документов, на которые надо посмотреть.
#
# Почему индекс, а не обход на лету. Обход дерева стоит секунды, но разбор его вывода
# стоит внимания. Индекс превращает вопрос «кого задело» в пересечение двух списков.
#
# Формат — TSV, по строке на механизм, поля разделены табуляцией:
#   path  sha  deps  docs  tests  names
#     path  — путь от корня репозитория
#     sha   — sha1 содержимого; по нему видно, устарела ли строка
#     deps  — что этот файл подключает или вызывает (через запятую), пути от корня
#     docs  — документы, называющие этот механизм по имени без расширения
#     tests — файлы тестов, называющие его в строке КОДА; комментарий не считается
#     names — публичные имена: функции оболочки, определения верхнего уровня в python
#
# Обратные рёбра (кто зависит от меня) не хранятся: для индекса нынешнего размера (173
# строки на 30 августа 2026; число печатает --check) они считаются на лету,
# а хранение двух направлений — два источника правды об одном факте.
#
# КОНТРПРИМЕР: зависимость, собранная в переменной по частям («$D/$N.sh»), не опознаётся.
# Индекс видит литералы путей и имена файлов; вычисляемые пути — нет, и это известно.

import hashlib
import os
import re
import subprocess
import sys

# Что в проекте код, тест и что не смотреть — у владельца `hooks/lib/project_map.py` (спецификация
# project-map-principle, шаг 1б.1): правило о файле, а не перечень мест, и одно на учёт и карту. Без описания
# проекта действуют умолчания, равные прежним MECH_RE/MECH_SKIP/TEST_RE. `--repo <путь>` — корень чужого проекта;
# прежние вызовы его не передают и получают прежний корень (каталог этого скрипта либо CLAUDSOUL_REPO).
# Библиотека ищется порядком `hooks/paths-lib.sh:33` — рядом со скриптом, CLAUDSOUL_ROOT, указатель
# ~/.claude/claudsoul-repo, установка; без CLAUDSOUL_REPO — здесь это «какое дерево судить» (тесты ставят песочницу).
def _find_lib(name):
    cands = [os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "hooks", "lib")]
    if os.environ.get("CLAUDSOUL_ROOT"):
        cands.append(os.path.join(os.environ["CLAUDSOUL_ROOT"], "hooks", "lib"))
    try:
        with open(os.path.expanduser("~/.claude/claudsoul-repo"), encoding="utf-8") as f:
            cands.append(os.path.join(f.read().strip(), "hooks", "lib"))
    except OSError:
        pass
    cands.append(os.path.expanduser("~/.claude/hooks/lib"))
    return next((c for c in cands if os.path.exists(os.path.join(c, name))), cands[-1])


sys.path.insert(0, _find_lib("project_map.py"))
try:
    import project_map  # noqa: E402
except ImportError:
    project_map = None

# ЗАПАСНОЙ ПУТЬ БЕЗ МОДУЛЯ — прежние правила дословно. Песочницы тестов копируют только этот файл и подменяют HOME,
# на CI нет ни указателя, ни установки: твёрдый импорт ронял бы их все. Громко там, где без модуля честно не
# исполнить: описание проекта лежит на месте либо передан `--repo`. Совпадение путей — нога P6 test_project_map.sh.
_MECH_RE = re.compile(r"\.(sh|py)$")
_TEST_RE = re.compile(r"(^|/)tests?/")
_MECH_SKIP = re.compile(r"(^|/)tests?/|^templates/|^scripts/publish/|__init__\.py$")
_DEFAULT_REPO = os.environ.get("CLAUDSOUL_REPO") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PMAP = None
if project_map is None:
    if any(a == "--repo" or a.startswith("--repo=") for a in sys.argv) \
            or os.path.exists(os.path.join(_DEFAULT_REPO, ".claude-docs", "project-map.json")):
        print("dep-index: модуль hooks/lib/project_map.py не найден — описание проекта и --repo без него не "
              "исполнить; учёт не собран", file=sys.stderr)
        sys.exit(2)
    REPO = _DEFAULT_REPO
else:
    try:
        REPO = project_map.repo_arg(sys.argv) or _DEFAULT_REPO
        PMAP = project_map.load(REPO)
    except project_map.DescriptorError as _e:
        print(f"dep-index: {_e} — учёт не собран", file=sys.stderr)
        sys.exit(2)
INDEX = os.path.join(REPO, ".claude-docs", "dep-index.tsv")


def is_mech(p):
    if PMAP is None:
        return bool(_MECH_RE.search(p)) and not _MECH_SKIP.search(p)
    return project_map.is_code(PMAP, p)


def is_test(p):
    if PMAP is None:
        return bool(_TEST_RE.search(p))
    return project_map.is_test(PMAP, p)


def is_skipped(p):
    if PMAP is None:
        return bool(_MECH_SKIP.search(p))
    return is_test(p) or any(project_map.glob_match(p, g) for g in PMAP["ignore"])
# Документ состояния: хроника называет всякий механизм в день заведения и носителем не считается.
DOC_SKIP = re.compile(
    r"_drafts/|^knowledge/|(^|/)(CHANGELOG|CHANGELOG-archive|SESSION|BACKLOG|BACKLOG-archive)\.md$"
    r"|-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\.md$"
)


def tracked(pattern):
    """Файлы дерева: под учётом git ПЛЮС новые, ещё не добавленные (но не игнорируемые).

    Только `ls-files` мало: новый документ виден индексу лишь после `git add`, и сборка
    до добавления тихо теряет его связи. Поймано 28 августа 2026 на собственном модульном
    доке — пересборка прошла, а `--check` сразу после коммита насчитал 5 расхождений.
    Порядок действий не должен менять результат.
    """
    # `-z`: имена отдаются как есть, разделённые нулём. Без него git ЦИТИРУЕТ путь с
    # не-ASCII восьмеричными экранами (`skills/\320\277…`), такой путь не открывается,
    # `read()` глотает OSError и отдаёт пустоту — документ становится неотличим от пустого,
    # а механизм печатается путём, которого нет на диске. Поймано противником 28 августа
    # 2026 на двух кириллических скиллах из 136 документов корпуса.
    out = _git("ls-files", "-z", "--cached", "--others", "--exclude-standard", pattern).stdout
    # Запись дерева, за которой на диске каталог (ссылка на каталог, подмодуль), — не файл учёта: `read()` назвал бы её
    # «не прочитано», и каждый отчёт `--impact` стал бы НЕПОЛОН (D1185, ссылка `bot -> legacy/bot` в Jurnalist).
    return sorted(set(l for l in out.split("\0") if l and not os.path.isdir(os.path.join(REPO, l))))


def _git(*args):
    """git в судимом дереве — у владельца `project_map.git`: программы из настроек чужого проекта не исполняются (D1089).

    Без модуля — прежний голый вызов: тогда судится только своё дерево (`--repo` и описание без модуля — отказ выше).
    """
    if project_map is None:
        return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True)
    return project_map.git(REPO, *args)


def mechanisms():
    return sorted(p for p in tracked("*") if is_mech(p))


# Снимок — документ, который описывает состояние НА МОМЕНТ НАПИСАНИЯ и обновлению не
# подлежит: разбор, ревизия, конкурентный обзор, архив. Требовать его правки при изменении
# кода значило бы просить подделать запись о прошлом.
#
# Признак — ЯВНАЯ пометка в самом документе, а не догадка по шапке. Догадку пробовали
# 28 августа 2026: «дата в первых строках» записала в снимки `architecture.md`, у которого
# дата ревью стоит рядом с обещанием покрывать текущую реализацию. Шесть ложных из
# двенадцати. Дата в шапке не отличает «описываю прошлое» от «проверено тогда-то».
SNAPSHOT_MARK = "<!-- doc-kind: snapshot -->"
# Архив по конвенции проекта: `<имя>-archive.md`, при выносе по пункту долга —
# `<имя>-archive-d<номер>.md`. Признак ЯКОРНЫЙ (хвост имени), а не вхождение подстроки:
# «-archive» где угодно в имени объявляло снимком живой документ про архивирование, и он
# молча выпадал из корпуса — `doc-impact-check` переставал о нём говорить. Носителей
# конвенции в дереве 3, живых документов, задетых сужением, 0 (замер 6 сентября 2026).
# ПРЕДЕЛ: живой документ, честно названный `*-archive.md`, снимком считаться продолжит —
# имя тут конвенция, а объявление роли одно, маркер выше.
ARCHIVE_RE = re.compile(r"-archive(-[dD][0-9]+)?\.md$")


def is_snapshot(path):
    if ARCHIVE_RE.search(os.path.basename(path)):
        return True
    return SNAPSHOT_MARK in "\n".join(read(path).splitlines()[:8])


def documents():
    return sorted(p for p in tracked("*.md")
                  if not DOC_SKIP.search(p) and not is_snapshot(p))


def tests():
    # С описанием проекта тест — любой файл языка кода под образцами тестов (TS/JS, шаг 1в), а не только .sh/.py;
    # README и реестры в каталоге тестов языка не имеют и тестами не становятся (C9, C10 test_project_map).
    if PMAP is None:
        return sorted(p for p in tracked("*.sh") + tracked("*.py") if is_test(p))
    return sorted(p for p in tracked("*") if is_test(p) and (p.endswith((".sh", ".py")) or project_map.lang_of(PMAP, p)))


# Отказ чтения СЧИТАЕТСЯ и НАЗЫВАЕТСЯ, а не гасится пустотой (род дефекта B,
# scripts/defect-class-carriers.py). Пустая строка — законное содержимое файла и потому
# маркером «не смог» быть не может: строка индекса нечитаемого механизма выходит ровно
# такой же, как у пустого (deps пусты, names пусты, sha = sha1 пустоты), а sha пустоты
# стабилен — значит дрейф не всплывёт и на следующих прогонах. Комментарий на :63 этот
# глушитель называл ещё 28 августа 2026, но чинили тогда одну ПРИЧИНУ OSError (кавычки
# git при не-ASCII пути), а различения не завели: остались права, оборванный симлинк,
# исчезновение файла между `ls-files` и чтением.
# Починка — образец hooks/lib/unread-lib.sh: гасим, НАЗВАВ ЦЕНУ. Цена здесь — перечень
# путей, который печатает каждый вердикт: `--check` не зеленеет, `--impact` объявляет
# отчёт неполным, сборка не кладёт отравленную строку в индекс.
UNREAD = []


def read(path, missing_ok=False):
    """Содержимое файла. `missing_ok` — отсутствие файла законно и отказом не считается.

    Отсутствие и нечитаемость — разные состояния мира (так же разведены в
    scripts/knowledge-instrument-audit.sh). В `impact()` изменённый файл бывает УДАЛЁН тем
    же коммитом, и это не отказ чтения; в `build()` список идёт из `git ls-files`, и там
    пропажа файла — именно отказ.
    """
    try:
        with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        if not missing_ok:
            UNREAD.append(f"{path}: файла нет")
        return ""
    except OSError as e:
        UNREAD.append(f"{path}: {e.strerror or e}")
        return ""


def _unread_note():
    """Приватная обёртка над владельцем — своей логики не несёт.

    «не прочитано: N — …» — пустая строка, если всё прочитано.

    Формулировка итога берётся у владельца (`hooks/lib/unread.py`), а не пишется своей
    копией: копии разошлись молча — у этой было «не прочитано файлов: N — пути», у
    `meta-contamination.py` «не прочитано: N — имена», и читатель получал разные ответы
    на один вопрос (род K, 6 сентября 2026). Список причин остаётся локальным: выносится
    ПРАВИЛО, как назвать итог, а не хранение.
    """
    _u = _Unread()
    _u.items = list(UNREAD)
    return _u.note()


def sha(text):
    return hashlib.sha1(text.encode("utf-8", "replace")).hexdigest()[:12]


def deps_of(path, text, mech_set):
    """Что файл подключает или зовёт. Ищутся ЛИТЕРАЛЫ имён файлов дерева.

    Одноимённые файлы в разных каталогах разводятся ПУТЁМ: если в тексте стоит
    `scripts/foo.sh`, засчитывается только он. Голое имя при неоднозначности не
    засчитывается никому — приписать связь наугад хуже, чем не приписать: отчёт печатает
    её как факт («этот документ про тот механизм»), и проверить его читателю нечем.
    Поймано противником 28 августа 2026; в дереве одноимённых сейчас ноль, запрета нет.
    """
    found = set()
    by_name = {}
    for m in mech_set:
        by_name.setdefault(os.path.basename(m), []).append(m)
    for name in set(re.findall(r"([A-Za-z0-9_-]+\.(?:sh|py))", text)):
        cands = [m for m in by_name.get(name, []) if m != path]
        if not cands:
            continue
        exact = [m for m in cands if m in text]
        if exact:
            found.update(exact)
        elif len(cands) == 1:
            found.update(cands)
    return sorted(found)


def contract_universe():
    """Отслеживаемые файлы-договоры по описанию проекта (шаг 1б.2); без модуля — пусто, прежнее поведение."""
    if PMAP is None:
        return set()
    u = {p for p in tracked("*") if project_map.is_contract(PMAP, REPO, p)}
    # Учёт — договор, который этот прибор сам пишет: при первой сборке файла ещё нет, а карта, собранная после, его
    # уже видит — инкремент разошёлся бы со сборкой (T35). Путь входит во вселенную до первой записи.
    if project_map.is_contract(PMAP, REPO, project_map.INDEX_REL):
        u.add(project_map.INDEX_REL)
    return u


def contract_deps(code, contracts):
    """Договоры, в которые разрешаются литералы строк кода — правило владельца `project_map.contract_refs`."""
    return sorted(project_map.contract_refs(PMAP, code, contracts)) if PMAP is not None and contracts else []


_CODE_UNIVERSE = None


def code_universe():
    """Файлы языков кода дерева, тесты включая, — вселенная разрешения импортов; та же, что у карты (`body_deps`)."""
    global _CODE_UNIVERSE
    if _CODE_UNIVERSE is None:
        _CODE_UNIVERSE = {p for p in tracked("*") if project_map.lang_of(PMAP, p)} if PMAP is not None else set()
    return _CODE_UNIVERSE


def import_deps(path, code):
    """Файлы дерева, в которые разрешаются импорты кода `path` — правило владельца `project_map.import_refs` (шаг 1в).

    Связь объявлена импортом, а не встречей имени: литерал `имя.py` был у 20 из 77 импортов Python ClaudSoul, а TS/JS не
    разбирался вовсе (D1079). Без модуля описания — пусто, прежнее поведение.
    """
    return project_map.import_refs(PMAP, REPO, path, code, code_universe()) if PMAP is not None else set()


def row_deps(path, code, mech_set, contracts):
    return join_list(sorted(set(deps_of(path, code, mech_set)) | set(contract_deps(code, contracts))
                            | (import_deps(path, code) & mech_set)))


def _corpus_invalidated(changed, rows, mech_set):
    """Строки, у которых правка теста или документа сдвигает колонку `tests` либо `docs` (скептик 72d00022, F1).

    Тест и документ — тоже входы учёта: прежний хук отдавал тест в `--changed`, и сборка шла целиком; перечень
    `--stale-by` без этой ветки терял их, а коммит одних тестов учёт не пересобирал вовсе (давний пробел). Здесь —
    точно: для изменённого файла корпуса сравнивается, каких механизмов он касается сейчас и у каких строк записан.
    """
    files = [p for p in changed if p not in mech_set]
    if not files:
        return set()
    # К какому корпусу относится файл, решают те же перечни, что у сборки (скептик b4c40167, А1/А2): README в каталоге
    # тестов — документ, реестр там же — ни тест, ни документ. Голое `is_test` было вторым владельцем этого ответа.
    live = {3: set(documents()), 4: set(tests())}
    seen = {}
    for x in mech_set:
        seen[os.path.basename(x)] = seen.get(os.path.basename(x), 0) + 1
    ambiguous = {n for n, c in seen.items() if c > 1}
    out = set()
    for p in files:
        for col in (3, 4):
            here = p in live[col]
            if not here and not any(p in split_list(r[col]) for r in rows.values()):
                continue
            raw = read(p, missing_ok=True) if here else ""
            corpus = [(p, code_only(raw, p.endswith(".py")) if col == 4 else raw)] if here else []
            imported = import_deps(p, corpus[0][1]) if corpus and col == 4 else set()
            for m in mech_set:
                now = bool(corpus) and (bool(mentions(os.path.basename(m), corpus, m, ambiguous)) or m in imported)
                was = m in rows and p in split_list(rows[m][col])
                if now != was:
                    out.add(m)
    return out


def _twins_changed(rows, mech_set):
    """Сменился СОСТАВ группы одноимённых механизмов (скептик b4c40167, А4; скептик sk3, А1).

    Голое имя засчитывается только у единственного владельца (`deps_of`, `mentions`), и снятие или появление двойника
    сдвигает строки, на которых имени-пути не было. Сравнивается состав групп, а не набор неоднозначных имён: из трёх
    двойников удалён один — имя неоднозначно и до, и после, а у оставшегося голое имя снова разрешается в соседа.
    """
    def groups(paths):
        g = {}
        for p in paths:
            g.setdefault(os.path.basename(p), set()).add(p)
        return g
    before, after = groups(rows), groups(mech_set)
    return any(before.get(n) != after.get(n) for n in before.keys() | after.keys()
               if len(before.get(n, ())) > 1 or len(after.get(n, ())) > 1)


def rule_files():
    """Код самого правила учёта В СУДИМОМ ДЕРЕВЕ — этот прибор и модуль описания (D1080): вход каждой строки.

    Строки строит правило, и его правка сдвигает их все — учёт объявлялся бы свежим, будучи построен прежним правилом.
    Прибор вне судимого дерева (чужой проект, `--repo`) сюда не попадает: смена его редакции там — названный предел.
    """
    root = os.path.realpath(REPO)
    out = set()
    for f in (__file__, getattr(project_map, "__file__", None)):
        if f:
            r = os.path.relpath(os.path.realpath(f), root)
            if r != ".." and not r.startswith(".." + os.sep):
                out.add(r)
    return out


RULE_MARK = "# правило "


def rule_stamp():
    """Отметка редакции правила учёта — хеш кода прибора и модуля описания, ГДЕ БЫ они ни лежали (D1339).

    `rule_files` видит смену правила только внутри судимого дерева (по перечню правленого). Учёт чужого проекта строит
    тот же прибор, лежащий вне его дерева: правило менялось, а строки оставались от прежнего, и по файлу учёта этого было
    не видно — ProjectA_NEW, 21 ноября 2026: у 1 163 строк TS из 1 166 колонка имён от прежнего правила, первый отчёт по
    каждому из 1 078 файлов назвал бы давние экспорты новыми. Отметку пишет `save`, читает `stored_rule`.
    """
    h = hashlib.sha1()
    for f in (__file__, getattr(project_map, "__file__", None)):
        try:
            with open(f, "rb") as fh:
                h.update(fh.read())
        except (OSError, TypeError):
            pass
    return h.hexdigest()[:12]


def stored_rule():
    """Отметка редакции правила в шапке записанного учёта; None — учёта нет либо он записан до отметки."""
    try:
        with open(INDEX, encoding="utf-8") as f:
            for _ in range(4):
                line = f.readline()
                if line.startswith(RULE_MARK):
                    return line[len(RULE_MARK):].strip()
    except OSError:
        pass
    return None


def rule_differs():
    """Записанный учёт собран другой редакцией правила (либо до отметки): его строки с нынешними несравнимы."""
    return os.path.exists(INDEX) and stored_rule() != rule_stamp()


def _shifts_all(changed, rows, mech_set):
    """Правка, чей сдвиг строк дешевле полной сборки не перечислить: код правила, описание проекта, состав одноимённых."""
    if rule_files() & set(changed) or rule_differs():
        return True
    # tsconfig корня (`roots` описания) задаёт псевдонимы импортов: его правка сдвигает строки TS/JS (шаг 1в).
    if PMAP is not None and {r["tsconfig"] for r in PMAP.get("roots", ())} & set(changed):
        return True
    return PMAP is not None and (project_map.DESCRIPTOR in changed or _twins_changed(rows, mech_set))


def _mech_set_invalidated(rows, mech_set):
    """Строки, которые сдвигает смена НАБОРА механизмов (скептик b4c40167, А4): набор — тоже вход каждой строки.

    Удалён механизм — строки, чей `deps` его называет (`install.sh` оставался со ссылкой на удалённый хук). Новый
    механизм перечень называет сам, и сборка с ним идёт целиком; смену состава одноимённых судит `_twins_changed`.
    """
    gone = set(rows) - mech_set
    return {r for r in rows if r in mech_set and gone & set(split_list(rows[r][2]))}


def invalidated_by(changed, rows, contracts=None, mech_set=None):
    """Строки учёта, которые меняет правка `changed` помимо самих механизмов — один владелец ответа (шаг 1б.3).

    Спецификация §3 (урок F2 D1067): учёт объявляет, от чего зависит его ответ. Изменилось описание проекта — все
    строки. Появился или удалён файл-договор — строки его читателей (прежних по колонке `deps` и новых по коду), но
    только те, чьи рёбра действительно сдвинулись: правка СОДЕРЖИМОГО договора рёбер не меняет, и бэклог, правленый
    почти каждым коммитом, пересборки не требует. Зовут `build(paths)`, `impact()` и режим `--stale-by` (хук
    коммита) — своих перечней событий у них нет.
    """
    if mech_set is None:
        mech_set = set(mechanisms())
    if _shifts_all(changed, rows, mech_set):
        return set(mech_set)
    if PMAP is None:
        return set()
    out = _corpus_invalidated(changed, rows, mech_set) | _mech_set_invalidated(rows, mech_set)
    # SWIFT (скептик opus по 9dc31762, H1): ребро A→B зависит от имён верхнего уровня B, то есть от СОДЕРЖИМОГО B, и
    # правка Swift-файла сдвигает чужие строки (deps и tests). Разошлись — те Swift-строки, что не равны собранным заново
    # тем же правилом (`_row`); прежде `--stale-by` называл только сам файл, и коммит уносил устаревший учёт.
    if any(project_map.lang_of(PMAP, p) == "swift" for p in changed):
        ctx = _row_context(mech_set, contracts if contracts is not None else contract_universe())
        out |= {f for f in mech_set if project_map.lang_of(PMAP, f) == "swift" and f not in changed
                and f in rows and rows[f] != _row(f, ctx, mech_set)}
    cs ={p for p in changed if project_map.is_contract(PMAP, REPO, p)}
    if not cs:
        return out
    if contracts is None:
        contracts = contract_universe()
    bases = {p.rsplit("/", 1)[-1] for p in cs}
    cand = {r for r in rows if cs & set(split_list(rows[r][2]))}
    codes = {}
    for f in mech_set:
        t = read(f, missing_ok=True)
        if any(b in t for b in bases):
            codes[f] = code_only(t, f.endswith(".py"))
            if contract_deps(codes[f], cs & contracts):
                cand.add(f)
    for f in cand & mech_set:
        code = codes.get(f)
        if code is None:
            code = code_only(read(f, missing_ok=True), f.endswith(".py"))
        if f not in rows or rows[f][2] != row_deps(f, code, mech_set, contracts):
            out.add(f)
    return out


def stale_rows(changed, rows):
    """Строки учёта, которые правка `changed` сделала НЕВЕРНЫМИ, — ответ `--stale-by` и `--impact` (D1082).

    Не «что можно пересобрать», а «что разошлось»: механизм с иным содержимым (в том числе правленный внутри области
    данных — А3), новый без строки, удалённый при живой строке, плюс сдвинутые `invalidated_by`. Строка, уже
    пересобранная (ловушкой pre-commit, ручным `--changed`), сюда не попадает: иначе хук поручал пересобрать свежий учёт
    (А2). Где сдвиг не перечислить (`_shifts_all`), ответ даёт сама сборка — сравнением с записанным.
    """
    mech_set = set(mechanisms())
    if _shifts_all(changed, rows, mech_set):
        fresh = build()
        return {p for p in set(fresh) | set(rows) if fresh.get(p) != rows.get(p)}
    own = {p for p in changed if is_mech(p) and ((p in mech_set) != (p in rows)
                                                 or (p in rows and rows[p][1] != sha(read(p, missing_ok=True))))}
    return own | invalidated_by(changed, rows, mech_set=mech_set)


_JS_NAMES_EXT = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts")


def public_names(path, text):
    """Публичные имена модуля: то, чем пользуются снаружи."""
    # Три формы объявления функции оболочки, а не одна: `имя() {`, `function имя() {`,
    # `function имя {`. Ведущее подчёркивание — приватное по конвенции, не считается.
    # Повод: противник 28 августа 2026 показал, что `knowledge-counter-bump.sh` объявляет
    # `function hist_entry() {` и это имя в учёт не попадало, а `mcp-server/server.py`
    # объявляет десять инструментов MCP через `async def` — поле имён было пустым,
    # то есть ветка «новая способность внутри модуля» на них не срабатывала НИКОГДА.
    if path.endswith(".sh"):
        return sorted(set(
            re.findall(r"^\s*(?:function\s+)?([a-z][a-z0-9_]*)\s*\(\)\s*\{", text, re.M)
            + re.findall(r"^\s*function\s+([a-z][a-z0-9_]*)\s*\{", text, re.M)))
    # TS и JS — ЭКСПОРТИРОВАННОЕ (D1339): правило питона (`def|class` в начале строки) на них не видело ни одной
    # `export function` и записывало публичным неэкспортированный `class`; у соседнего проекта имена были у 3 файлов
    # из 1166, и ветка «новое публичное имя» на них молчала. Берутся функции, классы и привязки `const|let|var`;
    # типы и интерфейсы способностью не считаются. Предел: перечень `export { a, b }` и реэкспорт не разбираются.
    if path.endswith(_JS_NAMES_EXT):
        return sorted(set(n for n in re.findall(
            r"^export\s+(?:default\s+)?(?:async\s+)?(?:function\*?|(?:abstract\s+)?class|const|let|var)\s+"
            r"([A-Za-z_$][A-Za-z0-9_$]*)", text, re.M) if not n.startswith("_")))
    return sorted(set(re.findall(r"^(?:async\s+def|def|class)\s+([A-Za-z][A-Za-z0-9_]*)", text, re.M)))


def carriers():
    """Файлы, которые ссылаются на механизм, но сами механизмом не являются.

    Расписания launchd, конфигурация, схемы. Переименование хука ломает их молча: launchd
    на пропавший файл в диалог не жалуется. Раньше в «зависимых» могли оказаться только
    механизмы — файл другого расширения не попадал туда НИ ПРИ КАКОМ содержимом, и
    объявленный предел про «путь, собранный по частям» этот случай не покрывал: путь тут
    литеральный. Поймано противником 28 августа 2026: три живых расписания держат
    `auto-scanner.sh`, `bridge-health-digest.sh`, `knowledge-audit-digest.sh`.

    Замер набора: 36 файлов на дерево — просмотр дешевле, чем ошибка о молчании.
    Сам индекс исключён: он называет каждый механизм по построению.
    """
    out = []
    for p in tracked("*"):
        if p.endswith((".md", ".sh", ".py")) or is_skipped(p):
            continue
        # Выходы инструментов — учёт, карта, замок карты — не носители (D1068, F1): прежний кэш карты прятала
        # строка `mcp-server/.gitignore`, а не объявление инструмента; на новом месте защиты не было.
        if p.endswith("dep-index.tsv") or (PMAP is not None and project_map.is_output(PMAP, REPO, p)):
            continue
        out.append(p)
    return sorted(out)


_WORD = re.compile(r"[A-Za-z0-9_-]+")
_WORD_ONLY = re.compile(r"[A-Za-z0-9_-]+")
_WORD_INDEX = {}


def _word_index(corpus):
    """Слово → номера файлов корпуса, по одному разу на корпус; корпус держится в ключе, чтобы `id` не переиспользовался."""
    hit = _WORD_INDEX.get(id(corpus))
    if hit is None or hit[0] is not corpus:
        idx = {}
        for i, (_, t) in enumerate(corpus):
            for w in set(_WORD.findall(t)):
                idx.setdefault(w, []).append(i)
        hit = _WORD_INDEX[id(corpus)] = (corpus, idx)
    return hit[1]


# Правая граница имени файла: дальше не буква, не цифра, не `_`, не `-` и не точка с продолжением (`x.sh.bak`, `x.tsv`).
_NAME_END = r"(?![A-Za-z0-9_-])(?!\.[A-Za-z0-9])"


def carrier_names(needle, text):
    """Носитель НАЗЫВАЕТ файл `needle` (имя либо путь от корня) — целым именем, а не подстрокой (D1339, корень R3).

    Прежде стояло `needle in text`: `outcome.sh` входит в `injection-outcome.sh`, `check.sh` — в `doc-check.sh`, и
    конфигурация, державшая только второй, называлась зависимой от первого (на дереве 3 ложных носителя, у соседнего
    проекта 37). Граница та же, что у `mentions` и `deps_of`: слева не часть имени, справа конец имени.
    """
    return re.search(r"(?<![A-Za-z0-9_.-])" + re.escape(needle) + _NAME_END, text) is not None


def mentions(name, corpus, path=None, ambiguous=()):
    """Файлы, называющие механизм.

    Две формы засчитываются по-разному, и различает их ФОРМА ИМЕНИ, а не список.

    Составное имя (есть дефис или подчёркивание) — `five-whys-gate`, `session-collector` —
    обычным словом быть не может, поэтому засчитывается и голое упоминание: справочник
    называет механизмы именно так, без расширения.

    Односложное имя — `phase`, `inject`, `cli`, `parse` — совпадает с обычным словом, и
    голое упоминание ничего не значит. Замер 28 августа 2026: `inject` поймал «silent
    inject» в PLAN.md, `phase` — поле JSON «"phase": "capture"», `cli` — псевдоним домена.
    Для таких требуется расширение (`inject.py`) либо путь (`core/inject`).

    КОНТРПРИМЕР: составное имя, ставшее обычным выражением («drift-check» в фразе про
    дрейф вообще), пройдёт как упоминание — форма имени тут уже не спасает, и это известно.
    """
    stem, _, ext = name.rpartition(".")
    stem = stem or name
    # Имя неоднозначно (такой basename есть у нескольких механизмов) — засчитывается
    # только упоминание ПУТЁМ, иначе оба получат оба документа. Поиск литерала — вхождение подстроки (D1089: то же,
    # что `re.escape(path)`, без компиляции на каждое имя).
    if path is not None and name in ambiguous:
        return sorted(p for p, t in corpus if path in t)
    # ПРЕДФИЛЬТР ПО СЛОВАМ КОРПУСА (D1089, решение владельца «ускорить сейчас»). Каждое имя искалось выражением в каждом
    # файле корпуса: на ProjectA_NEW 1311 механизмов × 2490 тестов — 3,5 млн поисков, 315 с из 320 полной сборки. Во всех
    # трёх формах ниже основа имени стоит ЦЕЛЫМ словом `[A-Za-z0-9_-]+` (слева граница, `/` или обратная кавычка; справа
    # граница, `.` или обратная кавычка), поэтому выражение зовётся только у файлов, где такое слово есть, — ответ тот
    # же. Основа с иными символами (`x.d` у `x.d.ts`) идёт прежним полным перебором.
    if _WORD_ONLY.fullmatch(stem):
        corpus = [corpus[i] for i in _word_index(corpus).get(stem, ())]
    bare = r"(?<![A-Za-z0-9_-])" + re.escape(stem)
    if "-" in stem or "_" in stem:
        rx = re.compile(bare + r"(?![A-Za-z0-9_-])")
    else:
        # Третья форма — имя в обратных кавычках: документ так помечает, что это ИМЯ, а не
        # слово. На боевом дереве она не добавляет ни одной связи (482 против 482), то есть
        # ложных срабатываний не несёт, но даёт документу законный способ назвать
        # односложный механизм без расширения.
        # Вторая форма опознаётся РОЛЬЮ соседа слева: перед слэшем обязан стоять
        # компонент пути (ASCII-имя каталога). Иначе слэш в прозе — «режим чтение/parse» —
        # засчитывался за путь, и тест одного модуля становился тестом другого. Замер
        # 6 сентября 2026: на живом дереве связей этой формы 3, ложных среди них 0, —
        # сужение ничего не отнимает и закрывает класс.
        # За основой в форме пути не идёт ЧУЖОЕ расширение (D1339): `archive/outcome.tsv`, `lint/cli.js`,
        # `$T/scan.py` — пути к ДРУГИМ файлам, а засчитывались упоминанием `outcome.sh`, `cli.py`, `scan.sh` (на
        # дереве 15 лишних связей на 60 парах). Своё расширение берёт первая форма; точка в конце фразы не мешает.
        rx = re.compile(r"(?:" + bare + re.escape("." + ext)
                        + r"|(?<![A-Za-z0-9_-])[A-Za-z0-9_.-]+/" + re.escape(stem)
                        + _NAME_END + r"|`" + re.escape(stem) + r"`)")
    return sorted(p for p, t in corpus if rx.search(t))


def code_only(text, is_py=False):
    """Текст без строк-комментариев — корпус тестов для `mentions()`.

    Зачем. Роль строки в вердикт о связи не входила, и имя механизма в КОММЕНТАРИИ теста
    делало этот тест его тестом. Замер 3 сентября 2026 на боевом дереве: связей
    «механизм → тест» 838, из них 227 держались исключительно на строке-комментарии
    (regex прибора; одна-строка пункта D279, сверяющая подстрокой, даёт 211), затронут
    101 механизм из 189, носителей 124 теста из 351, а у четырёх механизмов (`session-end`,
    `frontmatter`, `ab-authorization-replay`, `knowledge-independence`) тестовыми были
    ТОЛЬКО комментарные связи — то есть теста у них нет, а индекс показывал, что есть.
    Тот же корень, что D272, в другом механизме и с бо́льшим симптомом.

    Корпусов у прибора четыре, и с 6 сентября 2026 (D284) роль строки различают ТРИ:
    тесты, `deps_of` и носители. Чего НЕ касается — документов: в markdown `#` это
    заголовок, а не комментарий, и снятие таких строк стоило бы 1 связи из 648 (замер
    3 сентября 2026). Отсев режется ровно там, где `#` означает комментарий.

    Четыре имени выше намеренно БЕЗ расширения: `deps_of` ищет литералы `имя.sh|py` по
    полному тексту механизма, и первая редакция этого докстринга добавила самому индексу
    4 ложных ребра в колонке deps (7 → 11) — прибор описал бы себя зависящим от того, что
    он всего лишь упоминает.

    КОНТРПРИМЕР: хвостовой комментарий (`bash hooks/alpha.sh   # запуск`) остаётся кодом —
    снимается только строка, чей ПЕРВЫЙ непробельный символ `#`. Иначе теряются живые
    связи вида `printf '#!/usr/bin/env bash…' > …`.

    ДОКСТРИНГ .py — ПРОЗА, А НЕ КОД (13 сентября 2026). До этого дня здесь стояло
    «docstring в .py-тесте остаются кодом… docstring-связей на дереве 7, и это известно»:
    цена была названа числом, а сверщика у числа не было, и оно уплыло. Замер: из 66 рёбер
    «зависит от» у .py-файлов **45 (68%) держались ТОЛЬКО на прозе докстринга**. Устройство
    у всех одно и оно же самое опасное: библиотека перечисляет в шапке своих ПОТРЕБИТЕЛЕЙ
    (`state_lock.py` — шестерых, `unread.py` — троих), получает ребро НАЗАД к каждому, и
    связь замыкается в кольцо, которого в исполнении нет. Тройные кавычки снимаются только
    у `.py`: в оболочке они ничего не значат, и трогать её текст незачем.
    НАЗВАННЫЙ ПРЕДЕЛ: строка кода на ОДНОЙ строке с закрывающей кавычкой теряется вместе с
    докстрингом; в дереве таких нет (проверено прогоном индекса до и после).
    Условие снятия: в дереве появится такая строка — прогон индекса до и после разойдётся.
    """
    # Проза питона — у разборщика (`project_map.py_prose_rows`, D1286), прежний счёт кавычек — только когда разбор не удался.
    prose = getattr(project_map, "py_prose_rows", lambda t: None)(text) if is_py else None
    out, in_doc = [], None
    for n, line in enumerate(text.split("\n"), 1):
        stripped = line.lstrip()
        if prose is not None:
            if n not in prose and not stripped.startswith("#"):
                out.append(line)
            continue
        if in_doc is not None:
            if in_doc in stripped:
                in_doc = None
            continue
        if stripped.startswith("#"):
            continue
        if is_py:
            m = re.match(r'^[A-Za-z]*("""|\'\'\')', stripped)
            if m:
                quote = m.group(1)
                if quote not in stripped[m.end():]:
                    in_doc = quote
                continue
        out.append(line)
    return "\n".join(out)


def _row_context(mech_set, contracts):
    """Входы строки, общие для всех механизмов: договоры, двойные имена, корпусы документов и тестов, импорты тестов."""
    seen = {}
    for x in mech_set:
        seen[os.path.basename(x)] = seen.get(os.path.basename(x), 0) + 1
    ambiguous = {n for n, c in seen.items() if c > 1}
    docs_corpus = [(p, read(p)) for p in documents()]
    tests_corpus = [(p, code_only(read(p), p.endswith(".py"))) for p in tests()]
    # Тест, импортирующий файл или подменяющий его (`vi.mock`), — его тест (решение владельца 25 октября 2026, шаг 1в).
    test_imports = {p: import_deps(p, c) for p, c in tests_corpus}
    return contracts, ambiguous, docs_corpus, tests_corpus, test_imports


def _row(path, ctx, mech_set):
    """Строка учёта одного механизма — одно правило для сборки и для ответа «что разошлось» (`invalidated_by`, Swift)."""
    contracts, ambiguous, docs_corpus, tests_corpus, test_imports = ctx
    text = read(path)
    name = os.path.basename(path)
    return [
        path,
        sha(text),
        # Корпус — строки КОДА: имя соседа в комментарии зависимостью не является.
        # Замер 6 сентября 2026: рёбер «зависит от» 666, из них 274 держались только
        # на комментарии. `sha` и публичные имена по-прежнему от полного текста —
        # дрейф считается по файлу целиком, а определение функции в комментарии
        # регекспом имён и так не ловится.
        # Плюс файлы-договоры, в которые РАЗРЕШАЕТСЯ литерал кода (шаг 1б.2, `project_map.contract_refs`).
        row_deps(path, code_only(text, path.endswith(".py")), mech_set, contracts),
        join_list(mentions(name, docs_corpus, path, ambiguous)),
        join_list(sorted(set(mentions(name, tests_corpus, path, ambiguous))
                         | {t for t, refs in test_imports.items() if path in refs})),
        join_list(public_names(path, text)),
    ]


def build(paths=None):
    mech = mechanisms()
    mech_set = set(mech)
    contracts = contract_universe()
    ctx = _row_context(mech_set, contracts)
    rows = {}
    if paths is not None:
        rows = load()
        # Индекса нет — «пересборка изменённых» записала бы учёт из одной строки поверх
        # всего. Пустой вход тоже: список из ничего не бывает «обновлённым индексом».
        if not rows:
            paths = None
    if paths is not None:
        # Новый механизм меняет ЧУЖИЕ рёбра: `deps_of` ищет литералы имён файлов, и строка
        # соседа, который его зовёт, становится неверной. Раньше полная пересборка была
        # предусмотрена только для изменившегося документа, а для нового механизма — нет,
        # и команда, которую диктует сам хук («--changed <файлы>»), оставляла индекс
        # несогласованным: следующий `--check` краснел уже в другом ходе, без контекста
        # правки. Поймано противником 28 августа 2026.
        # Полная пересборка нужна всякий раз, когда правка меняет ЧУЖИЕ строки: новый
        # механизм (его начнут звать соседи), документ и ТЕСТ (оба входят в корпус
        # упоминаний). Тест не попадал под условие, потому что механизмом не считается, —
        # и предписанная самим хуком команда оставляла учёт несогласованным. Поймано
        # противником 28 августа 2026, вторым раундом, после того как первый закрыл ровно
        # тот же класс для документов и новых механизмов.
        touches_corpus = any(p.endswith(".md") for p in paths) \
            or any(is_test(p) for p in paths)
        if any(p not in rows for p in paths if p in mech_set) or touches_corpus:
            paths = None
    if paths is not None:
        # Строки, которые сдвигает появление/удаление договора или правка описания, — у владельца ответа (шаг 1б.3).
        wanted = sorted({p for p in paths if p in mech_set} | invalidated_by(paths, rows, contracts, mech_set))
    else:
        wanted = mech
    for path in wanted:
        rows[path] = _row(path, ctx, mech_set)
    for gone in [p for p in list(rows) if p not in mech_set]:
        del rows[gone]
    return rows


class IndexConflict(Exception):
    """Учёт не разрешён после слияния. Читать его нельзя: строки обеих сторон складываются
    в один словарь, побеждает нижняя, и потерянные связи выглядят как отсутствующие.
    Условие включения хука было «файл на месте» — файл на месте и в конфликте.
    Поймано противником 28 августа 2026: индекс под учётом git, merge-драйвера нет,
    пересобирается почти каждым коммитом, то есть конфликт в нём — обычное дело."""


# Разделители полей и списков — часть формата, поэтому в значениях они кодируются, а не
# запрещаются. Раньше запятая в имени документа резала поле надвое (отчёт требовал
# обновить два несуществующих файла), а табуляция в имени механизма давала строку из семи
# полей, которую `load()` выбрасывал: `--check` краснел сразу после успешной сборки, и
# предписанное им же лекарство не помогало. Поймано противником 28 августа 2026.
ESCAPES = ((chr(92), r"\\"), ("\t", r"\t"), (",", r"\c"), ("\n", r"\n"))


def enc(v):
    for raw, esc in ESCAPES:
        v = v.replace(raw, esc)
    return v


def dec(v):
    out, i = [], 0
    while i < len(v):
        if v[i] == chr(92) and i + 1 < len(v):
            nxt = v[i + 1]
            repl = {"t": "\t", "c": ",", "n": "\n", chr(92): chr(92)}.get(nxt)
            if repl is not None:
                out.append(repl); i += 2; continue
        out.append(v[i]); i += 1
    return "".join(out)


def join_list(items):
    return ",".join(enc(x) for x in items)


def split_list(field):
    return [dec(x) for x in field.split(",") if x]


def load():
    rows = {}
    if not os.path.exists(INDEX):
        return rows
    with open(INDEX, encoding="utf-8") as f:
        for line in f:
            if line.startswith(("<<<<<<< ", "=======", ">>>>>>> ")):
                raise IndexConflict(INDEX)
            line = line.rstrip("\n")
            # Комментарий — только «# » с пробелом: обе строки шапки такие. Путь
            # механизма может начинаться с `#` (в корне дерева), и его строка была
            # неотличима от комментария: чтение её молча теряло, сборка писала —
            # `--check` краснел сразу после успешной сборки и не зеленел никогда.
            # ПРЕДЕЛ: механизм с именем «# что-то.sh» (пробел после решётки) так и
            # останется невидимым; в дереве таких ноль.
            if not line or line.startswith("# "):
                continue
            parts = line.split("\t")
            if len(parts) == 6:
                rows[dec(parts[0])] = [dec(parts[0])] + parts[1:]
    return rows


def load_or_report():
    """Учёт либо читается, либо о его состоянии говорится вслух. Молча вернуть пустой
    словарь нельзя: пустой учёт неотличим от «связей нет», и страж замолчит именно там,
    где обязан кричать."""
    try:
        return load(), None
    except IndexConflict:
        return {}, ("учёт зависимостей не разрешён после слияния — сначала разреши конфликт "
                    "в .claude-docs/dep-index.tsv и пересобери: python3 scripts/dep-index.py --all")


# ОБЩИЙ ЗАМОК НА ИНДЕКС (род H). `load()` читает индекс, вызывающий его правит, `save()`
# кладёт обратно — это read-modify-write, а писателей больше одного: индекс пересобирают из
# любой сессии, и предписание сделать это выдаёт хук `doc-impact-check` на каждом коммите,
# трогающем механизм. Две сессии в одном дереве — не гипотеза: 6 сентября 2026 в реестре
# числились pid 15571 и 59216 с cwd = этот репозиторий. Без замка та из них, что прочла
# индекс раньше, затирает строки, дописанные другой, и учёт молча теряет файлы.
_SL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "hooks", "lib")
try:
    from unread import Unread as _Unread  # владелец формулировки «не прочитано»
except ImportError:  # библиотеки нет — своя формулировка как запасной путь, но громко
    class _Unread:  # noqa: D101
        def __init__(self): self.items = []
        def note(self):
            if not self.items:
                return ""
            n = sorted(set(self.items))
            t = f" … и ещё {len(n) - 5}" if len(n) > 5 else ""
            return f"не прочитано: {len(n)} — " + ", ".join(n[:5]) + t
if _SL not in sys.path:
    sys.path.insert(0, _SL)
try:
    from state_lock import with_lock  # type: ignore
except ImportError:  # библиотека рядом всегда есть; молчать о её отсутствии нельзя
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):  # type: ignore
        print("dep-index: нет hooks/lib/state_lock.py — индекс пишется БЕЗ замка",
              file=sys.stderr)
        yield False


def save(rows):
    if PMAP is not None:
        try:
            project_map.safe_output(REPO, INDEX)      # каталог записи внутри проекта, файл не ссылка (D1070)
        except project_map.DescriptorError as e:
            print(f"dep-index: {e} — учёт не записан", file=sys.stderr)
            sys.exit(2)
    os.makedirs(os.path.dirname(INDEX), exist_ok=True)
    # Запись через временный файл рядом: прерывание на середине оставило бы половину
    # таблицы, и следующий читатель принял бы её за полный учёт.
    tmp = INDEX + ".tmp.%d" % os.getpid()
    # Временный файл — только новый и не по ссылке (D1071, F4): прежний `open(tmp, "w")` шёл по подложенной ссылке.
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
    except OSError as e:
        print(f"dep-index: временный файл учёта {tmp} не создан ({e.strerror}) — учёт не записан", file=sys.stderr)
        sys.exit(2)
    with with_lock(INDEX), os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("# path\tsha\tdeps\tdocs\ttests\tnames\n")
        f.write("# Генерируется scripts/dep-index.py — не править руками.\n")
        f.write(RULE_MARK + rule_stamp() + "\n")
        for path in sorted(rows):
            row = rows[path]
            f.write("\t".join([enc(row[0])] + list(row[1:])) + "\n")
    os.replace(tmp, INDEX)


DATA_START = "dep-index: data-region-start"
DATA_END = "dep-index: data-region-end"
# Строка-маркер: только комментарий и сам маркер. Хвост после тире разрешён — там пишут,
# почему область объявлена. Прозаическое упоминание маркера внутри фразы под это не подходит.
MARK_START_RE = re.compile(r"^\s*(?:#|//|--)\s*" + re.escape(DATA_START) + r"\b")
MARK_END_RE = re.compile(r"^\s*(?:#|//|--)\s*" + re.escape(DATA_END) + r"\b")


def changed_lines_are_data(path):
    """Все ли изменённые строки лежат внутри объявленной области данных.

    Область объявляет сам файл — парой маркеров. Признак взят из объявления, а не из
    догадки по содержимому: догадка «много документов = узловой файл» уже провалилась
    28 августа 2026, заглушив справочник на правке `blocker-tier-check`.

    КОНТРПРИМЕР: файл без разметки считается изменённым по поведению, даже если правка
    чисто данных. Умолчание намеренно в сторону лишней строки в отчёте, а не тишины.
    """
    # Границы берутся из ТОГО ЖЕ снимка, что и номера строк, — из индекса git.
    # Раньше маркеры читались из рабочего дерева, а номера — из `--cached`: достаточно было
    # дописать в дерево незастейдженные строки, чтобы границы уехали и правка поведения
    # объявилась данными. Поймано противником 28 августа 2026 (порядок «фикс → add →
    # дописал регистрацию → коммит» штатный).
    # Содержимое берётся из РАБОЧЕГО ДЕРЕВА, потому что и набор изменённых файлов хук
    # берёт из объединения индекса и дерева (иначе `git commit -am` молчит целиком).
    # Читать здесь только индекс значило бы судить о правке по половине её.
    # `missing_ok`: файл, удалённый этим же коммитом, разметки не имеет — это не отказ.
    text = read(path, missing_ok=True)
    if not MARK_START_RE.search(text) and not any(
            MARK_START_RE.match(l) for l in text.splitlines()):
        return False
    regions, start = [], None
    for i, line in enumerate(text.splitlines(), 1):
        # Маркер опознаётся ЯКОРНОЙ формой, а не вхождением подстроки: строка целиком
        # отдана комментарию-маркеру. Иначе текст, ОБЪЯСНЯЮЩИЙ разметку, сам становится
        # разметкой — и это случилось прямо здесь: комментарий про пару маркеров открывал
        # область, которая висела незакрытой до конца файла, то есть страж молчал бы на
        # правках собственного инструмента. Поймано противником 28 августа 2026, третьим
        # раундом. Тот же класс, что «упоминание ≠ исполнение» в предикатах команды.
        opens = bool(MARK_START_RE.match(line))
        closes = bool(MARK_END_RE.match(line))
        if opens and not closes:
            start = i
        elif closes and not opens and start is not None:
            regions.append((start, i)); start = None
    if not regions:
        return False
    # `diff HEAD` вместо `--cached`: покрывает и застейдженное, и то, что уйдёт в коммит
    # через `-a`. Поймано противником 28 августа 2026: правка данных в индексе плюс правка
    # поведения в дереве давала вердикт «поведение не менялось».
    # Внешний diff и textconv из настроек судимого дерева — исполняемые программы, настройкой не гасятся (D1089, D517).
    diff = _git("diff", "--no-ext-diff", "--no-textconv", "HEAD", "-U0", "--", path).stdout
    touched = []
    for h in re.findall(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", diff, re.M):
        count = int(h[1]) if h[1] else 1
        # Новая сторона пуста — это ЧИСТОЕ УДАЛЕНИЕ, и номер в заголовке указывает на
        # соседнюю уцелевшую строку. Раньше из `+633,0` получался диапазон range(633,634),
        # то есть закрывающий маркер области, и удаление 27 строк поведения сразу за
        # областью объявлялось данными. Удалённое лежит на СТАРОЙ стороне, которой здесь
        # нет; разбирать её — отдельная работа, а до тех пор чистое удаление считается
        # изменением поведения. Умолчание в сторону лишней строки в отчёте, не тишины.
        if count == 0:
            return False
        touched.extend(range(int(h[0]), int(h[0]) + count))
    if not touched:
        return False
    return all(any(a <= n <= b for a, b in regions) for n in touched)


def normalize(paths):
    """Пути приводятся к виду, в котором живёт индекс: относительно корня репозитория.

    Абсолютный путь и `./hooks/...` не узнавались вовсе: `--impact` объявлял описанный
    механизм «новым, без строки в учёте», а `--changed` рапортовал успех, не пересчитав
    ни строки, — и `--check` сразу за ним краснел. Это ровно та команда, которую хук
    печатает в каждом сообщении, а среда требует абсолютных путей. Поймано противником
    28 августа 2026.
    """
    # Любой путь — одним правилом с картой (`rel_path`, D1073): относительный от корня, `..` по файловой системе, имена с
    # диска. Прежде карта брала относительный путь от каталога вызова, и из подкаталога одно имя давало два ключа.
    # Имя, которым учёт уже ключует (строка учёта, файл git), идёт как есть — второй круг D1073: имя git файла,
    # удалённого коммитом или лежащего на диске в NFD, по диску переводилось в чужое.
    out = []
    known = set()
    if project_map is not None and paths:
        try:
            known = set(load())
        except IndexConflict:
            pass
        known.update(tracked("*"))
    for p in paths:
        if project_map is not None:
            q = project_map.rel_path(REPO, p, known)
        else:
            q = os.path.normpath(p)
            if os.path.isabs(q):
                try:
                    q = os.path.relpath(q, REPO)
                except ValueError:
                    pass
        out.append(q)
    return out


def input_exists(path):
    """Вход `--changed` существует: файл на диске либо запись о нём в HEAD.

    Вторая ветка — файл, удалённый ЭТИМ коммитом: на диске его уже нет, а корпус он
    меняет, и пересобрать надо. Без неё отказ бил бы по законному ходу. Строка в учёте
    проверяется на месте вызова: у удалённого РАНЬШЕ механизма нет ни диска, ни HEAD.
    """
    if os.path.exists(os.path.join(REPO, path)):
        return True
    return _git("cat-file", "-e", f"HEAD:{path}").returncode == 0


def impact(changed):
    """Кого задело изменение: адресный список, а не «проверь всё».

    Глубина 0 (документы, описывающие сам изменённый файл) — рабочий сигнал: замер
    28 августа 2026 по 151 механизму дал медиану 2 документа на изменение. Глубина 1
    (документы всего, что зависит) даёт медиану 21 — это тот же полный аудит, только
    автоматический, и читать его никто не станет. Поэтому зависимые называются ИМЕНАМИ
    (медиана 1 на механизм), а их документы не подтягиваются: судить, задело ли их
    поведение, — работа для головы, и список имён для этого достаточен.
    """
    rows, conflict = load_or_report()
    if conflict:
        # Учёт не читается — но молчать нельзя: связи считаются из ДЕРЕВА, а о конфликте
        # говорится отдельной строкой. Отказ работать был бы тем же молчанием, только
        # с объяснением: страж обязан говорить именно тогда, когда учёт ненадёжен.
        rows = build()
    rev = {}
    for path, r in rows.items():
        for d in split_list(r[2]):
            rev.setdefault(d, set()).add(path)
    staged = set(changed)
    mech = [c for c in changed if c in rows]
    new_mech = [c for c in changed
                if is_mech(c) and c not in rows]
    # Шум даёт не файл, а ХАРАКТЕР правки. `install.sh` упоминается в 15 документах, но
    # добавление строки регистрации не меняет ни одного их утверждения; правка поведения
    # того же файла — меняет. Порог «много документов = узловой» пробовали 28 августа
    # 2026 и он провалил собственную приёмку: `blocker-tier-check` с девятью документами
    # стал узловым, и справочник замолчал — тот самый случай, ради которого страж делался.
    # Число документов не различает данные и поведение.
    #
    # Различие берётся из ОБЪЯВЛЕНИЯ файла: область данных размечается парой
    # `dep-index: data-region-start` / `data-region-end`. Правка целиком внутри такой
    # области — данные. Не размечено — считается поведением (умолчание в сторону шума,
    # а не тишины: пропустить изменившееся описание дороже, чем прочесть лишнюю строку).
    data_only = [m for m in mech if changed_lines_are_data(m)]
    mech = [m for m in mech if m not in data_only]
    docs, dependents, renamed = {}, set(), {}
    foreign_rule = rule_differs()
    # То же и у носителей: в расписании, конфигурации и .tsv `#` — комментарий, и
    # историческая справка про механизм зависимостью не является. Замер 6 сентября 2026:
    # связей носителей 98, из них 4 держались только на комментарии.
    carrier_corpus = [(c, code_only(read(c), c.endswith(".py"))) for c in carriers()]
    _seen = {}
    for _x in rows:
        _seen[os.path.basename(_x)] = _seen.get(os.path.basename(_x), 0) + 1
    ambiguous = {n for n, c in _seen.items() if c > 1}
    # Связи ИЗМЕНЁННЫХ механизмов считаются заново, а не берутся из строки: строка могла
    # устареть — документ завели вчерашним коммитом, индекс не пересобрали, и отчёт по
    # старой строке подавался как текущий. Предупреждения об устаревании мало: оно
    # говорит «может быть неполно», а нужно назвать документ. Пересчёт стоит один проход
    # по корпусу документов, доли секунды. Поймано противником 28 августа 2026.
    docs_corpus = [(d, read(d)) for d in documents()]
    for m in mech:
        # Объединение двух источников, а не замена одного другим. Строка учёта помнит
        # связи, посчитанные при сборке; пересчёт находит документ, заведённый после неё.
        # Пересчёт ВМЕСТО строки был ошибкой: он требует, чтобы документы лежали на диске,
        # и терял всё, что знал индекс. Поймано собственным прогоном набора 28 августа 2026
        # сразу после правки — оба источника нужны, и ни один не покрывает другой.
        stored = split_list(rows[m][3])
        for d in sorted(set(stored) | set(mentions(os.path.basename(m), docs_corpus, m, ambiguous))):
            if d and d not in staged:
                docs.setdefault(d, []).append(m)
        dependents |= {x for x in rev.get(m, set()) if x not in staged}
        base = os.path.basename(m)
        needle = m if base in ambiguous else base
        for c in carrier_corpus:
            if c[0] not in staged and carrier_names(needle, c[1]):
                dependents.add(c[0])
        # Новое публичное имя — новая способность внутри существующего модуля. Учёт
        # требует записи и на неё, а не только на новый файл: 28 августа 2026 четыре
        # предиката появились внутри библиотеки и не потребовали ни строки документации.
        # Учёт другой редакции правила имён не судит (D1339): «прежние» имена строило иное правило, и разница с нынешними
        # — смена правила, а не новая способность. Отчёт называет это своей строкой (`foreign_rule`).
        before = set(split_list(rows[m][5]))
        after = set(public_names(m, read(m, missing_ok=True)))
        if after - before and not foreign_rule:
            renamed[m] = sorted(after - before)
    # Устаревшая строка: содержимое механизма уже другое, а связи в индексе — прежние.
    # Поле `sha` для этого и заведено, но его не читал ни один потребитель, и отчёт по
    # старой строке подавался как текущий. Отдельно: правка ДОКУМЕНТА меняет чужие связи,
    # и об этом надо сказать, даже когда механизмов в коммите нет вовсе — иначе учёт
    # тихо расходится с деревом. Оба случая найдены противником 28 августа 2026.
    # Правка описания проекта — свой смысл, а не «устарели все строки»: пересборка нужна вся, но разошедшимися строки
    # от этого не становятся (два смысла по одному проводу — R6). Отчёт называет её отдельной строкой.
    # Устаревшие строки — у того же владельца, что и перечень `--stale-by` (D1082): прежде механизм с правкой области
    # данных выпадал из `mech` выше, и его строка с новым sha не называлась (А3).
    # Правка кода правила (D1080) — тоже свой смысл: строки строятся по нему заново, и отчёт называет это строкой, а не
    # полной сборкой внутри отчёта; собственные строки файлов правила судятся как у любого механизма.
    descriptor = PMAP is not None and project_map.DESCRIPTOR in changed
    rules = sorted(rule_files() & set(changed))
    own_rules = {r for r in rules if r in rows and rows[r][1] != sha(read(r, missing_ok=True))}
    stale = [] if conflict else sorted(
        (stale_rows([c for c in changed if (not descriptor or c != project_map.DESCRIPTOR) and c not in rules], rows)
         | own_rules) - set(new_mech))
    docs_changed = sorted(p for p in changed if p.endswith(".md") and not DOC_SKIP.search(p))
    return {"docs": docs, "dependents": sorted(dependents),
            "new_mech": sorted(new_mech), "new_names": renamed,
            "data_only": sorted(data_only), "stale": stale, "docs_changed": docs_changed, "descriptor": descriptor,
            "rules": rules, "foreign_rule": foreign_rule,
            "conflict": conflict, "unread": _unread_note()}


# Перечень режимов объявлен, и вход сверяется с ним ДО любой работы. Раньше разбор был
# тремя независимыми вопросами «есть ли тут такой флаг», а всё несовпавшее падало в
# остаток `rows = build(); save(rows)` — то есть просьба показать справку ПЕРЕПИСЫВАЛА
# учёт (поймано дважды 6 сентября 2026: `--help` напечатал «индекс собран»; исполнитель
# соседнего пункта побочно перестроил 101 строку чужого индекса). Умолчание прибора —
# самое разрушительное его действие, поэтому оно обязано быть НАЗВАННОЙ веткой, а не
# остатком: неизвестный вход отбивается кодом 2 и мира не меняет.
MODES = ("--all", "--check", "--impact", "--changed", "--stale-by")


def main():
    """Обёртка вокруг разбора: конфликт слияния в учёте — ВЕРДИКТ, а не трейсбек.

    Класс `IndexConflict` был заведён и ловился только в `--impact`; `--check` и
    `--changed` читают учёт напрямую и падали стеком. Стек читателю ничего не говорит о
    том, что делать, — а делать надо одно: разрешить конфликт и пересобрать.
    """
    try:
        return _run(sys.argv[1:])
    except IndexConflict as e:
        print(f"учёт зависимостей не разрешён после слияния — конфликт в {e.args[0]}; "
              f"разреши его и пересобери: python3 scripts/dep-index.py --all",
              file=sys.stderr)
        return 2
    except Exception as e:
        # Отказ владельца git (`project_map.git`, D1089) — вердикт с причиной, а не трейсбек.
        if project_map is not None and isinstance(e, project_map.DescriptorError):
            print(f"dep-index: {e} — учёт не собран", file=sys.stderr)
            return 2
        raise


def _run(args):
    mode, rest = (args[0], args[1:]) if args else ("--all", [])
    # Путь файла с дефиса не начинается ни разу в дереве, поэтому такой аргумент среди
    # путей — опечатка в флаге, а не имя. Умолчание в сторону отказа, а не записи.
    unknown = [a for a in rest if a.startswith("-")]
    if mode not in MODES or unknown or (mode in ("--all", "--check") and rest):
        print(f"неизвестный аргумент: {' '.join(unknown) or mode}; "
              f"режимы: {', '.join(MODES)} (--impact, --changed и --stale-by берут пути файлов). "
              f"Индекс не тронут.", file=sys.stderr)
        return 2
    if mode == "--stale-by":
        # Какие строки учёта правка этих путей сделала неверными (`stale_rows`): пусто — учёт свеж. Хук коммита решает
        # пересборку по этому ответу, а не по фразам отчёта и не своим фильтром расширений (D1082).
        paths = normalize([a for a in rest if a])
        rows, conflict = load_or_report()
        if conflict:
            print(conflict, file=sys.stderr)
            return 2
        for p in sorted(stale_rows(paths, rows)):
            print(p)
        note = _unread_note()
        if note:
            print(f"{note} — перечень может быть неполон", file=sys.stderr)
            return 2
        return 0
    if mode == "--impact":
        r = impact(normalize([a for a in rest if a]))
        lines = []
        if r.get("unread"):
            lines.append(r["unread"] + " — отчёт ниже НЕПОЛОН: у нечитаемого файла связи "
                         "и публичные имена выходят пустыми, как у пустого")
        if r.get("conflict"):
            lines.append(r["conflict"])
        if r["docs"]:
            shown = sorted(r["docs"])[:8]
            lines.append(f"описывают изменённое, но не тронуты ({len(r['docs'])}):")
            for d in shown:
                lines.append(f"  · {d} — про {', '.join(r['docs'][d][:3])}")
            if len(r["docs"]) > 8:
                lines.append(f"  · … и ещё {len(r['docs']) - 8} (полный список: --impact без хука)")
        if r["new_names"]:
            lines.append("новые публичные имена — учёт требует записи и на них:")
            for m, names in sorted(r["new_names"].items()):
                lines.append(f"  · {m}: {', '.join(names[:6])}")
        if r["dependents"]:
            dep = r["dependents"][:8]
            lines.append(f"зависят от изменённого ({len(r['dependents'])}) — реши, задело ли их описания:")
            lines.append("  " + ", ".join(dep) + (f" … и ещё {len(r['dependents']) - 8}" if len(r["dependents"]) > 8 else ""))
        if r["data_only"]:
            lines.append("правка внутри объявленной области данных — поведение не менялось:")
            for h in r["data_only"]:
                lines.append(f"  · {h}")
        if r["new_mech"]:
            lines.append("новые механизмы без строки в учёте:")
            for m in r["new_mech"]:
                lines.append(f"  · {m} — нужен документ и пересборка индекса")
        if r.get("descriptor"):
            lines.append("описание проекта изменено — связи считаются по нему заново, пересобери учёт")
        if r.get("rules"):
            lines.append(f"изменён код правила учёта ({', '.join(r['rules'])}) — строки строятся по нему заново, "
                         "пересобери учёт")
        if r.get("foreign_rule") and not r.get("rules"):
            lines.append("учёт собран другой редакцией правила — новые публичные имена по нему не судятся, "
                         "пересобери учёт (--all)")
        if r["stale"]:
            lines.append("строки учёта устарели — отчёт выше может быть неполным:")
            lines.append("  " + ", ".join(r["stale"][:6]))
        # С модулем описания сдвинутые документом строки точно знает `invalidated_by` — они уже в «строки учёта
        # устарели». Строка ниже — запасной путь без владельца: иначе «пересобери» звучало и при свежем учёте (D1077, R6).
        if PMAP is None and r["docs_changed"] and not (r["docs"] or r["new_names"] or r["new_mech"]):
            # Имена изменённых документов здесь НЕ перечисляются: они и так в коммите, а
            # «тронутый документ не поминается» — правило отчёта. Смысл ветви другой:
            # правка документа меняет чужие связи, и об этом надо сказать даже когда
            # механизмов в коммите нет вовсе, иначе учёт тихо разойдётся с деревом.
            lines.append(f"изменено документов: {len(r['docs_changed'])} — связи «кто что "
                         "описывает» могли поменяться, пересобери учёт")
        print("\n".join(lines))
        return 1 if lines else 0
    if mode == "--check":
        fresh, stored = build(), load()
        note = _unread_note()
        if note:
            # Проверяется ПЕРВЫМ: сравнение строк, посчитанных по непрочитанному файлу,
            # ничего не значит — у нечитаемого механизма строка выходит такой же, как у
            # пустого. Код 2 отличает «не смог сверить» от «разошлось» (код 1).
            print(f"{note} — сверка НЕ ВЫПОЛНЕНА: строка нечитаемого механизма совпадает "
                  f"со строкой пустого, и расхождение не всплыло бы")
            return 2
        drift = [p for p in set(fresh) | set(stored) if fresh.get(p) != stored.get(p)]
        if drift:
            print(f"индекс зависимостей устарел: строк расходится {len(drift)}")
            for p in sorted(drift)[:10]:
                print(f"  · {p}")
            if len(drift) > 10:
                print(f"  … и ещё {len(drift) - 10}")
            print("  пересобрать: python3 scripts/dep-index.py --all")
            return 1
        print(f"индекс зависимостей совпадает с деревом: механизмов {len(stored)}")
        return 0
    if mode == "--changed":
        paths = normalize(rest)
        # Вход, которого нет, — опечатка в пути: пересобирать нечего, а прибор рапортовал
        # успех и оставлял учёт несогласованным (изменённый на самом деле файл не
        # пересчитан, и `--check` краснел уже в другом ходе, без контекста правки).
        known = load()
        absent = [q for q in paths if q not in known and not input_exists(q)]
        if absent:
            print("нет такого входа: " + ", ".join(absent)
                  + " — учёт не тронут; проверь путь (он берётся от корня репозитория)",
                  file=sys.stderr)
            return 2
        rows = build(paths=paths)
    else:
        rows = build()
    note = _unread_note()
    if note:
        # Строка, посчитанная по нечитаемому файлу, неотличима от строки пустого файла и
        # СТАБИЛЬНА (sha пустоты не меняется) — записав её, индекс перестал бы краснеть
        # на этом механизме навсегда. Не записываем и говорим почему.
        print(f"{note} — индекс НЕ ЗАПИСАН: строка по нечитаемому файлу неотличима "
              f"от строки пустого и больше не покраснеет", file=sys.stderr)
        return 1
    save(rows)
    docs_linked = sum(1 for r in rows.values() if r[3])
    print(f"индекс собран: механизмов {len(rows)}, из них описаны в документах {docs_linked}")
    if not rows and PMAP is not None and PMAP.get("_source") != "умолчания":
        # Ноль по описанию называется причиной, а не тишиной (D1070, F10): «нет кода» и «язык вне разбора» — разное.
        langs = sorted({c["lang"] for c in PMAP["code"]} - set(project_map.SUPPORTED_LANGS))
        print("описание проекта не дало ни одного файла кода"
              + (f": языки вне разбора этой редакции — {', '.join(langs)}" if langs else ": образцы не нашли файлов"),
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
