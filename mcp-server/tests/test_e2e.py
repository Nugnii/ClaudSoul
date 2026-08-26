"""End-to-end test: parse sample.md → source_store → integrate."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ingest import parse  # noqa: E402
from ingest.integrate import integrate  # noqa: E402
from ingest.schemas import validate_extract_output  # noqa: E402
from ingest.source_store import SourceIndexEntry, SourceStore  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "sample.md"


def test_pipeline_end_to_end(tmp_path):
    sources_root = tmp_path / "sources"
    lessons_dir = tmp_path / "global-lessons"
    source_id = "techflow-sample-2026-04-20"

    res = parse(FIXTURE, source_id=source_id)
    store = SourceStore(root=sources_root)
    store.append_index(
        SourceIndexEntry(
            id=source_id,
            type="document",
            format="md",
            original_path=str(FIXTURE),
            title="TechFlow",
            ingested_at="2026-04-20T21:00:00Z",
            stages_completed=["parse"],
            block_count=len(res.blocks),
        )
    )
    store.write_meta(
        source_id,
        {"id": source_id, "parser": res.parser, "parser_version": res.parser_version},
    )
    store.write_markdown(source_id, res.markdown)
    store.write_parsed(
        source_id,
        [
            {
                "block_id": b.block_id,
                "source_id": b.source_id,
                "block_type": b.block_type,
                "text": b.text,
                "provenance": b.provenance,
            }
            for b in res.blocks
        ],
    )

    assert (sources_root / source_id / "markdown.md").exists()
    assert (sources_root / source_id / "parsed.jsonl").exists()
    assert (sources_root / source_id / "meta.yaml").exists()

    extract_payload = {
        "source_id": source_id,
        "entities": [
            {
                "name": "TechFlow",
                "entity_type": "company",
                "domain": ["b2b_sales"],
                "attributes": {
                    "founded": {"value": "2019", "source_type": "document", "sources": [f"{source_id}:p1"]},
                    "hq": {"value": "Москва", "source_type": "document", "sources": [f"{source_id}:p1"]},
                    "arr": {"value": "4.2M USD", "source_type": "document", "sources": [f"{source_id}:p2"]},
                },
            }
        ],
        "facts": [
            {
                "description": "TechFlow была основана в 2019 году в Москве как финтех-стартап.",
                "fact_type": "event",
                "sources": [{"id": f"{source_id}:p1", "type": "document", "extracted": "2026-04-20"}],
                "entity_refs": ["entity-techflow.md"],
            }
        ],
        "relations": [],
    }
    validate_extract_output(extract_payload)

    summary = integrate(extract_payload, lessons_dir)
    assert summary["entities_created"] == ["entity-techflow.md"]
    assert len(summary["facts_created"]) == 1
    assert summary["relations_created"] == []

    entity_path = lessons_dir / "entity-techflow.md"
    meta = yaml.safe_load(entity_path.read_text().split("---")[1])
    assert meta["entity_type"] == "company"
    assert set(meta["attributes"].keys()) == {"founded", "hq", "arr"}
    assert meta["attributes"]["founded"]["confidence"] == 2

    store.update_index_entry(
        source_id,
        stages_completed=["parse", "extract", "integrate"],
        entity_count=1,
        fact_count=1,
        relation_count=0,
    )
    rows = store.read_index()
    assert rows[0]["stages_completed"] == ["parse", "extract", "integrate"]

    summary2 = integrate(extract_payload, lessons_dir)
    assert summary2["entities_merged"] == ["entity-techflow.md"]
    assert summary2["facts_merged"] == [list(lessons_dir.glob("fact-*.md"))[0].name]
