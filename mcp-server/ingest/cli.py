"""CLI entrypoint for ingest pipeline.

Commands:
    parse <path> [--source-id ID] [--title T]
        Parse a file, write ~/.claude/sources/<source_id>/ layout, print JSON summary.

    integrate <extract_json_path> [--lessons-dir DIR]
        Validate extract output against schema and merge into lessons dir.

    show-schema {entity|fact|relation|extract_output}
        Print JSON schema to stdout (for skill authors).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from .discovery import discover as discover_relations
from .integrate import integrate
from .parse import parse as parse_file
from .schemas import load as load_schema, validate_extract_output
from .source_store import SourceIndexEntry, SourceStore


def _derive_source_id(path: Path, title: str | None) -> str:
    base = title or path.stem
    slug = re.sub(r"[^\w\s-]", "", base.lower(), flags=re.UNICODE)
    slug = re.sub(r"[\s_]+", "-", slug).strip("-") or "source"
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return f"{slug}-{today}"


def cmd_parse(args: argparse.Namespace) -> int:
    path = Path(args.path).expanduser().resolve()
    if not path.exists():
        print(f"error: file not found: {path}", file=sys.stderr)
        return 2

    source_id = args.source_id or _derive_source_id(path, args.title)
    store = SourceStore()
    res = parse_file(path, source_id=source_id)

    store.write_markdown(source_id, res.markdown)
    blocks_as_dicts = [
        {
            "block_id": b.block_id,
            "source_id": b.source_id,
            "block_type": b.block_type,
            "text": b.text,
            "provenance": b.provenance,
        }
        for b in res.blocks
    ]
    parsed_path = store.write_parsed(source_id, blocks_as_dicts)

    meta = {
        "id": source_id,
        "type": "document",
        "format": path.suffix.lstrip(".").lower(),
        "original_path": str(path),
        "title": args.title or path.stem,
        "ingested_at": datetime.now(timezone.utc).isoformat(),
        "parser": res.parser,
        "parser_version": res.parser_version,
        "parse_warnings": res.warnings,
    }
    store.write_meta(source_id, meta)

    existing_ids = {row["id"] for row in store.read_index()}
    if source_id not in existing_ids:
        store.append_index(
            SourceIndexEntry(
                id=source_id,
                type="document",
                format=meta["format"],
                original_path=meta["original_path"],
                title=meta["title"],
                ingested_at=meta["ingested_at"],
                stages_completed=["parse"],
                block_count=len(res.blocks),
            )
        )

    print(
        json.dumps(
            {
                "source_id": source_id,
                "source_dir": str(store.source_dir(source_id)),
                "parsed_jsonl": str(parsed_path),
                "block_count": len(res.blocks),
                "parser": res.parser,
                "warnings": res.warnings,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def cmd_integrate(args: argparse.Namespace) -> int:
    payload_path = Path(args.extract_json).expanduser().resolve()
    if not payload_path.exists():
        print(f"error: extract JSON not found: {payload_path}", file=sys.stderr)
        return 2

    payload = json.loads(payload_path.read_text(encoding="utf-8"))
    validate_extract_output(payload)

    lessons_dir = Path(args.lessons_dir).expanduser().resolve()
    summary = integrate(payload, lessons_dir)

    if not args.no_discover:
        summary["discovery"] = discover_relations(lessons_dir)

    store = SourceStore()
    if store.index_path.exists() and any(row["id"] == payload["source_id"] for row in store.read_index()):
        store.update_index_entry(
            payload["source_id"],
            stages_completed=["parse", "extract", "integrate"],
            entity_count=len(summary["entities_created"]) + len(summary["entities_merged"]) + len(summary["entities_candidates"]),
            fact_count=len(summary["facts_created"]) + len(summary["facts_merged"]),
            relation_count=len(summary["relations_created"]) + len(summary["relations_merged"]),
        )

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def cmd_discover(args: argparse.Namespace) -> int:
    lessons_dir = Path(args.lessons_dir).expanduser().resolve()
    if not lessons_dir.exists():
        print(f"error: lessons dir not found: {lessons_dir}", file=sys.stderr)
        return 2
    summary = discover_relations(lessons_dir)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def cmd_show_schema(args: argparse.Namespace) -> int:
    print(json.dumps(load_schema(args.name), ensure_ascii=False, indent=2))
    return 0


def _parse_fm(path: Path) -> dict | None:
    # Через общий модуль frontmatter (см. mcp-server/frontmatter.py).
    from frontmatter import read_frontmatter

    fm = read_frontmatter(path)
    if fm is None:
        return None
    meta, body = fm
    meta["_body"] = body
    meta["_path"] = str(path)
    return meta


def cmd_show_entity(args: argparse.Namespace) -> int:
    lessons_dir = Path(args.lessons_dir).expanduser().resolve()
    if not lessons_dir.exists():
        print(f"error: lessons dir not found: {lessons_dir}", file=sys.stderr)
        return 2

    from .integrate import _slugify  # единый источник слагификации (principle-single-source-of-truth)
    query = args.name
    candidate = lessons_dir / query if query.endswith(".md") else lessons_dir / f"entity-{_slugify(query)}.md"
    if not candidate.exists():
        matches = []
        for p in lessons_dir.glob("entity-*.md"):
            m = _parse_fm(p)
            if not m:
                continue
            names = {m.get("name", "")} | set(m.get("aliases") or [])
            if any(query.lower() == n.lower() for n in names if n):
                matches.append(p)
        if len(matches) == 1:
            candidate = matches[0]
        elif len(matches) > 1:
            print(
                json.dumps(
                    {"error": "ambiguous", "matches": [p.name for p in matches]},
                    ensure_ascii=False,
                    indent=2,
                )
            )
            return 3
        else:
            print(json.dumps({"error": "not_found", "query": query}, ensure_ascii=False, indent=2))
            return 4

    ent = _parse_fm(candidate)
    if not ent:
        print(f"error: failed to parse {candidate}", file=sys.stderr)
        return 5

    facts: list[dict] = []
    for p in lessons_dir.glob("fact-*.md"):
        fm = _parse_fm(p)
        if not fm:
            continue
        if candidate.name in (fm.get("entity_refs") or []):
            facts.append({"file": p.name, "description": fm.get("description", ""), "confidence": fm.get("confidence")})

    relations: list[dict] = []
    for p in lessons_dir.glob("relation-*.md"):
        rm = _parse_fm(p)
        if not rm:
            continue
        if rm.get("from_entity") == candidate.name or rm.get("to_entity") == candidate.name:
            relations.append(
                {
                    "file": p.name,
                    "from": rm.get("from_entity"),
                    "to": rm.get("to_entity"),
                    "type": rm.get("relation_type"),
                    "confidence": rm.get("confidence"),
                }
            )

    out = {
        "file": candidate.name,
        "name": ent.get("name"),
        "entity_type": ent.get("entity_type"),
        "status": ent.get("status"),
        "confidence": ent.get("confidence"),
        "aliases": ent.get("aliases", []),
        "domain": ent.get("domain", []),
        "attributes": ent.get("attributes", {}),
        "edges": ent.get("edges", []),
        "related_facts": facts,
        "related_relations": relations,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def _score_entity(ent: dict, query_tokens: set[str]) -> int:
    if not query_tokens:
        return 0
    score = 0
    name = (ent.get("name") or "").lower()
    aliases = [str(a).lower() for a in (ent.get("aliases") or [])]
    domain = [str(d).lower() for d in (ent.get("domain") or [])]
    tags = [str(t).lower() for t in (ent.get("tags") or [])]

    for token in query_tokens:
        if len(token) < 2:
            continue
        if token == name:
            score += 10
        elif token in name:
            score += 5
        if any(token == a for a in aliases):
            score += 8
        elif any(token in a for a in aliases):
            score += 3
        if token in domain:
            score += 4
        if token in tags:
            score += 2
    return score


def _tokenize(text: str) -> set[str]:
    import re as _re
    return {t for t in _re.split(r"[^\w]+", text.lower(), flags=_re.UNICODE) if t}


def _format_entity_card(ent: dict) -> dict:
    attrs_summary = []
    for key, val in (ent.get("attributes") or {}).items():
        if isinstance(val, dict):
            v = val.get("value")
            if v is not None:
                attrs_summary.append(f"{key}={v}")
        elif isinstance(val, (str, int, float)):
            attrs_summary.append(f"{key}={val}")
        if len(attrs_summary) >= 3:
            break
    return {
        "file": ent["_path"].name,
        "name": ent.get("name"),
        "entity_type": ent.get("entity_type"),
        "aliases": ent.get("aliases", []) or [],
        "domain": ent.get("domain", []) or [],
        "attributes_summary": attrs_summary,
        "confidence": ent.get("confidence"),
    }


def cmd_slug(args: argparse.Namespace) -> int:
    """Emit canonical entity filename for a given name (so Claude in /ingest can build
    correct entity_refs without guessing the slugify algorithm)."""
    from .integrate import _slugify as _integrate_slugify

    slug = _integrate_slugify(args.name)
    print(f"entity-{slug}.md")
    return 0


def cmd_activate(args: argparse.Namespace) -> int:
    """Keyword-scored entity lookup for knowledge-activator hook."""
    from .integrate import _load_by_type

    lessons_dir = Path(args.lessons_dir).expanduser().resolve()
    if not lessons_dir.exists():
        print(json.dumps([], ensure_ascii=False))
        return 0

    tokens = _tokenize(args.query or "")
    if not tokens:
        print(json.dumps([], ensure_ascii=False))
        return 0

    entities = _load_by_type(lessons_dir, "entity")
    scored = []
    for ent in entities:
        score = _score_entity(ent, tokens)
        if score > 0:
            scored.append((score, ent))
    scored.sort(key=lambda x: x[0], reverse=True)

    limit = max(1, args.limit)
    cards = [{**_format_entity_card(e), "score": s} for s, e in scored[:limit]]
    print(json.dumps(cards, ensure_ascii=False))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="ingest")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_parse = sub.add_parser("parse", help="Parse a document into ~/.claude/sources/")
    p_parse.add_argument("path")
    p_parse.add_argument("--source-id")
    p_parse.add_argument("--title")
    p_parse.set_defaults(fn=cmd_parse)

    p_int = sub.add_parser("integrate", help="Integrate extract output into global-lessons/")
    p_int.add_argument("extract_json")
    p_int.add_argument(
        "--lessons-dir",
        default=str(Path.home() / ".claude" / "global-lessons"),
    )
    p_int.add_argument("--no-discover", action="store_true", help="Skip Discovery Engine pass")
    p_int.set_defaults(fn=cmd_integrate)

    p_disc = sub.add_parser("discover", help="Run Discovery Engine on lessons dir (no changes to sources)")
    p_disc.add_argument(
        "--lessons-dir",
        default=str(Path.home() / ".claude" / "global-lessons"),
    )
    p_disc.set_defaults(fn=cmd_discover)

    p_show = sub.add_parser("show-schema", help="Print a JSON schema to stdout")
    p_show.add_argument("name", choices=["entity", "fact", "relation", "extract_output"])
    p_show.set_defaults(fn=cmd_show_schema)

    p_ent = sub.add_parser("show-entity", help="Show entity frontmatter + related facts/relations")
    p_ent.add_argument("name", help="Entity name, slug, or entity-<slug>.md filename")
    p_ent.add_argument(
        "--lessons-dir",
        default=str(Path.home() / ".claude" / "global-lessons"),
    )
    p_ent.set_defaults(fn=cmd_show_entity)

    p_slug = sub.add_parser("slug", help="Print canonical entity-<slug>.md filename for a name (helper for extract step)")
    p_slug.add_argument("name")
    p_slug.set_defaults(fn=cmd_slug)

    p_act = sub.add_parser("activate", help="Score entities against a query for knowledge-activator injection")
    p_act.add_argument("query", help="Context text — file path, command, keywords")
    p_act.add_argument(
        "--lessons-dir",
        default=str(Path.home() / ".claude" / "global-lessons"),
    )
    p_act.add_argument("--limit", type=int, default=3)
    p_act.set_defaults(fn=cmd_activate)

    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
