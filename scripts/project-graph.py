#!/usr/bin/env python3
# project-graph.py — единая карта связей проекта: код И смыслы, в одном графе.
#
# Результат: по любому узлу виден ПОЛНЫЙ путь — на чём он стоит и что стоит на нём,
#            включая тесты, документы, знания, пункты долга и замеры
# Проверка результата: python3 scripts/project-graph.py --check даёт 0 и печатает числа
#            Ответ берётся из кэша рядом с картой; `--refresh` пересобирает силой
#            `--scc` печатает спайки — единицу разбора колец (кольцо ею НЕ является);
#            `--scc --exec` — только по рёбрам исполнения, где и возможна рекурсия
#            узлов и рёбер по видам; --node <путь> печатает полный путь одного узла
#
# Повод (13 сентября 2026, слово владельца). «Нет учёта зависимостей и связей и нет
# проверки. Что за функция тронута, где она ещё используется, что за хук, что на нём стоит
# и он на чём, что за тест, на чём он стоит, что его вызывает. Нет полного пути».
# Замер того дня подтвердил диагноз числом: в `.claude-docs/dep-index.tsv` 242 механизма,
# зависимости записаны у 162 (67%), обратной карты «функция → кто зовёт» нет вовсе, а
# смысловой слой (знания, пункты долга, замеры) в учёте не представлен ни одним ребром.
# Визуализация в дереве была только для базы знаний.
#
# ЧЕМ ЭТО РЕШАЛОСЬ РАНЬШЕ (правило «сперва узнай»): `dep-index.py` считает рёбра
# механизм→механизм, механизм→документ, механизм→тест и хранит публичные имена; он и
# остаётся ВЛАДЕЛЬЦЕМ этих рёбер — здесь они читаются из его файла, а не пересчитываются.
# Новое здесь три: обратные рёбра по именам функций, смысловой слой и единый граф.
#
# НАЗВАННЫЙ ПРЕДЕЛ: связь «знание ↔ механизм» выводится по УПОМИНАНИЮ имени файла в тексте
# знания, а не по объявлению — знание, говорящее о механизме иносказательно, ребра не даст.
# Условие снятия: у знаний появится поле с именем механизма, и ребро станет объявленным.
import json, os, re, subprocess, sys, glob, pathlib

# ОБЩИЙ ЗАМОК (род H). Кэш карты — файл не одного писателя: его пишут полная сборка,
# режим `--touch` и два хука, которые зовутся на каждую правку файла. Окно read→write
# открыто по построению, поэтому берётся тот же протокол, что у прочих общих файлов
# дерева: `hooks/lib/state_lock.py` (оболочечная половина — `hooks/state-lock-lib.sh`).
# Библиотеки нет — работаем как прежде: замок улучшает, а не требуется.
_LIB = pathlib.Path(__file__).resolve().parent.parent / "hooks" / "lib"
if not (_LIB / "state_lock.py").exists():
    _LIB = pathlib.Path.home() / ".claude/hooks/lib"
sys.path.insert(0, str(_LIB))
try:
    from state_lock import with_lock
except ImportError:
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):
        yield False

REPO = os.environ.get('CLAUDSOUL_REPO') or subprocess.run(
    ['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True).stdout.strip()
if not REPO:
    # ОТКАЗ РЕЗОЛВА НАЗЫВАЕТСЯ (род B). Пустая строка здесь означала бы, что все пути
    # складываются от корня файловой системы, а прибор при этом честно печатает «узлов 0»:
    # «не нашёл дерева» и «дерево пустое» отвечали бы одним числом.
    print('project-graph: корень не найден — задай CLAUDSOUL_REPO либо зови из репозитория',
          file=sys.stderr)
    sys.exit(2)
# ВЕРДИКТ ПО РОДУ B (13 сентября 2026): подстановка ниже — НАСТРОЙКА, а не проглоченный
# отказ. `LESSONS_DIR` называет, ГДЕ лежит база знаний; умолчание — её штатное место, и
# «переменная не задана» не есть «прочитать не смог». Прибор рода судит форму и потому
# считает этот файл носителем — оставляем носителем с записанным вердиктом, как уже
# сделано с тремя остатками рода. Настоящие два места (кэш и корень дерева) разведены выше.
LESSONS = os.path.expanduser(os.environ.get('LESSONS_DIR', '~/.claude/global-lessons'))
INDEX = os.path.join(REPO, '.claude-docs', 'dep-index.tsv')

def code_lines(text, is_py=False):
    """Текст без прозы: строки-комментарии и, у .py, тела тройных кавычек.

    Правило то же, что у владельца рёбер `scripts/dep-index.py` (`code_only`), и повторено
    здесь намеренно: карта читает файлы, которых в учёте нет вовсе (сами тесты), и брать
    ради этого чужой модуль дороже, чем держать семь строк. Расхождение поймает нога
    теста карты, а не молчание.
    """
    out, doc = [], None
    for line in text.split('\n'):
        st = line.lstrip()
        if doc is not None:
            if doc in st:
                doc = None
            continue
        if st.startswith('#'):
            continue
        if is_py:
            m = re.match(r'^[A-Za-z]*(' + '"' * 3 + '|' + "'" * 3 + ')', st)
            if m:
                if m.group(1) not in st[m.end():]:
                    doc = m.group(1)
                continue
        out.append(line)
    return '\n'.join(out)


def read_index():
    rows = []
    if not os.path.exists(INDEX):
        return rows
    with open(INDEX, errors='replace') as fh:
        for line in fh:
            if line.startswith('#'):
                continue
            p = line.rstrip('\n').split('\t')
            while len(p) < 6:
                p.append('')
            rows.append({'path': p[0], 'deps': p[2], 'docs': p[3], 'tests': p[4], 'names': p[5]})
    return rows

def tracked_files():
    out = subprocess.run(['git', '-C', REPO, 'ls-files'], capture_output=True, text=True).stdout
    return [f for f in out.split('\n') if f]

# ВИДЫ УЗЛОВ названы раздельно, а не одним «механизмом»: владелец просил видеть, ЧТО
# именно тронуто — хук, скрипт, библиотека или тест. Реестры отделены от прочих таблиц
# потому, что у них особая роль: они и есть объявленная правда о мире.
REGISTRIES = {
    'scripts/measurements.tsv': 'реестр замеров',
    'scripts/doc-claims.tsv': 'реестр чисел документов',
    'hooks/tests/always-run.tsv': 'реестр «всегда»',
    'hooks/tests/costly-justified.tsv': 'реестр дорогих тестов',
    'ROOTS.md': 'карта корней',
    'BACKLOG.md': 'долг',
    '.claude-docs/dep-index.tsv': 'индекс зависимостей',
}

def node_kind(path):
    if path in REGISTRIES:
        return 'registry'
    if path.startswith('hooks/tests/'):
        return 'test'
    if path.startswith('hooks/lib/') or path.endswith('-lib.sh'):
        return 'library'
    if path.startswith('hooks/') and path.endswith('.sh'):
        return 'hook'   # уточняется ниже до «страж», если у него есть канал наружу
    if '/tests/' in path or path.startswith('tests/'):
        return 'test'          # тесты сервера MCP лежат вне hooks/tests и тоже тесты
    if path.endswith(('.sh', '.py')):
        return 'script'        # любой исполняемый файл дерева, а не только три каталога
    if path.endswith('.md'):
        return 'doc'
    # ВИД ЕСТЬ У КАЖДОГО ФАЙЛА ДЕРЕВА (13 сентября 2026, слово владельца: «хуки, скрипты,
    # тесты, функции, документы — все они должны быть в карте»). Прежняя редакция отдавала
    # None всему, что не подошло трём каталогам, и такой файл в карту не попадал ВОВСЕ:
    # 44 файла из 1082, включая три теста сервера MCP, настройки хуков `.claude/settings.json`,
    # рецепт CI и шаблоны. Отсутствие узла читалось как «связей нет», хотя его просто не
    # спрашивали.
    if path.endswith(('.json', '.yml', '.yaml', '.toml', '.tsv', '.txt', '.plist', '.tmpl',
                      '.jq', '.sed', '.lock', '.gitignore', '.python-version')):
        return 'data'
    if path.endswith(('.html', '.js', '.css', '.png', '.svg', '.jpg')):
        return 'asset'
    return 'data'

# Отказ чтения СЧИТАЕТСЯ и НАЗЫВАЕТСЯ (род B). До 14 сентября 2026 нечитаемый файл молча
# получал роль по умолчанию, молча выпадал из обхода имён и молча оставался без исходящих
# рёбер: «не смог прочитать» было неотличимо от «прочитал, там пусто». Владелец правила для
# оболочки — hooks/lib/unread-lib.sh; здесь то же правило своим счётчиком, потому что прибор
# на питоне и библиотеку не источает.
UNREAD = []


def report_unread(where):
    if UNREAD:
        print(f'project-graph: НЕ ПРОЧИТАНО файлов: {len(UNREAD)} ({where}) — '
              + ', '.join(sorted(set(UNREAD))[:5]), file=sys.stderr)


def dep_role(src_path, dep_name, cache={}):
    """Роль ребра зависимости: ИСПОЛНЯЕТ файл или ЧИТАЕТ его как данные.

    Учёт (`scripts/dep-index.py`) знает ЧТО от чего зависит и намеренно не знает КАК:
    у него один вид связи. Карте различие нужно: рекурсию во время работы даёт только
    исполнение, а чтение файла кольцом не крутится. Замер 14 сентября 2026 (D406): спайка
    по «вызовам» — 45 узлов, и ВОСЕМЬ рёбер её рассыпают, из них шесть ведут в `install.sh`;
    проверка каждого показала, что это ЧТЕНИЕ установщика как реестра регистраций
    (`ins = (ROOT / "install.sh").read_text(…)`, `git grep -- … install.sh`,
    `python3 - "$ROOT/install.sh"`), а не его запуск.

    НАЗВАННЫЙ ПРЕДЕЛ: роль читается по форме строки. Исполнение через переменную
    (`"$TOOL"`, `$CMD`) распознаётся лишь когда рядом стоит имя файла; иначе ребро
    остаётся «зовёт» — то есть ошибка идёт в сторону БОЛЬШЕЙ связности, а не меньшей.
    """
    key = (src_path, dep_name)
    if key in cache:
        return cache[key]
    base = os.path.basename(dep_name)
    try:
        body = code_lines(open(os.path.join(REPO, src_path), errors='replace').read(),
                          src_path.endswith('.py'))
    except OSError:
        UNREAD.append(src_path)
        cache[key] = 'зовёт'
        return cache[key]
    hits = [l for l in body.split('\n') if base in l]
    if not hits:
        cache[key] = 'зовёт'
        return cache[key]
    # ИНТЕРПРЕТАТОР С `-` БЕРЁТ ПРОГРАММУ СО STDIN, а файл идёт аргументом-ДАННЫМИ:
    # `python3 - "$ROOT/install.sh"` установщик не запускает, а разбирает. Без этой оговорки
    # ребро числилось исполнением (замер 14 сентября 2026, `scripts/count-stats.sh:30`).
    EXEC = re.compile(r'(?:^|[;|&(]|\$\()\s*(?:bash|sh|zsh|python3?|perl|exec|source|\.)\s+(?!-\s)\S*'
                      + re.escape(base) + r'|(?:^|[;|&(])\s*\S*' + re.escape(base) + r'\s')
    READ = re.compile(r'(read_text|open\s*\(|\bcat\b|\bgrep\b|\bawk\b|\bsed\b|\bhead\b|'
                      r'\btail\b|\bwc\b|\bjq\b|<\s*\S*' + re.escape(base) + r'|--\s|'
                      r'(?:bash|sh|python3?|perl)\s+-\s)')
    # ИМЯ ВНУТРИ СООБЩЕНИЯ — НЕ СВЯЗЬ ИСПОЛНЕНИЯ. «Запусти install.sh» советует человеку,
    # а не вызывает: ребро зовётся «называет» и в кольца исполнения не входит.
    SAY = re.compile(r'^\s*(?:echo|printf|print|warn|info|error|die)\b')
    # РЕГИСТРАЦИЯ — НЕ ВЫЗОВ. Строка `"command": "bash ~/.claude/hooks/X"` в установщике
    # объявляет, КОГДА харнесс позовёт хук, но сам установщик его не запускает. Без этой
    # роли `install.sh` оказывался в кольце с каждым зарегистрированным хуком, и спайка
    # исполнения раздувалась (замер 14 сентября 2026, D406).
    REG = re.compile(r'"command"\s*:\s*"|"matcher"\s*:')
    # Имя в образце `case` — сверка ТЕКСТА, а не запуск: `*install.sh*) exit 0 ;;`.
    CASE = re.compile(r'^\s*[*\w|\-]*\*?' + re.escape(base) + r'\*?[\w|]*\)\s')
    if all(REG.search(l) for l in hits):
        cache[key] = 'устанавливает'
        return cache[key]
    if all(CASE.search(l) for l in hits):
        cache[key] = 'называет'
        return cache[key]
    # ИМЯ ВНУТРИ СТРОКОВОЙ КОНСТАНТЫ — тоже упоминание: маркер
    # `CLAUDE_MD_MARKER_START="<!-- … (install.sh синхронизирует область) -->"` объявляет
    # ТЕКСТ, а не запуск. Это была последняя пара спайки исполнения (D406).
    CONST = re.compile(r'^\s*[A-Za-z_][A-Za-z0-9_]*=(["\']).*' + re.escape(base))
    if all(CONST.search(l) for l in hits):
        cache[key] = 'называет'
        return cache[key]
    if any(EXEC.search(l) for l in hits):
        cache[key] = 'зовёт'
    elif all(SAY.match(l) for l in hits):
        cache[key] = 'называет'
    elif all(READ.search(l) for l in hits):
        cache[key] = 'читает'
    else:
        cache[key] = 'зовёт'
    return cache[key]


def build():
    nodes, edges, seen = [], [], {}

    def nid(key, kind, name=None):
        if key not in seen:
            seen[key] = len(seen) + 1
            nodes.append({'id': seen[key], 'name': name or key, 'type': kind, 'key': key})
        return seen[key]

    rows = read_index()
    files = tracked_files()

    # 1. Узлы кода и документов — из учёта и дерева
    for f in files:
        k = node_kind(f)
        if k:
            nid(f, k, os.path.basename(f))

    # 2. Рёбра механизм→механизм / →тест / →документ: ВЛАДЕЛЕЦ рёбер — dep-index
    name_owners = {}
    for r in rows:
        src = nid(r['path'], node_kind(r['path']) or 'mechanism', os.path.basename(r['path']))
        for dep in filter(None, r['deps'].split(',')):
            edges.append({'source': src, 'target': nid(dep, node_kind(dep) or 'mechanism', os.path.basename(dep)),
                          'type': dep_role(r['path'], dep), 'strength': 3})
        for t in filter(None, r['tests'].split(',')):
            edges.append({'source': nid(t, 'test', os.path.basename(t)), 'target': src, 'type': 'проверяет', 'strength': 2})
        for d in filter(None, r['docs'].split(',')):
            edges.append({'source': nid(d, 'doc', os.path.basename(d)), 'target': src, 'type': 'описывает', 'strength': 1})
        for n in filter(None, r['names'].split(',')):
            name_owners.setdefault(n.strip(), set()).add(r['path'])

    # ИМЯ С НЕСКОЛЬКИМИ ВЛАДЕЛЬЦАМИ ВЛАДЕЛЬЦА НЕ ИМЕЕТ (13 сентября 2026).
    # Первая редакция брала `setdefault(имя, путь)` — первый встреченный файл забирал имя
    # себе, а остальные определения терялись молча. Цена измерена на самой карте: у `main`
    # 27 владельцев, у `to_lower` 12, у `is_git_commit` 10 — всего 38 имён из 442, — и
    # каждое чужое определение давало ребро «использует» в произвольного из них. Так
    # возникло кольцо `project-graph.py ↔ defect-class-carriers.py`, где второй файл
    # слова `project-graph` не содержит вовсе. Предмет объявлялся как «имя → владелец»,
    # тогда как мир даёт «имя → владельцы»: признак снят с ВИДА плоской колонки, а
    # различать надо роль (pattern-marker-matches-form-not-role).
    # Дерево знало об этом заранее: род K называет `to_lower` при 16 копиях примитивом.
    # НАЗВАННЫЙ ПРЕДЕЛ: общий помощник, объявленный в библиотеке И переопределённый у
    # потребителя, теряет ребро целиком — молчание вместо лжи. Условие снятия: появится
    # разбор области видимости, и владелец будет выбираться, а не отбрасываться.
    name_owner = {n: next(iter(o)) for n, o in name_owners.items() if len(o) == 1}
    name_shared = {n: sorted(o) for n, o in name_owners.items() if len(o) > 1}

    # 3. ОБРАТНАЯ КАРТА ФУНКЦИЙ — то, чего не было: где ещё используется имя.
    #    Один проход по дереву вместо грепа на каждое имя: имён сотни.
    # ИМЯ СЧИТАЕТСЯ ИСПОЛЬЗОВАННЫМ ПО ПОЗИЦИИ ВЫЗОВА, а не по голому слову (13 сентября 2026).
    # Первая редакция брала `\bимя\b` и дала 3464 ребра, из которых половину составляли
    # общие слова: `tests` 390, `ok` 300, `bad` 293, `read` 191 — это локальные хелперы,
    # встречающиеся в каждом тесте. Признак судил вид текста, а различать надо роль
    # (pattern-marker-matches-form-not-role). Теперь имя засчитывается, если стоит как вызов:
    # `имя(` либо командным словом в начале строки или после `;`, `|`, `&&`, `$(`.
    # НАЗВАННЫЙ ПРЕДЕЛ: вызов через переменную (`$fn "$arg"`) не виден; условие снятия —
    # разбор оболочки вместо шаблона.
    if name_owner:
        # ИМЯ, СОВПАДАЮЩЕЕ С КОМАНДОЙ ИЛИ ВСТРОЕННЫМ СЛОВОМ ОБОЛОЧКИ, именем модуля не
        # считается: `read`, `find`, `test`, `log` стоят в позиции вызова в каждом втором
        # файле и дают ребро в никуда. Отсев МЕХАНИЧЕСКИЙ — спрашиваем систему, а не вкус.
        builtins = set(subprocess.run(['bash', '-c', 'compgen -b; compgen -c | sort -u'],
                                      capture_output=True, text=True).stdout.split('\n'))
        long_names = [n for n in name_owner if len(n) >= 4 and n not in builtins]
        # ОДИН ПРОХОД НА ВСЕ ИМЕНА, а не проход на имя (13 сентября 2026). Прежняя
        # редакция гоняла 397 шаблонов по 790 файлам кода: 51,5 с из 60 с всей сборки, —
        # и цена била по потребителю, ради которого карта и строилась (хук правки).
        # Замер равенства: одна альтернатива дала ТЕ ЖЕ 1185 совпадений, расхождений 0,
        # время 1,5 с. Длинные имена стоят раньше коротких: альтернатива в re берёт
        # ПЕРВОЕ подошедшее, и без сортировки `dis_expire` съел бы `dis_expire_old`.
        if long_names:
            alt = '|'.join(sorted(map(re.escape, long_names), key=len, reverse=True))
            # ПРИСВАИВАНИЕ — НЕ ВЫЗОВ (13 сентября 2026). В позиции команды стоит и
            # `stats=$(jq …)`, и `note = os.environ[…]` внутри встроенного python: имя в
            # начале строки, а роль обратная. Замер: 29 рёбер из 794 держались ТОЛЬКО на
            # присваивании, все ложные. Отсекается лукахедом `=` (кроме `==`); ветка
            # `имя(` не трогается — там роль вызова видна знаком.
            # РОЛЬ ИМЕНИ, А НЕ ЕГО ВИД (14 сентября 2026, D411). Три формы давали ложные
            # рёбра, и все три проверены глазом: `re.search(` — вызов МЕТОДА чужого объекта,
            # а не функции-владельца (dep-index.py:74 и ещё восемь мест); `entries.append(`
            # — обращение к полю локальной переменной (storage.py:474); `impact: int,` и
            # `impact INTEGER,` — объявление параметра и SQL внутри строки (storage.py:90,153).
            # Лукбехайнд снимает первую, запрет на `.`/`:` следом — две другие.
            big = re.compile(r'(?:^|[;|&]|\$\()\s*(' + alt + r')\b(?![.:]|\s*=[^=])'
                             r'|(?<![.\w])(' + alt + r')\(', re.M)
            for f in files:
                if not f.endswith(('.sh', '.py')):
                    continue
                try:
                    # КОД, а не сырой текст: комментарий и строка документации — проза, а не
                    # вызов. Правило уже стоит у владельца рёбер (dep-index.py) и у dep_role;
                    # сюда оно не дошло, и обратная карта считала прозу наравне с кодом.
                    text = code_lines(open(os.path.join(REPO, f), errors='replace').read(),
                                      f.endswith('.py'))
                except OSError:
                    UNREAD.append(f)
                    continue
                for mt in {(mo.group(1) or mo.group(2)) for mo in big.finditer(text)}:
                    owner = name_owner[mt]
                    if owner == f:
                        continue
                    edges.append({'source': nid(f, node_kind(f) or 'mechanism', os.path.basename(f)),
                                  'target': nid(owner, node_kind(owner) or 'mechanism', os.path.basename(owner)),
                                  'type': f'использует {mt}', 'strength': 2})

    # 3б. ТЕСТ, ЧЕЙ ПРЕДМЕТ — ДРУГОЙ ТЕСТ (13 сентября 2026, слово владельца: «связь должна
    #     быть механизм-тест, и оба в карте должны быть отражены»). Колонка `tests` учёта
    #     есть только у МЕХАНИЗМОВ, поэтому проверка стража стражем в карту не попадала
    #     вовсе: 19 узлов-тестов висели без единого ребра, а связей в коде — 115 у 88 тестов.
    #     Связь многие-ко-многим и такой и остаётся: один тест покрывает несколько предметов
    #     (рекорд дерева — 22), у одного предмета бывает несколько тестов (64 у install.sh).
    #     Роль строки та же, что везде: комментарий и докстринг .py — проза, не код.
    test_files = [f for f in files if '/tests/' in f and f.endswith(('.sh', '.py'))]
    tf_by_name = {os.path.basename(t): t for t in test_files}
    for t in test_files:
        try:
            body = code_lines(open(os.path.join(REPO, t), errors='replace').read(), t.endswith('.py'))
        except OSError:
            continue
        for other, opath in tf_by_name.items():
            if opath == t or other not in body:
                continue
            edges.append({'source': nid(t, 'test', os.path.basename(t)),
                          'target': nid(opath, 'test', other),
                          'type': 'проверяет', 'strength': 2})

    # 3в. СОБЫТИЕ ХУКА — сущность, которой в карте не было (13 сентября 2026, слово
    #     владельца: «пройди флоу пошагово, все сущности и связи должны быть видны»).
    #     Повод измерен в тот же час: хук `impact-inject` висел на Edit|Write|MultiEdit,
    #     а правки шли командой Bash — механизм не задевал реальный поток, и по карте
    #     прошло 0 правок из 11 при зелёных тестах. Из карты этого видно не было: узел
    #     хука есть, а КОГДА он срабатывает и кто делит с ним событие — нет.
    #     Источник — регистрация в `install.sh` (владелец состава хуков, ADR-009);
    #     нет install.sh — слоя просто нет, молча.
    inst = os.path.join(REPO, 'install.sh')
    if os.path.exists(inst):
        cur_event, cur_matcher = None, ''
        for line in open(inst, errors='replace'):
            ev = re.search(r'"(PreToolUse|PostToolUse|Stop|UserPromptSubmit|SessionStart|'
                           r'PreCompact|Notification|SubagentStop|SessionEnd)"\s*:', line)
            if ev:
                cur_event, cur_matcher = ev.group(1), ''
                continue
            mt = re.search(r'"matcher"\s*:\s*"([^"]*)"', line)
            if mt:
                cur_matcher = mt.group(1)
                continue
            hk = re.search(r'hooks/([a-z0-9_-]+\.sh)', line)
            if hk and cur_event:
                hp = 'hooks/' + hk.group(1)
                if hp not in seen:
                    continue
                label = cur_event + (f'[{cur_matcher}]' if cur_matcher else '')
                edges.append({'source': nid(hp, node_kind(hp) or 'hook', os.path.basename(hp)),
                              'target': nid('событие:' + label, 'event', label),
                              'type': 'висит на', 'strength': 3})

    # 4. Смысловой слой: замеры
    mpath = os.path.join(REPO, 'scripts', 'measurements.tsv')
    if os.path.exists(mpath):
        for line in open(mpath, errors='replace'):
            if line.startswith('#') or not line.strip():
                continue
            p = line.split('\t')
            if len(p) < 3:
                continue
            mid = nid('замер:' + p[0], 'measurement', p[0])
            for f in files:
                if f.endswith(('.sh', '.py')) and os.path.basename(f) in p[2]:
                    edges.append({'source': mid, 'target': nid(f, node_kind(f) or 'mechanism', os.path.basename(f)), 'type': 'мерит', 'strength': 2})

    # 5. Смысловой слой: пункты долга
    for bl in ('BACKLOG.md', 'BACKLOG-archive.md'):
        bp = os.path.join(REPO, bl)
        if not os.path.exists(bp):
            continue
        cur = None
        for line in open(bp, errors='replace'):
            m = re.search(r'\*\*(D\d+)\*\*', line)
            if m:
                cur = m.group(1)
                nid('пункт:' + cur, 'backlog', cur)
            if cur:
                for f in files:
                    if f.endswith(('.sh', '.py')) and os.path.basename(f) in line:
                        edges.append({'source': seen['пункт:' + cur], 'target': nid(f, node_kind(f) or 'mechanism', os.path.basename(f)), 'type': 'пункт о', 'strength': 1})

    # 6. Смысловой слой: знания
    for kf in sorted(glob.glob(os.path.join(LESSONS, '*.md'))):
        base = os.path.basename(kf)
        if not base.startswith(('case-', 'pattern-', 'principle-')):
            continue
        try:
            txt = open(kf, errors='replace').read()
        except OSError:
            continue
        ktype = 'case' if base.startswith('case-') else ('pattern' if base.startswith('pattern-') else 'principle')
        kid = None
        for f in files:
            if f.endswith(('.sh', '.py')) and os.path.basename(f) in txt:
                if kid is None:
                    kid = nid('знание:' + base[:-3], ktype, base[:-3])
                edges.append({'source': kid, 'target': nid(f, node_kind(f) or 'mechanism', os.path.basename(f)), 'type': 'знание о', 'strength': 1})

    # 6б. СТРАЖИ — отдельный вид, а не «просто хук». Страж отличается КАНАЛОМ наружу, и
    #     именно канал мы сегодня путали: `additionalContext` — инжект (уровень 2),
    #     `permissionDecision: ask` — вопрос владельцу, `deny` — отказ (уровень 4).
    #     Вид узла несёт канал, чтобы «механизм сработает» не приходилось проверять грепом.
    for n in nodes:
        if n.get('type') != 'hook':
            continue
        try:
            t = open(os.path.join(REPO, n['key']), errors='replace').read()
        except OSError:
            continue
        code = '\n'.join(l for l in t.split('\n') if not l.lstrip().startswith('#'))
        if 'permissionDecision' in code and '"deny"' in code:
            n['type'], n['channel'] = 'guard', 'отказ'
        elif 'permissionDecision' in code:
            n['type'], n['channel'] = 'guard', 'вопрос'
        elif 'additionalContext' in code:
            n['type'], n['channel'] = 'guard', 'инжект'

    # 6в. ДОКУМЕНТАЦИЯ по роду: документ состояния, док модуля, решение (ADR), правила.
    for n in nodes:
        if n.get('type') != 'doc':
            continue
        k = n['key']
        if k.startswith('.claude-docs/modules/'):
            n['doc_kind'] = 'док модуля'
        elif k in ('docs/decisions.md',):
            n['doc_kind'] = 'решения (ADR)'
        elif k.startswith('rules/') or k.endswith('CLAUDE.md'):
            n['doc_kind'] = 'правила'
        elif k in ('CHANGELOG.md', 'SESSION.md', 'внутренний архив (не публикуется)'):
            n['doc_kind'] = 'хроника'
        else:
            n['doc_kind'] = 'документ состояния'

    # 7. ФУНКЦИИ УЗЛАМИ, а не ярлыками на рёбрах: владелец спрашивает «что за функция
    #    тронута и где ещё используется» — на этот вопрос отвечает узел со своими рёбрами.
    for n, owner in name_owner.items():
        if len(n) < 4:
            continue
        fid = nid('функция:' + n, 'function', n)
        edges.append({'source': fid, 'target': nid(owner, node_kind(owner) or 'script', os.path.basename(owner)),
                      'type': 'определена в', 'strength': 3})

    # 8. РОДЫ ДЕФЕКТА и КОРНИ — сущности реестров, а не файлы.
    reg = os.path.join(REPO, 'scripts', 'defect-class-carriers.py')
    if os.path.exists(reg):
        out = subprocess.run(['python3', reg, '--list'], capture_output=True, text=True, cwd=REPO).stdout
        cur = None
        for line in out.split('\n'):
            m = re.match(r'^РОД ([A-L]) · (.+?) —', line)
            if m:
                cur = nid('род:' + m.group(1), 'genus', f'род {m.group(1)}: {m.group(2)[:40]}')
                continue
            m2 = re.search(r'(hooks/[^\s]+|scripts/[^\s]+)', line)
            if cur and m2:
                f = m2.group(1)
                edges.append({'source': cur, 'target': nid(f, node_kind(f) or 'script', os.path.basename(f)),
                              'type': 'носитель рода', 'strength': 2})
    roots = os.path.join(REPO, 'ROOTS.md')
    if os.path.exists(roots):
        cur = None
        for line in open(roots, errors='replace'):
            m = re.search(r'\b(R\d)\b[^\n]{0,80}', line)
            if m and line.lstrip().startswith('#'):
                cur = nid('корень:' + m.group(1), 'root', m.group(0)[:50])
            if cur:
                for f in files:
                    if f.endswith(('.sh', '.py')) and os.path.basename(f) in line:
                        edges.append({'source': cur, 'target': nid(f, node_kind(f) or 'script', os.path.basename(f)),
                                      'type': 'корень держит', 'strength': 2})

    # 9. ПЕРЕДАЧА ДАННЫХ — второе направление, которого не было: кто ПИШЕТ файл состояния
    #    и кто его ЧИТАЕТ. Без этого «зависимость» видна, а поток данных нет.
    state_re = re.compile(r'(?:STATE_DIR|STATE)["\']?[}]?/([a-z0-9][a-z0-9._-]*\.(?:jsonl|tsv|txt|json))')
    for f in files:
        if not f.endswith(('.sh', '.py')):
            continue
        try:
            text = open(os.path.join(REPO, f), errors='replace').read()
        except OSError:
            continue
        for m in set(state_re.findall(text)):
            jid = nid('журнал:' + m, 'journal', m)
            fid = nid(f, node_kind(f) or 'script', os.path.basename(f))
            # Направление по устройству: `>>`/`>` рядом с именем — запись, иначе чтение.
            writes = re.search(r'>>?\s*"?[^"\n]*' + re.escape(m), text) is not None
            edges.append({'source': fid, 'target': jid, 'type': 'пишет' if writes else 'читает', 'strength': 2}
                         if writes else {'source': jid, 'target': fid, 'type': 'читает', 'strength': 1})

    # 9б. ПАРАМЕТРЫ ТЕСТА: число ног и объявленный результат — владелец просил видеть тест
    #     не как файл, а как проверку с содержимым.
    for n in nodes:
        if n.get('type') != 'test':
            continue
        try:
            t = open(os.path.join(REPO, n['key']), errors='replace').read()
        except OSError:
            continue
        n['legs'] = len(re.findall(r'^\s*#\s*-{2,}\s*T\d', t, re.M)) or len(re.findall(r'\bT\d+[а-я]?\b', t))
        m = re.search(r'^#\s*Результат:\s*(.+)$', t, re.M)
        if m:
            n['result'] = m.group(1).strip()[:120]

    # 10. ИСТОРИЯ: у каждого файлового узла — когда правился в последний раз и сколько раз
    #     за 30 дней. Владелец просил «проследить, где что когда менялось».
    hist = {}
    log = subprocess.run(['git', '-C', REPO, 'log', '--since=30 days ago',
                          '--pretty=format:%ad', '--date=short', '--name-only'],
                         capture_output=True, text=True).stdout
    cur_date = None
    for line in log.split('\n'):
        if re.match(r'^\d{4}-\d{2}-\d{2}$', line.strip()):
            cur_date = line.strip()
        elif line.strip() and cur_date:
            h = hist.setdefault(line.strip(), {'edits': 0, 'last': cur_date})
            h['edits'] += 1
            if cur_date > h['last']:
                h['last'] = cur_date
    for n in nodes:
        h = hist.get(n.get('key', ''))
        if h:
            n['edits30'] = h['edits']
            n['last_change'] = h['last']

    return {'nodes': nodes, 'edges': edges, 'domains': [], 'shared_names': name_shared}

def counts(g):
    from collections import Counter
    return Counter(n['type'] for n in g['nodes']), Counter(e['type'].split()[0] for e in g['edges'])

def path_of(g, key):
    idx = {n['id']: n for n in g['nodes']}
    tgt = [n for n in g['nodes'] if n['key'] == key or n['name'] == key]
    if not tgt:
        return f'узла «{key}» в карте нет'
    out = []
    for t in tgt:
        up = [f"{idx[e['source']]['key']} --{e['type']}-->" for e in g['edges'] if e['target'] == t['id']]
        down = [f"--{e['type']}--> {idx[e['target']]['key']}" for e in g['edges'] if e['source'] == t['id']]
        out.append(f"=== {t['key']} ({t['type']}) ===\nНА НЁМ СТОЯТ ({len(up)}):\n  " + '\n  '.join(up[:40]) +
                   f"\nОН СТОИТ НА ({len(down)}):\n  " + '\n  '.join(down[:40]))
    return '\n'.join(out)

def brief(g, key):
    """Одна строка про узел: кто на нём стоит, по видам. Для потребителя в ходе правки."""
    idx = {n['id']: n for n in g['nodes']}
    tgt = [n for n in g['nodes'] if n['key'] == key or n['name'] == key]
    if not tgt:
        return ''
    t = tgt[0]
    # СЧИТАЮТСЯ РАЗЛИЧНЫЕ УЗЛЫ, а не рёбра: один документ называет механизм дважды —
    # это одна зависимость, а не две (первая редакция печатала «CLAUDE.md, CLAUDE.md»).
    up = list({idx[e['source']]['id']: idx[e['source']] for e in g['edges'] if e['target'] == t['id']}.values())
    down = [e for e in g['edges'] if e['source'] == t['id']]
    by = {}
    for n in up:
        by.setdefault(n['type'], []).append(n['name'])
    order = ['test', 'hook', 'guard', 'script', 'library', 'mechanism', 'doc', 'case', 'pattern',
             'principle', 'backlog', 'measurement', 'genus', 'root', 'function', 'registry', 'journal']
    parts = []
    for k in order + [x for x in by if x not in order]:
        v = by.get(k)
        if not v:
            continue
        uniq = sorted({x[:48] for x in v})
        names = ', '.join(uniq[:3]) + ('…' if len(uniq) > 3 else '')
        parts.append(f'{k} {len(v)} ({names})')
    return f'на нём стоят {len(up)}: ' + '; '.join(parts) + f' | сам стоит на {len(down)}'


def sccs(g):
    """Сильно связные куски по рёбрам исполнения и данных (Тарьян, итеративно).

    ЕДИНИЦА РАЗБОРА — КУСОК, А НЕ КОЛЬЦО (13 сентября 2026). `--cycles` печатает 88
    путей, но 72 из них — обходы ОДНОГО и того же клубка: вердикт по каждому был бы
    восемьдесят восемь раз переписанным одним фактом (pattern-subject-of-measurement-mismatch).
    Внутри куска достижимо всё из всего, поэтому чинится он не «кольцом», а ребром:
    набор рёбер, чей разрыв рассыпает кусок.
    """
    KIND = ('зовёт', 'использует', 'пишет', 'читает', 'проверяет')
    adj = {}
    for e in g['edges']:
        if e['type'].startswith(KIND):
            adj.setdefault(e['source'], set()).add(e['target'])
    nodes = set(adj) | {t for s in adj.values() for t in s}
    index, low, onstk, stk, out, cnt = {}, {}, {}, [], [], [0]
    for root in nodes:
        if root in index:
            continue
        work = [(root, iter(adj.get(root, ())))]
        index[root] = low[root] = cnt[0]; cnt[0] += 1; stk.append(root); onstk[root] = True
        while work:
            v, it = work[-1]
            advanced = False
            for w in it:
                if w not in index:
                    index[w] = low[w] = cnt[0]; cnt[0] += 1; stk.append(w); onstk[w] = True
                    work.append((w, iter(adj.get(w, ())))); advanced = True; break
                elif onstk.get(w):
                    low[v] = min(low[v], index[w])
            if advanced:
                continue
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[v])
            if low[v] == index[v]:
                comp = []
                while True:
                    w = stk.pop(); onstk[w] = False; comp.append(w)
                    if w == v:
                        break
                if len(comp) > 1:
                    out.append(comp)
    out.sort(key=len, reverse=True)
    return out, len(nodes)


def cycles(g):
    """Кольца по рёбрам ИСПОЛНЕНИЯ и ДАННЫХ. Предмет — замкнутый путь, по которому
    управление или данные возвращаются в тот же узел: именно он даёт «починил здесь —
    вылезло там» и спираль правок (case-2026-09-01-check-runner-ring-breeds-process-storm).
    Рёбра описания («описывает», «знание о», «пункт о») в счёт НЕ идут: по ним ничего
    не исполняется, и кольцо из них — не кольцо, а перекрёстная ссылка."""
    import collections
    KIND = ('зовёт', 'использует', 'пишет', 'читает', 'проверяет')
    adj = collections.defaultdict(set)
    for e in g['edges']:
        if e['type'].split()[0] in KIND:
            adj[e['source']].add(e['target'])
    color, found = {}, []
    idx = {n['id']: n for n in g['nodes']}
    def dfs(u, stack):
        color[u] = 1
        stack.append(u)
        for v in adj[u]:
            if color.get(v) == 1:
                found.append(stack[stack.index(v):] + [v])
            elif color.get(v, 0) == 0:
                dfs(v, stack)
        stack.pop()
        color[u] = 2
    sys.setrecursionlimit(20000)
    for n in list(adj):
        if color.get(n, 0) == 0:
            dfs(n, [])
    uniq, seen = [], set()
    for c in sorted(found, key=len):
        k = tuple(sorted(set(c)))
        if k not in seen:
            seen.add(k)
            uniq.append([idx[x]['key'] for x in c])
    return uniq


DATA = os.path.join(REPO, 'mcp-server', 'visualization', 'project-graph-data.json')


def load(fresh=False):
    """Карта из кэша, если он не старше учёта; иначе сборка с записью кэша.

    Сборка стоит 54 с (замер 13 сентября 2026: обход дерева по именам функций плюс
    чтение базы знаний). Потребитель карты — агент в цикле правки: «перед правкой
    посмотреть, что ещё зависит; после сохранения — не сломал ли» (слово владельца
    13 сентября 2026). Полсотни секунд на КАЖДУЮ правку такой потребитель не переживёт,
    поэтому ответ берётся из кэша, а свежесть решается ОДНИМ сравнением — кэш против
    учёта `.claude-docs/dep-index.tsv`, владельца рёбер.
    НАЗВАННЫЙ ПРЕДЕЛ: правка, не тронувшая учёт (текст знания, тело пункта долга), в кэш
    не попадёт до следующей пересборки. Условие снятия: у кэша появится свой сторож
    свежести по mtime источников, а не по одному учёту.
    """
    if not fresh and os.path.exists(DATA):
        try:
            if os.path.getmtime(DATA) >= os.path.getmtime(INDEX):
                return json.load(open(DATA))
        except OSError as exc:
            # ОТКАЗ ЧТЕНИЯ ГОВОРИТСЯ, а не глотается (род B): «кэша нет» и «кэш не читается»
            # суть разные состояния мира, и молчание об отказе читается как «кэш устарел».
            print(f'project-graph: кэш не прочитан ({exc}) — собираю заново', file=sys.stderr)
        except ValueError as exc:
            print(f'project-graph: кэш повреждён ({exc}) — собираю заново', file=sys.stderr)
    if os.environ.get('PROJECT_GRAPH_NO_BUILD'):
        return None          # потребителю с потолком цены: кэша нет либо он стар
    g = build()
    try:
        with with_lock(DATA):
            json.dump(g, open(DATA, 'w'), ensure_ascii=False)
    except OSError:
        pass
    return g


def touch(path):
    """Внести ОДИН файл в кэш карты, не пересобирая её (13 сентября 2026).

    Повод — слово владельца: «при создании должно новое в карту попадать». Замер флоу в тот
    день: только что созданный файл в карте отсутствовал, а хук правки на нём МОЛЧАЛ, и
    молчание читалось как «связей нет» — ровно там, где связи нужнее всего. Полная сборка
    стоит 10 с, пересборка учёта 9 с — на каждую запись файла ни то, ни другое не годится.
    Здесь считается только то, что видно из САМОГО файла: его узел и его исходящие рёбра
    («зовёт» по литералам имён дерева).
    НАЗВАННЫЙ ПРЕДЕЛ: ВХОДЯЩИЕ рёбра (кто зовёт новый файл, какой тест его проверяет, какой
    документ описывает) требуют прохода по всему дереву и появляются на ближайшем `--refresh`;
    узел при этом уже стоит в карте и виден как одинокий, а не отсутствует. Условие снятия:
    инкрементальный обратный проход по одному имени.
    """
    # ПРИЧИНА НАЗЫВАЕТСЯ, А НЕ СВОРАЧИВАЕТСЯ В ОДНО «нет» (род B): три состояния мира —
    # кэша нет, кэш не читается, файл вне дерева — раньше отвечали одним `None`, и вызывающий
    # печатал про них одну строку.
    if not os.path.exists(DATA):
        return 'кэша нет'
    try:
        g = json.load(open(DATA))
    except OSError as exc:
        return f'кэш не прочитан: {exc}'
    except ValueError as exc:
        return f'кэш повреждён: {exc}'
    rel = os.path.relpath(os.path.abspath(path), REPO)
    if rel.startswith('..'):
        return 'файл вне дерева'
    kind = node_kind(rel)
    seen = {n['key']: n for n in g['nodes']}
    if rel in seen:
        node = seen[rel]
    else:
        node = {'id': max((n['id'] for n in g['nodes']), default=0) + 1,
                'name': os.path.basename(rel), 'type': kind, 'key': rel,
                'edits30': 0, 'last_change': ''}
        g['nodes'].append(node)
    # исходящие рёбра по литералам имён файлов дерева — один проход по своему тексту
    try:
        body = code_lines(open(os.path.join(REPO, rel), errors='replace').read(), rel.endswith('.py'))
    except OSError:
        UNREAD.append(rel)
        body = ''
    by_key = {n['key']: n for n in g['nodes'] if n.get('key')}
    have = {(e['source'], e['target']) for e in g['edges']}
    added = 0
    for other, onode in by_key.items():
        if other == rel or '/' not in other:
            continue
        if os.path.basename(other) in body and (node['id'], onode['id']) not in have:
            g['edges'].append({'source': node['id'], 'target': onode['id'],
                               'type': 'зовёт', 'strength': 3})
            added += 1
    with with_lock(DATA):
        json.dump(g, open(DATA, 'w'), ensure_ascii=False)
    return rel, kind, added


if __name__ == '__main__':
    if '--touch' in sys.argv:
        r = touch(sys.argv[sys.argv.index('--touch') + 1])
        if isinstance(r, str):
            print(f'карта не тронута: {r}', file=sys.stderr)
            sys.exit(3)
        print(f'в карте: {r[0]} ({r[1]}), исходящих рёбер добавлено {r[2]}')
        report_unread('внесение узла')
        sys.exit(0)
    g = load(fresh='--refresh' in sys.argv)
    if g is None:
        print('карта не пересобрана: кэш отсутствует или старше учёта', file=sys.stderr)
        sys.exit(3)
    if '--scc' in sys.argv:
        # `--exec` — только рёбра ИСПОЛНЕНИЯ: рекурсию во время работы даёт лишь вызов,
        # журнал и тест кольцом не крутятся (D406, 14 сентября 2026).
        if '--exec' in sys.argv:
            g = {'nodes': g['nodes'],
                 'edges': [e for e in g['edges'] if e['type'].startswith('зовёт')]}
        comps, total = sccs(g)
        idx = {n['id']: n for n in g['nodes']}
        print(f'спаек (кусков, где всё достижимо из всего): {len(comps)}; '
              f'узлов в рёбрах исполнения и данных: {total}')
        for c in comps:
            names = sorted(idx[x]['name'] for x in c)
            print(f'  [{len(c)} узлов, {len(c) * 100 // total}% от {total}] ' + ', '.join(names[:12]) +
                  ('…' if len(names) > 12 else ''))
        report_unread('спайки')
        sys.exit(0 if not comps else 1)
    if '--cycles' in sys.argv:
        cs = cycles(g)
        print(f'колец: {len(cs)}')
        for c in cs[:20]:
            print('  · ' + ' → '.join(os.path.basename(x) for x in c))
        sys.exit(0 if not cs else 1)
    if '--node' in sys.argv:
        key = sys.argv[sys.argv.index('--node') + 1]
        print(brief(g, key) if '--brief' in sys.argv else path_of(g, key))
        report_unread('узел')
        sys.exit(0)
    report_unread('сборка карты')
    nc, ec = counts(g)
    print(f"узлов: {len(g['nodes'])}  рёбер: {len(g['edges'])}")
    print('  по видам узлов: ' + ', '.join(f'{k} {v}' for k, v in nc.most_common()))
    print('  по видам рёбер: ' + ', '.join(f'{k} {v}' for k, v in ec.most_common()))
    sh = g.get('shared_names') or {}
    if sh:
        top = sorted(sh.items(), key=lambda kv: -len(kv[1]))[:5]
        print(f'  имён без владельца (определены в нескольких файлах): {len(sh)} — '
              + ', '.join(f'{n} ({len(o)})' for n, o in top))
    if '--check' in sys.argv:
        sys.exit(0 if g['nodes'] and g['edges'] else 1)
    with with_lock(DATA):
        json.dump(g, open(DATA, 'w'), ensure_ascii=False)
    print('карта записана:', DATA)
