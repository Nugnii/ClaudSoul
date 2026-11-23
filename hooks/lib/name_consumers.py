#!/usr/bin/env python3
"""name_consumers.py — переменная окружения, которую правка перестаёт читать, и файлы, которые её ещё задают.

Разбор хука `hooks/name-consumer-notice.sh` (D1200): там шапка с поводом, признаком, точностью и пределами.

Признак. Файл F в прежней редакции ЧИТАЕТ переменную окружения NAME в строке кода (не в комментарии и не в
докстроке): `$NAME`, `${NAME…}`, `os.environ.get('NAME')`, `os.environ['NAME']`, `getenv('NAME')`, awk
`ENVIRON["NAME"]`, `'NAME' in os.environ`, а в файле, который вообще трогает окружение (`os.environ`, `getenv`), —
и голый литерал `'NAME'` (чтение через обёртку: `_int("NAME", 300)`). Новая редакция F его не читает ни сама, ни
через файл, который ПОДКЛЮЧАЕТ строкой кода, а не упоминает в прозе (строка с кириллицей или обратной кавычкой —
проза; докстрока — тоже). Потребитель — другой файл `*.sh`/`*.py` дерева (учтённый или новый неучтённый), который в
строке кода ЗАДАЁТ NAME (`NAME=…`, `'NAME': …`, `["NAME"] = …`, `setenv('NAME'`, `putenv('NAME'`,
`setdefault('NAME'`) и называет F по имени. Имя без подчёркивания не судится.

Вход:  stdin — JSON события: PreToolUse Write/Edit/MultiEdit либо подача диспетчера правок командой
       (`tool_name: "Write"`, `content` — файл на диске после записи).
       argv[1] — `paths-lib.sh`, владелец безопасного вызова git (`project_git`, D515).
Выход: stdout — текст находки, пусто — находок нет либо уже показаны этой сессии.
Код:   0 — ответ получен; 2 — спросить нечем (git ответил ошибкой), причина в stderr.
Ядро признака — `consumers()`: оно же гоняется по истории дерева замером точности.
"""
import ast
import json
import os
import re
import subprocess
import sys
import time

ENV = r'[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+'
READ = re.compile(r'\$\{?(' + ENV + r')(?![A-Za-z0-9_])'
                  r'|(?:environ\.get\(|environ\[|getenv\(|ENVIRON\[)\s*[\'"](' + ENV + r')[\'"]'
                  r'|[\'"](' + ENV + r')[\'"]\s+(?:not\s+)?in\s+os\.environ')
LITERAL = re.compile(r'[\'"](' + ENV + r')[\'"]')
PREFIX = re.compile(r'[\'"]([A-Z][A-Z0-9]*_)[\'"]')  # «все GIT_*»: `k.startswith("GIT_")` читает имена по префиксу
ENV_API = re.compile(r'os\.environ|getenv\(')
PROSE = re.compile(r'[А-Яа-яЁё`]')
SHOW = 5        # потребителей одного имени в тексте; остальные называются числом
RECENT = 600    # с: коммит моложе — подача диспетчера после `sed -i … && git commit` судит его, а не HEAD


def code_lines(text, path):
    """Строки кода: без строк-комментариев и, у питона, без докстрок."""
    lines = text.splitlines()
    skip = set()
    if path.endswith('.py'):
        try:
            for node in ast.walk(ast.parse(text)):
                body = getattr(node, 'body', None)
                if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and body:
                    d = body[0]
                    if isinstance(d, ast.Expr) and isinstance(d.value, ast.Constant) and isinstance(d.value.value, str):
                        skip.update(range(d.lineno, (d.end_lineno or d.lineno) + 1))
        except (SyntaxError, ValueError):
            pass
    return [l for i, l in enumerate(lines, 1) if i not in skip and not l.lstrip().startswith('#')]


def reads(text, path):
    c = '\n'.join(code_lines(text, path))
    out = {next(g for g in m if g) for m in READ.findall(c)}
    if ENV_API.search(c):
        out |= set(LITERAL.findall(c))
    return out


def gone_names(old, new, path):
    """Имена, которые прежняя редакция читала, а новая не читает ни по имени, ни по префиксу (`startswith("GIT_")`:
    список GIT_DIR, GIT_INDEX_FILE… заменён снятием всех GIT_* — b281b0ea, замер D1200)."""
    prefixes = PREFIX.findall('\n'.join(code_lines(new, path)))
    return {n for n in reads(old, path) - reads(new, path) if not any(n.startswith(x) for x in prefixes)}


def token(word):
    return re.compile(r'(?<![\w-])' + re.escape(word) + r'(?![\w-])')


def stem(path):
    return os.path.splitext(os.path.basename(path))[0]


def consumers(gone, rel, new, texts):
    """Ядро признака. gone — снятые имена, rel — путь F, new — новая редакция F, texts — {путь: текст} кандидатов.
    → [(имя, [«путь:строка», …])] — только имена, у которых остался потребитель."""
    me = token(stem(rel))
    # Подключение — строка кода, а не проза: `paths-lib.sh` в `. "$PATHS_LIB"` назван строкой присваивания пути,
    # а «`hooks/state-lock-lib.sh`; обе обязаны совпадать» в докстроке не подключает ничего (скептик D1200, M2).
    linked = [l for l in code_lines(new, rel) if not PROSE.search(l)]
    found = []
    for name in sorted(gone):
        word = token(name)
        mine = {p: t for p, t in texts.items() if word.search(t)}
        # Читатель с той же основой имени, что F, держит договор, только если строка подключения называет и его каталог:
        # прокладка `. "$(cd …/../lib" && pwd)/universe-lib.sh"` — да (40f9c372), копия-бэкап `old/recheck.sh` при F,
        # называющем свою основу, — нет (скептик D1200, L3). Каталог — словом в той же строке, а не хвостом пути подряд:
        # живая прокладка пишет каталог и имя через `" && pwd)/`.
        def held(p):
            if stem(p) != stem(rel):
                return any(token(stem(p)).search(l) for l in linked)
            d = os.path.basename(os.path.dirname(p))
            return bool(d) and any(token(stem(p)).search(l) and token(d).search(l) for l in linked)
        if any(name in reads(t, p) and held(p) for p, t in mine.items()):
            continue
        sets = re.compile(r'(?<![\w$])' + name + r'=|[\'"]' + name + r'[\'"]\s*(?::|\]\s*=(?!=))'
                          r'|(?:setenv|putenv|setdefault)\(\s*[\'"]' + name + r'[\'"]')
        cons = []
        for p, t in sorted(mine.items()):
            if not any(me.search(l) for l in code_lines(t, p)):
                continue
            hits = [(i, l) for i, l in enumerate(t.splitlines(), 1) if not l.lstrip().startswith('#') and sets.search(l)]
            if hits:
                # Адрес — строка, где имя задаётся рядом с вызовом F, если такая есть (L4).
                i = next((i for i, l in hits if me.search(l)), hits[0][0])
                cons.append(f'{p}:{i}')
        if cons:
            found.append((name, cons))
    return found


def git(paths_lib, root, *args):
    r = subprocess.run(['bash', '-c', '. "$1" && shift && project_git -C "$@"', '_', paths_lib, root, *args],
                       capture_output=True, text=True, errors='replace')
    return r.returncode, r.stdout, r.stderr


def read(path):
    """Текст файла; None — прочитать не удалось (не путать с пустым файлом: род B)."""
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            return fh.read()
    except OSError:
        return None


def new_content(ev, path):
    ti = ev.get('tool_input') or {}
    if isinstance(ti.get('content'), str):
        return ti['content']
    edits = ti.get('edits') if ev.get('tool_name') == 'MultiEdit' else [ti]
    cur = read(path)
    if cur is None:
        return None  # правленый файл не читается — правка не применится, судить нечего
    for e in edits or []:
        o, n = e.get('old_string'), e.get('new_string')
        if not isinstance(o, str) or not isinstance(n, str) or not o or o not in cur:
            return None  # правка не применится — судить нечего
        cur = cur.replace(o, n) if e.get('replace_all') else cur.replace(o, n, 1)
    return cur


def main():
    paths_lib = sys.argv[1]
    try:
        ev = json.load(sys.stdin)
    except ValueError as e:
        print(f'name-consumer-notice: вход хука не разобран ({e}) — правка НЕ ПРОВЕРЕНА', file=sys.stderr)
        return 2
    path = (ev.get('tool_input') or {}).get('file_path') or ''
    if not path.endswith(('.sh', '.py')) or not os.path.isfile(path):
        return 0
    path = os.path.realpath(path)
    rc, root, _ = git(paths_lib, os.path.dirname(path), 'rev-parse', '--show-toplevel')
    root = root.strip()
    if rc or not root:
        return 0
    rel = os.path.relpath(path, os.path.realpath(root))
    rc, old, _ = git(paths_lib, root, 'show', f'HEAD:{rel}')
    if rc:
        return 0  # файла нет в последнем коммите — снимать нечего
    new = new_content(ev, path)
    if new is None:
        return 0
    commit = ''
    if new == old:
        # Подача диспетчера пришла после коммита (`sed -i … && git commit`, либо коммит следующей командой): HEAD уже
        # новая редакция. «Было» — у родителя свежего коммита, тронувшего F (скептик D1200, M3).
        rc, log, _ = git(paths_lib, root, 'log', '-1', '--format=%H %ct', '--', rel)
        parts = log.split()
        if rc or len(parts) != 2 or time.time() - int(parts[1]) > RECENT:
            return 0
        rc, old, _ = git(paths_lib, root, 'show', f'{parts[0]}^:{rel}')
        if rc:
            return 0
        commit = parts[0][:8]
    gone = gone_names(old, new, rel)
    if not gone:
        return 0
    # Один поиск на все снятые имена (L5): цена не растёт с их числом. `-z` — пути без экранирования (L2).
    args = ['grep', '-z', '-l', '-I', '-w', '-F', '--untracked']
    for name in sorted(gone):
        args += ['-e', name]
    rc, out, err = git(paths_lib, root, *args, '--', '*.sh', '*.py')
    # Непрочитанный файл `git grep` называет только в потоке ошибок («error: failed to stat 'x': Permission
    # denied»), а код оставляет 0 — без этого разбора такой файл выпадал бы из суждения молча (род B).
    errs = [l for l in err.splitlines() if l.startswith(('error:', 'fatal:'))]
    unread = [m.group(1) for m in map(re.compile(r"'([^']+)'").search, errs) if m]
    if rc > 1 or len(unread) < len(errs):
        print(f'name-consumer-notice: git grep ответил {rc} ({"; ".join(errs)[:200]}) — потребители '
              f'{", ".join(sorted(gone))} НЕ ПРОВЕРЕНЫ', file=sys.stderr)
        return 2
    texts = {p: read(os.path.join(root, p)) for p in out.split('\0') if p and p != rel}
    # Непрочитанный файл не «пуст»: он называется отдельно, а не выпадает из суждения молча.
    blind = sorted({p for p, t in texts.items() if t is None} | set(unread) - {rel})
    found = consumers(gone, rel, new, {p: t for p, t in texts.items() if t is not None})
    if blind:
        found.append(('(любое из снятых)', [f'{p} — не прочитан, потребитель ли он, не известно' for p in blind]))
    if not found:
        return 0
    # Дедуп по составу находки на сессию: путь инструмента и подача диспетчера видят одну правку дважды,
    # а повтор той же правки до починки потребителей нового не говорит.
    key = '|'.join([rel] + [n + '=' + ','.join(c) for n, c in found])
    state = os.environ.get('STATE_DIR') or os.path.expanduser('~/.claude/hooks/state')
    sid = re.sub(r'[^A-Za-z0-9_-]', '_', str(ev.get('session_id') or 'nosid'))
    seen = os.path.join(state, f'name-consumer-fired-{sid}.txt')
    if key in (read(seen) or '').splitlines():  # журнал не читается — сказать ещё раз, а не промолчать
        return 0
    try:
        os.makedirs(state, exist_ok=True)
        with open(seen, 'a', encoding='utf-8') as fh:
            fh.write(key + '\n')
    except OSError:
        pass
    lines = []
    for name, cons in found:
        more = f'\n  · …и ещё {len(cons) - SHOW}' if len(cons) > SHOW else ''
        lines.append(f'`{name}`:\n' + '\n'.join(f'  · {c}' for c in cons[:SHOW]) + more)
    who = f'Коммит {commit} снял' if commit else 'Правка снимает'
    print(f'📛 {who} с `{rel}` чтение переменной окружения, а её ещё задают файлы, которые '
          f'`{os.path.basename(rel)}` зовут:\n' + '\n'.join(lines) +
          '\nПосле правки они задают значение, которого здесь никто не читает: имя в них само не сменится. '
          'Пройди каждого до коммита — поправь имя либо убедись, что значение там для другого читателя '
          '(приманка, соседний скрипт). Признак D1200.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
