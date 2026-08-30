"""Характеризующий тест: reindex не должен обнулять БД при пустом index_all().

Баг (P1, потеря данных): `_do_reindex()` зовёт `remove_stale(db, existing_paths)`.
Если `index_all()` вернул `[]` (транзиентно пустой global-lessons ИЛИ сбой загрузки
fastembed-модели), `existing_paths` пуст → `remove_stale` удаляет ВСЕ записи, теряя
весь индекс. Авто-путь защищён `_is_reindex_needed`, но `reindex_knowledge` tool и
viz `_reindex_after_mutation` зовут `_do_reindex` напрямую, минуя этот гард.

Инвариант (fail-safe): пустой набор при непустой БД — почти всегда транзиентный сбой,
а не легитимное удаление всех знаний. Не трогаем БД: устаревшие записи восстановимы
следующим непустым reindex; обнуление индекса — нет.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server  # noqa: E402
from storage import get_connection, init_db, upsert_knowledge, get_stats  # noqa: E402

DIM = 384


def _emb(pos: int) -> list[float]:
    v = [0.0] * DIM
    v[pos % DIM] = 1.0
    return v


def _fresh_db():
    db = get_connection(Path(":memory:"))
    init_db(db)
    return db


def _add(db, fp, pos):
    upsert_knowledge(
        db, file_path=fp, name=fp, type_="case", confidence=3, impact=3,
        status="active", domain="[test]", tags="", content=f"body {fp}",
        updated_at="2026-06-20", embedding=_emb(pos),
    )


def _entry(fp, pos):
    """Минимальный entry-dict как у index_all() — без обращения к fastembed."""
    return {
        "file_path": fp, "name": fp, "type_": "case", "confidence": 3,
        "impact": 3, "status": "active", "domain": "[test]", "tags": "",
        "content": f"body {fp}", "updated_at": "2026-06-20", "embedding": _emb(pos),
    }


def _paths(db) -> set[str]:
    return {r[0] for r in db.execute("SELECT file_path FROM knowledge").fetchall()}


def test_reindex_preserves_db_when_index_returns_empty(monkeypatch):
    """index_all()==[] при непустой БД → записи НЕ удаляются (инвариант защиты)."""
    db = _fresh_db()
    _add(db, "a.md", 0)
    _add(db, "b.md", 10)
    assert get_stats(db)["total"] == 2

    monkeypatch.setattr(server, "index_all", lambda *a, **k: [])
    asyncio.run(server._do_reindex(db))

    assert get_stats(db)["total"] == 2, "reindex обнулил базу при пустом index_all()"


def test_reindex_removes_stale_when_index_nonempty(monkeypatch):
    """index_all() непустой → отсутствующие пути удаляются (поведение сохранено)."""
    db = _fresh_db()
    _add(db, "a.md", 0)
    _add(db, "b.md", 10)

    # Новый набор содержит только a.md → b.md должен уйти как stale.
    monkeypatch.setattr(server, "index_all", lambda *a, **k: [_entry("a.md", 0)])
    asyncio.run(server._do_reindex(db))

    assert _paths(db) == {"a.md"}, "stale-запись не удалена при непустом index_all()"


def test_reindex_empty_index_empty_db_stays_empty(monkeypatch):
    """index_all()==[] при пустой БД → остаётся пусто (легитимный кейс, без падений)."""
    db = _fresh_db()
    monkeypatch.setattr(server, "index_all", lambda *a, **k: [])
    asyncio.run(server._do_reindex(db))
    assert get_stats(db)["total"] == 0
