"""Markitdown backend — DOCX / HTML → Markdown.

Uses Microsoft's markitdown library. Wrapped with our normalizer.
"""

from __future__ import annotations

from pathlib import Path

from ..normalize import normalize
from ..parse import ParseResult


def read(path: Path, source_id: str, **opts) -> ParseResult:
    try:
        from markitdown import MarkItDown  # type: ignore
    except ImportError as e:
        raise RuntimeError(
            "markitdown is required for DOCX/HTML ingestion. "
            "Install with `uv add 'markitdown[docx,html]'`."
        ) from e

    md = MarkItDown()
    result = md.convert(str(path))
    markdown = result.text_content or ""

    normalized, blocks = normalize(markdown, source_id)

    warnings: list[str] = []
    if not markdown.strip():
        warnings.append("markitdown produced empty output")

    try:
        import markitdown as _mi
        version = getattr(_mi, "__version__", "unknown")
    except ImportError:
        version = "unknown"

    return ParseResult(
        markdown=normalized,
        blocks=blocks,
        warnings=warnings,
        parser="markitdown",
        parser_version=version,
    )
