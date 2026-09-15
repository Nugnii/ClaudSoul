#!/usr/bin/env bash
# docs-duplicates.sh — один факт описан в одном месте, а не в двух (канон D1/D3).
#
# Результат: ни одна содержательная строка не повторяется в двух документах состояния одного
#            языка; универсум — весь трекаемый markdown корня и docs/, кроме двух названных
#            и печатаемых классов исключений.
# Проверка результата: bash scripts/docs-duplicates.sh даёт 0.
#
# Повод. Аудит документации 28 августа 2026. Дубль уже дорого обходился: таблица мостов
# жила и в `architecture.md`, и в `bridges/_index.md`, разъехалась на пяти статусах из
# пятнадцати и была снята по ADR-001 (пункт D97). Дубль не «некрасив» — он расходится,
# и расходится молча, потому что правят обычно одну копию.
#
# Переводные пары сравниваются РАЗДЕЛЬНО: README.md английский, README.ru.md русский, и
# совпадение фактов между ними законно — это перевод, а не дубль.
#
# УНИВЕРСУМ ВЫВЕДЕН, А НЕ ПЕРЕЧИСЛЕН (род F, D294, 4 сентября 2026). До этого дня здесь стоял
# GROUPS — литеральный перечень из 10 документов, снятый с состава дерева на день написания;
# 23 документа docs/ сверщика не имели вовсе, и отчёт молчал об этом: он говорил о
# просмотренном так, будто говорит обо всём. Теперь множество берётся из индекса git, а
# исключения названы классом и ПЕЧАТАЮТСЯ пофайлово — невидимых документов не остаётся:
#   · хроника — CHANGELOG/BACKLOG/SESSION, архивы и снимки с датой в имени. Повтор там
#     законен по построению: архив хранит перенесённое, отчёт дня — сказанное в тот день.
#     Это тот же раздел, что и правило «документ состояния ≠ хроника».
#   · автоотчёт — документ, объявляющий себя выводом генератора («Автоматический отчёт
#     scripts/…»). Два прогона одного генератора повторяют его шаблон, а не копипасту руки;
#     на 4 сентября 2026 таких документов два и обе повторяющиеся строки — шапка генератора.
#
# НАЗВАННЫЙ ПРЕДЕЛ языка: он выведен из перевеса букв, и документ у самой границы перевеса
# может перейти в соседнюю группу от одной добавленной строки (проверено мутацией 4 сентября
# 2026 на docs/narrative-design.md). Тогда дубль между ним и его прежней группой перестанет
# быть виден — цена того, что перевод сравнивается с переводом, а не с оригиналом.
# Условие снятия: предел держится, пока язык определяется перевесом букв. Появится явное
# объявление языка в самом документе (поле шапки либо суффикс имени, как у README.ru.md) —
# группа перестанет зависеть от содержимого, и граница исчезнет вместе с пределом.
#
# КОНТРПРИМЕР: страж ловит повтор СТРОК, а не повтор СМЫСЛА. Один и тот же факт, сказанный
# в двух документах разными словами, он не увидит — а именно так дубли и появляются чаще
# всего. Это проверка на копипасту, не на единственность источника истины.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd -P)}"
cd "$REPO" || exit 2
command -v python3 >/dev/null 2>&1 || { echo "docs-duplicates: нужен python3" >&2; exit 2; }

python3 - <<'PY'
import re, sys, collections, pathlib, subprocess

MIN_LEN = 60          # короче — служебные строки и заголовки, повтор у них законен

# Множество ВЫВОДИТСЯ обращением к индексу git; предмет — markdown корня и docs/.
tracked = subprocess.run(["git", "ls-files", "*.md"],
                         capture_output=True, text=True).stdout.split()
cand = [f for f in tracked if "/" not in f or f.startswith("docs" + "/")]

CHRONICLE = re.compile(r"(^|/)(CHANGELOG|BACKLOG|SESSION)|\d{4}-\d{2}-\d{2}|-archive")
AUTO_MARK = "Автоматический отчёт"

def text_of(fp):
    return pathlib.Path(fp).read_text(encoding="utf-8", errors="replace")

kept, skipped = [], []
for fp in sorted(cand):
    if not pathlib.Path(fp).is_file():
        continue
    if CHRONICLE.search(fp):
        skipped.append((fp, "хроника"))
    elif AUTO_MARK in text_of(fp)[:4000]:
        skipped.append((fp, "автоотчёт"))
    else:
        kept.append(fp)

# Пустой или подозрительно мелкий универсум — отказ, а не зелёный отчёт: страж, не
# открывший документов, выглядит ровно как страж, не нашедший дублей (род F).
if len(kept) < 20:
    print(f"docs-duplicates: универсум не выведен — документов в сверке {len(kept)}"
          f" при {len(cand)} трекаемых; проверь git ls-files и корень репозитория")
    sys.exit(2)

def lines_of(fp):
    out = []
    for raw in text_of(fp).splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or s.startswith("|") or s.startswith("```"):
            continue
        s = re.sub(r"\s+", " ", s)
        s = re.sub(r"[*_`\[\]()>-]", "", s).strip()
        if len(s) >= MIN_LEN:
            out.append(s)
    return out

# Переводные пары сравниваются РАЗДЕЛЬНО, и язык тоже выводится — из самого текста, а не из
# перечня имён: README.md английский, README.ru.md русский, а CLAUDE.md русский без суффикса.
def lang(fp):
    body = text_of(fp)
    return "русские" if len(re.findall(r"[а-яё]", body, re.I)) > len(re.findall(r"[a-z]", body, re.I)) \
           else "английские"

groups = collections.defaultdict(list)
for fp in kept:
    groups[lang(fp)].append(fp)

total = 0
for gname in sorted(groups):
    files = groups[gname]
    where = collections.defaultdict(set)
    for fp in files:
        for s in lines_of(fp):
            where[s].add(fp)
    dups = {s: f for s, f in where.items() if len(f) > 1}
    print(f"ГРУППА «{gname}»: документов {len(files)}, дублей {len(dups)}")
    for s, f in sorted(dups.items(), key=lambda x: -len(x[0]))[:12]:
        print(f"   · {' + '.join(sorted(f))}")
        print(f"     {s[:110]}…")
    total += len(dups)

# Исключённое называется пофайлово: невидимых документов у сверщика быть не должно.
print(f"\nВНЕ СВЕРКИ {len(skipped)} из {len(cand)}:")
for fp, why in skipped:
    print(f"   · {fp} — {why}")

print()
if total:
    print(f"[замер: находки, не сбой] — дублей всего: {total}")
    sys.exit(1)
print("дублей нет")
PY
