"""Unit tests for parse + normalize — M2."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ingest import parse  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "sample.md"


def _by_type(blocks, block_type):
    return [b for b in blocks if b.block_type == block_type]


def test_md_parse_basic():
    res = parse(FIXTURE, source_id="test-sample")
    assert res.parser == "pass_through"
    assert res.blocks, "expected at least one block"

    headings = _by_type(res.blocks, "heading")
    titles = [b.text for b in headings]
    assert titles == ["TechFlow", "Company background", "Metrics"]


def test_md_heading_path():
    res = parse(FIXTURE, source_id="test-sample")
    bg_paragraph = next(
        b for b in res.blocks
        if b.block_type == "paragraph" and "выросла из внутреннего" in b.text
    )
    assert bg_paragraph.provenance["heading_path"] == ["TechFlow", "Company background"]


def test_md_page_provenance():
    res = parse(FIXTURE, source_id="test-sample")
    metrics_heading = next(b for b in res.blocks if b.block_type == "heading" and b.text == "Metrics")
    assert metrics_heading.provenance.get("page") == 2

    techflow_heading = next(b for b in res.blocks if b.block_type == "heading" and b.text == "TechFlow")
    assert techflow_heading.provenance.get("page") == 1


def test_md_list_items():
    res = parse(FIXTURE, source_id="test-sample")
    items = [b.text for b in _by_type(res.blocks, "list_item")]
    assert "Сотрудников: 42" in items
    assert "Офисы: Москва, Ереван" in items
    assert "Клиенты: B2B SMB" in items


def test_md_table_rows():
    res = parse(FIXTURE, source_id="test-sample")
    rows = _by_type(res.blocks, "table_row")
    assert len(rows) >= 2
    assert any("ARR" in r.text for r in rows)
    assert any("Churn" in r.text for r in rows)


def test_md_code_block():
    res = parse(FIXTURE, source_id="test-sample")
    code = _by_type(res.blocks, "code_block")
    assert len(code) == 1
    assert "def revenue" in code[0].text


def test_md_quote():
    res = parse(FIXTURE, source_id="test-sample")
    quotes = _by_type(res.blocks, "quote")
    assert len(quotes) == 1
    assert "инфраструктуру" in quotes[0].text


def test_txt_wrap(tmp_path):
    p = tmp_path / "notes.txt"
    p.write_text("line one\nline two\n", encoding="utf-8")
    res = parse(p, source_id="test-txt")
    assert res.parser == "text_wrap"
    titles = [b.text for b in res.blocks if b.block_type == "heading"]
    assert titles == ["notes"]
    code = [b for b in res.blocks if b.block_type == "code_block"]
    assert len(code) == 1
    assert "line one" in code[0].text
    assert "line two" in code[0].text


def test_block_ids_sequential():
    res = parse(FIXTURE, source_id="test-sample")
    ids = [b.block_id for b in res.blocks]
    assert ids == [f"b{i:03d}" for i in range(len(ids))]
