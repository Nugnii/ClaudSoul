# Extract Guide — rules for /ingest skill

Этот документ описывает, как Claude должен извлекать entity/fact/relation из `parsed.jsonl`. Соблюдение критично: integrate использует поля буквально.

## 1. Объекты

### 1.1 Entity

Именованная единица в одной из таксономий:

| entity_type | Примеры |
|-------------|---------|
| `person` | Имена людей (CEO, author, researcher) |
| `company` | Организации, стартапы, корпорации, НКО |
| `concept` | Теории, методологии, абстрактные идеи ("System 1", "gated-action") |
| `event` | Конкретные события с датой (IPO, запуск продукта, инцидент) |
| `place` | Географические локации (город, страна, офис) |
| `work` | Произведения (книга, статья, репозиторий, датасет) |
| `product` | Продукты/сервисы (API, SaaS, библиотека, устройство) |

Обязательные поля:
```json
{
  "name": "TechFlow",
  "entity_type": "company",
  "attributes": { /* см. §1.4 */ }
}
```

Опциональные:
```json
{
  "aliases": ["TF", "ТехФлоу"],
  "description": "Финтех-стартап для B2B SMB",
  "domain": ["b2b_sales", "fintech"],
  "tags": ["startup", "russia"],
  "first_seen": "<source_id>:b003",
  "trajectory": [
    {"date": "2019", "observation": "основан в Москве", "source": "<source_id>:b002"}
  ]
}
```

**Правило для `aliases`:** если в документе сущность встречается в нескольких написаниях (сокращения, перевод, транслитерация, cross-script варианты) — перечислить ВСЕ встреченные варианты. Integrate использует `aliases` как детерминированный мост между написаниями:

- Сокращения: `"aliases": ["TF", "TechF"]` для TechFlow
- Cross-script: `"aliases": ["Polska", "Польша"]` для entity-польша.md
- Транслитерация: `"aliases": ["Umowa o dzieło", "Umowa o dzielo"]` — если один источник использует диакритику, другой нет
- Перевод названия: `"aliases": ["Bank of Poland", "Bank Polski"]`

Canonical `name` — то, которое ты считаешь основным (обычно: как написано в первоисточнике, с сохранением Unicode). Остальные варианты — в `aliases`. Любой `entity_ref` с alias-написанием резолвится на canonical файл через `_resolve_entity_ref` (tier 3: aliases-match до SequenceMatcher-fallback).

### 1.2 Fact

Отдельное утверждение, которое **не помещается** в attributes конкретной entity. Если утверждение о свойстве сущности — делать его attribute, не fact.

Обязательные поля:
```json
{
  "description": "TechFlow была основана в 2019 году в Москве.",
  "fact_type": "event",
  "sources": [{"id": "<source_id>:b002", "type": "document", "extracted": "2026-04-20"}]
}
```

`fact_type`:
- `attribute` — свойство, которое должно было быть attribute, но entity ещё не выделена
- `event` — дискретное событие ("основан в 2019", "продал компанию в 2024")
- `rule` — общее правило/эвристика ("particle systems: 40-80k вершин приемлемы")
- `definition` — формальное определение термина/концепта

Опциональные:
```json
{
  "name": "techflow-founded-2019",
  "entity_refs": ["entity-techflow.md"],
  "valid_from": "2019",
  "valid_until": null,
  "temporal_note": "до ребрендинга в 2024",
  "domain": ["b2b_sales"],
  "tags": ["founding"]
}
```

### 1.3 Relation

Типизированная связь между двумя уже определёнными entity'ами.

Обязательные поля:
```json
{
  "relation_type": "created",
  "from_entity": "entity-vasturiano.md",
  "to_entity": "entity-3d-force-graph.md",
  "sources": [{"id": "<source_id>:b005", "type": "document"}]
}
```

`relation_type` ∈
`role_in | knows | studied_at | works_at | part_of | created | participated_in | similar_to | contradicts | caused_by | applied_to`.

Опциональные:
```json
{
  "direction": "directed",
  "description": "Автор оригинального 3D force-directed графа",
  "valid_from": "2018",
  "valid_until": null,
  "temporal_note": ""
}
```

### 1.4 Attribute value

Каждый attribute внутри entity — объект со строгой структурой:

```json
{
  "value": "fintech",
  "source_type": "document",
  "sources": ["<source_id>:b003"]
}
```

`source_type` ∈ `self_report | document | third_party | behavioral | cross_reference` (см. §3).

Массив значений (например, список навыков или продуктов):

```json
"skills": [
  {"value": "Python", "level": "senior", "source_type": "document", "sources": ["<source_id>:b010"]},
  {"value": "Go",     "level": "junior", "source_type": "behavioral", "sources": ["<source_id>:b012"]}
]
```

**Не выставлять `confidence` вручную** — integrate пересчитает по формуле в META.md.

## 2. Slug convention

Имена файлов в `global-lessons/` — детерминированные. Для ссылок из `entity_refs`, `from_entity`, `to_entity`:

Алгоритм (Python `re` с `flags=re.UNICODE`):
1. `lowercase` имя
2. Удалить символы НЕ подходящие под `[\w\s-]` (любой Unicode word char сохраняется)
3. Заменить последовательности пробелов/подчёркиваний на `-`
4. Обрезать ведущие/хвостовые `-`
5. `entity-<slug>.md`

**КРИТИЧНО:** Unicode символы (кириллица, польская диакритика — `ł`, `ś`, `ę`, `ą` и т.п.) **СОХРАНЯЮТСЯ**. Не транслитерируй.

Примеры:
- `TechFlow` → `entity-techflow.md`
- `Vasili Petrov` → `entity-vasili-petrov.md`
- `3D Force Graph` → `entity-3d-force-graph.md`
- `Umowa o dzieło` → `entity-umowa-o-dzieło.md` (НЕ `entity-umowa-o-dzielo.md`)
- `Польша` → `entity-польша.md` (НЕ `entity-polsha.md`)
- `Карта побыта` → `entity-карта-побыта.md` (НЕ `entity-karta-pobyta.md`)

**Helper для проверки:**
```bash
"$PY" -m ingest.cli slug "Umowa o dzieło"
# → entity-umowa-o-dzieło.md
```
Используй, если сомневаешься — особенно для имён с диакритикой или не-латиницей.

Если в pipeline integrate создаст сущность со status `merged_candidate` и другим путём — Claude указывает в `entity_refs` имя, которое он бы дал сам. Integrate использует similarity-resolver (порог 0.75), так что небольшие расхождения разрешатся автоматически. Серьёзные расхождения (транслитерация) попадут в `warnings` — проверь их после integrate.

## 3. Confidence и source_type

Integrate использует формулу из `knowledge/META.md` §3.2:

```
weights = {self_report:1, document:2, third_party:2, behavioral:3, cross_reference:4}
confidence = min(5, round(mean(weights) + bonus))
bonus = 1 if len(distinct_source_types) >= 2 else 0
```

Выбор `source_type`:

| Тип источника | Критерий |
|---------------|----------|
| `self_report` | Сущность описывает саму себя (bio, own website, interview про себя) |
| `document` | Формальный документ: отчёт, статья, whitepaper, PDF. **Default для MD/TXT/PDF ingestion.** |
| `third_party` | Сторонний источник пишет о сущности (новость, ревью) |
| `behavioral` | Вывод из поведения/действий, а не из прямого утверждения |
| `cross_reference` | Подтверждено 2+ независимыми источниками одного типа или разных |

Практика для документов:
- Большинство attributes/facts → `document`
- Если документ — интервью/автобиография сущности → `self_report`
- Если документ цитирует другой источник → `cross_reference`

## 4. Что НЕ извлекать

- Собственные мысли Claude о тексте — только факты из текста
- Предположения, которых нет в тексте (даже "логично следует, что")
- Дубли: если уже есть attribute `founded: 2019`, не делать отдельный fact "основан в 2019"
- Meta-комментарии документа ("эта таблица показывает...") — это структура, не знание
- Code blocks как факты — если это иллюстрация, не знание о мире

## 5. Политика дедупа (на стороне integrate)

Claude **не обязан** проверять существующие entity — integrate сделает это. Но полезно знать:

- Exact match: same `name` или `name in aliases` + same `entity_type` + domain пересекается → merge
- Similar (Levenshtein ≥ 0.85) + same domain → создание с `status: merged_candidate` и edge `similar_to`
- Разный `entity_type` при совпадении имени → отдельные сущности (Apple company vs Apple fruit)

Если Claude знает, что `TechFlow` в parsed.jsonl — это та же компания, что в существующей `entity-techflow.md`, он всё равно просто выдаёт entity с name `TechFlow`. Integrate заметит и сольёт.

## 6. Provenance формат в sources

Для каждого attribute/fact/relation source:

```json
{"id": "<source_id>:b042", "type": "document", "extracted": "2026-04-20"}
```

- `<source_id>:b<block_id>` — точная ссылка на блок в parsed.jsonl (предпочтительно)
- `<source_id>:p<page>` — ссылка на страницу (для PDF когда блок не релевантен)
- `<source_id>` без локатора — крайний случай

`extracted` — дата извлечения (today, в ISO формате).

## 7. Минимальный валидный payload

Если сомневаешься что извлекать — лучше меньше, чем неправильно. Минимум для успешного integrate:

```json
{
  "source_id": "<SOURCE_ID>",
  "entities": [],
  "facts": [],
  "relations": []
}
```

Это валидно. Но если `entities` + `facts` оба пусты — задать пользователю вопрос: «Документ не содержит извлекаемых знаний по текущим правилам. Это ожидаемо?»

**Version:** 0.1.0
**Last Updated:** 2026-04-20
