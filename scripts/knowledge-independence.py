#!/usr/bin/env python3
# Результат: у подтверждений записан повод: доля прослеживаемых не ниже порога
# Проверка результата: python3 scripts/knowledge-independence.py даёт 0
#
"""knowledge-independence.py — на чём стоит confidence знания: на событиях или на источниках.

Повод (D81). `confirmed_count` считает СОБЫТИЯ, а не независимые источники. Пять
подтверждений могут оказаться пятью проявлениями одной первой ошибки — тогда счётчик
меряет корреляцию, а confidence растёт на самоподтверждении. Контур замкнут: гипотезу
порождает агент, evidence производит агент, evidence оценивает агент.

Материал для проверки уже есть — `provenance_log` в каждом знании несёт повод каждого
подтверждения. Недостающим была метрика, и это она.

Что меряется, по знаниям с confidence >= порога:
  · доля подтверждений, у которых вообще есть запись в provenance_log — без записи
    независимость непроверяема в принципе;
  · сколько различимых дней стоит за записями: несколько записей одной датой это один
    инцидент, а не несколько независимых наблюдений;
  · знания, где заявленный счёт сильно оторван от записанного провенанса.

Оговорка о том, что метрика НЕ доказывает: разные дни не равны независимым источникам.
Один агент в одном проекте может подтвердить знание трижды за три дня из одной причины.
День — нижняя граница различимости, а не мера независимости; настоящая независимость
требует разных доменов и разных типов повода, и её здесь нет.

Код возврата: 0 — доля подтверждений со следом >= порога; 1 — ниже порога (находка);
2 — не смог отработать.
"""
import os
import re
import sys
import pathlib

# Общий замок (род H). База знаний — файл не одного писателя: её правят этот скрипт,
# хук `knowledge-link-symmetry.sh` (под оболочечным замком на тот же каталог),
# `knowledge-counter-bump.sh` и `/learn`. Ниже открыто окно read→write по каждому файлу
# знания, и без замка встречная правка гибнет молча. Протокол один на оба языка —
# `hooks/lib/state_lock.py` и `hooks/state-lock-lib.sh`.
_LIB = pathlib.Path(__file__).resolve().parent.parent / "hooks" / "lib"
if not (_LIB / "state_lock.py").exists():
    _LIB = pathlib.Path.home() / ".claude/hooks/lib"
sys.path.insert(0, str(_LIB))
try:
    from state_lock import with_lock
except ImportError:  # библиотеки нет — работаем как прежде, замок улучшает, а не требуется
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):
        yield False

# Провенанс читается РАЗБОРОМ, а не построчным шаблоном (род A реестра дефектов).
# `- date:` лежит и в `provenance_log`, и в `modification_history`; шаблон
# `^\s+-\s+date:` привязан к началу строки и родителя не видит. Замер 6 сентября 2026 на
# живой базе: 143 записи повода по шаблону при 125 настоящих — 18 дат заняты у перекроек
# правила, доля прослеживаемых 58% вместо 51%. Ошибка благоприятная: прибор, созданный
# ловить самоподтверждение, занижал собственную находку.
# Границу шапки берём у `link_symmetry` — она там уже одна на всех (D312), и `source_cases:`
# в прозе знания её ловушку уже проходило.
try:
    import yaml
except ImportError:  # разбора нет — потребитель узнает об этом по None, а не по нулю
    yaml = None
try:
    from link_symmetry import frontmatter
except ImportError:
    frontmatter = None


def provenance(text):
    """Записи `provenance_log`. None — РАЗОБРАТЬ НЕ УДАЛОСЬ (нет PyYAML, нет библиотеки
    границы, нет шапки, битый YAML, значение не список). Пустой список — разобрали, и он
    пуст. Ноль вместо None здесь запрещён (род B): «не смог» неотличим от «повода нет»,
    а неотличимость выбирает благоприятное."""
    if yaml is None or frontmatter is None:
        return None
    fm = frontmatter(text)
    if fm is None:
        return None
    try:
        meta = yaml.safe_load(fm) or {}
    except Exception:
        return None
    if not isinstance(meta, dict):
        return None
    v = meta.get("provenance_log")
    if v is None:
        return []
    return v if isinstance(v, list) else None


def _entry_field(entries, key):
    return [str(e[key]) for e in entries
            if isinstance(e, dict) and e.get(key) not in (None, "")]


LESSONS = pathlib.Path(os.environ.get("LESSONS_DIR", pathlib.Path.home() / ".claude/global-lessons"))
MIN_CONF = int(os.environ.get("INDEPENDENCE_MIN_CONFIDENCE", "4"))
MIN_TRACED_PCT = int(os.environ.get("INDEPENDENCE_MIN_TRACED_PCT", "70"))
# Перечень режимов ОБЪЯВЛЕН, неузнанное отбивается кодом 2 ДО замера и ДО пометки (D320).
# Прежде опечатка `--mark-untrace` отрабатывала как обычный замер с кодом 0, и отличить
# «пометил» от «не понял флаг» снаружи было нечем — работа молча не делалась.
_MODES = {"--mark-untraced": "проставить пометку untraced знаниям без прослеживаемого повода"}
_args = sys.argv[1:]
if "--help" in _args or "-h" in _args:
    print("usage: knowledge-independence.py [--mark-untraced]\n\nРежимы:")
    for _k, _v in _MODES.items():
        print(f"  {_k:18} {_v}")
    print("  (без аргументов)   только замер, в базу не пишет")
    raise SystemExit(0)
_unknown = [a for a in _args if a not in _MODES]
if _unknown:
    print(f"неизвестный аргумент: {' '.join(_unknown)}", file=sys.stderr)
    print(f"известные: {' '.join(_MODES)} (или без аргументов — только замер)", file=sys.stderr)
    raise SystemExit(2)
MARK_UNTRACED = "--mark-untraced" in _args

if not LESSONS.is_dir():
    print(f"knowledge-independence: нет базы {LESSONS}", file=sys.stderr)
    sys.exit(2)

# ПЕРЕЧЕНЬ ФАЙЛОВ — ОДИН ИСТОЧНИК НА ВЕСЬ СКРИПТ (7 сентября 2026, род L).
# Предмет замера — provenance_log, поле ОПЕРАЦИОННОЙ схемы: у entity/fact/relation его нет
# ни в одном файле, а confidence там означает надёжность источника, а не уверенность в
# правиле. До правки обход брал всю базу трижды, и в заголовочный счёт «знаний с
# confidence >= 4» попадали 2 записи второго контура из 20 (10%). Три копии фильтра
# разошлись бы молча — потому функция одна (род K).
OPERATIONAL_PREFIXES = ("case-", "pattern-", "principle-")


def operational_files():
    return [f for f in sorted(LESSONS.glob("*.md"))
            if f.name.startswith(OPERATIONAL_PREFIXES)]


rows = []
unparsed = []
for f in operational_files():
    text = f.read_text(errors="ignore")
    m = re.search(r"^confidence:\s*(\d+)", text, re.M)
    if not m:
        continue
    conf = int(m.group(1))
    if conf < MIN_CONF:
        continue
    cc = re.search(r"^confirmed_count:\s*(\d+)", text, re.M)
    claimed = int(cc.group(1)) if cc else 0
    entries = provenance(text)
    if entries is None:
        unparsed.append(f.stem)
        continue
    dates = _entry_field(entries, "date")
    rows.append({"name": f.stem, "conf": conf, "claimed": claimed,
                 "logged": len(dates), "days": len(set(dates))})

if not rows:
    # «Нечем разобрать» и «нечего разбирать» — разные исходы, и код 2 у них общий. Без этой
    # ветки отсутствие PyYAML печаталось как «ни одного знания с confidence >= 4» на базе,
    # где таких знаний двадцать: сбой прибора в одежде замера.
    if unparsed:
        print(f"knowledge-independence: не разобрана шапка ни у одного из {len(unparsed)} "
              f"знаний (нет PyYAML либо битый frontmatter) — замер не выполнен", file=sys.stderr)
    else:
        print(f"knowledge-independence: ни одного знания с confidence >= {MIN_CONF}", file=sys.stderr)
    sys.exit(2)

claimed = sum(r["claimed"] for r in rows)
logged = sum(r["logged"] for r in rows)
days = sum(r["days"] for r in rows)
traced_pct = logged * 100 // claimed if claimed else 0
no_prov = [r for r in rows if r["logged"] == 0 and r["claimed"] > 0]

print(f"Знаний с confidence >= {MIN_CONF}: {len(rows)}")
print(f"  подтверждений заявлено   : {claimed}")
print(f"  записано в provenance_log: {logged} ({traced_pct}%)")
print(f"  различимых дней за ними  : {days}")
print(f"  без единой записи повода : {len(no_prov)} знани(й)")
if unparsed:
    print(f"  НЕ РАЗОБРАНО (в счёт не вошли): {len(unparsed)} — {', '.join(unparsed[:5])}")
print()
print("Наибольший отрыв заявленного счёта от записанного повода:")
gap = sorted(rows, key=lambda r: r["claimed"] - r["logged"], reverse=True)[:8]
print(f"  {'знание':<50} {'conf':>4} {'заявл':>6} {'запис':>6} {'дней':>5}")
for r in gap:
    print(f"  {r['name'][:50]:<50} {r['conf']:>4} {r['claimed']:>6} {r['logged']:>6} {r['days']:>5}")

# --- Правило роста выше confidence 4 (D81, решение владельца 2026-08-26) ---
#
# До четвёрки хватает событий: знание набирает вес тем, что срабатывает. Выше — нужен
# ДРУГОЙ повод, иначе confidence растёт на самоподтверждении: пять подтверждений из
# одной сессии это одно наблюдение, повторённое пять раз.
#
# Механизм здесь — называние, а не запрет, и это честная граница. Сам `confidence`
# скрипт `knowledge-counter-bump.sh` не трогает: счётчик механический, а уровень
# уверенности агент ставит рукой. Блокировать нечего, поэтому нарушители перечисляются
# поимённо, а не «предотвращаются» текстовым правилом (principle-knowledge-in-the-world:
# уровень 1 хрупок, но третий уровень тут недостижим по конструкции — признаём прямо).
#
# Сессии в провенансе появились 2026-08-26, поэтому у старых записей их нет: знание
# без единой сессии в логе не нарушитель, а непроверяемое — так и печатается.
def sessions_of(text):
    """Сессии ПОДТВЕРЖДЕНИЙ. `session:` встречается и в записи перекройки правила —
    чужая сессия оттуда превращала односессионное знание в многосессионное и снимала
    находку. None — разобрать не удалось."""
    entries = provenance(text)
    if entries is None:
        return None
    return set(_entry_field(entries, "session"))

single_source = []
for f in operational_files():
    text = f.read_text(errors="ignore")
    m = re.search(r"^confidence:\s*(\d+)", text, re.M)
    if not m or int(m.group(1)) < 4:
        continue
    sess = sessions_of(text)
    if sess is not None and len(sess) == 1:
        single_source.append(f.stem)

if single_source:
    print()
    print(f"Знания confidence >= 4, все записанные подтверждения которых из ОДНОЙ сессии: {len(single_source)}")
    for name in single_source[:10]:
        print(f"  · {name}")
    print("  Выше четвёрки такой рост опирается на одно наблюдение, повторённое несколько раз.")

if MARK_UNTRACED:
    marked = []
    # Замок ПОФАЙЛОВЫЙ, и это не вкус, а условие работоспособности: взаимное исключение
    # живёт на общем ИМЕНИ. `mkdir global-lessons.lock` и `mkdir <файл>.lock` — разные
    # каталоги, друг друга не блокируют ни в одну сторону, а обе стороны при этом считают
    # себя защищёнными. Замер 5 сентября 2026: у базы знаний было ТРИ имени замка —
    # `knowledge-link-symmetry.sh` брал каталог, `knowledge-audit-digest.sh` через
    # `atomic_filter` берёт файл, `knowledge-counter-bump.sh` не брал ничего. Сведено к
    # пофайловому: писатели трогают отдельные записи, а каталожный замок сериализует всю
    # базу разом и с пофайловым не складывается.
    for f in operational_files():
        text = f.read_text(errors="ignore")
        m = re.search(r"^confidence:\s*(\d+)", text, re.M)
        if not m or int(m.group(1)) < MIN_CONF:
            continue
        cc = re.search(r"^confirmed_count:\s*(\d+)", text, re.M)
        claimed = int(cc.group(1)) if cc else 0
        entries = provenance(text)
        if entries is None:
            continue                     # не разобрали — не помечаем: пометка необратима
        logged = len(_entry_field(entries, "date"))
        if claimed == 0:
            continue
        if logged * 100 // claimed >= MIN_TRACED_PCT:
            continue
        # Отдельное поле, а НЕ `fragile`. Флаг `fragile` уже занят другим смыслом:
        # META.md ставит его при 3+ перекройках правила, и он блокирует промоушен
        # паттерна в принцип и множит `source_factor` на 1.2. Пометив им непрослеживаемые
        # подтверждения, мы молча изменили бы поведение промоушена у четырёх паттернов —
        # проверено и откачено 2026-08-26. Перегружать флаг с последствиями нельзя.
        if re.search(r"^provenance_traced:", text, re.M):
            continue
        # Окно read→write по ОДНОМУ файлу: перечитываем под замком, иначе правка ляжет
        # поверх версии, прочитанной до чужой записи.
        with with_lock(str(f)):
            fresh = f.read_text(errors="ignore")
            if re.search(r"^provenance_traced:", fresh, re.M):
                continue
            f.write_text(re.sub(r"^status:", "provenance_traced: low\nstatus:",
                                fresh, count=1, flags=re.M))
        marked.append(f.stem)
    print()
    print(f"Помечено provenance_traced: low — {len(marked)}")
    for name in marked:
        print(f"  · {name}")
elif traced_pct < MIN_TRACED_PCT:
    print()
    print("Пометить знания с непрослеживаемыми подтверждениями: --mark-fragile "
          "(правит базу, поэтому только по явному флагу)")

print()
if traced_pct < MIN_TRACED_PCT:
    print(f"⚠️ у {100 - traced_pct}% подтверждений нет записанного повода — независимость "
          f"этих подтверждений непроверяема, а confidence на них уже стоит")
    print("[замер: находки, не сбой] — ненулевой код здесь — вердикт замера, а не сбой (D95)")
    sys.exit(1)
print(f"✅ след повода есть у {traced_pct}% подтверждений (порог {MIN_TRACED_PCT}%)")
sys.exit(0)
