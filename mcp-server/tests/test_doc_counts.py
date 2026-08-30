"""Страж чисел документации против единого источника `scripts/count-stats.sh`.

Числа (хуки/скиллы/мосты/домены) правились вручную в README/CLAUDE/PLAN и
дрейфовали врозь. Единый источник истины — `count-stats.sh` (считает из
файловой системы). Этот тест держит канонные строки статистики равными
реальности в ОБОИХ человеко-фейсах (английский + русский README) и тест-файловые
числа в CLAUDE.md.

Покрытие расширено (Ф2 R2.2): раньше проверялся только английский README →
русский README.ru.md и CLAUDE.md дрейфовали ровно там, где стража не было
(`principle-single-source-of-truth` «от обратного»).

ЧИСЛА ФАЙЛОВ тестов (39 хук / 20 mcp) — проверяются (меняются редко, при добавлении
файла, и заявлены в доках точным числом). ЧИСЛА АССЕРТОВ (824, 104 mcp-теста) —
НЕ проверяются: меняются часто, описательны. PLAN.md синхронизируется вручную.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def _real_counts() -> dict:
    out = subprocess.run(
        ["bash", str(REPO / "scripts" / "count-stats.sh")],
        capture_output=True, text=True, check=True,
    ).stdout
    counts = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            counts[k.strip()] = int(v.strip())
    return counts


def test_readme_canonical_counts_match_reality():
    c = _real_counts()
    readme = (REPO / "README.md").read_text(encoding="utf-8")
    m = re.search(
        r"(\d+) active hooks, (\d+) skills, (\d+) inter-layer bridges, (\d+) domain nodes",
        readme,
    )
    assert m, "канонная строка статистики не найдена в README.md (формат: 'N active hooks, N skills, N inter-layer bridges, N domain nodes')"
    hooks, skills, bridges, domains = (int(x) for x in m.groups())
    mismatches = []
    for label, claimed, real in (
        ("hooks", hooks, c["hooks"]),
        ("skills", skills, c["skills"]),
        ("bridges", bridges, c["bridges"]),
        ("domains", domains, c["domains"]),
    ):
        if claimed != real:
            mismatches.append(f"{label}: README {claimed} != реально {real}")
    assert not mismatches, "дрейф чисел в README (запусти scripts/count-stats.sh):\n  " + "\n  ".join(mismatches)


def test_readme_ru_canonical_counts_match_reality():
    c = _real_counts()
    readme = (REPO / "README.ru.md").read_text(encoding="utf-8")
    m = re.search(
        r"(\d+) активны\w+ хук\w*, (\d+) скилл\w*, (\d+) межслойны\w+ мост\w*, (\d+) домен\w*",
        readme,
    )
    assert m, "канонная строка статистики не найдена в README.ru.md (формат: 'N активных хуков, N скилл..., N межслойных мостов, N доменов')"
    hooks, skills, bridges, domains = (int(x) for x in m.groups())
    mismatches = []
    for label, claimed, real in (
        ("hooks", hooks, c["hooks"]),
        ("skills", skills, c["skills"]),
        ("bridges", bridges, c["bridges"]),
        ("domains", domains, c["domains"]),
    ):
        if claimed != real:
            mismatches.append(f"{label}: README.ru {claimed} != реально {real}")
    assert not mismatches, "дрейф чисел в README.ru.md (запусти scripts/count-stats.sh):\n  " + "\n  ".join(mismatches)


def test_claude_md_test_file_counts_match_reality():
    """CLAUDE.md заявляет точные числа файлов тестов ('N файлов тестов хуков + N mcp')
    в нескольких местах — все должны совпадать с count-stats (числа файлов, не ассертов)."""
    c = _real_counts()
    claude = (REPO / "CLAUDE.md").read_text(encoding="utf-8")
    # Русские числительные требуют трёх форм: 51 файл, 52 файла, 55 файлов.
    # Регулярка знала только одну и упала на «51 файл» — то есть страж чисел
    # требовал грамматически неверный текст ради собственного удобства разбора.
    found = re.findall(r"(\d+) файл(?:а|ов)? тестов хуков \+ (\d+) mcp", claude)
    assert found, "не найдено ни одной строки 'N файлов тестов хуков + N mcp' в CLAUDE.md"
    mismatches = []
    for i, (hook_t, mcp_t) in enumerate(found):
        if int(hook_t) != c["hook_test_files"]:
            mismatches.append(f"hook_test_files (вхождение {i}): CLAUDE.md {hook_t} != реально {c['hook_test_files']}")
        if int(mcp_t) != c["mcp_test_files"]:
            mismatches.append(f"mcp_test_files (вхождение {i}): CLAUDE.md {mcp_t} != реально {c['mcp_test_files']}")
    assert not mismatches, "дрейф тест-чисел в CLAUDE.md (запусти scripts/count-stats.sh):\n  " + "\n  ".join(mismatches)


def test_claude_md_seed_counts_match_reality():
    """CLAUDE.md называет состав seed-базы ('N принципов + N universal-паттернов').

    Числа брались из головы: на 2026-08-22 в файле стояло «9 принципов + 14
    universal-паттернов», а `regen-seed.py` собирал 9 и 21. Расхождение росло молча —
    seed пересобирается скриптом, а строка в документе правится рукой, и сверять их
    было нечем. Тот же класс, что дрейф тест-чисел выше.
    """
    import re

    seed_dir = REPO / "knowledge"
    principles = len(list(seed_dir.glob("principle-*.md")))
    patterns = len(list(seed_dir.glob("pattern-*.md")))

    claude = (REPO / "CLAUDE.md").read_text(encoding="utf-8")
    found = re.findall(r"(\d+)\s+принцип\w*\s*\+\s*(\d+)\s+universal-паттерн\w*", claude)
    assert found, "не найдено строки 'N принципов + N universal-паттернов' в CLAUDE.md"

    mismatches = []
    for i, (p_doc, pat_doc) in enumerate(found):
        if int(p_doc) != principles:
            mismatches.append(f"принципы (вхождение {i}): CLAUDE.md {p_doc} != реально {principles}")
        if int(pat_doc) != patterns:
            mismatches.append(f"паттерны (вхождение {i}): CLAUDE.md {pat_doc} != реально {patterns}")
    assert not mismatches, (
        "дрейф состава seed в CLAUDE.md (пересчитай по knowledge/):\n  " + "\n  ".join(mismatches)
    )
