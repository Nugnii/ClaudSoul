---
name: ingest
description: "Добавить материал в базу знаний ClaudSoul (второй контур обучения). Запускай явно по /ingest или когда пользователь говорит «добавь в базу знаний», «запомни это», «внеси в базу», «разбери и запомни», «проанализируй и добавь», «изучи и сохрани». Принимает локальный файл (MD/TXT/PDF/DOCX/HTML), URL, текст-сниппет или изображение/скриншот. Извлекает сущности, факты и связи, сливает в глобальную базу знаний, показывает отчёт и ссылку на граф."
description_en: "Adds material to the ClaudSoul knowledge base (second learning contour). Run explicitly via /ingest or when the user supplies a document."
user-invocable: true
argument-hint: "<путь-к-файлу | URL | — для текста из чата>"
---

# Ingest — добавление материала в базу знаний

**Type:** worker

Переводит внешний материал (документ, ссылку, картинку, текст) в структурированные знания второго контура: сущности (`entity-*.md`), факты (`fact-*.md`), связи (`relation-*.md`) — всё в `~/.claude/global-lessons/`.

## Когда использовать

**Явный вызов:** `/ingest <путь или URL>` или `/ingest` + файл в контексте.

**Автотриггер по словам пользователя** (без слэш-команды):
- «добавь в базу знаний», «внеси в базу», «запомни это»
- «разбери этот документ и добавь», «проанализируй и сохрани»
- «изучи и запомни», «добавь это знание», «сохрани в свою базу»

⚠️ **НЕ триггериться** на одиночное «изучи это» / «разберись» — это обычная задача для текущего проекта, не запрос на обучение. Триггер срабатывает только когда явно упомянут контур обучения («в базу», «запомни», «добавь знание»).

## MANDATORY READ

- `~/.claude/global-lessons/META.md` — правила эволюции знаний, формула confidence, якоря.
- `references/extract-guide.md` — таксономия entity_type, confidence-by-source, slug convention.

## Step 0: Определить путь к движку ClaudSoul

Скилл работает из любого проекта, не только из ClaudSoul. Найти корень репо по цепочке:

```bash
# Резолвер репо — общий ~/.claude/bin/resolve-claudsoul-repo.sh (вынесен из inline-копий, ставит install.sh).
source "$HOME/.claude/bin/resolve-claudsoul-repo.sh" 2>/dev/null \
    || { echo "ERROR: нет ~/.claude/bin/resolve-claudsoul-repo.sh — запусти install.sh из корня ClaudSoul" >&2; exit 1; }
REPO=$(resolve_claudsoul_repo) || exit 1
PY="$REPO/mcp-server/.venv/bin/python"
INGEST="$PY -m ingest.cli"
```

Если `$PY` не существует — сообщить пользователю: «нужен `uv sync` в `$REPO/mcp-server/`». Не пытаться делать это сам.

## Step 1: Определить тип входа

По аргументу / контексту разбей на ветку:

| Тип | Признак | Что делать |
|-----|---------|-----------|
| **Локальный файл** | путь существует на диске, расширение `.md/.txt/.pdf/.docx/.html/.htm` | → Step 2 (Parse) напрямую |
| **URL** | строка начинается с `http://` или `https://` | → Step 1a (скачать) |
| **Изображение** | путь существует, расширение `.png/.jpg/.jpeg/.gif/.webp` | → Step 1b (прочитать как картинку) |
| **Текст из чата** | пользователь приложил текст без файла | → Step 1c (сохранить в файл) |

### Step 1a: URL → текст

```
Вызвать WebFetch(url=<url>, prompt="Извлеки основной контент страницы как markdown: заголовки, абзацы, списки. Сохрани структуру. Не добавляй ничего от себя.")
```

Записать результат в `/tmp/ingest-url-<timestamp>.md`. Использовать этот файл как input для Step 2.

Title по умолчанию — заголовок страницы (первая H1) или хост+путь.

### Step 1b: Изображение → текст

```
Вызвать Read(file_path=<image-path>) — Claude Code читает изображение мультимодально.
```

Опиши содержимое картинки развёрнуто (минимум 200 слов): что на ней, какой текст видно, какие объекты/люди/схемы. Если это скриншот с текстом — распознай текст как есть (OCR-стиль). Запиши это описание в `/tmp/ingest-image-<timestamp>.md` с заголовком `# <имя-файла>`.

Используй этот файл как input для Step 2.

### Step 1c: Текст из чата

Если пользователь вставил текст в чат без файла — сохрани как есть в `/tmp/ingest-text-<timestamp>.md`. Первой строкой добавь `# <title>` (если title известен) либо `# Ingested text <timestamp>`.

## Step 2: Parse

```bash
$INGEST parse "<path>" --title "<title>" > /tmp/parse-out.json
SOURCE_ID=$(jq -r .source_id /tmp/parse-out.json)
PARSED_PATH=$(jq -r .parsed_jsonl /tmp/parse-out.json)
```

Прочитать `$PARSED_PATH` — JSONL с блоками (heading/paragraph/list_item/table_row/code_block/quote), heading_path, page provenance.

Если `block_count == 0` — остановиться, сообщить. Не генерировать extract из пустоты.

## Step 3: Extract

**MANDATORY READ:** `references/extract-guide.md` — не продолжать без него.

Из `parsed.jsonl`:

1. **Сущности** — имена людей/компаний/концептов/событий/мест/работ/продуктов. Для каждой — имя, entity_type, domain, attributes.
2. **Факты** — отдельные утверждения о мире, не атрибуты конкретной сущности. fact_type ∈ {attribute, event, rule, definition}.
3. **Связи** — типизированные edges между сущностями (works_at, created, knows, part_of, caused_by, ...).

Правила:
- Confidence отдельных атрибутов/фактов **не выставлять вручную** — integrate пересчитает по `source_type` согласно формуле META.md.
- В `sources` использовать формат `<source_id>:b<block_id>` (блок) или `<source_id>:p<page>` (страница).
- В `entity_refs` и `from_entity`/`to_entity` использовать `entity-<slug>.md`, slug = lowercased name с заменой пробелов на `-`, без спец-символов. См. `extract-guide.md` § «Slug convention».
- НЕ выдумывать. Если в тексте нет утверждения — не добавлять.

Для URL — `source_type: "document"`. Для изображения — `source_type: "document"` с пометкой в `extracted_from: "image"`. Для текста из чата — `source_type: "document"` (если пользователь явно не сказал, что это его слова → тогда `self-report`).

## Step 4: Запись extract payload

Собрать JSON по схеме `extract_output`:

```json
{
  "source_id": "<SOURCE_ID>",
  "entities": [...],
  "facts": [...],
  "relations": [],
  "warnings": []
}
```

Записать в `/tmp/extract-<SOURCE_ID>.json`.

## Step 5: Integrate

```bash
$INGEST integrate /tmp/extract-$SOURCE_ID.json > /tmp/integrate-out.json
```

Если `jsonschema.ValidationError` — исправить payload и перезапустить. НЕ игнорировать.

## Step 6: Отчёт пользователю

По-человечески, без технического жаргона:

```
📥 Добавлено в базу знаний: <имя источника>

🧬 Новые сущности: X  (плюс Y обновлены)
📜 Новые факты: X  (плюс Y обновлены)
🔗 Новые связи: X

Посмотреть в графе знаний → открой дашборд: /dashboard
Либо открой граф напрямую: /graph
```

Если есть `entities_candidates` — отдельная строка: «⚠️ Требуют ручной проверки: [file1, file2] — возможны дубликаты».

## Rules

- Parse и Integrate — детерминированные, вручную не трогать
- Extract — ответственность скилла. Claude читает parsed.jsonl и выдаёт JSON по схеме
- `source_type` обязателен для каждого attribute/fact/relation source. По умолчанию `document` для файлов и URL
- Валидация integrate обязательна — не обходить
- Никогда не чистить `~/.claude/global-lessons/` — integrate только добавляет/сливает
- Если извлечено 0 entities — спросить пользователя: «В материале не нашёл именованных сущностей. Сохранить только факты?»

## Definition of Done

- [ ] Путь к движку ClaudSoul разрешён (Step 0)
- [ ] Определён тип входа и выполнен соответствующий Step 1*
- [ ] Parse отработал, source_id получен, parsed.jsonl доступен
- [ ] Extract guide прочитан, правила применены
- [ ] Extract payload валиден против `extract_output.json` schema
- [ ] Integrate завершён без ошибок
- [ ] Отчёт показан пользователю (человеческий язык, 5-8 строк)
- [ ] При `entities_candidates` — отдельная пометка о ручной проверке

**Version:** 0.2.2
**Last Updated:** 2026-07-29