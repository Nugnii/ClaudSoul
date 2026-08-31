---
name: init-project
description: "Завести проект ИЛИ проверить уже заведённый: сверяет CLAUDE.md, SESSION.md, документацию и память с нынешним договором и называет расхождения. В новом проекте создаёт недостающее, в существующем — только проверяет и ничего не переписывает. Запускать при начале работы в проекте и когда нужно убедиться, что настройка не отстала."
description_en: "Sets up a project OR audits an already-initialised one: compares CLAUDE.md, SESSION.md, docs and memory against the current contract and names the gaps. Creates what is missing in a new project; in an existing one it only checks and never overwrites."
user-invocable: true
argument-hint: "[описание проекта в нескольких словах]"
---

# Init Project

**Type:** worker

Set up a new project directory for productive work with Claude Code.

## Step 0 — проект уже заведён? Тогда это аудит, а не инициация

**Сначала выполни:**

```bash
bash ~/My\ Project/ClaudSoul/scripts/project-conformance.sh "$PWD"
```

Скрипт **только читает**. Он сравнивает настройку проекта с нынешним договором и по каждому
расхождению называет механизм, который из-за этого не работает.

| Вывод | Что делать |
|-------|-----------|
| `CLAUDE.md отсутствует` и расхождений много | Проект не заведён — иди по разделам ниже |
| Расхождения точечные | **Не переинициализировать.** Показать список собеседнику и закрывать по одному |
| Расхождений нет | Сказать об этом и спросить, что делаем сегодня |

**Никогда не перезаписывай существующие `CLAUDE.md` и `SESSION.md`.** В них живут написанные
руками бизнес-правила и история решений; перезапись необратима и незаметна. Недостающий
раздел дописывается, существующий — не трогается.

Строки со знаком `·` — справка, а не дефект: отличие от шаблона бывает осознанным (у самого
ClaudSoul `CLAUDE.md` намеренно короткий, потому что грузится каждую сессию целиком).

## What to create

### 1. CLAUDE.md in the project root

Create `CLAUDE.md` using the template from `~/.claude/templates/CLAUDE.md.tmpl` (if exists) or following this structure. Fill in by reading project files (package.json, README, src/, etc.):

```markdown
# [Project Name] — CLAUDE.md

> Этот файл — единый источник правды для Claude Code при работе с проектом.

## 1. О проекте
[Что это за проект — 1-2 предложения. Спросить пользователя если неясно.]

## 2. Стек технологий
| Слой | Технология | Версия |
|------|-----------|--------|
[Заполнить из package.json, requirements.txt, etc.]

## 3. Структура проекта
[Дерево ключевых директорий и их назначение]

## 4. Как запустить
- Dev: `...`
- Build: `...`
- Test: `...`

## 5. Бизнес-правила
[Спросить пользователя о критических правилах, которые нельзя нарушать]

## 6. Паттерны кода
[Именование файлов, архитектура, паттерны из существующего кода]

## 7. Git и деплой
[Как деплоить, куда, какие ограничения]

## 8. Текущий статус
[Что работает, что в процессе — спросить пользователя]

## 9. Правила для этого проекта
- Всегда обновлять SESSION.md после завершения значимой работы
- Тестировать изменения перед тем как отчитаться
- Следовать существующим конвенциям кода
- При работе с библиотеками — проверять актуальную документацию
- Коммиты на русском языке
```

### 2. `.claude-docs/` — documentation structure

```
.claude-docs/
├── sessions/    # Доклады по сессиям (YYYY-MM-DD_описание.md) — пишет агент
├── modules/     # Документация модулей (один файл на модуль)
└── refactoring/ # Артефакты рефакторинга (аудиты, карты процессов)
```

У каждого свой писатель, и он разный:

| Каталог | Кто пишет | Кто читает |
|---------|-----------|-----------|
| `sessions/` | агент по правилу `rules/CLAUDE.md` §Documentation | человек, следующая сессия |
| `modules/` | агент при изменении модуля | `docs-family-check.sh:208`, `claude-md-size-check.sh:58`, `auto-scanner.sh:208` |
| `refactoring/` | агент при рефакторинге | человек |

**Поправка к v1.16.0.** В том релизе `sessions/` и `refactoring/` были отсюда убраны как
«мёртвые». Вывод был неверный, и ошибка в рамке замера: я спрашивал, какой **хук или
скрипт** ссылается на путь, а писатель здесь — агент по правилу, не скрипт. Живой счёт на
2026-07-31 в ProjectA_NEW: `sessions/` 19 файлов, `refactoring/` 40 (последний 14 июля),
`modules/` 55 (28 июля). Требования возвращены.

Остальное в `.claude-docs/` появляется само и заводить руками не нужно:
`session-activity.md` (пишет `activity-flush-lib`, читает `/compile`), `narrative.md`
(пишет `session-start`, ведёт `/narrative`).

### 3. SESSION.md in the project root

Use `~/.claude/templates/SESSION.md.tmpl` if available, or:

```markdown
# Session Log

## [today's date] — Инициализация проекта
### Что сделано
- Создан CLAUDE.md с правилами проекта
- Инициализирована структура документации
- Настроено отслеживание сессий

### Текущее состояние
- [Описать что видим в проекте]

### Следующие шаги
- [Спросить пользователя что будем делать]

### Ключевые решения
- Инициализирована система документирования
```

### 4. BACKLOG.md in the project root

Use `~/.claude/templates/BACKLOG.md.tmpl`. Долг проекта живёт в файле с первого
дня: `session-collector.sh:262` читает локальный `BACKLOG.md` по cwd и поднимает
открытые пункты в сигналы сессии. Файл, который никто не создаёт при инициации, —
это читатель без писателя (класс «reformulation-tracker до v1.11»: механизм
читает то, чего не существует, и молчит годами). В существующем проекте файл
не создаётся автоматически — отсутствие называет аудит (Step 0, conformance).

### 5. Project memory directory

Ensure `~/.claude/projects/[project-path]/memory/` exists with a MEMORY.md index file.

### 6. Версионирование — для любого git-репозитория с кодом

Глобальные правила называют это «общесистемным правилом, не опциональным», а инициатор до
2026-07-31 не заводил ни того, ни другого — новый проект стартовал уже не по договору.

- **Носитель версии** — `VERSION` (или `package.json` / `pyproject.toml` / `Cargo.toml`).
  Один источник на проект. До первого прод-релиза — `0.X.Y`.
- **`CHANGELOG.md`** в корне, формат Keep a Changelog, на русском, с открытым блоком
  `## [Unreleased]` сверху.
- Коммиты — conventional (`feat:` / `fix:` / `docs:` / `refactor:` / `chore:` / `test:`).

Исключения: чистый dotfiles-конфиг и репозитории только с документами. При сомнении —
версионировать: дёшево добавить, дорого внедрять задним числом.

### 7. Project knowledge directory (v0.2)

If the project is likely to generate domain-specific knowledge, create:
```
knowledge/
└── META.md  # Copy from ~/.claude/global-lessons/META.md or ClaudSoul/knowledge/META.md
```

This is optional — most projects use only `~/.claude/global-lessons/` for cross-project knowledge.

## Process

0. **Прогнать `scripts/project-conformance.sh` (Step 0).** Если проект уже заведён —
   дальше идёт разбор расхождений, а не создание файлов заново
1. Read the project directory — understand what's there
2. Analyze code: package.json, README, src structure, config files
3. Create all items above, filling in as much as possible automatically
4. Show the user what was created
5. Ask them to verify/correct, especially:
   - Business rules (section 5)
   - Deploy process (section 7)
   - Current status (section 8)
6. Ask: "Что будем делать сегодня?"

## Definition of Done

- [ ] `project-conformance.sh` прогнан ДО любых правок; если проект заведён — ничего не перезаписано
- [ ] CLAUDE.md есть, все 9 разделов заполнены (существующий дополнен, не заменён)
- [ ] SESSION.md есть с записью (существующий дополнен, не заменён)
- [ ] `.claude-docs/` создан с `sessions/`, `modules/`, `refactoring/`
- [ ] Каталог памяти проекта существует
- [ ] Для git-репозитория с кодом: носитель версии и CHANGELOG.md заведены
- [ ] Собеседник подтвердил бизнес-правила и процесс деплоя

**Version:** 1.2.0
**Last Updated:** 2026-08-01