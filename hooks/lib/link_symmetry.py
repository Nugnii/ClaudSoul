"""Единый источник инварианта «ссылка кейс → родитель двусторонняя».

Результат: один ответ на вопрос «перечислен ли кейс в `source_cases` родителя» —
           для писателя встречных ссылок и для всех, кто эту симметрию проверяет
Проверка результата: bash hooks/tests/test_link_symmetry_lib.sh даёт 0

Зачем модуль (D312). До 5 сентября 2026 инвариант жил ТРЕМЯ копиями:
`hooks/knowledge-link-symmetry.sh` (писатель), `scripts/backlog-recheck.sh` (инвариант
D12) и `mcp-server/tests/test_knowledge_link_symmetry.py`. Две копии-прибора спрашивали
`имя_кейса not in текст_родителя` — вхождение подстроки по ВСЕМУ файлу. Имя кейса лежит
в файле родителя и помимо `source_cases`: в `provenance_log.trigger_case`, в `related`,
в прозе. Замер 5 сентября 2026: приборы показывали 1 нарушение там, где разбор поля даёт
18; выборочная проверка трёх подтвердила все три.

Избыточность двух приборов была МНИМОЙ: код в них совпадал дословно, то есть это был
один прибор в двух копиях, и ошибались они согласованно. Независимость восстанавливается
не копией кода, а собственным отрицательным контролем у каждого потребителя.

НАЗВАННЫЙ ПРЕДЕЛ: без PyYAML разбор невозможен, и `source_cases()` возвращает None —
«не смог», а не «пусто». Потребитель обязан различить эти два исхода (род B реестра
дефектов); молча подставлять пустой список нельзя.
Условие снятия: PyYAML станет обязательной зависимостью установки либо разбор frontmatter
перейдёт на собственный разборщик.
"""

import re
from pathlib import Path

try:
    import yaml
except ImportError:  # разбора нет — потребитель узнает об этом по None, а не по нулю
    yaml = None

# Виды рёбер, объявляющие родительство. `knowledge/META.md` перечисляет их как связь
# кейса с паттерном или принципом; `instance_of` в договор не входит намеренно.
PARENT_KINDS = ("confirms", "specializes", "extends", "generalizes")


def frontmatter(text):
    """Тело frontmatter или None, если его нет. Вне его не судим ни о чём: строка
    `source_cases:` встречается и в прозе знания, объясняющего само поле."""
    if not text.startswith("---"):
        return None
    m = re.search(r"^---[ \t]*$", text[3:], re.M)
    return text[3 : 3 + m.start()] if m else None


_FM_KEY = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):[ \t]*(.*)$")
_FM_ITEM = re.compile(r"^[ \t]*-[ \t]*(.*)$")


def _unquote(v):
    """Снятие кавычек с разэкранированием, как это делает PyYAML: в двойных кавычках
    `\\"` значит кавычку, `\\\\` — обратную косую; в одинарных удвоенная кавычка значит
    одну. Поймано положительным контролем на `pattern-shell-portability`, где кейс
    прозой несёт `\\"$SEMGREP\\"` внутри значения."""
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        body = v[1:-1]
        if v[0] == '"':
            return body.replace('\\"', '"').replace("\\\\", "\\")
        return body.replace("''", "'")
    return v


def _strip_comment(v):
    """Хвостовой комментарий YAML: `#` ПОСЛЕ пробела и вне кавычек. Формы взяты из живой
    базы: `- led_to: case-x.md  # этот случай — engineering follow-on` (13 сентября 2026)."""
    v = v.strip()
    if v[:1] in "\"'":
        return v
    i = v.find(" #")
    return v[:i].strip() if i >= 0 else v


def _scalar_or_pair(body):
    """Элемент списка: пара «вид: цель» — словарём, поточное отображение — словарём,
    прочее — строкой. Так же, как это делает PyYAML на формах живой базы."""
    body = body.strip()
    if body.startswith("{") and body.endswith("}"):
        out = {}
        for part in _split_flow(body[1:-1]):
            mk = _FM_KEY.match(part.strip())
            if not mk:
                return body
            out[mk.group(1)] = _unquote(_strip_comment(mk.group(2)))
        return out
    if body.startswith(("\"", "'")):
        return _unquote(body)
    mk = _FM_KEY.match(body)
    if mk:
        return {mk.group(1): _unquote(_strip_comment(mk.group(2)))}
    return _unquote(_strip_comment(body))


def _split_flow(inner):
    """Элементы поточного списка. Вложенные `{...}`/`[...]` и запятые ВНУТРИ КАВЫЧЕК не
    режутся: в живой базе `note` несёт прозу с запятыми и двоеточиями
    (`case-2026-08-08-fabricated-time-canary`), и наивное деление рвало отображение
    на куски."""
    out, depth, buf, quote = [], 0, "", ""
    for ch in inner:
        if quote:
            buf += ch
            if ch == quote:
                quote = ""
            continue
        if ch in "\"'":
            quote = ch
            buf += ch
            continue
        if ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(buf)
            buf = ""
        else:
            buf += ch
    if buf.strip():
        out.append(buf)
    return [x for x in out if x.strip()]


def _fallback_meta(fm):
    """Разбор БЕЗ PyYAML — ТОЛЬКО двух полей, ради которых модуль существует
    (`source_cases` и `edges`). Возвращает словарь либо None.

    Зачем (13 сентября 2026). Инвариант D12 непроверяем не «сегодня», а ПО УСТРОЙСТВУ:
    в рамке периодического прогона `python3` — это /usr/bin/python3 (3.9.6, Xcode CLT),
    где PyYAML нет, и он нигде не объявлен зависимостью. Замер в день правки: прямой
    прогон в оболочке владельца отвечал «7 инвариантов, все держатся», а тот же прогон
    с `env -i PATH=/usr/bin:/bin` — «? D12: 389 родителей не разобрать». Прибор не мог
    ответить на свой вопрос именно там, где ходит сам, — и это неотличимо от чистоты для
    всякого, кто читает только число.

    ОТКАЗ ВМЕСТО ДОГАДКИ. Незнакомая форма внутри этих двух полей даёт None, а не частичный
    разбор: запасной путь, который «почти разбирает», превратил бы честное «не проверено»
    в ложное «чисто» — исход хуже нынешнего. Всё, что вне двух полей, не разбирается вовсе
    и на результат не влияет.

    НАЗВАННЫЙ ПРЕДЕЛ: многострочная поточная форма (`[` без `]` на той же строке), скаляр
    вместо списка и вложенные отображения внутри этих полей не узнаются — отказ.
    Положительный контроль: `hooks/tests/test_link_symmetry_lib.sh` прогоняет оба разбора
    по ЖИВОЙ базе и требует совпадения на всех файлах.
    Условие снятия: в рабочей базе появится запись в одной из этих форм — положительный
    контроль покраснеет первым.
    """
    out = {}
    lines = fm.split("\n")
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        m = _FM_KEY.match(line)
        if not m:
            i += 1
            continue
        key, rest = m.group(1), m.group(2).strip()
        if key not in ("source_cases", "edges"):
            i += 1
            continue
        if rest.startswith("["):
            rest = _strip_comment(rest)
            if not rest.endswith("]"):
                return None
            inner = rest[1:-1].strip()
            # Поточный список несёт ПАРЫ: `edges: [similar_to: case-x.md, ...]` —
            # PyYAML делает из каждого элемента отображение, и запасной путь обязан
            # совпасть, иначе рёбра станут строками и разбор молча потеряет их.
            out[key] = [] if not inner else [_scalar_or_pair(x) for x in _split_flow(inner)]
            i += 1
            continue
        if rest:
            return None
        items = []
        i += 1
        while i < n:
            li = lines[i]
            # Пустая строка и КОММЕНТАРИЙ внутри блока список не заканчивают: в живой базе
            # между элементами `edges` стоят пояснения (`case-2026-06-09-mcp-wrapper-lags-library`),
            # и обрыв на них терял второй элемент молча.
            if not li.strip() or li.lstrip().startswith("#"):
                i += 1
                continue
            mi = _FM_ITEM.match(li)
            if not mi:
                break
            body = mi.group(1).strip()
            if body.startswith("[") and body.endswith("]"):
                items.append([_scalar_or_pair(x) for x in _split_flow(body[1:-1].strip())])
            else:
                items.append(_scalar_or_pair(body))
            i += 1
        out[key] = items
    return out


def _meta(text):
    """Разобранный frontmatter словарём. None — РАЗОБРАТЬ НЕ УДАЛОСЬ (нет frontmatter,
    битый YAML, корень не словарь, незнакомая форма при разборе без PyYAML). Один разбор
    на обе стороны связи. Без PyYAML работает запасной разбор двух полей — см.
    `_fallback_meta`: инвариант обязан отвечать в той рамке, где ходит сам."""
    fm = frontmatter(text)
    if fm is None:
        return None
    if yaml is None:
        return _fallback_meta(fm)
    try:
        meta = yaml.safe_load(fm) or {}
    except Exception:
        return None
    return meta if isinstance(meta, dict) else None


def source_cases(parent_text):
    """Список `source_cases` родителя. None — РАЗОБРАТЬ НЕ УДАЛОСЬ (нет PyYAML, нет
    frontmatter, битый YAML, значение не список). Пустой список — разобрали, и он пуст."""
    meta = _meta(parent_text)
    if meta is None:
        return None
    v = meta.get("source_cases")
    if v is None:
        return []
    if not isinstance(v, list):
        return None
    return [str(x).strip() for x in v]


def listed(parent_text, case_name):
    """Перечислен ли кейс в `source_cases` родителя. None — разобрать не удалось."""
    sc = source_cases(parent_text)
    if sc is None:
        return None
    return case_name in sc


def is_parent_name(name):
    """Родителем бывает паттерн или принцип. Ребро кейс → кейс законно, но встречной
    записи в `source_cases` не требует: там это поле значит другое."""
    return name.startswith("pattern-") or name.startswith("principle-")


def _parent_file(target):
    """Имя файла родителя из цели ребра. Путь схлопывается, `.md` дописывается: договор
    (`knowledge/META.md:161-165`) говорит «имя родителя» и расширения не требует."""
    name = str(target).strip().split("/")[-1]
    return name if name.endswith(".md") else name + ".md"


def parent_edges(case_text):
    """Рёбра кейса на родителей: [(вид, имя файла)], только виды родительства и только
    имена родителей.

    Читается ТЕМ ЖЕ разбором поля, каким читается `source_cases` родителя (D319). До
    6 сентября 2026 здесь стоял шаблон строки, требовавший от цели окончания `.md`, —
    один модуль читал две стороны одной связи двумя разными способами. Замер по рабочей
    базе в тот день: рёбер родительства 222, шаблон видел 190, невидимых 32 (14%). «Не
    распознал ребро» неотличимо от «нарушений нет».

    НАЗВАННЫЙ ПРЕДЕЛ: элемент `edges`, записанный не парой «вид: цель» (строкой
    `- "confirms: p.md"` или списком `- [specializes, p]`), ребром не считается — это
    дефект записи, а не форма договора. В рабочей базе таких 3 из 225, и прежний шаблон
    их тоже не видел. Отказ разбора всего поля виден отдельно — через `_meta`.
    Условие снятия: записей такой формы в рабочей базе не останется — тогда отказ на них
    можно сделать громким.

    ВОЗВРАТ: None — РАЗОБРАТЬ НЕ УДАЛОСЬ (нет PyYAML, нет frontmatter, битый YAML).
    Пустой список — разобрали, и рёбер на родителей нет.
    """
    meta = _meta(case_text)
    if meta is None:
        # None, а не []: «разобрать не удалось» и «рёбер нет» — разные исходы, и пустой
        # список между ними не различает (род B). Контракт тот же, что у соседа
        # `source_cases` тридцатью строками ниже; до 9 сентября 2026 он был только у него,
        # и писатель встречных ссылок (`hooks/knowledge-link-symmetry.sh`) молчал при
        # отказе разбора, выдавая молчание за «дописывать нечего» (D333).
        return None
    v = meta.get("edges")
    if not isinstance(v, list):
        return []
    out = []
    for item in v:
        if not isinstance(item, dict):
            continue
        for kind, target in item.items():
            if kind not in PARENT_KINDS or not isinstance(target, str) or not target.strip():
                continue
            name = _parent_file(target)
            if is_parent_name(name):
                out.append((kind, name))
    return out


def asymmetric(lessons_dir):
    """Односторонние ссылки: [(кейс, вид, родитель)].

    Возвращает пару (нарушения, неразобранные). Второе — файлы, чей frontmatter
    разобрать не удалось: родитель со своим `source_cases` и кейс со своими `edges`.
    Они НЕ засчитываются ни в нарушения, ни в порядок, и потребитель обязан назвать их
    отдельно, иначе отказ разбора выглядит как чистота.
    """
    d = Path(lessons_dir)
    parents = {}
    for p in list(d.glob("pattern-*.md")) + list(d.glob("principle-*.md")):
        parents[p.name] = p.read_text(errors="replace")

    bad, unread = [], set()
    for c in sorted(d.glob("case-*.md")):
        text = c.read_text(errors="replace")
        # Снятое с учёта знание основанием паттерна не считается.
        if "DEPRECATED" in text[:2000]:
            continue
        # Рёбра читаются разбором, и его отказ — не «рёбер нет» (род B): без этой ветки
        # отсутствие PyYAML давало бы (0, 0), то есть чистоту вместо «не проверено».
        if _meta(text) is None:
            unread.add(c.name)
            continue
        for kind, target in (parent_edges(text) or []):
            if target not in parents:
                continue
            seen = listed(parents[target], c.name)
            if seen is None:
                unread.add(target)
            elif not seen:
                bad.append((c.name, kind, target))
    return bad, sorted(unread)
