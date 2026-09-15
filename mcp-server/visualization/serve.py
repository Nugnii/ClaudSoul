#!/usr/bin/env python3
"""Live HTTP server for the ClaudSoul knowledge-graph visualization.

Serves static files from this directory. For `/graph-data.json` and
`/dashboard-data.json` the server calls MCP's reindex-if-needed and
regenerates the payload on every request, so browser refresh always
reflects the current state of ~/.claude/global-lessons/.
"""
import asyncio
import json
import shutil
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
MCP_DIR = HERE.parent
sys.path.insert(0, str(MCP_DIR))
KNOWLEDGE_ROOT = Path.home() / ".claude" / "global-lessons"
ARCHIVE_DIR = KNOWLEDGE_ROOT / "_archive"

_modules = None


def _load():
    global _modules
    if _modules is None:
        import storage
        import server as mcp_server
        from indexer import scan_domains
        _modules = (storage, mcp_server, scan_domains)
    return _modules


def _ensure_fresh(storage, mcp_server, db):
    stats = storage.get_stats(db)
    if stats["total"] == 0 or mcp_server._is_reindex_needed(db):
        asyncio.run(mcp_server._do_reindex(db))


def _build_graph_data() -> bytes:
    storage, mcp_server, scan_domains = _load()
    db = storage.get_connection()
    storage.init_db(db)
    _ensure_fresh(storage, mcp_server, db)
    data = storage.graph_data(db)
    data["domains"] = scan_domains()
    db.close()
    return json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")


def _build_dashboard_data() -> bytes:
    storage, mcp_server, _ = _load()
    db = storage.get_connection()
    storage.init_db(db)
    _ensure_fresh(storage, mcp_server, db)
    data = storage.dashboard_data(db)
    db.close()
    return json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")


LIVE_ENDPOINTS = {
    "/graph-data.json": _build_graph_data,
    "/dashboard-data.json": _build_dashboard_data,
}


def _resolve_node_path(node_id: int) -> Path:
    """Look up the on-disk .md file for a knowledge node id."""
    storage, _, _ = _load()
    db = storage.get_connection()
    storage.init_db(db)
    row = db.execute(
        "SELECT file_path FROM knowledge WHERE id = ?", (node_id,)
    ).fetchone()
    db.close()
    if not row:
        raise ValueError(f"node {node_id} not found")
    path = Path(row[0]).resolve()
    root = KNOWLEDGE_ROOT.resolve()
    if root not in path.parents and path != root:
        raise ValueError(f"path {path} is outside {root}")
    return path


def _reindex_after_mutation() -> None:
    storage, mcp_server, _ = _load()
    db = storage.get_connection()
    storage.init_db(db)
    asyncio.run(mcp_server._do_reindex(db))
    db.close()


def _op_open(node_id: int) -> dict:
    path = _resolve_node_path(node_id)
    if not path.exists():
        raise ValueError(f"file missing: {path}")
    # macOS reveals in Finder; on other platforms falls back to xdg-open
    if sys.platform == "darwin":
        subprocess.Popen(["open", "-R", str(path)])
    elif sys.platform.startswith("linux"):
        subprocess.Popen(["xdg-open", str(path.parent)])
    else:
        raise ValueError(f"unsupported platform: {sys.platform}")
    return {"ok": True, "path": str(path)}


def _op_archive(node_id: int) -> dict:
    path = _resolve_node_path(node_id)
    if not path.exists():
        raise ValueError(f"file missing: {path}")
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    dst = ARCHIVE_DIR / path.name
    i = 1
    while dst.exists():
        dst = ARCHIVE_DIR / f"{path.stem}.{i}{path.suffix}"
        i += 1
    shutil.move(str(path), str(dst))
    _reindex_after_mutation()
    return {"ok": True, "archived_to": str(dst)}


def _op_delete(node_id: int) -> dict:
    path = _resolve_node_path(node_id)
    if not path.exists():
        raise ValueError(f"file missing: {path}")
    path.unlink()
    _reindex_after_mutation()
    return {"ok": True, "deleted": str(path)}


MUTATION_ENDPOINTS = {
    "/api/node/open": _op_open,
    "/api/node/archive": _op_archive,
    "/api/node/delete": _op_delete,
}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(HERE), **kw)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        builder = LIVE_ENDPOINTS.get(path)
        if builder is None:
            return super().do_GET()
        try:
            body = builder()
        except Exception as e:
            self.send_response(500)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(f"error: {e}".encode("utf-8"))
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _origin_allowed(self) -> bool:
        """Reject cross-origin browser POSTs (CSRF). Non-browser clients
        (no Origin header) and same-origin requests pass."""
        origin = self.headers.get("Origin")
        if origin is None:
            return True
        host = self.headers.get("Host", "")
        return origin in (f"http://{host}", f"https://{host}")

    def do_POST(self):
        # Read the request body up front so every response branch leaves the
        # connection cleanly framed (unread body → RST on close).
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        if not self._origin_allowed():
            body = b"cross-origin request rejected"
            self.send_response(403)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        path = self.path.split("?", 1)[0]
        op = MUTATION_ENDPOINTS.get(path)
        if op is None:
            body = b"unknown endpoint"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
            node_id = int(payload.get("id"))
            result = op(node_id)
            body = json.dumps(result, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            body = json.dumps({"ok": False, "error": str(e)}).encode("utf-8")
            self.send_response(400)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8742
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"ClaudSoul viz live on http://localhost:{port}", file=sys.stderr, flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.server_close()


if __name__ == "__main__":
    main()
