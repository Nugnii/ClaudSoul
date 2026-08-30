#!/usr/bin/env python3
# Результат: в записях знаний перекройки правила и провенанс подтверждений разнесены по разным полям
# Проверка результата: grep -l 'provenance_log:' ~/.claude/global-lessons/*.md — поле есть там, где были подтверждения
#
"""Разнести `modification_history` на два поля: перекройки правила и провенанс подтверждений.

Зачем. Формула `fragile` считает записи `modification_history`, полагая их перекройками scope.
Но `knowledge-counter-bump.sh` пишет туда `kind: reinforced` на КАЖДОЕ подтверждение, и 96 из 132
записей базы — именно провенанс. Два разных смысла в одном списке: по букве формулы любое хорошо
подтверждённое знание становится «хрупким».

Что делает. Записи с `kind` из PROVENANCE_KINDS переезжают в новое поле `provenance_log:`,
остальные (narrowed/branched/deprecated/scope_widened/escalation/без kind) остаются в
`modification_history`. Порядок записей сохраняется в обоих полях.

Как делает — ПОСТРОЧНО, а не через YAML-парсер. Причины (замер базы 2026-08-11):
  * значения `reason`/`note` — одностроч­ники до 2225 символов; YAML-дампер с width=80 молча
    превратил бы их в блочные скаляры и изменил содержимое базы;
  * 87 из 132 значений содержат `:` внутри, спасают только внешние кавычки — перезапись,
    теряющая кавычки, ломает YAML;
  * `date` без кавычек: YAML-парсер вернул бы `datetime.date`, дамп изменил бы вид.
Поэтому строки записей переносятся ПОБАЙТОВО, а корректность проверяется инвариантом:
мультимножество строк файла после миграции = было + одна новая строка-заголовок поля.

Краевые случаи, найденные замером и учтённые здесь:
  * META.md — спецификация схемы, а НЕ знание (нет frontmatter) → в исключениях;
  * комментарий в нулевой колонке ВНУТРИ списка (строки `# …` между записями в
    `pattern-inside-out-blindness.md`) не
    завершает блок для YAML → не завершает и здесь; такие строки остаются в
    `modification_history` на своих местах (комментарий возвращается к своему разделу сам);
  * легаси-словарь ключей `by_case`/`note` вместо `trigger_case`/`reason` (35 записей) —
    строки переносятся как есть, ключи не переписываются;
  * запись без `kind` (`change: created`) — остаётся в modification_history (это происхождение);
  * формы поля `[]` / пустое значение с блоком / отсутствие — все три обрабатываются;
  * повторный запуск идемпотентен: уже перенесённые записи лежат в provenance_log и не двигаются.

Запуск:
    python3 scripts/split-provenance-log.py --dir ~/.claude/global-lessons            # сухой прогон
    python3 scripts/split-provenance-log.py --dir ~/.claude/global-lessons --apply    # запись
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from collections import Counter

# Виды записей, которые суть ПРОВЕНАНС подтверждения/противоречия, а не изменение правила.
# `confirmation` — легаси-синоним `reinforced` (17 записей, в спецификации META не описан).
PROVENANCE_KINDS = {"reinforced", "contradicted", "confirmation"}

MH_KEY = "modification_history"
PL_KEY = "provenance_log"

TOP_LEVEL_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*:")
ENTRY_START = re.compile(r"^  - ")
KIND_LINE = re.compile(r"^\s+kind:\s*(.+?)\s*$")


class Skip(Exception):
    """Файл не является знанием либо мигрировать нечего."""


def frontmatter_bounds(lines: list[str]) -> tuple[int, int]:
    """Границы frontmatter: индекс строки после открывающего `---` и индекс закрывающего."""
    if not lines or lines[0].rstrip("\n") != "---":
        raise Skip("нет frontmatter")
    for i in range(1, len(lines)):
        if lines[i].rstrip("\n") == "---":
            return 1, i
    raise Skip("frontmatter не закрыт")


def parse_block(lines: list[str], start: int, fm_end: int) -> tuple[list[dict], int]:
    """Разобрать блок списка, начиная со строки после заголовка поля.

    Возвращает (items, конец блока). item = {"type": "entry"|"loose", "lines": [...]}.
    Блок завершается top-level ключом или концом frontmatter. Комментарии и пустые строки
    в нулевой колонке блок НЕ завершают (так же считает YAML) и сохраняются как "loose".
    """
    items: list[dict] = []
    i = start
    while i < fm_end:
        line = lines[i]
        if TOP_LEVEL_KEY.match(line):
            break
        if ENTRY_START.match(line):
            entry = [line]
            i += 1
            while i < fm_end:
                nxt = lines[i]
                if ENTRY_START.match(nxt) or TOP_LEVEL_KEY.match(nxt):
                    break
                if nxt.startswith("  ") and nxt.strip():
                    entry.append(nxt)
                    i += 1
                    continue
                break
            items.append({"type": "entry", "lines": entry})
            continue
        items.append({"type": "loose", "lines": [line]})
        i += 1
    return items, i


def entry_kind(entry_lines: list[str]) -> str | None:
    for ln in entry_lines:
        m = KIND_LINE.match(ln)
        if m:
            return m.group(1).strip().strip('"').strip("'")
    return None


def migrate(path: pathlib.Path) -> tuple[list[str], Counter]:
    original = path.read_text().splitlines(keepends=True)
    fm_start, fm_end = frontmatter_bounds(original)

    mh_idx = pl_idx = None
    for i in range(fm_start, fm_end):
        if original[i].startswith(f"{MH_KEY}:"):
            mh_idx = i
        elif original[i].startswith(f"{PL_KEY}:"):
            pl_idx = i
    if mh_idx is None:
        raise Skip("поля modification_history нет")

    mh_items, mh_block_end = parse_block(original, mh_idx + 1, fm_end)
    entries = [it for it in mh_items if it["type"] == "entry"]
    if not entries:
        raise Skip("записей нет")

    moving = [it for it in entries if (entry_kind(it["lines"]) or "") in PROVENANCE_KINDS]
    if not moving:
        raise Skip("нечего переносить")

    staying_items = [
        it for it in mh_items
        if it["type"] == "loose" or (entry_kind(it["lines"]) or "") not in PROVENANCE_KINDS
    ]
    stay_entries = [it for it in staying_items if it["type"] == "entry"]

    # Уже существующий provenance_log (повторный запуск / ручная правка) — дописываем в конец.
    existing_pl_items: list[dict] = []
    pl_block_end = None
    if pl_idx is not None:
        existing_pl_items, pl_block_end = parse_block(original, pl_idx + 1, fm_end)

    out: list[str] = []
    i = 0
    while i < len(original):
        if i == mh_idx:
            out.append(f"{MH_KEY}: []\n" if not stay_entries else f"{MH_KEY}:\n")
            for it in staying_items:
                out.extend(it["lines"])
            i = mh_block_end
            # provenance_log кладём сразу за историей, если отдельного поля ещё не было
            if pl_idx is None:
                out.append(f"{PL_KEY}:\n")
                for it in moving:
                    out.extend(it["lines"])
            continue
        if pl_idx is not None and i == pl_idx:
            out.append(original[i])
            for it in existing_pl_items:
                out.extend(it["lines"])
            for it in moving:
                out.extend(it["lines"])
            i = pl_block_end
            continue
        out.append(original[i])
        i += 1

    # ── Инвариант: набор строк сохранён побайтово, добавлена ровно одна строка-заголовок ──
    before, after = Counter(original), Counter(out)
    added = after - before
    removed = before - after
    allowed_added = Counter({f"{PL_KEY}:\n": 1})
    if not stay_entries:
        allowed_added[f"{MH_KEY}: []\n"] += 1
    allowed_removed = Counter() if stay_entries else Counter({original[mh_idx]: 1})
    if added != allowed_added or removed != allowed_removed:
        raise RuntimeError(
            f"{path.name}: инвариант строк нарушен. Лишние: {list(added)[:2]}, "
            f"потерянные: {list(removed)[:2]}"
        )

    stats = Counter({
        "перенесено": len(moving),
        "осталось": len(stay_entries),
        "loose": len([it for it in staying_items if it["type"] == "loose"]),
    })
    return out, stats


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="каталог знаний")
    ap.add_argument("--apply", action="store_true", help="записать (по умолчанию сухой прогон)")
    ap.add_argument("--exclude", nargs="*", default=["META.md", "source-tiers.md"],
                    help="файлы-исключения: спецификации, а не знания")
    args = ap.parse_args()

    root = pathlib.Path(args.dir).expanduser()
    files = sorted(p for p in root.glob("*.md") if p.name not in args.exclude)

    total = Counter()
    touched = 0
    for path in files:
        try:
            out, stats = migrate(path)
        except Skip:
            continue
        touched += 1
        total.update(stats)
        print(f"  {path.name}: перенесено {stats['перенесено']}, "
              f"осталось {stats['осталось']}, комментариев/пустых {stats['loose']}")
        if args.apply:
            path.write_text("".join(out))

    mode = "ЗАПИСАНО" if args.apply else "СУХОЙ ПРОГОН"
    print(f"\n{mode}: файлов затронуто {touched}, "
          f"перенесено записей {total['перенесено']}, оставлено {total['осталось']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
