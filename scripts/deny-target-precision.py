#!/usr/bin/env python3
# Результат: доля отказов стража разбора, ударивших не по механизму, считается по сроку и при доле выше четверти
#            (N ≥ 20) замер отвечает кодом 1 — отбитые записи в документ, песочницу, git не копятся незамеченными
# Проверка результата: python3 scripts/deny-target-precision.py --self-test даёт 0
"""deny-target-precision.py [--since ISO] [--self-test] — доля отказов стража разбора, ударивших НЕ по механизму.

Результат: отказ, отбивший запись в документ, песочницу или команду git, не копится незамеченным:
           доля таких отказов считается по сроку, и при доле выше четверти (при N ≥ 20) замер
           отвечает кодом 1 — признак сужают, а не воспитывают исполнителя (правило вердикта
           «показалось», docs/mechanism-errors-and-backlog.ru.md, этап 5)
Проверка результата: python3 scripts/deny-target-precision.py --self-test — код 0; на живых
           расшифровках печатает счёт по классам и код 0/1 (2 — расшифровок нет)

Повод (23 октября 2026, ветвь В2, D1036): с 4 октября из 460 отказов по дереву проекта 45 %,
остальное — песочница 17 %, git 17 %, документы и журналы 13 %; за 22–23 октября документы и
журналы — 31 % из 96. Доля считалась руками один раз и не повторялась.

Роли целей берутся У ВЛАДЕЛЬЦЕВ одним вызовом bash: `rc_is_record_target` и `rc_is_outcome_carrier`
(hooks/root-cause-lib.sh), `_wt_outside` (hooks/lib/write-target-lib.sh), цель heredoc —
`ds_heredoc_writes` (hooks/detection-signals-lib.sh). Своей копии правил здесь нет; остальные
формы Bash (git, перенаправление, правка на месте) классифицируются здесь же по голове команды —
это замер, а не гейт, и его ошибка меняет число, а не пропускает правку. Печатает только счёт:
ни текста отказа, ни команд.
Классы: механизм (код/конфиг в дереве) · запись (документ/журнал/носитель исхода) · песочница ·
git · не разобрано. Доля «не по механизму» = (запись + песочница + git) / (все − не разобрано).
"""
import datetime
import glob
import json
import os
import pwd
import re
import shlex
import subprocess
import sys
import tempfile

GATE = 'Правка не пройдёт'
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PROJECTS = os.environ.get('DTP_PROJECTS', os.path.expanduser('~/.claude/projects'))


def strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, list):
        for x in v:
            yield from strings(x)
    elif isinstance(v, dict):
        for k in ('text', 'content'):
            if k in v:
                yield from strings(v[k])


def refusals(since):
    """(ts, tool, input) каждого отказа стража с момента since: tool_result с фразой отказа как hook error."""
    out = []
    for path in glob.glob(PROJECTS + '/**/*.jsonl', recursive=True):
        try:
            mtime = datetime.datetime.fromtimestamp(os.path.getmtime(path), datetime.timezone.utc)
        except OSError:
            continue
        if mtime.strftime('%Y-%m-%dT%H:%M:%S') < since[:19]:
            continue
        last_use = {}
        try:
            fh = open(path, errors='replace')
        except OSError:
            continue
        with fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                m = r.get('message') or {}
                c = m.get('content')
                if r.get('type') == 'assistant' and isinstance(c, list):
                    for b in c:
                        if isinstance(b, dict) and b.get('type') == 'tool_use':
                            last_use[b.get('id')] = (b.get('name'), b.get('input') or {})
                elif r.get('type') == 'user' and isinstance(c, list):
                    for b in c:
                        if isinstance(b, dict) and b.get('type') == 'tool_result':
                            txt = ' '.join(strings(b.get('content')))
                            if GATE in txt and ('hook error' in txt[:300] or 'hook blocking error' in txt[:300]):
                                ts = r.get('timestamp', '')
                                if ts >= since:
                                    out.append((ts, *last_use.get(b.get('tool_use_id'), ('?', {}))))
    return out


OWNERS = r'''
set -u
. "$1/hooks/root-cause-lib.sh" 2>/dev/null
. "$1/hooks/lib/write-target-lib.sh" 2>/dev/null
. "$1/hooks/detection-signals-lib.sh" 2>/dev/null
command -v rc_is_record_target >/dev/null 2>&1 || { echo "BROKEN нет владельца rc_is_record_target" >&2; exit 2; }
while IFS= read -r p; do
    [ -n "$p" ] || { echo "-"; continue; }
    if _wt_outside "$p" "/нет/такого/проекта"; then echo S
    elif rc_is_outcome_carrier "$p" || rc_is_record_target "$p"; then echo R
    else echo M; fi
done < "$2"
printf '%s\n' "==HEREDOC=="
while IFS= read -r -d '' c; do
    t=$(printf '%s\n' "$c" | ds_heredoc_writes 2>/dev/null | awk -F'\t' '$1 == "T" { print $2 }' | paste -sd'|' -)
    printf '%s\n' "${t:-}"
done < "$3"
'''


def ask_owners(paths, heredocs):
    """Один вызов bash: роль каждого пути (S песочница / R запись / M механизм) и цель каждого heredoc."""
    with tempfile.NamedTemporaryFile('w', delete=False, suffix='.paths') as fp, \
         tempfile.NamedTemporaryFile('w', delete=False, suffix='.cmds') as fc:
        fp.write('\n'.join(paths) + '\n')
        fc.write('\0'.join(heredocs) + ('\0' if heredocs else ''))
    try:
        res = subprocess.run(['bash', '-c', OWNERS, '_', ROOT, fp.name, fc.name], capture_output=True, text=True)
    finally:
        os.unlink(fp.name)
        os.unlink(fc.name)
    if res.returncode == 2:
        sys.stderr.write(res.stderr)
        sys.exit(2)
    lines = res.stdout.split('\n')
    cut = lines.index('==HEREDOC==') if '==HEREDOC==' in lines else len(lines)
    return lines[:cut], lines[cut + 1:cut + 1 + len(heredocs)]


GIT_ONLY = re.compile(r'^(cd\s+("[^"]*"|\S+)\s*&&\s*)?git\s+(add|commit|push|tag|status|diff|log|show|fetch|rev-parse)\b[^|;&>]*(\s*&&\s*git\s+\S+[^|;&>]*)*\s*$')
# Песочница по пути — ответ владельца (`_wt_outside`, роль S в OWNERS), перечня корней здесь нет (D1112: свой перечень
# не знал `/private/var/folders`, и одна запись получала разный класс по написанию пути). Здесь — только формы ТЕКСТА,
# которых владелец путей не раскроет: переменные песочницы и относительный `scratchpad`.
# `${TMPDIR}`, `${TMPDIR-…}`, `${TMPDIR:-…}` — песочница; `${TMPDIR+…}`/`${TMPDIR:+…}` подставляют ДРУГОЙ путь, когда
# $TMPDIR задан (скептик D1112, третий круг, M3), — не форма песочницы. `scratchpad/` — каталог, а не слово в имени:
# `case-scratchpad-x.md` в базе знаний, `hooks/scratchpad-lib.sh` и `projects/-…-scratchpad/` установки — не песочница
# (четвёртый круг, M2; пятый, M2 — дефис проходил левую границу).
# Имена `$S/`, `$T/`, `$TMP/` песочницей больше не считаются (D1220): переменную, заданную той же командой, раскрывает
# `expand`, а незаданная пуста — состояние оболочки между вызовами не живёт, и `S=/p/hooks; … $S/x.sh` шёл в «песочницу».
VARSAND = re.compile(r'(^|[^A-Za-z0-9_])(\$TMPDIR/|\$\{TMPDIR(:?-[^}]*)?\}/)|(^|[/\'"])scratchpad/')
HOME = re.compile(r'^(~[A-Za-z0-9_.-]*|\$HOME|\$\{HOME\})(?=/|$)')  # `~<имя>` — дом этого имени (D1192, L1)
SIMPLEVAR = re.compile(r'^\$(?:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\})')
MKTEMP = re.compile(r'^\$\(mktemp\b([^)]*)\)$')
HEREDOC_OPEN = re.compile(r'(?<!<)<<-?\s*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\1')


def mktemp_base(args):
    """Путь, который отдаст `mktemp <args>`: `-p DIR`/`--tmpdir=DIR` — под DIR; шаблон — сам шаблон (без `/` — в
    рабочем каталоге, как литерал); без шаблона — под `$TMPDIR` (круг скептика D1220: M1 и 8 отказов с шаблоном и `-p`
    уходили в «не разобрано»). Разобрать нечем — None."""
    try:
        a = shlex.split(args)
    except ValueError:
        return None
    base, tmpl, i = None, None, 0
    while i < len(a):
        x = a[i]
        if x == '-p' and i + 1 < len(a):
            base, i = a[i + 1], i + 2
        elif x.startswith('--tmpdir='):
            base, i = x.split('=', 1)[1], i + 1
        elif x == '-t' and i + 1 < len(a) and not a[i + 1].startswith('-'):
            i += 2  # macOS: префикс имени под $TMPDIR
        elif x.startswith('-'):
            i += 1
        else:
            tmpl, i = x, i + 1
    if tmpl and (tmpl.startswith('/') or (base is None and '/' in tmpl)):
        return tmpl
    if base:
        return base.rstrip('/') + '/' + (tmpl or 'mktemp')
    return tmpl or '$TMPDIR/mktemp'


def code_only(cmd):
    """Команда с телами heredoc, забитыми пробелами той же длины: присваивание в теле — данные, а не код (круг скептика
    D1220, L2). Места символов сохраняются. Предел: `<<` внутри кавычек открывает тело ложно — присваивания в нём не
    видны, и цель уходит в «не разобрано», а не в чужой класс."""
    out, wait = [], []
    for line in cmd.split('\n'):
        if wait:
            if line.strip() == wait[0]:
                wait.pop(0)
                out.append(line)
            else:
                out.append(' ' * len(line))
            continue
        out.append(line)
        wait = [m.group(2) for m in HEREDOC_OPEN.finditer(line)]
    return '\n'.join(out)


def expand(t, cmd, depth=0, pos=None):
    """Цель `$VAR/…` с переменной, заданной В ТОЙ ЖЕ команде, — раскрытым путём (D1220, корень R3: класс выбирали
    расширение и имя переменной, и один каталог песочницы получал три класса). Решает последнее присваивание-оператор
    до цели вне тел heredoc — в начале команды, после `;`, `&`, `&&`, `(`, `{`, перевода строки, после `export`/`local`/
    `declare`/`readonly`/`do`/`then`/`else`; литерал пути, цепочка `O=$S/out`, `$(mktemp …)` (`mktemp_base`). После `|`
    и `||` присваивание в расчёт не идёт: в конвейере оно живёт в подоболочке, после `||` — условно. Незаданные HOME и
    TMPDIR остаются как есть — их судят `own` и `varsand`. None — нераскрываемая: подстановка, `$` внутри значения,
    незаданная переменная, префикс-присваивание `M=… cmd` (оболочка раскрывает цель до него). Пределы (частота 0 на
    отказах с 1 октября 2026): `A=1 B=2;` и `declare -x S=` — `S` не раскрывается; присваивание в подоболочке `( … )`,
    в фоне `S=… &`, внутри `$(…)` и в теле невызванной функции раскрывается, хотя до цели не доживает; ветки `if`/`else`
    — побеждает последняя; присваивание внутри строки в кавычках видно как код; глубина цепочки больше 3 судится как
    остаток с `$`; рекурсия ищет переменную значения по первому вхождению; `~` в кавычках значения раскрывается как дом;
    `export S=…` среди аргументов чужой команды видно как присваивание; цель heredoc судится по первому вхождению своего
    текста — места её владелец не отдаёт, а `"$S"/a.sh` не находится вовсе и судится по всей команде."""
    s = t.strip('\'"')
    v = SIMPLEVAR.match(s)
    if not v or depth > 3:
        return t
    name, rest = v.group(1) or v.group(2), s[v.end():]
    pos = cmd.find(s) if pos is None else pos
    pos = len(cmd) if pos < 0 else pos
    a = [x for x in re.finditer(r'(?:(?:^|[;&\n({])\s*|\b(?:export|local|declare|readonly|do|then|else)\s+)' + name +
                                r'=(?P<v>"\$\([^)]*\)"|"[^"]*"|\'[^\']*\'|\$\([^)]*\)|[^\s;&|)]*)(?=\s*(?:[;&|\n)]|$))',
                                code_only(cmd))
         if x.start() < pos]
    if not a:
        return t if name in ('HOME', 'TMPDIR') else None
    val = a[-1].group('v')
    val = val[1:-1] if len(val) > 1 and val[0] == val[-1] and val[0] in '"\'' else val
    mk = MKTEMP.match(val)
    if mk:
        val = mktemp_base(mk.group(1))
        if val is None:
            return None
    if re.search(r'[`*?\[]|\$\(', val) or '$' in val[1:]:
        return None
    if val.startswith('$'):
        inner = expand(val, cmd[:a[-1].start()], depth + 1)
        return None if inner is None else inner + rest
    return val + rest


def own(t):
    """Цель для владельца: без кавычек, с раскрытым домашним каталогом и разрешённым `..`, без ФС — одна для Write/Edit,
    heredoc и Bash (скептик D1112, круги 1–2: `'/tmp/x'` и `/tmp/a/../b` уходили в «механизм»; пятый круг: `~/…` и
    `$HOME/…` — в «песочницу», и одно место получало два класса по виду записи)."""
    t = HOME.sub(lambda h: os.path.expanduser(h.group(1) if h.group(1).startswith('~') else '~'), t.strip('\'"'), count=1)
    return os.path.normpath(t) if t.startswith('/') else t


def varsand(t):
    """Форма текста песочницы — только у цели, которую владелец не раскроет: абсолютную знает он, и форма его ответ не
    перебивает (пятый круг, M2: `~/.claude/projects/-…-scratchpad/memory/MEMORY.md` через heredoc — «песочница», через
    Write — «запись»). Предел: относительный путь с каталогом `scratchpad` — замер не знает `cwd`. И только без `..`
    ПОСЛЕ формы: `$TMPDIR/../…/.claude/hooks/x` ведёт в установку (скептик D1112, M3), а `../scratchpad/q.txt` из
    соседнего каталога — в песочницу (корпус: единственная смена третьего круга)."""
    if own(t).startswith('/'):
        return False
    m = VARSAND.search(t)
    # Кавычки и `\` снимаются до суда о `..`: `$TMPDIR/'..'/…` оболочка читает как `..` (третий круг, L2).
    return bool(m) and '..' not in re.sub(r'[\\\'"]', '', t[m.end():]).split('/')
REDIRECT = re.compile(r'(?<![<>])>>?\s*"?([^\s"&|;)]+)')
INPLACE = re.compile(r'sed\s+-i\S*(?:\s+\S+)?\s+\'[^\']*\'\s+"?([^\s"&|;]+)')  # правка на месте: последний аргумент — файл
INTERP = re.compile(r'\b(python3?|node|perl|ruby|bash|sh)\s+-')


def classify(items):
    paths, pidx, heredocs, hidx = [], {}, [], {}
    for i, (ts, tool, inp) in enumerate(items):
        if tool in ('Write', 'Edit', 'MultiEdit') and inp.get('file_path'):
            pidx[i] = len(paths)
            paths.append(own(inp['file_path']))
        elif tool == 'Bash' and '<<' in (inp.get('command') or ''):
            hidx[i] = len(heredocs)
            heredocs.append(inp['command'])
    roles, targets = ask_owners(paths, heredocs) if (paths or heredocs) else ([], [])
    # Цели — раскрытые по присваиваниям своей команды (`expand`, D1220); None — нераскрываемая.
    htargets = {i: [expand(t, items[i][2]['command']) for t in targets[k].split('|')]
                for i, k in hidx.items() if k < len(targets) and targets[k]}
    btargets = {}
    for i, (ts, tool, inp) in enumerate(items):
        cmd = inp.get('command') or ''
        if tool == 'Bash' and i not in htargets and not GIT_ONLY.match(cmd.strip()):
            # Место цели — своё у каждого вхождения: `>> $L/x; L=…; >> $L/x` судится по присваиванию до каждого.
            btargets[i] = [expand(x.group(1), cmd, pos=x.start(1)) for x in list(REDIRECT.finditer(cmd)) + list(INPLACE.finditer(cmd))
                           if x.group(1) not in ('/dev/null', '&1', '&2')]
    # Владельцу — путь без кавычек и с разрешённым `..`: страж `..` отвергает ради безопасности, а замеру нужен класс
    # места, куда запись шла (скептик D1112, M2: `'/tmp/x'`, `/tmp/a/../b` уходили в «механизм»). Без ФС.
    opaths = sorted({own(t) for v in list(htargets.values()) + list(btargets.values()) for t in v if t is not None})
    hroles = dict(zip(opaths, ask_owners(opaths, [])[0])) if opaths else {}
    sand = lambda t: t is not None and (hroles.get(own(t)) == 'S' or varsand(t))
    # 'V' — цель с переменной, которую команда не задала литералом: владелец судил бы её по расширению. Остаток `$TMPDIR`
    # вне формы песочницы (`$TMPDIR/../…`, `${TMPDIR+…}`) — «механизм», как до D1220: путь уводит из песочницы.
    role = lambda t: ('V' if t is None else 'S' if sand(t) else 'M' if own(t).startswith('$')
                      else hroles.get(own(t), '-'))
    classes = []
    for i, (ts, tool, inp) in enumerate(items):
        cmd = inp.get('command') or ''
        if i in pidx:
            classes.append({'S': 'песочница', 'R': 'запись', 'M': 'механизм'}.get(roles[pidx[i]], 'не разобрано'))
        elif tool == 'Bash':
            if GIT_ONLY.match(cmd.strip()):
                classes.append('git')
            elif i in htargets:
                rs = {role(t) for t in htargets[i]}
                classes.append('механизм' if 'M' in rs else 'не разобрано' if 'V' in rs else 'запись' if 'R' in rs
                               else 'песочница' if rs == {'S'} else 'не разобрано')
            else:
                tgts = btargets[i]
                # Роль R — у владельца, как у Write и heredoc: `>>` и `sed -i` в документ — «запись», а не «механизм»
                # (D1192, M1 скептика D1112). Только у цели с известным путём: нераскрытую `$VAR/…` владелец судил бы
                # по расширению (скептик D1192, H2), такая цель — 'V', и без механизма рядом она «не разобрано» (D1220).
                # И без интерпретатора, как у песочницы (H1).
                rs = {role(t) for t in tgts}
                if tgts and rs == {'S'} and not INTERP.search(cmd):
                    classes.append('песочница')
                elif 'R' in rs and rs <= {'S', 'R'} and not INTERP.search(cmd):
                    classes.append('запись')
                elif 'V' in rs and 'M' not in rs:
                    classes.append('не разобрано')
                elif tgts and not all(sand(t) for t in tgts):
                    classes.append('механизм')
                else:
                    classes.append('не разобрано')
        else:
            classes.append('не разобрано')
    return classes


def report(items, since):
    classes = classify(items)
    n = len(classes)
    cnt = {k: classes.count(k) for k in ('механизм', 'запись', 'песочница', 'git', 'не разобрано')}
    known = n - cnt['не разобрано']
    off = cnt['запись'] + cnt['песочница'] + cnt['git']
    share = (100 * off // known) if known else 0
    print(f'отказов стража с {since}: {n}; разобрано {known}; не по механизму {off} ({share}%): '
          f'запись {cnt["запись"]}, песочница {cnt["песочница"]}, git {cnt["git"]}; механизм {cnt["механизм"]}; не разобрано {cnt["не разобрано"]}')
    if known < 20:
        print(f'  знаменатель {known} при пороге 20 — решения не принимаются')
        return 0
    if share > 25:
        print(f'  НАХОДКА: не по механизму {share}% > 25% — признак отказа сужать, а не исполнителя воспитывать (D1036)')
        return 1
    return 0


def self_test():
    """Синтетическая расшифровка: 27 отказов — код, документ, песочница (heredoc в /tmp), git и три песочницы D1112:
    перенаправление в /private/var/folders, правка на месте по пути в кавычках с `..`, перенаправление в "$TMPDIR/…" и в
    ${TMPDIR:-/tmp}/…; девятый — "$TMPDIR/../…/.claude/hooks/x.sh", механизм: `..` после формы текста уводит из песочницы; десятый —
    `../scratchpad/q.txt`, песочница: `..` до формы (форма из корпуса); 11–13 (четвёртый круг) — `$TMPDIR/'..'/…` и
    `${TMPDIR+…}` — механизм, heredoc в "$TMPDIR/y.sh" — песочница; 14–15 (пятый круг) — heredoc в имя со словом
    scratchpad: в базе знаний — запись, в `hooks/` — механизм; 16–18 (шестой) — heredoc в `~/.claude/projects/-…-scratchpad/`
    — запись, `>` в "$HOME/.claude/hooks/scratchpad/…" — механизм (абсолютную цель судит владелец, а не форма текста),
    `../x-scratchpad/` — механизм (дефис — не граница каталога); 19 — `>` в относительный `hooks/scratchpad-lib.sh` —
    механизм: форма текста живёт только у относительной цели, и там `scratchpad/` — каталог, а не начало имени;
    20–23 (D1192) — `>>` и `sed -i` в документ — запись, как у Write; `${HOME}/…` и `~<имя>/…` установки — механизм;
    24–27 (скептик D1192) — интерпретатор рядом с документом — механизм; цель `$M/…` при `M=/p/docs` той же команды —
    запись по раскрытому пути (D1220); смесь «песочница + запись» — запись, «механизм + запись» — механизм.
    Сверка ПО ПОРЯДКУ: обмен классами двух строк виден."""
    global PROJECTS
    d = tempfile.mkdtemp(prefix='dtp-')
    PROJECTS = d
    os.makedirs(os.path.join(d, 'proj'))
    path = os.path.join(d, 'proj', 'x.jsonl')
    deny = {'type': 'user', 'timestamp': '2026-10-23T10:00:00Z', 'message': {'role': 'user', 'content': [
        {'type': 'tool_result', 'tool_use_id': 'u', 'content': [{'type': 'text', 'text': 'PreToolUse:Write hook error: ⛔ ОТКАЗ. Правка не пройдёт, пока …'}]}]}}
    uses = [('Write', {'file_path': '/p/hooks/x.sh'}), ('Write', {'file_path': '/p/docs/notes.md'}),
            ('Bash', {'command': "cat >> /tmp/x/notes.md <<'EOF'\nтело\nEOF"}), ('Bash', {'command': 'cd "/p" && git commit -q -m x'}),
            ('Bash', {'command': 'echo x > /private/var/folders/ab/T/y.txt'}), ('Bash', {'command': "sed -i.bak 's/a/b/' '/tmp/a/../y.txt'"}),
            ('Bash', {'command': 'echo x > "$TMPDIR/y.txt"'}), ('Bash', {'command': 'echo x > ${TMPDIR:-/tmp}/y.txt'}),
            ('Bash', {'command': 'echo x > "$TMPDIR/../../Users/u/.claude/hooks/x.sh"'}), ('Bash', {'command': 'echo x > ../scratchpad/q.txt'}),
            ('Bash', {'command': "echo x > $TMPDIR/'..'/'..'/Users/u/.claude/hooks/x.sh"}), ('Bash', {'command': 'echo x > ${TMPDIR+/Users/u/.claude}/hooks/x.sh'}),
            ('Bash', {'command': "cat > \"$TMPDIR/y.sh\" <<'EOF'\nтело\nEOF"}),
            ('Bash', {'command': "cat > \"/Users/u/.claude/global-lessons/case-scratchpad-x.md\" <<'EOF'\nтело\nEOF"}),
            ('Bash', {'command': "cat > \"/p/hooks/scratchpad-lib.sh\" <<'EOF'\nтело\nEOF"}),
            ('Bash', {'command': "cat >> ~/.claude/projects/-private-tmp-x-scratchpad/memory/MEMORY.md <<'EOF'\nтело\nEOF"}),
            ('Bash', {'command': 'echo x > "$HOME/.claude/hooks/scratchpad/x.sh"'}), ('Bash', {'command': 'echo x > ../x-scratchpad/q.txt'}),
            ('Bash', {'command': 'echo x > hooks/scratchpad-lib.sh'}),
            ('Bash', {'command': 'echo x >> /p/docs/notes.md'}), ('Bash', {'command': "sed -i.bak 's/a/b/' '/p/docs/notes.md'"}),
            ('Bash', {'command': 'echo x > ${HOME}/.claude/hooks/scratchpad/x.sh'}),
            ('Bash', {'command': 'echo x > ~' + pwd.getpwuid(os.getuid()).pw_name + '/.claude/hooks/scratchpad/x.sh'}),
            ('Bash', {'command': "python3 -c 'open(1)' > /p/docs/log.md"}), ('Bash', {'command': 'M=/p/docs; echo x > $M/a.log'}),
            ('Bash', {'command': "sed -i.bak 's/a/b/' '/p/docs/notes.md'; echo x > \"$TMPDIR/o.txt\""}),
            ('Bash', {'command': 'echo x >> /p/docs/notes.md; echo y > /p/hooks/x.sh'})]
    with open(path, 'w') as fh:
        for k, (tool, inp) in enumerate(uses):
            fh.write(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': [{'type': 'tool_use', 'id': f'u{k}', 'name': tool, 'input': inp}]}}) + '\n')
            dd = json.loads(json.dumps(deny))
            dd['message']['content'][0]['tool_use_id'] = f'u{k}'
            fh.write(json.dumps(dd, ensure_ascii=False) + '\n')
    items = refusals('2026-10-01T00:00:00')
    classes = classify(items)
    want = ['механизм', 'запись', 'песочница', 'git', 'песочница', 'песочница', 'песочница', 'песочница', 'механизм', 'песочница',
            'механизм', 'механизм', 'песочница', 'запись', 'механизм', 'запись', 'механизм', 'механизм', 'механизм',
            'запись', 'запись', 'механизм', 'механизм', 'механизм', 'запись', 'запись', 'механизм']
    ok = classes == want and len(items) == 27
    print(('самопроверка ok: ' if ok else 'САМОПРОВЕРКА КРАСНАЯ: ') + ', '.join(classes))
    return 0 if ok else 1


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--self-test' in args:
        sys.exit(self_test())
    since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=14)).strftime('%Y-%m-%dT%H:%M:%S')
    if '--since' in args:
        since = args[args.index('--since') + 1]
    if not glob.glob(PROJECTS + '/**/*.jsonl', recursive=True):
        print(f'нечем мерить: расшифровок нет под {PROJECTS}')
        sys.exit(2)
    sys.exit(report(refusals(since), since))
