---
name: compile
description: "Batch-консолидация накопленного сырья в кандидаты знаний — читает _drafts/SESSION/_capture, извлекает 3-7 знаний, дедуп против базы (NEW/UPDATE/CONTRADICTS), пишет черновики."
description_en: "Batch consolidation of accumulated raw material into knowledge candidates — reads _drafts/SESSION/_capture, extracts 3-7 items, dedupes against the base (NEW/UPDATE/CONTRADICTS), writes drafts."
user-invocable: true
argument-hint: "[since: YYYY-MM-DD | all] [--dry-run]"
---

# Compile — Batch Knowledge Consolidation

**Type:** worker

Периодический проход «сырьё → кандидаты знаний». Закрывает слой L1→L2 (механическая абстракция), который `/learn` и `/retro` делают поштучно. Перенос механизма `compile.py` из `claude-memory-compiler`, адаптированный под формат знаний ClaudSoul и дисциплину курирования.

| | /learn | /retro | /compile |
|---|--------|--------|----------|
| Объём | одно знание | один инцидент | **много сырья за период** |
| Вход | то, что в диалоге | таймлайн события | `_drafts/`, `SESSION.md`, `_capture/` |
| Выход | live case | многосекционный отчёт + case | **кандидаты в `_drafts/`** (NEW/UPDATE/CONTRADICTS) |
| Запуск | на ходу | после события | периодически / по порогу |

**MANDATORY READ:** Load `~/.claude/global-lessons/META.md` — правила формата и эволюции знаний.
**MANDATORY READ:** Load `references/compile-procedure.md` — детальный механизм: вход, инкрементальность, усечка больших файлов, extract-промпт, дедуп-логика, формат черновика и отчёта.

## Step 1: Определить окно

Прочитать state-маркер `~/.claude/global-lessons/_compile-state.json` (last_compiled). Окно = с `last_compiled` по now, либо из аргумента (`since:DATE` / `all`). `--dry-run` — показать что было бы скомпилировано, не писать.

## Step 2: Собрать сырьё

Источники (что существует — то и брать):
- `~/.claude/global-lessons/_drafts/*.md` — auto-drafts от `error-tracker`
- **`.claude-docs/session-activity.md` по ВСЕМ проектам, не только локальный** — машинный лог сессий (инструменты, файлы, коммиты, **промпты пользователя**). Собрать со всех корней проектов `find`-ом (точная команда + тегирование проектом + дедуп пересечений — в `references/compile-procedure.md`). Локальный-только обход был дефектом v1.0.0: консолидировался лишь проект запуска
- проектный `SESSION.md` — narrative-записи в окне
- текущий transcript — только если в окне были коррекции/промахи предсказаний, не попавшие в файлы

Большие файлы читать с усечкой head 60% / tail 30% + маркер `<elided>` (см. references) — не раздувать контекст.

## Step 3: Загрузить базу для дедупа (index-guided)

Прочитать индекс существующих знаний (`~/.claude/global-lessons/` — имена + description из frontmatter; при наличии — `_index`). Это карта для решения NEW vs UPDATE. Без эмбеддингов — LLM рассуждает по индексу (Karpathy-подход, как `query.py`).

## Step 4: Извлечь 3–7 кандидатов

Из сырья выделить 3–7 **различных** знаний. Пропускать рутину/тривиальное (правило `flush.py`). Каждый кандидат — по формату v0.2 (type, конкретное actionable правило, 9 якорей, confidence, impact, demand). Якоря извлекать автоматически.

## Step 5: Дедуп против базы

Для каждого кандидата сверить trigger+situation+domain с базой:

| Решение | Условие | Действие |
|---------|---------|----------|
| **UPDATE** | есть знание с похожим trigger, не противоречит | пометить «подкрепляет [name], confidence N→N+1» — НЕ трогать live-файл, записать предложение |
| **CONTRADICTS** | противоречит существующему | пометить «противоречит [name] — нужен `/retro`». Не разрешать конфликт здесь |
| **NEW** | совпадений нет | новый кандидат |

## Step 6: Записать черновики (не live)

Каждый кандидат → `~/.claude/global-lessons/_drafts/compile-YYYY-MM-DD-slug.md` по шаблону `references/case-template.md` (из `/learn`), плюс header с `proposed_action: NEW|UPDATE|CONTRADICTS` и `source_window`. **Не** писать в live-базу — это кандидаты, нужно подтверждение (uncertainty principle, memory-as-resource).

## Step 7: Обновить state, сбросить напоминание, отчёт

Записать `_compile-state.json` (last_compiled=now, processed sources hash). **Этого достаточно — счётчик напоминания обнулится сам** (v1.16.1): он выводится из `last_compiled`, а не живёт отдельным файлом. До этой правки сброс предписывался здесь текстом и вызывался только если о нём вспомнить; на прогоне 2026-07-28 его пропустили, а счётчик разошёлся с реальностью в 28 раз (140 против 5). Показать отчёт-таблицу: кандидат · proposed_action · target · impact. В конце — как промоутить: `/learn` поштучно или batch-accept.

Пропустить сброс при `--dry-run` (ничего не консолидировали — напоминание остаётся в силе).

## Rules

- Черновики, не live. Confidence стартует низким, эволюция — через `/learn`.
- Коммуникативные знания: confidence ≤ 2 пока не подтверждено разными speaker'ами.
- Конфликты НЕ разрешать — флаг на `/retro`.
- Инкрементально: не перекомпилировать уже обработанное сырьё (state-маркер).
- Каждое правило КОНКРЕТНО и actionable, не «быть внимательнее».
- Пусто/тривиально → честно сказать «нечего консолидировать», не выдумывать кандидатов.

## Definition of Done

- [ ] Окно определено (state-маркер или аргумент)
- [ ] Сырьё собрано из существующих источников **по всем проектам** (с усечкой больших файлов)
- [ ] База загружена для дедупа (index-guided)
- [ ] 3–7 кандидатов извлечено (или честное «нечего консолидировать»)
- [ ] Каждый кандидат помечен NEW/UPDATE/CONTRADICTS
- [ ] Черновики записаны в `_drafts/` (не live)
- [ ] `_compile-state.json` обновлён
- [ ] `last_compiled` продвинут — этим счётчик напоминания обнуляется сам (отдельный сброс не нужен)
- [ ] Отчёт-таблица показан + как промоутить

**Version:** 1.1.0
**Last Updated:** 2026-07-31