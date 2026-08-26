"""Markdown normalizer — block extraction + heading_path + page anchors.

See docs/ingestion-pipeline.md §4.3.

Input: raw markdown string (possibly with <!-- page: N --> anchors).
Output: (normalized_markdown, blocks) where blocks carry heading_path and page provenance.
"""

from __future__ import annotations

import re

from .parse import Block

_PAGE_ANCHOR = re.compile(r"<!--\s*page:\s*(\d+)\s*-->")
_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
_LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+\.)\s+(.+?)\s*$")
_TABLE_ROW = re.compile(r"^\s*\|.*\|\s*$")
_TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$")
_FENCE = re.compile(r"^\s*(```|~~~)(.*)$")
_QUOTE = re.compile(r"^\s*>\s?(.*)$")


def normalize(markdown: str, source_id: str) -> tuple[str, list[Block]]:
    text = markdown.replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")

    blocks: list[Block] = []
    heading_stack: list[tuple[int, str]] = []  # (level, title)
    current_page: int | None = None
    block_index = 0
    offset = 0

    def _hp() -> list[str]:
        return [title for _, title in heading_stack]

    def _new_id() -> str:
        nonlocal block_index
        bid = f"b{block_index:03d}"
        block_index += 1
        return bid

    def _add(block_type: str, content: str) -> None:
        content = content.strip()
        if not content:
            return
        prov: dict = {"heading_path": list(_hp()), "offset": offset}
        if current_page is not None:
            prov["page"] = current_page
        blocks.append(
            Block(
                block_id=_new_id(),
                source_id=source_id,
                block_type=block_type,
                text=content,
                provenance=prov,
            )
        )

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]

        m_page = _PAGE_ANCHOR.search(line)
        if m_page and line.strip() == m_page.group(0):
            current_page = int(m_page.group(1))
            offset += len(line) + 1
            i += 1
            continue

        m_fence = _FENCE.match(line)
        if m_fence:
            fence = m_fence.group(1)
            j = i + 1
            code_lines: list[str] = []
            while j < n and not lines[j].lstrip().startswith(fence):
                code_lines.append(lines[j])
                j += 1
            _add("code_block", "\n".join(code_lines))
            offset += sum(len(line_inner) + 1 for line_inner in lines[i : j + 1])
            i = j + 1
            continue

        m_h = _HEADING.match(line)
        if m_h:
            level = len(m_h.group(1))
            title = m_h.group(2).strip()
            while heading_stack and heading_stack[-1][0] >= level:
                heading_stack.pop()
            _add("heading", title)
            heading_stack.append((level, title))
            offset += len(line) + 1
            i += 1
            continue

        if _TABLE_ROW.match(line):
            j = i
            while j < n and _TABLE_ROW.match(lines[j]):
                if not _TABLE_SEP.match(lines[j]):
                    _add("table_row", lines[j].strip())
                offset += len(lines[j]) + 1
                j += 1
            i = j
            continue

        m_q = _QUOTE.match(line)
        if m_q:
            quote_lines: list[str] = [m_q.group(1)]
            j = i + 1
            while j < n:
                mq = _QUOTE.match(lines[j])
                if not mq:
                    break
                quote_lines.append(mq.group(1))
                j += 1
            _add("quote", "\n".join(quote_lines))
            offset += sum(len(lines[k]) + 1 for k in range(i, j))
            i = j
            continue

        m_li = _LIST_ITEM.match(line)
        if m_li:
            _add("list_item", m_li.group(1))
            offset += len(line) + 1
            i += 1
            continue

        if line.strip() == "":
            offset += 1
            i += 1
            continue

        para_lines: list[str] = [line]
        j = i + 1
        while j < n:
            nxt = lines[j]
            if nxt.strip() == "":
                break
            if _HEADING.match(nxt) or _LIST_ITEM.match(nxt) or _TABLE_ROW.match(nxt) or _FENCE.match(nxt) or _QUOTE.match(nxt):
                break
            if _PAGE_ANCHOR.search(nxt) and nxt.strip() == _PAGE_ANCHOR.search(nxt).group(0):
                break
            para_lines.append(nxt)
            j += 1
        _add("paragraph", " ".join(p.strip() for p in para_lines))
        offset += sum(len(lines[k]) + 1 for k in range(i, j))
        i = j

    return text, blocks
