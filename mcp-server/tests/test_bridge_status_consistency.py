"""Согласованность статусов мостов: поле `status` в файлах ↔ Статистика в `_index.md`.

Статус моста живёт в двух местах (frontmatter каждого моста + сводка в
`_index.md`) — классический «статус в N местах», который уже дрейфовал (L2↔L2
был реализован, но индекс числил его designed/consumer). Тест держит сводку в
индексе равной фактическим статусам файлов и ловит опечатки в статусе.
"""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

BRIDGES = Path(__file__).resolve().parents[2] / "bridges"
VOCAB = {"designed", "implemented", "implicit", "formalized"}
# статус файла → подпись категории в секции «Статистика» _index.md
CATEGORY = {
    "implemented": "Реализовано",
    "formalized": "Формализован",
    "implicit": "Неявно работают",
    "designed": "Спроектировано",
}


def _bridge_files():
    return sorted(BRIDGES.glob("L*.md"))


def _status(path: Path):
    m = re.search(r"^status:\s*(\S+)", path.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else None


def test_statuses_in_vocabulary():
    for p in _bridge_files():
        st = _status(p)
        assert st in VOCAB, f"{p.name}: статус '{st}' вне словаря {sorted(VOCAB)}"


def test_index_stats_match_files():
    counts = Counter(_status(p) for p in _bridge_files())
    index = (BRIDGES / "_index.md").read_text(encoding="utf-8")

    m_total = re.search(r"Всего мостов:\s*\*\*(\d+)\*\*", index)
    assert m_total and int(m_total.group(1)) == len(_bridge_files()), (
        f"_index.md «Всего мостов» != числу файлов ({len(_bridge_files())})"
    )

    for status, label in CATEGORY.items():
        m = re.search(rf"{label}:\s*\*\*(\d+)\*\*", index)
        stated = int(m.group(1)) if m else 0
        actual = counts.get(status, 0)
        assert stated == actual, (
            f"_index.md «{label}: {stated}» != фактических {status}={actual} "
            f"(обнови сводку в _index.md)"
        )
