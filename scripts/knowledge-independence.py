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

LESSONS = pathlib.Path(os.environ.get("LESSONS_DIR", pathlib.Path.home() / ".claude/global-lessons"))
MIN_CONF = int(os.environ.get("INDEPENDENCE_MIN_CONFIDENCE", "4"))
MIN_TRACED_PCT = int(os.environ.get("INDEPENDENCE_MIN_TRACED_PCT", "70"))
MARK_UNTRACED = "--mark-untraced" in sys.argv

if not LESSONS.is_dir():
    print(f"knowledge-independence: нет базы {LESSONS}", file=sys.stderr)
    sys.exit(2)

rows = []
for f in sorted(LESSONS.glob("*.md")):
    text = f.read_text(errors="ignore")
    m = re.search(r"^confidence:\s*(\d+)", text, re.M)
    if not m:
        continue
    conf = int(m.group(1))
    if conf < MIN_CONF:
        continue
    cc = re.search(r"^confirmed_count:\s*(\d+)", text, re.M)
    claimed = int(cc.group(1)) if cc else 0
    dates = re.findall(r"^\s+-\s+date:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})", text, re.M)
    rows.append({"name": f.stem, "conf": conf, "claimed": claimed,
                 "logged": len(dates), "days": len(set(dates))})

if not rows:
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
    return set(re.findall(r"^\s+session:\s*(\S+)", text, re.M))

single_source = []
for f in sorted(LESSONS.glob("*.md")):
    text = f.read_text(errors="ignore")
    m = re.search(r"^confidence:\s*(\d+)", text, re.M)
    if not m or int(m.group(1)) < 4:
        continue
    sess = sessions_of(text)
    if len(sess) == 1:
        single_source.append(f.stem)

if single_source:
    print()
    print(f"Знания confidence >= 4, все записанные подтверждения которых из ОДНОЙ сессии: {len(single_source)}")
    for name in single_source[:10]:
        print(f"  · {name}")
    print("  Выше четвёрки такой рост опирается на одно наблюдение, повторённое несколько раз.")

if MARK_UNTRACED:
    marked = []
    for f in sorted(LESSONS.glob("*.md")):
        text = f.read_text(errors="ignore")
        m = re.search(r"^confidence:\s*(\d+)", text, re.M)
        if not m or int(m.group(1)) < MIN_CONF:
            continue
        cc = re.search(r"^confirmed_count:\s*(\d+)", text, re.M)
        claimed = int(cc.group(1)) if cc else 0
        logged = len(re.findall(r"^\s+-\s+date:\s*[0-9-]+", text, re.M))
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
        text = re.sub(r"^status:", "provenance_traced: low\nstatus:", text, count=1, flags=re.M)
        f.write_text(text)
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
