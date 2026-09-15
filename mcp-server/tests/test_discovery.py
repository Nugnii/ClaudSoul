"""Tests for Discovery Engine — co-occurrence, shared-attribute, contradictions."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ingest.discovery import detect_cross_contour_mentions, discover  # noqa: E402
from ingest.integrate import _parse_frontmatter, _write_file, integrate  # noqa: E402


def _doc_payload(source_id: str, entities, facts, relations=None):
    return {
        "source_id": source_id,
        "entities": entities,
        "facts": facts,
        "relations": relations or [],
    }


def _ent(name, entity_type="company", domain=None, attrs=None):
    return {
        "name": name,
        "entity_type": entity_type,
        "domain": domain or ["test"],
        "attributes": attrs or {},
    }


def _fact(desc, refs, source_id, fact_type="event"):
    return {
        "description": desc,
        "fact_type": fact_type,
        "sources": [{"id": f"{source_id}:p1", "type": "document"}],
        "entity_refs": refs,
    }


def test_co_occurrence_two_shared_sources(tmp_path):
    lessons = tmp_path / "lessons"
    for sid in ("doc-a", "doc-b"):
        integrate(
            _doc_payload(
                sid,
                [_ent("Alice", "person"), _ent("Bob", "person")],
                [
                    _fact(f"Alice событие {sid}", ["entity-alice.md"], sid),
                    _fact(f"Bob событие {sid}", ["entity-bob.md"], sid),
                ],
            ),
            lessons,
        )

    result = discover(lessons)
    assert len(result["co_occurrence"]) == 1
    rel_file = result["co_occurrence"][0]
    assert (lessons / rel_file).exists()


def test_co_occurrence_requires_two_sources(tmp_path):
    lessons = tmp_path / "lessons"
    integrate(
        _doc_payload(
            "doc-a",
            [_ent("Alice", "person"), _ent("Bob", "person")],
            [
                _fact("Alice событие", ["entity-alice.md"], "doc-a"),
                _fact("Bob событие", ["entity-bob.md"], "doc-a"),
            ],
        ),
        lessons,
    )
    result = discover(lessons)
    assert result["co_occurrence"] == []


def test_shared_attribute_employer(tmp_path):
    lessons = tmp_path / "lessons"
    integrate(
        _doc_payload(
            "doc-a",
            [
                _ent(
                    "Alice",
                    "person",
                    attrs={"employer": {"value": "Acme", "source_type": "document", "sources": ["doc-a:p1"]}},
                ),
                _ent(
                    "Bob",
                    "person",
                    attrs={"employer": {"value": "Acme", "source_type": "document", "sources": ["doc-a:p1"]}},
                ),
            ],
            [],
        ),
        lessons,
    )
    result = discover(lessons)
    assert len(result["shared_attr"]) == 1
    rel_file = result["shared_attr"][0]
    assert "works_with" in rel_file


def test_shared_attribute_different_values(tmp_path):
    lessons = tmp_path / "lessons"
    integrate(
        _doc_payload(
            "doc-a",
            [
                _ent(
                    "Alice",
                    "person",
                    attrs={"employer": {"value": "Acme", "source_type": "document", "sources": ["doc-a:p1"]}},
                ),
                _ent(
                    "Bob",
                    "person",
                    attrs={"employer": {"value": "Globex", "source_type": "document", "sources": ["doc-a:p1"]}},
                ),
            ],
            [],
        ),
        lessons,
    )
    result = discover(lessons)
    assert result["shared_attr"] == []


def test_discovery_does_not_duplicate_existing_relation(tmp_path):
    lessons = tmp_path / "lessons"
    for sid in ("doc-a", "doc-b"):
        integrate(
            _doc_payload(
                sid,
                [_ent("Alice", "person"), _ent("Bob", "person")],
                [
                    _fact(f"Alice {sid}", ["entity-alice.md"], sid),
                    _fact(f"Bob {sid}", ["entity-bob.md"], sid),
                ],
            ),
            lessons,
        )

    first = discover(lessons)
    assert len(first["co_occurrence"]) == 1
    second = discover(lessons)
    assert second["co_occurrence"] == []


def test_contradiction_same_entity_divergent_facts(tmp_path):
    lessons = tmp_path / "lessons"
    integrate(
        _doc_payload(
            "doc-a",
            [_ent("Acme", "company")],
            [
                _fact(
                    "Компания Acme была основана в 2010 году в Сан-Франциско.",
                    ["entity-acme.md"],
                    "doc-a",
                    fact_type="attribute",
                ),
                _fact(
                    "Компания Acme была основана в 2015 году в Нью-Йорке.",
                    ["entity-acme.md"],
                    "doc-a",
                    fact_type="attribute",
                ),
            ],
        ),
        lessons,
    )
    result = discover(lessons)
    assert len(result["contradictions"]) >= 1

    edges_found = False
    for p in lessons.glob("fact-*.md"):
        text = p.read_text(encoding="utf-8")
        if "contradicts" in text:
            edges_found = True
            break
    assert edges_found


def test_discover_empty_dir(tmp_path):
    result = discover(tmp_path / "does-not-exist")
    assert result == {
        "co_occurrence": [],
        "shared_attr": [],
        "contradictions": [],
        "cross_contour": [],
        "skipped_duplicates": 0,
    }


def _write_knowledge(lessons: Path, name: str, body: str) -> None:
    lessons.mkdir(parents=True, exist_ok=True)
    meta = {"name": name, "type": "case", "confidence": 1, "status": "active"}
    _write_file(lessons / name, meta, body)


def test_cross_contour_mention_detected(tmp_path, monkeypatch):
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(
        lessons,
        "case-2026-04-22-acme-deal.md",
        "В работе с клиентом Acme мы столкнулись с задержкой согласования. Acme отказался.",
    )
    result = discovery_mod.discover(lessons)
    assert any("entity-acme.md" in s for s in result["cross_contour"])
    assert log_path.exists()
    assert "entity-acme.md" in log_path.read_text(encoding="utf-8")


def test_cross_contour_no_match_when_no_mention(tmp_path, monkeypatch):
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(
        lessons,
        "case-2026-04-22-other.md",
        "Случай про что-то совершенно другое, без упоминаний компаний.",
    )
    result = discovery_mod.discover(lessons)
    assert result["cross_contour"] == []


def test_cross_contour_alias_match(tmp_path, monkeypatch):
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    payload = _doc_payload("doc-a", [_ent("Polska", "country")], [])
    payload["entities"][0]["aliases"] = ["Польша"]
    integrate(payload, lessons)
    _write_knowledge(
        lessons,
        "case-2026-04-22-poland.md",
        "Кейс по Polska: налоговый режим отличается. Также упомянем Польша.",
    )
    result = discovery_mod.discover(lessons)
    assert any("entity-polska.md" in s for s in result["cross_contour"])
