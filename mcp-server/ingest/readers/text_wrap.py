"""TXT reader — wrap in a single code block under a heading = filename stem."""

from __future__ import annotations

from pathlib import Path

from ..normalize import normalize
from ..parse import ParseResult


def read(path: Path, source_id: str, **opts) -> ParseResult:
    raw = path.read_text(encoding="utf-8")
    heading = path.stem
    markdown = f"# {heading}\n\n```\n{raw}\n```\n"
    normalized, blocks = normalize(markdown, source_id)
    return ParseResult(
        markdown=normalized,
        blocks=blocks,
        warnings=[],
        parser="text_wrap",
        parser_version="1.1.1",
    )
