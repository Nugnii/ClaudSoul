# Compile — детальный механизм

> Перенос `compile.py` + `flush.py` (`coleam00/claude-memory-compiler`) и гигиены захвата (`thedotmack/claude-mem`), адаптировано под ClaudSoul. Этот файл — рабочая инструкция Step 2–7 скилла `/compile`.

## Вход и инкрементальность

### State-маркер `~/.claude/global-lessons/_compile-state.json`
```json
{
  "last_compiled": "2026-06-13T02:30:00+02:00",
  "processed": { "<source-file>": { "hash": "<sha256[:16]>", "compiled_at": "<iso>" } },
  "compile_count": 0
}
```
Инкрементальность по хешу (как `state.json` «ingested» в compile.py): источник перекомпилируется только если его хеш изменился. `all` — игнорировать state. `--dry-run` — не писать ни черновики, ни state.

### Источники сырья (брать существующие)
1. `~/.claude/global-lessons/_drafts/*.md` — auto-drafts `error-tracker` (готовое полусырьё).
2. **Машинный лог сессий по ВСЕМ проектам** — `*/.claude-docs/session-activity.md` от `activity-flush-lib.sh` (Stop): счётчики инструментов, файлы, коммиты и **промпты пользователя** (с v1.6.0). Захват пишет в `$cwd/.claude-docs/` каждого проекта (силос по дизайну хука) — поэтому `/compile` собирает файлы со всех корней. Локальный-только обход был дефектом v1.0.0: консолидировался лишь проект, из которого запущен `/compile`.

   Найти все файлы детерминированно (не полагаться на «вспомнить про glob»). Обёртка `bash -c` обязательна: `read -ra` — bash-only, а Bash-инструмент Claude Code может работать в zsh (там `read -ra` → `bad option: -a`, массив пуст, find находит 0). Корни переопределяются через `COMPILE_SCAN_ROOTS` (разделитель — двоеточие):
   ```bash
   bash -c 'ROOTS="${COMPILE_SCAN_ROOTS:-$HOME/My Project:$HOME/Documents/Claude/Projects}"
   IFS=":" read -ra _r <<< "$ROOTS"
   find "${_r[@]}" -name session-activity.md -path "*/.claude-docs/*" 2>/dev/null | sort'
   ```
   Из каждого файла брать блоки `## <дата>` в окне `[last_compiled, now]`. Каждый блок **тегировать проектом** (путь без `$HOME/` и без хвоста `/.claude-docs/session-activity.md`). Инкрементальность — по хешу каждого файла отдельно (`processed[<полный-путь>]`).

   **Дедуп пересечений:** одна сессия (`session <id>`) попадает в `.claude-docs/` и родителя, и подпапки (напр. `ProjectA_NEW` и `ProjectA_NEW/web`), когда cwd менялся в рамках сессии. Блоки с одинаковым `session <id>` + близким timestamp считать одним событием, брать самый полный.
3. Проектный `SESSION.md` — narrative-записи с датой в окне (локальный проект; кросс-проектная агрегация narrative — отдельный вопрос, пока не делаем).
4. Текущий transcript — только коррекции / промахи предсказаний в окне, ещё не в файлах.

## Гигиена: усечка больших полей (из claude-mem `prompts.ts`)

Любой файл/поле сырья > 16 000 символов читать усечённо, чтобы один гигантский лог не раздул контекст:
- head = первые **60%** бюджета (там канонический сигнал: путь, заголовок ошибки, команда),
- tail = последние **30%** (там финальный контекст / ошибки),
- между ними — явный маркер: `... <elided chars="N" original_size_chars="M" reason="oversize" /> ...`

Правило: описывать только видимую часть, **не выдумывать** содержимое усечённого диапазона. Маркер обязателен — он сообщает, что усечка произошла.

## Extract-промпт (адаптация `flush.py` + `compile.py`)

Применять к собранному сырью. Цель — не пересказ, а извлечение durable-знаний:

```
Ты — компилятор знаний ClaudSoul. Прочитай сырьё ниже (логи сессий, auto-drafts,
коррекции) и извлеки 3–7 РАЗЛИЧНЫХ durable-знаний формата v0.2.

Включай: решения с обоснованием, уроки/подводные камни, повторяющиеся паттерны,
коммуникативные инсайты (ложные допущения, intent gaps), сработавшие стратегии.

Пропускай: рутинные tool-вызовы и чтения файлов, тривиальный обмен, очевидное,
уточняющие реплики без содержания.

Для каждого знания:
- type: error | success | communication | reference
- rule: ОДНО конкретное actionable правило (не «быть внимательнее» — а «проверять X перед Y»)
- anchors (9): domain, situation, trigger, stakes, actors, environment, circumstances, purpose, method
- confidence (1), impact (1–5), demand (need/urgency/availability)

Если нечего извлечь — верни ровно: COMPILE_EMPTY
```

Якоря извлекать автоматически из контекста, не спрашивать.

## Дедуп против базы (index-guided, без эмбеддингов)

Карта = индекс существующих знаний: имена файлов `~/.claude/global-lessons/{case,pattern,principle}-*.md` + их `description`/`trigger`/`domain` из frontmatter. LLM рассуждает по индексу (подход `query.py`: читать индекс → выбрать релевантные → сверить), не по векторному сходству.

Решение на кандидата:
| proposed_action | условие | что записать |
|---|---|---|
| `UPDATE` | существует знание с похожим trigger+situation+domain, **не** противоречит | предложение: «подкрепляет `[name]`: confidence N→N+1, confirmed_count++, last_confirmed=today». НЕ редактировать live-файл |
| `CONTRADICTS` | противоречит существующему знанию | пометка: «противоречит `[name]` — требуется `/retro` для investigate WHY». Конфликт здесь не разрешать |
| `NEW` | совпадений в индексе нет | новый кандидат |

Это перенос правила compile.py «update existing if new info», но в режиме *предложения*, а не live-правки (дисциплина курирования ClaudSoul).

## Формат черновика

Путь: `~/.claude/global-lessons/_drafts/compile-YYYY-MM-DD-slug.md`

Header + тело по `skills/learn/references/case-template.md`:
```yaml
---
# compile-meta
proposed_action: NEW | UPDATE | CONTRADICTS
update_target: <name знания>        # только для UPDATE/CONTRADICTS
source_window: "<last_compiled> .. <now>"
source_files: [<откуда извлечено>]
needs_review: true                   # черновик, не live
# --- ниже стандартный frontmatter знания v0.2 (META.md) ---
confidence: 1
impact: <1-5>
...9 якорей, demand, edges...
---
<тело: что произошло / правило / why / how to apply>
```

`needs_review: true` и расположение в `_drafts/` гарантируют, что знание не попадёт в активную базу до промоушена через `/learn`.

## Формат отчёта (Step 7)

```
🧱 /compile: окно <last_compiled> .. <now> | проектов: P | источников: N | кандидатов: K
   (провенанс по проектам, напр.: ProjectA_NEW ×16, ClaudSoul ×2)

| # | proposed | кандидат (slug) | target | impact |
|---|----------|-----------------|--------|--------|
| 1 | NEW      | ...             | —      | 4      |
| 2 | UPDATE   | ...             | pattern-X | 3   |
| 3 | CONTRADICTS | ...          | principle-Y | 5 |

Промоушен: `/learn` поштучно, либо подтвердить пачкой. CONTRADICTS → `/retro`.
```

Если `COMPILE_EMPTY` — отчёт: «Нечего консолидировать за окно, state продвинут». Не выдумывать кандидатов.

## Source provenance

- `compile.py` / `flush.py` / `query.py` — `github.com/coleam00/claude-memory-compiler` (механизм компиляции, инкрементальность, index-guided retrieval, FLUSH_OK→COMPILE_EMPTY).
- усечка полей head/tail/`<elided>` — `github.com/thedotmack/claude-mem` `src/sdk/prompts.ts`.

**Version:** 1.1.0
**Last Updated:** 2026-06-14
