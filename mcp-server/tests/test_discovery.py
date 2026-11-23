"""Tests for Discovery Engine — co-occurrence, shared-attribute, contradictions."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ingest.discovery import detect_cross_contour_mentions, discover  # noqa: E402
from ingest.integrate import _parse_frontmatter, _write_file, integrate  # noqa: E402


def _doc_payload(source_id: str, entities, facts, relations=None):
    return {
        "source_id": source_id,
        "entities": entities,
        "facts": facts,
        "relations": relations or [],
    }


def _ent(name, entity_type="company", domain=None, attrs=None):
    return {
        "name": name,
        "entity_type": entity_type,
        "domain": domain or ["test"],
        "attributes": attrs or {},
    }


def _fact(desc, refs, source_id, fact_type="event"):
    return {
        "description": desc,
        "fact_type": fact_type,
        "sources": [{"id": f"{source_id}:p1", "type": "document"}],
        "entity_refs": refs,
    }


def test_co_occurrence_two_shared_sources(tmp_path):
    lessons = tmp_path / "lessons"
    for sid in ("doc-a", "doc-b"):
        integrate(
            _doc_payload(
                sid,
                [_ent("Alice", "person"), _ent("Bob", "person")],
                [
                    _fact(f"Alice событие {sid}", ["entity-alice.md"], sid),
                    _fact(f"Bob событие {sid}", ["entity-bob.md"], sid),
                ],
            ),
            lessons,
        )

    result = discover(lessons)
    assert len(result["co_occurrence"]) == 1
    rel_file = result["co_occurrence"][0]
    assert (lessons / rel_file).exists()


def test_co_occurrence_requires_two_sources(tmp_path):
    lessons = tmp_path / "lessons"
    integrate(
        _doc_payload(
            "doc-a",
            [_ent("Alice", "person"), _ent("Bob", "person")],
            [
                _fact("Alice событие", ["entity-alice.md"], "doc-a"),
                _fact("Bob событие", ["entity-bob.md"], "doc-a"),
            ],
        ),
        lessons,
    )
    result = discover(lessons)
    assert result["co_occurrence"] == []


def test_shared_attribute_employer(tmp_path):
    lessons = tmp_path / "lessons"
    integrate(
        _doc_payload(
            "doc-a",
            [
                _ent(
                    "Alice",
                    "person",
                    attrs={"employer": {"value": "Acme", "source_type": "document", "sources": ["doc-a:p1"]}},
                ),
                _ent(
                    "Bob",
                    "person",
                    attrs={"employer": {"value": "Acme", "source_type": "document", "sources": ["doc-a:p1"]}},
                ),
            ],
            [],
        ),
        lessons,
    )
    result = discover(lessons)
    assert len(result["shared_attr"]) == 1
    rel_file = result["shared_attr"][0]
    assert "works_with" in rel_file


def test_shared_attribute_different_values(tmp_path):
    lessons = tmp_path / "lessons"
    integrate(
        _doc_payload(
            "doc-a",
            [
                _ent(
                    "Alice",
                    "person",
                    attrs={"employer": {"value": "Acme", "source_type": "document", "sources": ["doc-a:p1"]}},
                ),
                _ent(
                    "Bob",
                    "person",
                    attrs={"employer": {"value": "Globex", "source_type": "document", "sources": ["doc-a:p1"]}},
                ),
            ],
            [],
        ),
        lessons,
    )
    result = discover(lessons)
    assert result["shared_attr"] == []


def test_discovery_does_not_duplicate_existing_relation(tmp_path):
    lessons = tmp_path / "lessons"
    for sid in ("doc-a", "doc-b"):
        integrate(
            _doc_payload(
                sid,
                [_ent("Alice", "person"), _ent("Bob", "person")],
                [
                    _fact(f"Alice {sid}", ["entity-alice.md"], sid),
                    _fact(f"Bob {sid}", ["entity-bob.md"], sid),
                ],
            ),
            lessons,
        )

    first = discover(lessons)
    assert len(first["co_occurrence"]) == 1
    second = discover(lessons)
    assert second["co_occurrence"] == []


def test_contradiction_same_entity_divergent_facts(tmp_path):
    lessons = tmp_path / "lessons"
    integrate(
        _doc_payload(
            "doc-a",
            [_ent("Acme", "company")],
            [
                _fact(
                    "Компания Acme была основана в 2010 году в Сан-Франциско.",
                    ["entity-acme.md"],
                    "doc-a",
                    fact_type="attribute",
                ),
                _fact(
                    "Компания Acme была основана в 2015 году в Нью-Йорке.",
                    ["entity-acme.md"],
                    "doc-a",
                    fact_type="attribute",
                ),
            ],
        ),
        lessons,
    )
    result = discover(lessons)
    assert len(result["contradictions"]) >= 1

    edges_found = False
    for p in lessons.glob("fact-*.md"):
        text = p.read_text(encoding="utf-8")
        if "contradicts" in text:
            edges_found = True
            break
    assert edges_found


def test_discover_empty_dir(tmp_path):
    result = discover(tmp_path / "does-not-exist")
    assert result == {
        "co_occurrence": [],
        "shared_attr": [],
        "contradictions": [],
        "cross_contour": [],
        "skipped_duplicates": 0,
    }


def _write_knowledge(lessons: Path, name: str, body: str) -> None:
    lessons.mkdir(parents=True, exist_ok=True)
    meta = {"name": name, "type": "case", "confidence": 1, "status": "active"}
    _write_file(lessons / name, meta, body)


def test_cross_contour_mention_detected(tmp_path, monkeypatch):
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(
        lessons,
        "case-2026-04-22-acme-deal.md",
        "В работе с клиентом Acme мы столкнулись с задержкой согласования. Acme отказался.",
    )
    result = discovery_mod.discover(lessons)
    assert any("entity-acme.md" in s for s in result["cross_contour"])
    assert log_path.exists()
    assert "entity-acme.md" in log_path.read_text(encoding="utf-8")


def test_cross_contour_no_match_when_no_mention(tmp_path, monkeypatch):
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(
        lessons,
        "case-2026-04-22-other.md",
        "Случай про что-то совершенно другое, без упоминаний компаний.",
    )
    result = discovery_mod.discover(lessons)
    assert result["cross_contour"] == []


def test_cross_contour_log_records_discovery_once(tmp_path, monkeypatch):
    """D1006: пара пишется в журнал один раз, а не на каждом прогоне."""
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(lessons, "case-2026-04-22-acme-deal.md", "Клиент Acme отказался.")
    discovery_mod.discover(lessons)
    discovery_mod.discover(lessons)
    lines = [ln for ln in log_path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    assert len(lines) == 1, lines


def test_cross_contour_log_compacts_legacy_duplicates(tmp_path, monkeypatch):
    """D1006: журнал с повторами прежней редакции становится снимком прогона — пара одной строкой
    со временем ПЕРВОГО открытия; пара, которую детектор больше не находит, и мусор уходят."""
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    first = {"ts": "2026-04-01T00:00:00+00:00", "knowledge_file": "case-2026-04-22-acme-deal.md",
             "entity_file": "entity-acme.md", "matched": "Acme"}
    other = {"ts": "2026-04-02T00:00:00+00:00", "knowledge_file": "pattern-old.md",
             "entity_file": "entity-old.md", "matched": "Old"}
    legacy = [first, other, dict(first, ts="2026-04-03T00:00:00+00:00"),
              dict(first, ts="2026-04-04T00:00:00+00:00")]
    log_path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in legacy)
                        + "not json\n", encoding="utf-8")

    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(lessons, "case-2026-04-22-acme-deal.md", "Клиент Acme отказался.")
    discovery_mod.discover(lessons)
    lines = log_path.read_text(encoding="utf-8").split("\n")
    assert lines == [json.dumps(first, ensure_ascii=False), ""], lines


def test_cross_contour_log_drops_pair_no_longer_found(tmp_path, monkeypatch):
    """D1006 (финальный скептик): упоминание убрали из знания — пара уходит из журнала, как уходила
    из окна прежнего читателя; новое упоминание приходит."""
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    integrate(_doc_payload("doc-a", [_ent("Acme", "company"), _ent("Betacorp", "company")], []), lessons)
    _write_knowledge(lessons, "case-2026-04-22-acme-deal.md", "Клиент Acme отказался.")
    discovery_mod.discover(lessons)
    assert "entity-acme.md" in log_path.read_text(encoding="utf-8")
    _write_knowledge(lessons, "case-2026-04-22-acme-deal.md", "Клиент Betacorp отказался.")
    discovery_mod.discover(lessons)
    text = log_path.read_text(encoding="utf-8")
    assert "entity-acme.md" not in text and "entity-betacorp.md" in text, text


def test_cross_contour_log_ignores_non_string_values(tmp_path, monkeypatch):
    """D1006 (финальный скептик): значение-список в прежнем журнале не роняет прогон детектора."""
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    log_path.write_text('{"knowledge_file": ["a"], "entity_file": {"k": 1}, "ts": 5}\n[1, 2]\n',
                        encoding="utf-8")
    discovery_mod._append_cross_contour_log([("case-a.md", "entity-x.md", "X")])
    recs = [json.loads(x) for x in log_path.read_text(encoding="utf-8").split("\n") if x]
    assert [(r["knowledge_file"], r["entity_file"]) for r in recs] == [("case-a.md", "entity-x.md")]


def test_cross_contour_log_splits_only_on_newline(tmp_path, monkeypatch):
    """D1006 (финальный скептик): U+2028 внутри строки не рвёт её — время первого открытия
    переносится, а журнал остаётся строкой на пару для читателей, делящих по \\n."""
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    token = "Acme Group"
    old = {"ts": "2026-01-01T00:00:00+00:00", "knowledge_file": "case-a.md",
           "entity_file": "entity-acme.md", "matched": token}
    log_path.write_text(json.dumps(old, ensure_ascii=False) + "\n", encoding="utf-8")
    discovery_mod._append_cross_contour_log([("case-a.md", "entity-acme.md", token)])
    parts = [x for x in log_path.read_text(encoding="utf-8").split("\n") if x]
    assert len(parts) == 1 and json.loads(parts[0])["ts"] == "2026-01-01T00:00:00+00:00", parts


def _reloaded_discovery(monkeypatch, log_path):
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)
    return discovery_mod


def test_cross_contour_empty_run_keeps_snapshot(tmp_path, monkeypatch):
    """D1006 (третий круг): пустой набор снимок не переписывает — пустой скан неотличим от сбоя чтения.
    Редакция «пустой набор — тоже снимок» стёрла живой журнал прогоном набора хуков. Названный предел:
    пропади все пары разом, последний снимок останется. Условие снятия: у скана появится признак
    «источник прочитан и пуст», отличимый от сбоя чтения."""
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    discovery_mod = _reloaded_discovery(monkeypatch, log_path)
    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(lessons, "case-2026-04-22-acme-deal.md", "Клиент Acme отказался.")
    discovery_mod.discover(lessons)
    before = log_path.read_text(encoding="utf-8")
    assert "entity-acme.md" in before
    (lessons / "entity-acme.md").unlink()
    discovery_mod.discover(lessons)
    assert log_path.read_text(encoding="utf-8") == before


def test_cross_contour_foreign_dir_leaves_journal(tmp_path, monkeypatch):
    """D1006 (третий круг): прогон по чужому каталогу без явного пути журнала журнал не пишет — живой
    журнал переписывали фикстуры тестов, потому что путь зависел от одного HOME."""
    import ingest.discovery as discovery_mod

    monkeypatch.delenv("CLAUDSOUL_CROSS_CONTOUR_LOG", raising=False)
    lessons = tmp_path / "lessons"
    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(lessons, "case-2026-04-22-acme-deal.md", "Клиент Acme отказался.")
    result = discovery_mod.discover(lessons)
    assert any("entity-acme.md" in s for s in result["cross_contour"])
    assert not discovery_mod.CROSS_CONTOUR_LOG_PATH.exists()


def test_cross_contour_writer_foreign_dir_leaves_journal(tmp_path, monkeypatch):
    """D1006 (третий круг): защита — у писателя, а не у discover(): дайджест зовёт писателя напрямую."""
    import ingest.discovery as discovery_mod

    monkeypatch.delenv("CLAUDSOUL_CROSS_CONTOUR_LOG", raising=False)
    discovery_mod._append_cross_contour_log([("case-a.md", "entity-x.md", "X")], tmp_path / "fixture")
    assert not discovery_mod.CROSS_CONTOUR_LOG_PATH.exists()


def test_cross_contour_default_base_writes_journal(tmp_path, monkeypatch):
    """D1006 (третий круг): прогон по базе по умолчанию (`~/.claude/global-lessons`) журнал пишет."""
    import ingest.discovery as discovery_mod

    monkeypatch.delenv("CLAUDSOUL_CROSS_CONTOUR_LOG", raising=False)
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    lessons = tmp_path / "home" / ".claude" / "global-lessons"
    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(lessons, "case-2026-04-22-acme-deal.md", "Клиент Acme отказался.")
    discovery_mod.discover(lessons)
    assert "entity-acme.md" in discovery_mod.CROSS_CONTOUR_LOG_PATH.read_text(encoding="utf-8")


def test_cross_contour_log_keeps_symlink_and_mode(tmp_path, monkeypatch):
    """D1006 (второй круг): журнал-ссылка остаётся ссылкой, права прежнего журнала сохраняются."""
    import stat

    lessons = tmp_path / "lessons"
    target = tmp_path / "real" / "cc.jsonl"
    target.parent.mkdir()
    target.write_text("", encoding="utf-8")
    target.chmod(0o640)
    log_path = tmp_path / "cross-contour.jsonl"
    log_path.symlink_to(target)
    discovery_mod = _reloaded_discovery(monkeypatch, log_path)
    integrate(_doc_payload("doc-a", [_ent("Acme", "company")], []), lessons)
    _write_knowledge(lessons, "case-2026-04-22-acme-deal.md", "Клиент Acme отказался.")
    discovery_mod.discover(lessons)
    assert log_path.is_symlink()
    assert "entity-acme.md" in target.read_text(encoding="utf-8")
    assert stat.S_IMODE(target.stat().st_mode) == 0o640


def test_cross_contour_new_log_gets_umask_mode(tmp_path, monkeypatch):
    """D1006 (второй круг): новый журнал — с правами по umask, как от open(), а не 0600 от mkstemp."""
    import os
    import stat

    log_path = tmp_path / "cross-contour.jsonl"
    discovery_mod = _reloaded_discovery(monkeypatch, log_path)
    discovery_mod._append_cross_contour_log([("case-a.md", "entity-x.md", "X")])
    um = os.umask(0)
    os.umask(um)
    assert stat.S_IMODE(log_path.stat().st_mode) == 0o666 & ~um


def test_cross_contour_log_isolated_from_live(tmp_path):
    """D1006 (второй круг): рамка conftest уводит журнал во временный каталог — тест без своей подмены
    не перепишет живой журнал."""
    import os

    import ingest.discovery as discovery_mod
    assert str(discovery_mod.CROSS_CONTOUR_LOG_PATH).startswith(str(tmp_path))
    assert os.environ["CLAUDSOUL_CROSS_CONTOUR_LOG"].startswith(str(tmp_path))


def test_cross_contour_alias_match(tmp_path, monkeypatch):
    lessons = tmp_path / "lessons"
    log_path = tmp_path / "cross-contour.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log_path))
    import importlib

    import ingest.discovery as discovery_mod
    importlib.reload(discovery_mod)

    payload = _doc_payload("doc-a", [_ent("Polska", "country")], [])
    payload["entities"][0]["aliases"] = ["Польша"]
    integrate(payload, lessons)
    _write_knowledge(
        lessons,
        "case-2026-04-22-poland.md",
        "Кейс по Polska: налоговый режим отличается. Также упомянем Польша.",
    )
    result = discovery_mod.discover(lessons)
    assert any("entity-polska.md" in s for s in result["cross_contour"])
