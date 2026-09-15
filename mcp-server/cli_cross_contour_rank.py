#!/usr/bin/env python
"""CLI ranker for cross-contour discoveries (Phase 5.1 / v1.6).

Reads cross-contour-discoveries.jsonl, computes cosine similarity for each
unique (knowledge_file, entity_file) pair via fastembed, writes
cross-contour-ranked.jsonl. Overwrites output on each run — latest state only.

Designed for weekly invocation from knowledge-audit-digest.sh. Silent on any
error: must never break the audit. Exit code always 0.

Env:
    LESSONS_DIR                     — path to lessons dir (default ~/.claude/global-lessons)
    CLAUDSOUL_CROSS_CONTOUR_LOG     — input discoveries path (default state/cross-contour-discoveries.jsonl)
    CLAUDSOUL_CROSS_CONTOUR_RANKED  — output ranked path (default state/cross-contour-ranked.jsonl)
"""
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    try:
        lessons_dir = Path(os.environ.get("LESSONS_DIR", Path.home() / ".claude" / "global-lessons"))
        log_path = Path(os.environ.get(
            "CLAUDSOUL_CROSS_CONTOUR_LOG",
            Path.home() / ".claude" / "hooks" / "state" / "cross-contour-discoveries.jsonl",
        ))
        ranked_path = Path(os.environ.get(
            "CLAUDSOUL_CROSS_CONTOUR_RANKED",
            Path.home() / ".claude" / "hooks" / "state" / "cross-contour-ranked.jsonl",
        ))

        if not lessons_dir.exists() or not log_path.exists():
            return 0

        # Collect unique (KF, EF) pairs from discoveries log
        pairs: dict[tuple[str, str], str] = {}
        with log_path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                kf = rec.get("knowledge_file")
                ef = rec.get("entity_file")
                matched = rec.get("matched", "")
                if kf and ef:
                    pairs.setdefault((kf, ef), matched)

        if not pairs:
            return 0

        from indexer import build_search_text, embed_texts, parse_knowledge_file

        unique_files = {kf for kf, _ in pairs} | {ef for _, ef in pairs}
        texts: dict[str, str] = {}
        for fname in unique_files:
            path = lessons_dir / fname
            if not path.exists():
                continue
            parsed = parse_knowledge_file(path)
            if parsed:
                texts[fname] = build_search_text(parsed)

        if not texts:
            return 0

        names = list(texts.keys())
        embeddings = embed_texts([texts[n] for n in names])
        emb_map = dict(zip(names, embeddings))

        def cosine(a: list[float], b: list[float]) -> float:
            num = sum(x * y for x, y in zip(a, b))
            da = sum(x * x for x in a) ** 0.5
            db = sum(y * y for y in b) ** 0.5
            if da == 0 or db == 0:
                return 0.0
            return num / (da * db)

        ranked_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
        ranked_path.parent.mkdir(parents=True, exist_ok=True)
        with ranked_path.open("w", encoding="utf-8") as f:
            for (kf, ef), matched in pairs.items():
                ek = emb_map.get(kf)
                ee = emb_map.get(ef)
                if ek is None or ee is None:
                    continue
                sim = round(cosine(ek, ee), 4)
                rec = {
                    "knowledge_file": kf,
                    "entity_file": ef,
                    "matched": matched,
                    "similarity": sim,
                    "ranked_at": ranked_at,
                }
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception as e:
        print(f"cli_cross_contour_rank: error: {e}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
