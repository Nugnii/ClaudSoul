#!/usr/bin/env bash
# docs-duplicates.sh — один факт описан в одном месте, а не в двух (канон D1/D3).
#
# Результат: ни одна содержательная строка не повторяется в двух документах одного языка.
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
# КОНТРПРИМЕР: страж ловит повтор СТРОК, а не повтор СМЫСЛА. Один и тот же факт, сказанный
# в двух документах разными словами, он не увидит — а именно так дубли и появляются чаще
# всего. Это проверка на копипасту, не на единственность источника истины.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd -P)}"
cd "$REPO" || exit 2
command -v python3 >/dev/null 2>&1 || { echo "docs-duplicates: нужен python3" >&2; exit 2; }

python3 - <<'PY'
import re, sys, collections, pathlib

GROUPS = {
 "русские": ["README.ru.md", "docs/reference.ru.md", "CLAUDE.md", "PLAN.md",
             "docs/architecture.md", "docs/development.md", "docs/decisions.md"],
 "английские": ["README.md", "docs/reference.md"],
}
MIN_LEN = 60          # короче — служебные строки и заголовки, повтор у них законен

def lines_of(fp):
    p = pathlib.Path(fp)
    if not p.is_file():
        return []
    out = []
    for raw in p.read_text(encoding="utf-8", errors="replace").splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or s.startswith("|") or s.startswith("```"):
            continue
        s = re.sub(r"\s+", " ", s)
        s = re.sub(r"[*_`\[\]()>-]", "", s).strip()
        if len(s) >= MIN_LEN:
            out.append(s)
    return out

total = 0
for gname, files in GROUPS.items():
    where = collections.defaultdict(set)
    for fp in files:
        for s in lines_of(fp):
            where[s].add(fp)
    dups = {s: f for s, f in where.items() if len(f) > 1}
    print(f"ГРУППА «{gname}»: документов {len([f for f in files if pathlib.Path(f).is_file()])}, дублей {len(dups)}")
    for s, f in sorted(dups.items(), key=lambda x: -len(x[0]))[:12]:
        print(f"   · {' + '.join(sorted(f))}")
        print(f"     {s[:110]}…")
    total += len(dups)

print()
if total:
    print(f"[замер: находки, не сбой] — дублей всего: {total}")
    sys.exit(1)
print("дублей нет")
PY
