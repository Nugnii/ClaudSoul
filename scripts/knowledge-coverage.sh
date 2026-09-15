#!/usr/bin/env bash
# knowledge-coverage.sh — у каждого знания старше недели есть подача либо названная причина.
#
# Результат: доля базы, доходящей до контекста, разложена по причинам, и остаток без
#            причины равен нулю
# Проверка результата: bash scripts/knowledge-coverage.sh даёт 0, когда необъяснённых нет
#
# Зачем (D248). Замера покрытия базы не было ни одного, и число «сколько знаний не доходит
# до контекста» трижды называлось на разных знаменателях: 341, потом 168 из 426, потом 171,
# потом 74 у стороннего критика. Все четыре считались верно и о РАЗНЫХ величинах — счёт шёл
# то по всей базе с двумя контурами, то по одному, то по уникальным строкам журнала.
#
# ЕДИНИЦА ОБЪЯВЛЕНА ЗДЕСЬ: знаменатель — operational-контур (case/pattern/principle) в
# `~/.claude/global-lessons`; второй контур (entity/fact/relation) идёт своим каналом
# кросс-контурных упоминаний и в это число не входит.
#
# НАЗВАННЫЙ ПРЕДЕЛ ПРИБОРА: `knowledge-activator` пишет в журнал ТОЛЬКО top-6 кандидатов
# (его шапка, строка 23). Поэтому «нет записи в журнале» означает «ни разу не вошло в
# шестёрку», а НЕ «не рассматривалось»: хвост оценки не наблюдаем вовсе. Отличить
# «оценивалось и проиграло» от «не оценивалось» можно только реплеем отбора — прибора для
# этого нет, и пока его нет, отсутствие записи объясняется рангом, а не мёртвым грузом.
# Условие снятия: предел держится, пока журнал `knowledge-activator` хранит только
# ПОДАННОЕ. Начнёт он писать весь оценённый набор с рангом — или появится реплей отбора, —
# и «нет записи» станет отличимо от «не оценивалось»; тогда объяснять отсутствие рангом
# станет незаконно, и знаменатель придётся пересчитать на наблюдаемом хвосте.
set -uo pipefail
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
# Нечем проверить — код 2 «не измерено», а не 0 «объяснено»: нулевой код читался реестром
# замеров как успех при отсутствующей базе и без python3 (прожарка 13 сентября 2026, атака 2).
[ -d "$LESSONS" ] || { echo "knowledge-coverage: нет базы знаний: $LESSONS — не измерено" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "knowledge-coverage: нужен python3 — не измерено" >&2; exit 2; }

LESSONS="$LESSONS" STATE="$STATE" python3 - <<'PY'
import os, re, glob, json, math, pathlib, statistics, datetime

L = pathlib.Path(os.environ["LESSONS"]); S = pathlib.Path(os.environ["STATE"])
oper = sorted(p.name for p in L.glob("*.md")
              if p.name.startswith(("case-", "pattern-", "principle-")))

served = set()
for f in list(S.glob("injection-log*.jsonl")):
    for line in f.read_text(errors="replace").splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue                      # битая строка не должна ронять замер
        if r.get("injected") is not False and r.get("file"):
            served.add(r["file"])

def field(name, key, default=0):
    m = re.search(rf'^{key}:\s*(-?\d+)', (L/name).read_text(errors="replace"), re.M)
    return int(m.group(1)) if m else default

def priority(name):
    rel = field(name, "confirmed_count") - field(name, "contradicted_count")
    return field(name, "impact", 3) * (1 + math.log(1 + max(0, rel)))

# Родитель — ДРУГОЙ файл: собственное имя в собственной шапке (`name:`) представлением не
# является. До 12 сентября 2026 тексты всех родителей склеивались в одну строку, и каждый
# паттерн и принцип, чей стем стоит в собственном тексте, объяснялся сам собой. Замер на живой
# базе 12 сентября 2026: таких родителей 2 из 58, и оба объяснены иначе — числа дня починка не
# сдвинула (НЕОБЪЯСНЁННЫХ 2 до и после). Класс закрыт по устройству, а не по симптому. Поймано
# свидетелем test_knowledge_coverage.sh (нога T5), написанным под D282.
parent_text = {p.name: (L/p.name).read_text(errors="replace")
               for p in list(L.glob("pattern-*.md")) + list(L.glob("principle-*.md"))}
def represented(n):
    # Имя ЦЕЛИКОМ, с границами: подстрокой `…-orphan` находился внутри `…-orphan-two`, и
    # запись считалась представленной соседом-по-префиксу (прожарка 13 сентября 2026, атака 7).
    stem_re = re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(n[:-3]) + r"(?![A-Za-z0-9_-])")
    return any(stem_re.search(t) for name, t in parent_text.items() if name != n)

today = datetime.date.today()
def young(name):
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})', name)
    if not m: return False
    try:
        return (today - datetime.date(*map(int, m.groups()))).days < 7
    except ValueError:
        return False

hit = [n for n in oper if n in served]
med = statistics.median([priority(n) for n in hit]) if hit else 0.0

buckets = {"подавалось": [], "представлен родителем": [], "моложе недели": [],
           "ранг ниже медианы поданных": [], "НЕОБЪЯСНЁННЫХ": []}
for n in oper:
    if n in served:                              buckets["подавалось"].append(n)
    elif represented(n):                         buckets["представлен родителем"].append(n)
    elif young(n):                               buckets["моложе недели"].append(n)
    elif priority(n) <= med:                     buckets["ранг ниже медианы поданных"].append(n)
    else:                                        buckets["НЕОБЪЯСНЁННЫХ"].append(n)

print(f"покрытие базы: operational-записей {len(oper)}, медиана priority поданных {med:.1f}")
for k, v in buckets.items():
    print(f"  {k}: {len(v)} ({100*len(v)/len(oper):.0f}%)")
bad = buckets["НЕОБЪЯСНЁННЫХ"]
if bad:
    print("\nбез названной причины:")
    for n in sorted(bad, key=priority, reverse=True):
        print(f"  · {n}  priority={priority(n):.1f}")
    print("[замер: находки, не сбой] реплей отбора по этим записям — единственный способ")
    print("отличить «оценивалось и проиграло» от «не оценивалось»")
raise SystemExit(1 if bad else 0)
PY
