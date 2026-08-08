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

from pathlib import Path

import yaml


def split_frontmatter(text: str):
    """Разобрать текст на (meta, body).

    Возвращает кортеж (dict, str) если есть frontmatter (meta={} при битом YAML),
    либо None если frontmatter отсутствует.
    """
    if not text.startswith("---"):
        return None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None
    try:
        meta = yaml.safe_load(parts[1]) or {}
    except yaml.YAMLError:
        meta = {}
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
