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
#     tests — файлы тестов, называющие его
#     names — публичные имена: функции оболочки, определения верхнего уровня в python
#
# Обратные рёбра (кто зависит от меня) не хранятся: для 154 строк они считаются на лету,
# а хранение двух направлений — два источника правды об одном факте.
#
# КОНТРПРИМЕР: зависимость, собранная в переменной по частям («$D/$N.sh»), не опознаётся.
# Индекс видит литералы путей и имена файлов; вычисляемые пути — нет, и это известно.

import hashlib
import os
import re
import subprocess
import sys

REPO = os.environ.get("CLAUDSOUL_REPO") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX = os.path.join(REPO, ".claude-docs", "dep-index.tsv")

# Что считать механизмом — правило о файле, не перечень мест (тот же выбор, что в
# module-doc-check и docs-inventory после разбора 28 августа 2026).
MECH_RE = re.compile(r"\.(sh|py)$")
TEST_RE = re.compile(r"(^|/)tests?/")
MECH_SKIP = re.compile(r"(^|/)tests?/|^templates/|^scripts/publish/|__init__\.py$")
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
    out = subprocess.run(
        ["git", "-C", REPO, "ls-files", "-z", "--cached", "--others", "--exclude-standard", pattern],
        capture_output=True, text=True).stdout
    return sorted(set(l for l in out.split("\0") if l))


def mechanisms():
    return sorted(p for p in tracked("*.sh") + tracked("*.py")
                  if MECH_RE.search(p) and not MECH_SKIP.search(p))


# Снимок — документ, который описывает состояние НА МОМЕНТ НАПИСАНИЯ и обновлению не
# подлежит: разбор, ревизия, конкурентный обзор, архив. Требовать его правки при изменении
# кода значило бы просить подделать запись о прошлом.
#
# Признак — ЯВНАЯ пометка в самом документе, а не догадка по шапке. Догадку пробовали
# 28 августа 2026: «дата в первых строках» записала в снимки `architecture.md`, у которого
# дата ревью стоит рядом с обещанием покрывать текущую реализацию. Шесть ложных из
# двенадцати. Дата в шапке не отличает «описываю прошлое» от «проверено тогда-то».
SNAPSHOT_MARK = "<!-- doc-kind: snapshot -->"


def is_snapshot(path):
    if "-archive" in os.path.basename(path):
        return True
    return SNAPSHOT_MARK in "\n".join(read(path).splitlines()[:8])


def documents():
    return sorted(p for p in tracked("*.md")
                  if not DOC_SKIP.search(p) and not is_snapshot(p))


def tests():
    return sorted(p for p in tracked("*.sh") + tracked("*.py") if re.search(r"(^|/)tests?/", p))


def read(path):
    try:
        with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


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
        if p.endswith((".md", ".sh", ".py")) or MECH_SKIP.search(p):
            continue
        if p.endswith("dep-index.tsv"):
            continue
        out.append(p)
    return sorted(out)


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
    # только упоминание ПУТЁМ, иначе оба получат оба документа.
    if path is not None and name in ambiguous:
        rxp = re.compile(re.escape(path))
        return sorted(p for p, t in corpus if rxp.search(t))
    bare = r"(?<![A-Za-z0-9_-])" + re.escape(stem)
    if "-" in stem or "_" in stem:
        rx = re.compile(bare + r"(?![A-Za-z0-9_-])")
    else:
        # Третья форма — имя в обратных кавычках: документ так помечает, что это ИМЯ, а не
        # слово. На боевом дереве она не добавляет ни одной связи (482 против 482), то есть
        # ложных срабатываний не несёт, но даёт документу законный способ назвать
        # односложный механизм без расширения.
        rx = re.compile(r"(?:" + bare + re.escape("." + ext) + r"|/" + re.escape(stem)
                        + r"(?![A-Za-z0-9_-])|`" + re.escape(stem) + r"`)")
    return sorted(p for p, t in corpus if rx.search(t))


def build(paths=None):
    mech = mechanisms()
    mech_set = set(mech)
    seen = {}
    for x in mech:
        seen[os.path.basename(x)] = seen.get(os.path.basename(x), 0) + 1
    ambiguous = {n for n, c in seen.items() if c > 1}
    docs_corpus = [(p, read(p)) for p in documents()]
    tests_corpus = [(p, read(p)) for p in tests()]
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
            or any(TEST_RE.search(p) for p in paths)
        if any(p not in rows for p in paths if p in mech_set) or touches_corpus:
            paths = None
    if paths is not None:
        wanted = [p for p in paths if p in mech_set]
    else:
        wanted = mech
    for path in wanted:
        text = read(path)
        name = os.path.basename(path)
        rows[path] = [
            path,
            sha(text),
            join_list(deps_of(path, text, mech_set)),
            join_list(mentions(name, docs_corpus, path, ambiguous)),
            join_list(mentions(name, tests_corpus, path, ambiguous)),
            join_list(public_names(path, text)),
        ]
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
            if not line or line.startswith("#"):
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


def save(rows):
    os.makedirs(os.path.dirname(INDEX), exist_ok=True)
    with open(INDEX, "w", encoding="utf-8") as f:
        f.write("# path\tsha\tdeps\tdocs\ttests\tnames\n")
        f.write("# Генерируется scripts/dep-index.py — не править руками.\n")
        for path in sorted(rows):
            row = rows[path]
            f.write("\t".join([enc(row[0])] + list(row[1:])) + "\n")


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
    text = read(path)
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
    diff = subprocess.run(["git", "-C", REPO, "diff", "HEAD", "-U0", "--", path],
                          capture_output=True, text=True).stdout
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
    out = []
    for p in paths:
        q = os.path.normpath(p)
        if os.path.isabs(q):
            try:
                q = os.path.relpath(q, REPO)
            except ValueError:
                pass
        out.append(q)
    return out


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
                if MECH_RE.search(c) and not MECH_SKIP.search(c) and c not in rows]
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
    carrier_corpus = [(c, read(c)) for c in carriers()]
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
            if c[0] not in staged and needle in c[1]:
                dependents.add(c[0])
        # Новое публичное имя — новая способность внутри существующего модуля. Учёт
        # требует записи и на неё, а не только на новый файл: 28 августа 2026 четыре
        # предиката появились внутри библиотеки и не потребовали ни строки документации.
        before = set(split_list(rows[m][5]))
        after = set(public_names(m, read(m)))
        if after - before:
            renamed[m] = sorted(after - before)
    # Устаревшая строка: содержимое механизма уже другое, а связи в индексе — прежние.
    # Поле `sha` для этого и заведено, но его не читал ни один потребитель, и отчёт по
    # старой строке подавался как текущий. Отдельно: правка ДОКУМЕНТА меняет чужие связи,
    # и об этом надо сказать, даже когда механизмов в коммите нет вовсе — иначе учёт
    # тихо расходится с деревом. Оба случая найдены противником 28 августа 2026.
    stale = [] if conflict else sorted(m for m in mech if rows[m][1] != sha(read(m)))
    docs_changed = sorted(p for p in changed if p.endswith(".md") and not DOC_SKIP.search(p))
    return {"docs": docs, "dependents": sorted(dependents),
            "new_mech": sorted(new_mech), "new_names": renamed,
            "data_only": sorted(data_only), "stale": stale, "docs_changed": docs_changed,
            "conflict": conflict}


def main():
    args = sys.argv[1:]
    if "--impact" in args:
        i = args.index("--impact")
        r = impact(normalize([a for a in args[i + 1:] if a]))
        lines = []
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
        if r["stale"]:
            lines.append("строки учёта устарели — отчёт выше может быть неполным:")
            lines.append("  " + ", ".join(r["stale"][:6]))
        if r["docs_changed"] and not (r["docs"] or r["new_names"] or r["new_mech"]):
            # Имена изменённых документов здесь НЕ перечисляются: они и так в коммите, а
            # «тронутый документ не поминается» — правило отчёта. Смысл ветви другой:
            # правка документа меняет чужие связи, и об этом надо сказать даже когда
            # механизмов в коммите нет вовсе, иначе учёт тихо разойдётся с деревом.
            lines.append(f"изменено документов: {len(r['docs_changed'])} — связи «кто что "
                         "описывает» могли поменяться, пересобери учёт")
        print("\n".join(lines))
        return 1 if lines else 0
    if "--check" in args:
        fresh, stored = build(), load()
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
    if "--changed" in args:
        i = args.index("--changed")
        rows = build(paths=normalize(args[i + 1:]))
    else:
        rows = build()
    save(rows)
    docs_linked = sum(1 for r in rows.values() if r[3])
    print(f"индекс собран: механизмов {len(rows)}, из них описаны в документах {docs_linked}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
