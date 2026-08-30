"""Ссылка кейс → паттерн обязана быть двусторонней.

Повод. Триаж 35 кейсов, не вошедших ни в один паттерн (2026-07-29), искал пропущенные
обобщения и не нашёл ни одного: все 11 предложенных кластеров были отклонены — где-то
участники оказались одним эпизодом, записанным дважды, где-то класс был уже покрыт.
Зато нашлось другое: **23 односторонние ссылки**. Кейс объявляет `confirms:` или
`specializes:` в сторону паттерна, а паттерн его в `source_cases` не перечисляет.

Почему это не косметика. Обход графа знаний идёт от паттерна вниз — «на чём это
основано». Кейс, который виден только со своей стороны, для такого обхода не существует:
паттерн выглядит основанным на трёх случаях, когда их девять. Это ровно `pattern-
measurement-validity` — счётчик, считающий не то, что заявлено.

Почему проверкой. Ссылки проставляются руками при записи знания, в двух разных файлах.
Расхождение накопилось за три месяца молча — ни один прогон его не видел.
"""

import re
from pathlib import Path

import pytest

LESSONS = Path.home() / ".claude" / "global-lessons"
EDGE_RE = re.compile(r"^\s*-\s*(confirms|specializes|extends|generalizes)\s*:\s*(\S+\.md)\s*$", re.M)


def _parents() -> dict[str, str]:
    if not LESSONS.is_dir():
        return {}
    out = {}
    for p in list(LESSONS.glob("pattern-*.md")) + list(LESSONS.glob("principle-*.md")):
        out[p.name] = p.read_text(errors="replace")
    return out


def _asymmetric() -> list[tuple[str, str, str]]:
    parents = _parents()
    bad = []
    for c in sorted(LESSONS.glob("case-*.md")):
        text = c.read_text(errors="replace")
        # Устаревший кейс не обязан быть в source_cases: он оставлен как отрицательный
        # пример, а не как основание паттерна.
        if "DEPRECATED" in text[:2000]:
            continue
        for kind, target in EDGE_RE.findall(text):
            target = target.split("/")[-1]
            if target in parents and c.name not in parents[target]:
                bad.append((c.name, kind, target))
    return bad


@pytest.mark.skipif(not LESSONS.is_dir(), reason="рабочая база знаний недоступна")
def test_case_to_pattern_links_are_bidirectional():
    """Если кейс ссылается на паттерн, паттерн обязан перечислять кейс."""
    bad = _asymmetric()
    assert not bad, "односторонние ссылки (кейс видит паттерн, паттерн кейса — нет):\n" + "\n".join(
        f"  {c} -{k}-> {t}" for c, k, t in bad
    )


@pytest.mark.skipif(not LESSONS.is_dir(), reason="рабочая база знаний недоступна")
def test_detector_can_fire():
    """Отрицательный контроль: проверка обязана уметь найти нарушение.

    Без него зелёный результат выше означал бы либо «нарушений нет», либо «regexp
    ничего не матчит» — а это разные вещи, и различить их снаружи нельзя.
    """
    parents = _parents()
    assert parents, "паттернов не найдено — проверке не с чем работать"

    sample = "- confirms: pattern-nonexistent-probe.md"
    assert EDGE_RE.findall(sample + "\n"), "регулярка не распознаёт форму ребра"

    # мишень существует, но кейс в ней не упомянут → нарушение должно детектироваться
    target = next(iter(parents))
    probe = f"---\nname: проба\n---\n- confirms: {target}\n"
    hits = [
        (kind, t.split("/")[-1])
        for kind, t in EDGE_RE.findall(probe)
        if t.split("/")[-1] in parents and "case-probe-not-in-base.md" not in parents[t.split("/")[-1]]
    ]
    assert hits, "заведомое нарушение не распознано — проверка ничего не измеряет"
