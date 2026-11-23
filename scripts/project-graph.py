#!/usr/bin/env python3
# project-graph.py — единая карта связей проекта: код И смыслы, в одном графе.
#
# Результат: по любому узлу виден ПОЛНЫЙ путь — на чём он стоит и что стоит на нём,
#            включая тесты, документы, знания, пункты долга и замеры
# Проверка результата: python3 scripts/project-graph.py --check даёт 0 и печатает числа
#            `--check` судит ЦЕЛОСТЬ снимка, а не его непустоту: ребро без конца и повтор id
#            узла — код 1 со списком нарушений (D427); прочие режимы на такой карте отвечают
#            кодом 4 и словом «НЕ ЦЕЛА», а не числом, посчитанным по ребру в никуда
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
import io, json, os, re, subprocess, sys, glob, pathlib, time, tokenize

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

# Что в проекте код и тест, куда класть карту — у владельца `hooks/lib/project_map.py` (спецификация
# project-map-principle, шаг 1б.1); `--repo <путь>` — корень чужого проекта, прежние вызовы его не передают.
# Поиск библиотеки — порядком `hooks/paths-lib.sh:33` (рядом, CLAUDSOUL_ROOT, указатель, установка): песочницы
# тестов копируют только этот файл, а установка получает модуль лишь при переносе.
def _find_lib(name):
    cands = [str(pathlib.Path(__file__).resolve().parent.parent / 'hooks' / 'lib')]
    if os.environ.get('CLAUDSOUL_ROOT'):
        cands.append(os.path.join(os.environ['CLAUDSOUL_ROOT'], 'hooks', 'lib'))
    try:
        with open(os.path.expanduser('~/.claude/claudsoul-repo'), encoding='utf-8') as f:
            cands.append(os.path.join(f.read().strip(), 'hooks', 'lib'))
    except OSError:
        pass
    cands.append(os.path.expanduser('~/.claude/hooks/lib'))
    return next((c for c in cands if os.path.exists(os.path.join(c, name))), cands[-1])


sys.path.insert(0, _find_lib('project_map.py'))
try:
    import project_map  # noqa: E402
except ImportError:
    project_map = None   # запасной путь — прежние правила (см. `_is_mech`, `DATA`); громко при описании и `--repo`
if project_map is None and any(a == '--repo' or a.startswith('--repo=') for a in sys.argv):
    print('project-graph: модуль hooks/lib/project_map.py не найден — --repo без него не исполнить', file=sys.stderr)
    sys.exit(2)
try:
    REPO = (project_map.repo_arg(sys.argv) if project_map else None) or os.environ.get('CLAUDSOUL_REPO') \
        or subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True).stdout.strip()
except project_map.DescriptorError as _e:
    print(f'project-graph: {_e}', file=sys.stderr)
    sys.exit(2)
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
PMAP = None
if project_map is None:
    if os.path.exists(os.path.join(REPO, '.claude-docs', 'project-map.json')):
        print('project-graph: описание проекта есть, а модуля hooks/lib/project_map.py нет — карта не собрана',
              file=sys.stderr)
        sys.exit(2)
else:
    try:
        PMAP = project_map.load(REPO)
    except project_map.DescriptorError as _e:
        print(f'project-graph: {_e} — карта не собрана', file=sys.stderr)
        sys.exit(2)


def _git(*args):
    """git в судимом дереве — у владельца `project_map.git`: программы из настроек чужого проекта не исполняются (D1089).

    Отказ владельца (нет `hooks/paths-lib.sh`) — код 2 с причиной. Без модуля — прежний голый вызов: тогда судится
    только своё дерево (`--repo` и описание без модуля — отказ выше).
    """
    if project_map is None:
        return subprocess.run(['git', '-C', REPO, *args], capture_output=True, text=True)
    try:
        return project_map.git(REPO, *args)
    except project_map.DescriptorError as exc:
        print(f'project-graph: {exc} — карта не собрана', file=sys.stderr)
        sys.exit(2)


def _own_tree():
    """Судимое дерево — то, где лежит этот прибор (ClaudSoul либо песочница теста с его копией), а не чужой проект."""
    return os.path.realpath(REPO) == os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))


def stable_text(path, tries=20):
    """Текст файла, прочитанный ЦЕЛИКОМ (D1101) — правило `backlog_stable_copy`: писатели бэклога кладут файл усечением,
    и чтение посреди записи видит пустой или обрезанный текст; два чтения подряд совпали — текст цельный, иначе повтор."""
    def _read():
        # «Не смог прочитать» — не «пусто» (род B): файл уходит в счётчик непрочитанного, его называет report_unread.
        try:
            return open(path, errors='replace').read()
        except OSError:
            UNREAD.append(os.path.relpath(path, REPO))
            return ''
    a = _read()
    for _ in range(tries):
        b = _read()
        if a == b:
            return b
        time.sleep(0.05)
        a = b
    return a


def mention_matchers(files):
    """Чем текст замера, пункта долга или знания НАЗЫВАЕТ механизм дерева (D1069, корень R3) — {путь: (имя, regex)}.

    Прежде связь давала подстрока имени: `t.sh` находился внутри `knowledge-inject.sh`, а имя, которое в дереве носят
    несколько файлов (`__init__.py`), вешало упоминание на все сразу. Теперь имя совпадает только ЦЕЛЫМ словом, и
    голое имя годится лишь в своём дереве и лишь когда оно в дереве одно; иначе — только путь. В чужом проекте —
    всегда путь: глобальная база знаний и долг пишут о файлах ClaudSoul, и совпадение имени с файлом проекта —
    случай, а не связь. Замер на ClaudSoul: рёбер знаний 622 → 607, пунктов долга 2849 → 2812 (снятое — ложное).
    Первый отбор — подстрока имени (`in`), он дёшев; регулярное выражение судит только кандидатов.
    """
    own = _own_tree()
    names = {}
    for f in files:
        if f.endswith(('.sh', '.py')):
            names.setdefault(os.path.basename(f), []).append(f)
    out = {}
    for b, fs in names.items():
        for f in fs:
            alts = [re.escape(f)] + ([re.escape(b)] if own and len(fs) == 1 else [])
            out[f] = (b, re.compile(r'(?<![\w.\-])(?:' + '|'.join(alts) + r')(?![\w\-])'))
    return out

def code_lines(text, is_py=False):
    """Текст без прозы: строки-комментарии и, у .py, тела тройных кавычек.

    Правило то же, что у владельца рёбер `scripts/dep-index.py` (`code_only`), и повторено
    здесь намеренно: карта читает файлы, которых в учёте нет вовсе (сами тесты), и брать
    ради этого чужой модуль дороже, чем держать семь строк. Расхождение поймает нога
    теста карты, а не молчание.
    """
    # Проза питона — у разборщика (`project_map.py_prose_rows`, D1286), прежний счёт кавычек — только когда разбор не удался.
    prose = getattr(project_map, 'py_prose_rows', lambda t: None)(text) if is_py else None
    out, doc = [], None
    for n, line in enumerate(text.split('\n'), 1):
        st = line.lstrip()
        if prose is not None:
            if n not in prose and not st.startswith('#'):
                out.append(line)
            continue
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


# СЛОВО, ПОСЛЕ КОТОРОГО ЛИТЕРАЛ ЕСТЬ ПРОГРАММА (17 сентября 2026, D428): флаг `-c` голый и в
# связке (`bash -lc`, `bash -euc`), а также `eval` и `trap` — их аргумент исполняется по
# грамматике оболочки. Первая редакция знала только голый `-c`, и все четыре формы, дававшие
# ребро до правки, его теряли (воспроизведено скептиком в песочнице; на живом дереве форм
# `-lc`/`-euc` 0, рёбер через `eval`/`trap` 0). Связка шире предмета намеренно: `grep -Ec 'fn('`
# тоже остаётся кодом — ошибка идёт в сторону большей связности. Цена измерена на копии живого
# дерева (HEAD 4551354): широкая связка против голого `-c` — 0 рёбер разницы, ложных не завела.
_PROGRAM_WORD = r'(?:^|\s)(?:-[A-Za-z]*c|eval|trap)'


def _blank_sh_line(s, carry=False):
    r"""Одна строка оболочки без содержимого кавычек; `$(…)` внутри кавычек остаётся кодом.

    `carry` — прошлая строка кончилась на `-c \`: первый литерал этой строки — программа.
    Возвращает (текст, кончилась ли ЭТА строка на `-c \`).

    НЕПАРНАЯ КАВЫЧКА — СТРОКА ОСТАЁТСЯ КОДОМ ЦЕЛИКОМ (17 сентября 2026, D428, находка скептика).
    Первая редакция при непарной кавычке выбрасывала ХВОСТ строки, и настоящий вызов после
    закрытия многострочного литерала терялся: `' "$f" | fn)`, `}"; fn "$P"`, `echo $'it\'s'; fn`,
    `x=${x//[']/}; fn` — ошибка шла в сторону МЕНЬШЕЙ связности, против объявленного правила.
    Непарная кавычка значит одно: граница литерала лежит на другой строке, и сканер в пределах
    строки не знает, какая половина — текст. Не знает — не судит. То же при глубине вложенности
    `(` за пределом рекурсии: одна враждебная строка не вправе ронять сборку всей карты.
    """
    out, n = [], len(s)
    in_word = False     # идёт слово-программа: `'…'"$LIB"'…'` — одно слово из трёх литералов
    first = carry

    def quoted(i, keep):    # внутри "…": текст выбрасывается, `$(…)` возвращается в код
        while i < n:
            c = s[i]
            if c == '\\' and i + 1 < n:
                if keep:
                    out.append(s[i:i + 2])
                i += 2
                continue
            if c == '"':
                out.append('"')
                return i + 1
            if c == '$' and s[i + 1:i + 2] == '(':
                out.append('$(')
                i = code(i + 2, ')')
                continue
            if keep:
                out.append(c)
            i += 1
        raise ValueError('непарная "')

    def code(i, stop=None):  # вне кавычек; со `stop` — до закрывающей скобки этого уровня
        nonlocal in_word, first
        while i < n:
            c = s[i]
            if c == '\\' and i + 1 < n:
                out.append(s[i:i + 2])
                i += 2
                continue
            if c in '\'"':
                # СТРОКА ПОСЛЕ `-c` — ПРОГРАММА ДЛЯ ДРУГОЙ ОБОЛОЧКИ, а не текст:
                # `bash -c '. lib; fn "$1"'` зовёт fn по-настоящему, и содержимое остаётся.
                program = in_word or first or re.search(_PROGRAM_WORD + r'\s*$', ''.join(out)) is not None
                in_word, first = program, False
                if c == "'":
                    j = s.find("'", i + 1)
                    if j < 0:
                        raise ValueError("непарная '")
                    out.append(s[i:j + 1] if program else "''")
                    i = j + 1
                    continue
                out.append('"')
                i = quoted(i + 1, program)
                continue
            if c == '(':
                out.append(c)
                i = code(i + 1, ')')
                continue
            if c.isspace():
                in_word = False
            out.append(c)
            i += 1
            if stop is not None and c == stop:
                return i
        return i

    carry_out = re.search(_PROGRAM_WORD + r'\s*\\$', s) is not None
    try:
        code(0)
    except (ValueError, RecursionError):
        return s, carry_out
    return ''.join(out), carry_out


def blank_strings(text, is_py=False):
    r"""Текст без содержимого строковых литералов — вход поиска ВЫЗОВОВ по именам функций.

    СТРОКА — НЕ ВЫЗОВ (17 сентября 2026, D428). `print("compute_action(")` и
    `echo "compute_action("` имя НАЗЫВАЮТ, а не зовут, и оба давали ребро «использует» в файл
    определения. Шаблон вызова был верен (D411), неверен был его ВХОД: область «код» обратная
    карта брала у `code_lines`, а та построена под другую роль — упоминание ИМЕНИ ФАЙЛА, где
    литерал есть законная цель (`bash "hooks/x.sh"`, `read_text("install.sh")`). Поэтому снятие
    живёт отдельной функцией и зовётся ТОЛЬКО обратной картой имён: `dep_role`, `touch` и слой
    «тест проверяет тест» судят имена файлов, и снять литералы там значило бы вернуть спайку D406.

    ЧЕМ ЭТО РЕШАЛОСЬ РАНЬШЕ. `executable_part` (`hooks/command-scope-lib.sh`) вырезает содержимое ЛЮБЫХ кавычек вне
    `$(…)` (оставляя кодом слова самой подстановки) — и литерал ПРОГРАММЫ после `-c`/`eval`/`trap` тоже (`bash -c "fn
    arg"` → `bash -c `), а он исполняется: у карты это код (D428; сверено вызовом, D1252). Первая редакция этой функции
    вырезала кавычки целиком, вместе с `$(…)`, и сняла 63 ребра, из них 28 настоящих вызовов `"$(fn "$arg")"`. `shell_text` (`hooks/lib/write_targets.py:48`) кавычек не
    трогает вовсе, его предмет — тела heredoc. Оба остаются владельцами своего (текст КОМАНДЫ хода);
    здесь предмет иной — текст ФАЙЛА, и различие названо, а не умолчано.

    У .py литералы снимает tokenize (строки, докстринги, середины f-строк; выражение `{fn()}`
    внутри f-строки остаётся кодом). У .sh — сканер по кавычкам В ПРЕДЕЛАХ СТРОКИ. Две оговорки
    выведены замером на копии живого дерева, третья — воспроизведением скептика:
    · подстановка `$(…)` внутри двойных кавычек — КОД (слова команды остаются, содержимое её вложенных литералов
      вычищается: `x="$(fn "$arg")"` → `x="$(fn "")"`);
    · строка сразу после слова-программы (`_PROGRAM_WORD`: `-c` голый и в связке, `eval`, `trap`)
      — ПРОГРАММА для оболочки (`bash -c '…fn…'`, `subprocess.run(["bash", "-c", "…fn…"])`),
      включая перенос `-c \` и склейку `'…'"$LIB"'…'`. Держит 15 рёбер, все пятнадцать программы;
    · строка с НЕПАРНОЙ кавычкой остаётся кодом ЦЕЛИКОМ — почему, сказано в `_blank_sh_line`.

    НАЗВАННЫЙ ПРЕДЕЛ: разбирается лексика, а не грамматика. Тело heredoc и литерал оболочки,
    перешедший на следующую строку, остаются кодом — состояние кавычки через строку НЕ несётся
    намеренно: апостроф в прозе тела heredoc открыл бы «литерал» до следующего апострофа и снял
    бы настоящий код ниже, а ошибка здесь обязана идти в сторону БОЛЬШЕЙ связности, как у
    `dep_role`. Цена предела ИЗМЕРЕНА (HEAD 4551354): из 504 рёбер от .sh только на строках тела
    heredoc, у открытия которого интерпретатор не назван, держатся не больше 15; прочитаны все —
    ложных 5 (проза и строка таблицы в теле), настоящих 10, вызовы `$(fn …)` в незакавыченном
    heredoc. Снять тела значило бы потерять вдвое больше, чем убрать. Программу узнают по слову
    перед литералом, а не по имени помощника: вызов, поданный строкой своей функции
    (`run_in "fn arg"`), ребра не даёт, а образец после `grep -c` остаётся кодом. У .py до
    3.12 f-строка — один токен и снимается целиком вместе с `{fn()}`; .py, который tokenize не
    разобрал, возвращается как есть — то есть как до этой функции.
    Условие снятия: у карты появится разбор оболочки вместо шаблона (то же условие, что у предела
    «вызов через переменную» ниже) — тогда heredoc, многострочный литерал и программа-аргумент
    получат роль по грамматике, а не по форме.
    """
    if not is_py:
        out, carry = [], False
        for line in text.split('\n'):
            blanked, carry = _blank_sh_line(line, carry)
            out.append(blanked)
        return '\n'.join(out)
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, SyntaxError):
        return text
    kinds = lambda *names: {getattr(tokenize, x) for x in names if hasattr(tokenize, x)}
    middle = kinds('FSTRING_MIDDLE', 'TSTRING_MIDDLE')
    opens, closes = kinds('FSTRING_START', 'TSTRING_START'), kinds('FSTRING_END', 'TSTRING_END')
    quiet = {tokenize.NL, tokenize.NEWLINE, tokenize.COMMENT, tokenize.INDENT, tokenize.DEDENT}
    drop, prev, program = [], [], False     # prev — два последних значимых токена
    for t in toks:
        if t.type in quiet:
            continue
        if t.type == tokenize.STRING or t.type in opens:
            program = (len(prev) == 2 and prev[1].string == ',' and prev[0].type == tokenize.STRING
                       and re.fullmatch(r'-[A-Za-z]*c', prev[0].string[1:-1]) is not None)
        if (t.type == tokenize.STRING or t.type in middle) and not program:
            drop.append(t)
        if t.type == tokenize.STRING or t.type in closes:
            program = False
        prev = (prev + [t])[-2:]
    lines = text.split('\n')
    for t in reversed(drop):    # с конца: срез не сдвигает ещё не тронутые позиции
        (sr, sc), (er, ec) = t.start, t.end
        if sr == er:
            lines[sr - 1] = lines[sr - 1][:sc] + lines[sr - 1][ec:]
        else:
            lines[sr - 1] = lines[sr - 1][:sc]
            for i in range(sr, er - 1):
                lines[i] = ''
            lines[er - 1] = lines[er - 1][ec:]
    return '\n'.join(lines)


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
    """Файлы дерева — ТОТ ЖЕ перечень, что у учёта: под учётом git плюс новые, не игнорируемые.

    ОДИН УНИВЕРСУМ НА ОБА КОНЦА СВЯЗИ (17 сентября 2026, D429). Карта стоит на связи с учётом
    дважды: читает его строки и сама обходит дерево. Учёт (`tracked()`, `scripts/dep-index.py:53-69`)
    с 28 августа 2026 перечисляет `--cached --others --exclude-standard` с `-z`; здесь стоял голый
    `git ls-files`, и концы расходились молча. Файл до `git add` учёт называл расхождением, а карта
    отвечала «узла в карте нет»; когда же строка учёта уже была, узел рождался из неё, но все
    проходы ниже идут по `files` и его пропускали — ни «использует», ни журналов, ни долга, ни
    знаний (воспроизведено: `scripts/newmech.py` со строкой в учёте и вызовом внутри — 0 рёбер).
    Хук `impact-inject.sh:64` при этом спрашивает карту именно о неотслеживаемых. Порядок действий
    («сперва add, потом карта») не должен менять ответ — довод тот же, что у учёта.
    Замер на копии живого дерева (HEAD 444677f, повторён на 682812c; неотслеживаемых 6, все — документы): узлов
    2275 → 2281, рёбер 6788 → 6788; цена перечня 0,012 → 0,013 с.
    · `-z`: без него git отдаёт не-ASCII путь в кавычках с восьмеричными экранами, такой ключ не
      открывается и с ключом из учёта не совпадает — у одного файла два узла, и обходы не видят
      ни одного (воспроизведено на `hooks/проба.sh`; на живом дереве таких путей 0).
    · `--exclude-standard` обязателен: кэш самой карты игнорируется (`mcp-server/.gitignore:5`) и
      иначе стал бы собственным узлом.
    · `set`: при неразрешённом слиянии индекс называет путь по разу на стадию (замер: 3 строки
      на один конфликтный файл, и без `set` у него 3 одинаковых ребра «использует» вместо 1 —
      нога T34).
    · Запись с косой чертой на конце — каталог ВЛОЖЕННОГО репозитория (так `--others` отдаёт чужой
      `.git`), а не файл: имя у неё пустое, и `touch()` до D430 давал на неё ребро «зовёт» из
      любого файла (`'' in body`). Воспроизведено в песочнице; на живом дереве таких 0.
    НАЗВАННЫЙ ПРЕДЕЛ: правило ПОВТОРЕНО литералом, а не позвано у владельца — у учёта свой резолв
    корня (каталог скрипта, а не `git rev-parse`), и песочницы тестов карты его не копируют.
    Расхождение ловит нога T30 `hooks/tests/test_project_graph.sh`: оба перечня снимаются с ОДНОГО
    дерева и сравниваются множествами — поведением, а не видом строки. Условие снятия: у учёта
    появится режим, отдающий перечень наружу, — тогда карта зовёт владельца, а литерал уходит.
    """
    out = _git('ls-files', '-z', '--cached', '--others', '--exclude-standard').stdout
    # Кэш карты и его замок — не узлы карты (D1068, F1); учёт остаётся узлом-реестром.
    # Запись, за которой на диске каталог (ссылка на каталог, подмодуль), — не файл: то же правило, что у учёта (D1185).
    return sorted(set(f for f in out.split('\0') if f and not f.endswith('/')
                      and not os.path.isdir(os.path.join(REPO, f))
                      and not (PMAP is not None and project_map.is_map_output(PMAP, REPO, f))))

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
    if _is_test_path(path):
        return 'test'          # тесты сервера MCP лежат вне hooks/tests и тоже тесты; правило — владельца (D1068, F7)
    if path.endswith(('.sh', '.py')):
        return 'script'        # любой исполняемый файл дерева, а не только три каталога
    if PMAP is not None and project_map.is_code(PMAP, path):
        return 'script'        # код иных языков по описанию проекта (TS/JS, шаг 1в): не «данные» и не «ресурс»
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
    if PMAP is not None and project_map.is_contract(PMAP, REPO, dep_name):
        kind = contract_kind(src_path, dep_name)
        if kind == 'w':
            cache[key] = 'записывает'
        elif kind == 'n':
            cache[key] = 'называет'
        else:
            cache[key] = 'читает'
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
    # ЛЕНИВЫЙ ИМПОРТ (D1230): `from .readers import text_wrap` ВНУТРИ функции исполняет соседа при вызове, а не при
    # импорте, — кольца импорта он не замыкает (`mcp-server/ingest/parse.py` ↔ читатели). Имя модуля в такой строке
    # стоит без `.py`, поэтому прежде ребро шло в «зовёт» запасным выходом.
    # Попадание-УПОМИНАНИЕ правило не отменяет (скептик D1340, H1): рядом с ленивым импортом имя файла бывает строкой
    # поиска библиотеки (`_find_lib('x.py')`), и ребро уходило в запасной «зовёт». Отменяет его только строка запуска
    # того же файла — тогда исполнение настоящее, и роль решают ветки ниже.
    if src_path.endswith('.py') and dep_name.endswith('.py') and not any(_PY_RUNS.search(l) for l in hits):
        lazy = _py_import_sites(body, os.path.splitext(base)[0])
        if lazy and all(lazy):
            cache[key] = 'подгружает'
            return cache[key]
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
    SAY = re.compile(r'^\s*(?:echo|printf|print|warn|info|error|die)\b(?!\s*=)')   # `info=$(…)` — не сообщение
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
    # ИМЯ В ТЕКСТЕ (D1230): тело heredoc для `cat`/`echo` и хвостовой комментарий — данные, а не вызов (после правила
    # регистрации: строки `"command": …` в heredoc установщика — его предмет). Правило
    # `code_lines` здесь не меняется (его держит равенство с учётом, нога T31): оно снимает только строки-комментарии.
    if not src_path.endswith('.py'):
        code_hits = [l for l in _sh_role_text_free(body, base).split('\n') if base in l]
        if not code_hits:
            cache[key] = 'называет'
            return cache[key]
        hits = code_hits
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
    if any(EXEC.search(l) for l in hits) or (not src_path.endswith('.py') and _sh_runs(hits, base)):
        cache[key] = 'зовёт'
    elif all(SAY.match(l) for l in hits):
        cache[key] = 'называет'
    elif all(READ.search(l) for l in hits):
        cache[key] = 'читает'
    else:
        cache[key] = 'зовёт'
    return cache[key]


_PY_RUNS = re.compile(r'subprocess|runpy|\bexec\s*\(|os\.system|Popen|check_output|check_call|\b(?:python3?|bash|sh)\b')


def _guard_kinds_from_files(g):
    """Вид стража у узлов вида hook выводится из ФАЙЛА при чтении кэша, а не только при его записи (скептик D1340, M1).

    Живой зовущий (`hooks/impact-inject.sh`) делает `--touch` ДО записи нового файла: в этот момент кода ещё нет, и
    узел встаёт видом hook. Значение, снятое до появления владельца факта, держалось до пересборки — у 8 из 18 стражей,
    созданных с 13 сентября 2026. Кэш на диске не меняется: правится ответ читателю. Обратное направление (страж,
    потерявший канал) чтением не снимается — его ведёт `--touch` существующего узла и пересборка.
    """
    if not g:
        return g
    for n in g.get('nodes', []):
        if n.get('type') == 'hook':
            ch = _guard_channel(n.get('key', ''))
            if ch:
                n['type'], n['channel'] = 'guard', ch
    return g


def _guard_channel(key):
    """Канал стража по коду хука — 'отказ', 'вопрос', 'инжект' либо None (обычный хук).

Один владелец для сборки (шаг 6б), для `--touch` и для чтения кэша (D1340): прежде правило жило только в сборке, и
    новый страж, вошедший в карту через `--touch`, числился видом hook без канала до ближайшей пересборки. `--touch`
    до записи файла вида знать не может — его доводит чтение кэша (`_guard_kinds_from_files`).
    """
    try:
        t = open(os.path.join(REPO, key), errors='replace').read()
    except OSError:
        return None
    code = '\n'.join(l for l in t.split('\n') if not l.lstrip().startswith('#'))
    if 'permissionDecision' in code and '"deny"' in code:
        return 'отказ'
    if 'permissionDecision' in code:
        return 'вопрос'
    if 'additionalContext' in code:
        return 'инжект'
    return None


def _sh_runs(lines, base):
    """Хоть одна строка оболочки ЗАПУСКАЕТ файл `base` — по разбору владельца, а не по виду строки (D1340, корень R3).

    Позицию команды называет `calls` (`hooks/lib/write_targets.py`): после `{`, `!`, `then`, `do`, префикса окружения —
    тоже начало команды, а цель снимается разбором кавычек (`bash "$(dirname -- "$0")/x.sh"`). Выражение `EXEC` выше
    знало четыре начала (`^`, `;`, `|`, `&`, `(`, `$(`) и цель без пробелов, поэтому запуск в теле функции и под
    `if !` читался как «читает»: на настоящей карте — `scripts/doc-figures.sh:28` и `scripts/ablation/phase.sh:87`.
    Библиотека ищется тем же порядком, что `project_map` (`_find_lib`): рядом, CLAUDSOUL_ROOT, указатель, установка.
    Нет владельца (песочница, скопировавшая один прибор, без указателя на репозиторий) либо разбор не удался — ответ
    «нет», решает прежнее выражение.
    """
    global _WT
    if _WT is None:
        d = _find_lib('write_targets.py')
        if d not in sys.path:
            sys.path.append(d)   # в конец: каталог `project_map` и замка уже стоят первыми
        try:
            import write_targets
            _WT = write_targets
        except Exception:  # noqa: BLE001
            _WT = False
    if not _WT:
        return False
    for l in lines:
        try:
            if any(os.path.basename(c) == base for c in _WT.calls(l)):
                return True
        except Exception:  # noqa: BLE001
            continue
    return False


_WT = None


_SH_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")
_SH_TOOLWORD = re.compile(r'\b(?:cat|grep|awk|sed|head|tail|wc|jq|eval|source)\b')
_SH_INTERP = re.compile(r'(?:^|[\s;|&(])(?:\S*/)?(?:python3?|bash|sh|zsh|perl|node|ruby|jq|awk|sed)\b')


def _sh_role_text_free(body, base=None):
    """Тело оболочки без ТЕКСТА: строки тел heredoc, чей приёмник не интерпретатор (`cat <<'X'`), и хвостовые комментарии.

    Heredoc для `python3 -`/`bash` (в любой позиции слова: `$(env X=1 python3 - <<'PY'`) — программа, его тело остаётся
    кодом. Строка тела heredoc для `cat` остаётся кодом, если в ней стоит форма исполнения цели `base`
    (`bash|sh|python3|source … имя`): таблица команд, которую цикл потом исполняет (`scripts/probes/R6.sh`), — вызов, а
    не текст. Хвостовой комментарий — `#` в начале слова вне кавычек.
    """
    run = (re.compile(r'(?:bash|sh|zsh|python3?|perl|source|\.)\s+(?:-\S+\s+)*["\']?\S*' + re.escape(base))
           if base else None)
    out, mark = [], None
    for line in body.split('\n'):
        if mark is not None:
            if line.strip() == mark:
                mark = None
            # Строка тела с формой исполнения или чтения цели — команда таблицы, а не проза: её роль судит `dep_role`.
            out.append(line if run is not None and (run.search(line) or _SH_TOOLWORD.search(line)) else '')
            continue
        # Открытие ищется по исходной строке: снятие кавычек съело бы маркер `<<'TXT'`.
        hm = _SH_HEREDOC.search(line) if '<<<' not in line else None
        if hm and hm.start() < _sh_comment_at(line) and not _SH_INTERP.search(line[:hm.start()]):
            mark = hm.group(2)
        out.append(line[:_sh_comment_at(line)])
    return '\n'.join(out)


def _sh_comment_at(line):
    """Позиция хвостового комментария (`#` в начале слова вне кавычек) либо длина строки."""
    q = None
    for i, c in enumerate(line):
        if q:
            if c == q:
                q = None
            elif c == '\\' and q == '"':
                continue
        elif c in '\'"':
            q = c
        elif c == '#' and (i == 0 or line[i - 1].isspace()):
            return i
    return len(line)


def _py_import_sites(body, stem):
    """Места импорта модуля `stem` в теле питона: True — внутри `def` (ленивый), False — на уровне модуля."""
    imp = re.compile(r'^\s*(?:from\s+\S*\b' + re.escape(stem) + r'\b\S*\s+import\b|import\s+(?:\S+\s*,\s*)*\S*\b'
                     + re.escape(stem) + r'\b|from\s+\S+\s+import\s+.*\b' + re.escape(stem) + r'\b)')
    sites, defs = [], []
    for line in body.split('\n'):
        if not line.strip():
            continue
        ind = len(line) - len(line.lstrip())
        while defs and ind <= defs[-1]:
            defs.pop()
        if re.match(r'\s*(?:async\s+)?def\s', line):
            defs.append(ind)
            continue
        if imp.match(line):
            sites.append(bool(defs))
    return sites


# РЕЖИМ ВЫЗОВА (D1230). `commit-trap.sh` зовёт `merge-root-gate.sh --judge-commit`, а тот зовёт `commit-trap.sh` только
# под охраной `if [ "${1:-}" = "--install" ]` — рекурсии нет, хотя рёбра в обе стороны. Спайка исполнения поэтому
# проверяется на графе СОСТОЯНИЙ (файл, режим прибытия): ребро из места под охраной режима проходимо, только если
# прибыли в этом режиме. Режим прибытия — первый ЛИТЕРАЛЬНЫЙ аргумент после имени цели (`--x`, `install`); `"$@"` и
# подключение (`source`, `.`) передают прибывший; переменная, подстановка и неузнанное место — «любой режим» (`*`);
# вызов без аргумента приходит без режима (`''`), и охраняемое место из него недостижимо. Вход извне — любой режим.
# ОШИБКА — ТОЛЬКО В СТОРОНУ БОЛЬШЕЙ СВЯЗНОСТИ (скептик opus по 86b1d5bb, H1): первая редакция давала неузнанному месту
# «пришёл без режима» и снимала восемь форм настоящих рекурсий. Теперь всё, чего разбор не понял, — «любой режим» либо
# «неохраняемое»: охрана — только `if [ "${1:-}" = "X" ]` (и `"$1"`, `[[ … == … ]]`) без `||`/`-o`, ветка `case "${1:-}" in`
# с литеральными метками; тела heredoc в разбор охраны не идут; кадры, не сошедшиеся к концу файла, обесценивают охрану
# всего файла.
# НАЗВАННЫЙ ПРЕДЕЛ: охрана по `$1` ФУНКЦИИ (`f() { if [ "$1" = --x ]; …; }; f --x`) читается как охрана файла — частота
# в дереве 0; условие снятия — первая такая охрана у места вызова.
_MODE_GUARD = re.compile(r'^\s*(?:el)?if\s+\[\[?\s*"?\$\{?1(?::-)?\}?"?\s*==?\s*["\']?([A-Za-z0-9_][\w.-]*|--?[A-Za-z][\w-]*)["\']?\s*\]\]?')
_ARG_CASE = re.compile(r'^\s*case\s+"?\$\{?1(?::-)?\}?"?\s+in\b')


def _strip_heredocs(lines):
    """Строки оболочки без тел ЛЮБЫХ heredoc (их `if`/`fi` — чужой язык или текст, кадрам охраны они не принадлежат)."""
    out, mark = [], None
    for line in lines:
        if mark is not None:
            if line.strip() == mark:
                mark = None
            out.append('')
            continue
        hm = _SH_HEREDOC.search(line) if '<<<' not in line else None
        if hm and hm.start() < _sh_comment_at(line):
            mark = hm.group(2)
        out.append(line)
    return out


def _call_sites(src_path, base):
    """[(охрана, режим)] мест ИСПОЛНЕНИЯ `base` в оболочечном файле.

    Охрана — множество режимов, в которых место достижимо, либо None. Режим — первый литеральный аргумент после имени
    цели; `@` — передаёт прибывший (`"$@"`, `source`); `*` — любой (переменная, подстановка, место не узнано); `''` — без
    аргумента. Место — строка, где файл исполняется (`bash|sh|zsh|source|.` либо путь в позиции команды); проверка
    `[ -f … ]` и текст подсказки вызовом не являются. Не узнано ни одного места — `[(None, '*')]`.
    """
    try:
        raw = open(os.path.join(REPO, src_path), errors='replace').read()
    except OSError:
        return [(None, '*')]
    call = re.compile(r'(?:^|[;|&({]|\$\(|\b(?:exec|then|do|else))\s*(?:exec\s+)?(?:(bash|sh|zsh|source|\.)\s+(?:-\w+\s+)*)?'
                      r'"?[^"\s;|&]*' + re.escape(base) + r'["\']?(?=\s|$|;|\)|&|\|)')
    lines = _strip_heredocs(_sh_role_text_free(code_lines(raw, False)).split('\n'))
    sites, stack, broken = [], [], False
    for line in lines:
        st = line.strip()
        if re.match(r'(?:el)?if\b', st) and not re.search(r'\bfi\b', st):
            gm = _MODE_GUARD.match(line)
            # Составная охрана (`… ] || [ … ]`, `-o`) — не охрана: в место приходят и без этого режима.
            frame = {'kind': 'if', 'mode': {gm.group(1)} if gm and not re.search(r'\|\||\s-o\s', st) else None}
            if st.startswith('elif') and stack and stack[-1]['kind'] == 'if':
                stack[-1] = frame
            else:
                stack.append(frame)
        elif re.match(r'else\b', st) and stack and stack[-1]['kind'] == 'if':
            stack[-1] = {'kind': 'if', 'mode': None}
        elif re.match(r'fi\b', st):
            if stack and stack[-1]['kind'] == 'if':
                stack.pop()
            else:
                broken = True
        elif re.match(r'case\b', st) and not re.search(r'\besac\b', st):
            stack.append({'kind': 'case', 'arg': bool(_ARG_CASE.match(line)), 'mode': None})
        elif re.match(r'esac\b', st):
            if stack and stack[-1]['kind'] == 'case':
                stack.pop()
            else:
                broken = True
        elif stack and stack[-1]['kind'] == 'case' and stack[-1]['arg']:
            lm = re.match(r'\s*\(?([^\s()]+(?:\s*\|\s*[^\s()]+)*)\)', line)
            if lm:
                labels = [x.strip().strip('"\'') for x in lm.group(1).split('|')]
                literal = all(re.fullmatch(r'[\w.-]+|--?[A-Za-z][\w-]*', x) for x in labels)
                stack[-1]['mode'] = set(labels) if literal and labels else None
        cm = call.search(line) if base in line else None
        if cm:
            guard = next((f['mode'] for f in reversed(stack) if f['mode']), None)
            one = _MODE_GUARD.match(line) if re.search(r'\bfi\b', st) else None
            if one and not re.search(r'\|\||\s-o\s', st):
                guard = {one.group(1)}
            if cm.group(1) in ('source', '.'):
                mode = '@'     # подключённый файл видит `$1` вызывающего
            else:
                rest = line[cm.end():].lstrip('"\'')
                am = re.match(r'\s+(\S+)', rest)
                tok = am.group(1).strip('"\'') if am else ''
                if not tok or tok[0] in ';|&)<>#':
                    mode = ''
                elif tok in ('$@', '${@}'):
                    mode = '@'
                elif re.fullmatch(r'[\w.-]+|--?[A-Za-z][\w-]*', tok):
                    mode = tok
                else:
                    mode = '*'
            sites.append((frozenset(guard) if guard else None, mode))
        if ';;' in line and stack and stack[-1]['kind'] == 'case':
            stack[-1]['mode'] = None
    if broken or stack:
        # Кадры не сошлись (многострочный литерал с `if`, иной язык вне heredoc): охране файла не верим.
        sites = [(None, m) for _g, m in sites]
    return sites or [(None, '*')]


def refine_by_mode(comps, g):
    """Куски, где рекурсия достижима с учётом режимов вызова; прочие рассыпаются."""
    key = {n['id']: n.get('key') or n.get('name') for n in g['nodes']}
    out = []
    for comp in comps:
        cs = set(comp)
        adj = {}
        for e in g['edges']:
            if e['source'] in cs and e['target'] in cs and e['type'].startswith(('зовёт', 'использует', 'пишет',
                                                                                 'читает', 'проверяет')):
                adj.setdefault(e['source'], set()).add(e['target'])
        sites = {}
        for u, vs in adj.items():
            for v in vs:
                ku, kv = key.get(u) or '', key.get(v) or ''
                sites[(u, v)] = (_call_sites(ku, os.path.basename(kv)) if ku.endswith('.sh') and kv.endswith('.sh')
                                 else [(None, '')])
        # Состояния (узел, режим прибытия); вход извне — «*».
        sadj, seen, work = {}, set(), [(u, '*') for u in cs]
        while work:
            st = work.pop()
            if st in seen:
                continue
            seen.add(st)
            u, a = st
            for v in adj.get(u, ()):
                for gd, md in sites[(u, v)]:
                    if gd is not None and a != '*' and a not in gd:
                        continue
                    nxt = (v, a if md == '@' else md)
                    sadj.setdefault(st, set()).add(nxt)
                    work.append(nxt)
        sub, _ = sccs({'edges': [{'source': x, 'target': y, 'type': 'зовёт'} for x, ys in sadj.items() for y in ys]})
        groups = []
        for c in sub:
            nodes = {x[0] for x in c}
            if len(nodes) < 2:
                continue
            for grp in groups:
                if grp & nodes:
                    grp |= nodes
                    break
            else:
                groups.append(set(nodes))
        out.extend(sorted(grp) for grp in groups)
    out.sort(key=len, reverse=True)
    return out


# КЛАСС РЁБЕР ЗАВИСИМОСТИ — всё множество значений `dep_role`, объявленное ОДИН раз (17 сентября
# 2026, D430). Его читает `touch`: исходящие рёбра файла именно этого класса он считает заново.
# Новая роль в `dep_role` вносится и сюда — иначе `touch` её не снимет, и прежнее ребро останется
# рядом с новым. Это ВТОРОЕ объявление одного множества, и держит его не этот текст, а нога T35b
# `hooks/tests/test_project_graph.sh`: литералы `cache[key] = '<роль>'` в `dep_role` против этого
# кортежа (находка скептика: без сверки здесь стояло то же устройство R5, которое пункт лечит).
# НАЗВАННЫЙ ПРЕДЕЛ: сверка по форме строки — роль, возвращённая иначе, ей не видна; пустой улов она
# считает отказом рамки. Условие снятия: `dep_role` станет брать значения из этого кортежа.
DEP_ROLES = ('зовёт', 'читает', 'называет', 'устанавливает', 'записывает', 'подгружает')

# `mv`/`cp`/`install` — командным словом строки или после `;`, `&&`, `||`, `then`/`else`/`do` (`… > "$t" && mv "$t" "$MD"`,
# `scripts/count-stats.sh:137`, D1075 F4); аргументы до пути разделителя команды не пересекают. Запись — только в
# ПОСЛЕДНИЙ аргумент (`_LAST_ARG` судит хвост строки за путём): источник с флагом (`cp -f "$N" "$S"`) — чтение (H1
# скептика 04481f5a); источник `mv` — тоже чтение, как было. У `shutil.copy*`/`shutil.move`/`os.replace` запись — второй
# аргумент (`_py_dst`). `sed -i` правит файл на месте.
_WRITE_PRE = re.compile(r'>>?\s*["\']?$|\btee\s+(?:-a\s+)?["\']?$|\bsed\b[^;&|]*\s-[A-Za-z]*i\S*\s[^;&|]*$')
_CP_PRE = re.compile(r'(?:^|[;&|(]|\b(?:then|else|do)\b)\s*(?:mv|cp|install)\s[^;&|]*\S\s+["\']?$')
_LAST_ARG = re.compile(r'["\']?\s*(?:$|[;&|)]|\d*>)')
_PY_MOVE = re.compile(r'(?:os\.replace|shutil\.(?:move|copy\w*))\(')
# Сравнение `[ "$x" = "$N" ]` — только у оболочки: в Python `path = INDEX` — присваивание (M2 скептика 04481f5a).
_NAME_PRE = re.compile(r'`$|(?:==|!=)\s*["\']?$|exclude[^\s]*\s*["\']?$')
_SH_CMP = re.compile(r'\s=\s*["\']?$')
# Слово сообщения — командой, а не именем переменной (`info=$(stat "$N")` — чтение; находка второго круга D1075).
_SAY = re.compile(r'^\s*(?:echo|printf|print|warn|info|error|die)\b(?!\s*=)')
# ПУТЬ ПРИСВОЕН ПЕРЕМЕННОЙ (D1075, F4): строка с путём действия не несёт, роль решают места, где переменная используется.
# Оболочка — `N=`, `N="`, `N="${E:-` после начала строки, разделителя, `(`, `)` ветки `case`, `{` или
# `then`/`else`/`do`/`local`/`export`…, и `${N:=` (`: "${N:=…}"`); Python — `N = ` перед путём, `os.path.join(`,
# f-строкой или `Path(`, в том числе внутри `os.path.abspath(`, `str(` (L3 скептика 04481f5a).
_BIND_SH = re.compile(r'(?:(?:^\s*|[;&|(){]\s*|\b(?:then|else|do|local|export|readonly|declare|typeset)(?:\s+-\w+)*\s+)'
                      r'([A-Za-z_]\w*)=["\']?(?:\$\{\w+:?[-=]["\']?)?|\$\{([A-Za-z_]\w*):?=)$')
_BIND_PY = re.compile(r'^\s*([A-Za-z_]\w*)\s*(?::[^=]*)?=\s*(?:(?:os\.path\.\w+|str|(?:pathlib\.)?Path)\(\s*)*'
                      r'(?:os\.path\.|f?["\']|(?:pathlib\.)?Path\(\s*)?$')


def _py_dst(pre):
    """Путь стоит вторым (или дальше) аргументом последнего `shutil.copy*(`/`move(`/`os.replace(` в `pre` — назначение."""
    m = None
    for m in _PY_MOVE.finditer(pre):
        pass
    if m is None:
        return False
    depth, commas = 0, 0
    for ch in pre[m.end():]:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
            if depth < 0:
                return False   # вызов закрыт до пути
        elif ch == ',' and depth == 0:
            commas += 1
    return commas > 0


def _ref_kind(line, s, e, is_py=False):
    """'w' / 'n' / 'r' одного места пути (или переменной с путём) в строке: запись, имя, иначе чтение."""
    pre, post = line[:s], line[e:]
    if _WRITE_PRE.search(pre) or (_CP_PRE.search(pre) and _LAST_ARG.match(post)) or _py_dst(pre) \
            or re.match(r'["\']?\)?\s*\.(?:write_(?:text|bytes)\(|open\(\s*["\'][wax])', post) \
            or (re.search(r'open\(\s*[^,()]*$', pre) and re.match(r'[^)]*,\s*["\'][wax]', post)):
        return 'w'
    if _SAY.match(line) or _NAME_PRE.search(pre) or (not is_py and _SH_CMP.search(pre)) or _in_prose(line, s) \
            or (re.match(r'[*]?(?:\|[^)]*)?\)', post) and re.search(r'(?:^\s*|\bin\s+)[\w*|./"\'-]*$', pre)) \
            or re.match(r'["\']\s*:(?![:=])', post):  # ключ словаря (F5)
        return 'n'
    return 'r'


def _var_uses(lines, var, is_py):
    """Места, где переменная с путём используется ЦЕЛИКОМ: `$N`, `${N}`, `${N:-…}`, `${N:?}` (у Python — имя вне присваивания).

    `${N%/*}/…`, `${N#…}` — производный путь, а не сам файл (`${BACKLOG_FILE%/*}/BACKLOG-archive.md`), — не использование;
    так же слово, продолженное за именем (`"$N.lock"`, `$N.bak`), и у Python `N + ".lock"` (M1 скептика 04481f5a).
    """
    rx = re.compile(r'(?<![\w.])' + var + r'(?!\w)(?!\s*=(?!=))(?!\s*\+)') if is_py \
        else re.compile(r'\$(?:\{' + var + r'(?::?[-=?]|\}(?=["\'\s;&|()<>`]|$))|' + var + r'(?=["\'\s;&|()<>`}]|$))')
    return [(j, m.start(), m.end()) for j, l in enumerate(lines) for m in rx.finditer(l)]


def _py_continued(lines):
    """Номера строк Python, начинающихся внутри открытой скобки прошлых строк (продолжение вызова, M3 скептика 04481f5a)."""
    out, depth = set(), 0
    for i, l in enumerate(lines):
        if depth > 0:
            out.add(i)
        l = re.sub(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|#.*', '', l)
        depth = max(0, depth + sum(l.count(c) for c in '([{') - sum(l.count(c) for c in ')]}'))
    return out


def _in_prose(line, s):
    """Путь стоит внутри строки-прозы: в кавычках, где после свёртки `${…}` и `$(…)` остаются пробелы."""
    q, qs, i = None, -1, 0
    while i < s:
        ch = line[i]
        if ch == '\\':
            i += 2
            continue
        if q is None and ch in '"\'':
            q, qs = ch, i
        elif ch == q:
            q = None
        i += 1
    if q is None:
        return False
    qe = line.find(q, s)
    seg = line[qs + 1:qe if qe >= 0 else len(line)]
    prev = None
    while prev != seg:
        prev, seg = seg, re.sub(r'\$\{[^{}]*\}|\$\([^()]*\)', 'X', seg)
    return bool(re.search(r'\s', seg))


def contract_kind(src_path, dep_name):
    """Вид ребра к файлу-договору: 'w' — записывает, 'n' — называет, 'r' — читает; «зовёт» никогда (шаг 1б.2, урок F4/F5).

    Роль по виду присваивает `dep_role` — литералами, которые сверяет нога T35b с `DEP_ROLES`.

    Строки берутся у владельца правила `project_map.contract_refs` — те же, по которым учёт поставил ребро. Запись
    (переадресация, `tee`, `sed -i`, последний аргумент `mv`/`cp`/`install`, второй — `os.replace`/`shutil.copy*`/
    `shutil.move`, `open(…, 'w')`, `.open('w')`, `.write_text`) на любой из строк — «записывает»; все строки — сообщение,
    проза в кавычках, образец `case`, сравнение, исключение или ключ словаря — «называет»; иначе «читает». Путь,
    присвоенный переменной, судится местами, где она используется (`_var_uses`), — один шаг (D1075, F4).
    НАЗВАННЫЕ ПРЕДЕЛЫ (решение владельца 30 октября 2026 — запись через программу пределом, а не разбором): шаг один и
    без учёта порядка — переменная, переданная программе (`python3 - "$N"` и запись через `sys.argv`, `env N=… python3 -`
    и `os.environ`, функция, дочерний процесс через `export`), видна как чтение (на дереве 30 октября 2026 — три ребра:
    `scripts/backlog-archive.sh` → `BACKLOG.md` и `BACKLOG-archive.md`, `scripts/backlog-refresh-readings.sh` →
    `BACKLOG.md`); одноимённая переменная другой функции и переприсвоенная до записи считаются той же; источник `mv`
    (файл уходит) — чтение; `cp -t <каталог> <источник>` — запись в источник; путь из ключа словаря, по которому идёт
    цикл чтения (`for p in LOADERS: open(p)`), — «называет» (L7 скептика 04481f5a).
    """
    is_py = src_path.endswith('.py')
    try:
        body = code_lines(open(os.path.join(REPO, src_path), errors='replace').read(), is_py)
    except OSError:
        UNREAD.append(src_path)
        return 'r'
    lines = body.split('\n')
    hits = project_map.contract_refs(PMAP, body, {dep_name}).get(dep_name, [])
    if not hits:
        return 'r'
    kinds, cont = [], None
    for i, s, e in hits:
        bound = (_BIND_PY if is_py else _BIND_SH).search(lines[i][:s])
        if bound and is_py:
            cont = _py_continued(lines) if cont is None else cont
            bound = None if i in cont else bound
        if bound:
            name = bound.group(1) or (None if is_py else bound.group(2))
            kinds += [_ref_kind(lines[j], us, ue, is_py) for j, us, ue in _var_uses(lines, name, is_py)] or ['r']
        else:
            kinds.append(_ref_kind(lines[i], s, e, is_py))
    return 'w' if 'w' in kinds else 'n' if all(k == 'n' for k in kinds) else 'r'

_MECH_SKIP = re.compile(r'(^|/)tests?/|^templates/|^scripts/publish/|__init__\.py$')   # запасной путь без модуля
_TEST_RE = re.compile(r'(^|/)tests?/')


def _is_mech(p):
    if PMAP is None:
        return p.endswith(('.sh', '.py')) and not _MECH_SKIP.search(p)
    return project_map.is_code(PMAP, p)


def _is_test_path(p):
    return bool(_TEST_RE.search(p)) if PMAP is None else project_map.is_test(PMAP, p)


def body_deps(rel, body, keys):
    """Зависимости ОДНОГО файла по его телу — то, что учёт записал бы ему в колонку `deps`.

    ИНКРЕМЕНТ ОБЯЗАН РАВНЯТЬСЯ ПОЛНОЙ СБОРКЕ НА ТОМ ЖЕ ФАЙЛЕ (17 сентября 2026, D430). У полной
    сборки рёбра зависимости приходят из учёта (`deps_of`, `scripts/dep-index.py:165-187`), а
    `touch` с 13 сентября держал своё правило — «имя любого узла с `/` стоит в теле подстрокой» —
    и расходился с владельцем молча. Замер на копии живого дерева (HEAD 7f7adf0, узлов 2074):
    · у 256 механизмов сборка даёт 523 ребра зависимости, прежнее правило — 927: лишних целей 415
      (документы, тесты, данные; `lib.sh` внутри `mylib.sh`), потерянных 11 (все — в файлы корня
      дерева, `install.sh`: фильтр `'/' in key`), а из 512 общих у 211 роль не «зовёт»;
    · у 588 тестов и 253 документов сборка рёбер этого класса не даёт ВОВСЕ (у неё там
      «проверяет» и «описывает»), прежнее правило дало бы 2448 и 3193 ребра «зовёт» — документ
      «звал» бы скрипт, а хук правки вносит в карту именно новые `.sh`, `.py` и `.md`.
    Поэтому здесь правило владельца: источник и цель — МЕХАНИЗМЫ (`.sh`/`.py` вне тестов, шаблонов
    и конфига публикации), имя ищется ТОКЕНОМ `имя.sh|py`, одноимённые разводятся путём, а голое
    неоднозначное имя не засчитывается никому.
    НАЗВАННЫЙ ПРЕДЕЛ: правило ПОВТОРЕНО литералом, а не позвано у владельца, — довод тот же, что у
    `tracked_files`: песочницы тестов карты и проба пункта учёт не копируют, а без него `touch`
    обязан работать. На живом дереве признак механизма совпал со строками учёта: 256 и 256,
    разность 0. Расхождение ловит нога T35: после `dep-index.py --all` и `--refresh` каждый файл
    песочницы проходит `--touch`, и рёбра ВСЕЙ карты обязаны остаться теми же — сверка поведением,
    а не видом строки. Условие снятия: у учёта появится режим «зависимости одного файла» наружу —
    тогда карта зовёт владельца, а литерал уходит.
    """
    if not _is_mech(rel):
        return []
    by_name = {}
    for k in keys:
        if k != rel and _is_mech(k):
            by_name.setdefault(os.path.basename(k), []).append(k)
    found = set()
    for name in set(re.findall(r'([A-Za-z0-9_-]+\.(?:sh|py))', body)):
        cands = by_name.get(name, [])
        found.update([k for k in cands if k in body] or (cands if len(cands) == 1 else []))
    # Файлы-договоры — правилом владельца `project_map.contract_refs`, тем же, что зовёт учёт (шаг 1б.2): литерала
    # здесь нет, инкремент равен сборке по построению.
    if PMAP is not None:
        found.update(project_map.contract_refs(PMAP, body, {k for k in keys
                                                            if project_map.is_contract(PMAP, REPO, k)}))
        # Импорты — правилом владельца `project_map.import_refs` на том же теле и той же вселенной (файлы языков кода),
        # что у учёта (шаг 1в): инкремент равен сборке по построению.
        universe = {k for k in keys if project_map.lang_of(PMAP, k)}
        found.update(t for t in project_map.import_refs(PMAP, REPO, rel, body, universe) if _is_mech(t))
    return sorted(found)


# ИСХОДЯЩИЕ РЁБРА, КОТОРЫЕ `touch` СЧИТАЕТ ЗАНОВО (17 сентября 2026, D430): класс зависимости плюс
# «проверяет» у теста и «описывает» у документа. Оба типа рождаются в `build()` только на шагах 2 и
# 3б, и оба шага здесь повторены — поэтому снять и пересчитать их можно без потери знания.
TOUCH_TYPES = DEP_ROLES + ('проверяет', 'описывает')

_DOC_SKIP = re.compile(
    r'_drafts/|^knowledge/|(^|/)(CHANGELOG|CHANGELOG-archive|SESSION|BACKLOG|BACKLOG-archive)\.md$'
    r'|-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\.md$')
_ARCHIVE_RE = re.compile(r'-archive(-[dD][0-9]+)?\.md$')
_SNAPSHOT_MARK = '<!-- doc-kind: snapshot -->'


def body_mentions(rel, raw, keys):
    """Кого ОДИН тест проверяет либо ОДИН документ описывает: (тип ребра, цели) — то, что учёт
    записал бы названным механизмам в колонки `tests` и `docs`.

    БЕЗ ЭТОГО ПОЧИНКА D430 БЫЛА РЕГРЕССИЕЙ (17 сентября 2026, находка скептика). Прежний `touch`
    писал тесту и документу «зовёт» по подстроке; метка была неверна, но ПАРА часто верна, а
    `--node <механизм> --brief` считает входящих по виду УЗЛА — и новый тест был виден у своего
    механизма сразу. Замер на копии живого дерева: из 2448 таких рёбер у тестов верных пар 1091
    (88% от 1243 рёбер «проверяет» сборки), у документов 582 (55% от 1058). Первая редакция D430
    эти рёбра просто перестала давать, а тесты и документы — 841 файл из 1100, то есть 76% входов
    режима: слово владельца «при создании новое должно попадать в карту» переставало исполняться
    ровно для них. Теперь на той же паре стоит метка владельца и пара считается ЕГО правилом.
    Правило — `mentions` (`scripts/dep-index.py:228-268`) на корпусах `tests()` и `documents()`:
    · тест — `.sh`/`.py` под `test/`|`tests/`, текст — строки КОДА; документ — `.md` вне хроники
      (`DOC_SKIP`), не архив по имени и не снимок по пометке в первых восьми строках, текст сырой;
    · составное имя (дефис, подчёркивание) засчитывается и голым, односложное — только с
      расширением, путём (`каталог/имя`) либо в обратных кавычках;
    · имя, которое носят несколько механизмов, засчитывается только ПУТЁМ.
    Замер правила на той же копии: у 1100 файлов из 1100 цели равны рёбрам сборки, 2301 против 2301.
    НАЗВАННЫЙ ПРЕДЕЛ тот же, что у `body_deps`: правило ПОВТОРЕНО литералом, сверка — нога T35
    (у каждой клаузы в её песочнице свой файл-свидетель). Условие снятия: учёт станет отдавать
    упоминания одного файла наружу — тогда карта зовёт владельца.
    """
    is_test = rel.endswith(('.sh', '.py')) and _is_test_path(rel)
    is_doc = (rel.endswith('.md') and not _DOC_SKIP.search(rel)
              and not _ARCHIVE_RE.search(os.path.basename(rel))
              and _SNAPSHOT_MARK not in '\n'.join(raw.splitlines()[:8]))
    if not (is_test or is_doc):
        return None, []
    text = code_lines(raw, rel.endswith('.py')) if is_test else raw
    mechs = [k for k in keys if _is_mech(k)]
    names = [os.path.basename(m) for m in mechs]
    found = []
    for m, name in zip(mechs, names):
        stem, _, ext = name.rpartition('.')
        bare = r'(?<![A-Za-z0-9_-])' + re.escape(stem)
        if names.count(name) > 1:
            rx = re.escape(m)
        elif '-' in stem or '_' in stem:
            rx = bare + r'(?![A-Za-z0-9_-])'
        else:
            rx = (r'(?:' + bare + re.escape('.' + ext) + r'|(?<![A-Za-z0-9_-])[A-Za-z0-9_.-]+/'
                  + re.escape(stem) + r'(?![A-Za-z0-9_-])|`' + re.escape(stem) + r'`)')
        if re.search(rx, text):
            found.append(m)
    return ('проверяет' if is_test else 'описывает'), sorted(found)


# СВЯЗЬ «ТЕСТ ПРОВЕРЯЕТ ТЕСТ» (шаг 3б сборки) — ОДНО правило на сборку и на `touch` (17 сентября
# 2026, D430): вынесено из тела `build()` дословно, чтобы инкремент не заводил ему копию.
def _is_test_file(f):
    """Тест, чей текст читается построчно как код шелла или питона (рёбра «тест → тест», `touch`). «Тест ли» — у
    владельца, описания проекта (`_is_test_path`), а не своей формой `/tests/` пути (D1265): у blalb шелл-тесты лежат в
    `Tests/adversary/` — описанием они тесты, формой не были, и рёбер «тест → тест» не получали."""
    return f.endswith(('.sh', '.py')) and _is_test_path(f)


def unique_tests(paths):
    """Имя теста → путь, только для имён с ЕДИНСТВЕННЫМ путём (D429, нога T32)."""
    tf_paths = {}
    for t in paths:
        if _is_test_file(t):
            tf_paths.setdefault(os.path.basename(t), []).append(t)
    return {n: ps[0] for n, ps in tf_paths.items() if len(ps) == 1}


def test_targets(t, body, tf_by_name):
    return [opath for other, opath in tf_by_name.items() if opath != t and other in body]


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
    file_set = set(files)
    for r in rows:
        src = nid(r['path'], node_kind(r['path']) or 'mechanism', os.path.basename(r['path']))
        for dep in filter(None, r['deps'].split(',')):
            # Договор, которого в дереве уже нет, узла не рождает, даже если строка учёта отстала (F2 D1067).
            if dep not in file_set and PMAP is not None and project_map.is_contract(PMAP, REPO, dep):
                continue
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
                    # И БЕЗ СТРОКОВЫХ ЛИТЕРАЛОВ (17 сентября 2026, D428): имя внутри строки названо,
                    # а не вызвано. Литералы снимаются с СЫРОГО текста и раньше `code_lines`:
                    # tokenize обязан видеть исходник целым, а не уже прореженным. Только здесь —
                    # почему не в `code_lines` для всех, сказано в `blank_strings`.
                    is_py = f.endswith('.py')
                    text = code_lines(blank_strings(
                        open(os.path.join(REPO, f), errors='replace').read(), is_py), is_py)
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
    test_files = [f for f in files if _is_test_file(f)]
    # ИМЯ ТЕСТА С ДВУМЯ ПУТЯМИ ПРЕДМЕТА НЕ ИМЕЕТ (17 сентября 2026, D429, находка скептика) — то
    # же правило, что у имён функций выше. Прежний словарь `{имя: путь}` молча отдавал имя
    # ПОСЛЕДНЕМУ пути по сортировке. Пока перечень был индексом git, повторов не было (замер живого
    # дерева: 0 среди тестов), а с неотслеживаемыми в перечне черновая копия `zz/tests/test_a.sh`
    # уводила на себя ребро «проверяет» настоящего `hooks/tests/test_a.sh` (воспроизведено: входящих
    # у настоящего 1 → 0, ребро стояло на копии). Теперь такое имя ребра не даёт никому.
    # НАЗВАННЫЙ ПРЕДЕЛ: пока копия лежит в дереве, настоящее ребро тоже молчит — молчание вместо
    # лжи; «предпочесть отслеживаемый» вернуло бы в карту зависимость ответа от `git add`, которую
    # D429 и снимал. Условие снятия: связь теста с тестом станет читаться по ПУТИ в тексте, а не
    # по имени файла. Нога T32 `hooks/tests/test_project_graph.sh`.
    tf_by_name = unique_tests(test_files)
    for t in test_files:
        try:
            body = code_lines(open(os.path.join(REPO, t), errors='replace').read(), t.endswith('.py'))
        except OSError:
            continue
        for opath in test_targets(t, body, tf_by_name):
            edges.append({'source': nid(t, 'test', os.path.basename(t)),
                          'target': nid(opath, 'test', os.path.basename(opath)),
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

    MENTION = mention_matchers(files)

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
            for f, (b, rx) in MENTION.items():
                if b in p[2] and rx.search(p[2]):
                    edges.append({'source': mid, 'target': nid(f, node_kind(f) or 'mechanism', os.path.basename(f)), 'type': 'мерит', 'strength': 2})

    # 5. Смысловой слой: пункты долга
    for bl in ('BACKLOG.md', 'BACKLOG-archive.md'):
        bp = os.path.join(REPO, bl)
        if not os.path.exists(bp):
            continue
        cur = None
        for line in stable_text(bp).splitlines(True):
            m = re.search(r'\*\*(D\d+)\*\*', line)
            if m:
                cur = m.group(1)
                nid('пункт:' + cur, 'backlog', cur)
            if cur:
                for f, (b, rx) in MENTION.items():
                    if b in line and rx.search(line):
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
        for f, (b, rx) in MENTION.items():
            if b in txt and rx.search(txt):
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
        ch = _guard_channel(n['key'])
        if ch:
            n['type'], n['channel'] = 'guard', ch

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
    # Реестр родов — ИСПОЛНЯЕМЫЙ файл судимого дерева, и зовётся он только у своего дерева (того, где лежит этот
    # прибор): в чужом проекте (`--repo`, шаг 1г) файл с тем же именем — его код, а не реестр владельца (D1089, D516).
    reg = os.path.join(REPO, 'scripts', 'defect-class-carriers.py')
    if os.path.exists(reg) and _own_tree():
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
                for f, (b, rx) in MENTION.items():
                    if b in line and rx.search(line):
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
            # Запись через переменную (D1003): путь журнала присвоен имени, а `>`/`>>` стоит перед
            # `$имя`. Замер на дереве 19 октября 2026: 21 ребро «читает» стало «пишет», за 20 — запись.
            if not writes:
                writes = any(re.search(r'>>?\s*"?\$\{?' + v + r'\b', text)
                             for v in re.findall(r'\b([A-Za-z_]\w*)=["\']?[^"\'\n]*' + re.escape(m), text))
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
    #     ПУТЬ ИЗ ИСТОРИИ — КАК ЕСТЬ (17 сентября 2026, D429, брат `-z` у перечня): без
    #     `core.quotePath=false` не-ASCII путь приходит в кавычках с восьмеричными экранами, с
    #     ключом узла не совпадает, и история файла теряется молча (воспроизведено: у
    #     `hooks/проба.sh` после коммита `edits30` пуст; на живом дереве таких путей 0).
    hist = {}
    log = _git('-c', 'core.quotePath=false', 'log', '--since=30 days ago',
               '--pretty=format:%ad', '--date=short', '--name-only').stdout
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

def unresolved_namers(g, key):
    """Механизмы, чьи строки кода называют имя договора `key` целым словом, а ребра к нему в карте нет (D1075, R6).

    Правило пути (`project_map.contract_refs`) видит не всякий путь: собранный производной переменной (`${f%/*}/B`,
    `$BL_DIR/B`), перечнем имён (`for f in B …`), переменной не из `repo_vars` (`$CWD/…`). Одноимённый файл другого
    проекта (`~/.claude/settings.json`) правило от такого читателя не отличит, поэтому они не становятся рёбрами, а
    называются оговоркой: «на нём стоят N» без неё отвечало бы и «читателей N», и «правило видит N из большего числа».
    Вселенная та же, что у рёбер к договорам, — механизмы; первый отбор — `git grep -F`, судят `code_lines` и граница
    имени `_RB`. НАЗВАННЫЙ ПРЕДЕЛ: комментарий в конце строки кода `code_lines` не снимает — имя в нём тоже названо.
    """
    if PMAP is None or not project_map.is_contract(PMAP, REPO, key):
        return []
    base = key.rsplit('/', 1)[-1]
    ids = {n['id']: n['key'] for n in g['nodes']}
    linked = {ids[e['source']] for e in g['edges'] if ids.get(e['target']) == key}
    rx = re.compile(r'(?<![\w.\-])' + re.escape(base) + project_map._RB)
    out = []
    for f in _git('grep', '--untracked', '-I', '-l', '-z', '-F', '-e', base, '--').stdout.split('\0'):
        if not f or f == key or f in linked or not _is_mech(f):
            continue
        try:
            body = code_lines(open(os.path.join(REPO, f), errors='replace').read(), f.endswith('.py'))
        except OSError:
            UNREAD.append(f)
            continue
        if rx.search(body):
            out.append(f)
    return sorted(out)


def _namers_tail(namers):
    if not namers:
        return ''
    short = sorted(os.path.basename(x) for x in namers)
    return (f' | имя называют ещё {len(namers)} без пути, который разрешает карта (связь не проверена): '
            + ', '.join(short[:3]) + ('…' if len(short) > 3 else ''))


def path_of(g, key):
    idx = {n['id']: n for n in g['nodes']}
    tgt = [n for n in g['nodes'] if n['key'] == key or n['name'] == key]
    if not tgt:
        return f'узла «{key}» в карте нет'
    out = []
    for t in tgt:
        up = [f"{idx[e['source']]['key']} --{e['type']}-->" for e in g['edges'] if e['target'] == t['id']]
        down = [f"--{e['type']}--> {idx[e['target']]['key']}" for e in g['edges'] if e['source'] == t['id']]
        namers = unresolved_namers(g, t['key'])
        out.append(f"=== {t['key']} ({t['type']}) ===\nНА НЁМ СТОЯТ ({len(up)}):\n  " + '\n  '.join(up[:40]) +
                   (f"\nИМЯ НАЗЫВАЮТ БЕЗ ПУТИ, КОТОРЫЙ РАЗРЕШАЕТ КАРТА ({len(namers)}, связь не проверена):\n  "
                    + '\n  '.join(namers[:40]) if namers else '') +
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
    namers = unresolved_namers(g, t['key'])
    if not up:
        return (f'на нём не стоит никто{" по разрешённому пути" if namers else ""} | сам стоит на {len(down)}'
                + _namers_tail(namers))
    return f'на нём стоят {len(up)}: ' + '; '.join(parts) + f' | сам стоит на {len(down)}' + _namers_tail(namers)


UNKNOWN_KIND = 'карта этого вида не знает — допиши .claude-docs/project-map.json (кто на нём стоит, не проверено)'


def kind_known(rel):
    """Есть ли у карты правило ВХОДЯЩИХ рёбер к файлу этого вида (шаг 1г, R6: «0» и «не знаю» — разные ответы).

    Код (его зовут, импортируют, проверяют, описывают), тест (тест зовёт тест), договор по описанию (его читают и
    пишут). Документ, данные и ресурс вне договоров узлом карты стоят, но правила «кто на нём стоит» у них нет:
    «на нём стоят 0» о таком файле было бы ответом на неспрошенный вопрос.
    """
    if _is_mech(rel) or _is_test_path(rel) or _is_test_file(rel):
        return True
    return PMAP is not None and project_map.is_contract(PMAP, REPO, rel)


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


DATA = project_map.graph_out(PMAP, REPO) if PMAP is not None \
    else os.path.join(REPO, 'mcp-server', 'visualization', 'project-graph-data.json')


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
            # Учёта в проекте нет — кэш несвеж: «годен всегда» (D1068) не обновлял его никогда (D1070, F4); отказом
            # чтения это не называется — ветка идёт к пересборке либо к «кэша нет» у потребителя с потолком цены.
            if os.path.getmtime(DATA) >= _fresh_mark():
                return _pending_edges(_guard_kinds_from_files(json.load(open(DATA))))
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
        _save_data(g)
    except OSError:
        pass
    return g


def _fresh_mark():
    """С чем сверять свежесть кэша: учёт (владелец рёбер), а без учёта — индекс git проекта (D1071, F7): «без учёта
    кэш вечен» (D1068) не обновлялся никогда, «без учёта кэш всегда стар» (D1070) пересобирал на каждом вызове."""
    if os.path.exists(INDEX):
        return os.path.getmtime(INDEX)
    gd = _git('rev-parse', '--git-dir').stdout.strip()
    gi = os.path.join(REPO, gd, 'index') if gd else ''
    return os.path.getmtime(gi) if gi and os.path.exists(gi) else float('inf')


def _save_data(g):
    """Запись кэша карты под замком; каталог создаётся — свежий проект без `.claude-docs/` не падает (D1068, F3).
    Каталог записи — внутри проекта, файл не ссылка (D1070): иначе отказ 2, а не запись по чужой ссылке."""
    if project_map is not None:
        try:
            project_map.safe_output(REPO, DATA)
        except project_map.DescriptorError as e:
            print(f'project-graph: {e} — карта не записана', file=sys.stderr)
            sys.exit(2)
    os.makedirs(os.path.dirname(DATA), exist_ok=True)
    with with_lock(DATA):
        json.dump(g, open(DATA, 'w'), ensure_ascii=False)


def integrity(g):
    """Нарушения ССЫЛОЧНОЙ целости снимка: повтор id узла и ребро, у которого нет конца.

    17 сентября 2026, D427 (корень R6). `--check` судил непустоту — `0 if nodes and edges` — и
    отвечал 0 и целой карте, и карте с ребром 1→999 при единственном узле: «граф цел» и «граф
    сломан» шли одним кодом. Первая редакция прибора звала `build()` в том же процессе, а там
    целость держится ПОСТРОЕНИЕМ (оба конца ребра выдаёт `nid()`), и непустоты хватало. В тот же
    день ответ стал браться из КЭША — файла, который пишут сборка, `--touch` и рука, — предмет
    проверки сменился с «только что собранного» на «снимок из файла», а проверка осталась прежней.
    Читатели снимка верят ему так же: `brief` считал ребро в никуда («сам стоит на 1»), `--scc`
    вносил призрака в знаменатель («узлов 2» при одном узле), повтор id давал `--node` чужое имя
    конца (в `idx` побеждает последний) — всё с кодом 0; `path_of` и `cycles` падали `KeyError`
    с кодом 1, который у `--scc`/`--cycles` означает «спайки есть». Замер до правки, 16 пар:
    четыре снимка (висячая цель, висячий исток, повтор id с петлёй 1→1, кольцо через призрак) на
    четыре режима (`--check`, `--node <узел> --brief`, `--scc`, `--cycles`) — код 0 молча в 11,
    `KeyError` в 4, и одна пара ответила законным вердиктом (петля у `--cycles`); названо 0.
    После — названо 16 из 16. Поэтому проверка одна и стоит между `load()` и всеми читателями,
    а не в одной ветке `--check`.
    Изолированный узел нарушением НЕ считается — одинокий узел законен (так объявлено у `touch`);
    петля (ребро узла в себя) — тоже: файл, зовущий себя, бывает.
    Цена: один проход по узлам и рёбрам — на живом кэше того дня (2231 узел, 7955 рёбер, нарушений
    0) 0,8 мс при 4,8 мс на само чтение JSON.
    СХЕМА: судится НАЛИЧИЕ полей, которые читатели берут без `.get` (у узла id, key, name, type;
    у ребра source, target, type). Нет поля — `KeyError` отсюда, и вызывающий называет его отказом
    «запись снимка не по схеме»: 1 у `--check`, 4 у прочих. Замер на шести формах (узел без id,
    key, name, type; ребро без target; снимок без поля edges) × те же четыре режима, 24 пары:
    на механизме до пункта `KeyError` с кодом 1 в 12 (из них 6 у `--scc`/`--cycles`, где единица —
    вердикт) и код 0 молча в 12, названо 0; после — названо 24 из 24.
    Поле, которого не читает никто (`strength`), не требуется.
    НАЗВАННЫЙ ПРЕДЕЛ: два узла с одним `key` при разных id не ловятся (4 пары из 4 — код 0, а
    который из двух ответит читателю по ключу, не определено), и не судится ВИД значения (`type`
    не строкой уронит читателя на `.split`). Условие снятия: то либо другое встретится в ЖИВОМ
    кэше — значит, у него есть писатель; сейчас оба живых писателя держат это построением
    (`nid()`, `seen`), и на живом кэше того дня нарушений 0.
    """
    from collections import Counter
    for n in g['nodes']:
        n['id'], n['key'], n['name'], n['type']   # поля, которые читатели берут без .get; нет поля —
    for e in g['edges']:                          # KeyError, и вызывающий называет его отказом по схеме
        e['source'], e['target'], e['type']
    ids = Counter(n['id'] for n in g['nodes'])
    out = [f"id {i} у {c} узлов: " + ', '.join(str(n.get('key')) for n in g['nodes'] if n['id'] == i)
           for i, c in ids.items() if c > 1]
    for e in g['edges']:
        gone = [str(x) for x in (e['source'], e['target']) if x not in ids]
        if gone:
            out.append(f"ребро {e['source']} --{e['type']}--> {e['target']}: узла {', '.join(gone)} в карте нет")
    return out


def integrity_text(bad):
    return (f'карта НЕ ЦЕЛА: нарушений {len(bad)} — ответам по ней верить нельзя; '
            'пересобрать: python3 scripts/project-graph.py --refresh\n'
            + '\n'.join('  · ' + b for b in bad[:10]) + ('\n  · …' if len(bad) > 10 else ''))


def _node_edges(g, by_key, key, nd):
    """Исходящие рёбра класса `TOUCH_TYPES` одного узла — заново, из его файла: «записано, снято». Одно правило
    `--touch` и чтения кэша (`_pending_edges`, D1345). Файл не прочитан — рёбра остаются как были, ключ — в `UNREAD`."""
    try:
        raw = open(os.path.join(REPO, key), errors='replace').read()
    except OSError:
        UNREAD.append(key)
        return 0, 0
    body = code_lines(raw, key.endswith('.py'))
    keep = [e for e in g['edges'] if not (e['source'] == nd['id'] and e['type'] in TOUCH_TYPES)]
    gone, g['edges'] = len(g['edges']) - len(keep), keep
    out = [(other, dep_role(key, other), 3) for other in body_deps(key, body, by_key)]
    typ, named = body_mentions(key, raw, by_key)
    out += [(other, typ, 2 if typ == 'проверяет' else 1) for other in named]
    if _is_test_file(key):
        out += [(other, 'проверяет', 2) for other in test_targets(key, body, unique_tests(by_key))]
    # Тест, чей импорт разрешается в механизм, — его тест: правило колонки tests учёта (решение владельца 25 октября
    # 2026), которое сборка берёт из учёта. Без него пересчёт узла снимал такое ребро (найдено ногой I16 при
    # пересчёте Swift-узлов; тем же путём шёл `--touch` теста TS/JS и Python). Тест — по описанию проекта
    # (`_is_test_path`) на любом языке, а не `_is_test_file`: та добавляет условие языка `.sh`/`.py` (D1265).
    if PMAP is not None and _is_test_path(key):
        universe = {k for k in by_key if project_map.lang_of(PMAP, k)}
        out += [(o, 'проверяет', 2) for o in sorted(project_map.import_refs(PMAP, REPO, key, body, universe))
                if o in by_key and _is_mech(o)]
    out = list({(o, t): (o, t, s) for o, t, s in out}.values())
    for other, typ, strength in out:
        g['edges'].append({'source': nd['id'], 'target': by_key[other]['id'],
                           'type': typ, 'strength': strength})
    return len(out), gone


def _pending_edges(g):
    """Узел, внесённый в карту ДО записи файла, отвечает своими исходящими рёбрами, как только файл есть (D1345).

    Живой зовущий (`hooks/impact-inject.sh`) делает `--touch` нового файла до его записи: тела ещё нет, рёбра считать
    не из чего, и повторного касания после записи никто не зовёт — узел отвечал «сам стоит на 0» до пересборки, то
    есть «связей нет» и «связи ещё не считались» шли одним значением (род B). `touch` помечает такой узел
    `unread`; первое чтение кэша после записи файла считает его рёбра тем же правилом, что `--touch`, и ПИШЕТ кэш
    (скептик D1345, L2 и L4): без записи досчёт повторялся на каждом чтении — около 140 мс на помеченный узел, 2,8 с
    при двадцати, — а читатели кэша мимо `load()` видели узел одиноким. Запись — тем же путём, что у `--touch`; отказ
    записи чтению не мешает.
    Снимок не по схеме (ребро без концов, узел без id) здесь не трогается: его называет проверка целости, а не трасса
    досчёта (L1). Файл с пометкой не прочитан — пометка остаётся. НАЗВАННЫЙ ПРЕДЕЛ (L3): у Swift-файла `--touch`
    пересчитывает и соседние Swift-узлы, досчёт при чтении — только сам узел; входящие рёбра от соседей появятся на
    пересборке. Условие снятия: Swift объявят в описании проекта, где новые файлы вносит страж правки.
    """
    if not g or not isinstance(g.get('edges'), list):
        return g
    todo = [n for n in g.get('nodes', []) if isinstance(n, dict) and n.get('unread') and n.get('key')
            and os.path.isfile(os.path.join(REPO, n['key']))]
    if not todo:
        return g
    work = dict(g)
    work['edges'] = list(g['edges'])
    seen_unread = len(UNREAD)
    try:
        by_key = {n['key']: n for n in g['nodes'] if n.get('key')}
        for n in todo:
            _node_edges(work, by_key, n['key'], n)
    except (KeyError, TypeError, AttributeError):
        return g
    g['edges'] = work['edges']
    failed = set(UNREAD[seen_unread:])
    for n in todo:
        if n['key'] not in failed:
            n.pop('unread', None)
    try:
        _save_data(g)
    except (OSError, SystemExit):
        pass
    return g


def touch(path):
    """Внести ОДИН файл в кэш карты, не пересобирая её (13 сентября 2026).

    Повод — слово владельца: «при создании должно новое в карту попадать». Замер флоу в тот
    день: только что созданный файл в карте отсутствовал, а хук правки на нём МОЛЧАЛ, и
    молчание читалось как «связей нет» — ровно там, где связи нужнее всего. Полная сборка
    стоит 10 с, пересборка учёта 9 с — на каждую запись файла ни то, ни другое не годится.
    Здесь считается только то, что видно из САМОГО файла: его узел и его исходящие рёбра класса
    `TOUCH_TYPES` — тем же правилом, что даёт полная сборка после пересчёта учёта: у механизма
    ЗАВИСИМОСТИ (цели от `body_deps`, роль от `dep_role`), у теста «проверяет» (`body_mentions` и
    связь «тест → тест», `test_targets`), у документа «описывает» (`body_mentions`); у файла,
    который уже стоит в карте, рёбра этого класса считаются заново, и исчезнувшая связь
    снимается (D430).
    НАЗВАННЫЙ ПРЕДЕЛ: ВХОДЯЩИЕ рёбра (кто зовёт новый файл, какой тест его проверяет, какой
    документ описывает) требуют прохода по всему дереву и появляются на ближайшем `--refresh`;
    узел при этом уже стоит в карте и виден как одинокий, а не отсутствует. Условие снятия:
    инкрементальный обратный проход по одному имени.
    ВТОРОЙ ПРЕДЕЛ (17 сентября 2026, D430): исходящие рёбра ИНЫХ классов — «использует <имя>»,
    «пишет», «висит на» — `touch` не считает и не снимает: у нового файла их до `--refresh` нет,
    у прежнего узла они остаются вчерашними. Условие снятия то же — правила этих классов станут
    вызываемы по одному файлу (в `build()` они идут циклами по всему дереву).
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
    seen = {n['key']: n for n in g['nodes']}
    # От корня, как у учёта (D1073); имя узла, который карта уже знает, — как есть (второй круг D1073).
    rel = project_map.rel_path(REPO, path, seen) if project_map is not None \
        else os.path.relpath(os.path.normpath(os.path.join(REPO, path)), REPO)
    if project_map is not None and project_map.outside(rel) \
            or project_map is None and (rel == '..' or rel.startswith('..' + os.sep)):  # `..odd.sh` — в дереве (D1071)
        return 'файл вне дерева'
    # `newdir/` и `newdir/.` — каталог, даже если его ещё нет (D1073): `rel_path` черту и точку в конце не хранит, их
    # видно только на входе.
    if rel == '.git' or rel.startswith('.git' + os.sep) or os.path.isdir(os.path.join(REPO, rel)) \
            or path.endswith(os.sep) or os.path.basename(path) in ('.', '..'):
        return 'не файл дерева'
    if PMAP is not None and project_map.is_map_output(PMAP, REPO, rel):
        return 'кэш карты — не узел карты'      # D1070, F6
    kind = node_kind(rel)
    channel = _guard_channel(rel) if kind == 'hook' else None   # вид стража — тем же правилом, что в сборке (D1340)
    if channel:
        kind = 'guard'
    if rel in seen:
        node = seen[rel]
        if node.get('type') in ('hook', 'guard') and kind in ('hook', 'guard'):
            node['type'] = kind
            node.pop('channel', None)
    else:
        node = {'id': max((n['id'] for n in g['nodes']), default=0) + 1,
                'name': os.path.basename(rel), 'type': kind, 'key': rel,
                'edits30': 0, 'last_change': ''}
        g['nodes'].append(node)
    if channel:
        node['channel'] = channel
    # ОДНО ПРАВИЛО НА ОБА ПУТИ (17 сентября 2026, D430): исходящие рёбра класса `TOUCH_TYPES`
    # считаются ЗАНОВО — прежние снимаются, цели берутся правилом учёта (`body_deps`, у теста и
    # документа `body_mentions`), роль зависимости — у владельца `dep_role`, сила ребра та же,
    # что в `build()`. Прежняя редакция писала «зовёт» литералом и только дописывала:
    # `grep x hooks/one.sh` после правки становился вызовом (спайка исполнения, разведённая в
    # D406, возвращалась одним `--touch`), а убранная зависимость жила до `--refresh`. Дедуп шёл
    # по ПАРЕ узлов без типа, и ребро «использует <имя>» в ту же библиотеку запрещало ребро
    # зависимости рядом, хотя сборка даёт оба.
    # Рёбра иных классов не трогаются: снять то, чего `touch` считать не умеет, значило бы терять
    # знание до пересборки. Файл НЕ ПРОЧИТАН — рёбра остаются как были: «не смог прочитать» не
    # есть «зависимостей нет» (род B), причина названа счётчиком `UNREAD`.
    by_key = {n['key']: n for n in g['nodes'] if n.get('key')}

    def retouch(key, nd):
        return _node_edges(g, by_key, key, nd)

    added, dropped = retouch(rel, node)
    # Файла ещё нет (касание до записи) — узел помечается: его рёбра досчитает чтение кэша (`_pending_edges`, D1345).
    if os.path.isfile(os.path.join(REPO, rel)):
        node.pop('unread', None)
    else:
        node['unread'] = True
    # SWIFT (скептик opus по 9dc31762, H1): ребро A→B зависит от имён верхнего уровня B, то есть от СОДЕРЖИМОГО B, —
    # правка Swift-файла сдвигает исходящие рёбра каждого Swift-узла, и пересчитываются все они (иначе после
    # переименования типа `--touch` оставлял рёбра, которых полная сборка не даёт). Счёт — по правленому файлу.
    if PMAP is not None and project_map.lang_of(PMAP, rel) == 'swift':
        for k, nd in list(by_key.items()):
            if k != rel and project_map.lang_of(PMAP, k) == 'swift':
                retouch(k, nd)
    _save_data(g)
    return rel, kind, added, dropped


if __name__ == '__main__':
    if '--touch' in sys.argv:
        r = touch(sys.argv[sys.argv.index('--touch') + 1])
        if isinstance(r, str):
            print(f'карта не тронута: {r}', file=sys.stderr)
            sys.exit(3)
        # Файла ещё нет (касание до записи) — «записано 0» читалось бы как «связей нет» (скептик D1345, M1): эту строку
        # страж правки показывает создающей сессии, и другой по этому файлу она не увидит.
        if os.path.isfile(os.path.join(REPO, r[0])):
            print(f'в карте: {r[0]} ({r[1]}), исходящих рёбер записано {r[2]}, прежних снято {r[3]}')
        else:
            print(f'в карте: {r[0]} ({r[1]}), файла ещё нет — исходящие связи посчитаются после записи')
        report_unread('внесение узла')
        sys.exit(0)
    g = load(fresh='--refresh' in sys.argv)
    if g is None:
        print('карта не пересобрана: кэш отсутствует или устарел (старше учёта, а без учёта — индекса git)', file=sys.stderr)
        sys.exit(3)
    # НЕЦЕЛАЯ КАРТА — ОТКАЗ ВСЕХ ЧИТАТЕЛЕЙ, А НЕ ОДНОЙ ВЕТКИ (17 сентября 2026, D427; довод — у
    # `integrity`). Код 4, а не 1: у `--scc` и `--cycles` единица — вердикт «спайки/кольца есть»,
    # и отказ прибора по тому же проводу был бы тем же дефектом. `--check` идёт дальше сам: числа
    # снимка он печатает и на сломанной карте (по ним видно, ЧТО судили), а вердикт выносит ниже;
    # режим, названный рядом с `--check`, старше него — порядок веток ниже тот же.
    # СХЕМА ЗАПИСИ — ТОТ ЖЕ ОТКАЗ (правка того же дня по замечанию скептика). Узел без `id`, ребро
    # без `target`, снимок без поля `edges` роняли саму проверку `KeyError`, а Python отдаёт на это
    # код 1 — вердикт «спайки/кольца есть» у `--scc`/`--cycles`: 12 пар «форма × режим», названо 0.
    # Снимок пишет и рука (она — предмет пробы пункта), а рука нарушает схему так же легко, как ссылку.
    only_check = '--check' in sys.argv and not any(m in sys.argv for m in ('--scc', '--cycles', '--node'))
    try:
        bad = integrity(g)
    except (KeyError, TypeError) as exc:
        print(integrity_text([f'запись снимка не по схеме — {type(exc).__name__}: {exc}']),
              file=sys.stdout if only_check else sys.stderr)
        sys.exit(1 if only_check else 4)
    if bad and not only_check:
        print(integrity_text(bad), file=sys.stderr)
        sys.exit(4)
    if '--scc' in sys.argv:
        # `--exec` — только рёбра ИСПОЛНЕНИЯ: рекурсию во время работы даёт лишь вызов,
        # журнал и тест кольцом не крутятся (D406, 14 сентября 2026).
        if '--exec' in sys.argv:
            g = {'nodes': g['nodes'],
                 'edges': [e for e in g['edges'] if e['type'].startswith('зовёт')]}
        comps, total = sccs(g)
        comps = refine_by_mode(comps, g)
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
        # Путь, которого карта не знает текстом (`TOOLS/b.sh`, `x/../y.sh`), — ключом от того же владельца, что у `touch`
        # и учёта (D1073, L1 скептика: третий потребитель «путь → ключ» шёл мимо `rel_path`). И путь, которого на диске
        # нет (удалённое коммитом имя в форме `./` или абсолютной, третий круг); имя сущности `rel_path` отдаёт как есть.
        if project_map is not None:
            keys = {n['key'] for n in g['nodes']}
            if key not in keys:
                key = project_map.rel_path(REPO, key, keys)
        # Файл дерева, чей вид карта не знает, — свой ответ (шаг 1г): «стоят 0» здесь не проверено, а пустой вывод
        # читается подсказкой как «узла нет, внести». Код 0: ответ дан, различает его текст, — новый код выхода
        # установленная подсказка прежней редакции читала бы поломкой карты (BROKEN) до переноса. Ключ — путь,
        # лежащий в дереве; имена сущностей (пункт, род, знание) путями не бывают и идут прежним ответом.
        if os.path.isfile(os.path.join(REPO, key)) and not kind_known(key):
            print(UNKNOWN_KIND)
            sys.exit(0)
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
        # ЦЕЛОСТЬ, а не одна непустота (D427). Требование непустоты остаётся: пустая карта тоже
        # отказ. Пересборки здесь нет намеренно — проверка судит СНИМОК и называет, а чинит
        # отдельная операция (`--refresh`).
        if bad:
            print(integrity_text(bad))
            sys.exit(1)
        sys.exit(0 if g['nodes'] and g['edges'] else 1)
    _save_data(g)
    print('карта записана:', DATA)
