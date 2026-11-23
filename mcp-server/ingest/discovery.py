"""Discovery Engine — find implicit relations between entities/facts.

Three detectors:
  1. co_occurrence  — entities mentioned in 2+ shared source_ids → `co_occurred_in` relation
  2. shared_attr    — entities with identical value for a link-worthy attribute → typed relation
                      (employer → works_with, studied_at → studied_together, etc.)
  3. contradiction  — two facts about same entity_refs with opposing values → `contradicts` relation

Discovered relations are marked with `discovered: true` in frontmatter and have lower
confidence than human-curated ones (co-occurrence 2, shared_attr 3).
"""

from __future__ import annotations

import json
import os
import re
import secrets
import shutil
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path

from .integrate import (
    SIMILAR_FACT_THRESHOLD,
    _load_by_type,
    _parse_frontmatter,
    _similarity,
    _slugify,
    _strip_entity_md,
    _write_file,
)

# ОБЩИЙ ЗАМОК (род H): журнал кросс-контурных открытий переписывается целиком, а пишут его двое —
# `/ingest` и еженедельный дайджест. Протокол общий с остальными писателями дерева
# (`hooks/lib/state_lock.py`), своей реализации нет намеренно — она стала бы носителем рода K.
_LOCK_LIB = Path(__file__).resolve().parents[2] / "hooks" / "lib"
if not (_LOCK_LIB / "state_lock.py").exists():
    _LOCK_LIB = Path.home() / ".claude" / "hooks" / "lib"
if str(_LOCK_LIB) not in sys.path:
    sys.path.insert(0, str(_LOCK_LIB))
try:
    from state_lock import with_lock  # type: ignore
except ImportError:  # pragma: no cover — библиотека рядом с сервером всегда есть
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):  # type: ignore
        yield False

CROSS_CONTOUR_KNOWLEDGE_PREFIXES = ("case-", "pattern-", "principle-")
CROSS_CONTOUR_LOG_PATH = Path(
    os.environ.get(
        "CLAUDSOUL_CROSS_CONTOUR_LOG",
        str(Path.home() / ".claude" / "hooks" / "state" / "cross-contour-discoveries.jsonl"),
    )
)

SHARED_ATTR_TO_RELATION = {
    "employer": ("works_with", "both_work_at"),
    "school": ("studied_together", "alma_mater"),
    "university": ("studied_together", "alma_mater"),
    "birthplace": ("from_same_place", "birthplace"),
    "city": ("from_same_place", "city"),
    "country": ("from_same_place", "country"),
    "company": ("works_with", "both_work_at"),
    "bank": ("shares_provider", "bank"),
    "jurisdiction": ("from_same_place", "jurisdiction"),
}

CO_OCCURRENCE_MIN_SHARED_SOURCES = 2
CO_OCCURRENCE_CONFIDENCE = 2
SHARED_ATTR_CONFIDENCE = 3


@dataclass
class DiscoverySummary:
    co_occurrence: list[str] = field(default_factory=list)
    shared_attr: list[str] = field(default_factory=list)
    contradictions: list[str] = field(default_factory=list)
    cross_contour: list[str] = field(default_factory=list)
    skipped_duplicates: int = 0

    def as_dict(self) -> dict:
        return {
            "co_occurrence": self.co_occurrence,
            "shared_attr": self.shared_attr,
            "contradictions": self.contradictions,
            "cross_contour": self.cross_contour,
            "skipped_duplicates": self.skipped_duplicates,
        }


def _extract_source_ids(fm: dict) -> set[str]:
    """Pull source_ids (doc-id part before ':') from a frontmatter dict."""
    ids: set[str] = set()
    for attr in (fm.get("attributes") or {}).values():
        if isinstance(attr, dict):
            for s in attr.get("sources") or []:
                if isinstance(s, str):
                    ids.add(s.split(":", 1)[0])
    for s in fm.get("sources") or []:
        sid = s.get("id") if isinstance(s, dict) else s
        if isinstance(sid, str):
            ids.add(sid.split(":", 1)[0])
    return ids


def _entity_source_ids(ent_fm: dict, all_facts: list[dict]) -> set[str]:
    """Collect source_ids from entity's own attributes + facts referencing it."""
    ids = _extract_source_ids(ent_fm)
    fname = ent_fm["_path"].name
    for f in all_facts:
        if fname in (f.get("entity_refs") or []):
            ids |= _extract_source_ids(f)
    return ids


def _relation_key(from_entity: str, to_entity: str, relation_type: str) -> tuple[str, str, str]:
    a, b = sorted([from_entity, to_entity])
    return (a, b, relation_type)


def _build_existing_relation_keys(relations: list[dict]) -> set[tuple[str, str, str]]:
    keys: set[tuple[str, str, str]] = set()
    for r in relations:
        fe = r.get("from_entity")
        te = r.get("to_entity")
        rt = r.get("relation_type")
        if fe and te and rt:
            keys.add(_relation_key(fe, te, rt))
    return keys


def _write_discovered_relation(
    lessons_dir: Path,
    from_entity: str,
    to_entity: str,
    relation_type: str,
    confidence: int,
    description: str,
    evidence: list[str],
    idx: int,
) -> Path:
    slug_base = f"{_slugify(_strip_entity_md(from_entity))}-{relation_type}-{_slugify(_strip_entity_md(to_entity))}"
    path = lessons_dir / f"relation-{slug_base}.md"
    if path.exists():
        path = lessons_dir / f"relation-{slug_base}-discovered-{idx:04d}.md"
    today = date.today().isoformat()
    meta = {
        "name": f"{from_entity} → {relation_type} → {to_entity}",
        "description": description,
        "type": "relation",
        "relation_type": relation_type,
        "status": "active",
        "confidence": confidence,
        "discovered": True,
        "sources": [{"id": ev, "type": "cross_reference"} for ev in evidence],
        "from_entity": from_entity,
        "to_entity": to_entity,
        "direction": "undirected",
        "valid_from": "",
        "valid_until": None,
        "temporal_note": "",
        "domain": [],
        "tags": ["auto-discovered"],
        "edges": [],
        "created": today,
        "last_updated": today,
    }
    _write_file(path, meta, "")
    return path


def _attr_scalar_value(attr) -> str | None:
    if isinstance(attr, dict):
        v = attr.get("value")
        if isinstance(v, (str, int, float)):
            return str(v).strip().lower() or None
    elif isinstance(attr, (str, int, float)):
        return str(attr).strip().lower() or None
    return None


def detect_co_occurrence(
    entities: list[dict],
    facts: list[dict],
    existing_keys: set[tuple[str, str, str]],
) -> list[tuple[str, str, list[str]]]:
    """Return list of (entity_a_file, entity_b_file, shared_source_ids)."""
    source_to_entities: dict[str, list[str]] = defaultdict(list)
    ent_sources: dict[str, set[str]] = {}
    for ent in entities:
        sids = _entity_source_ids(ent, facts)
        ent_sources[ent["_path"].name] = sids
        for sid in sids:
            source_to_entities[sid].append(ent["_path"].name)

    pair_evidence: dict[tuple[str, str], set[str]] = defaultdict(set)
    for sid, ent_files in source_to_entities.items():
        if len(ent_files) < 2:
            continue
        uniq = sorted(set(ent_files))
        for i in range(len(uniq)):
            for j in range(i + 1, len(uniq)):
                pair_evidence[(uniq[i], uniq[j])].add(sid)

    results = []
    for (a, b), sids in pair_evidence.items():
        if len(sids) < CO_OCCURRENCE_MIN_SHARED_SOURCES:
            continue
        if _relation_key(a, b, "co_occurred_in") in existing_keys:
            continue
        results.append((a, b, sorted(sids)))
    return results


def detect_shared_attribute(
    entities: list[dict],
    existing_keys: set[tuple[str, str, str]],
) -> list[tuple[str, str, str, str, str]]:
    """Return list of (entity_a, entity_b, relation_type, attr_key, shared_value)."""
    by_attr_value: dict[tuple[str, str], list[str]] = defaultdict(list)
    for ent in entities:
        attrs = ent.get("attributes") or {}
        for key, val in attrs.items():
            if key not in SHARED_ATTR_TO_RELATION:
                continue
            scalar = _attr_scalar_value(val)
            if not scalar:
                continue
            by_attr_value[(key, scalar)].append(ent["_path"].name)

    results = []
    for (key, value), names in by_attr_value.items():
        if len(names) < 2:
            continue
        rel_type, _ = SHARED_ATTR_TO_RELATION[key]
        uniq = sorted(set(names))
        for i in range(len(uniq)):
            for j in range(i + 1, len(uniq)):
                a, b = uniq[i], uniq[j]
                if _relation_key(a, b, rel_type) in existing_keys:
                    continue
                results.append((a, b, rel_type, key, value))
    return results


def detect_contradictions(facts: list[dict]) -> list[tuple[dict, dict]]:
    """Find pairs of facts that share entity_refs but have near-opposite descriptions.

    Heuristic: same entity_refs overlap, fact_type='attribute' or 'event', and description
    differs but contains shared noun-like tokens. We keep it conservative — only flag when
    two facts describe the same entity with different scalar values (e.g. birth years).
    """
    results = []
    grouped: dict[frozenset, list[dict]] = defaultdict(list)
    for f in facts:
        refs = frozenset(f.get("entity_refs") or [])
        if not refs:
            continue
        grouped[refs].append(f)

    for refs, group in grouped.items():
        if len(group) < 2:
            continue
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                a, b = group[i], group[j]
                if a.get("fact_type") != b.get("fact_type"):
                    continue
                sim = _similarity(a.get("description", ""), b.get("description", ""))
                if 0.4 <= sim < SIMILAR_FACT_THRESHOLD:
                    results.append((a, b))
    return results


def _write_contradiction_edge(lessons_dir: Path, fact_a: dict, fact_b: dict) -> None:
    for src, other in ((fact_a, fact_b), (fact_b, fact_a)):
        edges = list(src.get("edges") or [])
        edge = {"type": "contradicts", "target": other["_path"].name}
        if edge not in edges:
            edges.append(edge)
        src["edges"] = edges
        src["last_updated"] = date.today().isoformat()
        _write_file(src["_path"], src, src.get("_body", ""))


def _load_knowledge_files(lessons_dir: Path) -> list[dict]:
    """Load case/pattern/principle frontmatter+body for cross-contour scanning."""
    items: list[dict] = []
    for prefix in CROSS_CONTOUR_KNOWLEDGE_PREFIXES:
        for p in lessons_dir.glob(f"{prefix}*.md"):
            fm = _parse_frontmatter(p)
            if fm:
                items.append(fm)
    return items


def detect_cross_contour_mentions(
    knowledge_files: list[dict],
    entities: list[dict],
) -> list[tuple[str, str, str]]:
    """H10 measurement: find entity name mentions inside knowledge bodies.

    Returns list of (knowledge_file_name, entity_file_name, matched_token).
    Match is case-insensitive whole-word against entity `name` and `aliases`.
    Read-only: does NOT mutate knowledge files. Used for counter only.
    """
    name_index: list[tuple[str, str]] = []
    for ent in entities:
        ent_file = ent["_path"].name
        names = [ent.get("name") or ""]
        names.extend(ent.get("aliases") or [])
        for n in names:
            n = (n or "").strip()
            if len(n) >= 3:
                name_index.append((n, ent_file))

    found: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    for kf in knowledge_files:
        body = kf.get("_body") or ""
        if not body:
            continue
        for token, ent_file in name_index:
            pattern = r"(?<![\w])" + re.escape(token) + r"(?![\w])"
            if re.search(pattern, body, flags=re.IGNORECASE):
                key = (kf["_path"].name, ent_file)
                if key in seen:
                    continue
                seen.add(key)
                found.append((kf["_path"].name, ent_file, token))
    return found


def _append_cross_contour_log(events: list[tuple[str, str, str]], lessons_dir: Path | None = None) -> None:
    """Write the current run's discoveries as the JSONL log snapshot. Best-effort; failures are silent.

    Журнал — СНИМОК последнего прогона (D1006, 19-20 октября 2026): пары (знание, сущность),
    которые детектор находит сейчас, с временем ПЕРВОГО открытия пары (переносится из прежнего
    журнала) и словом нынешнего совпадения. Читатели (`cc_consume`, `cli_cross_contour_rank.py`)
    показывают то, что находится сейчас: пара, упоминание которой убрали из знания, уходит.
    Прежде каждый прогон дописывал весь набор целиком (7,9 МБ при 144 уникальных парах), и
    читатель активатора держался на этом окном «последние 200 строк» — хвост и был последним
    прогоном. Первая редакция починки писала пару один раз и потеряла признак «пара всё ещё
    находится» — нашёл финальный скептик; снимок сохраняет этот признак без повторов.
    Перезапись — под общим замком `<путь>.lock`, через уникальный временный файл и os.replace:
    читатель видит прежний снимок или новый, но не половину. Строки делятся только по `\\n`:
    `splitlines` режет и по U+2028/U+0085, которые json.dumps(ensure_ascii=False) пишет как есть.
    Строки прежнего журнала, не являющиеся парой, в снимок не переходят.
    Пустой набор снимок НЕ переписывает: пустой скан неотличим от сбоя чтения, а редакция «пустой
    набор — тоже снимок» за час стёрла живой журнал прогоном набора хуков (третий круг финального
    скептика, 20 октября 2026). Чей это журнал, решает `_journal_is_ours` по каталогу, который назвал
    зовущий (`lessons_dir`); не назван — пишется, как прежде: так зовёт установленный дайджест до переноса.
    Журнал-ссылка остаётся ссылкой — переписывается её цель; права прежнего журнала сохраняются.
    Названные пределы: скан идёт вне замка, и два прогона внахлёст оставят снимок писавшего
    последним — до следующего прогона, а разница между их сканами не больше длины скана; пара,
    выпавшая хотя бы из одного прогона, вернётся с новым временем (машинных читателей у времени
    нет); пропади все пары разом (единственная сущность удалена) — последний снимок останется.
    """
    if not events:
        return
    if lessons_dir is not None and not _journal_is_ours(lessons_dir):
        return
    path = Path(os.path.realpath(CROSS_CONTOUR_LOG_PATH))
    tmp_name = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with with_lock(str(path)):
            first_ts: dict[tuple[str, str], str] = {}
            if path.exists():
                for line in path.read_text(encoding="utf-8", errors="replace").split("\n"):
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(rec, dict):
                        continue
                    kf, ef, ts0 = rec.get("knowledge_file"), rec.get("entity_file"), rec.get("ts")
                    if isinstance(kf, str) and isinstance(ef, str) and isinstance(ts0, str):
                        first_ts.setdefault((kf, ef), ts0)
            now = datetime.now(timezone.utc).isoformat(timespec="seconds")
            seen: set[tuple[str, str]] = set()
            lines = []
            for kf_name, ent_name, token in events:
                key = (kf_name, ent_name)
                if key in seen:
                    continue
                seen.add(key)
                lines.append(json.dumps({
                    "ts": first_ts.get(key, now),
                    "knowledge_file": kf_name,
                    "entity_file": ent_name,
                    "matched": token,
                }, ensure_ascii=False))
            # Свой временный файл через open("x"), а не mkstemp: тот создаёт 0600, и журнал после
            # первой перезаписи менял права. Новый журнал получает права по umask, как от open().
            tmp = path.with_name(f"{path.name}.{os.getpid()}.{secrets.token_hex(4)}.tmp")
            with open(tmp, "x", encoding="utf-8") as f:
                tmp_name = str(tmp)
                f.write("".join(x + "\n" for x in lines))
            if path.exists():
                shutil.copymode(path, tmp_name)
            os.replace(tmp_name, path)
            tmp_name = None
    except OSError:
        pass
    finally:
        if tmp_name:
            try:
                os.unlink(tmp_name)
            except OSError:
                pass


def _journal_is_ours(lessons_dir: Path) -> bool:
    """Журнал открытий — снимок базы знаний по умолчанию (`~/.claude/global-lessons`).

    Прогон по другому каталогу (фикстура теста, чужая база) пишет журнал, только если путь задан
    явно (`CLAUDSOUL_CROSS_CONTOUR_LOG`). Путь журнала зависел от одного HOME, и 20 октября 2026
    прогон набора хуков переписал живой журнал снимком фикстуры: чью базу сканировали, писатель
    не знал (третий круг финального скептика D1006). Спрашивает писатель, а не `discover()`:
    дайджест (`hooks/knowledge-audit-digest.sh`) зовёт писателя напрямую.
    """
    if os.environ.get("CLAUDSOUL_CROSS_CONTOUR_LOG"):
        return True
    return os.path.realpath(lessons_dir) == os.path.realpath(Path.home() / ".claude" / "global-lessons")


def discover(lessons_dir: Path) -> dict:
    """Run all detectors on lessons_dir. Returns DiscoverySummary.as_dict()."""
    if not lessons_dir.exists():
        return DiscoverySummary().as_dict()

    entities = _load_by_type(lessons_dir, "entity")
    facts = _load_by_type(lessons_dir, "fact")
    relations = _load_by_type(lessons_dir, "relation")
    existing_keys = _build_existing_relation_keys(relations)

    summary = DiscoverySummary()

    knowledge_files = _load_knowledge_files(lessons_dir)
    cross_contour_events = detect_cross_contour_mentions(knowledge_files, entities)
    for kf_name, ent_name, _token in cross_contour_events:
        summary.cross_contour.append(f"{kf_name} -> {ent_name}")
    _append_cross_contour_log(cross_contour_events, lessons_dir)

    for idx, (a, b, sids) in enumerate(detect_co_occurrence(entities, facts, existing_keys)):
        path = _write_discovered_relation(
            lessons_dir,
            from_entity=a,
            to_entity=b,
            relation_type="co_occurred_in",
            confidence=CO_OCCURRENCE_CONFIDENCE,
            description=f"Обе сущности упоминаются в {len(sids)} общих источниках.",
            evidence=sids,
            idx=idx,
        )
        summary.co_occurrence.append(path.name)
        existing_keys.add(_relation_key(a, b, "co_occurred_in"))

    for idx, (a, b, rel_type, attr_key, value) in enumerate(
        detect_shared_attribute(entities, existing_keys)
    ):
        path = _write_discovered_relation(
            lessons_dir,
            from_entity=a,
            to_entity=b,
            relation_type=rel_type,
            confidence=SHARED_ATTR_CONFIDENCE,
            description=f"Общий атрибут {attr_key}={value!r}.",
            evidence=[f"shared-attr:{attr_key}={value}"],
            idx=idx,
        )
        summary.shared_attr.append(path.name)
        existing_keys.add(_relation_key(a, b, rel_type))

    for fact_a, fact_b in detect_contradictions(facts):
        _write_contradiction_edge(lessons_dir, fact_a, fact_b)
        summary.contradictions.append(
            f"{fact_a['_path'].name} <-> {fact_b['_path'].name}"
        )

    return summary.as_dict()
