#!/usr/bin/env python3
# Результат: ПРИБОР, не инструмент. Заражённость словарей сенсоров. Решение, которое оно меняет: какие словари чинить вырезанием цитат, а какие переписывать (D88); срок — при появлении нового языкового сенсора
# Проверка результата: python3 scripts/meta-contamination.py — таблица заражённости напечатана
#
"""Замер рефлексивного заражения сенсоров: как часто словарь языкового детектора
срабатывает на текстах, которые сам же проект породил, разбирая работу этих детекторов.

Вопрос не «правильно ли сенсор распознаёт состояние собеседника», а «считает ли он
собственный метадискурс объектным сигналом». Ground truth не нужен: корпус по построению
состоит из разбора срабатываний, ожидаемый сигнал везде — «нет».

Различаются два вида заражения (формулировка внешней рецензии 2026-08-26):
  · лексическое — маркер попадает в текст как ЦИТАТА самого маркера; лечится вырезанием
    цитат, и в разборе виден как совпадение внутри кавычек, backtick'ов, «ёлочек»;
  · семантическое — слово приходит естественно, без цитирования; вырезание цитат его не
    берёт, потому что словарь сенсора пересекается с обычной лексикой.

Повод: BACKLOG D87/D88. Запуск: python3 scripts/meta-contamination.py
"""
import io, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOKS = os.path.join(REPO, "hooks")
LESSONS = os.path.expanduser("~/.claude/global-lessons")


def _read(path):
    try:
        return io.open(path, encoding="utf-8").read()
    except OSError:
        return ""


def bash_array(filename, name):
    """Строки из bash-массива NAME=( "a" "b" ) — словарь сенсора как он есть в коде."""
    m = re.search(rf"{name}=\((.*?)\n\)", _read(os.path.join(HOOKS, filename)), re.S)
    return re.findall(r'"([^"]+)"', m.group(1)) if m else []


def bash_regexes(filename):
    """Регулярные выражения из вызовов grep -qiE '(...)' — словари классификатора."""
    return re.findall(r"grep -qiE '\((.*?)\)'", _read(os.path.join(HOOKS, filename)))


def sensors():
    out = {}
    for label, (f, name) in {
        "reformulation:CORRECTION": ("reformulation-tracker.sh", "CORRECTION_PATTERNS"),
        "reformulation:FORWARD": ("reformulation-tracker.sh", "REFORMULATION_PATTERNS"),
        "itr-event:DECLINE": ("itr-event-detector.sh", "DECLINE_MARKERS"),
        "itr-event:CORRECTION": ("itr-event-detector.sh", "CORRECTION_MARKERS"),
    }.items():
        words = bash_array(*f_name) if (f_name := (f, name)) else []
        if words:
            out[label] = ("words", words)
    m = re.search(r"^CORRECTION_REGEX='(.+)'$", _read(os.path.join(HOOKS, "user-correction-guard.sh")), re.M)
    if m:
        out["correction-guard:LEXICAL"] = ("regex", [m.group(1)])
    for i, rx in enumerate(bash_regexes("intrusiveness-classify-lib.sh"), 1):
        out[f"classify:{i:02d}"] = ("regex", [rx])
    return out


def corpus():
    """Тексты, порождённые разбором работы самих детекторов."""
    items = {}
    session = _read(os.path.join(REPO, "SESSION.md"))
    tail = session[-40000:]
    if tail:
        items["SESSION.md (хвост)"] = tail
    for rel in ("BACKLOG.md", "BACKLOG-archive.md", "CHANGELOG.md"):
        t = _read(os.path.join(REPO, rel))
        if t:
            items[rel] = t[-40000:]
    if os.path.isdir(LESSONS):
        for fn in sorted(os.listdir(LESSONS)):
            if not fn.endswith(".md"):
                continue
            t = _read(os.path.join(LESSONS, fn))
            if re.search(r"detector|детектор|ложн[оы]|false.positive|сенсор", t, re.I):
                items[f"знание/{fn}"] = t
    return items


QUOTE = re.compile(r"«[^»]{0,80}»|\"[^\"]{0,80}\"|`[^`]{0,80}`|„[^“]{0,80}“")


def scan(kind, pats, text):
    """Возвращает (всего, внутри цитат, примеры вне цитат)."""
    low, spans, total, quoted, free = text.lower(), [m.span() for m in QUOTE.finditer(text)], 0, 0, set()
    for p in pats:
        if kind == "words":
            rx = r"(?<![а-яёa-z])" + re.escape(p) + r"(?![а-яёa-z])"
        else:
            rx = p.replace("[[:space:]]", r"\s")
        try:
            found = list(re.finditer(rx, low))
        except re.error:
            continue
        for m in found:
            total += 1
            if any(a <= m.start() < b for a, b in spans):
                quoted += 1
            else:
                free.add(m.group(0))
    return total, quoted, free


def main():
    docs, sens = corpus(), sensors()
    if not docs or not sens:
        print("нет корпуса или словарей — проверь пути", file=sys.stderr)
        return 1
    rows = []
    for label, (kind, pats) in sens.items():
        files = total = quoted = 0
        free = set()
        for text in docs.values():
            t, q, f = scan(kind, pats, text)
            if t:
                files += 1
            total, quoted = total + t, quoted + q
            free |= f
        rows.append((total - quoted, total, quoted, files, label, sorted(free)[:4]))
    rows.sort(reverse=True)
    print(f"корпус: {len(docs)} документов, {sum(len(t) for t in docs.values())} символов; "
          f"сенсоров: {len(sens)}; ожидаемый сигнал везде — нет\n")
    print(f"{'сенсор':<26} {'семант.':>8} {'всего':>6} {'цитаты':>7} {'докум.':>7}  примеры вне цитат")
    print("-" * 96)
    for semantic, total, quoted, files, label, ex in rows:
        if not total:
            continue
        print(f"{label:<26} {semantic:>8} {total:>6} {quoted:>7} {files:>7}  {', '.join(ex)}")
    silent = [r[4] for r in rows if not r[1]]
    if silent:
        print(f"\nни разу не сработали ({len(silent)}): {', '.join(silent)}")
    print("\nСемантическое заражение — то, которое не лечится вырезанием цитат.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
