#!/usr/bin/env bash
# second-contour-freshness.sh — второй контур не участвует в распаде по конструкции.
# Результат: во втором контуре нет записей старше порога свежести
# Проверка результата: bash scripts/second-contour-freshness.sh даёт 0
#
#
# Повод (D48). FSRS в `knowledge-audit-digest.sh` отбирает `case-*|pattern-*|principle-*`,
# то есть 104 записи второго контура (entity/fact/relation) не входят в контур распада
# вообще. Замер: `last_confirmed` — 0 записей из 104, `valid_until` — 69 записей, и у ВСЕХ
# значение `null`.
#
# Загонять их в FSRS было бы неверно: у него семантика «пора перепроверить урок», а у
# факта вопрос другой — «не устарел ли он». Поэтому здесь отдельный замер по `last_updated`,
# а не расширение отбора FSRS: смешение сдвинуло бы `overdue_ratio`, которым меряется
# совсем другое.
#
# Код возврата: 0 — в пределах порога; 1 — есть записи старше него.

set -uo pipefail

LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
MAX_DAYS="${SECOND_CONTOUR_MAX_DAYS:-120}"
[ -d "$LESSONS" ] || { echo "second-contour-freshness: нет базы $LESSONS" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "second-contour-freshness: нужен python3" >&2; exit 2; }

python3 - "$LESSONS" "$MAX_DAYS" <<'PY'
import datetime, pathlib, re, sys

lessons, max_days = pathlib.Path(sys.argv[1]), int(sys.argv[2])
today = datetime.date.today()
# Значение бывает в кавычках и без: `last_updated: '2026-04-21'` и `last_updated: 2026-04-20`.
# Первая версия этого разбора требовала голую дату и нашла 2 записи из 102 — цифра,
# которая выглядела бы как «поле почти никто не заполняет».
pat = re.compile(r"^last_updated:\s*['\"]?(\d{4}-\d{2}-\d{2})", re.M)
val = re.compile(r"^valid_until:\s*(.+)$", re.M)

buckets, no_date, valid_null, total = [], 0, 0, 0
for prefix in ("entity", "fact", "relation"):
    for f in sorted(lessons.glob(f"{prefix}-*.md")):
        total += 1
        t = f.read_text(errors="replace")
        m = pat.search(t)
        if m:
            age = (today - datetime.date.fromisoformat(m.group(1))).days
            buckets.append((age, prefix, f.stem))
        else:
            no_date += 1
        v = val.search(t)
        if v and v.group(1).strip().strip("'\"") in ("null", "~", ""):
            valid_null += 1

stale = [b for b in buckets if b[0] > max_days]
buckets.sort(reverse=True)

print(f"Второй контур: {total} записей, с датой обновления {len(buckets)}, без даты {no_date}.")
print(f"Старше {max_days} дн.: {len(stale)}. Фактов/связей со сроком годности `null`: {valid_null}.")
if buckets:
    print("Самые давние:")
    for age, prefix, name in buckets[:5]:
        print(f"  {age:4d} дн.  {prefix:8s} {name[:52]}")
if valid_null:
    print("`valid_until: null` означает «срок не задан», а не «бессрочно» —")
    print("для факта это то же самое, что отсутствие срока у обязанности.")

if stale:
    print("[замер: находки, не сбой] — ненулевой код здесь — вердикт замера, а не сбой (D95)")
raise SystemExit(1 if stale else 0)
PY
