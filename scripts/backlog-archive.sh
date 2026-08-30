#!/usr/bin/env bash
# backlog-archive.sh — выполненное уезжает в архив, в рабочем файле остаётся только открытое.
# Результат: в BACKLOG.md нет выполненных пунктов: закрытое уехало в архив
# Проверка результата: bash scripts/backlog-archive.sh check даёт 0
#
# Прежняя проверка звучала `grep -c '^- ☑' BACKLOG.md даёт 0` — то есть искала ту же
# вёрстку, что и сам инструмент, и была зелёной ровно тогда, когда он слеп. Проверка,
# выраженная через реализацию, наследует её слепое пятно и отказ обнаружить не может.
#
#
# Повод. Собеседник: «сейчас в бэклоге я наблюдаю отмеченные как выполненные пункты, и он
# из-за них распухший». Замер на момент заведения: 21 открытый пункт против 32 выполненных,
# и 65% символов файла приходилось на уже закрытое.
#
# Разбор в v1.14.7 уже чистил бэклог — но чистил РАЗДЕЛАМИ: в архив уезжал раздел, где не
# осталось ни одного открытого пункта. Выполненный пункт внутри живого раздела оставался
# лежать. Одной сессии хватило, чтобы файл распух заново. То есть уборка была обязанностью
# без владельца и срока — ровно тот класс, что разбирался в D38.
#
# Поэтому здесь не разовая чистка, а команда со строкой в `scripts/measurements.tsv`.
#
# И строка стоит в режиме `run`, а не `check` (правка 2026-08-01). Первая версия
# отчитывалась вместо того, чтобы убирать: замер честно отработал, сообщил «13 выполненных
# пунктов» — и файл остался распухшим, пока собеседник не сказал «бэклог не почистился».
# Уборка — действие, а не измерение: её результат не требует суждения, а идемпотентность
# и сохранность свидетельств закрытий проверены отдельными случаями теста.
#
# Что переносится: пункт верхнего уровня `- ☑` или `- ⊘` вместе со всеми его строками
# продолжения (вложенные строки и абзацы до следующего пункта или заголовка). Заголовок
# раздела переносится вместе с пунктами и остаётся в рабочем файле, только если под ним
# уцелел хотя бы один открытый пункт.
#
# Что НЕ трогается: `- ☐` и `- ◐` — обе метки означают «не сделано» (легенда BACKLOG.md),
# и обе считает Stop-алерт. Преамбула файла до первого раздела остаётся на месте.
#
# Свидетельства закрытий не выбрасываются: архив — источник для `backlog-recheck.sh`,
# который раз в неделю проверяет, что закрытое осталось закрытым.

set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
BACKLOG="${BACKLOG_FILE:-$REPO/BACKLOG.md}"
ARCHIVE="${BACKLOG_ARCHIVE:-$REPO/BACKLOG-archive.md}"
MODE="${1:-run}"          # run — переносить; check — только сказать, сколько накопилось

[ -f "$BACKLOG" ] || { echo "backlog-archive: нет $BACKLOG" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "backlog-archive: нужен python3" >&2; exit 2; }

python3 - "$BACKLOG" "$ARCHIVE" "$MODE" <<'PY'
import re, sys, os, pathlib, datetime

backlog, archive, mode = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]

DONE = ("☑", "⊘")
OPEN = ("☐", "◐")

# Опознание пункта — по ПРАВИЛУ, а не по одной вёрстке. Прежний признак требовал `^- `
# и с 28 августа 2026, когда пункты стали заголовками, не видел ни одного: архиватор
# сутки печатал «переносить нечего» при двух ☑ в файле. Правило и обе вёрстки — в
# `hooks/backlog-lib.sh`, здесь его питоновское отражение с тем же контрпримером:
# строка легенды несёт все четыре метки и пунктом не является, потому что не несёт `D<N>`.
_MARKS = "".join(DONE + OPEN)
ITEM_RE = re.compile(rf'^(?:- |#{{2,6}} )[^|]*[{_MARKS}]')

def item_mark(line):
    if not ITEM_RE.match(line):
        return None
    m = re.search(rf'[{_MARKS}]', line)
    return m.group(0) if m else None

lines = backlog.read_text().splitlines(keepends=True)

# Разбор на блоки: заголовок раздела (## / ###) либо пункт с его продолжением.
blocks = []          # (kind, heading_level|mark, [строки])
cur = None
for ln in lines:
    if re.match(r'^#{2,6} ', ln) and item_mark(ln) is None:
        if cur: blocks.append(cur)
        cur = ["heading", len(ln) - len(ln.lstrip('#')), [ln]]
    elif item_mark(ln) in DONE + OPEN:
        if cur: blocks.append(cur)
        cur = ["item", item_mark(ln), [ln]]
    else:
        if cur is None:
            cur = ["preamble", None, []]
        cur[2].append(ln)
if cur: blocks.append(cur)

moved = [b for b in blocks if b[0] == "item" and b[1] in DONE]

# ── Гейт закрытия: «сделано» без показания в архив не уезжает ────────────────────
# Требование владельца 29 августа 2026: у решения должен быть измеримый и достижимый
# результат, а решением считается и МЕХАНИЗМ, не дающий проблеме возникнуть. Отсюда
# контракт закрытого пункта: ☑ несёт строку `**Проверка.**` с командой (состояние мира
# проверяемо), ⊘ несёт строку `**Вердикт.**` (названа цена отказа либо чем опровергнут
# признак). Пункт без этого — не закрытие, а исчезновение с меткой.
#
# Это отказ ПО ДАННЫМ, а не по действию: признак — отсутствие строки в самом пункте,
# ложных срабатываний он не даёт по построению, и альтернатива исполнима без чужого
# разрешения (дописать строку либо вернуть метку в ◐). Правило ADR-011 соблюдено.
#
# ПОРОГ ПО НОМЕРУ. Контракт действует с пунктов, заведённых после его введения:
# исторические закрытия писались до него, и требовать от них строку задним числом
# значило бы выдать десятки ложных отказов на правильной работе — ровно тот прецедент,
# который запрещает слепое ужесточение (40 отказов, из них 32 ложных).
MIN_ID = int(os.environ.get("BACKLOG_CONTRACT_MIN_ID", "200"))
def _item_id(block):
    m = re.search(r'D(\d+)', block[2][0])
    return int(m.group(1)) if m else None

unproven = []
for b in moved:
    iid = _item_id(b)
    if iid is None or iid < MIN_ID:
        continue
    body = "".join(b[2])
    if b[1] == "☑" and "**Проверка.**" not in body:
        unproven.append((iid, "☑ без строки «**Проверка.** `команда` → 0»"))
    if b[1] == "⊘" and "**Вердикт.**" not in body:
        unproven.append((iid, "⊘ без строки «**Вердикт.** <цена отказа либо чем опровергнут признак>»"))

if unproven and mode != "check":
    print("Закрытие без показания — в архив не переносится:")
    for iid, why in unproven:
        print(f"  · D{iid}: {why}")
    print("\nИсход называется состоянием мира, а не меткой. Допиши строку показания —")
    print("либо верни метку в ◐, если работа не закончена. После этого перенос пройдёт.")
    sys.exit(1)

if mode == "check":
    print(f"В BACKLOG.md выполненных пунктов: {len(moved)} "
          f"(открытых: {sum(1 for b in blocks if b[0]=='item' and b[1] in OPEN)})")
    sys.exit(0 if len(moved) == 0 else 1)

if not moved:
    print("Переносить нечего: выполненных пунктов в BACKLOG.md нет.")
    sys.exit(0)

# Какие заголовки уцелеют: те, под которыми остался хотя бы один открытый пункт.
# Считаем от заголовка до следующего заголовка того же или более высокого уровня.
keep_heading = [False] * len(blocks)
for i, b in enumerate(blocks):
    if b[0] != "heading":
        continue
    for j in range(i + 1, len(blocks)):
        nb = blocks[j]
        if nb[0] == "heading" and nb[1] <= b[1]:
            break
        if nb[0] == "item" and nb[1] in OPEN:
            keep_heading[i] = True
            break

# Рабочий файл: преамбула + уцелевшие заголовки + открытые пункты.
kept, to_archive = [], []
heading_stack = []           # заголовки, ещё не выведенные в архив
for i, b in enumerate(blocks):
    if b[0] == "preamble":
        kept.extend(b[2])
    elif b[0] == "heading":
        heading_stack = [h for h in heading_stack if h[0] < b[1]]
        heading_stack.append((b[1], b[2]))
        if keep_heading[i]:
            # Пустая строка перед заголовком: продолжение перенесённого пункта могло
            # унести с собой разделитель, и заголовок слипся бы с предыдущим текстом.
            if kept and kept[-1].strip():
                kept.append("\n")
            kept.extend(b[2])
    elif b[1] in OPEN:
        kept.extend(b[2])
    else:
        for lvl, hl in heading_stack:
            to_archive.extend(hl)
        heading_stack = []
        to_archive.extend(b[2])

# Перенос — не запись агента: mtime BACKLOG.md возвращается прежний (с наносекундами),
# иначе сверщик исхода хода `declared-problem-recorded`, судящий по mtime носителя, счёл бы
# уборку на Stop за «агент записал что-то» и подделал бы `none` → `recorded`. Тот же класс
# и та же правка, что у пересчёта показаний (D210, scripts/backlog-refresh-readings.sh).
_st = backlog.stat()
backlog.write_text("".join(kept))
os.utime(backlog, ns=(_st.st_atime_ns, _st.st_mtime_ns))

stamp = datetime.date.today().isoformat()
head = (f"\n## Перенесено из BACKLOG.md {stamp}\n\n"
        f"Свидетельства закрытий. Источник для `scripts/backlog-recheck.sh` — он раз в неделю\n"
        f"проверяет, что закрытое осталось закрытым.\n\n")
existing = archive.read_text() if archive.exists() else "# BACKLOG — архив\n"
archive.write_text(existing.rstrip("\n") + "\n" + head + "".join(to_archive))

print(f"Перенесено в архив: {len(moved)} выполненных пункт(ов).")
print(f"  BACKLOG.md: {len(lines)} → {len(kept)} строк")
PY