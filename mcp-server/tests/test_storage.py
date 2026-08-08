"""Характеризующий тест ядра storage (поиск/вставка/граф/дашборд).

Ядро поиска было без тестов (~0%). Фиксирует текущее поведение на in-memory БД
с фейковыми эмбеддингами, чтобы будущий рефактор не сломал его незаметно.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from storage import (  # noqa: E402
    dashboard_data,
    get_connection,
    graph_data,
    init_db,
    search,
    upsert_knowledge,
)

DIM = 384


def _emb(pos: int) -> list[float]:
    """Единичный вектор с 1.0 на позиции pos — для контролируемой близости."""
    v = [0.0] * DIM
    v[pos % DIM] = 1.0
    return v


def _fresh_db():
    db = get_connection(Path(":memory:"))
    init_db(db)
    return db


def _add(db, fp, pos, *, name=None, type_="case", confidence=3, impact=3):
    upsert_knowledge(
        db,
        file_path=fp,
        name=name or fp,
        type_=type_,
        confidence=confidence,
        impact=impact,
        status="active",
        domain="[test]",
        tags="",
        content=f"body of {fp}",
        updated_at="2026-06-20",
        embedding=_emb(pos),
    )


def test_search_returns_nearest_first():
    db = _fresh_db()
    _add(db, "a.md", 0)
    _add(db, "b.md", 10)
    _add(db, "c.md", 20)
    res = search(db, _emb(0), limit=3)
    assert res, "ожидались результаты"
    assert res[0]["file_path"] == "a.md"  # запрос совпал с эмбеддингом a


def test_type_filter():
    db = _fresh_db()
    _add(db, "case.md", 0, type_="case")
    _add(db, "pat.md", 1, type_="pattern")
    res = search(db, _emb(0), limit=5, type_filter="pattern")
    assert all(r["type"] == "pattern" for r in res)
    assert "case.md" not in [r["file_path"] for r in res]


def test_min_confidence_filter():
    db = _fresh_db()
    _add(db, "low.md", 0, confidence=1)
    _add(db, "high.md", 1, confidence=5)
    res = search(db, _emb(0), limit=5, min_confidence=3)
    assert all(r["confidence"] >= 3 for r in res)
    assert "low.md" not in [r["file_path"] for r in res]


def test_upsert_updates_not_duplicates():
    db = _fresh_db()
    _add(db, "x.md", 0, name="старое")
    _add(db, "x.md", 0, name="новое")
    cnt = db.execute("SELECT COUNT(*) FROM knowledge").fetchone()[0]
    assert cnt == 1
    res = search(db, _emb(0), limit=5)
    assert res[0]["name"] == "новое"


def test_content_truncated_in_results():
    db = _fresh_db()
    upsert_knowledge(
        db, file_path="big.md", name="big", type_="case", confidence=3, impact=3,
        status="active", domain="", tags="", content="x" * 2000,
        updated_at="2026-06-20", embedding=_emb(0),
    )
    res = search(db, _emb(0), limit=1)
    assert len(res[0]["content"]) <= 500


def test_graph_and_dashboard_do_not_crash_on_small_db():
    db = _fresh_db()
    _add(db, "a.md", 0)
    _add(db, "b.md", 1)
    g = graph_data(db)
    assert isinstance(g, dict)
    d = dashboard_data(db)
    assert isinstance(d, dict)


def test_graph_edges_never_point_outside_nodes(tmp_path):
    """Relation-файл не узел: ребро на него висячее и роняет отрисовку целиком.

    Связь при этом обязана уцелеть — её строит проход 2b напрямую.

    Второе утверждение не украшение. Первая версия этого теста проверяла только
    отсутствие висячих рёбер и оставалась ЗЕЛЁНОЙ, если graph_data выбросит вообще
    все рёбра (проверено мутантом `edges = []`): пустой список висячих не содержит.
    Фикс сделан глушителем — постфильтром на выходе, — поэтому проверять надо и то,
    что глушитель не заглушил лишнее. Файл связи кладётся на диск настоящим, чтобы
    проход 2b отработал и утверждение стало проверяемым, а не декларативным.
    """
    rel = tmp_path / "relation-a-created-b.md"
    rel.write_text(
        "---\ntype: relation\nrelation_type: created\n"
        "from_entity: entity-a.md\nto_entity: entity-b.md\n---\n",
        encoding="utf-8")
    db = _fresh_db()
    _add(db, "entity-a.md", 0, type_="entity")
    _add(db, "entity-b.md", 1, type_="entity")
    upsert_knowledge(
        db, file_path=str(rel), name="rel", type_="relation",
        confidence=3, impact=3, status="active", domain="", tags="",
        content="", updated_at="2026-06-20", embedding=_emb(5),
        edges_json=[{"type": "from:created", "target": "entity-a.md"},
                    {"type": "to:created", "target": "entity-b.md"}],
    )
    g = graph_data(db)
    ids = {n["name"]: n["id"] for n in g["nodes"]}
    node_ids = set(ids.values())
    dangling = [e for e in g["edges"]
                if e["source"] not in node_ids or e["target"] not in node_ids]
    assert not dangling, f"висячие рёбра: {dangling}"
    pairs = {frozenset((e["source"], e["target"])) for e in g["edges"]}
    assert frozenset((ids["entity-a.md"], ids["entity-b.md"])) in pairs, \
        f"фильтр срезал и саму связь: {g['edges']}"


def test_graph_and_dashboard_on_empty_db():
    db = _fresh_db()
    assert isinstance(graph_data(db), dict)
    assert isinstance(dashboard_data(db), dict)
