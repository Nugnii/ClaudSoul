"""ClaudSoul Ingestion Pipeline — v1.1.1

Stages:
- parse:      source -> unified Markdown + parsed.jsonl
- extract:    Markdown -> entities/facts/relations JSON (in /ingest skill, v1.1.2)
- integrate:  JSON -> files in ~/.claude/global-lessons/ with dedup + confidence recalc

See docs/ingestion-pipeline.md for the full spec.
"""

from .discovery import discover
from .parse import parse, ParseResult, Block
from .source_store import SourceStore

__all__ = ["parse", "ParseResult", "Block", "SourceStore", "discover"]
