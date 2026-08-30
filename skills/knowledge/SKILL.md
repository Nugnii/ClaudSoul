---
name: knowledge
description: "L2 координатор знаний: routing к /learn, /retro, /knowledge-audit, /bridge-health по контексту. Единая точка входа."
description_en: "L2 knowledge coordinator: routes to /learn, /retro, /knowledge-audit, /bridge-health by context. Single entry point."
user-invocable: true
argument-hint: "[capture|audit|health|auto] [контекст]"
---

# Knowledge — L2 Coordinator

**Type:** coordinator

Единая точка входа для всех операций со знаниями. Анализирует контекст, направляет к нужному worker'у, отслеживает результаты.

**MANDATORY READ:** Load `references/routing-rules.md` — правила маршрутизации.
**MANDATORY READ:** Load `references/result-contract.md` — контракт результатов worker'ов.

## Зачем координатор

| Без координатора | С координатором |
|-----------------|-----------------|
| Хуки независимо предлагают /learn, /retro | Единая логика: что, когда, почему |
| Пользователь решает какой скилл | Автоматический routing по контексту |
| Нет tracking что сделано за сессию | Session knowledge log |
| Пропущенные знания обнаруживаются поздно | Гарантия: ничего не потеряно |

## Step -1: Resume check

Проверить `~/.claude/sessions/*/checkpoint.json` — есть ли незавершённая операция:
- Если `phase ≠ "done"` → показать: "Незавершённая операция: [context.task]. Продолжить? (workers_pending)"
- Если пользователь подтверждает → перейти к Step 3 с pending workers
- Если нет → начать заново (checkpoint.phase = "abandoned")

## Step 0: Определить режим

| Аргумент | Режим | Что делает |
|----------|-------|-----------|
| `capture` | Захват знания | → routing к /learn или /retro |
| `audit` | Аудит | → /knowledge-audit |
| `health` | Здоровье мостов | → /bridge-health |
| `auto` или без аргумента | Автоматический | → анализ контекста → routing |

## Step 1: Анализ контекста (режим auto)

Оценить текущую ситуацию:

| Сигнал | Вес | Направление |
|--------|-----|-------------|
| Были 2+ ошибки Bash | +3 | capture (error) |
| Только что починили баг | +3 | capture (error) |
| Была коррекция от собеседника | +2 | capture (communication) |
| Задача решена гладко | +1 | capture (success) |
| Прошло > 7 дней с последнего аудита | +2 | audit |
| Запрос о здоровье знаний/мостов | +3 | health |
| Конец сессии (Stop) | +1 | capture (scan for uncaptured) |

## Step 2: Routing — выбор worker'а

### Capture routing (знание нужно записать)

```
Сигнал → Severity Assessment → Worker
```

| Severity | Условие | Worker |
|----------|---------|--------|
| **Deep** | 3+ попытки починки, нетривиальная корневая причина, цепочка ошибок | `/retro` |
| **Quick** | 1-2 попытки, понятная причина, быстрый захват | `/learn` |
| **Skip** | Тривиальная опечатка, уже записанное знание | Ничего |

Дополнительно определить тип:
- `error` — ошибки, баги, неверные подходы
- `success` — удачная стратегия, сработавший подход
- `communication` — intent gap, коррекция, аналогия от собеседника

### Audit routing

| Условие | Worker |
|---------|--------|
| Общий запрос о знаниях | `/knowledge-audit quick` |
| Детальный анализ | `/knowledge-audit full` |
| Мосты между слоями | `/bridge-health` |
| Конкретный мост | `/bridge-health L2-L3` |

## Step 3: Делегирование

Передать управление выбранному worker'у с контекстом:

```
→ /learn [тип] [контекст]
→ /retro [описание]
→ /knowledge-audit [quick|full]
→ /bridge-health [фильтр]
```

## Step 4: Запись результата + checkpoint

После завершения worker'а:

1. **Записать результат** в session artifact:
```
~/.claude/sessions/knowledge-log.jsonl
```
Формат строки:
```json
{"ts":"ISO","worker":"learn|retro|audit|bridge","type":"error|success|communication|audit","result":"case-file.md|report","trigger":"auto|user|hook"}
```

2. **Обновить checkpoint** (если запущено 2+ workers):
```
~/.claude/sessions/<session-id>/checkpoint.json
```
- Перенести worker из `workers_pending` в `workers_completed`
- Если все workers завершены → `phase: "done"`
- **MANDATORY READ:** Load `docs/checkpoint-resume.md` при работе с checkpoint

## Step 5: Gap detection (при capture)

После записи знания — быстрая проверка:
1. Есть ли в текущей сессии **незахваченные события**?
   - Ошибки без /learn
   - Коррекции без записи
   - Успехи без фиксации
2. Если да — предложить: "Ещё N событий не записано. Записать?"

## Rules

- Координатор НЕ дублирует работу worker'ов — он только routing + tracking
- При неоднозначности — спросить одним вопросом: "Это глубокий разбор (/retro) или быстрый захват (/learn)?"
- Не создавать скилл для тривиальных событий (severity = Skip)
- Knowledge log — append-only, не перезаписывать
- Координатор user-invocable, но может быть вызван и автоматически (хуками)

## Definition of Done

- [ ] Режим определён (capture/audit/health/auto)
- [ ] Контекст проанализирован (auto mode)
- [ ] Worker выбран и вызван
- [ ] Результат записан в knowledge-log.jsonl
- [ ] Gap detection выполнен (capture mode)

**Version:** 1.0.1
**Last Updated:** 2026-07-29