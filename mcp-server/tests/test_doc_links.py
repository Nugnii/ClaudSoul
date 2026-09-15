"""Страж внутренних ссылок в документации репозитория.

Markdown-ссылки на файлы внутри репозитория должны разрешаться. Внешнее
намеренно исключено: `~/.claude/...` (каноническая база знаний — репозиторий
ставится В ~/.claude), http(s), mailto/tel, абсолютные пути и якоря.
Проверяются только относительные ссылки на файлы с известным расширением —
ловит ошибки относительного пути (как `hooks/x.sh` из `docs/` вместо `../hooks/`).

Append-only логи (CHANGELOG*, SESSION*) ИСКЛЮЧЕНЫ: они фиксируют состояние на
момент записи и закономерно ссылаются на файлы, которые позже удаляются/
переименовываются (историческая правда записи ≠ текущая навигация). Иначе любое
удаление файла ломало бы исторические ссылки и требовало правки датированных записей.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
KNOWN_EXT = (".md", ".sh", ".py", ".json", ".txt", ".yml", ".yaml", ".js", ".html", ".css")
SKIP_DIRS = {".git", "node_modules", ".venv", "site-packages", "__pycache__"}
# Append-only историч. логи — ссылки точечны во времени, не текущая навигация.
SKIP_FILE_PREFIXES = ("CHANGELOG", "SESSION")


def _md_files():
    return [
        p for p in REPO.rglob("*.md")
        if not any(part in SKIP_DIRS for part in p.parts)
        and not p.name.startswith(SKIP_FILE_PREFIXES)
    ]


def _should_check(target: str) -> bool:
    if target.startswith(("http://", "https://", "#", "mailto:", "tel:", "<", "$", "/", "~")):
        return False
    if ".claude" in target:  # внешняя база знаний в домашней директории — by design
        return False
    path = target.split("#")[0].split("?")[0].strip()
    return bool(path) and path.lower().endswith(KNOWN_EXT)


def test_no_broken_internal_doc_links():
    broken = []
    for md in _md_files():
        try:
            text = md.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for m in LINK.finditer(text):
            target = m.group(1).strip()
            if not _should_check(target):
                continue
            path = target.split("#")[0].split("?")[0].strip()
            if not (md.parent / path).resolve().exists():
                broken.append(f"{md.relative_to(REPO)} → {target}")
    assert not broken, "битые внутренние ссылки:\n  " + "\n  ".join(sorted(broken))
