"""Parse dispatcher — picks backend by file extension.

See docs/ingestion-pipeline.md §4.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Block:
    block_id: str
    source_id: str
    block_type: str              # heading | paragraph | list_item | table_row | code_block | quote
    text: str
    provenance: dict             # {page?: int, offset?: int, heading_path: list[str]}


@dataclass
class ParseResult:
    markdown: str
    blocks: list[Block]
    warnings: list[str] = field(default_factory=list)
    parser: str = ""
    parser_version: str = ""


def parse(path: Path, source_id: str, **opts) -> ParseResult:
    """Dispatch by extension. Implemented in M2."""
    ext = path.suffix.lower()
    if ext == ".md":
        from .readers import pass_through
        return pass_through.read(path, source_id, **opts)
    if ext == ".txt":
        from .readers import text_wrap
        return text_wrap.read(path, source_id, **opts)
    if ext == ".pdf":
        from .readers import pymupdf4llm_reader
        return pymupdf4llm_reader.read(path, source_id, **opts)
    if ext in (".docx", ".html", ".htm"):
        from .readers import markitdown_reader
        return markitdown_reader.read(path, source_id, **opts)
    raise ValueError(f"Unsupported extension: {ext}")
