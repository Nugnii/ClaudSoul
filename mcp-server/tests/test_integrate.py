"""Tests for integrate stage — dedup, confidence recalc, merged_candidate."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ingest.integrate import _merge_scalar_attrs, _resolve_entity_ref, integrate, recalc_confidence  # noqa: E402


def _payload(**overrides):
    base = {
        "source_id": "s1",
        "entities": [
            {
                "name": "TechFlow",
                "entity_type": "company",
                "domain": ["b2b_sales"],
                "attributes": {
                    "industry": {
                        "value": "fintech",
                        "source_type": "document",
                        "sources": ["s1:p1"],
                    }
                },
            }
        ],
        "facts": [
            {
                "description": "TechFlow была основана в 2019 году в Москве.",
                "fact_type": "event",
                "sources": [{"id": "s1:p1", "type": "document"}],
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
    base.update(overrides)
    return base


def test_confidence_single_source():
    assert recalc_confidence(["self_report"]) == 1
    assert recalc_confidence(["document"]) == 2
    assert recalc_confidence(["behavioral"]) == 3
    assert recalc_confidence(["cross_reference"]) == 4


def test_confidence_bonus_for_distinct_sources():
    assert recalc_confidence(["document", "behavioral"]) == 4
    assert recalc_confidence(["document", "document"]) == 2
    assert recalc_confidence(["self_report", "cross_reference"]) == 4


def test_confidence_capped_at_5():
    assert recalc_confidence(["cross_reference", "cross_reference", "cross_reference", "behavioral"]) == 5
    assert recalc_confidence(["cross_reference"] * 10 + ["behavioral"]) == 5


def test_integrate_creates_new(tmp_path):
    summary = integrate(_payload(), tmp_path)
    assert len(summary["entities_created"]) == 1
    assert len(summary["facts_created"]) == 1
    assert len(summary["relations_created"]) == 1
    assert (tmp_path / "entity-techflow.md").exists()


def test_integrate_dedup_entity(tmp_path):
    integrate(_payload(), tmp_path)
    summary = integrate(_payload(), tmp_path)
    assert summary["entities_created"] == []
    assert summary["entities_merged"] == ["entity-techflow.md"]


def test_integrate_similar_entity_candidate(tmp_path):
    integrate(_payload(), tmp_path)
    close = _payload()
    close["entities"][0]["name"] = "Techflow"
    summary = integrate(close, tmp_path)
    assert summary["entities_candidates"], f"expected candidate, got: {summary}"


def test_integrate_dedup_fact(tmp_path):
    integrate(_payload(), tmp_path)
    dup = _payload()
    dup["facts"][0]["sources"][0]["type"] = "behavioral"
    summary = integrate(dup, tmp_path)
    assert summary["facts_merged"]

    import yaml
    fact_files = list(tmp_path.glob("fact-*.md"))
    assert len(fact_files) == 1
    text = fact_files[0].read_text()
    meta = yaml.safe_load(text.split("---")[1])
    assert meta["confidence"] == 4


def test_integrate_dedup_relation(tmp_path):
    integrate(_payload(), tmp_path)
    summary = integrate(_payload(), tmp_path)
    assert summary["relations_merged"]
    assert not summary["relations_created"]


def test_integrate_different_entity_no_merge(tmp_path):
    integrate(_payload(), tmp_path)
    other = _payload()
    other["entities"][0]["name"] = "CompletelyDifferentCompany"
    other["entities"][0]["attributes"] = {}
    summary = integrate(other, tmp_path)
    assert summary["entities_created"] == ["entity-completelydifferentcompany.md"]


def test_resolve_entity_ref_exact_match(tmp_path):
    integrate(_payload(), tmp_path)
    resolved, ok = _resolve_entity_ref("entity-techflow.md", tmp_path)
    assert ok is True
    assert resolved == "entity-techflow.md"


def test_resolve_entity_ref_unicode_mismatch(tmp_path):
    payload = _payload()
    payload["entities"][0]["name"] = "Umowa o dzieło"
    payload["facts"] = []
    payload["relations"] = []
    integrate(payload, tmp_path)

    resolved, ok = _resolve_entity_ref("entity-umowa-o-dzielo.md", tmp_path)
    assert ok is True
    assert resolved == "entity-umowa-o-dzieło.md"


def test_resolve_entity_ref_not_found(tmp_path):
    integrate(_payload(), tmp_path)
    resolved, ok = _resolve_entity_ref("entity-completely-unrelated.md", tmp_path)
    assert ok is False
    assert resolved == "entity-completely-unrelated.md"


def test_integrate_warns_on_unresolved_refs(tmp_path):
    payload = _payload()
    payload["facts"][0]["entity_refs"] = ["entity-nonexistent-12345.md"]
    summary = integrate(payload, tmp_path)
    assert any("unresolved entity_ref" in w for w in summary["warnings"])


def test_resolve_entity_ref_via_alias_crossscript(tmp_path):
    payload = _payload()
    payload["entities"][0]["name"] = "Польша"
    payload["entities"][0]["aliases"] = ["Polska", "Poland"]
    payload["facts"] = []
    payload["relations"] = []
    integrate(payload, tmp_path)

    resolved, ok = _resolve_entity_ref("entity-polska.md", tmp_path)
    assert ok is True
    assert resolved == "entity-польша.md"

    resolved, ok = _resolve_entity_ref("entity-poland.md", tmp_path)
    assert ok is True
    assert resolved == "entity-польша.md"


def test_resolve_entity_ref_alias_preferred_over_similarity(tmp_path):
    payload = _payload()
    payload["entities"] = [
        {
            "name": "Umowa o dzieło",
            "entity_type": "document_type",
            "aliases": ["Umowa o dzielo"],
            "attributes": {},
        },
        {
            "name": "Umowa zlecenie",
            "entity_type": "document_type",
            "aliases": [],
            "attributes": {},
        },
    ]
    payload["facts"] = []
    payload["relations"] = []
    integrate(payload, tmp_path)

    resolved, ok = _resolve_entity_ref("entity-umowa-o-dzielo.md", tmp_path)
    assert ok is True
    assert resolved == "entity-umowa-o-dzieło.md"


def test_resolve_entity_ref_alias_empty_list_safe(tmp_path):
    payload = _payload()
    payload["entities"][0]["aliases"] = []
    payload["facts"] = []
    payload["relations"] = []
    integrate(payload, tmp_path)

    resolved, ok = _resolve_entity_ref("entity-techflow.md", tmp_path)
    assert ok is True
    assert resolved == "entity-techflow.md"


def test_gap_type_stated_vs_inferred():
    """H9: self_report value contradicted by behavioral inference → gap_type=stated_vs_inferred."""
    existing = {"value": "junior", "source_type": "self_report", "sources": ["chat:p1"]}
    new = {"value": "senior", "source_type": "behavioral", "sources": ["chat:p2"]}
    merged = _merge_scalar_attrs(existing, new)
    assert merged["value"] == "senior"
    assert merged["contradiction"]["stated_value"] == "junior"
    assert merged["contradiction"]["gap_type"] == "stated_vs_inferred"


def test_gap_type_source_drift():
    """Same source_type, different values → gap_type=source_drift."""
    existing = {"value": "fintech", "source_type": "document", "sources": ["s1:p1"]}
    new = {"value": "edtech", "source_type": "document", "sources": ["s2:p1"]}
    merged = _merge_scalar_attrs(existing, new)
    assert merged["contradiction"]["gap_type"] == "source_drift"


def test_gap_type_cross_source():
    """Different source_types not in stated_vs_inferred pair → gap_type=cross_source."""
    existing = {"value": "Москва", "source_type": "document", "sources": ["s1:p1"]}
    new = {"value": "Лондон", "source_type": "third_party", "sources": ["s2:p1"]}
    merged = _merge_scalar_attrs(existing, new)
    assert merged["contradiction"]["gap_type"] == "cross_source"


def test_gap_type_absent_when_values_match():
    """No contradiction → no gap_type field."""
    existing = {"value": "fintech", "source_type": "document", "sources": ["s1:p1"]}
    new = {"value": "fintech", "source_type": "behavioral", "sources": ["s2:p1"]}
    merged = _merge_scalar_attrs(existing, new)
    assert "contradiction" not in merged or "gap_type" not in (merged.get("contradiction") or {})
