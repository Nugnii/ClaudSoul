# Media pass — публикации о сущности

Детальная спецификация Step 4c из `/enrich`. Основной SKILL.md ссылается сюда.

Отдельный проход целенаправленно ищет упоминания сущности в прессе/блогах. Это независимая цель: ищем не столько факты *о* компании, сколько сами публикации как first-class записи (название, издание, дата, автор, URL).

## Множество поисковых доменов

Для каждого языка из `primary_languages` (Step 2 главного SKILL.md) домены берутся
из `knowledge/source-tiers.md` — единственного источника доменных таблиц (канон
single-source-of-truth: до v1.18.0 списки дублировались здесь и разъезжались):
- язык с собственной секцией → её Tier 2 + Tier 3
- язык юрисдикции сущности → Tier 2 + Tier 3 секции юрисдикции
- `en` и языки без своей секции → Global Tier 2 + Tier 3
- совсем без покрытия → без `allowed_domains`, tier определять постфактум

## Запросы

Для каждого языка сформировать 2-3 запроса:
1. **Имя + язык-специфичное слово:** `"ProjectA"` + (pl: `<miasto> inkubator`) / (ru: `Польша инкубатор отзыв`) / (en: `Poland incubator freelancer`)
2. **Имя + один из ключевых атрибутов:** `"ProjectA" NIP <номер из графа>` (если есть), `"ProjectA Sp. z o.o."`
3. **По каждому человеку из графа** (входящие `works_at`/`role_in`): `"<имя человека>" "<компания>"` — чтобы ловить интервью / упоминания персон

```
WebSearch(query="<query>", allowed_domains=[<lang tier 2-3 домены>])
```

## Отбор публикаций

Из результатов взять те, где имя сущности **в заголовке или первом абзаце** (не случайное упоминание в списке клиентов). До **10 URL суммарно** на все языки (чтобы не раздуть граф).

**Если ground truth известен** (пользователь явно сказал «минимум N публикаций существуют») — если найдено меньше N, расширить запросы: алиасы, aliases персон, запросы без `site:` ограничений.

## WebFetch + извлечение

Для каждого отобранного URL:

```
WebFetch(url=<url>, prompt="Извлеки: (1) заголовок статьи, (2) издание/медиа (название), (3) дата публикации, (4) автор, (5) одна ключевая цитата о <name>. Markdown, один блок на каждый пункт.")
```

## Ensure media entity (Media-as-entity, v0.4.0)

**Publisher — не строка, а сущность в графе.** Перед созданием work убедиться, что media-сущность (`entity_type: company`, `type: *_media`) существует.

1. Нормализовать имя издания из извлечённого текста/URL: `example-it.io` → `example-it.media`, `news.example-news.media` → `example-news.media`, `example.media` → `Example Media`.
2. `show-entity "<имя медиа>"` — если найдено (точно или через alias), взять slug.
3. Если не найдено — создать минимальную сущность с атрибутами: `website`, `language` (язык СМИ), `target_audience` (кому пишет), `country` (если очевидна), `type: industry_media|general_media|business_media|blog_platform`, `description_short`. Теги: `[media, <lang>, <region|industry>]`.
4. **Никогда не создавать публикацию без media-сущности.** Если отрезать — будет висящий узел.

## Создание entity_type=work

Для каждой публикации — новая сущность `work`. **Атрибут `publisher` НЕ пишем** — имя издания отражено через relation `published_in`.

```yaml
entity_type: work
name: "<заголовок статьи>"
aliases: []
attributes:
  title:
    value: "<точный заголовок>"
    source_type: document
    sources: [<source_id>]
  published_at:
    value: "<YYYY-MM-DD>"
    source_type: document
    sources: [<source_id>]
  url:
    value: "<полный URL>"
    source_type: document
    sources: [<source_id>]
  author_name:      # если есть
    value: "<ФИО>"
    source_type: document
    sources: [<source_id>]
  language:
    value: "<ru|pl|en|…>"
    source_type: document
    sources: [<source_id>]
  excerpt:           # ключевая цитата
    value: "<одно предложение из статьи>"
    source_type: document
    sources: [<source_id>]
domain: [<domain сущности>, media]
tags: [publication, <язык>, <ad_partnership|editorial>]
```

Slug сущности: `publication-<media-slug>-<YYYY-MM-DD>-<первые-3-слова-заголовка>`.

## Связи: mentions + published_in

Для каждой публикации создать **две** связи:

```yaml
# 1. Публикация → subject (компания или персона)
relation_type: mentions
from_entity: entity-<publication-slug>.md
to_entity: entity-<subject-slug>.md
description: "<одно предложение — о чём статья в контексте subject>"
sources: [<source_id>]
```

```yaml
# 2. Публикация → медиа (обязательно)
relation_type: published_in
from_entity: entity-<publication-slug>.md
to_entity: entity-<media-slug>.md
description: "<editorial|ad_partnership> — <краткий комментарий>"
sources: [<source_id>]
```

Если статья упоминает и компанию, и персону — две `mentions` + одна `published_in` (издание всё равно одно).

## Дедуп

Если URL уже в графе (поиск по `attributes.url.value`) — не дублировать entity, только добавить новый `source_id` к существующим атрибутам через integrate.

## Когда 0 публикаций — это сигнал

Если после всех запросов на всех языках 0 публикаций:
- Зафиксировать в warnings: `"Media pass: 0 публикаций найдено на языках [<list>]. Если ground truth > 0, возможно: (a) индекс поисковика не покрывает, (b) публикации в Telegram/YouTube (вне web), (c) требует ручного submit."`
- Пользователю **явно сказать** в отчёте — не прятать 0
