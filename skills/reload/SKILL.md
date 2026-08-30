---
name: reload
description: "Перечитать базу знаний и контекст проекта без перезапуска сессии. Полезно при параллельных сессиях."
description_en: "Re-reads the knowledge base and project context without restarting the session. Useful with parallel sessions."
user-invocable: true
argument-hint: "[knowledge | session | all]"
---

# Reload — Hot Reload Knowledge & Context

**Type:** worker

Перечитать базу знаний и/или контекст проекта внутри текущей сессии. Нужен когда параллельная сессия записала новые знания или обновила SESSION.md.

## Что перечитывать

| Аргумент | Что делает |
|----------|-----------|
| `knowledge` | Перечитать `~/.claude/global-lessons/` — показать новые/обновлённые файлы |
| `session` | Перечитать `SESSION.md` текущего проекта — восстановить контекст |
| `all` или без аргумента | И то, и другое |

## Алгоритм

### 1. Knowledge reload

1. Прочитать ВСЕ файлы в `~/.claude/global-lessons/` (кроме META.md и .audit-history.json)
2. Для каждого — извлечь name, type, confidence, impact, last_confirmed, status
3. Показать сводку:
   - Всего знаний: N
   - Новые с начала сессии (если можно определить): список
   - Top-3 по priority (impact × (1 + ln(1 + reliability)))

### 2. Session reload

1. Прочитать SESSION.md текущего проекта (если есть)
2. Показать последнюю запись (## блок)
3. Принять как текущий контекст

### 3. Отчёт

```
🔄 RELOAD — [дата время]
━━━━━━━━━━━━━━━━━━━━━━

📚 Knowledge: N знаний загружено
   [Новые: file1.md, file2.md] (если есть)
   Top-3: ...

📋 Session: [последняя запись из SESSION.md — заголовок]
   Состояние: ...
   Следующие шаги: ...

✅ Контекст обновлён
```

## Rules

- Не модифицировать файлы — только читать
- Показывать кратко, не дублировать содержимое файлов целиком
- Если SESSION.md нет — сообщить, не падать
- Если global-lessons пуста — сообщить, не падать

## Definition of Done

- [ ] Requested scope reloaded (knowledge / session / all)
- [ ] Summary shown with counts and top items
- [ ] No files modified

**Version:** 1.0.1
**Last Updated:** 2026-07-29