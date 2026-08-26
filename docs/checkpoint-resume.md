# Checkpoint & Resume — Runtime State Persistence

> Механизм сохранения прогресса координаторов при обрыве сессии.

## Проблема

Сессия может оборваться в любой момент (timeout, crash, context overflow). Без checkpoint:
- Координатор не знает, какие workers завершились
- Работа повторяется с начала
- Knowledge log может содержать дубликаты

## Решение

### Checkpoint file

```
~/.claude/sessions/<session-id>/checkpoint.json
```

```json
{
  "coordinator": "knowledge",
  "started_at": "2026-04-16T10:00:00Z",
  "updated_at": "2026-04-16T10:15:00Z",
  "phase": "capture",
  "workers_completed": [
    {"worker": "learn", "ts": "2026-04-16T10:05:00Z", "artifact": "case-2026-04-16-name.md"}
  ],
  "workers_pending": [
    {"worker": "knowledge-audit", "reason": "overdue_count > 3"}
  ],
  "context": {
    "task": "краткое описание",
    "signals": ["error_fixed", "communication_insight"]
  }
}
```

### Lifecycle

```
Start coordinator
  → Write checkpoint (phase: "routing")
  → Route to worker
  → Worker completes
  → Update checkpoint (worker → completed)
  → Route to next worker (if any)
  → Update checkpoint (phase: "done")
```

### Resume protocol

При старте сессии, knowledge-activator проверяет:

1. Есть ли `checkpoint.json` в последней сессии?
2. Если `phase ≠ "done"` → незавершённая работа
3. Инжектировать:
   ```
   ⚠️ Незавершённая операция координатора [name]:
   Завершено: [workers_completed]
   Ожидает: [workers_pending]
   Контекст: [context.task]
   Рекомендация: запустить /knowledge auto для продолжения
   ```

### Интеграция

| Компонент | Действие |
|-----------|----------|
| knowledge-activator.sh | При startup: проверить checkpoint, инжектировать warning |
| /knowledge coordinator | При каждом шаге: обновлять checkpoint |
| session-collector.sh | При Stop: если checkpoint.phase ≠ done → warning |

### Когда НЕ нужен checkpoint

- Одиночный worker (/learn, /retro) — слишком быстро для обрыва
- Только audit/health — idempotent, можно перезапустить

### Когда НУЖЕН

- Координатор запустил 2+ workers последовательно
- Pipeline (будущий v0.7.2)
- /autoresearch (длинные циклы)

## Реализация в координаторе

Добавить в SKILL.md координатора:

```
После каждого завершённого worker'а:
1. Записать результат в knowledge-log.jsonl
2. Обновить checkpoint.json (worker → completed)
3. Если есть pending workers → продолжить
4. Если все done → checkpoint.phase = "done"
```

## File cleanup

Checkpoint файлы старше 7 дней удаляются session-collector'ом при Stop.
