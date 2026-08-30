---
name: skill-review
description: "Проверка SKILL.md на соответствие контракту ClaudSoul. Показывает нарушения и предлагает фиксы."
description_en: "Checks a SKILL.md against the ClaudSoul contract. Reports violations and proposes fixes."
user-invocable: true
argument-hint: "[путь к SKILL.md или директории скилла, или 'all' для проверки всех]"
---

# Skill Review — Contract Compliance Checker

**Type:** worker

**MANDATORY READ:** Load `docs/skill-contract.md` — полная спецификация контракта.

## What it does

Проверяет один или все SKILL.md файлы на соответствие контракту. Выдаёт отчёт: PASS / FAIL с конкретными нарушениями и предложенными фиксами.

## Process

### Step 1: Determine scope

- Если аргумент = `all` или не указан → проверить все скиллы в `skills/`
- Если аргумент = путь к файлу → проверить один файл
- Если аргумент = имя скилла → найти `skills/{name}/SKILL.md`

### Step 2: Load contract

Read `docs/skill-contract.md` — источник истины для проверок.

### Step 3: Run checks

Для каждого SKILL.md выполнить проверки:

#### Обязательные элементы (FAIL если отсутствует)

| # | Проверка | Что искать |
|---|----------|------------|
| 1 | YAML frontmatter | Блок `---` в начале файла с `name`, `description`, `user-invocable` |
| 2 | description длина | `description` ≤ 200 символов |
| 3 | description кавычки | Если `description` содержит `:` — должна быть в кавычках |
| 4 | `**Type:**` | Строка `**Type:** worker` (или другой валидный тип) |
| 5 | Definition of Done | Секция `## Definition of Done` с хотя бы одним `- [ ]` чекбоксом |
| 6 | Version | Строка `**Version:** X.Y.Z` в конце файла |
| 7 | Last Updated | Строка `**Last Updated:** YYYY-MM-DD` в конце файла |

#### Запреты (WARN если найдено)

| # | Проверка | Что искать |
|---|----------|------------|
| 8 | Пассивные ссылки | `See `, `Per `, `Read ... first` без `MANDATORY READ:` |
| 9 | Changes секция | `## Changes` или `### Changes` |
| 10 | Длина файла | > 400 строк |
| 11 | Parent/Coordinator | `**Parent:**` или `**Coordinator:**` (нарушает worker independence) |

### Step 4: Build report

Для каждого файла:

```
### {skill-name} — {PASS|FAIL}
{если FAIL:}
  FAIL:
  - #{номер}: {описание нарушения}
    Fix: {конкретное исправление}
{если WARN:}
  WARN:
  - #{номер}: {описание}
    Suggest: {рекомендация}
```

### Step 5: Summary

```
## Skill Review Summary

| Skill | Status | Fails | Warns |
|-------|--------|-------|-------|
| retro | PASS   | 0     | 0     |
| learn | FAIL   | 1     | 1     |
| ...   | ...    | ...   | ...   |

Total: N skills, M passed, K failed
```

### Step 6: Offer fixes

Если есть FAIL — предложить конкретные исправления для каждого:
- Показать что добавить/изменить
- Спросить: "Применить фиксы? (все / выборочно / нет)"
- Применить только после подтверждения

## Rules

- Контракт (`docs/skill-contract.md`) — единственный источник истины. Не выдумывать дополнительные требования
- FAIL = нарушение обязательного элемента. WARN = нарушение рекомендации
- Не модифицировать файлы без подтверждения
- При проверке `all` — проверять только `skills/*/SKILL.md` в репозитории ClaudSoul

## Definition of Done

- [ ] Все файлы в scope проверены по контракту
- [ ] Отчёт с PASS/FAIL/WARN показан пользователю
- [ ] Для FAIL предложены конкретные фиксы
- [ ] Фиксы применены только после подтверждения

**Version:** 1.0.1
**Last Updated:** 2026-07-29