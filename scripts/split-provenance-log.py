#!/usr/bin/env python3
# Результат: в записях знаний перекройки правила и провенанс подтверждений разнесены по разным полям
# Проверка результата: test -d ~/.claude/global-lessons && python3 scripts/split-provenance-log.py --dir ~/.claude/global-lessons --check даёт 0 — ни одной записи вида reinforced/contradicted/confirmation внутри modification_history не осталось; каталога нет либо в нём ни одного знания — код 2, «предмета не было» отличимо от «результат достигнут»
#
"""Разнести `modification_history` на два поля: перекройки правила и провенанс подтверждений.

Зачем. Формула `fragile` считает записи `modification_history`, полагая их перекройками scope.
Но `knowledge-counter-bump.sh` пишет туда `kind: reinforced` на КАЖДОЕ подтверждение, и 96 из 132
записей базы — именно провенанс. Два разных смысла в одном списке: по букве формулы любое хорошо
подтверждённое знание становится «хрупким».

Что делает. Записи с `kind` из PROVENANCE_KINDS переезжают в новое поле `provenance_log:`,
остальные (narrowed/branched/deprecated/scope_widened/escalation/без kind) остаются в
`modification_history`. Порядок записей сохраняется в обоих полях.

Как делает — ПОБАЙТОВЫЙ перенос строк, а корректность проверяется ЧИТАЯ YAML. Причины
побайтовости (замер базы 2026-08-11):
  * значения `reason`/`note` — одностроч­ники до 2225 символов; YAML-дампер с width=80 молча
    превратил бы их в блочные скаляры и изменил содержимое базы;
  * 87 из 132 значений содержат `:` внутри, спасают только внешние кавычки — перезапись,
    теряющая кавычки, ломает YAML;
  * `date` без кавычек: YAML-парсер вернул бы `datetime.date`, дамп изменил бы вид.
Из «дампер портит значения» НЕ следует «парсер не нужен»: значения не переписываются, но и
вход, и выход ЧИТАЮТСЯ парсером. До 6 сентября 2026 парсера не было ни на одной стороне, и
это был общий корень трёх дефектов (D290, D301): проверка выхода была списком ожидаемых
ДЕЛЬТ строк, вычисленным той же веткой, что и преобразование, — она не могла отличить
«получилось» от «сломал» и была написана лишь под одну из двух веток.

Пофайловая ТРАНЗАКЦИЯ (D301). Для каждого файла: разобрал → преобразовал → проверил свойства
выхода → записал. Не сошлось хоть что-то — файл не трогается вовсе, отказ называется строкой
`ОТКАЗ <файл>: <почему>`, прогон продолжается. Проверяемые свойства выхода:
  * frontmatter остаётся валидным YAML;
  * мультимножество записей `modification_history + provenance_log` совпало с исходным;
  * в `modification_history` не осталось провенанс-видов, в `provenance_log` нет чужих;
  * остальные поля frontmatter не изменились;
  * мультимножество СТРОК файла сохранено, добавлены только строки-заголовки полей.
Плюс сверка на входе: сколько провенанс-записей внутри `modification_history` видит YAML и
сколько видит построчный разбор. Разошлись — форма списка построчному разбору не по зубам
(нулевой отступ, отступ 4, поток), файл не трогается и НЕ считается чистым.

Краевые случаи, найденные замером и учтённые здесь:
  * META.md — спецификация схемы, а НЕ знание (нет frontmatter) → в исключениях;
  * комментарий в нулевой колонке ВНУТРИ списка (строки `# …` между записями в
    `pattern-inside-out-blindness.md`) не
    завершает блок для YAML → не завершает и здесь; такие строки остаются в
    `modification_history` на своих местах (комментарий возвращается к своему разделу сам);
  * YAML-комментарий ПОСЛЕ значения `kind` (`kind: reinforced  # почему`) отрезается при
    сравнении вида и переезжает вместе со строкой;
  * легаси-словарь ключей `by_case`/`note` вместо `trigger_case`/`reason` (35 записей) —
    строки переносятся как есть, ключи не переписываются;
  * запись без `kind` (`change: created`) — остаётся в modification_history (это происхождение);
  * формы поля `[]` / пустое значение с блоком / отсутствие — все три обрабатываются;
  * `provenance_log` УЖЕ есть, а внутри `modification_history` остался провенанс-вид (D290):
    новая строка-заголовок не добавляется, записи дописываются в конец существующего поля;
  * перевод строки файла (LF или CRLF) сохраняется, в том числе у добавленных заголовков;
  * повторный запуск идемпотентен: уже перенесённые записи лежат в provenance_log и не двигаются.

Коды возврата: 0 — предмет осмотрен и чист (для `--check`) либо запись прошла; 1 — остаток
есть; 2 — предмета нет (каталога нет либо ни одного файла знания) или были отказы при записи.

Запуск:
    python3 scripts/split-provenance-log.py --dir ~/.claude/global-lessons            # сухой прогон
    python3 scripts/split-provenance-log.py --dir ~/.claude/global-lessons --apply    # запись
    python3 scripts/split-provenance-log.py --dir ~/.claude/global-lessons --check    # 1 — остаток есть, ничего не пишет
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from collections import Counter

try:
    import yaml
except ImportError:  # без парсера проверить выход нечем — писать запрещено, см. main()
    yaml = None

# Общий замок (род H). База знаний — файл не одного писателя: её правят этот скрипт,
# хук `knowledge-link-symmetry.sh` (оболочечный замок на тот же каталог),
# `knowledge-counter-bump.sh` и `/learn`. Ниже открыто окно read→write по каждому файлу.
# Протокол один на оба языка: `hooks/lib/state_lock.py` и `hooks/state-lock-lib.sh`.
_LIB = pathlib.Path(__file__).resolve().parent.parent / "hooks" / "lib"
if not (_LIB / "state_lock.py").exists():
    _LIB = pathlib.Path.home() / ".claude/hooks/lib"
sys.path.insert(0, str(_LIB))
try:
    from state_lock import with_lock
except ImportError:  # библиотеки нет — работаем как прежде: замок улучшает, а не требуется
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):
        yield False

# Виды записей, которые суть ПРОВЕНАНС подтверждения/противоречия, а не изменение правила.
# `confirmation` — легаси-синоним `reinforced` (17 записей, в спецификации META не описан).
PROVENANCE_KINDS = {"reinforced", "contradicted", "confirmation"}

MH_KEY = "modification_history"
PL_KEY = "provenance_log"

TOP_LEVEL_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*:")
ENTRY_START = re.compile(r"^  - ")
KIND_LINE = re.compile(r"^\s+kind:\s*(.+?)\s*$")


class Skip(Exception):
    """Файл — предмет инструмента, но мигрировать в нём нечего."""


class NotKnowledge(Skip):
    """Нет frontmatter — файл вообще не предмет этого инструмента."""


class Unsafe(Exception):
    """Файл — предмет, но безопасно преобразовать его не вышло: не трогаем."""


def read_lines(path: pathlib.Path) -> list[str]:
    """Строки БЕЗ перевода переводов строк: CRLF остаётся CRLF (инвариант «побайтово»)."""
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.readlines()


def write_lines(path: pathlib.Path, lines: list[str]) -> None:
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write("".join(lines))


def frontmatter_bounds(lines: list[str]) -> tuple[int, int]:
    """Границы frontmatter: индекс строки после открывающего `---` и индекс закрывающего."""
    if not lines or lines[0].rstrip("\r\n") != "---":
        raise NotKnowledge("нет frontmatter")
    for i in range(1, len(lines)):
        if lines[i].rstrip("\r\n") == "---":
            return 1, i
    raise NotKnowledge("frontmatter не закрыт")


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
        if not m:
            continue
        val = m.group(1).strip()
        if val[:1] not in ('"', "'"):
            # YAML-комментарий отделён пробелом: `reinforced  # почему`. Значение `a#b` цело.
            val = re.split(r"\s#", val, maxsplit=1)[0].strip()
        return val.strip('"').strip("'")
    return None


def frontmatter_data(lines: list[str], fm_start: int, fm_end: int) -> dict | None:
    """Frontmatter как данные. None — парсера нет либо разобрать не вышло."""
    if yaml is None:
        return None
    try:
        data = yaml.safe_load("".join(lines[fm_start:fm_end]))
    except Exception:
        return None
    return data if isinstance(data, dict) else None


def prov_entries(seq) -> list:
    out = []
    for e in seq or []:
        if isinstance(e, dict) and e.get("kind") in PROVENANCE_KINDS:
            out.append(e)
    return out


def migrate(path: pathlib.Path) -> tuple[list[str], Counter]:
    original = read_lines(path)
    fm_start, fm_end = frontmatter_bounds(original)

    mh_idx = pl_idx = None
    for i in range(fm_start, fm_end):
        if original[i].startswith(f"{MH_KEY}:"):
            mh_idx = i
        elif original[i].startswith(f"{PL_KEY}:"):
            pl_idx = i
    if mh_idx is None:
        raise Skip("поля modification_history нет")

    old_data = frontmatter_data(original, fm_start, fm_end)
    if yaml is not None and old_data is None:
        raise Unsafe("frontmatter не разбирается как YAML — остаток неотличим от его отсутствия")

    mh_items, mh_block_end = parse_block(original, mh_idx + 1, fm_end)
    entries = [it for it in mh_items if it["type"] == "entry"]
    moving = [it for it in entries if (entry_kind(it["lines"]) or "") in PROVENANCE_KINDS]

    # Сверка двух взглядов на ОДИН файл. Разошлись — форма списка построчному разбору не по
    # зубам (нулевой отступ, отступ 4, поток): такой файл не чинится молча и не зовётся чистым.
    if old_data is not None:
        yaml_rem = len(prov_entries(old_data.get(MH_KEY)))
        if yaml_rem != len(moving):
            raise Unsafe(
                f"построчный разбор видит {len(moving)} провенанс-записей, YAML — {yaml_rem}: "
                "форма списка не поддержана"
            )

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

    nl = "\r\n" if original[mh_idx].endswith("\r\n") else "\n"

    out: list[str] = []
    i = 0
    while i < len(original):
        if i == mh_idx:
            out.append(f"{MH_KEY}: []{nl}" if not stay_entries else f"{MH_KEY}:{nl}")
            for it in staying_items:
                out.extend(it["lines"])
            i = mh_block_end
            # provenance_log кладём сразу за историей, если отдельного поля ещё не было
            if pl_idx is None:
                out.append(f"{PL_KEY}:{nl}")
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

    # ── Инвариант строк: набор сохранён побайтово, добавлены только строки-заголовки ──
    # Заголовок provenance_log добавляется ТОЛЬКО когда поля ещё не было (D290: при
    # существующем поле новой строки нет, и безусловное ожидание роняло разбор).
    before, after = Counter(original), Counter(out)
    added = after - before
    removed = before - after
    allowed_added: Counter = Counter()
    if pl_idx is None:
        allowed_added[f"{PL_KEY}:{nl}"] += 1
    if not stay_entries:
        allowed_added[f"{MH_KEY}: []{nl}"] += 1
    allowed_removed = Counter() if stay_entries else Counter({original[mh_idx]: 1})
    if added != allowed_added or removed != allowed_removed:
        raise Unsafe(
            f"инвариант строк нарушен. Лишние: {list(added)[:2]}, потерянные: {list(removed)[:2]}"
        )

    # ── Свойства выхода: файл остаётся валидным YAML и несёт ТЕ ЖЕ записи ──
    if old_data is not None:
        try:
            _, new_fm_end = frontmatter_bounds(out)
        except Skip:
            raise Unsafe("после переноса frontmatter не найден")
        new_data = frontmatter_data(out, fm_start, new_fm_end)
        if new_data is None:
            raise Unsafe("после переноса frontmatter перестал быть валидным YAML")
        old_all = list(old_data.get(MH_KEY) or []) + list(old_data.get(PL_KEY) or [])
        new_all = list(new_data.get(MH_KEY) or []) + list(new_data.get(PL_KEY) or [])
        if sorted(map(repr, old_all)) != sorted(map(repr, new_all)):
            raise Unsafe(
                f"набор записей изменился: было {len(old_all)}, стало {len(new_all)}"
            )
        if prov_entries(new_data.get(MH_KEY)):
            raise Unsafe("в modification_history остался провенанс-вид")
        new_pl = list(new_data.get(PL_KEY) or [])
        if len(prov_entries(new_pl)) != len(new_pl):
            raise Unsafe("в provenance_log попала не-провенанс запись")
        rest_old = {k: v for k, v in old_data.items() if k not in (MH_KEY, PL_KEY)}
        rest_new = {k: v for k, v in new_data.items() if k not in (MH_KEY, PL_KEY)}
        if rest_old != rest_new:
            raise Unsafe("остальные поля frontmatter изменились")

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
    # Предикат для строки «Проверка результата» шапки: она обязана мерять ОБЪЯВЛЕННЫЙ результат,
    # а не след прогона. Прежняя проверка (`grep -l 'provenance_log:' …`) была зелена от одного
    # совпавшего файла из 440 — замер 3 сентября 2026: 83 файла с provenance_log, 59 со строкой
    # modification_history, остаток провенанс-видов 0, и код возврата 0 при любом из этих чисел (D282).
    # Отрицательный контроль на отсутствие ПРЕДМЕТА (D302): ноль осмотренных файлов — код 2,
    # а не 0; «базы нет» никогда не читается как «результат достигнут».
    ap.add_argument("--check", action="store_true", help="ничего не писать; 1 — остаток есть, 0 — переносить нечего, 2 — предмета нет")
    ap.add_argument("--exclude", nargs="*", default=["META.md", "source-tiers.md"],
                    help="файлы-исключения: спецификации, а не знания")
    args = ap.parse_args()

    root = pathlib.Path(args.dir).expanduser()
    files = sorted(p for p in root.glob("*.md") if p.name not in args.exclude)

    if args.apply and not args.check and yaml is None:
        print("ОТКАЗ: без модуля yaml проверить выход нечем — запись запрещена "
              "(поставьте PyYAML либо запускайте --check)")
        return 2

    total = Counter()
    touched = 0
    examined = 0
    refused: list[str] = []

    def refuse(name: str, why: str) -> None:
        refused.append(f"{name}: {why}")
        print(f"  ОТКАЗ {name}: {why} — файл не тронут")

    for path in files:
        # Пофайловая транзакция: ни одно исключение не обрывает прогон целиком (D301).
        try:
            out, stats = migrate(path)
        except NotKnowledge:
            continue
        except Skip:
            examined += 1
            continue
        except Unsafe as exc:
            examined += 1
            refuse(path.name, str(exc))
            continue
        except Exception as exc:  # noqa: BLE001 — сбой одного файла не отменяет остальных
            examined += 1
            refuse(path.name, f"{type(exc).__name__}: {exc}")
            continue
        examined += 1
        total.update(stats)
        print(f"  {path.name}: перенесено {stats['перенесено']}, "
              f"осталось {stats['осталось']}, комментариев/пустых {stats['loose']}")
        if args.apply and not args.check:
            # Замок ПОФАЙЛОВЫЙ: взаимное исключение живёт на общем ИМЕНИ, а у базы знаний
            # их было три (каталог у `knowledge-link-symmetry.sh`, файл у
            # `knowledge-audit-digest.sh`, никакого у `knowledge-counter-bump.sh`).
            # Сведено к имени `<файл>.lock` — том, что уже берёт `atomic_filter`.
            try:
                with with_lock(str(path)):
                    write_lines(path, out)
            except Exception as exc:  # noqa: BLE001
                refuse(path.name, f"запись не удалась: {type(exc).__name__}: {exc}")
                continue
        touched += 1

    if not examined:
        print(f"\nПРЕДМЕТА НЕТ: в {root} ни одного файла знания с frontmatter — "
              "это не «результат достигнут»")
        return 2

    mode = "ЗАПИСАНО" if args.apply and not args.check else "СУХОЙ ПРОГОН"
    print(f"\n{mode}: осмотрено файлов {examined}, затронуто {touched}, "
          f"перенесено записей {total['перенесено']}, оставлено {total['осталось']}, "
          f"отказов {len(refused)}")
    if refused:
        return 1 if args.check else 2
    if args.check and total["перенесено"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
