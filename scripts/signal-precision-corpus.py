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
import json, re, sys, glob, os, random, subprocess

# Шов для фикстур: корпус берётся из переменной, иначе проверка судила бы ЖИВЫЕ расшифровки
# и зеленела бы от чужой работы (правило «тест не читает живой ~/.claude»).
CORPUS = os.path.expanduser(os.environ.get('CORPUS_DIR', '~/.claude/projects'))

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
    run = subprocess.run(['bash', '-c', 'source "$1" && ds_heredoc_writes', '_', DS_LIB],
                         input=command, capture_output=True, text=True)
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
    except (OSError, ValueError):
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
    # `sed` у владельца правила, hooks/portable-lib.sh:234-238), и фраза внутри «…» хуком
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
# ЕДИНИЦА — ПОСЛЕДНИЙ ТЕКСТОВЫЙ БЛОК ХОДА, потому что хук скан ведёт по последнему ответу
# агента, а не по всему ходу.
_PAD_PUNCT = '][(){}<>.,;:!?"`~@#$%^&*+=|\\/-'

def pad_words(text):
    out = []
    for ch in (text or ''):
        out.append(' ' if (ch in _PAD_PUNCT or ch in '\n\t—–…') else ch)
    return ' ' + ' '.join(''.join(out).split()) + ' '


def outcome_phrases(lessons_dir=None):
    """[(фраза, имя знания)] из всех типов операционного знания (pattern/principle/case).

    ПАРАМИ, А НЕ СЛОВАРЁМ ПО ФРАЗЕ (13 сентября 2026). Первая редакция складывала
    `{фраза: знание}` через `setdefault` и теряла вторых владельцев: «проверка прошла» стоит
    у ДВУХ знаний, и снятие её у одного не убирало из словаря ничего. Хук читает именно пары
    «знание<TAB>фраза» (hooks/fix-level-check.sh:146-160) — замер обязан считать так же,
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
# ЕДИНИЦА — ХОД. Реестр засчитывается, если назван В ТОМ ЖЕ ходу: дробь «N из M», счёт
# носителей числом либо вызов реестра родов. Названный предел: наблюдается РЕЧЬ, а не мир;
# ход, где реестр построен молча и показан только в следующем, засчитан не будет.
RECOGNITION = [
    'тот же класс', 'класс закрыт', 'закрывает класс', 'в обоих носителях',
    'во всех носителях', 'поправил везде', 'правка адресована корню',
]
# Реестр предъявлен: дробь «N из M», «носителей N», «мест N», вызов реестра родов.
# Счёт предъявляется не только цифрой: «чинился трижды в других местах» — это тот же
# реестр, названный словом. Замер 14 сентября 2026: сырой признак (одни цифры) дал 50%,
# и ЧЕТЫРЕ из шести промахов оказались ложными — счёт был назван словом либо носители
# перечислены поимённо. Признак, судящий форму записи числа вместо его наличия, повторил
# бы дефект, ради которого пункт и заведён.
REGISTRY_RE = re.compile(
    r'\b\d+\s+из\s+\d+\b'
    r'|носител\w*[^.\n]{0,20}?\d+|\d+\s+носител'
    r'|defect-class-carriers'
    r'|\bмест\w*\s+\d+|\d+\s+мест\w*'
    r'|дроб\w*[^.\n]{0,30}\d+'
    r'|\b(?:дважды|трижды|четырежды|пятикратно)\b'
    r'|\bв\s+(?:двух|трёх|четырёх|пяти|шести|семи|восьми|девяти|десяти)\s+\w+'
    r'|\bбрать\w*\s+корня\b'
    r'|\bD\d{2,3}\b',
    re.I)


def class_recognition_of(text):
    """Решение по ОДНОМУ ходу: (какая форма опознания, назван ли реестр).

    Вынесено функцией, чтобы у правила был один владелец: его зовёт и режим замера, и
    плечо самопроверки. Правило совпадения зеркалит хук: нормализуются ОБЕ стороны.
    """
    padded = pad_words((text or '').lower())
    hit = next((p for p in RECOGNITION if pad_words(p.lower()) in padded), None)
    if not hit:
        return None, False
    return hit, bool(REGISTRY_RE.search(text or ''))


def class_recognition_main(limit_files=None, sample=6):
    """Доля опознаний класса, за которыми в том же ходу назван реестр носителей."""
    # ПРАВИЛО СОВПАДЕНИЯ ЗЕРКАЛИТ ХУК: нормализуются ОБЕ стороны (`pad_words`), и ищется
    # подстрока. Первая редакция звала `re.search(pad_words(фраза), текст)` — то есть
    # искала строку с ПРОБЕЛАМИ по сырому тексту, и фраза в начале блока либо перед запятой
    # не ловилась вовсе. Замер недосчитывал, то есть льстил: доля выходила выше настоящей.
    said = with_registry = 0
    misses = []
    # `turn_texts` отдаёт ПАРУ (файл, текст). Первая редакция звала `str()` на паре целиком,
    # и кавычка из repr приклеивалась к первому слову: фраза в НАЧАЛЕ хода не ловилась.
    # Симптом был виден в выводе промахов (`('file.jsonl', 'Механизм есть…')`) и прошёл мимо.
    for path, text in turn_texts(limit_files=limit_files):
        hit, has_reg = class_recognition_of(text)
        if not hit:
            continue
        said += 1
        if has_reg:
            with_registry += 1
        elif len(misses) < sample:
            i = text.lower().find(hit.lower())
            a = max(0, i - 90) if i >= 0 else 0
            misses.append((hit, text[a:a + 220].replace('\n', ' ')))
    share = round(100 * with_registry / said, 1) if said else 0.0
    print(f'опознаний класса: {said}; с реестром носителей в том же ходу: {with_registry} '
          f'({share}%)')
    for h, ex in misses:
        print(f'  · без реестра [{h}]: {ex}')
    return 0 if said and with_registry == said else 1


def turn_texts(limit_files=None):
    """(файл, последний текстовый блок хода) — единица та же, что у хука."""
    files = [f for f in glob.glob(f'{CORPUS}/**/*.jsonl', recursive=True)
             if '/subagents/' not in f]
    files.sort(key=lambda f: os.path.getmtime(f))
    if limit_files:
        files = files[-limit_files:]
    for path in files:
        try:
            fh = open(path, errors='replace')
        except OSError:
            continue
        last = None
        with fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                t = d.get('type')
                if t == 'user' and not d.get('isMeta') and ((d.get('origin') or {}).get('kind', 'human') == 'human'):
                    if last:
                        yield os.path.basename(path), last
                    last = None
                elif t == 'assistant':
                    for b in ((d.get('message') or {}).get('content') or []):
                        if isinstance(b, dict) and b.get('type') == 'text' and (b.get('text') or '').strip():
                            last = b['text']
        if last:
            yield os.path.basename(path), last


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
    if '--class-recognition' in sys.argv:
        _lim = int(sys.argv[sys.argv.index('--files') + 1]) if '--files' in sys.argv else None
        sys.exit(class_recognition_main(_lim))
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
