"""Discovery Engine — find implicit relations between entities/facts.

Three detectors:
  1. co_occurrence  — entities mentioned in 2+ shared source_ids → `co_occurred_in` relation
  2. shared_attr    — entities with identical value for a link-worthy attribute → typed relation
                      (employer → works_with, studied_at → studied_together, etc.)
  3. contradiction  — two facts about same entity_refs with opposing values → `contradicts` relation

Discovered relations are marked with `discovered: true` in frontmatter and have lower
confidence than human-curated ones (co-occurrence 2, shared_attr 3).
"""

from __future__ import annotations

import json
import os
import re
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path

from .integrate import (
    SIMILAR_FACT_THRESHOLD,
    _load_by_type,
    _parse_frontmatter,
    _similarity,
    _slugify,
    _strip_entity_md,
    _write_file,
)

CROSS_CONTOUR_KNOWLEDGE_PREFIXES = ("case-", "pattern-", "principle-")
CROSS_CONTOUR_LOG_PATH = Path(
    os.environ.get(
        "CLAUDSOUL_CROSS_CONTOUR_LOG",
        str(Path.home() / ".claude" / "hooks" / "state" / "cross-contour-discoveries.jsonl"),
    )
)

SHARED_ATTR_TO_RELATION = {
    "employer": ("works_with", "both_work_at"),
    "school": ("studied_together", "alma_mater"),
    "university": ("studied_together", "alma_mater"),
    "birthplace": ("from_same_place", "birthplace"),
    "city": ("from_same_place", "city"),
    "country": ("from_same_place", "country"),
    "company": ("works_with", "both_work_at"),
    "bank": ("shares_provider", "bank"),
    "jurisdiction": ("from_same_place", "jurisdiction"),
}

CO_OCCURRENCE_MIN_SHARED_SOURCES = 2
CO_OCCURRENCE_CONFIDENCE = 2
SHARED_ATTR_CONFIDENCE = 3


@dataclass
class DiscoverySummary:
    co_occurrence: list[str] = field(default_factory=list)
    shared_attr: list[str] = field(default_factory=list)
    contradictions: list[str] = field(default_factory=list)
    cross_contour: list[str] = field(default_factory=list)
    skipped_duplicates: int = 0

    def as_dict(self) -> dict:
        return {
            "co_occurrence": self.co_occurrence,
            "shared_attr": self.shared_attr,
            "contradictions": self.contradictions,
            "cross_contour": self.cross_contour,
            "skipped_duplicates": self.skipped_duplicates,
        }


def _extract_source_ids(fm: dict) -> set[str]:
    """Pull source_ids (doc-id part before ':') from a frontmatter dict."""
    ids: set[str] = set()
    for attr in (fm.get("attributes") or {}).values():
        if isinstance(attr, dict):
            for s in attr.get("sources") or []:
                if isinstance(s, str):
                    ids.add(s.split(":", 1)[0])
    for s in fm.get("sources") or []:
        sid = s.get("id") if isinstance(s, dict) else s
        if isinstance(sid, str):
            ids.add(sid.split(":", 1)[0])
    return ids


def _entity_source_ids(ent_fm: dict, all_facts: list[dict]) -> set[str]:
    """Collect source_ids from entity's own attributes + facts referencing it."""
    ids = _extract_source_ids(ent_fm)
    fname = ent_fm["_path"].name
    for f in all_facts:
        if fname in (f.get("entity_refs") or []):
            ids |= _extract_source_ids(f)
    return ids


def _relation_key(from_entity: str, to_entity: str, relation_type: str) -> tuple[str, str, str]:
    a, b = sorted([from_entity, to_entity])
    return (a, b, relation_type)


def _build_existing_relation_keys(relations: list[dict]) -> set[tuple[str, str, str]]:
    keys: set[tuple[str, str, str]] = set()
    for r in relations:
        fe = r.get("from_entity")
        te = r.get("to_entity")
        rt = r.get("relation_type")
        if fe and te and rt:
            keys.add(_relation_key(fe, te, rt))
    return keys


def _write_discovered_relation(
    lessons_dir: Path,
    from_entity: str,
    to_entity: str,
    relation_type: str,
    confidence: int,
    description: str,
    evidence: list[str],
    idx: int,
) -> Path:
    slug_base = f"{_slugify(_strip_entity_md(from_entity))}-{relation_type}-{_slugify(_strip_entity_md(to_entity))}"
    path = lessons_dir / f"relation-{slug_base}.md"
    if path.exists():
        path = lessons_dir / f"relation-{slug_base}-discovered-{idx:04d}.md"
    today = date.today().isoformat()
    meta = {
        "name": f"{from_entity} → {relation_type} → {to_entity}",
        "description": description,
        "type": "relation",
        "relation_type": relation_type,
        "status": "active",
        "confidence": confidence,
        "discovered": True,
        "sources": [{"id": ev, "type": "cross_reference"} for ev in evidence],
        "from_entity": from_entity,
        "to_entity": to_entity,
        "direction": "undirected",
        "valid_from": "",
        "valid_until": None,
        "temporal_note": "",
        "domain": [],
        "tags": ["auto-discovered"],
        "edges": [],
        "created": today,
        "last_updated": today,
    }
    _write_file(path, meta, "")
    return path


def _attr_scalar_value(attr) -> str | None:
    if isinstance(attr, dict):
        v = attr.get("value")
        if isinstance(v, (str, int, float)):
            return str(v).strip().lower() or None
    elif isinstance(attr, (str, int, float)):
        return str(attr).strip().lower() or None
    return None


def detect_co_occurrence(
    entities: list[dict],
    facts: list[dict],
    existing_keys: set[tuple[str, str, str]],
) -> list[tuple[str, str, list[str]]]:
    """Return list of (entity_a_file, entity_b_file, shared_source_ids)."""
    source_to_entities: dict[str, list[str]] = defaultdict(list)
    ent_sources: dict[str, set[str]] = {}
    for ent in entities:
        sids = _entity_source_ids(ent, facts)
        ent_sources[ent["_path"].name] = sids
        for sid in sids:
            source_to_entities[sid].append(ent["_path"].name)

    pair_evidence: dict[tuple[str, str], set[str]] = defaultdict(set)
    for sid, ent_files in source_to_entities.items():
        if len(ent_files) < 2:
            continue
        uniq = sorted(set(ent_files))
        for i in range(len(uniq)):
            for j in range(i + 1, len(uniq)):
                pair_evidence[(uniq[i], uniq[j])].add(sid)

    results = []
    for (a, b), sids in pair_evidence.items():
        if len(sids) < CO_OCCURRENCE_MIN_SHARED_SOURCES:
            continue
        if _relation_key(a, b, "co_occurred_in") in existing_keys:
            continue
        results.append((a, b, sorted(sids)))
    return results


def detect_shared_attribute(
    entities: list[dict],
    existing_keys: set[tuple[str, str, str]],
) -> list[tuple[str, str, str, str, str]]:
    """Return list of (entity_a, entity_b, relation_type, attr_key, shared_value)."""
    by_attr_value: dict[tuple[str, str], list[str]] = defaultdict(list)
    for ent in entities:
        attrs = ent.get("attributes") or {}
        for key, val in attrs.items():
            if key not in SHARED_ATTR_TO_RELATION:
                continue
            scalar = _attr_scalar_value(val)
            if not scalar:
                continue
            by_attr_value[(key, scalar)].append(ent["_path"].name)

    results = []
    for (key, value), names in by_attr_value.items():
        if len(names) < 2:
            continue
        rel_type, _ = SHARED_ATTR_TO_RELATION[key]
        uniq = sorted(set(names))
        for i in range(len(uniq)):
            for j in range(i + 1, len(uniq)):
                a, b = uniq[i], uniq[j]
                if _relation_key(a, b, rel_type) in existing_keys:
                    continue
                results.append((a, b, rel_type, key, value))
    return results


def detect_contradictions(facts: list[dict]) -> list[tuple[dict, dict]]:
    """Find pairs of facts that share entity_refs but have near-opposite descriptions.

    Heuristic: same entity_refs overlap, fact_type='attribute' or 'event', and description
    differs but contains shared noun-like tokens. We keep it conservative — only flag when
    two facts describe the same entity with different scalar values (e.g. birth years).
    """
    results = []
    grouped: dict[frozenset, list[dict]] = defaultdict(list)
    for f in facts:
        refs = frozenset(f.get("entity_refs") or [])
        if not refs:
            continue
        grouped[refs].append(f)

    for refs, group in grouped.items():
        if len(group) < 2:
            continue
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                a, b = group[i], group[j]
                if a.get("fact_type") != b.get("fact_type"):
                    continue
                sim = _similarity(a.get("description", ""), b.get("description", ""))
                if 0.4 <= sim < SIMILAR_FACT_THRESHOLD:
                    results.append((a, b))
    return results


def _write_contradiction_edge(lessons_dir: Path, fact_a: dict, fact_b: dict) -> None:
    for src, other in ((fact_a, fact_b), (fact_b, fact_a)):
        edges = list(src.get("edges") or [])
        edge = {"type": "contradicts", "target": other["_path"].name}
        if edge not in edges:
            edges.append(edge)
        src["edges"] = edges
        src["last_updated"] = date.today().isoformat()
        _write_file(src["_path"], src, src.get("_body", ""))


def _load_knowledge_files(lessons_dir: Path) -> list[dict]:
    """Load case/pattern/principle frontmatter+body for cross-contour scanning."""
    items: list[dict] = []
    for prefix in CROSS_CONTOUR_KNOWLEDGE_PREFIXES:
        for p in lessons_dir.glob(f"{prefix}*.md"):
            fm = _parse_frontmatter(p)
            if fm:
                items.append(fm)
    return items


def detect_cross_contour_mentions(
    knowledge_files: list[dict],
    entities: list[dict],
) -> list[tuple[str, str, str]]:
    """H10 measurement: find entity name mentions inside knowledge bodies.

    Returns list of (knowledge_file_name, entity_file_name, matched_token).
    Match is case-insensitive whole-word against entity `name` and `aliases`.
    Read-only: does NOT mutate knowledge files. Used for counter only.
    """
    name_index: list[tuple[str, str]] = []
    for ent in entities:
        ent_file = ent["_path"].name
        names = [ent.get("name") or ""]
        names.extend(ent.get("aliases") or [])
        for n in names:
            n = (n or "").strip()
            if len(n) >= 3:
                name_index.append((n, ent_file))

    found: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    for kf in knowledge_files:
        body = kf.get("_body") or ""
        if not body:
            continue
        for token, ent_file in name_index:
            pattern = r"(?<![\w])" + re.escape(token) + r"(?![\w])"
            if re.search(pattern, body, flags=re.IGNORECASE):
                key = (kf["_path"].name, ent_file)
                if key in seen:
                    continue
                seen.add(key)
                found.append((kf["_path"].name, ent_file, token))
    return found


def _append_cross_contour_log(events: list[tuple[str, str, str]]) -> None:
    """Append discoveries to JSONL log. Best-effort; failures are silent."""
    if not events:
        return
    try:
        CROSS_CONTOUR_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        ts = datetime.now(timezone.utc).isoformat(timespec="seconds")
        with CROSS_CONTOUR_LOG_PATH.open("a", encoding="utf-8") as f:
            for kf_name, ent_name, token in events:
                f.write(json.dumps({
                    "ts": ts,
                    "knowledge_file": kf_name,
                    "entity_file": ent_name,
                    "matched": token,
                }, ensure_ascii=False) + "\n")
    except OSError:
        pass


def discover(lessons_dir: Path) -> dict:
    """Run all detectors on lessons_dir. Returns DiscoverySummary.as_dict()."""
    if not lessons_dir.exists():
        return DiscoverySummary().as_dict()

    entities = _load_by_type(lessons_dir, "entity")
    facts = _load_by_type(lessons_dir, "fact")
    relations = _load_by_type(lessons_dir, "relation")
    existing_keys = _build_existing_relation_keys(relations)

    summary = DiscoverySummary()

    knowledge_files = _load_knowledge_files(lessons_dir)
    cross_contour_events = detect_cross_contour_mentions(knowledge_files, entities)
    for kf_name, ent_name, _token in cross_contour_events:
        summary.cross_contour.append(f"{kf_name} -> {ent_name}")
    _append_cross_contour_log(cross_contour_events)

    for idx, (a, b, sids) in enumerate(detect_co_occurrence(entities, facts, existing_keys)):
        path = _write_discovered_relation(
            lessons_dir,
            from_entity=a,
            to_entity=b,
            relation_type="co_occurred_in",
            confidence=CO_OCCURRENCE_CONFIDENCE,
            description=f"Обе сущности упоминаются в {len(sids)} общих источниках.",
            evidence=sids,
            idx=idx,
        )
        summary.co_occurrence.append(path.name)
        existing_keys.add(_relation_key(a, b, "co_occurred_in"))

    for idx, (a, b, rel_type, attr_key, value) in enumerate(
        detect_shared_attribute(entities, existing_keys)
    ):
        path = _write_discovered_relation(
            lessons_dir,
            from_entity=a,
            to_entity=b,
            relation_type=rel_type,
            confidence=SHARED_ATTR_CONFIDENCE,
            description=f"Общий атрибут {attr_key}={value!r}.",
            evidence=[f"shared-attr:{attr_key}={value}"],
            idx=idx,
        )
        summary.shared_attr.append(path.name)
        existing_keys.add(_relation_key(a, b, rel_type))

    for fact_a, fact_b in detect_contradictions(facts):
        _write_contradiction_edge(lessons_dir, fact_a, fact_b)
        summary.contradictions.append(
            f"{fact_a['_path'].name} <-> {fact_b['_path'].name}"
        )

    return summary.as_dict()
