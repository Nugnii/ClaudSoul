"""ClaudSoul MCP Server — semantic search across the knowledge base."""

import sys
import logging
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from indexer import index_all, embed_text, scan_knowledge_dir, scan_domains, KNOWLEDGE_DIR, EMBED_MODEL
from storage import get_connection, init_db, upsert_knowledge, search, get_stats, remove_stale, graph_data, dashboard_data
from brain import export_brain, import_brain

# Logging to stderr only (stdout is reserved for MCP JSON-RPC)
logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(message)s")
log = logging.getLogger("claudsoul-mcp")

mcp = FastMCP("claudsoul")


@mcp.tool()
async def search_knowledge(
    query: str,
    limit: int = 5,
    type_filter: str = "",
    min_confidence: int = 0,
) -> str:
    """Semantic search across ClaudSoul knowledge base.

    Finds knowledge entries (cases, patterns, principles) most relevant
    to the query using vector similarity.

    Args:
        query: Search query in natural language (Russian or English)
        limit: Maximum number of results (default 5, max 20)
        type_filter: Filter by type: "case", "pattern", "principle", or "" for all
        min_confidence: Minimum confidence level (0-5, default 0)
    """
    limit = min(limit, 20)
    db = get_connection()
    init_db(db)

    stats = get_stats(db)
    if stats["total"] == 0:
        # Auto-index on first search
        log.info("Knowledge base empty, auto-indexing...")
        count = await _do_reindex(db)
        if count == 0:
            return "Knowledge base is empty. No files found in ~/.claude/global-lessons/"
    elif _is_reindex_needed(db):
        log.info("Knowledge files changed on disk, auto-reindexing...")
        await _do_reindex(db)

    query_embedding = embed_text(query)
    results = search(
        db,
        query_embedding,
        limit=limit,
        type_filter=type_filter or None,
        min_confidence=min_confidence,
    )
    db.close()

    if not results:
        return f"No results found for: {query}"

    lines = [f"## Search results for: {query}\n"]
    for i, r in enumerate(results, 1):
        lines.append(f"### {i}. {r['name']} ({r['type']}, confidence: {r['confidence']})")
        lines.append(f"**File:** {Path(r['file_path']).name}")
        if r["domain"]:
            lines.append(f"**Domain:** {r['domain']}")
        if r["tags"]:
            lines.append(f"**Tags:** {r['tags']}")
        lines.append(f"**Relevance:** {1 - r['distance']:.2%}")
        lines.append(f"\n{r['content']}\n")
        lines.append("---\n")

    return "\n".join(lines)


@mcp.tool()
async def reindex_knowledge() -> str:
    """Reindex all knowledge files from ~/.claude/global-lessons/.

    Parses markdown files with YAML frontmatter, generates embeddings,
    and stores them in SQLite for semantic search. Run this after adding
    new knowledge or if search results seem stale.
    """
    db = get_connection()
    init_db(db)
    count = await _do_reindex(db)
    db.close()
    return f"Indexed {count} knowledge files from {KNOWLEDGE_DIR}"


@mcp.tool()
async def knowledge_stats() -> str:
    """Show statistics about the indexed knowledge base.

    Returns counts by type, average confidence, and index health.
    """
    db = get_connection()
    init_db(db)
    stats = get_stats(db)
    db.close()

    lines = ["## Knowledge Base Statistics\n"]
    lines.append(f"**Total indexed:** {stats['total']}")
    lines.append(f"**Average confidence:** {stats['avg_confidence']}")
    lines.append("\n**By type:**")
    for type_, count in sorted(stats["by_type"].items()):
        lines.append(f"- {type_}: {count}")

    # Check source directory
    files = scan_knowledge_dir()
    lines.append(f"\n**Source files in {KNOWLEDGE_DIR}:** {len(files)}")
    if len(files) != stats["total"]:
        lines.append(f"⚠️ Index out of sync: {stats['total']} indexed vs {len(files)} on disk")
        lines.append("Run `reindex_knowledge` to sync.")

    return "\n".join(lines)


@mcp.tool()
async def get_knowledge(file_name: str) -> str:
    """Read a specific knowledge file by name.

    Args:
        file_name: File name (e.g. "pattern-false-obviousness.md") or partial match
    """
    from indexer import parse_knowledge_file

    # Try exact match first
    exact = KNOWLEDGE_DIR / file_name
    if exact.exists():
        parsed = parse_knowledge_file(exact)
        if parsed:
            return f"## {parsed['meta'].get('name', file_name)}\n\n{parsed['body']}"

    # Try partial match
    matches = []
    for md_file in KNOWLEDGE_DIR.glob("*.md"):
        if file_name.lower() in md_file.name.lower():
            matches.append(md_file)

    if not matches:
        return f"No knowledge file matching '{file_name}' found."

    if len(matches) == 1:
        parsed = parse_knowledge_file(matches[0])
        if parsed:
            return f"## {parsed['meta'].get('name', matches[0].name)}\n\n{parsed['body']}"

    lines = [f"Multiple matches for '{file_name}':\n"]
    for m in matches:
        lines.append(f"- {m.name}")
    return "\n".join(lines)


@mcp.tool()
async def knowledge_graph() -> str:
    """Export the knowledge graph as JSON for visualization.

    Returns a JSON object with nodes (knowledge entries) and edges
    (relations between them), plus domain cluster data.
    Designed for force-directed graph rendering.
    """
    import json as _json

    db = get_connection()
    init_db(db)

    stats = get_stats(db)
    if stats["total"] == 0:
        log.info("Knowledge base empty, auto-indexing...")
        await _do_reindex(db)
    elif _is_reindex_needed(db):
        log.info("Knowledge files changed on disk, auto-reindexing...")
        await _do_reindex(db)

    data = graph_data(db)

    # Add domain clusters
    domains = scan_domains()
    data["domains"] = domains

    db.close()
    return _json.dumps(data, ensure_ascii=False, indent=2)


@mcp.tool()
async def open_graph() -> str:
    """Generate the knowledge graph and open visualization in browser.

    Exports graph data as JSON, writes it to the visualization directory,
    and opens the HTML file in the default browser.
    """
    import json as _json
    import subprocess

    db = get_connection()
    init_db(db)

    stats = get_stats(db)
    if stats["total"] == 0:
        log.info("Knowledge base empty, auto-indexing...")
        await _do_reindex(db)
    elif _is_reindex_needed(db):
        log.info("Knowledge files changed on disk, auto-reindexing...")
        await _do_reindex(db)

    data = graph_data(db)
    domains = scan_domains()
    data["domains"] = domains
    db.close()

    # Write JSON to visualization directory
    viz_dir = Path(__file__).parent / "visualization"
    viz_dir.mkdir(exist_ok=True)
    json_path = viz_dir / "graph-data.json"
    json_path.write_text(_json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    html_path = viz_dir / "index.html"
    if not html_path.exists():
        return f"Graph data written to {json_path}, but index.html not found in {viz_dir}"

    # Open in browser
    subprocess.Popen(["open", str(html_path)])
    return f"Graph opened in browser. {len(data['nodes'])} nodes, {len(data['edges'])} edges."


@mcp.tool()
async def open_dashboard() -> str:
    """Generate knowledge metrics and open the dashboard in browser.

    Shows: knowledge health, confidence/impact distributions, domain coverage,
    reliability rankings, recent updates, and type statistics.
    """
    import json as _json
    import subprocess

    db = get_connection()
    init_db(db)

    stats = get_stats(db)
    if stats["total"] == 0:
        log.info("Knowledge base empty, auto-indexing...")
        await _do_reindex(db)
    elif _is_reindex_needed(db):
        log.info("Knowledge files changed on disk, auto-reindexing...")
        await _do_reindex(db)

    data = dashboard_data(db)
    db.close()

    viz_dir = Path(__file__).parent / "visualization"
    viz_dir.mkdir(exist_ok=True)
    json_path = viz_dir / "dashboard-data.json"
    json_path.write_text(_json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    html_path = viz_dir / "dashboard.html"
    if not html_path.exists():
        return f"Dashboard data written to {json_path}, but dashboard.html not found in {viz_dir}"

    subprocess.Popen(["open", str(html_path)])
    return f"Dashboard opened. {data['summary']['total']} entries analyzed."


@mcp.tool()
async def brain_export(output_dir: str = "") -> str:
    """Export the full ClaudSoul brain as a portable archive.

    Packs all knowledge, skills, hooks, templates, domains, sessions,
    knowledge.db, settings, and global rules into a .tar.gz archive.
    Transfer this archive to another machine to replicate the brain.

    Args:
        output_dir: Directory to save the archive (default: ~/Desktop)
    """
    from pathlib import Path as _Path

    out = _Path(output_dir) if output_dir else None
    if out and not out.exists():
        return f"Output directory does not exist: {output_dir}"

    try:
        archive_path = export_brain(out)
        return (
            f"🧠 Brain exported successfully!\n\n"
            f"**Archive:** `{archive_path}`\n"
            f"**Size:** {archive_path.stat().st_size / 1024:.1f} KB\n\n"
            f"Transfer this file to another machine and use `brain_import` to restore."
        )
    except Exception as e:
        return f"Export failed: {e}"


@mcp.tool()
async def brain_import(archive_path: str, dry_run: bool = True) -> str:
    """Import a ClaudSoul brain archive into this machine.

    Merges knowledge (higher confirmed_count wins), overwrites skills/hooks,
    adds missing domains, merges hook settings.

    Args:
        archive_path: Path to the .tar.gz brain archive
        dry_run: If true (default), only preview changes without applying them.
                 Set to false to actually import.
    """
    from pathlib import Path as _Path

    path = _Path(archive_path)
    if not path.exists():
        return f"Archive not found: {archive_path}"
    if not path.name.endswith(".tar.gz"):
        return f"Expected a .tar.gz archive, got: {path.name}"

    try:
        report = import_brain(path, dry_run=dry_run)
    except Exception as e:
        return f"Import failed: {e}"

    mode = "🔍 DRY RUN (preview)" if dry_run else "✅ IMPORTED"
    lines = [f"## {mode}\n"]

    k = report["knowledge"]
    lines.append(f"**Knowledge:** +{k['added']} new, ↑{k['updated']} updated, ={k['skipped']} skipped")

    c = report["commands"]
    lines.append(f"**Skills:** +{c['added']} new, ↑{c['updated']} updated")

    h = report["hooks"]
    lines.append(f"**Hooks:** +{h['added']} new, ↑{h['updated']} updated")

    t = report["templates"]
    lines.append(f"**Templates:** +{t['added']} new, ↑{t['updated']} updated")

    d = report["domains"]
    lines.append(f"**Domains:** +{d['added']} new")

    if report["rules"]:
        lines.append("**Rules (CLAUDE.md):** " + ("will be updated" if dry_run else "updated"))
    if report["settings_merged"]:
        lines.append("**Settings (hooks):** " + ("will be merged" if dry_run else "merged"))
    if report["db_reindex_needed"]:
        lines.append("\n⚠️ Knowledge files changed — run `reindex_knowledge` to update embeddings.")

    if dry_run:
        lines.append(f"\n*Run with `dry_run: false` to apply these changes.*")

    return "\n".join(lines)


def _is_reindex_needed(db) -> bool:
    """Return True when the SQLite index is behind the filesystem.

    Triggers reindex if the file count differs from DB, or if any .md on
    disk was modified after the latest `updated_at` in the DB. META.md and
    files starting with `_` are skipped to match indexer's scan rules.
    """
    from datetime import datetime
    from storage import get_meta

    if not KNOWLEDGE_DIR.exists():
        return False

    # Смена модели эмбеддингов → все векторы устарели, нужен полный реиндекс
    if get_meta(db, "embed_model") != EMBED_MODEL:
        return True

    md_files = [
        f for f in KNOWLEDGE_DIR.glob("*.md")
        if not f.name.startswith("_") and f.name != "META.md"
    ]
    if not md_files:
        return False

    stats = get_stats(db)
    if stats["total"] != len(md_files):
        return True

    latest_disk = max(f.stat().st_mtime for f in md_files)

    row = db.execute("SELECT MAX(updated_at) FROM knowledge").fetchone()
    if not row or not row[0]:
        return True
    try:
        latest_db = datetime.fromisoformat(row[0]).timestamp()
    except ValueError:
        return True

    # 1s tolerance to avoid false positives from fractional mtimes
    return latest_disk > latest_db + 1


async def _do_reindex(db) -> int:
    """Internal: perform full reindex."""
    entries = index_all()

    # Fail-safe против обнуления индекса: пустой результат index_all() при непустой
    # БД — почти всегда транзиентный сбой (пустой/недоступный global-lessons или не
    # загрузился fastembed), а не легитимное удаление всех знаний. Не зовём
    # remove_stale: устаревшие записи восстановимы следующим reindex, потеря всего
    # индекса — нет. Авто-путь это уже исключал через _is_reindex_needed, но
    # reindex_knowledge tool и viz зовут _do_reindex напрямую, минуя ту проверку.
    if not entries and get_stats(db)["total"] > 0:
        log.warning(
            "index_all() вернул пусто при непустой БД — пропускаю remove_stale "
            "(защита от обнуления индекса)"
        )
        return 0

    existing_paths = set()

    for entry in entries:
        existing_paths.add(entry["file_path"])
        upsert_knowledge(
            db,
            file_path=entry["file_path"],
            name=entry["name"],
            type_=entry["type_"],
            confidence=entry["confidence"],
            impact=entry["impact"],
            status=entry["status"],
            domain=entry["domain"],
            tags=entry["tags"],
            content=entry["content"],
            updated_at=entry["updated_at"],
            embedding=entry["embedding"],
            confirmed_count=entry.get("confirmed_count", 0),
            contradicted_count=entry.get("contradicted_count", 0),
            edges_json=entry.get("edges_json", []),
        )

    removed = remove_stale(db, existing_paths)
    # Зафиксировать модель, которой построен индекс — для детекции смены модели
    from storage import set_meta
    set_meta(db, "embed_model", EMBED_MODEL)
    total = len(entries)
    log.info(f"Indexed {total} files, removed {removed} stale entries")
    return total


if __name__ == "__main__":
    mcp.run(transport="stdio")
