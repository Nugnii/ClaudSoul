---
name: bridge-health
description: "Мониторинг 15 межслойных мостов: статус, метрики активности, здоровье связей между когнитивными слоями."
description_en: "Monitors the 16 inter-layer bridges: status, activity metrics, health of links between cognitive layers."
user-invocable: true
argument-hint: "[all — все мосты | L2 — мосты слоя | L2-L3 — конкретный мост]"
---

# Bridge Health — Inter-Layer Bridge Monitor

**Type:** worker

Мониторинг здоровья 15 мостов между когнитивными слоями L2-L7. Без мониторинга мосты существуют в документации, но неизвестно, работают ли они в реальности.

**MANDATORY READ:** Load `bridges/_index.md` из проекта ClaudSoul — индекс всех мостов.

## Step 1: Сканирование мостов

Прочитать все файлы `bridges/L*-L*-*.md`. Для каждого извлечь из YAML frontmatter:
- name, layers, status (implemented/designed/implicit), version

## Step 2: Сбор метрик активности

Для каждого моста — оценить активность по косвенным данным:

### L2↔L3 (Обучение на диалоге)
- Количество knowledge files с `outcome: communication` в `~/.claude/global-lessons/`

### L2↔L4 (Антиципаторное обучение)
- Наличие trajectory секции в SESSION.md + знания с `trigger: trajectory_*`

### L2↔L5 (Самоочищение)
- Наличие `.audit-history.json`, дата последнего аудита

### L2↔L6 (Проактивный intensity)
- Знания с `intensity: 0` (ожидаемые ошибки — проактивный режим работал)

### L2↔L7 (Со-эволюционное знание)
- Знания с `origin: co-cognition` или `trigger: co_cognition`

### L3↔L4 (Направление мысли)
- Наличие точек T1, T2... в SESSION.md Trajectory

### L3↔L5 (Качество коммуникации)
- Количество communication кейсов, тренд коррекций

### L3↔L6 (Коммуникативное предсказание)
- Gentle suggestions в prediction log SESSION.md

### L3↔L7 (Совместный язык)
- Наличие Shared Vocabulary в SESSION.md или memory

### L4↔L5 (Калибровка предсказаний)
- Prediction log: accuracy distribution (exact/adjacent/miss)

### L4↔L6 (Готовность к запросу)
- Prediction log: количество записей, confidence тренд

### L4↔L7 (Управление траекторией)
- Pivots с origin: co-cognition в trajectory

### L5↔L6 (Адаптивное предсказание)
- Изменение accuracy по типам предсказаний (тренд)

### L5↔L7 (Мета-со-когниция)
- Co-cognitive insights: count, impact тренд

### L6↔L7 (Генеративное мышление)
- Generative misses: промахи, ставшие инсайтами

## Step 3: Здоровье мостов

Для каждого моста определить статус здоровья:

| Статус | Условие |
|--------|---------|
| 🟢 Active | Есть данные за последние 7 дней |
| 🟡 Dormant | Данные есть, но старше 7 дней |
| 🔴 Inactive | Нет данных вообще |
| ⚪ Designed | Мост спроектирован, не реализован |

## Step 4: Матрица связности

Построить матрицу 6×6 (L2-L7) с символами здоровья:

```
     L2   L3   L4   L5   L6   L7
L2    ·   🟢   🔴   🟢   🟡   🔴
L3        ·    🟡   🔴   🟢   🔴
L4             ·    🔴   🟡   🔴
L5                  ·    🔴   🔴
L6                       ·    🟡
L7                            ·
```

## Step 5: Рекомендации

На основе матрицы:
1. **Слабые слои** — слои с большинством 🔴 мостов → приоритет реализации
2. **Сильные цепочки** — последовательности 🟢 мостов → усилить
3. **Quick wins** — implicit мосты с простым шагом к реализации

## Step 6: Отчёт

```
🌉 BRIDGE HEALTH — [date]
━━━━━━━━━━━━━━━━━━━━━━━

[Матрица связности]

📊 Статистика:
- 🟢 Active: N/15
- 🟡 Dormant: N/15
- 🔴 Inactive: N/15
- ⚪ Designed: N/15

🏆 Самые активные мосты:
1. L_↔L_ — [name] — [метрика]

⚠️ Рекомендации:
- [конкретная рекомендация]
```

Фильтры (аргументы):
- `all` — все 15 мостов (по умолчанию)
- `L2`, `L3`... — только мосты конкретного слоя
- `L2-L3` — детальный отчёт по одному мосту

## Rules

- Не фальсифицировать метрики — если данных нет, статус = inactive
- Implicit мосты могут быть active (работают через правила, не через код)
- Designed мосты никогда не 🟢 — пока нет реализации, они ⚪
- Рекомендации конкретны: "добавить origin: co-cognition в /learn" > "улучшить L2↔L7"

## Definition of Done

- [ ] All 15 bridge files scanned
- [ ] Activity metrics collected for each bridge
- [ ] Health status determined (🟢🟡🔴⚪)
- [ ] Connectivity matrix built
- [ ] Recommendations generated
- [ ] Report shown to user

**Version:** 1.0.1
**Last Updated:** 2026-07-29