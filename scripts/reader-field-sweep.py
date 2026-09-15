#!/usr/bin/env python3
# Результат: в дереве нет читателя, который просит у файла состояния поле, ни разу не
#            встречающееся в живых записях этого семейства
# Проверка результата: python3 scripts/reader-field-sweep.py --check даёт 0, когда таких
#            читателей нет и каждый читатель состояния сверен (находки или несверенные —
#            код 1, отказ прибора — код 2)
"""Читатель просит поле, которого писатель не кладёт.

Повод (7 сентября 2026): `five-whys-gate.sh` читал `.file` у записей, где писатель
(`rework-detector.sh:201`) кладёт `.path`. Список выходил пустым ВСЕГДА — напоминание
шло без имён файлов, атрибуция `rework` не могла сработать ни разу. Прогоны были зелёные:
фикстура теста несла ту же выдуманную форму и соглашалась с читателем.

Признак: путь поля в чтении записи не встречается ни в одной живой записи того семейства
файлов состояния, которое читатель открывает.

НАСЕЛЕНИЕ И СВЕРКА — ОДИН КОД (D359, 12 сентября 2026). До этого население считал
отдельный grep (5 строк, все — `.state.current` из `intrusiveness-*.json`), а сверка
открывала только `*.jsonl` — множества не пересекались, и «1 из 5» сравнивало разные
предметы. Формы чтения промерены по дереву: `jq '.поле' "$VAR"` — 25 носителей, все с
присваиванием VAR в том же файле; «путь на месте», `cat … | jq`, `jq … <<<` — по нулю;
python-читатели записей — переменная, принявшая `json.loads(...)`, и её `.get("к")`/`["к"]`.
Чтение файла ВНЕ каталогов состояния (`settings.json`, маркер ablation) — не предмет и
исключается с названным числом. Семейство без живых записей на этой машине сверить нельзя —
оно называется и держит `--check` красным: «не сверено» и «сверено, чисто» — разные ответы.
Названный предел: у python-читателя поле сверяется с ЛЮБЫМ семейством, названным в том же
файле, — файл с двумя семействами сверяется грубее, чем с одним; видны переменная, принявшая
`json.loads` напрямую, и переменная цикла по списку, наполненному `append(json.loads(...))`,
а запись, прошедшая через словарь или функцию, невидима. Условие снятия: появится привязка
переменной записи к семейству по потоку данных (какой открытый файл она читает).
"""
import collections, glob, json, os, re, sys

REPO = os.environ.get("RFS_REPO") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.expanduser(os.environ.get("STATE_DIR", "~/.claude/hooks/state"))
SESSIONS = os.path.expanduser(os.environ.get("SR_SESSIONS_DIR", "~/.claude/sessions"))
STATE_MARKS = ("$STATE", "${STATE", "hooks/state", "$SR_SESSIONS_DIR", "${SR_SESSIONS_DIR")
FAMILY_RE = re.compile(r'/([a-z][a-z0-9-]*?)(?:-\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)?\.(jsonl?)\b')
PY_FAMILY_RE = re.compile(r'"([a-z][a-z0-9-]*?)(?:-\*|-\{[^}]*\}|-%s|-%\([^)]*\)s)?\.(jsonl?)"')


def family_of(basename):
    base = re.sub(r"\.jsonl?$", "", basename)
    return re.sub(r"-[0-9a-f]{8}-[0-9a-f-]+$", "", base)


def live_samples():
    """Живые записи каждого семейства: и одиночные `*.json`, и строки `*.jsonl`."""
    samples, unread = collections.defaultdict(list), []
    for d in (STATE, SESSIONS):
        for path in sorted(glob.glob(os.path.join(d, "*.json")) + glob.glob(os.path.join(d, "*.jsonl"))):
            fam = family_of(os.path.basename(path))
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    if path.endswith(".jsonl"):
                        # Голова И хвост файла. Одна голова лгала: у intrusiveness-history первые
                        # 95 записей — старая форма без `boundary`, а 4628 из 4728 её несут; прибор
                        # по первым 41 строке назвал четыре живых поля выдуманными (12 сентября 2026).
                        head, tail = [], collections.deque(maxlen=40)
                        for i, line in enumerate(fh):
                            line = line.strip()
                            if not line.startswith("{"):
                                continue
                            (head if i < 40 else tail).append(line)
                        for line in head + list(tail):
                            try:
                                samples[fam].append(json.loads(line))
                            except Exception:
                                pass
                    else:
                        try:
                            obj = json.load(fh)
                            if isinstance(obj, dict):
                                samples[fam].append(obj)
                        except Exception:
                            pass
            except OSError:
                unread.append(os.path.basename(path))
    return samples, unread


def path_present(records, parts):
    """Есть ли путь поля хотя бы в одной живой записи. Список на пути — предел глубины."""
    for rec in records:
        cur, ok = rec, True
        for p in parts:
            if isinstance(cur, dict) and p in cur:
                cur = cur[p]
            elif isinstance(cur, list):
                break
            else:
                ok = False
                break
        if ok:
            return True
    return False


def shell_readers(samples):
    out = []  # (file, line, fieldpath, family, verdict)
    files = sorted(glob.glob(os.path.join(REPO, "hooks", "*.sh")) + glob.glob(os.path.join(REPO, "hooks", "lib", "*.sh")))
    for hook in files:
        src = open(hook, encoding="utf-8", errors="replace").read()
        rhs = {m.group(1): m.group(2) for m in re.finditer(r'^\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)=("[^"\n]*"|[^\s;]+)', src, re.M)}
        for m in re.finditer(r"jq\s+(?:-[a-zA-Z]+\s+)*'(\.[^']*)'\s+\"\$\{?([A-Z_][A-Z0-9_]*)\}?\"", src):
            flt, var = m.group(1), m.group(2)
            fm = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)", flt)
            if not fm:
                continue
            parts = fm.group(1).split(".")
            line = src[:m.start()].count("\n") + 1
            name = os.path.relpath(hook, REPO)
            r = rhs.get(var)
            if r is None:
                out.append((name, line, fm.group(1), "?", "unresolved"))
                continue
            if not any(k in r for k in STATE_MARKS):
                out.append((name, line, fm.group(1), "?", "outside"))
                continue
            fam_m = FAMILY_RE.search(r)
            if not fam_m:
                out.append((name, line, fm.group(1), "?", "unresolved"))
                continue
            fam = fam_m.group(1)
            if fam not in samples:
                out.append((name, line, fm.group(1), fam, "no_live"))
                continue
            out.append((name, line, fm.group(1), fam, "ok" if path_present(samples[fam], parts) else "bad"))
    return out


def python_readers(samples):
    out = []
    me = os.path.abspath(__file__)
    files = sorted(glob.glob(os.path.join(REPO, "hooks", "lib", "*.py")) + glob.glob(os.path.join(REPO, "scripts", "*.py")))
    for py in files:
        if os.path.abspath(py) == me:
            continue
        src = open(py, encoding="utf-8", errors="replace").read()
        fams = sorted({m.group(1) for m in PY_FAMILY_RE.finditer(src)})
        if not fams:
            continue
        name = os.path.relpath(py, REPO)
        recvars = {m.group(1) for m in re.finditer(r'\b([a-z_][a-z0-9_]*)\s*=\s*json\.loads?\(', src)}
        # Запись, прошедшая через контейнер: `rows.append(json.loads(line))` и `for rec in rows:` —
        # переменная цикла тоже читает запись. Без этого `calibrate.py` (56 обращений) был невидим.
        lists = {m.group(1) for m in re.finditer(r'\b([a-z_][a-z0-9_]*)\.append\(json\.loads?\(', src)}
        for lst in lists:
            recvars |= {m.group(1) for m in re.finditer(r'\bfor\s+([a-z_][a-z0-9_]*)\s+in\s+' + re.escape(lst) + r'\b', src)}
        recvars = sorted(recvars)
        for v in recvars:
            for am in re.finditer(r'\b' + re.escape(v) + r'(?:\.get\("([A-Za-z_][A-Za-z0-9_]*)"|\["([A-Za-z_][A-Za-z0-9_]*)"\])', src):
                key = am.group(1) or am.group(2)
                line = src[:am.start()].count("\n") + 1
                live = [f for f in fams if f in samples]
                if not live:
                    out.append((name, line, key, ",".join(fams), "no_live"))
                    continue
                present = any(path_present(samples[f], [key]) for f in live)
                out.append((name, line, key, ",".join(live), "ok" if present else "bad"))
    return out


def main():
    samples, unread = live_samples()
    if not samples:
        print("BROKEN|reader-field-sweep|0|0|каталог состояния пуст: сверять не с чем")
        return 2
    if unread:
        print("BROKEN|reader-field-sweep|0|0|не прочитано файлов состояния: %d (%s)" % (len(unread), ", ".join(unread[:3])))
        return 2
    rows = shell_readers(samples) + python_readers(samples)
    by = collections.Counter(v for *_, v in rows)
    pop = len(rows) - by["outside"]
    checked = by["ok"] + by["bad"]
    for name, line, field, fam, v in rows:
        if v == "bad":
            live = sorted({k for r in samples.get(fam.split(",")[0], []) for k in (r.keys() if isinstance(r, dict) else [])})
            print("  ✗ %s:%d просит .%s у %s, живут: %s" % (name, line, field, fam, ",".join(live)))
        elif v == "no_live":
            print("  ? %s:%d просит .%s у %s — живых записей семейства нет, не сверено" % (name, line, field, fam))
        elif v == "unresolved":
            print("  ? %s:%d просит .%s — путь файла не разрешён по присваиванию" % (name, line, field))
    status = "ЧИСТО" if not by["bad"] else "РАСХОЖДЕНИЕ"
    print("%s|reader-field-sweep|%d|%d|население читателей состояния %d, сверено %d, не сверено %d, вне состояния %d"
          % (status, checked, by["bad"], pop, checked, by["no_live"] + by["unresolved"], by["outside"]))
    if "--check" in sys.argv and checked < pop:
        print("КРАСНО: сверено %d из %d читателей состояния — дробь НЕ ИЗМЕРЕНА" % (checked, pop))
        return 1
    return 1 if by["bad"] else 0


if __name__ == "__main__":
    sys.exit(main())
