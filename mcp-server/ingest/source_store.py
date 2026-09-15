"""Source storage at ~/.claude/sources/ — index.jsonl + per-source directories.

See docs/ingestion-pipeline.md §3.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

import yaml

# Общий замок (род H). Индекс подач пишут двое: сервер MCP (вызовы `/ingest` идут
# конкурентно в долгоживущем процессе) и командная строка — отдельный процесс. Ниже
# `update_index_entry` читает индекс ЦЕЛИКОМ и кладёт обратно ЦЕЛИКОМ, а рядом
# `append` дозаписывает: при наложении дозаписанная строка гибнет вместе с
# прочитанной ранее версией. Протокол один на оба языка — `hooks/lib/state_lock.py`
# и `hooks/state-lock-lib.sh`.
_LIB = Path(__file__).resolve().parents[2] / "hooks" / "lib"
if not (_LIB / "state_lock.py").exists():
    _LIB = Path.home() / ".claude/hooks/lib"
sys.path.insert(0, str(_LIB))
try:
    from state_lock import with_lock
except ImportError:  # библиотеки нет — работаем как прежде: замок улучшает, а не требуется
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):
        yield False


def _default_root() -> Path:
    env = os.environ.get("CLAUDE_SOURCES_ROOT")
    if env:
        return Path(env).expanduser()
    return Path.home() / ".claude" / "sources"


DEFAULT_ROOT = _default_root()


@dataclass
class SourceIndexEntry:
    id: str
    type: str                          # document | chat | screenshot | url | audio_transcript
    format: str                        # pdf | md | txt | docx | html | json
    original_path: str
    title: str
    ingested_at: str
    stages_completed: list[str] = field(default_factory=list)
    block_count: int | None = None
    entity_count: int | None = None
    fact_count: int | None = None
    relation_count: int | None = None


class SourceStore:
    """Read/write helpers for ~/.claude/sources/."""

    def __init__(self, root: Path | None = None):
        self.root = root if root is not None else _default_root()
        self.index_path = self.root / "index.jsonl"

    def ensure_root(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)

    def source_dir(self, source_id: str) -> Path:
        return self.root / source_id

    def append_index(self, entry: SourceIndexEntry) -> None:
        self.ensure_root()
        with self.index_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(asdict(entry), ensure_ascii=False) + "\n")

    def read_index(self) -> list[dict]:
        if not self.index_path.exists():
            return []
        return [json.loads(line) for line in self.index_path.read_text(encoding="utf-8").splitlines() if line.strip()]

    def update_index_entry(self, source_id: str, **fields) -> None:
        # Всё окно read→write под одним замком: чтение ВНУТРИ него, иначе правка ляжет
        # поверх версии, прочитанной до чужой записи, и та пропадёт.
        with with_lock(str(self.index_path)):
            entries = self.read_index()
            for e in entries:
                if e["id"] == source_id:
                    e.update(fields)
                    break
            self.index_path.write_text(
                "\n".join(json.dumps(e, ensure_ascii=False) for e in entries) + "\n",
                encoding="utf-8",
            )

    def write_meta(self, source_id: str, meta: dict) -> Path:
        d = self.source_dir(source_id)
        d.mkdir(parents=True, exist_ok=True)
        p = d / "meta.yaml"
        p.write_text(yaml.safe_dump(meta, allow_unicode=True, sort_keys=False), encoding="utf-8")
        return p

    def read_meta(self, source_id: str) -> dict:
        return yaml.safe_load((self.source_dir(source_id) / "meta.yaml").read_text(encoding="utf-8"))

    def write_markdown(self, source_id: str, markdown: str) -> Path:
        d = self.source_dir(source_id)
        d.mkdir(parents=True, exist_ok=True)
        p = d / "markdown.md"
        p.write_text(markdown, encoding="utf-8")
        return p

    def write_parsed(self, source_id: str, blocks: list[dict]) -> Path:
        d = self.source_dir(source_id)
        d.mkdir(parents=True, exist_ok=True)
        p = d / "parsed.jsonl"
        with p.open("w", encoding="utf-8") as f:
            for b in blocks:
                f.write(json.dumps(b, ensure_ascii=False) + "\n")
        return p
