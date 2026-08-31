---
name: knowledge-audit
description: "Аудит базы знаний: метрики здоровья, надёжность, decay, рекомендации. Измеряет рост системы."
description_en: "Audits the knowledge base: health metrics, reliability, decay, recommendations. Measures how the system grows."
user-invocable: true
argument-hint: "[full — полный отчёт | quick — только метрики]"
---

# Knowledge Audit — Health Check

**Type:** worker

Измеряет здоровье базы знаний и прогресс обучения. Без измерений система слепа.

**MANDATORY READ:** Load `~/.claude/global-lessons/META.md` — knowledge system rules.

## Step 1: Сканирование базы

Прочитать ВСЕ файлы в `~/.claude/global-lessons/` (кроме META.md). Для каждого извлечь из YAML frontmatter:
- name, type, outcome, confidence, impact, confirmed_count, contradicted_count, last_confirmed, status, domain, trigger, tags

## Step 2: Рассчитать reliability

```
reliability = confirmed_count - contradicted_count
priority = impact × (1 + ln(1 + max(0, reliability)))
```

## Step 3: Рассчитать FSRS decay

Источник формулы — `~/.claude/hooks/fsrs-lib.sh` (единственный авторитетный источник, shared с knowledge-activator). Не дублировать формулу inline.

```bash
source ~/.claude/hooks/fsrs-lib.sh

# Для каждого знания:
stability=$(fsrs_stability "$confirmed_count" "$impact")          # int days
overdue=$(fsrs_days_overdue "$last_confirmed" "$confirmed_count" "$impact")  # int (neg=fresh)
status=$(fsrs_review_status "$overdue")                           # fresh|due|overdue|critical
```

Для отчёта: группировать по `status`. Категории `overdue` и `critical` → кандидаты в Step 5 «Кандидаты на decay».

## Step 4: Метрики здоровья

| Метрика | Формула | Здоровое значение |
|---------|---------|-------------------|
| **total_count** | Общее количество | — |
| **depth_ratio** | (patterns + principles) / (cases + patterns + principles) | 10-20% |
| **freshness** | % с last_confirmed ≤ 30 дней | > 40% |
| **overdue_count** | Просрочивших next_review | < 30% |
| **avg_reliability** | Средний reliability | Растёт |
| **contradiction_ratio** | contradicted / confirmed | < 20% |
| **outcome_distribution** | error / success / communication | Сбалансировано |

## Step 5: Выявить аномалии

### Кандидаты на decay (просрочены)
Знания где `today > next_review`. Сортировать по overdue_days.

### Кандидаты на промоушен
- Cases с reliability ≥ 3, impact ≥ 3 → в pattern
- Patterns с кросс-доменным подтверждением → в principle

### Подозрительные
- `contradicted_count >= confirmed_count` → расследовать
- `reliability < 0` → кандидат на deprecation

### Мёртвые
- Ни разу не подтверждены, создано > 30 дней назад

### Пробелы
- Нет success / communication знаний → не сбалансировано

## Step 6: Bridge Health (краткая)

Быстрая проверка межслойных мостов (для полного отчёта — `/bridge-health`):

1. Посчитать знания с `origin: co-cognition` → активность L2↔L7, L5↔L7
2. Посчитать знания с `outcome: communication` → активность L2↔L3
3. Проверить дату последнего аудита → активность L2↔L5
4. Посчитать predictions в SESSION.md (если доступен) → активность L4↔L6

Показать краткую строку:
```
🌉 Мосты: N/15 active | co-cognition: N знаний | communication: N знаний
```

## Step 6b: Co-Cognition Health (мост L2↔L7, v1.20.0)

Агрегат уже посчитан `metrics-collector.sh` — читать секцию `## Co-cognition health (L2↔L7)` из `metrics.md`, не пересчитывать по файлам (у канала один писатель; та же дисциплина, что Step 8/8b/8c). В секции: доли origin, co_cognition_ratio, средний impact co-cognition против solo, триггеры.

Тренд `co_cognition_ratio` (проект моста: должен расти) — сравнить с прошлыми записями `.audit-history.json` (`co_cognition_count` / ядро).

## Step 8: Injection Analytics

Агрегат уже посчитан `metrics-collector.sh` — читать из `metrics.md` (**hit_rate**,
`Уникальных знаний инжектировано`, `Из них pattern/principle`, `Средний score`,
Top-5, never_injected), не парсить сырой JSONL. Логика та же, что в Step 8b.

Если всё же разбирать `injection-log.jsonl` руками — три обязательные оговорки:
- `select(.injected != false)` — с v1.11 логируется top-6, а инжектится top-3;
  ранги 4-6 это контрольная группа, в hit_rate они не входят.
- Числитель hit_rate считать только по `pattern-*|principle-*`: в логе есть ещё
  case/fact/relation от mcp-fallback, иначе доля уходит за 100%.
- `jq -rR 'fromjson? // empty'`, не `jq -r` — в логе 173 исторические битые строки
  (апрель-июнь 2026, утечка `|` из `name`), голый разбор обрывается на первой.
- never_injected = потенциальный dead weight (якоря слишком узкие)

## Step 8b: Intrusiveness trends (L6 gate, v1.3.2)

Параллельное здоровье системы — не знаниевое, а коммуникативное. Источник: `~/.claude/hooks/state/intrusiveness-history.jsonl` (одна JSONL строка на закрытую сессию, пишется `session-collector.sh` через `itr_append_history`). Агрегат уже посчитан `metrics-collector.sh` и лежит в `metrics.md` секция «Intrusiveness trends» — читать оттуда, не парсить сырой JSONL в SKILL.

Ключевые показатели:
- **gentle_acceptance_rate** — % принятых gentle suggestions. Целевое: > 50%. Если < 30% в last-20 — cost model miscalibrated.
- **override rate** — emergency overrides / все interventions. Целевое: < 20%. Рост > 20% → порог `silence_cost ≥ 4` сработал не по делу.
- **debt carryover** — % сессий с pending silence_debt на закрытии. Рост → окна для surfacing не ловятся.
- **trend (↑↓→)** — last-20 vs prev-20 по каждой метрике.

Формат отчёта:
```
🎚️ Intrusiveness (last 20 / prev 20):
  acceptance N% → N% (↑/↓/→)
  overrides N → N (↑/↓/→)
  debt carryover N% → N% (↑/↓/→)
```

Если сессий < 20 — показать кумулятив без trend-сравнения, отметить «недостаточно данных для H13/H14/H15».

Рекомендации (если предупреждения):
- `acceptance < 30%` → ревизия `user_profile.md`: какие gentle не принимаются? Топик? Таймингом? → `/learn communication`
- `override > 20%` → audit расчёта `silence_cost` в `bash-cost-detector.sh` / `intrusiveness-tracker.sh` — порог срабатывает ложно
- `debt carryover ↑` → session-collector не находит окон для surfacing, возможно нужно опустить порог с `silence_cost ≥ 3`

## Step 8c: Prediction health (мост L4↔L5, v1.19.0)

Агрегат уже посчитан `metrics-collector.sh` — читать секцию `## Prediction calibration (L4↔L5)` из `metrics.md`, не парсить SESSION.md руками (та же дисциплина, что Step 8/8b: у канала один писатель).

Показать: секций/решённых, accuracy по типам (topic|reaction|need|action|untyped), вердикты правила (< 40% → снизить confidence типа, > 80% → повысить). Если секция говорит «не измеряли» или «вердикт не выносится» (гейт выборки) — показать ровно это, не нули.

## Step 9: Сравнить с прошлым аудитом

Прочитать `~/.claude/global-lessons/.audit-history.json`. Показать тренд (↑↓→).

## Step 10: Сохранить и отчёт

**MANDATORY READ:** Load `references/report-format.md` — JSON schema + quick/full report formats.

Сохранить метрики в `.audit-history.json`. Показать quick (по умолчанию) или full (аргумент `full`).

## Rules

- Не удалять знания автоматически — только помечать и рекомендовать
- При первом аудите — не паниковать, это точка отсчёта
- Тон: нейтральный, фактический
- Рекомендации конкретные: "ревьюнуть X", не "улучшить знания"

## Definition of Done

- [ ] All knowledge files scanned and parsed
- [ ] Reliability and FSRS calculated for each
- [ ] Health metrics computed
- [ ] Anomalies identified (overdue, promotion candidates, suspicious)
- [ ] Intrusiveness trends read from metrics.md (if history.jsonl exists)
- [ ] Prediction calibration read from metrics.md (Step 8c; «не измеряли» показывается как есть)
- [ ] Audit history saved to `.audit-history.json`
- [ ] Report shown to user (quick or full)

**Version:** 1.4.0
**Last Updated:** 2026-08-07