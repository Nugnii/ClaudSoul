"""Мета-таблица key-value — основа детекции смены модели эмбеддингов.

`server._is_reindex_needed` сравнивает `meta['embed_model']` с текущей
`indexer.EMBED_MODEL`: расхождение → полный реиндекс (старые векторы
несравнимы с новой моделью). Здесь проверяем слой хранения этого признака.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from storage import get_connection, get_meta, init_db, set_meta  # noqa: E402


def _fresh_db(tmp_path):
    db = get_connection(tmp_path / "knowledge.db")
    init_db(db)
    return db


def test_fresh_db_has_no_model(tmp_path):
    # свежая БД → embed_model отсутствует → _is_reindex_needed обязан реиндексить
    db = _fresh_db(tmp_path)
    assert get_meta(db, "embed_model") is None


def test_default_returned_when_absent(tmp_path):
    db = _fresh_db(tmp_path)
    assert get_meta(db, "missing", "fallback") == "fallback"


def test_set_then_get(tmp_path):
    db = _fresh_db(tmp_path)
    set_meta(db, "embed_model", "model-A")
    assert get_meta(db, "embed_model") == "model-A"


def test_set_is_upsert_not_duplicate(tmp_path):
    db = _fresh_db(tmp_path)
    set_meta(db, "embed_model", "model-A")
    set_meta(db, "embed_model", "model-B")
    assert get_meta(db, "embed_model") == "model-B"
    count = db.execute("SELECT COUNT(*) FROM meta WHERE key = 'embed_model'").fetchone()[0]
    assert count == 1
