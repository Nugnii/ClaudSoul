"""Smoke test for PDF reader via pymupdf4llm — generates a tiny PDF fixture on the fly."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def _make_pdf(path: Path) -> None:
    pymupdf = pytest.importorskip("pymupdf")
    doc = pymupdf.open()
    for i, title in enumerate(["Intro", "Body"], start=1):
        page = doc.new_page()
        page.insert_text((72, 72), f"{title} page {i}", fontsize=16)
        page.insert_text((72, 120), f"Contents of {title}. Just a paragraph.", fontsize=12)
    doc.save(str(path))
    doc.close()


def test_pdf_parse(tmp_path):
    pytest.importorskip("pymupdf4llm")
    from ingest import parse

    pdf_path = tmp_path / "sample.pdf"
    _make_pdf(pdf_path)

    res = parse(pdf_path, source_id="pdf-sample")
    assert res.parser == "pymupdf4llm"
    assert res.blocks, "expected blocks extracted from PDF"

    pages_seen = {b.provenance.get("page") for b in res.blocks if b.provenance.get("page")}
    assert pages_seen == {1, 2}
