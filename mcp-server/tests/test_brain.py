"""Характеризующий тест merge-ядра brain (export/import базы знаний).

_merge_knowledge_file решает, перезаписать ли локальное знание импортируемым —
по confirmed_count. Ошибка здесь = тихая потеря/откат накопленных знаний.
Было без тестов. Здесь фиксируем точную логику added/updated/skipped + dry_run.
"""

from __future__ import annotations

import json
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import brain as brain_mod  # noqa: E402
from brain import _merge_knowledge_file, import_brain  # noqa: E402


def _write(path: Path, confirmed, body="тело"):
    if confirmed is None:
        fm = "---\nname: k\n---\n"
    else:
        fm = f"---\nname: k\nconfirmed_count: {confirmed}\n---\n"
    path.write_text(fm + body, encoding="utf-8")


def test_added_when_dst_missing(tmp_path):
    src = tmp_path / "src.md"
    _write(src, 5)
    dst = tmp_path / "dst.md"
    assert _merge_knowledge_file(src, dst, dry_run=False) == "added"
    assert dst.exists()


def test_added_dry_run_does_not_copy(tmp_path):
    src = tmp_path / "src.md"
    _write(src, 5)
    dst = tmp_path / "dst.md"
    assert _merge_knowledge_file(src, dst, dry_run=True) == "added"
    assert not dst.exists()


def test_updated_when_src_more_confirmed(tmp_path):
    src = tmp_path / "src.md"
    _write(src, 10, "новое")
    dst = tmp_path / "dst.md"
    _write(dst, 3, "старое")
    assert _merge_knowledge_file(src, dst, dry_run=False) == "updated"
    assert "новое" in dst.read_text()


def test_skipped_when_src_less_confirmed(tmp_path):
    src = tmp_path / "src.md"
    _write(src, 2)
    dst = tmp_path / "dst.md"
    _write(dst, 8, "сохранить локальное")
    assert _merge_knowledge_file(src, dst, dry_run=False) == "skipped"
    assert "сохранить локальное" in dst.read_text()


def test_skipped_when_equal(tmp_path):
    src = tmp_path / "src.md"
    _write(src, 5)
    dst = tmp_path / "dst.md"
    _write(dst, 5, "не трогать")
    assert _merge_knowledge_file(src, dst, dry_run=False) == "skipped"
    assert "не трогать" in dst.read_text()


def test_updated_dry_run_does_not_copy(tmp_path):
    src = tmp_path / "src.md"
    _write(src, 10, "новое")
    dst = tmp_path / "dst.md"
    _write(dst, 3, "старое")
    assert _merge_knowledge_file(src, dst, dry_run=True) == "updated"
    assert "старое" in dst.read_text()  # dry_run — не скопирован


def test_missing_confirmed_count_treated_as_zero(tmp_path):
    src = tmp_path / "src.md"
    _write(src, None, "без счётчика")  # нет confirmed_count → 0
    dst = tmp_path / "dst.md"
    _write(dst, 0, "локальное")
    # src 0, dst 0 → skipped
    assert _merge_knowledge_file(src, dst, dry_run=False) == "skipped"
    assert "локальное" in dst.read_text()


# --- import_brain end-to-end: dry_run-безопасность по всем ветвям мутации ---
# Merge-ядро покрыто выше; здесь — что dry_run НЕ мутирует commands/rules/knowledge
# (самый деструктивный путь: перезаписывает скиллы, CLAUDE.md, мерджит settings).

def _make_archive(tmp_path) -> Path:
    """Минимальный brain-архив: knowledge + skill + rules."""
    stage = tmp_path / "stage"
    (stage / "global-lessons").mkdir(parents=True)
    _write(stage / "global-lessons" / "imported.md", 9, "импортируемое знание")
    (stage / "commands" / "demoskill").mkdir(parents=True)
    (stage / "commands" / "demoskill" / "SKILL.md").write_text("imported skill", encoding="utf-8")
    (stage / "CLAUDE.md").write_text("# imported rules", encoding="utf-8")
    (stage / "manifest.json").write_text(json.dumps({"version": "test"}), encoding="utf-8")
    archive = tmp_path / "brain.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for item in stage.iterdir():
            tar.add(item, arcname=item.name)
    return archive


def _patch_home(monkeypatch, home: Path):
    """Перенаправить все модульные пути brain в изолированный temp-home."""
    for attr, sub in (
        ("KNOWLEDGE_DIR", "global-lessons"), ("COMMANDS_DIR", "commands"),
        ("HOOKS_DIR", "hooks"), ("TEMPLATES_DIR", "templates"),
        ("DOMAINS_DIR", "domains"), ("SETTINGS_FILE", "settings.json"),
        ("RULES_FILE", "CLAUDE.md"),
    ):
        monkeypatch.setattr(brain_mod, attr, home / sub)


def test_import_dry_run_mutates_no_content(tmp_path, monkeypatch):
    archive = _make_archive(tmp_path)
    home = tmp_path / "home"
    home.mkdir()
    _patch_home(monkeypatch, home)

    report = import_brain(archive, dry_run=True)

    # Отчёт считает что БЫЛО БЫ сделано...
    assert report["dry_run"] is True
    assert report["knowledge"]["added"] == 1
    assert report["commands"]["added"] == 1
    assert report["rules"] is True
    # ...но контент НЕ записан (dry_run создаёт пустые родительские каталоги
    # через mkdir, но ни одного файла/скилла/правил не пишет — текущее поведение).
    assert not (home / "global-lessons" / "imported.md").exists()
    assert not (home / "commands" / "demoskill").exists()
    assert not (home / "CLAUDE.md").exists()


def test_import_real_adds_files(tmp_path, monkeypatch):
    archive = _make_archive(tmp_path)
    home = tmp_path / "home"
    home.mkdir()
    _patch_home(monkeypatch, home)

    report = import_brain(archive, dry_run=False)

    assert (home / "global-lessons" / "imported.md").exists()
    assert (home / "commands" / "demoskill" / "SKILL.md").read_text() == "imported skill"
    assert (home / "CLAUDE.md").read_text() == "# imported rules"
    assert report["knowledge"]["added"] == 1
    assert report["db_reindex_needed"] is True
