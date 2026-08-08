"""SQLite-vec storage for knowledge embeddings."""

import json
import re
import sqlite3
import sqlite_vec
import struct
from pathlib import Path
from typing import Optional

import yaml


_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def _parse_relation_endpoints(file_path: str) -> tuple[Optional[str], Optional[str], Optional[str]]:
    """Extract (from_entity, to_entity, relation_type) from a relation file's frontmatter.

    Reads from disk because the indexer strips the frontmatter before storing `content`.
    Returns (None, None, None) if parsing fails or the file is missing.
    """
    if not file_path:
        return None, None, None
    try:
        raw = Path(file_path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None, None, None
    match = _FRONTMATTER_RE.match(raw)
    if not match:
        return None, None, None
    try:
        fm = yaml.safe_load(match.group(1)) or {}
    except yaml.YAMLError:
        return None, None, None
    if not isinstance(fm, dict):
        return None, None, None
    return fm.get("from_entity"), fm.get("to_entity"), fm.get("relation_type")

DB_PATH = Path.home() / ".claude" / "knowledge.db"


def _serialize_f32(vec: list[float]) -> bytes:
    """Serialize float list to bytes for sqlite-vec."""
    return struct.pack(f"{len(vec)}f", *vec)


def get_connection(db_path: Optional[Path] = None) -> sqlite3.Connection:
    """Get SQLite connection with vec extension loaded."""
    path = db_path or DB_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(str(path))
    db.enable_load_extension(True)
    sqlite_vec.load(db)
    db.enable_load_extension(False)
    return db


def init_db(db: sqlite3.Connection) -> None:
    """Create tables if they don't exist."""
    db.execute("""
        CREATE TABLE IF NOT EXISTS knowledge (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT UNIQUE NOT NULL,
            name TEXT,
            type TEXT,
            confidence INTEGER,
            impact INTEGER,
            status TEXT,
            domain TEXT,
            tags TEXT,
            content TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            confirmed_count INTEGER DEFAULT 0,
            contradicted_count INTEGER DEFAULT 0,
            edges_json TEXT DEFAULT '[]'
        )
    """)
    db.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS vec_knowledge
        USING vec0(embedding float[384])
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)
    """)
    # Migration: add columns if they don't exist (for existing databases)
    existing_cols = {row[1] for row in db.execute("PRAGMA table_info(knowledge)").fetchall()}
    for col, default in [
        ("confirmed_count", "0"),
        ("contradicted_count", "0"),
        ("edges_json", "'[]'"),
    ]:
        if col not in existing_cols:
            db.execute(f"ALTER TABLE knowledge ADD COLUMN {col} {'INTEGER' if 'count' in col else 'TEXT'} DEFAULT {default}")
    db.commit()


def get_meta(db: sqlite3.Connection, key: str, default: Optional[str] = None) -> Optional[str]:
    """Read a value from the meta key-value table (None/default if absent)."""
    try:
        row = db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
    except sqlite3.OperationalError:
        return default
    return row[0] if row else default


def set_meta(db: sqlite3.Connection, key: str, value: str) -> None:
    """Upsert a value into the meta key-value table."""
    db.execute(
        "INSERT INTO meta (key, value) VALUES (?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (key, str(value)),
    )
    db.commit()


def upsert_knowledge(
    db: sqlite3.Connection,
    file_path: str,
    name: str,
    type_: str,
    confidence: int,
    impact: int,
    status: str,
    domain: str,
    tags: str,
    content: str,
    updated_at: str,
    embedding: list[float],
    confirmed_count: int = 0,
    contradicted_count: int = 0,
    edges_json: Optional[list] = None,
) -> None:
    """Insert or update a knowledge entry with its embedding."""
    edges_str = json.dumps(edges_json or [], ensure_ascii=False)
    existing = db.execute(
        "SELECT id FROM knowledge WHERE file_path = ?", (file_path,)
    ).fetchone()

    if existing:
        row_id = existing[0]
        db.execute(
            """UPDATE knowledge SET name=?, type=?, confidence=?, impact=?,
               status=?, domain=?, tags=?, content=?, updated_at=?,
               confirmed_count=?, contradicted_count=?, edges_json=?
               WHERE id=?""",
            (name, type_, confidence, impact, status, domain, tags, content, updated_at,
             confirmed_count, contradicted_count, edges_str, row_id),
        )
        db.execute(
            "UPDATE vec_knowledge SET embedding = ? WHERE rowid = ?",
            (_serialize_f32(embedding), row_id),
        )
    else:
        cursor = db.execute(
            """INSERT INTO knowledge (file_path, name, type, confidence, impact,
               status, domain, tags, content, updated_at,
               confirmed_count, contradicted_count, edges_json)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (file_path, name, type_, confidence, impact, status, domain, tags, content, updated_at,
             confirmed_count, contradicted_count, edges_str),
        )
        row_id = cursor.lastrowid
        db.execute(
            "INSERT INTO vec_knowledge (rowid, embedding) VALUES (?, ?)",
            (row_id, _serialize_f32(embedding)),
        )
    db.commit()


def search(
    db: sqlite3.Connection,
    query_embedding: list[float],
    limit: int = 5,
    type_filter: Optional[str] = None,
    min_confidence: int = 0,
) -> list[dict]:
    """Semantic search across knowledge base."""
    results = db.execute(
        """
        SELECT v.rowid, v.distance, k.file_path, k.name, k.type,
               k.confidence, k.impact, k.status, k.domain, k.tags, k.content
        FROM vec_knowledge v
        JOIN knowledge k ON k.id = v.rowid
        WHERE v.embedding MATCH ?
          AND k = ?
        ORDER BY v.distance
        """,
        (_serialize_f32(query_embedding), limit * 3),
    ).fetchall()

    filtered = []
    for row in results:
        rowid, distance, fpath, name, type_, conf, imp, status, domain, tags, content = row
        if type_filter and type_ != type_filter:
            continue
        if conf is not None and conf < min_confidence:
            continue
        filtered.append({
            "file_path": fpath,
            "name": name,
            "type": type_,
            "confidence": conf,
            "impact": imp,
            "status": status,
            "domain": domain,
            "tags": tags,
            "content": content[:500],
            "distance": round(distance, 4),
        })
        if len(filtered) >= limit:
            break

    return filtered


def get_stats(db: sqlite3.Connection) -> dict:
    """Get knowledge base statistics."""
    total = db.execute("SELECT COUNT(*) FROM knowledge").fetchone()[0]
    by_type = db.execute(
        "SELECT type, COUNT(*) FROM knowledge GROUP BY type"
    ).fetchall()
    avg_conf = db.execute(
        "SELECT AVG(confidence) FROM knowledge WHERE confidence IS NOT NULL"
    ).fetchone()[0]

    return {
        "total": total,
        "by_type": {row[0]: row[1] for row in by_type},
        "avg_confidence": round(avg_conf, 1) if avg_conf else 0,
    }


def graph_data(db: sqlite3.Connection) -> dict:
    """Export all knowledge as graph data for visualization.

    Returns {nodes: [...], edges: [...]} where:
    - nodes have id, name, type, confidence, impact, domain, tags,
      confirmed_count, contradicted_count
    - edges have source, target, type (from edges_json + domain relations)
    """
    rows = db.execute(
        """SELECT id, file_path, name, type, confidence, impact, status,
                  domain, tags, confirmed_count, contradicted_count, edges_json, content
           FROM knowledge"""
    ).fetchall()

    # First pass: build file_path → id lookup for edge resolution.
    # Relation files are skipped as nodes — they become edges in pass 2.
    path_to_id = {}
    id_to_conf = {}
    id_to_reliability = {}
    nodes = []
    for row in rows:
        (row_id, fpath, name, type_, conf, imp, status,
         domain, tags, confirmed, contradicted, edges_str, content) = row
        fname = Path(fpath).name
        path_to_id[fname] = row_id
        path_to_id[fpath] = row_id

        reliability = (confirmed or 0) - (contradicted or 0)
        mass = (conf or 1) * (imp or 1)
        id_to_conf[row_id] = conf or 1
        id_to_reliability[row_id] = reliability

        if type_ == "relation":
            continue

        # Extract first meaningful line as summary
        summary = ""
        if content:
            for line in content.split("\n"):
                line = line.strip()
                if line and not line.startswith("#") and not line.startswith("---"):
                    summary = line[:200]
                    break

        nodes.append({
            "id": row_id,
            "name": name or fname,
            "type": type_ or "unknown",
            "confidence": conf or 1,
            "impact": imp or 1,
            "mass": mass,
            "reliability": reliability,
            "confirmed_count": confirmed or 0,
            "contradicted_count": contradicted or 0,
            "domain": domain or "",
            "tags": tags or "",
            "status": status or "active",
            "summary": summary,
        })

    # Second pass: build edges from edges_json and from relation-*.md files
    edges = []
    seen_edges = set()
    for row in rows:
        (row_id, fpath, name, type_, conf, imp, status,
         _domain, _tags, _conf_c, _contra_c, edges_str, content) = row

        # 2a. Edges declared in frontmatter `edges:` field (cases/patterns/principles)
        try:
            edge_list = json.loads(edges_str) if edges_str else []
        except json.JSONDecodeError:
            edge_list = []

        for edge in edge_list:
            target_file = edge.get("target", "")
            target_id = path_to_id.get(target_file)
            if target_id and target_id != row_id:
                edge_key = (min(row_id, target_id), max(row_id, target_id), edge["type"])
                if edge_key not in seen_edges:
                    seen_edges.add(edge_key)
                    strength = min(
                        id_to_conf.get(row_id, 1),
                        id_to_conf.get(target_id, 1),
                    )
                    edges.append({
                        "source": row_id,
                        "target": target_id,
                        "type": edge["type"],
                        "strength": strength,
                    })

        # 2b. Relation files contribute edges between their from_entity / to_entity.
        if type_ != "relation":
            continue
        from_e, to_e, rel_type = _parse_relation_endpoints(fpath)
        if not from_e or not to_e:
            continue
        source_id = path_to_id.get(from_e)
        target_id = path_to_id.get(to_e)
        if not source_id or not target_id or source_id == target_id:
            continue
        edge_type = rel_type or "relation"
        edge_key = (source_id, target_id, edge_type)
        if edge_key in seen_edges:
            continue
        seen_edges.add(edge_key)
        edges.append({
            "source": source_id,
            "target": target_id,
            "type": edge_type,
            "strength": conf or 1,
        })

    # Relation-файлы не являются узлами (пропущены в первом проходе), но их id
    # попадает в path_to_id — рёбра, ссылающиеся на них, висячие и ломают отрисовку
    # ("node not found: N" в force-graph). Отбрасываем: связь между сущностями уже
    # построена в 2b напрямую.
    node_ids = {n["id"] for n in nodes}
    edges = [e for e in edges if e["source"] in node_ids and e["target"] in node_ids]

    return {"nodes": nodes, "edges": edges}


def dashboard_data(db: sqlite3.Connection) -> dict:
    """Collect comprehensive metrics for the knowledge dashboard.

    Returns:
        - summary: total, by_type, avg_confidence, avg_impact
        - confidence_dist: histogram of confidence values (1-5)
        - impact_dist: histogram of impact values (1-5)
        - reliability: top/bottom entries by confirmed - contradicted
        - domains: coverage map {domain: count}
        - health: stale/weak/contradicted entries
        - recent: last 10 updated entries
        - type_mass: average mass per type
    """
    rows = db.execute(
        """SELECT id, file_path, name, type, confidence, impact, status,
                  domain, tags, confirmed_count, contradicted_count, updated_at
           FROM knowledge ORDER BY updated_at DESC"""
    ).fetchall()

    if not rows:
        return {"summary": {"total": 0}, "confidence_dist": {}, "impact_dist": {},
                "reliability": [], "domains": {}, "health": [], "recent": [], "type_mass": {}}

    # Summary
    total = len(rows)
    by_type = {}
    conf_sum, imp_sum, conf_count, imp_count = 0, 0, 0, 0
    conf_dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
    imp_dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
    domains = {}
    type_mass_sum = {}
    type_mass_count = {}
    entries = []

    for row in rows:
        (row_id, fpath, name, type_, conf, imp, status,
         domain, tags, confirmed, contradicted, updated_at) = row

        by_type[type_ or "unknown"] = by_type.get(type_ or "unknown", 0) + 1

        if conf is not None:
            conf_sum += conf
            conf_count += 1
            if 1 <= conf <= 5:
                conf_dist[conf] += 1
        if imp is not None:
            imp_sum += imp
            imp_count += 1
            if 1 <= imp <= 5:
                imp_dist[imp] += 1

        # Domain parsing (can be comma-separated or JSON list)
        if domain:
            for d in domain.replace("[", "").replace("]", "").replace("'", "").replace('"', "").split(","):
                d = d.strip()
                if d:
                    domains[d] = domains.get(d, 0) + 1

        mass = (conf or 1) * (imp or 1)
        t = type_ or "unknown"
        type_mass_sum[t] = type_mass_sum.get(t, 0) + mass
        type_mass_count[t] = type_mass_count.get(t, 0) + 1

        reliability = (confirmed or 0) - (contradicted or 0)
        entries.append({
            "id": row_id,
            "name": name or Path(fpath).name,
            "type": type_ or "unknown",
            "confidence": conf or 0,
            "impact": imp or 0,
            "mass": mass,
            "reliability": reliability,
            "confirmed": confirmed or 0,
            "contradicted": contradicted or 0,
            "status": status or "active",
            "updated_at": updated_at or "",
        })

    # Sort by reliability for top/bottom
    by_reliability = sorted(entries, key=lambda e: e["reliability"], reverse=True)
    top_reliable = by_reliability[:5]
    bottom_reliable = [e for e in by_reliability if e["reliability"] < 0][:5]

    # Health issues
    health = []
    for e in entries:
        issues = []
        if e["confidence"] <= 1 and e["confirmed"] == 0:
            issues.append("unconfirmed")
        if e["contradicted"] > e["confirmed"]:
            issues.append("contradicted")
        if e["status"] == "weakened":
            issues.append("weakened")
        if e["status"] == "deprecated":
            issues.append("deprecated")
        if issues:
            health.append({"name": e["name"], "type": e["type"], "issues": issues})

    # Type mass averages
    type_mass = {}
    for t in type_mass_sum:
        type_mass[t] = round(type_mass_sum[t] / type_mass_count[t], 1)

    return {
        "summary": {
            "total": total,
            "by_type": by_type,
            "avg_confidence": round(conf_sum / conf_count, 1) if conf_count else 0,
            "avg_impact": round(imp_sum / imp_count, 1) if imp_count else 0,
        },
        "confidence_dist": conf_dist,
        "impact_dist": imp_dist,
        "reliability": {
            "top": top_reliable,
            "bottom": bottom_reliable,
        },
        "domains": domains,
        "health": health,
        "recent": [{"name": e["name"], "type": e["type"], "updated_at": e["updated_at"],
                     "confidence": e["confidence"], "reliability": e["reliability"]}
                   for e in entries[:10]],
        "type_mass": type_mass,
    }


def remove_stale(db: sqlite3.Connection, existing_paths: set[str]) -> int:
    """Remove entries for files that no longer exist."""
    all_paths = db.execute("SELECT id, file_path FROM knowledge").fetchall()
    removed = 0
    for row_id, fpath in all_paths:
        if fpath not in existing_paths:
            db.execute("DELETE FROM knowledge WHERE id = ?", (row_id,))
            db.execute("DELETE FROM vec_knowledge WHERE rowid = ?", (row_id,))
            removed += 1
    if removed:
        db.commit()
    return removed
