"""Целостность seed-базы знаний (`knowledge/`) — CI-безопасный инвариант.

`scripts/regen-seed.py` пересобирает seed из рабочей базы (нужен
`~/.claude/global-lessons`, в CI его нет). Этот тест проверяет то, что
проверяемо БЕЗ рабочей базы: каждый shipped принцип/паттерн прошёл через
генератор (счётчики сброшены к базовым) и паттерны действительно universal.
Ловит ручную правку seed в обход генератора и утечку личных знаний.

ВНИМАНИЕ — НЕ покрывает content-drift: зелёный этот тест НЕ означает «seed
актуален». Расхождение содержимого seed с выросшей рабочей базой ловит только
`regen-seed.py --check` (нужна рабочая база) — вшит неблокирующим warn в
`scripts/smoke-test.sh` (секция 5). Не путать зелёный страж с синхронностью seed.
"""

from __future__ import annotations

import re
from pathlib import Path

SEED = Path(__file__).resolve().parents[2] / "knowledge"
_FM = re.compile(r"^---\n(.*?)\n---\n", re.S)


def _frontmatter(path: Path) -> str:
    m = _FM.match(path.read_text(encoding="utf-8"))
    assert m, f"{path.name}: нет frontmatter-блока"
    return m.group(1)


def _field(fm: str, key: str):
    m = re.search(rf"^{key}:\s*(.+)$", fm, re.M)
    return m.group(1).strip() if m else None


def _shipped():
    return sorted(SEED.glob("principle-*.md")) + sorted(SEED.glob("pattern-*.md"))


def test_counters_reset_to_baseline():
    for path in _shipped():
        fm = _frontmatter(path)
        assert _field(fm, "confirmed_count") == "1", (
            f"{path.name}: confirmed_count не сброшен — запусти scripts/regen-seed.py"
        )
        assert _field(fm, "contradicted_count") == "0", (
            f"{path.name}: contradicted_count не 0"
        )
        # source_session несёт UUID сессии автора — в публикуемый seed он попасть не должен.
        ss = _field(fm, "source_session")
        assert ss in (None, '""', "''", ""), (
            f"{path.name}: source_session не вычищен — утечка session id в публичный seed"
        )


def test_shipped_patterns_are_universal():
    for path in sorted(SEED.glob("pattern-*.md")):
        fm = _frontmatter(path)
        assert _field(fm, "scope") == "universal", (
            f"{path.name}: не-universal паттерн в seed (личные не шипаются)"
        )


def test_no_personal_knowledge_in_seed():
    for prefix in ("case-", "entity-", "fact-", "relation-"):
        leaked = [p.name for p in SEED.glob(f"{prefix}*.md")]
        assert not leaked, f"личные знания просочились в seed: {leaked}"


def test_demand_fields_present():
    """Каждое shipped знание format-complete: demand-поля заполнены (drive
    приоритет инжекта). Forces backfill при добавлении нового universal-знания."""
    for path in _shipped():
        fm = _frontmatter(path)
        for field in ("need", "urgency", "availability"):
            assert _field(fm, field), (
                f"{path.name}: нет demand-поля '{field}' — заполни в рабочей базе и пересобери seed"
            )
