"""Единый парсер YAML frontmatter для сервера MCP.

До этого модуля логика чтения «--- yaml --- body» была скопирована в 4 места с
расходящейся обработкой битого YAML: indexer.parse_knowledge_file (сохранял файл
с пустым meta), ingest.integrate._parse_frontmatter и ingest.cli._parse_fm (теряли
файл → None), brain._parse_meta (возвращал {}). Та же боль «правлю в одном, надо в N»,
что чинили в hooks через yaml-lib.sh.

Канон: None ТОЛЬКО когда frontmatter отсутствует (нет ведущего `---` или нет второго
`---`). При битом YAML файл НЕ теряется — возвращается ({}, body), чтобы потребитель
мог проиндексировать/обработать его с пустыми метаданными.
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml


_SCALAR_LINE = re.compile(r"^([A-Za-z_][\w-]*):[ \t]+(\S.*)$")


def _salvage_scalars(raw: str) -> dict:
    """Достать верхнеуровневые скалярные поля из frontmatter, который не взял YAML.

    Зачем: строка вида `description: ... это не ловит: он проверяет ...` — валидный
    русский текст и невалидный YAML («mapping values are not allowed here»), потому что
    двоеточие с пробелом внутри незакавыченного скаляра читается как вложенное отображение.
    Раньше такой файл терял ВЕСЬ frontmatter: уходил в индекс без имени и описания (в вектор
    шло голое тело), с `type: unknown` и `confidence: None` — а значит выпадал и из фильтра
    `min_confidence`. Замер на живой базе: 21 файл из 317, включая `principle-affect-as-
    engineering` и `pattern-shell-portability`.

    Разбор намеренно грубый и построчный: берём только `ключ: значение` без отступа,
    значение — весь остаток строки как текст. Блоки, списки и многострочные значения
    пропускаем — они не нужны ни поиску, ни фильтрам, а угадывать их структуру опаснее,
    чем не иметь. Числа приводим к int, чтобы работали confidence/impact.
    """
    meta: dict = {}
    for line in raw.splitlines():
        m = _SCALAR_LINE.match(line)
        if not m:
            continue
        key, value = m.group(1), m.group(2).strip()
        if value.startswith(("[", "{", "|", ">")):
            continue  # список/блок — не наше дело
        value = value.strip("'\"")
        if value.isdigit():
            meta[key] = int(value)
        elif value:
            meta[key] = value
    return meta


def split_frontmatter(text: str):
    """Разобрать текст на (meta, body).

    Возвращает кортеж (dict, str) если есть frontmatter, либо None если frontmatter
    отсутствует. При битом YAML файл НЕ теряется и НЕ обнуляется: метаданные достаются
    построчно (`_salvage_scalars`).
    """
    if not text.startswith("---"):
        return None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None
    try:
        meta = yaml.safe_load(parts[1]) or {}
    except yaml.YAMLError:
        meta = _salvage_scalars(parts[1])
    return meta, parts[2].strip()


def read_frontmatter(path):
    """Прочитать файл и разобрать frontmatter.

    None если файл нечитаем ИЛИ frontmatter отсутствует.
    """
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    return split_frontmatter(text)
