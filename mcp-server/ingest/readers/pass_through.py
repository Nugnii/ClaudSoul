"""MD reader — read as-is, run through normalizer."""

from __future__ import annotations

from pathlib import Path

from ..normalize import normalize
from ..parse import ParseResult


def read(path: Path, source_id: str, **opts) -> ParseResult:
    markdown = path.read_text(encoding="utf-8")
    normalized, blocks = normalize(markdown, source_id)
    return ParseResult(
        markdown=normalized,
        blocks=blocks,
        warnings=[],
        parser="pass_through",
        parser_version="1.1.1",
    )
