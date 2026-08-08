"""Knowledge file parser and embedding generator."""

import os
import yaml
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastembed import TextEmbedding

from frontmatter import split_frontmatter

KNOWLEDGE_DIR = Path.home() / ".claude" / "global-lessons"
DOMAIN_DIR = None  # Set dynamically if project path known

# Модель эмбеддингов: многоязычная (50+ языков вкл. русский), 384-мерная —
# drop-in по размерности с прежней bge-small-en на двуязычной (ru/en) базе.
# Симметричная paraphrase-модель: префиксы query:/passage: не нужны.
# Смена значения → авто-реиндекс (server._is_reindex_needed сверяет meta-таблицу).
EMBED_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"

# Lazy-loaded embedding model
_model: Optional[TextEmbedding] = None


def get_model() -> TextEmbedding:
    """Lazy-load the embedding model (downloads ~120MB on first use)."""
    global _model
    if _model is None:
        _model = TextEmbedding(EMBED_MODEL)
    return _model


def embed_text(text: str) -> list[float]:
    """Generate embedding for a single text."""
    model = get_model()
    embeddings = list(model.embed([text]))
    return embeddings[0].tolist()


def embed_texts(texts: list[str]) -> list[list[float]]:
    """Generate embeddings for multiple texts (batched)."""
    model = get_model()
    return [e.tolist() for e in model.embed(texts)]


def parse_knowledge_file(path: Path) -> Optional[dict]:
    """Parse a markdown file with YAML frontmatter.

    Returns dict with 'meta' (parsed YAML) and 'body' (markdown content),
    or None if file can't be parsed.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None

    # Frontmatter — через общий модуль frontmatter; контракт indexer (всегда dict)
    # сохранён: нет frontmatter → пустой meta + весь текст как body.
    fm = split_frontmatter(text)
    if fm is None:
        meta, body = {}, text.strip()
    else:
        meta, body = fm

    return {
        "meta": meta,
        "body": body,
        "file_path": str(path),
        "modified": datetime.fromtimestamp(path.stat().st_mtime).isoformat(),
    }


def build_search_text(parsed: dict) -> str:
    """Build text for embedding from parsed knowledge file.

    Combines name, description, type, domain, tags and body
    for richer semantic representation.
    """
    meta = parsed["meta"]
    parts = []

    if meta.get("name"):
        parts.append(f"Name: {meta['name']}")
    if meta.get("description"):
        parts.append(f"Description: {meta['description']}")
    if meta.get("type"):
        parts.append(f"Type: {meta['type']}")
    if meta.get("domain"):
        domains = meta["domain"] if isinstance(meta["domain"], list) else [meta["domain"]]
        parts.append(f"Domain: {', '.join(str(d) for d in domains)}")
    if meta.get("tags"):
        tags = meta["tags"] if isinstance(meta["tags"], list) else [meta["tags"]]
        parts.append(f"Tags: {', '.join(str(t) for t in tags)}")
    if meta.get("situation"):
        parts.append(f"Situation: {meta['situation']}")
    if meta.get("trigger"):
        parts.append(f"Trigger: {meta['trigger']}")

    # Body — truncate to ~2000 chars for embedding
    body = parsed["body"][:2000]
    parts.append(body)

    return "\n".join(parts)


DOMAINS_DIR = Path(__file__).parent.parent / "domains"


def parse_domain_file(path: Path) -> Optional[dict]:
    """Parse a domain graph node file.

    Returns dict with name, aliases, depth, and typed relations.
    """
    parsed = parse_knowledge_file(path)
    if not parsed:
        return None

    meta = parsed["meta"]
    body = parsed["body"]

    # Relations are in body as "key: [values]" lines, not in YAML frontmatter
    relations = {}
    for rel_type in ("parent", "children", "overlaps", "applies_to", "analogous"):
        # Check body lines
        for line in body.split("\n"):
            stripped = line.strip()
            if stripped.startswith(f"{rel_type}:"):
                val = stripped[len(rel_type) + 1:].strip()
                # Parse "[a, b, c]" format
                if val.startswith("[") and val.endswith("]"):
                    items = [x.strip() for x in val[1:-1].split(",") if x.strip()]
                    relations[rel_type] = items
                elif val:
                    relations[rel_type] = [val]
                else:
                    relations[rel_type] = []
                break
        if rel_type not in relations:
            relations[rel_type] = []

    return {
        "name": meta.get("name", path.stem),
        "aliases": meta.get("aliases", []),
        "depth": meta.get("depth", 0),
        "relations": relations,
    }


def scan_domains(domains_dir: Optional[Path] = None) -> list[dict]:
    """Scan domains directory and parse all domain files."""
    dir_path = domains_dir or DOMAINS_DIR
    if not dir_path.exists():
        return []

    results = []
    for md_file in sorted(dir_path.glob("*.md")):
        if md_file.name.startswith("_"):
            continue
        parsed = parse_domain_file(md_file)
        if parsed:
            results.append(parsed)
    return results


def scan_knowledge_dir(knowledge_dir: Optional[Path] = None) -> list[dict]:
    """Scan knowledge directory and parse all .md files.

    Returns list of parsed files ready for indexing.
    """
    dir_path = knowledge_dir or KNOWLEDGE_DIR
    if not dir_path.exists():
        return []

    results = []
    for md_file in sorted(dir_path.glob("*.md")):
        if md_file.name.startswith("_") or md_file.name == "META.md":
            continue
        parsed = parse_knowledge_file(md_file)
        if parsed:
            results.append(parsed)

    return results


def index_all(knowledge_dir: Optional[Path] = None) -> list[dict]:
    """Parse all files and generate embeddings.

    Returns list of dicts ready for storage.upsert_knowledge().
    """
    files = scan_knowledge_dir(knowledge_dir)
    if not files:
        return []

    # Build search texts and embed in batch
    search_texts = [build_search_text(f) for f in files]
    embeddings = embed_texts(search_texts)

    entries = []
    for parsed, embedding in zip(files, embeddings):
        meta = parsed["meta"]
        domain = meta.get("domain", [])
        if isinstance(domain, list):
            domain = ", ".join(str(d) for d in domain)
        tags = meta.get("tags", [])
        if isinstance(tags, list):
            tags = ", ".join(str(t) for t in tags)

        # Parse edges and relations
        raw_edges = meta.get("edges", [])
        edges_list = []
        if isinstance(raw_edges, list):
            for edge in raw_edges:
                if isinstance(edge, dict):
                    for rel_type, target in edge.items():
                        edges_list.append({"type": rel_type, "target": target})
                elif isinstance(edge, str) and ":" in edge:
                    rel_type, target = edge.split(":", 1)
                    edges_list.append({"type": rel_type.strip(), "target": target.strip()})

        related = meta.get("related", [])
        if isinstance(related, list):
            for r in related:
                if isinstance(r, str) and r:
                    edges_list.append({"type": "related", "target": r})

        source_cases = meta.get("source_cases", [])
        if isinstance(source_cases, list):
            for sc in source_cases:
                if isinstance(sc, str) and sc:
                    edges_list.append({"type": "source_case", "target": sc})

        # Entity Knowledge (v1.1+): relation-nodes connect two entities via
        # from_entity/to_entity, fact-nodes reference entities via entity_refs.
        # Without this, ingested nodes appear disconnected in the graph.
        rel_type_name = meta.get("relation_type") or "relates"
        from_entity = meta.get("from_entity")
        to_entity = meta.get("to_entity")
        if isinstance(from_entity, str) and from_entity:
            edges_list.append({"type": f"from:{rel_type_name}", "target": from_entity})
        if isinstance(to_entity, str) and to_entity:
            edges_list.append({"type": f"to:{rel_type_name}", "target": to_entity})

        entity_refs = meta.get("entity_refs", [])
        if isinstance(entity_refs, list):
            for er in entity_refs:
                if isinstance(er, str) and er:
                    edges_list.append({"type": "refs", "target": er})

        entries.append({
            "file_path": parsed["file_path"],
            "name": meta.get("name", Path(parsed["file_path"]).stem),
            "type_": meta.get("type", "unknown"),
            "confidence": meta.get("confidence"),
            "impact": meta.get("impact"),
            "status": meta.get("status", "active"),
            "domain": domain,
            "tags": tags,
            "content": parsed["body"],
            "updated_at": parsed["modified"],
            "embedding": embedding,
            "confirmed_count": meta.get("confirmed_count", 0),
            "contradicted_count": meta.get("contradicted_count", 0),
            "edges_json": edges_list,
        })

    return entries
