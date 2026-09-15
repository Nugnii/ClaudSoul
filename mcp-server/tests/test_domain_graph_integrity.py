"""Целостность графа доменов (`domains/`) — CI-страж.

Узлы ссылаются друг на друга через рёбра parent/children/overlaps/applies_to/
analogous. Два класса разрыва ловим механически:
  1. ВИСЯЧАЯ ссылка — ребро указывает на имя без файла/алиаса (узел «есть» в
     графе, но недостижим как сущность);
  2. СИРОТА — не-корневой узел, на который никто не ссылается (недостижим
     обходом от корней).

Оба — следствие односторонне записанного двунаправленного ребра. Тест держит
граф связным после ручных правок.
"""

from __future__ import annotations

import re
from pathlib import Path

DOMAINS = Path(__file__).resolve().parents[2] / "domains"
EDGE_KEYS = ("parent", "children", "overlaps", "applies_to", "analogous")
ROOTS = {"science", "engineering", "humanities", "business", "health", "law", "arts"}


def _nodes():
    return [p for p in DOMAINS.glob("*.md") if p.stem != "_roots"]


def _list_field(text: str, key: str):
    m = re.search(rf"^{key}:\s*\[(.*?)\]", text, re.M)
    if not m:
        return []
    return [x.strip() for x in m.group(1).split(",") if x.strip()]


def _known_names():
    """Слаги файлов + алиасы — всё, на что валидно ссылаться."""
    known = set()
    for p in _nodes():
        known.add(p.stem)
        for a in _list_field(p.read_text(encoding="utf-8"), "aliases"):
            known.add(a)
    return known


def _referenced():
    ref = {}
    for p in _nodes():
        text = p.read_text(encoding="utf-8")
        for key in EDGE_KEYS:
            for name in _list_field(text, key):
                ref.setdefault(name, []).append(p.stem)
    return ref


def test_no_dangling_references():
    known = _known_names()
    dangling = {n: srcs for n, srcs in _referenced().items() if n not in known}
    assert not dangling, (
        "висячие узлы (ребро на несуществующий домен): "
        + "; ".join(f"{n}←{sorted(set(s))}" for n, s in sorted(dangling.items()))
    )


def test_no_non_root_orphans():
    ref = _referenced()
    known_aliases = _known_names()
    orphans = [
        p.stem
        for p in _nodes()
        if p.stem not in ROOTS and p.stem not in ref and p.stem not in known_aliases
    ]
    assert not orphans, f"сироты (не-корень, никто не ссылается, недостижим от корней): {sorted(orphans)}"


def _alias_to_stem():
    """Карта alias→stem (+ stem→stem) для резолва имён в рёбрах."""
    a2s = {}
    for p in _nodes():
        a2s[p.stem] = p.stem
        for a in _list_field(p.read_text(encoding="utf-8"), "aliases"):
            a2s[a] = p.stem
    return a2s


def _graph():
    """{stem: {edge_key: [resolved_stems]}} — рёбра с резолвом алиасов в слаги."""
    a2s = _alias_to_stem()
    g = {}
    for p in _nodes():
        text = p.read_text(encoding="utf-8")
        g[p.stem] = {k: [a2s.get(n, n) for n in _list_field(text, k)] for k in EDGE_KEYS}
    return g


def test_overlaps_and_analogous_symmetric():
    """overlaps/analogous — симметричные отношения: A↔B. Одностороннее ребро
    направленно искажает scoring в domain-graph-lib (раскрытие идёт по исходящим
    рёбрам), потому страж форсирует симметрию (его исходный failure-mode)."""
    g = _graph()
    asym = []
    for a, edges in g.items():
        for field in ("overlaps", "analogous"):
            for b in edges[field]:
                if b in g and a not in g[b][field]:
                    asym.append(f"{a}.{field}={b}, но {b}.{field} без {a}")
    assert not asym, "односторонние симметричные рёбра:\n  " + "\n  ".join(sorted(asym))


def test_parent_children_inverse_consistent():
    """parent/children — взаимно-обратные: A.parent=P ⟹ P.children∋A (и наоборот)."""
    g = _graph()
    bad = []
    for a, edges in g.items():
        for p in edges["parent"]:
            if p in g and a not in g[p]["children"]:
                bad.append(f"{a}.parent={p}, но {p}.children без {a}")
        for c in edges["children"]:
            if c in g and a not in g[c]["parent"]:
                bad.append(f"{a}.children={c}, но {c}.parent без {a}")
    assert not bad, "рассогласование parent/children:\n  " + "\n  ".join(sorted(bad))
