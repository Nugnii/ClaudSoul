---
name: entity
description: "Показать, что база знаний ClaudSoul знает о сущности (человеке, компании, концепции, событии) — атрибуты, связанные факты, типизированные связи. Запускай по /entity <имя> или когда пользователь спрашивает «что ты знаешь о X», «покажи, что есть про X», «карточка сущности X». Только чтение, не редактирует."
description_en: "Shows what the ClaudSoul knowledge base knows about an entity (person, company, concept, event) — attributes, links, sources."
user-invocable: true
argument-hint: "<имя или slug>"
---

# Entity — просмотр сущности второго контура

**Type:** worker

Показывает frontmatter сущности из `~/.claude/global-lessons/entity-*.md` плюс всё, что с ней связано: факты (через `entity_refs`) и relations (через `from_entity`/`to_entity`).

Не редактирует. Для правки — открыть файл напрямую в редакторе.

## Step 1: Поиск

Определить путь к движку ClaudSoul (тем же способом, что в `/ingest`):

```bash
# Резолвер репо — общий ~/.claude/bin/resolve-claudsoul-repo.sh (вынесен из inline-копий, ставит install.sh).
source "$HOME/.claude/bin/resolve-claudsoul-repo.sh" 2>/dev/null \
    || { echo "ERROR: нет ~/.claude/bin/resolve-claudsoul-repo.sh — запусти install.sh из корня ClaudSoul" >&2; exit 1; }
REPO=$(resolve_claudsoul_repo) || exit 1
PY="$REPO/mcp-server/.venv/bin/python"
```

Запустить поиск:
```bash
$PY -m ingest.cli show-entity "<query>" > /tmp/entity.json
```

CLI умеет искать по:
1. **Точное имя файла** — `entity-techflow.md`
2. **Slug** — `techflow` → `entity-techflow.md`
3. **name или alias** — ищет match по `name` или `aliases` в frontmatter

Exit codes:
- `0` — нашёл одну сущность, JSON в stdout
- `3` — ambiguous (несколько matches по alias) — показать список и попросить уточнить
- `4` — not_found — предложить `/ingest` для добавления

## Step 2: Форматирование

Прочитать JSON и показать пользователю (NOT syntax highlighting — просто текст):

```
🧬 [name]  ([entity_type], confidence N/5)
Status: [status] | Aliases: [...] | Domain: [...]

📋 Атрибуты
  key: value (confidence N, source_type, N sources)
  ...

🔗 Связи к операционному контуру (edges)
  similar_to: pattern-X.md
  ...

📜 Связанные факты (N)
  [fact-1-description] (confidence N)
  ...

🌐 Связанные relations (N)
  [from] → [relation_type] → [to]  (confidence N)
  ...
```

Если какая-то секция пуста — опустить целиком, не показывать «нет фактов».

## Step 3: Подсказки по действиям

В конце — одна строка, если применимо:

- Если `entities_candidates` в недавней ingestion и эта сущность — одна из них: «⚠️ merged_candidate, проверьте edges similar_to и решите merge/keep».
- Если у сущности attributes пусты и facts/relations тоже: «Минимальная запись — можно расширить через `/ingest` на релевантном документе».
- Иначе подсказку не давать.

## Rules

- Только чтение. Не изменять файлы.
- JSON от CLI — source of truth, не парсить YAML повторно.
- Если найдено несколько matches — показать пронумерованный список, предложить вызвать снова с точным slug.
- Не сокращать attribute values — показывать полностью.
- Confidence attribute'а показывать рядом, не в отдельной колонке.

## Definition of Done

- [ ] CLI `show-entity` отработал (exit 0)
- [ ] Frontmatter показан человекочитаемо
- [ ] Все связанные facts перечислены (если есть)
- [ ] Все связанные relations перечислены (если есть)
- [ ] Пустые секции не отображаются
- [ ] При ambiguous/not_found показан осмысленный ответ и предложены следующие шаги

**Version:** 0.1.2
**Last Updated:** 2026-07-29