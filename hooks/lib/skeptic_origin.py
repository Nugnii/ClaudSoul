#!/usr/bin/env python3
# skeptic_origin.py <корень репозитория> [срок поиска, с] — со stdin блок пункта долга; по строке на каждую находку
# скептика уровня H/M, чьё происхождение не сверено с миром:
#   bad<TAB><находка><TAB><причина>  — закрытие отбивается (D1305);
#   disowned<TAB><находка>           — находка объявлена неподтвердившейся (принимается, пишется в журнал стража).
# Пусто — находок H/M нет либо у каждой происхождение сверено. Код 0; 2 — git недоступен (судить нечем).
#
# Зачем (D1305, решение владельца 16 ноября 2026 — отказ, всё перепроверяется). Находки скептика закрывались строкой
# «Скептик.» без разбора, откуда дыра: из 123 закрытий, называющих H/M, слово о происхождении есть у 18. Все проверки,
# что встречались исполнителю, требовали ЗАПИСИ, и он закрывал самой дешёвой. Здесь запись сверяется с миром: git
# подтверждает, что названный коммит менял названное МЕСТО (строку файла), а поиск братьев повторяется и даёт число.
#
# Формат (одна строка на находку или на группу с общим происхождением):
#   **Происхождение.** H1, M2 — <коммит> <путь>:<строка>; братьев <N>: `<команда поиска>`
#   **Происхождение.** M3 — пунктом D<N>        (находка ушла в пункт долга с корнем — разбор несёт он)
#   **Происхождение.** M4 — не подтвердилась: <довод не короче 10 знаков>
# «Место» — строка файла нынешнего дерева; коммит обязан быть в её истории (`git log -L`), путь — файлом, не каталогом
# (скептик D1305, H1: путь «.» и голый файл принимали любой коммит, менявший хоть что-то). Число братьев — непустые
# строки вывода команды (срок — второй аргумент, по умолчанию 20 с).
# Находки — из абзацев с жирным заголовком «Скептик…» или «Круг скептика…» (строка и продолжение до следующей
# контрактной строки): H<n>, M<n> латиницей и кириллицей («Н4», «М2» — 4 из 30 последних закрытий, скептик D1305, H2),
# «H-1»; диапазоны «M1–M4», «M1—M3», «M1..M3» раскрываются.
# ПРЕДЕЛЫ (скептик D1305): номера кругов не различаются; смысл команды поиска не сверяется (`seq N` даст N); коммит
# происхождения бывает самой починкой — так и есть, когда дыру внесла она (D1309, L3), и git этого не различит;
# «h1» строчными и «H 1» через пробел не читаются.
import os
import re
import subprocess
import sys

CONTRACT = re.compile(r"^\s*\*\*[^*]+\*\*")
SKEPTIC = re.compile(r"^\s*\*\*(?:Скептик|Круг скептика)[^*]*\*\*")
ORIGIN = re.compile(r"^\s*\*\*Происхождение\.\*\*\s*(.*)$")
_W = r"A-Za-z0-9_А-Яа-яЁё"
FINDING = re.compile(r"(?<![%s])([HMНМ])-?(\d+)(?:(?:\s*[–-]\s*|—|\.\.)(?:[HMНМ])?-?(\d+))?(?![%s])" % (_W, _W))
LATIN = {"Н": "H", "М": "M"}
COMMIT = re.compile(r"(?<![0-9a-zA-Z])([0-9a-f]{7,40})(?![0-9a-zA-Z])")
PLACE = re.compile(r"^`?([^\s`;:]+):(\d+)")
SIBLINGS = re.compile(r"братьев\s+(\d+)\s*:\s*`([^`]+)`")
ROUTED = re.compile(r"^пунктом\s+(D\d+)\b")
ITEM = re.compile(r"^- \S+ \*\*D\d+\*\*")


QUOTES = {"«": "»", '"': '"', "`": "`", "„": "“"}


def findings(text):
    out = []
    for m in FINDING.finditer(text):
        # Номер в кавычках целиком — цитата примера («пишут «Н4», «М2»»), а не находка (сквозняк закрытием D1305).
        before, after = text[m.start() - 1:m.start()], text[m.end():m.end() + 1]
        if before in QUOTES and QUOTES[before] == after:
            continue
        lo, hi = int(m.group(2)), int(m.group(3) or m.group(2))
        letter = LATIN.get(m.group(1), m.group(1))
        for n in range(lo, hi + 1) if lo <= hi and hi - lo < 50 else [lo]:
            t = f"{letter}{n}"
            if t not in out:
                out.append(t)
    return out


def paragraphs(lines, head):
    """Тексты абзацев, открытых строкой `head`: строка и продолжение до следующей контрактной строки."""
    out, cur = [], None
    for ln in lines:
        if head.match(ln):
            if cur is not None:
                out.append(cur)
            cur = ln
        elif cur is not None and not CONTRACT.match(ln):
            cur += " " + ln.strip()
        elif cur is not None:
            out.append(cur)
            cur = None
    if cur is not None:
        out.append(cur)
    return out


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, encoding="utf-8",
                          errors="replace")


def item_has_root(root, ident):
    """Пункт D<N> есть в бэклоге или архиве и несёт строку «Корень.» — разбор живёт у него (скептик D1305, L3)."""
    head = re.compile(r"^- \S+ \*\*%s\*\*" % re.escape(ident))
    for name in ("BACKLOG.md", "BACKLOG-archive.md"):
        try:
            lines = open(os.path.join(root, name), encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            continue
        for i, ln in enumerate(lines):
            if head.match(ln):
                for nxt in lines[i + 1:]:
                    if ITEM.match(nxt):
                        break
                    if re.match(r"^\s*\*\*Корень\.\*\*", nxt):
                        return True
                return False
    return False


def verify(root, body, budget):
    """Причина отказа для строки происхождения либо '' (сверено) либо 'disowned'."""
    rest = body.split("—", 1)[1].strip() if "—" in body else ""
    if rest.startswith("не подтвердил"):
        why = rest.split(":", 1)[1].strip() if ":" in rest else ""
        return "disowned" if len(why) >= 10 else "«не подтвердилась» без довода через двоеточие"
    routed = ROUTED.match(rest)
    if routed:
        ident = routed.group(1)
        return "" if item_has_root(root, ident) else f"пункта {ident} с корнем нет ни в бэклоге, ни в архиве"
    c = COMMIT.search(rest)
    if not c:
        return "нет коммита, оставившего дыру"
    place = PLACE.match(rest[c.end():].strip())
    if not place:
        return f"не названо место «путь:строка», которое менял {c.group(1)}"
    path, line = place.group(1), int(place.group(2))
    if git(root, "cat-file", "-e", c.group(1) + "^{commit}").returncode != 0:
        return f"коммита {c.group(1)} в репозитории нет"
    if git(root, "cat-file", "-t", f"HEAD:{path}").stdout.strip() != "blob":
        return f"{path} — не файл нынешнего дерева"
    full = git(root, "rev-parse", c.group(1) + "^{commit}").stdout.strip()
    hist = git(root, "log", "--format=%H", "--no-patch", f"-L{line},{line}:{path}", "HEAD")
    if hist.returncode != 0:
        return f"строки {path}:{line} в нынешнем дереве нет"
    if full not in hist.stdout.split():
        return f"коммит {c.group(1)} не менял {path}:{line}"
    s = SIBLINGS.search(rest)
    if not s:
        return "нет поиска братьев: «братьев N: `команда`»"
    try:
        res = subprocess.run(["bash", "-c", s.group(2)], cwd=root, capture_output=True, timeout=budget,
                             env={**os.environ, "BACKLOG_CHECKS_NESTED": "1"})
    except subprocess.TimeoutExpired:
        return f"поиск братьев не уложился в {budget:g} с"
    got = sum(1 for x in res.stdout.decode("utf-8", "replace").splitlines() if x.strip())
    if got != int(s.group(1)):
        return f"поиск братьев дал {got} строк, записано {s.group(1)}"
    return ""


def main():
    if len(sys.argv) < 2:
        return 2
    root = sys.argv[1]
    try:
        budget = float(sys.argv[2]) if len(sys.argv) > 2 else 20.0
    except ValueError:
        budget = 20.0
    lines = sys.stdin.read().splitlines()
    named = []
    for p in paragraphs(lines, SKEPTIC):
        for t in findings(SKEPTIC.sub("", p, 1)):
            if t not in named:
                named.append(t)
    if not named:
        return 0
    if git(root, "rev-parse", "--git-dir").returncode != 0:
        return 2
    verdict = {}   # лучший исход у находки: сверено ("") < не подтвердилась < причина отказа
    rank = lambda w: 0 if w == "" else 1 if w == "disowned" else 2
    for p in paragraphs(lines, ORIGIN):
        body = ORIGIN.match(p).group(1)
        why = verify(root, body, budget)
        for t in findings(body.split("—", 1)[0]):
            if t not in verdict or rank(why) < rank(verdict[t]):
                verdict[t] = why
    for t in named:
        why = verdict.get(t, "нет строки «Происхождение»")
        if why == "disowned":
            print(f"disowned\t{t}")
        elif why:
            print(f"bad\t{t}\t{why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
