"""Tests for DOCX/HTML ingestion via markitdown."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def _by_type(blocks, block_type):
    return [b for b in blocks if b.block_type == block_type]


def test_html_parse(tmp_path):
    pytest.importorskip("markitdown")
    from ingest import parse

    html = """<html><body>
<h1>TechFlow</h1>
<p>Fintech startup founded in 2019.</p>
<h2>Metrics</h2>
<ul>
<li>ARR: 4.2M USD</li>
<li>Churn: 3.1%</li>
</ul>
</body></html>"""
    p = tmp_path / "doc.html"
    p.write_text(html, encoding="utf-8")

    res = parse(p, source_id="html-test")
    assert res.parser == "markitdown"
    headings = [b.text for b in _by_type(res.blocks, "heading")]
    assert "TechFlow" in headings
    assert "Metrics" in headings
    items = [b.text for b in _by_type(res.blocks, "list_item")]
    assert any("ARR" in i for i in items)
    assert any("Churn" in i for i in items)


def test_docx_parse(tmp_path):
    pytest.importorskip("markitdown")
    docx_mod = pytest.importorskip("docx")
    from ingest import parse

    doc = docx_mod.Document()
    doc.add_heading("Vasturiano", level=1)
    doc.add_paragraph("Author of the force-graph ecosystem.")
    doc.add_heading("Projects", level=2)
    doc.add_paragraph("3d-force-graph: 4000+ stars on GitHub.")
    p = tmp_path / "bio.docx"
    doc.save(str(p))

    res = parse(p, source_id="docx-test")
    assert res.parser == "markitdown"
    headings = [b.text for b in _by_type(res.blocks, "heading")]
    assert "Vasturiano" in headings
    assert "Projects" in headings
    paragraphs = [b.text for b in _by_type(res.blocks, "paragraph")]
    assert any("force-graph" in p for p in paragraphs)


def test_heading_path_docx(tmp_path):
    pytest.importorskip("markitdown")
    docx_mod = pytest.importorskip("docx")
    from ingest import parse

    doc = docx_mod.Document()
    doc.add_heading("Top", level=1)
    doc.add_heading("Sub", level=2)
    doc.add_paragraph("Body under Top/Sub.")
    p = tmp_path / "nested.docx"
    doc.save(str(p))

    res = parse(p, source_id="docx-heading-path")
    body = next(b for b in res.blocks if b.block_type == "paragraph" and "Body under" in b.text)
    assert body.provenance["heading_path"] == ["Top", "Sub"]
