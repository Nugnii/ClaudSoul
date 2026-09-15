# Result Contract — Worker Output Format

## Зачем

Workers пишут результат в файл (artifact), координатор читает файл. Это:
- Переживает обрыв сессии (файл на диске, не в памяти)
- Позволяет resume: координатор видит что было сделано
- Структурировано: машиночитаемый формат, не парсинг текста

## Artifact Location

```
~/.claude/sessions/knowledge-log.jsonl
```

Append-only JSONL. Каждая строка — один результат worker'а.

## Schema

```json
{
  "ts": "2026-04-16T10:30:00Z",
  "session_id": "abc123",
  "worker": "learn|retro|knowledge-audit|bridge-health",
  "trigger": "auto|user|hook",
  "input": {
    "type": "error|success|communication|audit|health",
    "context": "краткое описание контекста"
  },
  "output": {
    "status": "completed|skipped|failed",
    "artifact": "case-2026-04-16-name.md",
    "action": "created|reinforced|contradicted|report",
    "summary": "одна строка результата"
  },
  "duration_estimate": "quick|deep"
}
```

## Worker-specific output

### /learn
```json
{
  "worker": "learn",
  "output": {
    "status": "completed",
    "artifact": "case-2026-04-16-brief-name.md",
    "action": "created",
    "promoted_to": null,
    "reinforced": null,
    "summary": "Записан кейс: [правило]"
  }
}
```

### /retro
```json
{
  "worker": "retro",
  "output": {
    "status": "completed",
    "artifact": "case-2026-04-16-brief-name.md",
    "action": "created",
    "attempts": 4,
    "root_cause": "описание",
    "promoted_to": "pattern-name.md",
    "summary": "Ретроспектива: [корневая причина], [правило]"
  }
}
```

### /knowledge-audit
```json
{
  "worker": "knowledge-audit",
  "output": {
    "status": "completed",
    "artifact": ".audit-history.json",
    "action": "report",
    "metrics": {
      "total": 30,
      "overdue": 3,
      "depth_ratio": 0.13
    },
    "summary": "Аудит: 30 знаний, 3 просрочены, depth 13%"
  }
}
```

### /bridge-health
```json
{
  "worker": "bridge-health",
  "output": {
    "status": "completed",
    "action": "report",
    "active": 5,
    "dormant": 3,
    "inactive": 4,
    "designed": 3,
    "summary": "Мосты: 5 active, 3 dormant, 4 inactive, 3 designed"
  }
}
```

## Error Codes

| Status | Значение |
|--------|----------|
| `completed` | Worker завершился успешно |
| `skipped` | Тривиальное событие, запись не нужна |
| `failed` | Worker не смог завершить (ошибка парсинга, файл недоступен) |
| `duplicate` | Знание уже существует, дубликат не создан |

## Retry Policy

| Status | Действие |
|--------|----------|
| `completed` | Ничего |
| `skipped` | Ничего |
| `failed` | Retry 1 раз. Если повторный fail → записать в лог, не блокировать |
| `duplicate` | Ничего, но проверить: может нужно reinforcement |
