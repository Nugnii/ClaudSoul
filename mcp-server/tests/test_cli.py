"""Tests for ingest CLI — parse + integrate + show-schema."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

FIXTURE = Path(__file__).parent / "fixtures" / "sample.md"
MCP_SERVER = Path(__file__).resolve().parents[1]


def _run(args, env_extra=None, cwd=None):
    env = {**os.environ, **(env_extra or {})}
    return subprocess.run(
        [sys.executable, "-m", "ingest.cli", *args],
        cwd=str(cwd or MCP_SERVER),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_cli_show_schema():
    r = _run(["show-schema", "extract_output"])
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["$id"] == "claudsoul://schemas/extract_output"


def test_cli_parse_writes_source_dir(tmp_path):
    sources = tmp_path / "sources"
    r = _run(
        ["parse", str(FIXTURE), "--title", "Sample"],
        env_extra={"CLAUDE_SOURCES_ROOT": str(sources)},
    )
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    sid = out["source_id"]
    assert (sources / sid / "markdown.md").exists()
    assert (sources / sid / "parsed.jsonl").exists()
    assert (sources / sid / "meta.yaml").exists()
    assert out["block_count"] > 0


def test_cli_integrate_round_trip(tmp_path):
    sources = tmp_path / "sources"
    lessons = tmp_path / "lessons"

    parse_result = _run(
        ["parse", str(FIXTURE), "--title", "TechFlow"],
        env_extra={"CLAUDE_SOURCES_ROOT": str(sources)},
    )
    assert parse_result.returncode == 0, parse_result.stderr
    sid = json.loads(parse_result.stdout)["source_id"]

    payload = {
        "source_id": sid,
        "entities": [
            {
                "name": "TechFlow",
                "entity_type": "company",
                "domain": ["b2b_sales"],
                "attributes": {
                    "founded": {"value": "2019", "source_type": "document", "sources": [f"{sid}:p1"]}
                },
            }
        ],
        "facts": [
            {
                "description": "TechFlow основана в 2019 году в Москве.",
                "fact_type": "event",
                "sources": [{"id": f"{sid}:p1", "type": "document", "extracted": "2026-04-20"}],
                "entity_refs": ["entity-techflow.md"],
            }
        ],
        "relations": [],
    }
    payload_path = tmp_path / "extract.json"
    payload_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    r = _run(
        ["integrate", str(payload_path), "--lessons-dir", str(lessons)],
        env_extra={"CLAUDE_SOURCES_ROOT": str(sources)},
    )
    assert r.returncode == 0, r.stderr
    summary = json.loads(r.stdout)
    assert summary["entities_created"] == ["entity-techflow.md"]
    assert len(summary["facts_created"]) == 1
    assert (lessons / "entity-techflow.md").exists()

    index_rows = [json.loads(line) for line in (sources / "index.jsonl").read_text().splitlines()]
    row = next(r for r in index_rows if r["id"] == sid)
    assert row["stages_completed"] == ["parse", "extract", "integrate"]


def test_cli_show_entity(tmp_path):
    sources = tmp_path / "sources"
    lessons = tmp_path / "lessons"

    parse_result = _run(
        ["parse", str(FIXTURE), "--title", "TechFlow"],
        env_extra={"CLAUDE_SOURCES_ROOT": str(sources)},
    )
    sid = json.loads(parse_result.stdout)["source_id"]

    payload = {
        "source_id": sid,
        "entities": [
            {
                "name": "TechFlow",
                "aliases": ["TF"],
                "entity_type": "company",
                "domain": ["b2b_sales"],
                "attributes": {
                    "founded": {"value": "2019", "source_type": "document", "sources": [f"{sid}:p1"]}
                },
            }
        ],
        "facts": [
            {
                "description": "TechFlow основана в 2019.",
                "fact_type": "event",
                "sources": [{"id": f"{sid}:p1", "type": "document"}],
                "entity_refs": ["entity-techflow.md"],
            }
        ],
        "relations": [],
    }
    payload_path = tmp_path / "extract.json"
    payload_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    _run(
        ["integrate", str(payload_path), "--lessons-dir", str(lessons)],
        env_extra={"CLAUDE_SOURCES_ROOT": str(sources)},
    )

    r = _run(["show-entity", "TechFlow", "--lessons-dir", str(lessons)])
    assert r.returncode == 0, r.stderr
    data = json.loads(r.stdout)
    assert data["name"] == "TechFlow"
    assert data["entity_type"] == "company"
    assert data["aliases"] == ["TF"]
    assert "founded" in data["attributes"]
    assert len(data["related_facts"]) == 1
    assert data["related_facts"][0]["description"].startswith("TechFlow")

    r_alias = _run(["show-entity", "TF", "--lessons-dir", str(lessons)])
    assert r_alias.returncode == 0
    assert json.loads(r_alias.stdout)["name"] == "TechFlow"

    r_missing = _run(["show-entity", "NoSuchEntity", "--lessons-dir", str(lessons)])
    assert r_missing.returncode == 4
    assert json.loads(r_missing.stdout)["error"] == "not_found"


def test_cli_activate_matches_name_and_alias(tmp_path):
    sources = tmp_path / "sources"
    lessons = tmp_path / "lessons"

    parse_result = _run(
        ["parse", str(FIXTURE), "--title", "TechFlow"],
        env_extra={"CLAUDE_SOURCES_ROOT": str(sources)},
    )
    sid = json.loads(parse_result.stdout)["source_id"]

    payload = {
        "source_id": sid,
        "entities": [
            {
                "name": "TechFlow",
                "aliases": ["TF"],
                "entity_type": "company",
                "domain": ["b2b_sales"],
                "attributes": {
                    "industry": {"value": "fintech", "source_type": "document", "sources": [f"{sid}:p1"]}
                },
            }
        ],
        "facts": [],
        "relations": [],
    }
    payload_path = tmp_path / "extract.json"
    payload_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    _run(
        ["integrate", str(payload_path), "--lessons-dir", str(lessons), "--no-discover"],
        env_extra={"CLAUDE_SOURCES_ROOT": str(sources)},
    )

    r = _run(["activate", "working with techflow fintech", "--lessons-dir", str(lessons)])
    assert r.returncode == 0, r.stderr
    cards = json.loads(r.stdout)
    assert len(cards) == 1
    assert cards[0]["name"] == "TechFlow"
    assert cards[0]["score"] > 0

    r_alias = _run(["activate", "integrate TF pipeline", "--lessons-dir", str(lessons)])
    cards_alias = json.loads(r_alias.stdout)
    assert len(cards_alias) == 1
    assert cards_alias[0]["name"] == "TechFlow"

    r_none = _run(["activate", "unrelated query xyz", "--lessons-dir", str(lessons)])
    assert json.loads(r_none.stdout) == []


def test_cli_activate_respects_limit(tmp_path):
    lessons = tmp_path / "lessons"
    sources = tmp_path / "sources"
    payload = {
        "source_id": "multi",
        "entities": [
            {"name": "Alpha", "entity_type": "company", "domain": ["test"], "attributes": {}},
            {"name": "Beta", "entity_type": "company", "domain": ["test"], "attributes": {}},
            {"name": "Gamma", "entity_type": "company", "domain": ["test"], "attributes": {}},
        ],
        "facts": [],
        "relations": [],
    }
    payload_path = tmp_path / "extract.json"
    payload_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    _run(
        ["integrate", str(payload_path), "--lessons-dir", str(lessons), "--no-discover"],
        env_extra={"CLAUDE_SOURCES_ROOT": str(sources)},
    )

    r = _run(["activate", "test alpha beta gamma", "--lessons-dir", str(lessons), "--limit", "2"])
    cards = json.loads(r.stdout)
    assert len(cards) == 2


def test_cli_slug_preserves_unicode():
    r_ascii = _run(["slug", "TechFlow"])
    assert r_ascii.returncode == 0
    assert r_ascii.stdout.strip() == "entity-techflow.md"

    r_cyr = _run(["slug", "Польша"])
    assert r_cyr.stdout.strip() == "entity-польша.md"

    r_pl = _run(["slug", "Umowa o dzieło"])
    assert r_pl.stdout.strip() == "entity-umowa-o-dzieło.md"


def test_cli_integrate_rejects_invalid_schema(tmp_path):
    bad = {"source_id": "x", "entities": [{"name": "", "entity_type": "alien", "attributes": {}}], "facts": [], "relations": []}
    p = tmp_path / "bad.json"
    p.write_text(json.dumps(bad), encoding="utf-8")
    lessons = tmp_path / "lessons"
    r = _run(["integrate", str(p), "--lessons-dir", str(lessons)])
    assert r.returncode != 0
    assert "ValidationError" in r.stderr or "valid" in r.stderr.lower()
