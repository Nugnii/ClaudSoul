"""Tests for Extract output JSON schemas."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def _valid_payload():
    return {
        "source_id": "s1",
        "entities": [
            {
                "name": "TechFlow",
                "entity_type": "company",
                "attributes": {
                    "industry": {
                        "value": "fintech",
                        "confidence": 3,
                        "source_type": "document",
                        "sources": ["s1:p1"],
                    }
                },
                "domain": ["b2b_sales"],
            }
        ],
        "facts": [
            {
                "description": "Компания основана в 2019 году.",
                "fact_type": "event",
                "sources": [{"id": "s1:p1", "type": "document", "extracted": "2026-04-20"}],
                "entity_refs": ["entity-techflow.md"],
            }
        ],
        "relations": [
            {
                "relation_type": "created",
                "from_entity": "entity-founder.md",
                "to_entity": "entity-techflow.md",
                "sources": [{"id": "s1:p1", "type": "document"}],
            }
        ],
    }


def test_valid_payload():
    pytest.importorskip("jsonschema")
    from ingest.schemas import validate_extract_output
    validate_extract_output(_valid_payload())


def test_missing_source_id():
    jsonschema = pytest.importorskip("jsonschema")
    from ingest.schemas import validate_extract_output
    bad = _valid_payload()
    del bad["source_id"]
    with pytest.raises(jsonschema.ValidationError):
        validate_extract_output(bad)


def test_invalid_entity_type():
    jsonschema = pytest.importorskip("jsonschema")
    from ingest.schemas import validate_extract_output
    bad = _valid_payload()
    bad["entities"][0]["entity_type"] = "alien"
    with pytest.raises(jsonschema.ValidationError):
        validate_extract_output(bad)


def test_relation_requires_sources():
    jsonschema = pytest.importorskip("jsonschema")
    from ingest.schemas import validate_extract_output
    bad = _valid_payload()
    bad["relations"][0]["sources"] = []
    with pytest.raises(jsonschema.ValidationError):
        validate_extract_output(bad)


def test_fact_requires_source_type():
    jsonschema = pytest.importorskip("jsonschema")
    from ingest.schemas import validate_extract_output
    bad = _valid_payload()
    bad["facts"][0]["sources"][0]["type"] = "hearsay"
    with pytest.raises(jsonschema.ValidationError):
        validate_extract_output(bad)
