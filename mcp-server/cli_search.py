#!/usr/bin/env python
"""CLI wrapper for semantic search — used by knowledge-activator hook as fallback
when keyword-based scoring yields weak matches.

Usage:
    cli_search.py "<query>" [limit] [min_confidence]

Output: JSON array to stdout. On error: prints "[]" to stdout, error to stderr.
Fast-fails silently so the hook doesn't block Claude Code on MCP issues.
"""
import sys
import json

try:
    from storage import get_connection, init_db, search, get_meta
    from indexer import embed_text, EMBED_MODEL
except Exception as e:
    print("[]")
    print(f"cli_search: import failed: {e}", file=sys.stderr)
    sys.exit(0)


def main() -> int:
    if len(sys.argv) < 2:
        print("[]")
        return 0

    query = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    min_conf = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    limit = max(1, min(limit, 20))

    try:
        db = get_connection()
        init_db(db)
        # Индекс построен другой моделью → векторы несравнимы. Безопасная
        # деградация: пусто (хук откатится на keyword), не мусорные результаты.
        if get_meta(db, "embed_model") != EMBED_MODEL:
            print("[]")
            print("cli_search: index built with a different embed model — reindex needed", file=sys.stderr)
            return 0
        embedding = embed_text(query)
        results = search(db, embedding, limit=limit, min_confidence=min_conf)
        # Strip the large `content` field — hook only needs file_path + score
        slim = [
            {
                "file_path": r["file_path"],
                "name": r["name"],
                "type": r["type"],
                "confidence": r["confidence"],
                "impact": r["impact"],
                "distance": r["distance"],
            }
            for r in results
        ]
        print(json.dumps(slim, ensure_ascii=False))
    except Exception as e:
        print("[]")
        print(f"cli_search: runtime error: {e}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
