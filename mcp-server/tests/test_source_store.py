"""Tests for SourceStore: index.jsonl + meta.yaml + parsed.jsonl round-trip."""

from __future__ import annotations

import json
import sys
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ingest import parse  # noqa: E402
from ingest.source_store import SourceIndexEntry, SourceStore  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "sample.md"


def test_index_append_and_read(tmp_path):
    store = SourceStore(root=tmp_path)
    entry = SourceIndexEntry(
        id="s1",
        type="document",
        format="md",
        original_path=str(FIXTURE),
        title="Sample",
        ingested_at="2026-04-20T21:00:00Z",
        stages_completed=["parse"],
    )
    store.append_index(entry)

    rows = store.read_index()
    assert len(rows) == 1
    assert rows[0]["id"] == "s1"
    assert rows[0]["stages_completed"] == ["parse"]


def test_index_update_entry(tmp_path):
    store = SourceStore(root=tmp_path)
    store.append_index(
        SourceIndexEntry(
            id="s1",
            type="document",
            format="md",
            original_path="/x",
            title="Sample",
            ingested_at="2026-04-20T21:00:00Z",
            stages_completed=["parse"],
        )
    )
    store.update_index_entry("s1", stages_completed=["parse", "extract"], block_count=12)
    rows = store.read_index()
    assert rows[0]["stages_completed"] == ["parse", "extract"]
    assert rows[0]["block_count"] == 12


def test_meta_round_trip(tmp_path):
    store = SourceStore(root=tmp_path)
    meta = {
        "id": "s1",
        "type": "document",
        "format": "md",
        "parser": "pass_through",
        "parse_warnings": [],
    }
    store.write_meta("s1", meta)
    assert store.read_meta("s1") == meta


def test_parsed_jsonl_round_trip(tmp_path):
    store = SourceStore(root=tmp_path)
    res = parse(FIXTURE, source_id="s1")
    as_dicts = [
        {
            "block_id": b.block_id,
            "source_id": b.source_id,
            "block_type": b.block_type,
            "text": b.text,
            "provenance": b.provenance,
        }
        for b in res.blocks
    ]
    path = store.write_parsed("s1", as_dicts)
    lines = path.read_text(encoding="utf-8").splitlines()
    assert len(lines) == len(res.blocks)

    first = json.loads(lines[0])
    assert first["block_id"] == "b000"
    assert first["source_id"] == "s1"
    assert first["block_type"] == "heading"
    assert "heading_path" in first["provenance"]
