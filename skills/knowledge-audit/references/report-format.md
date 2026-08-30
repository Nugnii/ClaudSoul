# Knowledge Audit Report Formats

## Audit history schema

Save to `~/.claude/global-lessons/.audit-history.json`:

```json
{
  "audits": [
    {
      "date": "YYYY-MM-DD",
      "total": N,
      "cases": N,
      "patterns": N,
      "principles": N,
      "depth_ratio": N,
      "freshness": N,
      "avg_reliability": N,
      "max_reliability": N,
      "overdue_count": N,
      "contradiction_ratio": N,
      "outcome_error": N,
      "outcome_success": N,
      "outcome_communication": N,
      "injections_total": N,
      "unique_injected": N,
      "hit_rate_pct": N,
      "avg_injection_score": N.N
    }
  ]
}
```

## Quick report format

```
📊 АУДИТ БАЗЫ ЗНАНИЙ — [дата]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 Всего: N знаний (C cases, P patterns, R principles)
📈 Depth ratio: N% [здоровье: ✅|⚠️|❌]
🔄 Freshness: N% [здоровье: ✅|⚠️|❌]
🎯 Avg reliability: N.N | Max: N
⏰ Просрочено: N знаний
⚠️ Противоречия: N% [здоровье: ✅|⚠️|❌]

📋 Распределение: error:N | success:N | communication:N

💉 Injection: N инжекций, hit_rate N%, avg score N.N
   Top: [самое частое знание] (N раз)

[Тренд vs прошлый аудит если есть: ↑↓→ для каждой метрики]
```

## Full report format

Quick report plus:

```
🔍 ДЕТАЛИ
━━━━━━━━

⏰ Просрочены (требуют ревью):
  1. [name] — просрочено N дней, reliability:N, impact:N
  2. ...

🚀 Кандидаты на промоушен:
  1. [name] → pattern (reliability:N, impact:N)
  2. ...

⚠️ Подозрительные:
  1. [name] — contradicted:N ≥ confirmed:N
  2. ...

💀 Мёртвые (нет подтверждений, > 30 дней):
  1. [name]
  2. ...

📊 TOP-5 по reliability:
  1. [name] — reliability:N, priority:N.N
  2. ...

🕳️ Пробелы:
  - [описание пробела]

💉 Injection Analytics:
  Всего инжекций: N | Уникальных: N | Hit rate: N% | Avg score: N.N
  Top-5:
    1. [file] (N раз, avg score N.N)
    2. ...
  Никогда не инжектировались:
    - [pattern/principle file] — проверить якоря
```
