#!/usr/bin/env python3
# Результат: коммит не уводит молча адрес «файл:строка», которого не тронул: каждый такой адрес назван до коммита (D1251)
# Проверка результата: bash hooks/tests/fixtures/probe_D1251.sh даёт 0
"""line-address-drift.py — адрес «файл:строка», который коммит не тронул, а строку под ним сдвинул или изменил.

Использование: line-address-drift.py [--staged | --commit <rev>] [--root <каталог>]
  --staged (по умолчанию) — индекс против HEAD (зовёт ловушка git до коммита);
  --commit <rev>          — коммит против родителя (замер по истории).
Печатает строку на каждый уехавший адрес: «<где упомянут>:<строка> — `<файл>:<N>` → <куда>»; код 0 всегда, кроме сбоя (2).

Зовёт ловушка git `commit-msg` (`hooks/commit-trap.sh`) подсказкой в stderr — коммит не держит.

Зачем (D1251). Адрес строки в комментарии кода и в документе объявляет, ЧТО там стоит, а сверки объявленного с файлом
после правки не было: 25e3e47a сдвинул 9 адресов в шести файлах, красным стал один (этот прибор по 25e3e47a называет их
все). Подозрителен только адрес, который стоял ТЕМ ЖЕ текстом и до коммита: адрес, переписанный автором в этом коммите,
— решение автора, а не дрейф. Цена — один `git grep` по именам сдвинутых файлов и чтение найденных (около 2 с).
НАЗВАННЫЙ ПРЕДЕЛ: судятся пути, названные целиком от корня (адрес по имени файла без каталога не судится); летописи и
журналы (CHANGELOG, архив бэклога, SESSION.md, как цель — и BACKLOG.md) не судятся: адрес в них верен на дату либо
сдвигается любой записью; датированный адрес в живом документе прибор от живого не отличит — решает автор.
Условие снятия: адрес строки получит якорь содержимого (имя функции, заголовок) — сверка пойдёт по нему, а не по номеру.
"""
import os
import re
import subprocess
import sys

ADDR = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.(?:sh|py|md|tsv|json|js|ts|toml|yml|yaml)):(\d+)(?:-\d+)?(?!\d)")
SKIP = {"CHANGELOG.md", "внутренний архив (не публикуется)", "BACKLOG-archive.md", "SESSION.md"}   # летописи: адрес верен на дату


def _chronicle():
    """Правило «документ — летопись, адрес в нём верен на дату» — у владельца, `scripts/docs-address-drift.py` (D409,
    `CHRONICLE`): он исключает и датированные отчёты `-20YY-MM-DD.md`, `_drafts/`, `sessions/` (скептик D1251, M2 —
    своя копия их не знала). Модуль владельца на верхнем уровне зовёт git и может выйти (мелкий клон) — не загрузился,
    тогда своё правило `SKIP`, как до M2."""
    import importlib.util
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "docs-address-drift.py")
    try:
        spec = importlib.util.spec_from_file_location("docs_address_drift", p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.CHRONICLE
    except (Exception, SystemExit):
        return None
# Цели-журналы растут с каждой записью: адрес строки в них сдвигает любой коммит, и номером его не исправить — такой
# адрес назывался бы на каждом коммите (замер по 20 коммитам 8 ноября 2026: `BACKLOG.md:1070`, `CHANGELOG.md:3348`).
SKIP_TARGET = SKIP | {"BACKLOG.md"}


def git(root, *a):
    r = subprocess.run(["git", "-C", root, *a], capture_output=True, text=True, errors="replace")
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout


def blob(root, spec):
    try:
        return git(root, "show", spec).split("\n")
    except RuntimeError:
        return None


def line_map(diff):
    """{файл: [(старое_начало, старых, новое_начало, новых), …]} из `diff -U0`."""
    out, cur = {}, None
    for ln in diff.split("\n"):
        if ln.startswith("+++ "):
            cur = ln[6:] if ln.startswith("+++ b/") else None
            if cur is not None:
                out.setdefault(cur, [])
        elif ln.startswith("@@") and cur is not None:
            m = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", ln)
            if m:
                out[cur].append((int(m.group(1)), int(m.group(2) or 1), int(m.group(3)), int(m.group(4) or 1)))
    return out


def where(hunks, n):
    """Старая строка n → ('same', n') | ('changed', None): в куске правки — изменена; иначе — сдвиг."""
    shift = 0
    for os_, oc, ns, nc in hunks:
        if oc == 0:            # чистая вставка ПОСЛЕ строки os_
            if n > os_:
                shift += nc
            continue
        if os_ <= n < os_ + oc:
            return "changed", None
        if n >= os_ + oc:
            shift += nc - oc
    return "same", n + shift


def main(argv):
    root = argv[argv.index("--root") + 1] if "--root" in argv[:-1] else os.getcwd()
    try:
        root = git(root, "rev-parse", "--show-toplevel").strip()
        if "--commit" in argv[:-1]:
            rev = argv[argv.index("--commit") + 1]
            old, new = f"{rev}^", rev
            diff = git(root, "diff", "-U0", "--no-color", "--no-renames", old, new)
            where_tree = [new]
            new_of = lambda p: blob(root, f"{new}:{p}")
        else:
            old = "HEAD"
            diff = git(root, "diff", "-U0", "--no-color", "--no-renames", "--cached")
            where_tree = ["--cached"]
            new_of = lambda p: blob(root, f":{p}")
    except RuntimeError as e:
        print(f"line-address-drift: {e}", file=sys.stderr)
        return 2
    hunks = line_map(diff)
    moved = {f: h for f, h in hunks.items() if h and os.path.basename(f) not in SKIP_TARGET}
    if not moved:
        return 0
    # Отбор — одним `git grep` по именам сдвинутых файлов: читать каждый файл дерева отдельным вызовом git — 62 с на коммит.
    pats = []
    for f in moved:
        pats += ["-e", f + ":"]
    try:
        hit = git(root, "grep", "-l", "-F", *pats, *where_tree)
    except RuntimeError:
        hit = ""          # код 1 — совпадений нет
    files = [ln.split(":", 1)[1] if where_tree != ["--cached"] else ln for ln in hit.split("\n") if ln]
    os.environ.setdefault("CLAUDSOUL_REPO", root)   # владелец правила летописи иначе ищет корень своим вызовом git
    chron = _chronicle()
    old_cache = {}
    for p in files:
        if not p or (chron.search(p) if chron else os.path.basename(p) in SKIP) or not ADDR.search(p + ":1"):
            continue
        lines = new_of(p)
        if lines is None:
            continue
        text = "\n".join(lines)
        if not any(f + ":" in text for f in moved):
            continue
        if p not in old_cache:
            ob = blob(root, f"{old}:{p}")
            old_cache[p] = "\n".join(ob) if ob is not None else ""
        before = old_cache[p]
        for i, ln in enumerate(lines, 1):
            for m in ADDR.finditer(ln):
                f, n = m.group(1), int(m.group(2))
                if f not in moved or m.group(0) not in before:   # не тот файл либо адрес переписан этим коммитом
                    continue
                kind, n2 = where(moved[f], n)
                if kind == "same" and n2 == n:
                    continue
                to = f"строка теперь {f}:{n2}" if kind == "same" else "строка изменена этим коммитом"
                print(f"{p}:{i} — `{f}:{n}` → {to}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
