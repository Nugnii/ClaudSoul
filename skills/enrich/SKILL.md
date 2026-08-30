---
name: enrich
description: "Веб-обогащение сущности по tier-источникам. Конфликты в contradiction, не перезаписывает. /enrich <name|slug> либо «обнови X»."
description_en: "Web enrichment of an entity from tier sources. Conflicts go into contradiction, nothing is overwritten. /enrich <name|slug> or \"update X\"."
user-invocable: true
argument-hint: "<имя сущности или slug> [--jurisdiction=PL|global|...]"
---

# Enrich — веб-обогащение сущности

**Type:** worker

Идёт в веб, находит новую информацию о сущности, сопоставляет с существующими атрибутами и мёрджит результат. Работает с одной сущностью за запуск. Read + WebSearch + WebFetch + стандартный ingest pipeline.

## Когда использовать

- `/enrich <name>` — явный вызов
- «обнови информацию про X», «проверь что известно про X в сети», «добавь публичные данные про X», «что про X пишут»

**НЕ использовать**, если:
- Сущности нет в графе (сначала `/ingest` или просто в чате добавить факты вручную)
- Нужен только веб-поиск без записи в граф (обычный `WebSearch` достаточен)

## MANDATORY READ

- `knowledge/source-tiers.md` — tier-таблица доменов, правила детекта юрисдикции
- `~/.claude/global-lessons/META.md` — формулы confidence, правила эволюции
- `skills/ingest/references/extract-guide.md` — схема extract payload, source_type, provenance

## Step 0: Путь к движку

Подключить общий резолвер репо: `source "$HOME/.claude/bin/resolve-claudsoul-repo.sh"`, затем `REPO=$(resolve_claudsoul_repo) || exit 1` (порядок поиска: `$CLAUDSOUL_REPO` → `~/.claude/claudsoul-repo` → `git rev-parse`; файл ставит install.sh). После:

```bash
PY="$REPO/mcp-server/.venv/bin/python"
INGEST="$PY -m ingest.cli"
TIERS="$REPO/knowledge/source-tiers.md"
```

## Step 1: Получить сущность

```bash
"$PY" -m ingest.cli show-entity "<query>" > /tmp/enrich-entity.json
```

- `not_found` → сказать пользователю: «сущности нет в графе, добавь через `/ingest` или чат»
- `ambiguous` → показать список, остановиться, попросить уточнить
- Прочитать JSON полностью: `name`, `aliases`, `entity_type`, `attributes`, `domain`, `related_relations`

## Step 2: Детект языков аудитории (primary axis, v0.5.0)

**Language-first:** язык — основная ось для большинства поисков (статьи, отзывы, описания). Юрисдикция — только для регуляторных запросов. Это инверсия прежнего порядка: раньше юрисдикция определяла набор источников целиком, теперь язык определяет narrative-источники, юрисдикция — только регуляторные.

**Почему:** польская компания с русскоязычной аудиторией описывается не в польской прессе (почти никогда), а в русскоязычных IT/business изданиях и диаспорной прессе. Искать в польских СМИ по запросу `"ProjectA"` — значит почти гарантированно не найти ничего; искать в ru-media — значит найти отзывы, интервью, обзоры. Раньше это решалось точечной правкой в Media pass; теперь — default для всего /enrich.

### Порядок сбора языков

Собрать множество `languages = { ... }` из:

1. **Interlocutor language** — язык, на котором общается пользователь с агентом (текущая сессия). Если пользователь пишет по-русски → `ru` попадает в множество **всегда**, независимо от сущности. Это сильный сигнал: если спрашивают по-русски про польскую компанию — ожидают русскоязычные источники.
2. **`attributes.support_languages`** — явный список (`Русский`, `Polski`, `English`, `Беларуская`, …) → нормализовать в ISO-коды (`ru`, `pl`, `en`, `be`, …).
3. **`attributes.target_audience`** — если содержит «русскоязыч», «диаспор», «СНГ», «rosyjskojęzyczn» → `ru`; «English-speaking», «international», «global» → `en`; «Polska», «polsk*» → `pl`.
4. **`domain`** — `russian_speaking_*`, `belarus_*`, `ru_*` → `ru`; `polish_speaking_*`, `pl_*` → `pl`; `english_speaking_*`, `us_*`, `international_*` → `en`.
5. **`entity.aliases` / `name`** — если есть алиасы в разных алфавитах (кириллица/латиница) → добавить соответствующие языки.

Если множество пусто → fallback на язык юрисдикции (PL → `pl`). Если юрисдикции тоже нет → `en` как default.

Типично 1-3 языка, максимум 5.

Результат: **primary_languages** — упорядоченный список по силе сигнала (interlocutor_lang > support_languages > target_audience > domain).

Записать пользователю: `Языки (primary): ru, pl, en — приоритет источников по языку, юрисдикция вторична`.

### Step 2b: Детект юрисдикции (secondary axis)

Юрисдикция нужна только для **регуляторных фактов**: выписки из реестров, налоги, законы, государственные лицензии. Для narrative (статьи, отзывы, описания) она не нужна — там primary_languages.

Порядок (прежний, без изменений):

1. Связь с `entity-<country>.md` / `entity-<city>.md` через `part_of`/`applied_to`
2. `domain` маркеры: `poland_*`, `us_*`, `eu_*`, `belarus_*`
3. Атрибуты: `country`, `country_code`, `address` (польский индекс `NN-NNN`, немецкий `NNNNN`), `nip`/`regon`/`krs` → PL; `ein` → US; `unp` → BY
4. `legal_form`, `legal_name`: `Sp. z o.o. | S.A. | JDG` → PL; `LLC | Inc. | Corp.` → US; `GmbH | AG` → DE

Первое сработавшее побеждает. Если ничего — `jurisdiction: global`.

Override: `--jurisdiction=<code>` от пользователя побеждает всё.

Записать пользователю: `Юрисдикция: PL (по связи с entity-польша.md) — используется только для регуляторных источников`.

### Решение: когда применять какую ось

| Цель поиска | Primary ось | Пример |
|-------------|-------------|--------|
| Выписка из реестра (KRS, РЕГОН, EIN) | **Jurisdiction** | `krs-online.com.pl`, реестр регулятора |
| Налоговая / юридическая информация о сущности | **Jurisdiction** | `podatki.gov.pl`, `sejm.gov.pl` |
| Описание, отзывы, мнения, обзоры | **Language** | `habr.com`, `vc.ru`, `example-it.media` для `ru` |
| Интервью с основателем / упоминания в прессе | **Language** | Russian-language media для `ru` |
| Официальный сайт самой сущности | **Language** (сайт сам выбирает свой язык) | `projecta.com.pl` |
| Сравнение с конкурентами, market overview | **Language** | отраслевые медиа на языке аудитории |

Это распределение применяется в Step 4 (основной поиск) и Step 4b (Media pass). Step 4 теперь тоже language-first для narrative-фактов.

## Step 3: Загрузить tier-таблицы

```bash
cat "$TIERS"
```

Составить **две in-memory таблицы**:

**A. `language_tiers`** — по каждому из `primary_languages` (секции `Russian-language media`, `Polish-language media`/PL, `English/Global`). Это основной источник для narrative-поисков.

```
language_tiers = {
  "ru": { 2: ["thebell.io", "meduza.io", ...], 3: ["habr.com", "vc.ru", "example-it.media", ...], 4: ["t.me/*", "reddit.com/r/russia", ...] },
  "pl": { 2: ["pap.pl", "rp.pl", ...], 3: ["bankier.pl", "money.pl", ...], 4: ["wykop.pl", ...] },
  "en": { 2: ["reuters.com", "apnews.com", ...], 3: ["techcrunch.com", ...], 4: [...] }
}
```

**B. `jurisdiction_tiers`** — по юрисдикции (`PL` → PL Tier 1, `US` → US Tier 1, и т.д.). Используется **только** для регуляторных поисков.

```
jurisdiction_tiers = {
  1: ["*.gov.pl", "sejm.gov.pl", "krs-online.com.pl", "zus.pl", "rejestr.io", "stat.gov.pl"],
  2: ["wikipedia.org", "reuters.com", ...]  // plus Global Tier 2 fallback
}
```

Если юрисдикция `global` — `jurisdiction_tiers` = Global Tier 1-2.

**Wikipedia, Reuters, AP, BBC** — кросс-ось: попадают и в language_tiers (en), и в jurisdiction_tiers (Global Tier 2). Дубликаты разрешать в пользу language (приоритет выше).

## Step 4: Веб-поиск (language-first)

Раздел раздваивается на **narrative pass** (primary) и **regulatory pass** (secondary, только если нужны регуляторные факты).

### Step 4a: Narrative pass (по primary_languages)

Для **каждого** языка из `primary_languages` сформировать 2-3 запроса:

1. **Имя + язык-специфичный ключевой атрибут:**
   - `ru`: `"<name>" <русский cue>` — напр. `"ProjectA" Польша инкубатор отзыв`, `"ProjectA" бизнес-инкубатор <город>`
   - `pl`: `"<name>" <польский cue>` — напр. `"ProjectA" inkubator biznesu`, `"ProjectA" NIP` (регуляторные ключевые в PL тоже узнаются)
   - `en`: `"<name>" <english cue>` — напр. `"ProjectA" Poland business incubator`, `"<name>" freelancer`
2. **Имя + сильный идентификатор:** `"<name>" <NIP|domain|legal_name>` — работает на любом языке
3. **По алиасам** — если есть (`ProjectA Sp. z o.o.`, `Team Adviser` и т.п.) — на каждом языке

Для каждого запроса:

```
WebSearch(query="<query>", allowed_domains=[<language_tiers[lang] Tier 2-3, до 20>])
```

Fallback: если `allowed_domains` дал 0 результатов — повторить без ограничения, отсортировать вручную по tier из `language_tiers[lang]`. **Tier 4 отбрасывать**, если Tier 1-3 дали результат.

Из результатов взять до **5 самых релевантных URL на язык** (имя в заголовке/сниппете, высший tier).

### Step 4b: Regulatory pass (по юрисдикции, опционально)

Запускать **только если**:
- У сущности есть регистрационный ID (`nip`, `regon`, `krs`, `ein`, `unp`) — проверить актуальность в реестре
- Или `attributes` содержит `legal_*` атрибуты, требующие подтверждения из гос-источника
- Или пользователь явно просил «проверь реквизиты / официальные данные»

Для каждого такого запроса:

```
WebSearch(query="\"<name>\" <identifier>", allowed_domains=[<jurisdiction_tiers[1] — до 20>])
```

Типично 1-2 запроса (не нужно веером).

Если юрисдикция `global` — regulatory pass пропустить (нет конкретных реестров).

## Step 4c: Media pass — публикации о сущности

Отдельный целенаправленный проход за упоминаниями сущности в прессе/блогах: статьи как first-class записи (название, издание, дата, автор, URL), а не просто факты *о* компании. Полная спецификация — в [references/media-pass.md](references/media-pass.md).

Тл;др шагов:
1. Для каждого языка из `primary_languages` — 2-3 запроса (имя + язык-специфичное слово; имя + ID; по людям из графа), `allowed_domains` = lang Tier 2-3.
2. Отобрать до 10 URL где имя в заголовке или первом абзаце.
3. WebFetch с извлечением заголовка, издания, даты, автора, цитаты.
4. **Ensure media entity** — найти или создать `entity_type: company, type: *_media` для издания. Без media-сущности work не создаётся.
5. Создать `entity_type: work` со slug `publication-<media>-<date>-<words>`. Атрибут `publisher` НЕ пишем — имя издания через relation `published_in`.
6. Две relations: `mentions` (work → subject) + `published_in` (work → media).
7. Дедуп по `url.value`. 0 публикаций при ожидаемых > 0 — явный warning в отчёт.

## Step 5: Скрейп страниц

Для каждого URL:

```
WebFetch(url=<url>, prompt="Извлеки факты про <name> (<entity_type>): все атрибуты, реквизиты, связи. Markdown. Без интерпретации — только то, что написано.")
```

Сохранить результат в `/tmp/enrich-<slug>-<i>.md` с первой строкой `# <name> — <host>` для контекста.

Если WebFetch вернул ошибку / пустоту — пропустить URL, записать в warnings.

## Step 6: Parse каждого скрейпа

```bash
for i in 0..N-1:
  "$INGEST" parse "/tmp/enrich-<slug>-<i>.md" \
    --title "<name> — <host>" > /tmp/enrich-parse-<i>.json
  SOURCE_ID_i=$(jq -r .source_id /tmp/enrich-parse-<i>.json)
```

Каждый URL → свой `source_id`. Блоки `parsed.jsonl` — стандартные.

## Step 7: Определить tier для каждого source_id

Для каждого URL определить tier из таблицы (шаг 3). Запомнить как mapping `source_id → tier`.

## Step 8: Extract — diff с существующими атрибутами

Прочитать каждый `parsed.jsonl` + данные сущности из Step 1. Для каждого найденного факта классифицировать:

| Категория | Условие | Действие |
|-----------|---------|----------|
| **confirmed** | значение совпадает (или почти — Levenshtein ≥ 0.9) с существующим атрибутом | добавить source к существующему атрибуту через integrate |
| **new** | атрибут которого не было в сущности | добавить как новый атрибут |
| **contradiction** | атрибут есть, но значение отличается | сохранить **оба** значения как массив |

### Правило source_type для web-фактов

- Tier 1 → `source_type: "document"` + в integrate после этого установить `confidence: 4` (hardcoded, перекрывает формулу)
- Tier 2 → `source_type: "document"` (стандартная формула даст confidence 3)
- Tier 3 → `source_type: "third_party"` (confidence 2)
- Tier 4 → `source_type: "third_party"` + пометить `low_trust: true` в source entry (отдельное поле — если схема отклоняет, положить в description)

Если источник — официальный сайт самой сущности → `source_type: "self_report"` (независимо от tier).

### Формат для contradictions

Схема `entity.json` даёт встроенный канал для конфликтов — поле `contradiction: {stated_value, stated_source, stated_confidence}` на attribute_value. Основной путь — через него. Массивы (вариант из списка attribute_value) — запасной инструмент для случая «множественные равноправные значения одного атрибута» (поддерживаемые языки, допустимые формы оплаты), НЕ для конфликта.

**Важно (v0.2+):** `integrate._merge_scalar_attrs` автоматически детектирует контрадикцию если новое `value` отличается от существующего. Победителем становится значение с более высоким (SOURCE_WEIGHTS, confidence). Проигравшее значение автоматически уходит в `contradiction.stated_value`. Поэтому:
- Extract payload может просто подать новое значение без поля `contradiction` — integrate сам всё разрулит.
- Если Claude явно вычислил конфликт и хочет зафиксировать конкретную интерпретацию — подать attribute_value с `contradiction: {...}` уже внутри. Integrate сохранит его как есть и не будет перезаписывать своим авто-детектом.

```yaml
# было:
monthly_fee:
  value: "500 PLN"
  source_type: document
  sources: ["projecta-...:b039"]
  confidence: 2

# становится (после контрадикции):
monthly_fee:
  value: "600 PLN"              # новое значение из веба
  source_type: document
  sources: ["enrich-example-co-...:b004"]
  confidence: 3
  contradiction:
    stated_value: "500 PLN"     # прежнее значение из графа
    stated_source: "example-co-обзор-2026-04-21:b039"
    stated_confidence: 2
```

Запись контрадикции — одноуровневая: новое значение «выигрывает» формально (становится `value`), но старое сохраняется внутри поля `contradiction` и видно любому, кто читает сущность. `/knowledge-audit` и `/wiki` должны уметь это показать.

**Если противоречивых источников несколько** (веб нашёл 3 разных значения) — в `stated_value` положить первое из прежних, а остальные web-варианты добавить в `warnings` extract payload'а с указанием URL каждого. Множественные web-значения как массив не храним — это усложняет схему без пользы.

**Решение о том, какое значение становится новым `value`:** по tier. Если новое значение tier ≥ старого — оно побеждает. Если новое tier ниже — старое остаётся `value`, а новое уходит в `contradiction.stated_value` (роли меняются местами). Цель — всегда держать самый надёжный tier в основном слоте.

## Step 9: Сборка extract payload

Объединить всё в один `/tmp/enrich-extract-<slug>.json`:

```json
{
  "source_id": "<source_id_0>",   // один из web-источников как анкер
  "entities": [
    {
      "name": "<name>",
      "entity_type": "<type>",
      "aliases": [...],
      "domain": [...],
      "attributes": {
        "<confirmed_key>": { "value": ..., "source_type": ..., "sources": [...] },
        "<new_key>":       { "value": ..., "source_type": ..., "sources": [...] },
        "<conflict_key>":  [ { existing }, { new_with_contradiction_flag } ]
      }
    },
    {  // от Media pass — publication entity
      "name": "<заголовок статьи>",
      "entity_type": "work",
      "domain": ["<исходный domain>", "media"],
      "tags": ["publication", "<язык>"],
      "attributes": { "title": ..., "published_at": ..., "url": ..., "author_name": ..., "language": ..., "excerpt": ... }  // publisher удалён — v0.4.0 использует relation published_in
    }
  ],
  "facts": [],
  "relations": [
    {  // от Media pass
      "relation_type": "mentions",
      "from_entity": "entity-<publication-slug>.md",
      "to_entity": "entity-<subject-slug>.md",
      "description": "<о чём статья>",
      "sources": [{"id": "<source_id>", "type": "document", "extracted": "<YYYY-MM-DD>"}]
    }
  ],
  "warnings": ["url X returned 404", "Media pass: 0 публикаций на [ru, en]", ...]
}
```

## Step 10: Integrate

```bash
"$INGEST" integrate "/tmp/enrich-extract-<slug>.json" > /tmp/enrich-integrate-out.json
```

Если `jsonschema.ValidationError` — не обходить. Чинить payload.

## Step 11: Отчёт пользователю

Человеческий язык. 8-12 строк. Формат:

```
🔎 Обогатил сущность: <name>
Языки (primary): <list> — narrative источники
Юрисдикция (secondary): <code> — только регуляторные источники
Просмотрено URL: <N> (narrative: <k_n>, regulatory: <k_r>, media: <k_m>)

✅ Подтверждено: <count> фактов
   — <attr1>, <attr2>

➕ Добавлено: <count> новых фактов
   — <attr3>: <value>
   — <attr4>: <value>

⚠️ Конфликты: <count> — требуют ревью
   — <attr5>: было "<old>" (<tier old>), в вебе "<new>" (<tier new>)
     Оба значения сохранены. Решить через /learn или правкой entity-файла.

📰 Публикации: <count>
   — [<язык>] <media_name> · <date> · "<title>" · <editorial|ad_partnership>
   — ...
🏢 Медиа-сущности: <новых>/<всего> (созданы или переиспользованы)

Обновлено: ~/.claude/global-lessons/entity-<slug>.md
```

Если ничего не найдено — честный отчёт: «Просмотрено N URL, новых фактов не нашёл». Не выдумывать.

Если Media pass нашёл 0 публикаций, а ground truth > 0 — явно упомянуть: «Media pass: 0 публикаций на [ru, pl, en]. Это подозрительно — если знаешь про конкретные статьи, подай URL вручную через /ingest».

## Rules

- **Не перезаписывать без следа.** Любое изменение существующего атрибута должно быть или (a) подтверждением с добавлением source, или (b) контрадикцией с сохранением оба значения.
- **Tier 4 не доверяем по умолчанию.** Факт из tier 4 принимается только если tier 1-2 не нашли ничего об этом поле. И даже тогда — с пометкой `low_trust`.
- **Не выдумывать атрибуты.** Если WebFetch не вернул структурированный факт — не генерировать. Не «допиливать» интерпретацией.
- **Language-first, jurisdiction-second.** Для narrative-фактов (статьи, отзывы, описания) ходить в language_tiers. Для регуляторных (реестры, налоги) — в jurisdiction_tiers. Никогда не искать narrative только в юрисдикционных источниках, если аудитория говорит на другом языке — получишь 0 результатов и ложный вывод «про сущность ничего не пишут».
- **Юрисдикция — не угадывать.** Если не определилась — `global` + regulatory pass пропустить, narrative продолжить по языкам.
- **Не запускать без сущности.** Если `show-entity` → not_found, остановиться. Не создавать сущность «по ходу».
- **Отчёт в человеческом языке.** Никаких путей к tmp-файлам, JSON-ответов, `source_id` в выводе пользователю (кроме финального пути к entity-файлу).
- **Один запуск — одна сущность.** Не делать batch. Если пользователь хочет обогатить 10 — запустить 10 раз или явно попросить batch-mode (не реализован в v0.1).

## Definition of Done

- [ ] Путь к движку разрешён, обе tier-таблицы (language + jurisdiction) собраны
- [ ] `show-entity` вернул данные (не not_found)
- [ ] `primary_languages` определены и озвучены пользователю (primary ось)
- [ ] Юрисдикция определена и озвучена пользователю (secondary ось, для регуляторных)
- [ ] Narrative pass (Step 4a): поиск по каждому языку из `primary_languages`
- [ ] Regulatory pass (Step 4b): запущен только если есть registry ID или пользователь просил
- [ ] WebFetch для каждого → parsed.jsonl
- [ ] Tier для каждого source_id зафиксирован
- [ ] Diff посчитан (confirmed / new / contradiction)
- [ ] Extract payload валиден против `extract_output.json`
- [ ] Integrate успешен
- [ ] Контрадикции сохранены как массив (оба значения живы)
- [ ] Media pass выполнен для всех языков из Step 2b
- [ ] Для каждого publisher ensure media entity (переиспользование или минимальный stub)
- [ ] Публикации созданы как entity_type=work БЕЗ attribute publisher
- [ ] Для каждой публикации построены relations: mentions (к subject) + published_in (к медиа)
- [ ] 0 публикаций при ожидаемом ground truth > 0 — явно упомянуто в отчёте
- [ ] Отчёт человеческий, без технических артефактов

## Known limitations (v0.5)

- Нет автосканера — только ручной запуск.
- Нет batch-режима — одна сущность за запуск.
- Tier-таблица покрывает PL, ru-media, global. US/DE/UA/BY — добавлять при встрече.
- Media pass зависит от индекса поисковика — публикации в Telegram/YouTube обычно не индексируются, 0 результатов на них — не признак отсутствия.
- `contradiction` поле не блокирует использование — нет механизма напоминания «есть неразрешённые контрадикции». Будет в `/knowledge-audit`.

**Version:** 0.5.1
**Last Updated:** 2026-07-29