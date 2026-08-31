"""Характеризующий тест единого парсера frontmatter.

Фиксирует канон, на который переводятся indexer/brain/ingest.integrate/ingest.cli,
чтобы дедупликация не изменила поведение незаметно.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from frontmatter import read_frontmatter, split_frontmatter  # noqa: E402


def test_valid_frontmatter():
    text = "---\nname: X\nconfidence: 5\n---\nтело документа"
    res = split_frontmatter(text)
    assert res is not None
    meta, body = res
    assert meta == {"name": "X", "confidence": 5}
    assert body == "тело документа"


def test_no_frontmatter_returns_none():
    assert split_frontmatter("просто текст без разделителей") is None


def test_single_delimiter_returns_none():
    # ведущий --- есть, второго нет → не валидный frontmatter
    assert split_frontmatter("---\nname: X\nтело без закрытия") is None


def test_broken_yaml_keeps_file_with_empty_meta():
    # КАНОН: битый YAML не теряет файл — ({}, body)
    text = "---\nname: [unclosed\n  bad: : :\n---\nтело"
    res = split_frontmatter(text)
    assert res is not None
    meta, body = res
    assert meta == {}
    assert body == "тело"


def test_empty_frontmatter_block():
    text = "---\n---\nтолько тело"
    res = split_frontmatter(text)
    assert res is not None
    meta, body = res
    assert meta == {}
    assert body == "только тело"


def test_body_is_stripped():
    text = "---\nk: v\n---\n\n  тело с пробелами  \n\n"
    _, body = split_frontmatter(text)
    assert body == "тело с пробелами"


def test_read_missing_file_returns_none():
    assert read_frontmatter(Path("/nonexistent/zzz.md")) is None


def test_read_valid_file(tmp_path):
    p = tmp_path / "k.md"
    p.write_text("---\nname: Y\n---\nсодержимое", encoding="utf-8")
    res = read_frontmatter(p)
    assert res is not None
    meta, body = res
    assert meta == {"name": "Y"}
    assert body == "содержимое"
