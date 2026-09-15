"""У вопроса «индекс отстал?» один владелец, и оба входа зовут его.

Повод (10 сентября 2026, D389). Условие свежести жило только в `server.py`, а второй
вход в тот же индекс — `cli_search.py` — его не знал: проверял лишь совпадение модели
эмбеддингов. Два хука (`knowledge-semantic-fallback-lib.sh`, `semantic-prefetch.sh`)
искали по устаревшему индексу. Замер того дня: 492 записи при 504 файлах базы, и все
десять знаний, записанных в тот день, были невидимы поиску, пока инструмент MCP не
тронули рукой. Корень R1 — условие написано на одном конце связи.

Ноги держат ОБЕ стороны различения: без T2 тест зеленел бы у функции, которая всегда
отвечает «отстал», без T3 — у той, что всегда молчит.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import indexer  # noqa: E402
from storage import get_connection, init_db, set_meta, upsert_knowledge  # noqa: E402

DIM = 384


def _db():
    db = get_connection(Path(":memory:"))
    init_db(db)
    return db


def _write(dirpath: Path, name: str, body: str = "тело") -> Path:
    f = dirpath / name
    f.write_text(f"---\nname: {name}\ntype: pattern\nconfidence: 3\n---\n{body}\n",
                 encoding="utf-8")
    return f


def test_owner_is_callable_and_shared(monkeypatch, tmp_path):
    """T1: владелец — публичная функция индексатора, и сервер зовёт именно её."""
    assert callable(indexer.is_reindex_needed)
    import server
    src = Path(server.__file__).read_text(encoding="utf-8")
    assert "from indexer import is_reindex_needed" in src, \
        "server перестал звать владельца — условие снова написано дважды"
    cli = (Path(server.__file__).parent / "cli_search.py").read_text(encoding="utf-8")
    assert "is_reindex_needed" in cli, \
        "второй вход не зовёт владельца — хуки снова ищут по устаревшему индексу (D389)"


def test_stale_index_is_detected(monkeypatch, tmp_path):
    """T2: файл на диске новее записи в БД → «отстал»."""
    monkeypatch.setattr(indexer, "KNOWLEDGE_DIR", tmp_path)
    db = _db()
    set_meta(db, "embed_model", indexer.EMBED_SIGNATURE)
    _write(tmp_path, "pattern-a.md")
    assert indexer.is_reindex_needed(db) is True


def test_fresh_index_is_quiet(monkeypatch, tmp_path):
    """T3: записи есть и они не старше файлов → молчит (положительный контроль)."""
    monkeypatch.setattr(indexer, "KNOWLEDGE_DIR", tmp_path)
    db = _db()
    set_meta(db, "embed_model", indexer.EMBED_SIGNATURE)
    f = _write(tmp_path, "pattern-a.md")
    time.sleep(0.01)
    # updated_at берётся ПОЗЖЕ mtime файла — иначе «свежесть» проверялась бы фикстурой,
    # собранной по памяти, а не формой из мира (сигнатура storage.upsert_knowledge).
    from datetime import datetime
    upsert_knowledge(db, file_path=str(f), name="pattern-a.md", type_="pattern",
                     confidence=3, impact=3, status="active", domain="[]", tags="[]",
                     content="тело",
                     updated_at=datetime.fromtimestamp(f.stat().st_mtime + 5).isoformat(),
                     embedding=[0.0] * DIM)
    assert indexer.is_reindex_needed(db) is False
