"""PDF reader via pymupdf4llm. Page-level provenance via <!-- page: N --> anchors."""

from __future__ import annotations

from pathlib import Path

from ..normalize import normalize
from ..parse import ParseResult


def read(path: Path, source_id: str, **opts) -> ParseResult:
    try:
        import pymupdf4llm  # type: ignore
    except ImportError as e:
        raise RuntimeError(
            "pymupdf4llm is required for PDF ingestion. Install with `uv add pymupdf4llm`."
        ) from e

    pages = pymupdf4llm.to_markdown(str(path), page_chunks=True)

    parts: list[str] = []
    warnings: list[str] = []
    for i, chunk in enumerate(pages, start=1):
        md = chunk.get("text", "") if isinstance(chunk, dict) else str(chunk)
        if not md.strip():
            warnings.append(f"page {i}: empty markdown")
        parts.append(f"<!-- page: {i} -->\n{md}")

    markdown = "\n\n".join(parts)
    normalized, blocks = normalize(markdown, source_id)

    version = getattr(pymupdf4llm, "__version__", "unknown")
    return ParseResult(
        markdown=normalized,
        blocks=blocks,
        warnings=warnings,
        parser="pymupdf4llm",
        parser_version=version,
    )
