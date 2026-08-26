# Ingestion Pipeline — v1.1.1 implementation spec

> Имплементация Stage 1 (Parse) и Stage 3 (Integrate) из `docs/entity-knowledge.md`.
> Stage 2 (Extract) — реализуется как Claude-in-session через скилл `/ingest` (v1.1.2).
> Stage 4 (Discover) — отдельная версия v1.1.4.

## 1. Обзор v1.1.1

```
📥 SOURCE          📋 PARSE                  🔍 EXTRACT (v1.1.2)     🧬 INTEGRATE
─────────          ──────────                ──────────              ──────────
MD/TXT/PDF   →     parse.py → parsed.jsonl →  /ingest skill (LLM)  → integrate.py
                   (unified Markdown)         JSON per schema        → global-lessons/
```

В этой версии реализуются **Parse** и **Integrate**. Между ними — JSON Schema (контракт, куда пишет Extract). Extract сам живёт в скилле `/ingest`.

## 2. Unified Markdown — промежуточный формат

Ключевое архитектурное решение: все источники приводятся к **Markdown** до извлечения.

Почему:
- Один формат для downstream обработки (Extract работает с MD, не со смесью форматов)
- Структура сохраняется (headings = boundaries сущностей, lists = атрибуты, tables = факты-таблицы)
- Человекочитаемо: parsed.jsonl можно глазами проверить
- Гомогенная трубопроводная логика: DOCX/HTML/чаты позже → MD → тот же pipeline

Провенанс (file, page, line/block) — через HTML-комментарии или frontmatter, сохраняется до Extract.

## 3. Source storage

```
~/.claude/sources/
├── index.jsonl              # Индекс всех загруженных источников
└── <source-id>/
    ├── meta.yaml            # Метаданные источника
    ├── original.<ext>       # Копия оригинала (опционально)
    ├── markdown.md          # Нормализованный MD
    └── parsed.jsonl         # Блоки с провенансом (для Extract)
```

### index.jsonl schema

Одна строка — один источник:

```json
{
  "id": "techflow-company-desc-2026-04-20",
  "type": "document",
  "format": "pdf",
  "original_path": "/path/to/input.pdf",
  "title": "TechFlow Company Description",
  "ingested_at": "2026-04-20T21:15:00Z",
  "stages_completed": ["parse"],
  "block_count": 42,
  "entity_count": null,
  "fact_count": null,
  "relation_count": null
}
```

`stages_completed` обновляется по мере прохождения pipeline: `parse` → `extract` → `integrate`.

### meta.yaml schema

```yaml
id: techflow-company-desc-2026-04-20
type: document              # document | chat | screenshot | url | audio_transcript
format: pdf                 # pdf | md | txt | docx | html | json
original_path: "..."
title: "..."
ingested_at: 2026-04-20T21:15:00Z

# Parse stage
parser: pymupdf4llm         # pymupdf4llm | markitdown | marker | pass_through | text_wrap
parser_version: "0.0.17"
parse_warnings: []          # e.g. "page 3 had OCR'd text, low confidence"

# Extract stage (v1.1.2, пустое в v1.1.1)
extractor: null             # /ingest skill version
extract_warnings: []

# Integrate stage
integrate_at: null
entities_created: []        # file IDs
facts_created: []
relations_created: []
```

### parsed.jsonl schema

Одна строка — один **блок**. Блок = семантическая единица: heading, paragraph, list item, table row, code block.

```json
{
  "block_id": "b042",
  "source_id": "techflow-company-desc-2026-04-20",
  "block_type": "paragraph",
  "text": "TechFlow — финтех-стартап, основанный в 2019 году в Москве.",
  "provenance": {
    "page": 3,
    "offset": 1247,
    "heading_path": ["Overview", "Company background"]
  }
}
```

`block_type` ∈ `heading | paragraph | list_item | table_row | code_block | quote`.

`heading_path` — стек заголовков родителей, помогает Extract понять контекст блока без чтения всего документа.

## 4. Parse stage

### 4.1 Dispatcher

`mcp-server/ingest/parse.py:parse(path: Path, **opts) -> ParseResult` — выбирает backend по расширению:

| Расширение | Backend | Примечания |
|-----------|---------|-----------|
| `.md` | `pass_through` | Читаем как есть |
| `.txt` | `text_wrap` | Оборачиваем в code block, heading = имя файла |
| `.pdf` | `pymupdf4llm` | Default. Opt-in `--high-quality` → marker |
| `.docx` | *not in v1.1.1* | v1.1.1.x или v1.1.2 |
| `.html` | *not in v1.1.1* | v1.1.1.x |

Dispatcher возвращает `ParseResult`:

```python
@dataclass
class ParseResult:
    markdown: str                  # Нормализованный MD
    blocks: list[Block]            # Разбиение для parsed.jsonl
    warnings: list[str]            # Parser warnings
```

### 4.2 Backend `pymupdf4llm`

Минимальная обвязка:

```python
import pymupdf4llm
md = pymupdf4llm.to_markdown(pdf_path, page_chunks=True)
# page_chunks=True → список страниц → вставляем <!-- page: N --> между ними
```

Page-level provenance через anchor-комментарий `<!-- page: N -->` в markdown. Нормализатор извлекает его и проставляет в `block.provenance.page`.

### 4.3 Normalizer `mcp-server/ingest/normalize.py`

После любого backend'а — нормализация:
1. Единый стиль newlines (`\n`)
2. Проставить `heading_path` для каждого блока (DFS по headings)
3. Выделить блоки: headings / paragraphs / list items / table rows / code
4. Сгенерировать `block_id` = `b{index:03d}`
5. Извлечь page anchors в `block.provenance.page`

## 5. Integrate stage

### 5.1 Вход

Integrate получает JSON массив от Extract (из скилла /ingest, v1.1.2). Схема:

```json
{
  "source_id": "...",
  "entities": [...],        // по entity JSON Schema
  "facts": [...],
  "relations": [...]
}
```

Схемы — в `mcp-server/ingest/schemas/{entity,fact,relation}.json`. Валидация через `jsonschema`.

### 5.2 Дедупликация

Алгоритм для entity:

1. Loaded existing entities из `~/.claude/global-lessons/entity-*.md`
2. Для каждой новой entity:
   - Exact match: same `name` или `name in aliases` **и** `entity_type` совпадает **и** domain пересекается → merge
   - Similar match: name similarity ≥ 0.85 (Levenshtein normalized) **и** domain совпадает → создать с `status: merged_candidate`, `edges: [similar_to: candidate.md]`
   - No match → создать новую
3. Merge: append attributes, merge sources (union), update `last_updated`, пересчитать confidence по формуле из META.md

Для fact:
- Match по `entity_refs` + `description` similarity ≥ 0.9 → merge sources
- Иначе → создать

Для relation:
- Match по `(from_entity, to_entity, relation_type)` → merge sources
- Иначе → создать

### 5.3 Confidence recalc

Из META.md:
```
source_weights = {self_report:1, document:2, third_party:2, behavioral:3, cross_reference:4}
confidence = min(5, mean(source_weights) + bonus)
bonus = 1 if len(independent_types) >= 2 else 0
```

Применяется per-attribute для entity, per-fact для fact, per-relation для relation.

## 6. Scope границы v1.1.1

**Входит:**
- Parse: MD / TXT / PDF (через pymupdf4llm)
- Source storage в `~/.claude/sources/`
- JSON Schemas для extract output
- Integrate: дедуп + confidence recalc
- Unit + e2e тесты с sample.md

**НЕ входит:**
- Extract (см. v1.1.2)
- DOCX / HTML / chat exports / screenshots / URLs / audio
- Discovery Engine (v1.1.4)
- Интеграция в knowledge-activator (v1.1.5)
- `marker` backend (opt-in можно добавить в v1.1.1.x если понадобится)

## 7. Зависимости

Добавляется в `mcp-server/pyproject.toml`:
- `pymupdf4llm` (PDF → MD)
- `jsonschema` (валидация extract output)
- `python-Levenshtein` (optional, для similarity в дедупе — fallback на difflib если не ставится)
