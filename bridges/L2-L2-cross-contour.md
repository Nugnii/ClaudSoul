---
name: Кросс-контурная аналогия
layers: [L2, L2]
direction: bidirectional
status: implemented
version: 0.1.0
last_updated: 2026-06-20
---

# Мост L2↔L2: Кросс-контурная аналогия

> Навык: спонтанная связь между двумя контурами L2 (case/pattern/principle ↔ entity/fact/relation). Момент «о, этот паттерн про X — он уже упоминается в entity Y».

## Почему не «мост внутри слоя»

L2 в ClaudSoul содержит **два независимых контура**:

| Контур | Атомы | Источник | Scoring в `knowledge-activator` |
|--------|-------|----------|----------------------------------|
| **Знаниевый** | `case / pattern / principle` | Опыт агента + `/learn` + `/retro` | Якоря (9) + demand + tier/scope |
| **Entity** | `entity / fact / relation` | `/ingest` + behavioral inference | Name aliases + fact confidence |

Контуры ведут **разные SQL таблицы**, имеют **разные scoring-функции**, **разные decay-модели**. Связь возможна только через пересечение семантики: когда случай/паттерн формулирует поведение, которое у конкретной entity уже задокументировано (или наоборот). Это **cross-contour reference**, не within-layer — потому что каждый контур — de facto отдельный модуль L2.

## Цикл

```
Знаниевый контур              Discovery (v1.3.7)             Entity контур
┌──────────────────┐          ┌───────────────────┐          ┌──────────────────┐
│ pattern:         │          │ discovery.py      │          │ entity:          │
│ "inside-out      │──token──→│ detect_cross_     │←──name──│ org-example      │
│  blindness"      │  match   │ contour_mentions  │   token │ facts: {...}     │
└──────────────────┘          └─────────┬─────────┘          └──────────────────┘
                                         │
                                         ↓ write JSONL
                              ┌───────────────────────┐
                              │ cross-contour-        │
                              │ discoveries.jsonl     │
                              └───────────┬───────────┘
                                          │
                                          ↓ read
                              ┌───────────────────────┐
                              │ knowledge-activator   │
                              │ (v1.3.9 consumer)     │
                              └───────────┬───────────┘
                                          │
                                          ↓ inject 📎
                                   Агент видит связь
                                          │
                                          ↓ /learn edge
                         ┌──────────────────────────────────┐
                         │ typed edge: similar_to           │
                         │ pattern.md ↔ entity.md           │
                         └──────────────────────────────────┘
```

## Четыре условия существования

| # | Условие | Воплощение |
|---|---------|------------|
| 1 | **Dataflow** | `discovery.py` пишет `cross-contour-discoveries.jsonl` (v1.3.7). `knowledge-activator.sh` читает (v1.3.9). JSONL — durable broadcast канал через L1 |
| 2 | **Feedback cycle** | Zафиксированный через `/learn` edge попадает в оба контура: `related` в знаниевом файле, `mentions`/`published_in` в entity. При следующем injection scoring учитывает новую связь |
| 3 | **Emergence** | Момент «insight»: ни контур знаний, ни entity контур по отдельности не поднимают связь. Она возникает только на пересечении. У человека это — спонтанная аналогия «о, это как тогда с...» |
| 4 | **Operationalizability** | Пайплайн измерим: счётчик discoveries в лог / surfaced в инжект / ручных /learn edges = воронка конверсии |

## Текущая реализация (v1.3.9)

**Detection:** `discovery.py::detect_cross_contour_mentions` — каждая запись `{knowledge_file, entity_file, matched, timestamp}` в `~/.claude/hooks/state/cross-contour-discoveries.jsonl`. Триггер — token match между knowledge name/anchors и entity name/aliases.

**Surfacing (базовый):** `knowledge-activator.sh` tail 200 записей + фильтр `knowledge_file` в текущем injection set + dedup по `(KF,EF)` + head 3. Inject секция `📎 Кросс-контурные упоминания (паттерн ↔ entity)`.

**Ограничение:** surfacing происходит **только** когда knowledge из лога уже в инжект-наборе по keyword scoring. Если keyword scoring не поднял паттерн, но entity в текущем контексте упоминается — связь остаётся молчать. Это **первый предел** spontanenous analogy surfacing.

## Планируемое расширение (v1.6, Фаза 5 pretzel plan)

- **5.1 Semantic scoring** — `cross_contour_rank(discovery, context) ∈ [0,1]` через MCP search_knowledge + fastembed. Возможно поднятие связи по similarity, не только по keyword inclusion. Критерий закрытия — top-3 similarity ≥0.5 на 10 ручных кейсах
- **5.2 Релаксация фильтра** — `similarity ≥ 0.6 OR knowledge в инжект-наборе`. Снижает false negatives за счёт допустимого роста шума
- **5.3 Session-scope dedup** — `state/cross-contour-surfaced-<SID>.jsonl`: одна и та же связь не surface'ится повторно в пределах сессии
- **5.5 H10 вторая ось** — `surfaced_count / written_count ≥ 0.1` как критерий живости моста (не только пишем, но и читаем)

## Риски и ограничения

- **Semantic score FP** (false positives) — MCP может поднять связь по слабому vocabulary overlap. Митигация: confidence threshold + ручной audit первых 20 инжектов
- **Latency** — MCP query в `knowledge-activator` на каждом PreToolUse опасен для SessionStart <2с бюджета. Митигация: async pre-computation при Stop / PreCompact (записать отранжированные discoveries в state) + hot-read при инжекте
- **Обратная связь через `/learn`** — агент должен фиксировать успешные инжекты через explicit edges. Без этого L2↔L2 остаётся read-only консьюмером

## Метрики живости

- **H10 first axis (v1.3.7):** `wc -l cross-contour-discoveries.jsonl` — detection работает
- **H10 second axis (v1.6, план):** счётчик `cross_contour_surfaced_total` в `history digest` / `written_total` — surfacing работает
- **H10 third axis (будущее):** explicit edges `similar_to` в knowledge/entity файлах, созданные через `/learn` после инжекта — loop закрыт

## Связь с другими мостами

- **L2↔L3** (knowledge-from-communication) — entity-контур построен в значительной степени на communication data (satisfaction signals + `/ingest` от пользовательских сообщений)
- **L2↔L5** (metacognition) — `/knowledge-audit` сканирует оба контура, discovery включён в weekly digest
- **L2↔L4** (anticipatory-learning) — в будущем: entity-траектория (история упоминаний) может обогатить knowledge-траекторию

## Статус

Базовый consumer работает с v1.3.9. Расширение через semantic scoring — v1.6 (Фаза 5 pretzel plan). H10 вторая ось инструментация планируется в 5.5.
