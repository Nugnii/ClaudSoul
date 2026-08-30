"""Frontmatter живой базы знаний обязан парситься YAML'ом.

Повод (2026-08-11). Строка `description: … это не ловит: он проверяет …` — валидный русский
и невалидный YAML: двоеточие с пробелом внутри незакавыченного скаляра читается как вложенное
отображение. Замер: 21 файл из 317, включая `principle-affect-as-engineering` и
`pattern-shell-portability`.

Почему тестом. `test_frontmatter.py` рядом проверяет парсер на выдуманных строках
(`"---\\nname: X\\n---\\nтело"`) и живую базу не открывает вовсе — предмет того теста «умеет
ли парсер парсить», предмет этого «парсится ли то, что реально записано». Разница в предмете
и позволила 21 файлу жить при 113 зелёных тестах (`pattern-subject-of-measurement-mismatch`).

Почему одного salvage мало. Парсер деградирует мягко и достаёт скаляры построчно, поэтому
знание не теряется целиком — но СПИСКИ (`edges`, `source_cases`, `related`, `domain`, `tags`)
он не восстанавливает. Связи графа исчезают тихо, а запись выглядит здоровой: пластырь без
детектора делает класс менее заметным, чем он был.

Мгновенную реакцию даёт хук `knowledge-frontmatter-check.sh` (PostToolUse на запись в базу);
этот тест — второй рубеж: ловит накопленный долг и регресс целиком, включая классы, которые
regex-режим хука не видит.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from frontmatter import split_frontmatter  # noqa: E402

LESSONS = Path.home() / ".claude" / "global-lessons"

# Списочные поля: ради них всё и делается — именно они теряются при битом YAML.
LIST_FIELDS = ("edges", "source_cases", "related", "domain", "tags")


def _knowledge_files() -> list[Path]:
    if not LESSONS.is_dir():
        return []
    return [
        f
        for f in sorted(LESSONS.glob("*.md"))
        if not f.name.startswith("_") and f.name != "META.md"
    ]


def _frontmatter_raw(path: Path) -> str | None:
    raw = path.read_text(encoding="utf-8", errors="replace")
    if not raw.startswith("---"):
        return None
    parts = raw.split("---", 2)
    return parts[1] if len(parts) >= 3 else None


@pytest.mark.skipif(not LESSONS.is_dir(), reason="рабочая база знаний недоступна")
def test_every_knowledge_file_has_parseable_frontmatter():
    """Ни один файл базы не должен полагаться на аварийный разбор скаляров."""
    broken = []
    for f in _knowledge_files():
        fm = _frontmatter_raw(f)
        if fm is None:
            continue
        try:
            yaml.safe_load(fm)
        except yaml.YAMLError as e:
            mark = getattr(e, "problem_mark", None)
            where = f"строка {mark.line + 1}" if mark else "?"
            broken.append(f"  {f.name} — {str(e).splitlines()[0].strip()} ({where})")

    assert not broken, (
        "битый YAML frontmatter (скаляры спасёт salvage, СПИСКИ будут потеряны молча):\n"
        + "\n".join(broken)
        + "\n  Лечится кавычками вокруг значения, содержащего «: »."
    )


@pytest.mark.skipif(not LESSONS.is_dir(), reason="рабочая база знаний недоступна")
def test_declared_list_fields_are_actually_lists():
    """Объявленный список обязан читаться списком, а не строкой и не пустотой.

    Отдельно от теста выше: YAML может быть валиден, а поле оформлено так, что парсер
    отдаёт строку — связь при этом существует на бумаге и не существует для обхода графа.
    """
    bad = []
    for f in _knowledge_files():
        fm = _frontmatter_raw(f)
        if fm is None:
            continue
        meta, _ = split_frontmatter(f.read_text(encoding="utf-8", errors="replace")) or ({}, "")
        for field in LIST_FIELDS:
            if field not in fm:
                continue  # поле не объявлено — нечего проверять
            value = meta.get(field)
            if value is None:
                bad.append(f"  {f.name}: поле «{field}» объявлено, но не прочитано")
            elif isinstance(value, str):
                bad.append(f"  {f.name}: поле «{field}» прочитано строкой, а не списком")

    assert not bad, "списочные поля потеряны или вырождены:\n" + "\n".join(bad)
