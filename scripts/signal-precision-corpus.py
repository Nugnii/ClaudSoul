#!/usr/bin/env python3
# signal-precision-corpus.py — точность признака знания измеряется по корпусу расшифровок.
# Результат: у признака знания есть измеренная точность (совпадений, из них настоящих),
#            а не отметка «НЕ ИЗМЕРЕНА»
# Проверка результата: python3 scripts/signal-precision-corpus.py --self-test даёт 0
#
# Повод (D326, 6 сентября 2026). Ревизия дала 11 признаков для знаний с высоким
# confirmed_count, и у каждого стоит «точность НЕ ИЗМЕРЕНА». Правило реестра то же, что для
# родов дефекта: признак без измеренной точности в уровень отказа не переводится, потому что
# широкий признак становится фоном и обучает не читать сигнал (повод — род C, точность 3%).
#
# Что считается: сколько ВЫЗОВОВ корпуса признак ловит. Осмотр совпадений — руками, здесь
# только счёт и выборка: инструмент не решает, настоящее совпадение или ложное.
#
# НАЗВАННЫЙ ПРЕДЕЛ: признаки, чья форма требует сравнения ДВУХ файлов в момент вызова
# (установленная копия против исходной), по расшифровке не проверяются — состояние дерева на
# тот момент не восстановимо. Такие признаки отмечаются «не измеряется по корпусу».
# Условие снятия: появится журнал, пишущий вердикт предиката В МОМЕНТ вызова (а не задним
# числом по нынешнему дереву) — тогда расшифровка перестанет быть единственным источником, и
# предел уходит. Цена предела названа числом: у pattern-install-drift вся различающая сила
# лежит именно в таком предикате, и без него точность сырой формы ≤27% (81 из 111 срабатываний
# суть штатный вызов knowledge-counter-bump).
#
# ЕДИНИЦА НАБЛЮДЕНИЯ — ДЕЙСТВИЕ НАД ФАЙЛОМ, А НЕ ВЫЗОВ ИНСТРУМЕНТА. Одно действие «записать
# файл» имеет две формы вызова: Write/Edit с file_path и Bash с heredoc внутри command. Счёт
# по имени инструмента недосчитывает вторую форму, и доля её измерена самим знанием
# case-2026-08-27-tool-name-detection-blind-to-work-mode: 1357 правок оболочкой против 1675
# файловыми, 45%. Поэтому calls() РАСКЛАДЫВАЕТ heredoc-запись в синтетический вызов Write:
# предикат, писавшийся под файловый инструмент, видит её без собственной правки.
import json, re, sys, glob, os, random, subprocess, datetime

# Шов для фикстур: корпус берётся из переменной, иначе проверка судила бы ЖИВЫЕ расшифровки
# и зеленела бы от чужой работы (правило «тест не читает живой ~/.claude»).
CORPUS = os.path.expanduser(os.environ.get('CORPUS_DIR', '~/.claude/projects'))
# Граница хода — запись user по `is_turn_user` (D1153), как у зеркалимых `RC_TURN_STEP` и `fix-level-check`: своя
# проверка роли делила ход на служебной записи `api-request-blob`. Помощника нет — замер не идёт.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'hooks', 'lib'))
try:
    from transcript_window import is_turn_user
except ImportError as _tw_e:
    # Владельца признака нет — замер не идёт кодом 2 «не измерено», а не трассой с кодом 1: единица — «находка» у
    # реестра замеров, у свода на Stop и у «Проверок» бэклога (D1157, R6).
    # Предел: у `--registry-in-text` код 2 значит и «опознания нет» — свод на Stop молчит в обоих случаях.
    print(f"нет владельца признака transcript_window ({_tw_e}) — не измерено"); sys.exit(2)

# Разбор «куда пишет heredoc» живёт в ОДНОМ месте — `ds_heredoc_writes` в
# hooks/detection-signals-lib.sh (D366). До 12 сентября 2026 здесь стояла своя регулярка
# (компилированный шаблон `cat|tee > цель <<МЕТКА`), и две реализации расходились в 1356
# случаях из 1357. Здесь — только вызов и
# чтение протокола: `T<TAB>цель` (по строке на цель), строки тела с ведущим `|`, `E`.
DS_LIB = os.environ.get('DS_LIB') or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'hooks', 'detection-signals-lib.sh')

def heredoc_writes(command):
    """Записи файлов внутри команды оболочки → [(путь, тело)]."""
    if '<<' not in command:
        return []
    # Отказ прибора — ошибка, а не пустой список: [] читался бы как «записей нет», и счёт
    # по файловым инструментам молча недосчитывал бы 45% правок.
    if not os.path.isfile(DS_LIB):
        raise RuntimeError(f'heredoc_writes: нет библиотеки разбора {DS_LIB}')
    # errors='replace' обязателен: вход — ПРОИЗВОЛЬНАЯ команда из расшифровки, и её байты
    # доходят до сообщений awk. Строгий декодер убивает весь замер на первом же негодном
    # байте (15 сентября 2026: `0x8c`, замер signal-reachability не отработал ни разу).
    run = subprocess.run(['bash', '-c', 'source "$1" && ds_heredoc_writes', '_', DS_LIB],
                         input=command, capture_output=True, text=True, errors='replace')
    if run.returncode != 0:
        raise RuntimeError(f'heredoc_writes: ds_heredoc_writes вернула {run.returncode}: {run.stderr.strip()[:200]}')
    out, targets, body = [], [], []
    for line in run.stdout.split('\n'):
        if line.startswith('T\t'):
            targets.append(line[2:])
        elif line.startswith('|'):
            body.append(line[1:])
        elif line == 'E':
            text = ''.join(b + '\n' for b in body)
            out.extend((tg, text) for tg in targets)
            targets, body = [], []
    return out

def calls(limit_files=None):
    """ДЕЙСТВИЯ над файлами и прочие вызовы: (файл, tool_name, tool_input).

    Bash-вызов, записывающий файл heredoc-ом, отдаётся ДВАЖДЫ: как сам Bash-вызов и как
    синтетический Write с file_path/content. Синтетический помечен _synthetic=True, чтобы
    замер, которому нужны именно вызовы Bash, мог его отличить."""
    files = [f for f in glob.glob(f'{CORPUS}/**/*.jsonl', recursive=True)
             if '/subagents/' not in f]
    if limit_files:
        files = files[:limit_files]
    for path in files:
        try:
            fh = open(path, errors='replace')
        except OSError:
            print(f"calls/turn_texts: файл не прочитан: {path}", file=sys.stderr)
            continue
        with fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                m = d.get('message') or {}
                if m.get('role') != 'assistant':
                    continue
                for b in (m.get('content') or []):
                    if not isinstance(b, dict) or b.get('type') != 'tool_use':
                        continue
                    name, inp = b.get('name') or '', b.get('input') or {}
                    yield os.path.basename(path), name, inp
                    if name == 'Bash' and isinstance(inp.get('command'), str):
                        for target, body in heredoc_writes(inp['command']):
                            yield os.path.basename(path), 'Write', {
                                'file_path': target, 'content': body, '_synthetic': True}

def measure(tool, field, pattern, exclude=None, sample=8, limit_files=None):
    rx = re.compile(pattern)
    ex = re.compile(exclude) if exclude else None
    total = hits = 0
    examples = []
    for fname, name, inp in calls(limit_files):
        if tool and name != tool:
            continue
        val = inp.get(field) or ''
        if not isinstance(val, str) or not val:
            continue
        total += 1
        if not rx.search(val):
            continue
        if ex and ex.search(val):
            continue
        hits += 1
        if len(examples) < sample:
            examples.append((fname, val[:180].replace('\n', ' ')))
    return total, hits, examples

REACH_HISTORY = os.path.expanduser(os.environ.get('REACH_HISTORY') or
                                   os.path.join(os.environ.get('STATE_DIR', '~/.claude/hooks/state'),
                                                'signal-reachability.tsv'))

def reachability(limit_files=None):
    """Достижимость предиката области (D367): доля вызовов корпуса, у которых предикат
    НАХОДИТ свой предмет. Прибор, считающий только совпадения (measure), выключение предиката
    не видит по построению: 8 сентября 2026 heredoc_target_regex после двух правильных сужений
    находил цель у 1 команды из 1357, а число точности в заметке признака стояло прежнее.
    Знаменатель — вызовы Bash с `<<` (область предиката), числитель — те, где единственный
    владелец разбора (ds_heredoc_writes, D366) отдал цель; оба одним проходом и тем же кодом,
    что у живого движка. Предел назван числом: измерен ОДИН предикат области. heredoc_body_regex
    разбирает тело своим awk внутри детектора — владельца-функции нет, доля не считается;
    command_uses видит «вид оболочки», непустой у любой команды, — достижимость 1 по
    построению. Условие снятия для heredoc_body_regex: вынос разбора тела в функцию
    библиотеки, как ds_heredoc_writes, — тогда та же доля считается тем же проходом."""
    area = reached = 0
    for _f, name, inp in calls(limit_files):
        cmd = inp.get('command') if name == 'Bash' else None
        if not isinstance(cmd, str) or '<<' not in cmd:
            continue
        area += 1
        if heredoc_writes(cmd):
            reached += 1
    share = round(reached / area, 4) if area else None
    return {'heredoc_target_regex': {'area': area, 'reached': reached, 'share': share},
            'heredoc_body_regex': 'не измерено — разбор тела живёт в детекторе без функции-владельца',
            'command_uses': 'не измерено — область непуста у любой команды, достижимость 1 по построению'}

def reachability_main(limit_files=None):
    """Печатает доли и сравнивает с ПРЕДЫДУЩИМ прогоном из своей истории: бегун замеров
    обнуляет .out до запуска, поэтому история — своя, append-only. Падение доли вдвое и
    больше — находка (код 1): именно так выключение признака называется числом, а не
    обнаруживается через десять дней тремя нарушениями подряд."""
    import datetime as _dt
    r = reachability(limit_files)
    h = r['heredoc_target_regex']
    for k, v in r.items():
        print(f'{k}: {json.dumps(v, ensure_ascii=False)}')
    if not h['area']:
        print('достижимость: вызовов с << в корпусе нет — измерять нечего')
        return 3
    prev = None
    try:
        with open(REACH_HISTORY, encoding='utf-8') as fh:
            rows = [l.rstrip('\n').split('\t') for l in fh if l.strip() and not l.startswith('#')]
        if rows and len(rows[-1]) >= 4:
            prev = float(rows[-1][3])
    except (OSError, ValueError) as e:
        # ОТКАЗ ГОВОРИТ, а не подставляет «истории нет» (найдено скептиком 19 сентября 2026,
        # остаточный носитель D444 в этом же файле). «История нечитаема либо испорчена» и
        # «истории нет вовсе» — разные состояния мира, и первое ТИХО ГАСИТ находку: детектор
        # падения достижимости, ради которого история и заведена (D367), просто не срабатывает.
        print(f"reachability: история не прочитана ({type(e).__name__}: {e}) — "
              f"падение достижимости в этом прогоне НЕ ПРОВЕРЕНО", file=sys.stderr)
        prev = None
    if limit_files is None:
        os.makedirs(os.path.dirname(REACH_HISTORY), exist_ok=True)
        with open(REACH_HISTORY, 'a', encoding='utf-8') as fh:
            fh.write(f"{_dt.date.today().isoformat()}\t{h['area']}\t{h['reached']}\t{h['share']}\n")
    if prev is not None and h['share'] is not None and h['share'] < prev / 2:
        print(f'ПАДЕНИЕ достижимости heredoc_target_regex: было {prev}, стало {h["share"]} — признак выключился')
        return 1
    print(f'достижимость heredoc_target_regex: {h["share"]} ({h["reached"]} из {h["area"]} вызовов с <<)'
          + (f', прежде {prev}' if prev is not None else ', истории нет'))
    return 0

def self_test():
    """Отрицательный контроль: признак, которого в корпусе быть не может, даёт ноль;
    признак, который есть заведомо, даёт больше нуля. Без обоих плеч счёт недоказателен."""
    _, zero, _ = measure('Bash', 'command', r'этой-строки-нет-в-корпусе-ЯЯЯ', limit_files=12)
    tot, some, _ = measure('Bash', 'command', r'\bgit\b', limit_files=12)
    ok = (zero == 0) and (some > 0) and (tot > 0)
    print(f'self-test: невозможный признак → {zero}; «git» → {some} из {tot} вызовов Bash')
    # Третье плечо: разложение heredoc. Без него счёт по файловым инструментам недосчитывает
    # 45% правок, и молчание предиката читается как «таких действий не было».
    syn = real = 0
    for _f, n, i in calls(limit_files=12):
        if n == 'Write':
            if i.get('_synthetic'): syn += 1
            else: real += 1
    got = heredoc_writes("cat > hooks/x.sh <<'EOF'\nтело\nEOF\n")
    ok = ok and got == [('hooks/x.sh', 'тело\n')] and syn > 0
    print(f'self-test: разбор heredoc → {got[:1]}; в 12 файлах корпуса Write настоящих {real}, из оболочки {syn}')
    # Четвёртое плечо (D367): достижимость считается и лежит между 0 и 1; знаменатель не
    # пуст. Без него режим мог бы молча отдавать пустую область — то самое «выключился».
    h = reachability(limit_files=12)['heredoc_target_regex']
    reach_ok = h['area'] > 0 and h['share'] is not None and 0 < h['share'] <= 1
    ok = ok and reach_ok
    print(f'self-test: достижимость heredoc_target_regex на 12 файлах → {h}')
    # Пятое плечо (13 сентября 2026): режим речевых признаков. Оба конца — правило
    # совпадения зеркалит хук (`pad_words` + подстрока с пробелами), и единица счёта не
    # пуста. Без первого замер мерил бы ДРУГОЙ предмет, чем ловит `fix-level-check`;
    # без второго пустой корпус читался бы как «признак не срабатывает».
    # Строка нарочно БЕЗ ёлочек: `pad_words` их не снимает (их нет ни в наборе `tr`, ни в
    # `sed` у владельца правила, hooks/portable-lib.sh:308-312), и фраза внутри «…» хуком
    # не ловится. Это НАЗВАННЫЙ ПРЕДЕЛ признака, а не свойство замера: зеркаля правило,
    # замер обязан наследовать и его слепоту, иначе померит другой предмет.
    # Шестое плечо (D408, 14 сентября 2026): опознание класса и его исход. ОБА полюса —
    # иначе признак, всегда отвечающий «реестр есть», прошёл бы проверку: зелёная сторона
    # пункта такого мутанта не ловит по построению, она доказывает лишь возможность зелени.
    _yes = class_recognition_of('Тот же класс, что вчера: носителей 3 из 7.')
    _no = class_recognition_of('Тот же класс, что вчера. Чиню на месте.')
    _none = class_recognition_of('Правка прошла, тест зелёный.')
    cr_ok = (_yes == ('тот же класс', True) and _no == ('тот же класс', False)
             and _none == (None, False))
    ok = ok and cr_ok
    print(f'self-test: опознание класса → с реестром {_yes[1]}, без реестра {_no[1]}, '
          f'вне предмета {_none[0]}')

    pw = pad_words('Хук поймает меня: механизма нет — и всё.')
    pad_ok = (' механизма нет ' in pw) and (' поймает ' in pw) and (' всё ' in pw)
    seen = 0
    for _f, _t in turn_texts(limit_files=6):
        seen += 1
        if seen > 3:
            break
    ok = ok and pad_ok and seen > 0
    print(f'self-test: правило совпадения зеркалит хук → {pad_ok}; ходов в 6 файлах корпуса видно → {seen > 0}')
    # Зеркало сверяется с владельцем исполнением, а не объявлением (D1285): владельца нет — плечо не измерено и
    # самопроверка красна, иначе «зеркалит» осталось бы словом шапки.
    _pm = pad_owner_mismatch()
    ok = ok and _pm == []
    print(f'self-test: pad_words совпадает с hooks/portable-lib.sh → '
          f'{"владельца нет — не измерено" if _pm is None else ("да" if not _pm else "нет: " + repr(_pm[:3]))}')

    # ОБЪЯВЛЕННОЕ ОКНО ДОХОДИТ ДО СЧЁТА (24 сентября 2026, D408, корень R5). Пункт трижды
    # объявлял окно, а вызов не передавал ничего — и знаменателем была вся история, отчего
    # планка «100%» была недостижима по построению. С 4 октября 2026 единица окна — ОПОЗНАНИЕ,
    # поэтому нога судит не аргумент обхода, а ИСХОД: подменяем обход потоком опознаний и
    # смотрим, сколько из них вошло в счёт и какой вынесен вердикт.
    _real_turn_texts, _real_corpus_files = globals()['turn_texts'], globals()['corpus_files']
    _with, _without = 'Тот же класс: носителей 3 из 7.', 'Тот же класс, иду дальше.'

    def _run(texts, *args):
        """(код, первая строка вывода) замера на подменённом потоке ходов, от старых к новым."""
        def _feed(limit_files=None, with_ts=False, files=None, speech=False):
            return iter([('f.jsonl', t, f'2026-10-01T00:{i:02d}:00') for i, t in enumerate(texts)])
        globals()['turn_texts'], globals()['corpus_files'] = _feed, lambda: []
        try:
            import contextlib, io as _io
            buf = _io.StringIO()
            with contextlib.redirect_stdout(buf):   # свои замеры наружу не нужны
                rc = class_recognition_main(*args)
        finally:
            globals()['turn_texts'], globals()['corpus_files'] = _real_turn_texts, _real_corpus_files
        return rc, buf.getvalue().split('\n')[0]

    # Старые промахи ЗА окном вердикт не портят: без окна было бы 20 из 30 и код 1.
    rc_def, out_def = _run([_without] * 10 + [_with] * CLASS_RECOGNITION_WINDOW)
    rc_exp, out_exp = _run([_without] * 10 + [_with] * 7, 7)
    # Промах ВНУТРИ окна виден: самый свежий ход без реестра.
    rc_miss, _ = _run([_with] * CLASS_RECOGNITION_WINDOW + [_without])
    # Меньше окна — вердикта нет: на «1 из 1» проверка открытого пункта зеленела по одному наблюдению.
    rc_few, out_few = _run([_with])
    win_ok = (rc_def == 0 and f'{CLASS_RECOGNITION_WINDOW} опознаний): {CLASS_RECOGNITION_WINDOW};' in out_def
              and rc_exp == 0 and '7 опознаний): 7;' in out_exp
              and rc_miss == 1 and rc_few == 2 and 'НЕ ИЗМЕРЕНО' in out_few)
    # КАЖДЫЙ ФАЙЛ ЧИТАЕТСЯ ОДИН РАЗ (27 октября 2026, D408). Окно расширяется удвоением, и прежде
    # каждый проход перечитывал все свежие файлы заново: 10,9 ГБ вместо 3,6 ГБ, «Проверка» пункта
    # шла 49 с при сроке 60 и под нагрузкой выходила за него. Нога судит обход: сколько раз
    # каждый файл отдан чтению, когда опознаний нет и окно растёт до конца корпуса.
    _given = []
    def _rec(limit_files=None, with_ts=False, files=None, speech=False):
        _given.extend(files or [])
        return iter([])
    globals()['turn_texts'], globals()['corpus_files'] = _rec, lambda: [f'f{i:03d}.jsonl' for i in range(100)]
    try:
        import contextlib, io as _io
        with contextlib.redirect_stdout(_io.StringIO()):
            class_recognition_main()
    finally:
        globals()['turn_texts'], globals()['corpus_files'] = _real_turn_texts, _real_corpus_files
    once_ok = len(_given) == 100 and len(set(_given)) == 100
    # ЕДИНИЦА — ВЕСЬ ТЕКСТ ХОДА (D1148). Результат инструмента — запись `user` без текста — ход не делит; реплика
    # владельца строкой делит. Прежде ход резался на каждом результате, и реестр, названный после вызова
    # инструмента, в счёт опознания не шёл: показание D408 вышло 45% вместо 90%.
    # Ноги на шесть мутантов первого скептика D1148 (M2): запись `isMeta` с текстом и вложение `queued_command` ход не
    # делят; реплика блоками и уведомление задачи (граница широкая, `is_turn_user`) — делят; три блока текста — все;
    # время хода — последнего текста. И L4: строковый content ассистента — текст, реплика из пробелов — граница.
    # Режим `speech` (двойник свода на Stop) берёт ещё thinking и тело `: <<'CHAIN'`; сверку с самим `rc_turn_text`
    # держит `hooks/tests/fixtures/probe_D1148.sh`.
    import tempfile as _tf
    _fx = _tf.NamedTemporaryFile('w', suffix='.jsonl', delete=False, encoding='utf-8')
    _chain = ": <<'CHAIN'\nцепь\n@@x:1@@\nCHAIN"   # строка вида метки в теле — не метка (четвёртый скептик, L4)
    _bash = lambda c: {'type': 'tool_use', 'id': 't', 'name': 'Bash', 'input': {'command': c}}
    _echo = _bash("echo 'CHAIN'")   # `'CHAIN'` в кавычках без heredoc: владельца зовёт, тела не даёт
    for _i, _r in enumerate((
            {'type': 'user', 'message': {'role': 'user', 'content': 'проверь'}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'A'}, _echo, _bash(_chain)]}},
            {'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': 't', 'content': 'ok'}]}},
            {'type': 'user', 'isMeta': True, 'message': {'role': 'user', 'content': 'служебное'}},
            {'type': 'attachment', 'attachment': {'type': 'queued_command', 'prompt': 'набрано посреди хода'}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'thinking', 'thinking': ''}, {'type': 'thinking', 'thinking': 'мысль'}, {'type': 'text', 'text': 'B'}, _echo]}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': 'S'}},
            {'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'text', 'text': 'дальше'}]}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [None, {'type': 'text', 'text': 'C'}]}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [_echo]}},
            {'type': 'user', 'origin': {'kind': 'task-notification'}, 'message': {'role': 'user', 'content': 'задача кончилась'}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'D'}, _bash(": <<'CHAIN'\n\nCHAIN"), _echo, _bash(": <<'CHAIN'\n\nCHAIN")]}},
            {'type': 'user', 'message': {'role': 'user', 'content': '   '}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'E'}, _bash(": <<'CHAIN'\nr\rs\nCHAIN")]}},
            {'type': 'user', 'message': {'role': 'user', 'content': 'ещё'}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [_echo]}},
            {'type': 'user', 'message': {'role': 'user', 'content': 'плохо'}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'F'}]}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': ['x', {'type': 'text', 'text': 'H'}]}},
            {'type': 'user', 'message': {'role': 'user', 'content': 'конец'}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'G'}]}},
            {'type': 'assistant', 'message': {'role': 'assistant', 'content': ['x']}})):
        _r['timestamp'] = f'2026-10-29T10:00:{_i:02d}Z'
        _fx.write(json.dumps(_r, ensure_ascii=False) + '\n')
    _fx.close()
    _runs, _real_run = [], subprocess.run
    def _count_run(*a, **kw):
        _runs.append(a)
        return _real_run(*a, **kw)
    try:
        _units = [(t, ts) for _f, t, ts in turn_texts(files=[_fx.name], with_ts=True)]
        subprocess.run = _count_run
        _speech = [(t, ts) for _f, t, ts in turn_texts(files=[_fx.name], with_ts=True, speech=True)]
    finally:
        subprocess.run = _real_run
        os.unlink(_fx.name)
    # Пустой блок thinking — основная форма в мире (второй скептик D1148, M1: 62 357 пустых против 21 162 непустых), его
    # свод не берёт; `null` в content свод пропускает, не отбрасывая ход (L4); время хода судится в обоих режимах (L1).
    # Третий скептик (L1): команда без тела ни пустой строки, ни времени хода не даёт, ход из одних таких команд не
    # выдаётся; пустое тело — пустая строка; не-объект в content отбрасывает ход в речи; `\r` тела цел (L2); владелец —
    # один вызов на ход с `'CHAIN'` (ради этого коммит 960098b6): ходов таких пять — пять вызовов (вызов на команду дал
    # бы семь: в первом ходе команд три).
    _ts = lambda *ii: [f'2026-10-29T10:00:{i:02d}Z' for i in ii]
    unit_ok = (_units == list(zip(['A\nB\nS', 'C', 'D', 'E', 'F\nH', 'G'], _ts(6, 8, 11, 13, 18, 20)))
               and _speech == list(zip(['A\nцепь\n@@x:1@@\nмысль\nB\nS', 'C', 'D\n\n', 'E\nr\rs'], _ts(6, 8, 11, 13)))
               and len(_runs) == 5)
    print(f'self-test: единица — весь текст хода, результат инструмента ход не делит → {unit_ok} '
          f'(ходы: {_units}; речь: {_speech}; вызовов владельца {len(_runs)})')
    # Режим замера речевых признаков — единица `fix-level-check`, без thinking и CHAIN (M2): `outcome_main` зовёт
    # `turn_texts` без `speech`. Отказ владельца тел CHAIN — исключение, а не пустой список (L2).
    _calls = []
    def _spy(*a, **kw):
        _calls.append(kw)
        return iter(())
    globals()['turn_texts'] = _spy
    try:
        import contextlib, io
        with contextlib.redirect_stdout(io.StringIO()):
            outcome_main(0, 1)
    finally:
        globals()['turn_texts'] = _real_turn_texts
    mode_ok = bool(_calls) and not any(kw.get('speech') for kw in _calls)
    # Четыре отказа: библиотеки нет; вызов владельца упал (нет `rc_turn_text`, нет jq); владелец отработал и промолчал;
    # владелец ответил без меток (третий скептик, L1 и L3).
    _rc_lib, refuse_ok = RC_LIB, True
    _libs = []
    for _body in ('', 'rc_turn_text() { :; }', 'rc_turn_text() { echo x; }',
                  'rc_turn_text() { grep -o "@@[0-9a-f]*:0@@" "$1"; }'):   # вернулась одна метка из двух (L3)
        _lf = _tf.NamedTemporaryFile('w', suffix='.sh', delete=False)
        _lf.write(_body + '\n')
        _lf.close()
        _libs.append(_lf.name)
    for _lib in ['/nonexistent/root-cause-lib.sh'] + _libs:
        globals()['RC_LIB'] = _lib
        try:
            chain_bodies_many([": <<'CHAIN'\nx\nCHAIN"] * 2)
            refuse_ok = False
        except RuntimeError:
            pass
        finally:
            globals()['RC_LIB'] = _rc_lib
    for _lf in _libs:
        os.unlink(_lf)
    print(f'self-test: речевые признаки — без speech → {mode_ok} (вызовов {len(_calls)}); '
          f'нет библиотеки свода — исключение → {refuse_ok}')
    ok = ok and win_ok and once_ok and unit_ok and mode_ok and refuse_ok
    print(f'self-test: каждый файл корпуса читается один раз → {once_ok} '
          f'(отдано чтению {len(_given)}, разных {len(set(_given))} из 100)')
    print(f'self-test: окно считается опознаниями → {win_ok} '
          f'(по умолчанию {CLASS_RECOGNITION_WINDOW}: код {rc_def}; явное 7: код {rc_exp}; '
          f'промах в окне: код {rc_miss}; меньше окна: код {rc_few})')
    return 0 if ok else 1

# ── Речевые признаки (outcome_signals) ───────────────────────────────────────
# Второй РОД признака знания. `detection_signals` судят вызов инструмента ДО действия,
# `outcome_signals` — текст хода ПОСЛЕ (их читает hooks/fix-level-check.sh на Stop/PreCompact).
# Предмет замера тот же — «сколько раз признак совпал и сколько из совпадений настоящие», —
# поэтому режим живёт здесь, а не вторым прибором (род K).
#
# ПРАВИЛО СОВПАДЕНИЯ ЗЕРКАЛИТ ХУК, а не изобретается заново: `pad_words` из
# hooks/portable-lib.sh (пунктуация → пробелы, края в пробелах) и вхождение фразы как
# подстроки с пробелами по краям. Своё правило дало бы другой предмет — ровно тот класс,
# что записан паттерном subject-of-measurement-mismatch.
#
# ЕДИНИЦА — ВЕСЬ ТЕКСТ АГЕНТА В ХОДЕ, как у механизмов, которые замер зеркалит: `fix-level-check` судит весь
# текст после последней записи `user` с текстом, свод на Stop — `rc_turn_text` (D1148). До 27 октября 2026 здесь
# стоял «последний текстовый блок хода», и ход резался на каждом результате инструмента.
_PAD_PUNCT = '][(){}<>.,;:!?"`~@#$%^&*+=|\\/-'
_PAD_TABLE = str.maketrans({c: ' ' for c in _PAD_PUNCT + '\n\t—–…'})
PAD_OWNER = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'hooks', 'portable-lib.sh')


def pad_words(text):
    """Зеркало `pad_words` из hooks/portable-lib.sh БАЙТ-В-БАЙТ (D1285, корень R1): те же символы в пробел (`tr`, `sed`),
    сжимаются ТОЛЬКО пробелы (`tr -s ' '`) — `\\r` и неразрывный пробел остаются, края — как у `printf ' %s '` (пробел
    исходного края сохраняется). Прежняя копия сжимала любой пробельный символ и резала края — на `\\r\\n`, неразрывном
    пробеле и пунктуации по краю ответы расходились с хуком. Сверку с владельцем держит `pad_owner_mismatch` в
    `--self-test`."""
    return ' ' + re.sub(' +', ' ', (text or '').translate(_PAD_TABLE)) + ' '


PAD_SAMPLES = ['Хук поймает меня: механизма нет — и всё.', 'строка\nвторая\tтаб', '  края с пробелами  ',
               'тире – среднее … многоточие', 'Конец с точкой.', '(скобки) [и] {фигурные}', 'строка\r\nс CRLF',
               'неразрывный пробел', '-флаг --длинный', '100% $HOME @user #tag ^ & * + = | \\ /', '']


def pad_owner_mismatch(samples=PAD_SAMPLES):
    """Входы, на которых зеркало расходится с владельцем `hooks/portable-lib.sh`; None — владельца нет (не измерено)."""
    if not os.path.isfile(PAD_OWNER):
        return None
    bad = []
    for s in samples:
        sh = subprocess.run(['bash', '-c', '. "$1"; pad_words "$2"', '_', PAD_OWNER, s],
                            capture_output=True).stdout.decode('utf-8', 'replace')
        if sh != pad_words(s):
            bad.append(s)
    return bad


def outcome_phrases(lessons_dir=None):
    """[(фраза, имя знания)] из всех типов операционного знания (pattern/principle/case).

    ПАРАМИ, А НЕ СЛОВАРЁМ ПО ФРАЗЕ (13 сентября 2026). Первая редакция складывала
    `{фраза: знание}` через `setdefault` и теряла вторых владельцев: «проверка прошла» стоит
    у ДВУХ знаний, и снятие её у одного не убирало из словаря ничего. Хук читает именно пары
    «знание<TAB>фраза» (hooks/fix-level-check.sh:148-162) — замер обязан считать так же,
    иначе меряет другой предмет, чем ловит страж."""
    import re as _re
    d = lessons_dir or os.path.expanduser('~/.claude/global-lessons')
    out = []
    for f in sorted(glob.glob(os.path.join(d, '*.md'))):
        base = os.path.basename(f)
        if not base.startswith(('pattern-', 'principle-', 'case-')):
            continue
        try:
            txt = open(f, errors='replace').read()
        except OSError:
            print(f"outcome_phrases: файл не прочитан: {f}", file=sys.stderr)
            continue
        m = _re.search(r'^outcome_signals:\s*$(.*?)^[^\s#]', txt, _re.M | _re.S)
        if not m:
            continue
        for line in m.group(1).split('\n'):
            line = line.strip()
            if not line.startswith('- '):
                continue
            ph = line[2:].strip().strip('"').strip("'").lower()
            if ph:
                out.append((ph, base[:-3]))
    return out


# ─── ОПОЗНАНИЕ КЛАССА И ЕГО ИСХОД (D408) ──────────────────────────────────────────────
# Обязанность возникает не когда класс объявлен ЗАКРЫТЫМ, а раньше — когда он ОПОЗНАН:
# сказал «это тот же класс» — предъяви реестр носителей числом. До 14 сентября 2026 это
# не считалось ничем: словарь знания ловил только закрытие, и «произнёс и сделал» было
# неотличимо от «произнёс и не сделал».
#
# ЕДИНИЦА — ХОД. Реестр засчитывается, если назван В ТОМ ЖЕ ходу И РЯДОМ С ОПОЗНАНИЕМ (D1152):
# форма из списка REGISTRY_FORMS (число рядом со словом «носители» или «места», раздел «Братья корня»). Предел:
# наблюдается РЕЧЬ, а не мир; ход, где реестр построен молча и показан только в следующем,
# засчитан не будет.
RECOGNITION = [
    'тот же класс', 'класс закрыт', 'закрывает класс', 'в обоих носителях',
    'во всех носителях', 'поправил везде', 'правка адресована корню',
]
# РЕЕСТР ПРИВЯЗАН К ОПОЗНАНИЮ (D1152, решение владельца 29 октября 2026 — «строгий счёт»).
# Прежний признак брал любое число где угодно в ходе — «N из M», «D\d+», «дважды», «мест N»,
# — а на единице хода (D1148) такое совпадение есть почти в каждом длинном ходе: на ходах БЕЗ
# опознания от 5000 символов — 520 из 596. Разметка 40 последних опознаний вручную: настоящий
# реестр — в 15 (из них 4 спорных: список проявлений с адресами), прежний признак засчитывал 35
# (точность 15 из 35); окно D408 показывало 18 из 20 при семи настоящих из 18.
# Отвергнуто замером на той же разметке: одно окно при прежних формах — 10 из 20 при полноте
# 10 из 15; «тот же абзац» — 11 из 24; прежние формы без «D\d+» и «дважды» в окне 200 — 7 из 9
# при полноте 7 из 15. Принято в первом круге (формы сужены третьим, ниже): окно 300 знаков от
# опознания. Цена названа: реестр, сказанный своими словами («три потребителя», носители
# поимённо), засчитан не будет — строка долга называет форму.
# ФОРМЫ — ОДНИМ СПИСКОМ (третий круг D1152). Два круга скептика подряд находили одно и то же:
# строка долга обещала одно, регулярка засчитывала другое, ноги стояли на примерах скептика —
# у факта «какая форма есть реестр» было три владельца. Теперь владелец один: каждая форма
# несёт описание и примеры «да» и «нет»; регулярка собирается из списка, описание печатает режим
# `--registry-in-text` (его берёт строка долга на Stop), тест обходит список. Решение владельца
# 29 октября 2026 — «только со словом»: число рядом со словами «носители» или «места» и раздел
# «Братья корня»; «Чиню все три» без слова о носителях не засчитывается. Цена названа: на ручной
# разметке полнота 3 из 15. Корпус (400 файлов): засчитано 16 опознаний, ложных среди них нет.
_NB = r'(?<![\w.,:/№#-])'               # число не продолжает чужое: номер пункта, версию, дату
_N = r'\d+(?!\w|%|[.,:-]\d)'             # и само не дробь, не время, не дата, не процент
_NUMW = (r'(?:два|две|двух|три|тр[её]х|четыре|четыр[её]х|пять|пяти|шесть|шести|семь|семи|восемь|восьми'
         r'|девять|девяти|десять|десяти|\w+надцат[ьи]|двадцат[ьи]|тридцат[ьи]|сорок)')
_UNIT = r'(?!\s*(?:раз|тест|минут|час|сек|строк|%))'   # число — счёт носителей, а не повторов, тестов, времени
_PLACES = r'(?:носител\w*|мест(?:а|ах|ам)?\b)'        # «мест» — только множественное: «1 место», «местами» — не счёт
REGISTRY_FORMS = [
    # Счётная форма — «носителей», «носители», «мест», «места»: «носителях 3 теста» не счёт; число — не единицы времени
    # и не повторы («Носители: 3 раза»), не тесты («У носителей 3 теста упали»).
    ('слово и число', r'\b(?:носител(?:ей|и)|мест|места)\b(?:\s*[:—–-]\s*|\s+)(?:' + _N + r'|' + _NUMW + r'\b)' + _UNIT,
     '«носителей 3 из 7», «носителей: 3», «носителей три», «места: 5»',
     ['носителей 3 из 7', 'носителей: 3', 'носителей:3', 'носителей 3/7', 'носителей три', 'места: 5'],
     ['у носителей 3 теста упали', 'носители не искал, тесты 33 из 33', 'носители: 3 раза запускал поиск',
      'носителей 5 минут искал', 'носителей 1,5 часа', 'носителей 12%', 'носителей 2026-09-12', 'носителей D1200',
      'носителей №1200', 'носителей 14:05', 'во всех носителях 3 теста']),
    ('число и слово', _NB + r'\d+\s+' + _PLACES,
     '«3 носителя», «в 5 местах», «3 из 7 мест»',
     ['3 носителя', 'в 5 местах', '3 из 7 мест'],
     ['33 из 33 тестов', '12 из 12 фикстур', 'на 1 месте в очереди', 'занял 1 место', '2 местных переменных',
      'версия 1.3 носителя', 'D420 носителя', '3 теста носителя']),
    ('числительное и слово', r'\b' + _NUMW + r'\s+(?:\w+\s+)?' + _PLACES,
     '«три носителя», «в трёх местах», «все двенадцать носителей»',
     ['три носителя', 'в трёх местах', 'все двенадцать носителей', 'все три разных носителя'],
     ['все три теста зелёные', 'все восемь зелёные', 'чиню все три', 'все триггеры перепроверил', 'три раза местами',
      'все три разных теста носителя']),
    # Раздел, а не упоминание: жирный заголовок где угодно или начало строки, только именительный «братья» и после
    # «корня» — лишь метка R<N> (все заголовки корпуса: «**братья корня.**», «**братья корня:**», «**братья корня R4**»).
    # «Ищу (**)братьев корня(**)», «**Братья корня не искал**», цитата доктрины и ссылка на файл реестра — не реестр.
    ('реестр родов', r'defect-class-carriers\.py\s+--\w|\bбратья\s+корня\s+r\d+\s*[—–:-]'
                     r'|\*\*[ \t]*братья[ \t]+корня(?:[ \t]+r\d+)?[ \t]*[.:]?[ \t]*\*\*'
                     r'|(?<![^\n])[ \t]*(?:[-*#>|][ \t]*)*братья\s+корня(?:\s+r\d+)?\s*[.:]',
     'раздел «**Братья корня.**» (жирным или с начала строки), «братья корня R6 —», вызов `defect-class-carriers.py --…`',
     ['**братья корня.** a, b', '\nбратья корня: a, b', 'братья корня r6 — где ещё',
      'python3 scripts/defect-class-carriers.py --genus f'],
     ['ищу братьев корня.', 'не искал братьев корня.', 'это братья корня, их ищут до починки',
      'это братья корня: их ищут до починки', '[defect-class-carriers.py:145](scripts/defect-class-carriers.py)',
      '(«братья корня — где то же устройство»)']),
]
REGISTRY_RE = re.compile('|'.join('(?:%s)' % f[1] for f in REGISTRY_FORMS), re.I)
REGISTRY_SPAN = 300   # знаков от начала формы опознания до начала формы реестра, в обе стороны
# Описание — ЦЕЛИКОМ из списка и окна: хвост «что не реестр» — первые примеры «нет» каждой формы (третий скептик: хвост,
# написанный руками, расходился с поведением в обе стороны).
REGISTRY_TOLD = (f'форма не дальше {REGISTRY_SPAN} знаков от опознания — число рядом со словом «носители» или «места»: '
                 + ', '.join(f[2] for f in REGISTRY_FORMS)
                 + '; не реестр, например: ' + ', '.join(f'«{f[4][0]}»' for f in REGISTRY_FORMS))


def class_recognition_of(text):
    """Решение по ОДНОМУ ходу: (какая форма опознания, назван ли реестр рядом с ней).

    Вынесено функцией, чтобы у правила был один владелец: его зовёт и режим замера, и
    плечо самопроверки, и свод на Stop. Правило совпадения зеркалит хук: нормализуются ОБЕ
    стороны; место опознания ищется по словам формы с любыми разделителями. Якорь — КАЖДАЯ
    форма опознания в ходе, а не первая; места и реестр ищутся в одном тексте (`lower()`
    меняет длину строки на «İ», и смешанные индексы сдвигали окно).
    """
    padded = pad_words((text or '').lower())
    hits = [p for p in RECOGNITION if pad_words(p.lower()) in padded]
    if not hits:
        return None, False
    low = (text or '').lower()
    spots = [m.start() for h in hits
             for m in re.finditer(r'(?<!\w)' + r'[\W_]+'.join(map(re.escape, h.split())) + r'(?!\w)', low)]
    return hits[0], any(abs(r.start() - s) <= REGISTRY_SPAN for r in REGISTRY_RE.finditer(low) for s in spots)


CLASS_RECOGNITION_WINDOW = 20   # ОПОЗНАНИЙ, не сессий; ВЛАДЕЛЕЦ объявленного окна — здесь, а не в пункте


def class_recognition_main(window=None, sample=6, since=None):
    """Доля опознаний класса, за которыми в том же ходу назван реестр носителей.

    Окно — последние `window` ОПОЗНАНИЙ по времени хода. Меньше окна — вердикт не выносится:
    код 2 и «НЕ ИЗМЕРЕНО» в строке показания; 0 — реестр назван при каждом опознании окна.

    `since='YYYY-MM-DD'` берёт опознания ТОЛЬКО от этой даты: механизм, который пункт D408
    проверяет, заводился датой, и без отсечки доля смешивает ходы С механизмом и БЕЗ него
    (`pattern-subject-of-measurement-mismatch`). При отсечке ходы без времени в счёт не входят
    и называются числом, а не теряются молча."""
    # ПРАВИЛО СОВПАДЕНИЯ ЗЕРКАЛИТ ХУК: нормализуются ОБЕ стороны (`pad_words`), и ищется
    # подстрока. Первая редакция звала `re.search(pad_words(фраза), текст)` — то есть
    # искала строку с ПРОБЕЛАМИ по сырому тексту, и фраза в начале блока либо перед запятой
    # не ловилась вовсе. Замер недосчитывал, то есть льстил: доля выходила выше настоящей.
    said = with_registry = 0
    misses = []
    # `turn_texts` отдаёт ПАРУ (файл, текст). Первая редакция звала `str()` на паре целиком,
    # и кавычка из repr приклеивалась к первому слову: фраза в НАЧАЛЕ хода не ловилась.
    # Симптом был виден в выводе промахов (`('file.jsonl', 'Механизм есть…')`) и прошёл мимо.
    # ОКНО БЫЛО ОБЪЯВЛЕНО, НО НЕ ЗАВЕДЕНО (24 сентября 2026, D408, корень R5). Пункт трижды
    # говорил «окно 20 сессий», а команда «Проверки» никакого окна не передавала: знаменателем
    # была ВСЯ история — 25 870 ходов, 201 опознание. Следствие не косметическое: прошлые
    # промахи вечны, поэтому планка «100%» была недостижима ПО ПОСТРОЕНИЮ, как бы ни вела себя
    # речь дальше. Замер отвечал на вопрос «называл ли когда-нибудь», а утверждение было про
    # «называет ли теперь» (pattern-subject-of-measurement-mismatch).
    # Числа расхождения на день починки: без окна 50.2%, в объявленном окне 42.3%.
    # ЕДИНИЦА ОКНА — ОПОЗНАНИЕ, А НЕ СЕССИЯ (4 октября 2026, D408, решение владельца). Сессий
    # появляется около 140 в сутки, и окно в 20 сессий покрывало 2-3 часа: за один день
    # показание прошло 7 → 1 → 0 опознаний, а на «1 из 1» вердикт был зелёным по единственному
    # наблюдению. Само событие редкое — 5 опознаний за 9 дней, — поэтому порог в 20 опознаний
    # ВНУТРИ окна сессий сделал бы планку недостижимой на деле. Знаменатель теперь постоянен.
    if window is None:
        window = CLASS_RECOGNITION_WINDOW
    # Обход расширяется от свежих файлов и останавливается, когда окно набрано ТОЧНО: файл,
    # тронутый раньше, не может нести ход новее своего времени правки, поэтому хватает того,
    # чтобы самое старое опознание окна было не старше самого свежего из непрочитанных файлов.
    files = corpus_files()
    n_files = max(window, 20)
    events, undated, read = [], 0, 0
    while True:
        # Каждый файл читается один раз: проход берёт только файлы, не прочитанные прежними.
        for path, text, ts in turn_texts(files=files[max(0, len(files) - n_files):len(files) - read], with_ts=True,
                                         speech=True):
            if since:
                day = (ts or '')[:10]
                if not day:
                    undated += 1
                    continue
                if day < since:
                    continue
            hit, has_reg = class_recognition_of(text)
            if hit:
                events.append((ts or '', hit, has_reg, text))
        read = min(n_files, len(files))
        events.sort(key=lambda e: e[0])   # устойчиво; ходы без времени считаются самыми старыми
        if n_files >= len(files):
            break
        if len(events) >= window:
            unread_newest = datetime.datetime.fromtimestamp(
                os.path.getmtime(files[-n_files - 1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')
            if events[-window][0][:19] >= unread_newest:
                break
        n_files *= 2
    events = events[-window:]
    said = len(events)
    for _ts, hit, has_reg, text in events:
        if has_reg:
            with_registry += 1
        elif len(misses) < sample:
            i = text.lower().find(hit.lower())
            a = max(0, i - 90) if i >= 0 else 0
            misses.append((hit, text[a:a + 220].replace('\n', ' ')))
    share = round(100 * with_registry / said, 1) if said else 0.0
    measured = said >= window
    label = f' (окно {window} опознаний' + (f', от {since}' if since else '') + ')'
    print(f'опознаний класса{label}: {said}; с реестром носителей в том же ходу: '
          f'{with_registry} ({share}%)'
          + ('' if measured else f' — НЕ ИЗМЕРЕНО: до окна не хватает {window - said}'))
    if undated:
        print(f'  ходов без времени в корпусе, в счёт не вошли: {undated}')
    for h, ex in misses:
        print(f'  · без реестра [{h}]: {ex}')
    if not measured:
        return 2
    return 0 if with_registry == said else 1


def corpus_files():
    """Файлы корпуса по возрастанию времени правки — один владелец универсума обхода."""
    files = [f for f in glob.glob(f'{CORPUS}/**/*.jsonl', recursive=True)
             if '/subagents/' not in f]
    files.sort(key=lambda f: os.path.getmtime(f))
    return files


RC_LIB = os.environ.get('RC_LIB') or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'hooks', 'root-cause-lib.sh')


def chain_bodies_many(commands):
    """[команда Bash] → [[тело] | []]: тела `: <<'CHAIN'` — у владельца, свода на Stop (`rc_turn_text`, D484), а не своей
    регуляркой: у разбора heredoc в замере владелец один (`hooks/tests/test_heredoc_writes_single_owner.sh`, T4). Все
    команды хода — одним вызовом (третий круг D1148: вызов на команду стоил 4 с из 24 и выталкивал «Проверку» D408 из
    бюджета гейта): каждая — своей записью за меткой с разовым словом, тела разбираются по меткам. Пустое тело свод
    кладёт пустой строкой — так и здесь. Владельца зовут только команды с `'CHAIN'` в кавычках (их требует его
    регулярка); нет библиотеки или вызов упал — ошибка, а не пустой список, как у `heredoc_writes`."""
    out = [[] for _ in commands]
    idx = [i for i, c in enumerate(commands) if "'CHAIN'" in c]
    if not idx:
        return out
    if not os.path.isfile(RC_LIB):
        raise RuntimeError(f'chain_bodies: нет библиотеки свода {RC_LIB}')
    import tempfile
    tag = os.urandom(6).hex()
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 't.jsonl')
        with open(p, 'w', encoding='utf-8') as f:
            for i in idx:
                f.write(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': [
                    {'type': 'text', 'text': f'@@{tag}:{i}@@'},
                    {'type': 'tool_use', 'name': 'Bash', 'input': {'command': commands[i]}}]}},
                    ensure_ascii=False) + '\n')
        # Байтами, а не `text=True`: универсальные переводы строк превращали `\r` тела в `\n` (третий скептик, L2).
        run = subprocess.run(['bash', '-c', '. "$1" 2>/dev/null && rc_turn_text "$2"', '_', RC_LIB, p],
                             capture_output=True, env=dict(os.environ, STATE_DIR=d))
    stdout = run.stdout.decode('utf-8', 'replace')
    if run.returncode != 0 or not stdout:
        raise RuntimeError(f'chain_bodies: rc_turn_text вернула {run.returncode}: '
                           f'{run.stderr.decode("utf-8", "replace").strip()[:200]}')
    cur, buf, seen = None, [], set()
    for line in stdout[:-1].split('\n') if stdout.endswith('\n') else stdout.split('\n'):
        mk = re.fullmatch(rf'@@{tag}:(\d+)@@', line)
        if mk:
            if cur is not None and buf:
                out[cur] = ['\n'.join(buf)]
            cur, buf = int(mk.group(1)), []
            seen.add(cur)
        else:
            buf.append(line)
    if cur is not None and buf:
        out[cur] = ['\n'.join(buf)]
    # Вернулись не все метки — форма вывода владельца разошлась с разбором; тела молча стали бы пустыми (L3).
    if seen != set(idx):
        raise RuntimeError(f'chain_bodies: меток вернулось {len(seen)} из {len(idx)}')
    return out


def chain_bodies(command):
    """Тело `: <<'CHAIN'` одной команды → [тело] | [] — `chain_bodies_many` на одну команду."""
    return chain_bodies_many([command])[0]


def turn_texts(limit_files=None, with_ts=False, files=None, speech=False):
    """(файл, весь текст агента в ходе) — единица та же, что у зеркалимых механизмов.

    Граница хода — `is_turn_user` (запись `user` без `isMeta` с непустым текстом, строкой либо блоками `text`), как у
    `RC_TURN_STEP` (`hooks/root-cause-lib.sh`) и `hooks/fix-level-check.sh`: результат инструмента — тоже запись
    `user`, но без текста, и ход не делит; вложение `queued_command` записью `user` не является (D1142). До D1148
    границей была любая запись `user` с автором-человеком или без автора — у результата инструмента `origin` нет.

    Текст хода у двух механизмов разный (D1148, второй круг). По умолчанию — блоки `text` (и строковый content), как
    у `fix-level-check`. `speech=True` — двойник свода на Stop (`rc_turn_text`): `text` и `thinking` записи через «\\n»,
    затем тела `: <<'CHAIN'` её вызовов Bash; ход с записью, на которой свод падает (не-объект, кроме null, в content),
    отбрасывается целиком. Названный предел: битая строка JSON посреди хода — свод отдаёт пустой ход, двойник её
    пропускает и отдаёт текст; в корпусе таких 0 (второй скептик D1148, L4). Двойник,
    а не вызов владельца: `RC_TURN_STEP` отдаёт только последний ход файла; расхождение ловит нога сверки в
    `hooks/tests/fixtures/probe_D1148.sh`.

    `with_ts=True` добавляет третьим элементом время хода (последнего текста агента) либо None.
    Форма по умолчанию НЕ меняется намеренно: у обхода три читателя в этом файле и один в
    пробе `probe_D444.sh`, и смена кортежа сломала бы их молча — ровно тот дефект, о котором
    `case-2026-09-13-format-writer-checked-against-validator-not-readers`."""
    if files is None:
        files = corpus_files()
        if limit_files:
            files = files[-limit_files:]
    for path in files:
        try:
            fh = open(path, errors='replace')
        except OSError:
            print(f"calls/turn_texts: файл не прочитан: {path}", file=sys.stderr)
            continue
        # Куски хода — (кусок, время записи); кусок — текст либо ('chain', команда). Тела CHAIN разбираются при выдаче
        # хода одним вызовом владельца; время хода — у последнего непустого куска после разбора.
        texts = []
        bad = False

        def _turn(pieces):
            bodies = iter(chain_bodies_many([p[1] for p, _t in pieces if isinstance(p, tuple)]))
            got, ts = [], None
            for p, t in pieces:
                one = next(bodies) if isinstance(p, tuple) else [p]
                if one:
                    got.extend(one)
                    ts = t
            if not got:
                return None
            return (os.path.basename(path), '\n'.join(got), ts) if with_ts else (os.path.basename(path), '\n'.join(got))

        with fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                m = d.get('message') if isinstance(d.get('message'), dict) else {}
                role = m.get('role') or d.get('role') or ''
                if is_turn_user(d):
                    # Реплика из одних пробелов — тоже граница: `is_turn_user` и jq-двойник судят текст без strip (L4).
                    if texts and not bad:
                        r = _turn(texts)
                        if r:
                            yield r
                    texts, bad = [], False
                elif role == 'assistant':
                    c = m.get('content', d.get('content'))
                    if isinstance(c, str):
                        got = [c] if (c if speech else c.strip()) else []
                    elif not isinstance(c, list):
                        got = []
                    elif speech:
                        if not all(isinstance(b, dict) or b is None for b in c):
                            bad = True   # свод падает на `.type` не-объекта (кроме null), и ход уходит целиком
                            continue
                        c = [b for b in c if b is not None]
                        x = '\n'.join((b.get('text') or '') if b.get('type') == 'text' else b['thinking'] for b in c
                                      if b.get('type') == 'text' or (b.get('type') == 'thinking' and b.get('thinking')))
                        got = ([x] if x else []) + [
                            ('chain', b['input']['command']) for b in c
                            if b.get('type') == 'tool_use' and b.get('name') == 'Bash'
                            and isinstance((b.get('input') or {}).get('command'), str)
                            and "'CHAIN'" in b['input']['command']]
                    else:
                        got = [b['text'] for b in c
                               if isinstance(b, dict) and b.get('type') == 'text' and (b.get('text') or '').strip()]
                    texts.extend((g, d.get('timestamp')) for g in got)
        if texts and not bad:
            r = _turn(texts)
            if r:
                yield r


def outcome_main(sample=10, limit_files=None, only=None, strip_guillemets=False):
    """`only` — считать ОДНУ фразу: решение о сужении принимается по её собственной выборке,
    а не по общей (в общей одна частая фраза вытесняет прочие — замер 13 сентября 2026:
    «жду завершения» заняла 8 мест из 12).

    `strip_guillemets` — контрфакт: что было бы, если бы правило совпадения снимало «…».
    Владелец правила (`pad_words`) их не снимает, и фраза внутри кавычек хуком не ловится;
    режим отвечает ЧИСЛОМ, сколько срабатываний на этом теряется, — иначе разговор о
    починке шёл бы без знаменателя."""
    phrases = outcome_phrases()
    if only:
        phrases = [(ph, kn) for ph, kn in phrases if ph == only.lower()]
        if not phrases:
            print(f'фразы «{only}» нет ни у одного знания', file=sys.stderr)
            return 2
    if not phrases:
        print('outcome_signals ни у одного знания — мерить нечего', file=sys.stderr)
        return 2
    turns = hits = 0
    per = {}
    shown = []
    for fname, text in turn_texts(limit_files):
        turns += 1
        low = text.lower()
        if strip_guillemets:
            low = low.replace('«', ' ').replace('»', ' ')
        padded = pad_words(low)
        for ph, know in phrases:
            if ' ' + ph + ' ' in padded:
                hits += 1
                per[(know, ph)] = per.get((know, ph), 0) + 1
                if len(shown) < sample:
                    i = padded.find(' ' + ph + ' ')
                    shown.append((fname[:8], know, ph, padded[max(0, i - 70):i + len(ph) + 70].strip()))
    print(f'ходов в корпусе: {turns}')
    print(f'пар «знание+фраза» в базе: {len(phrases)} '
          f'(различных фраз: {len(set(p for p, _ in phrases))}, знаний: {len(set(k for _, k in phrases))})')
    print(f'СОВПАДЕНИЙ: {hits}')
    if turns:
        print(f'доля ходов с совпадением: {100.0 * hits / turns:.1f}%')
    for (know, ph), n in sorted(per.items(), key=lambda kv: -kv[1]):
        print(f'  {n:4d}  {know}  «{ph}»')
    print('--- выборка для осмотра глазом (инструмент не решает, настоящее совпадение или ложное) ---')
    for e in shown:
        print(f'  · [{e[0]}] {e[1]} «{e[2]}»\n      …{e[3]}…')
    return 0


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        sys.exit(self_test())
    if '--outcome-signals' in sys.argv:
        _s = int(sys.argv[sys.argv.index('--sample') + 1]) if '--sample' in sys.argv else 10
        _lim = int(sys.argv[sys.argv.index('--files') + 1]) if '--files' in sys.argv else None
        _only = sys.argv[sys.argv.index('--phrase') + 1] if '--phrase' in sys.argv else None
        _gu = '--strip-guillemets' in sys.argv
        sys.exit(outcome_main(_s, _lim, _only, _gu))
    # РЕЖИМ ОДНОГО ТЕКСТА (23 сентября 2026, работа по D408). Признак «класс опознан, реестр
    # назван» живёт здесь и имеет измеренную точность; механизму границы хода он нужен ТОТ ЖЕ.
    # Вторая реализация в оболочке разошлась бы с этой молча — корень R1, ради которого
    # владельцы и заводятся. Текст приходит стандартным входом, ответ — кодом:
    #   0 — опознание есть И реестр назван; 1 — опознание есть, реестра НЕТ (долг);
    #   2 — опознания в тексте нет, судить нечего.
    if '--registry-in-text' in sys.argv:
        _t = sys.stdin.read()
        _form, _has = class_recognition_of(_t)
        if not _form:
            print('опознания класса в тексте нет')
            raise SystemExit(2)
        # Описание форм — в ТУ ЖЕ строку: свод на Stop кладёт вывод в очередь напоминаний построчно.
        print(f'опознание: {_form}; реестр назван: {"да" if _has else "НЕТ"}'
              + ('' if _has else f'; засчитывается: {REGISTRY_TOLD}'))
        raise SystemExit(0 if _has else 1)
    if '--class-recognition' in sys.argv:
        _since = None
        if '--since' in sys.argv:
            _i = sys.argv.index('--since')
            if _i + 1 < len(sys.argv):
                _since = sys.argv[_i + 1]
        _win = int(sys.argv[sys.argv.index('--window') + 1]) if '--window' in sys.argv else None
        # Отказ владельца тел CHAIN (нет библиотеки свода, нет jq) — код 2 «не измерено», а не 1: «Проверка» D408 читает
        # только код, и сломанная установка была неотличима от приговора «реестр не назван» (второй скептик D1148, L2).
        try:
            sys.exit(class_recognition_main(_win, since=_since))
        except RuntimeError as _e:
            print(f'замер не состоялся: {_e}', file=sys.stderr)
            sys.exit(2)
    if '--reachability' in sys.argv:
        _lim = int(sys.argv[sys.argv.index('--files') + 1]) if '--files' in sys.argv else None
        sys.exit(reachability_main(_lim))
    if len(sys.argv) < 4:
        print('usage: signal-precision-corpus.py <tool> <field> <regex> [--exclude RE] [--files N]',
              file=sys.stderr)
        sys.exit(2)
    tool, field, pattern = sys.argv[1], sys.argv[2], sys.argv[3]
    exclude = sys.argv[sys.argv.index('--exclude') + 1] if '--exclude' in sys.argv else None
    limit = int(sys.argv[sys.argv.index('--files') + 1]) if '--files' in sys.argv else None
    total, hits, ex = measure(tool, field, pattern, exclude, limit_files=limit)
    print(f'вызовов {tool}.{field}: {total}, совпадений: {hits}'
          f'{" (" + str(round(100*hits/total, 2)) + "%)" if total else ""}')
    for f, v in ex:
        print(f'  · {f}: {v}')
    sys.exit(0 if total else 3)
