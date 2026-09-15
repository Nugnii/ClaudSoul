"""Integrate stage — dedup entities/facts/relations + confidence recalc.

See docs/ingestion-pipeline.md §5 and knowledge/META.md for the confidence formula.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date
from difflib import SequenceMatcher
from pathlib import Path

import yaml

from frontmatter import read_frontmatter

ENTITY_REF_SIMILARITY_THRESHOLD = 0.75


SOURCE_WEIGHTS = {
    "self_report": 1,
    "document": 2,
    "third_party": 2,
    "behavioral": 3,
    "cross_reference": 4,
}

SIMILAR_ENTITY_THRESHOLD = 0.85
SIMILAR_FACT_THRESHOLD = 0.9


def recalc_confidence(source_types: list[str]) -> int:
    """confidence = min(5, round(mean(weights) + bonus)); bonus=1 if 2+ distinct source types."""
    if not source_types:
        return 1
    weights = [SOURCE_WEIGHTS.get(t, 1) for t in source_types]
    mean = sum(weights) / len(weights)
    bonus = 1 if len(set(source_types)) >= 2 else 0
    return min(5, round(mean + bonus))


def _slugify(name: str) -> str:
    s = name.lower().strip()
    s = re.sub(r"[^\w\s-]", "", s, flags=re.UNICODE)
    s = re.sub(r"[\s_]+", "-", s).strip("-")
    return s or "unnamed"


def _similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()


def _parse_frontmatter(path: Path) -> dict | None:
    # Через общий модуль frontmatter. Канон: битый YAML не теряет файл (meta={}),
    # раньше эта копия возвращала None — теперь устойчивее.
    fm = read_frontmatter(path)
    if fm is None:
        return None
    meta, body = fm
    meta["_body"] = body
    meta["_path"] = path
    return meta


def _write_file(path: Path, meta: dict, body: str) -> None:
    clean = {k: v for k, v in meta.items() if not k.startswith("_")}
    content = "---\n" + yaml.safe_dump(clean, allow_unicode=True, sort_keys=False) + "---\n\n" + body.strip() + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


@dataclass
class IntegrateSummary:
    entities_created: list[str] = field(default_factory=list)
    entities_merged: list[str] = field(default_factory=list)
    entities_candidates: list[str] = field(default_factory=list)
    facts_created: list[str] = field(default_factory=list)
    facts_merged: list[str] = field(default_factory=list)
    relations_created: list[str] = field(default_factory=list)
    relations_merged: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "entities_created": self.entities_created,
            "entities_merged": self.entities_merged,
            "entities_candidates": self.entities_candidates,
            "facts_created": self.facts_created,
            "facts_merged": self.facts_merged,
            "relations_created": self.relations_created,
            "relations_merged": self.relations_merged,
            "warnings": self.warnings,
        }


def _load_by_type(lessons_dir: Path, prefix: str) -> list[dict]:
    return [m for p in lessons_dir.glob(f"{prefix}-*.md") if (m := _parse_frontmatter(p))]


def _resolve_entity_ref(ref: str, lessons_dir: Path, existing_entities: list[dict] | None = None) -> tuple[str, bool]:
    """Resolve entity_refs like 'entity-foo.md' to a canonical filename that exists.

    Returns (resolved_name, resolved_flag). If no match is found — returns (ref, False)
    and the caller should log a warning. Strategy (in order):
      1. Exact file match in lessons_dir → use as-is
      2. Slugified filename match → entity-<slugify(raw)>.md exists
      3. Alias match — raw (or its slug) equals any alias (or its slug) of a known entity.
         Deterministic cross-script bridge: extractor may specify aliases=[Polska, Польша]
         and either spelling resolves to the canonical entity file.
      4. SequenceMatcher similarity ≥ ENTITY_REF_SIMILARITY_THRESHOLD over slug and name
    """
    if not ref:
        return ref, False
    target = lessons_dir / ref
    if target.exists():
        return ref, True

    raw = ref[len("entity-"):] if ref.startswith("entity-") else ref
    raw = raw[:-3] if raw.endswith(".md") else raw
    raw_slug = _slugify(raw)
    if (lessons_dir / f"entity-{raw_slug}.md").exists():
        return f"entity-{raw_slug}.md", True

    candidates = existing_entities if existing_entities is not None else _load_by_type(lessons_dir, "entity")

    for ent in candidates:
        aliases = ent.get("aliases") or []
        for alias in aliases:
            if not alias:
                continue
            if alias == raw or _slugify(alias) == raw_slug:
                return ent["_path"].name, True

    best_score = 0.0
    best_name = ""
    for ent in candidates:
        ent_name = ent["_path"].name
        ent_slug = ent_name[len("entity-"):-3] if ent_name.startswith("entity-") and ent_name.endswith(".md") else ent_name
        s1 = _similarity(raw_slug, ent_slug)
        s2 = _similarity(raw, ent.get("name", "") or "")
        score = max(s1, s2)
        if score > best_score:
            best_score = score
            best_name = ent_name

    if best_score >= ENTITY_REF_SIMILARITY_THRESHOLD:
        return best_name, True
    return ref, False


def _find_entity_match(new_ent: dict, existing: list[dict]) -> tuple[dict | None, str]:
    new_name = new_ent["name"]
    new_aliases = set(new_ent.get("aliases", []))
    new_names = {new_name} | new_aliases
    new_domain = set(new_ent.get("domain", []))
    new_type = new_ent["entity_type"]

    for ex in existing:
        if ex.get("entity_type") != new_type:
            continue
        ex_names = {ex.get("name", "")} | set(ex.get("aliases", []))
        if new_names & ex_names:
            if not new_domain or not ex.get("domain") or (new_domain & set(ex.get("domain", []))):
                return ex, "exact"

    for ex in existing:
        if ex.get("entity_type") != new_type:
            continue
        if _similarity(new_name, ex.get("name", "")) >= SIMILAR_ENTITY_THRESHOLD:
            if new_domain & set(ex.get("domain", [])):
                return ex, "similar"

    return None, "none"


def _merge_entity_attributes(existing_attrs: dict, new_attrs: dict) -> dict:
    merged: dict = dict(existing_attrs or {})
    for key, new_val in new_attrs.items():
        if key not in merged:
            merged[key] = _recalc_attr_confidence(new_val)
            continue
        existing_val = merged[key]
        if isinstance(existing_val, list) or isinstance(new_val, list):
            existing_list = existing_val if isinstance(existing_val, list) else [existing_val]
            new_list = new_val if isinstance(new_val, list) else [new_val]
            merged[key] = [_recalc_attr_confidence(v) for v in existing_list + new_list]
        else:
            merged[key] = _merge_scalar_attrs(existing_val, new_val)
    return merged


def _values_match(a, b) -> bool:
    if a == b:
        return True
    if isinstance(a, str) and isinstance(b, str):
        return a.strip().lower() == b.strip().lower()
    return False


def _first_source(attr: dict) -> str | None:
    sources = attr.get("sources") or []
    return sources[0] if sources else None


def _attr_confidence(attr: dict) -> int:
    conf = attr.get("confidence")
    if isinstance(conf, int):
        return conf
    st = attr.get("source_type")
    return recalc_confidence([st] if st else [])


def _merge_scalar_attrs(existing: dict, new: dict) -> dict:
    """Merge two scalar attribute_value dicts.

    Contract:
    - Values match → union sources, recalc confidence, preserve either side's `contradiction`.
    - Values differ → authoritative side wins `value`; loser's value goes into `contradiction.stated_value`.
      Authority = (source_type weight, explicit confidence). Explicit `contradiction` field on the
      incoming payload is respected as-is (Claude pre-classified the conflict).
    """
    source_types = [t for t in [existing.get("source_type"), new.get("source_type")] if t]
    sources = list(dict.fromkeys((existing.get("sources") or []) + (new.get("sources") or [])))

    if _values_match(existing.get("value"), new.get("value")):
        merged = {
            **existing,
            "value": new.get("value", existing.get("value")),
            "sources": sources,
            "confidence": recalc_confidence(source_types),
        }
        contradiction = new.get("contradiction") or existing.get("contradiction")
        if contradiction:
            merged["contradiction"] = contradiction
        return merged

    if "contradiction" in new:
        return {
            **new,
            "sources": sources,
            "confidence": recalc_confidence(source_types),
        }

    existing_weight = SOURCE_WEIGHTS.get(existing.get("source_type"), 1)
    new_weight = SOURCE_WEIGHTS.get(new.get("source_type"), 1)
    existing_conf = _attr_confidence(existing)
    new_conf = _attr_confidence(new)

    new_wins = (new_weight, new_conf) >= (existing_weight, existing_conf)
    winner, loser = (new, existing) if new_wins else (existing, new)

    return {
        **winner,
        "sources": sources,
        "confidence": recalc_confidence(source_types),
        "contradiction": {
            "stated_value": loser.get("value"),
            "stated_source": _first_source(loser),
            "stated_confidence": _attr_confidence(loser),
            "gap_type": _classify_gap(winner, loser),
        },
    }


def _classify_gap(winner: dict, loser: dict) -> str:
    """Classify contradiction provenance for H9 measurement.

    - stated_vs_inferred: self_report lost to behavioral (the canonical H9 case)
    - source_drift: same source_type with diverging values
    - cross_source: different source_types, neither self_report/behavioral pair
    """
    w_st = winner.get("source_type")
    l_st = loser.get("source_type")
    if w_st == "behavioral" and l_st == "self_report":
        return "stated_vs_inferred"
    if w_st == l_st and w_st is not None:
        return "source_drift"
    return "cross_source"


def _recalc_attr_confidence(attr: dict) -> dict:
    if not isinstance(attr, dict):
        return attr
    st = attr.get("source_type")
    if st and "confidence" not in attr:
        attr["confidence"] = recalc_confidence([st])
    return attr


def _entity_body(ent: dict) -> str:
    return ent.get("description", "")


def _write_new_entity(lessons_dir: Path, ent: dict, status: str = "active", note: str = "") -> Path:
    slug = _slugify(ent["name"])
    path = lessons_dir / f"entity-{slug}.md"
    today = date.today().isoformat()
    attrs = {k: _recalc_attr_confidence(v) if isinstance(v, dict) else v for k, v in ent.get("attributes", {}).items()}
    meta = {
        "name": ent["name"],
        "description": ent.get("description", ""),
        "type": "entity",
        "entity_type": ent["entity_type"],
        "status": status,
        "confidence": 1,
        "aliases": ent.get("aliases", []),
        "attributes": attrs,
        "trajectory": ent.get("trajectory", []),
        "created": today,
        "last_updated": today,
        "first_seen": ent.get("first_seen", ""),
        "relations": [],
        "edges": ent.get("edges", []),
        "domain": ent.get("domain", []),
        "tags": ent.get("tags", []),
    }
    body = _entity_body(ent) + (f"\n\n{note}" if note else "")
    _write_file(path, meta, body)
    return path


def _merge_into_entity(ent_path: Path, existing: dict, new_ent: dict) -> None:
    merged_attrs = _merge_entity_attributes(existing.get("attributes") or {}, new_ent.get("attributes", {}))
    existing_domain = list(dict.fromkeys((existing.get("domain") or []) + new_ent.get("domain", [])))
    existing_aliases = list(dict.fromkeys((existing.get("aliases") or []) + new_ent.get("aliases", [])))
    existing.update(
        {
            "attributes": merged_attrs,
            "domain": existing_domain,
            "aliases": existing_aliases,
            "last_updated": date.today().isoformat(),
        }
    )
    _write_file(ent_path, existing, existing.get("_body", ""))


def _write_new_fact(lessons_dir: Path, fact: dict, idx: int) -> Path:
    name = fact.get("name") or (fact["description"][:50].strip())
    slug = _slugify(name) or f"fact-{idx:04d}"
    path = lessons_dir / f"fact-{slug}.md"
    if path.exists():
        path = lessons_dir / f"fact-{slug}-{idx:04d}.md"
    today = date.today().isoformat()
    source_types = [s.get("type") for s in fact.get("sources", []) if s.get("type")]
    meta = {
        "name": name,
        "description": fact["description"],
        "type": "fact",
        "fact_type": fact["fact_type"],
        "status": "active",
        "confidence": recalc_confidence(source_types),
        "sources": fact["sources"],
        "valid_from": fact.get("valid_from", ""),
        "valid_until": fact.get("valid_until"),
        "temporal_note": fact.get("temporal_note", ""),
        "entity_refs": fact.get("entity_refs", []),
        "domain": fact.get("domain", []),
        "tags": fact.get("tags", []),
        "edges": fact.get("edges", []),
        "created": today,
        "last_updated": today,
    }
    body = fact.get("body", "")
    _write_file(path, meta, body)
    return path


def _find_fact_match(new_fact: dict, existing: list[dict]) -> dict | None:
    new_refs = set(new_fact.get("entity_refs", []))
    for ex in existing:
        ex_refs = set(ex.get("entity_refs", []))
        if new_refs and ex_refs and not (new_refs & ex_refs):
            continue
        if _similarity(new_fact["description"], ex.get("description", "")) >= SIMILAR_FACT_THRESHOLD:
            return ex
    return None


def _merge_into_fact(ex: dict, new_fact: dict) -> None:
    existing_sources = ex.get("sources") or []
    seen = {(s.get("id"), s.get("type")) for s in existing_sources}
    for s in new_fact.get("sources", []):
        key = (s.get("id"), s.get("type"))
        if key not in seen:
            existing_sources.append(s)
            seen.add(key)
    source_types = [s.get("type") for s in existing_sources if s.get("type")]
    ex["sources"] = existing_sources
    ex["confidence"] = recalc_confidence(source_types)
    ex["last_updated"] = date.today().isoformat()
    _write_file(ex["_path"], ex, ex.get("_body", ""))


def _find_relation_match(new_rel: dict, existing: list[dict]) -> dict | None:
    for ex in existing:
        if (
            ex.get("from_entity") == new_rel["from_entity"]
            and ex.get("to_entity") == new_rel["to_entity"]
            and ex.get("relation_type") == new_rel["relation_type"]
        ):
            return ex
    return None


def _strip_entity_md(ref: str) -> str:
    s = ref[len("entity-"):] if ref.startswith("entity-") else ref
    s = s[:-3] if s.endswith(".md") else s
    return s


def _write_new_relation(lessons_dir: Path, rel: dict, idx: int) -> Path:
    slug_base = f"{_slugify(_strip_entity_md(rel['from_entity']))}-{rel['relation_type']}-{_slugify(_strip_entity_md(rel['to_entity']))}"
    path = lessons_dir / f"relation-{slug_base}.md"
    if path.exists():
        path = lessons_dir / f"relation-{slug_base}-{idx:04d}.md"
    today = date.today().isoformat()
    source_types = [s.get("type") for s in rel.get("sources", []) if s.get("type")]
    meta = {
        "name": f"{rel['from_entity']} → {rel['relation_type']} → {rel['to_entity']}",
        "description": rel.get("description", ""),
        "type": "relation",
        "relation_type": rel["relation_type"],
        "status": "active",
        "confidence": recalc_confidence(source_types),
        "sources": rel["sources"],
        "from_entity": rel["from_entity"],
        "to_entity": rel["to_entity"],
        "direction": rel.get("direction", "directed"),
        "valid_from": rel.get("valid_from", ""),
        "valid_until": rel.get("valid_until"),
        "temporal_note": rel.get("temporal_note", ""),
        "domain": rel.get("domain", []),
        "tags": rel.get("tags", []),
        "edges": rel.get("edges", []),
        "created": today,
        "last_updated": today,
    }
    _write_file(path, meta, "")
    return path


def _merge_into_relation(ex: dict, new_rel: dict) -> None:
    existing_sources = ex.get("sources") or []
    seen = {(s.get("id"), s.get("type")) for s in existing_sources}
    for s in new_rel.get("sources", []):
        key = (s.get("id"), s.get("type"))
        if key not in seen:
            existing_sources.append(s)
            seen.add(key)
    source_types = [s.get("type") for s in existing_sources if s.get("type")]
    ex["sources"] = existing_sources
    ex["confidence"] = recalc_confidence(source_types)
    ex["last_updated"] = date.today().isoformat()
    _write_file(ex["_path"], ex, ex.get("_body", ""))


def integrate(extract_output: dict, lessons_dir: Path) -> dict:
    """Merge extract output into lessons_dir. Returns IntegrateSummary.as_dict()."""
    lessons_dir.mkdir(parents=True, exist_ok=True)
    summary = IntegrateSummary()

    existing_entities = _load_by_type(lessons_dir, "entity")
    for ent in extract_output.get("entities", []):
        match, kind = _find_entity_match(ent, existing_entities)
        if kind == "exact" and match is not None:
            _merge_into_entity(match["_path"], match, ent)
            summary.entities_merged.append(match["_path"].name)
        elif kind == "similar" and match is not None:
            path = _write_new_entity(
                lessons_dir,
                ent,
                status="merged_candidate",
                note=f"Similar to {match['_path'].name} (similarity ≥ {SIMILAR_ENTITY_THRESHOLD}).",
            )
            summary.entities_candidates.append(path.name)
        else:
            path = _write_new_entity(lessons_dir, ent)
            summary.entities_created.append(path.name)
        existing_entities = _load_by_type(lessons_dir, "entity")

    entity_index = _load_by_type(lessons_dir, "entity")

    existing_facts = _load_by_type(lessons_dir, "fact")
    for idx, fact in enumerate(extract_output.get("facts", [])):
        resolved_refs = []
        for ref in fact.get("entity_refs", []) or []:
            resolved, ok = _resolve_entity_ref(ref, lessons_dir, entity_index)
            resolved_refs.append(resolved)
            if not ok:
                summary.warnings.append(f"fact #{idx}: unresolved entity_ref {ref!r}")
        fact = {**fact, "entity_refs": resolved_refs}

        match = _find_fact_match(fact, existing_facts)
        if match is not None:
            _merge_into_fact(match, fact)
            summary.facts_merged.append(match["_path"].name)
        else:
            path = _write_new_fact(lessons_dir, fact, idx)
            summary.facts_created.append(path.name)
        existing_facts = _load_by_type(lessons_dir, "fact")

    existing_relations = _load_by_type(lessons_dir, "relation")
    for idx, rel in enumerate(extract_output.get("relations", [])):
        fe_resolved, fe_ok = _resolve_entity_ref(rel.get("from_entity", ""), lessons_dir, entity_index)
        te_resolved, te_ok = _resolve_entity_ref(rel.get("to_entity", ""), lessons_dir, entity_index)
        if not fe_ok:
            summary.warnings.append(f"relation #{idx}: unresolved from_entity {rel.get('from_entity')!r}")
        if not te_ok:
            summary.warnings.append(f"relation #{idx}: unresolved to_entity {rel.get('to_entity')!r}")
        rel = {**rel, "from_entity": fe_resolved, "to_entity": te_resolved}

        match = _find_relation_match(rel, existing_relations)
        if match is not None:
            _merge_into_relation(match, rel)
            summary.relations_merged.append(match["_path"].name)
        else:
            path = _write_new_relation(lessons_dir, rel, idx)
            summary.relations_created.append(path.name)
        existing_relations = _load_by_type(lessons_dir, "relation")

    return summary.as_dict()
