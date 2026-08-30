# ClaudSoul — CLAUDE.md

> Система самообучения для Claude Code

<!-- narrative-start -->
<!-- narrative-end -->

## 1. О проекте

ClaudSoul — система управления знаниями и самообучения для AI-агентов. Не отдельное приложение, а набор скиллов, правил и структур файлов, которые превращают Claude Code в самообучающегося агента.

Когнитивная модель из 7 слоёв (слои 1-6 несут собственный код с v1.0.9; слой 7
наблюдается в данных, но своего кода не имеет — см. секцию 5 и таблицу слоёв в README):
1. Persistence — SESSION.md, CLAUDE.md, global-lessons, memory, git
2. Knowledge — case/pattern/principle с якорями, FSRS decay, кросс-доменный перенос
3. Communication — intent gaps, decision trails, satisfaction signals, interlocutor model
4. Thought Trajectory — отслеживание развития идей, гипотезы о направлении
5. Meta-Cognition — рефлексия над процессом обучения, метрики здоровья
6. Prediction — silent prep, gentle suggestion, proactive action
7. Co-Cognition — совместное мышление, конструктивное несогласие

## 2. Стек

| Компонент | Технология |
|-----------|-----------|
| Знания, правила, скиллы | Markdown + YAML frontmatter |
| Установка | Shell scripts |
| Метаданные знаний | YAML v0.2 (confidence, impact, 9 якорей, demand) |
| Skills API | Claude Code native |
| Семантический поиск | сервер MCP (sqlite-vec + fastembed, работает с v1.0.10) |

## 3. Структура

```
ClaudSoul/
├── CLAUDE.md              # Этот файл
├── README.md              # Документация
├── PLAN.md                # План: что впереди, гипотезы, roadmap фаз
├── CHANGELOG.md           # История изменений
├── BACKLOG.md             # Долг проекта: только открытое + как файл живёт
├── BACKLOG-archive.md     # Разделы без открытых пунктов (свидетельства закрытий)
├── SESSION.md             # Лог сессий разработки
├── install.sh             # Скрипт установки на чистую машину
├── docs/
│   ├── architecture.md    # Когнитивная архитектура (7 слоёв)
│   ├── research.md        # Результаты исследований
│   └── decisions.md       # Архитектурные решения (ADR)
├── hooks/                 # 61 активный хук + 28 библиотек alive learning system + tests/
│   └── *.sh               # error-tracker, knowledge-activator, session-collector,
│                          # intrusiveness-tracker, trust-guard, output-language-check, ...
├── skills/                # 23 скилла: user-invocable + координатор + оркестратор
│   └── */SKILL.md         # /retro, /learn, /knowledge, /knowledge-audit, /skill-forge,
│                          # /quality-gate, /decompose, /pipeline, /enrich, /wiki, ...
├── templates/             # Шаблоны файлов
│   ├── CLAUDE.md.tmpl     # Шаблон проектного CLAUDE.md
│   ├── SESSION.md.tmpl    # Шаблон SESSION.md
│   └── knowledge.md.tmpl  # Шаблон записи знания (v0.2)
├── rules/                 # Глобальные правила
│   └── CLAUDE.md          # Мастер-копия глобальных правил (v0.2)
├── bridges/               # Inter-Layer Bridges (16 мостов, v0.5.7)
│   ├── _index.md          # Индекс мостов между слоями
│   └── L*-L*-*.md         # Формализованные мосты (L3↔L6, L2↔L6)
├── domains/               # Граф доменов (7 root + depth 1-2, v1.0.9)
│   ├── _roots.md          # Индекс 7 корневых доменов
│   └── *.md               # Узлы доменов (name, aliases, depth, связи)
├── knowledge/             # Seed базы знаний (для чистой установки)
│   ├── META.md            # Мета-правила эволюции знаний (v0.2)
│   └── *.md               # 10 принципов + 27 universal-паттернов (генерируется scripts/regen-seed.py)
├── scripts/               # regen-seed, count-stats, smoke-test, calibrate,
│   ├── publish-public.sh  # публикация снимка наружу: archive → exclude → redact → гейт
│   ├── backlog-recheck.sh # закрытый пункт долга остался ли закрытым (еженедельно)
│   ├── measurements.tsv   # реестр замеров: у каждого период и команда
│   ├── measurement-due.sh # просроченные замеры называются и запускаются
│   ├── knowledge-instrument-audit.sh # знание → инструмент: три уровня + очередь
│   ├── knowledge-independence.py # на чём стоит confidence: события или записанные поводы
│   ├── docs-inventory.sh  # документация описывает то, что есть, и только то, что есть
│   ├── docs-duplicates.sh # один факт описан в одном месте, а не в двух
│   ├── ci-status.sh       # исход CI для ЭТОГО коммита, а не для самого свежего прогона
│   ├── project-conformance.sh # настройка проекта совпадает с нынешним договором
│   ├── statusline-claudsoul.sh # строка статуса показывает нынешнюю фазу, а не выдуманную
│   ├── ab-authorization-replay.sh # расхождения классификаторов авторизации названы числом
│   ├── split-provenance-log.py # перекройки правила и провенанс подтверждений разнесены
│   └── publish/           # конфиг публикации (не публикуется: в нём реальные имена)
└── hooks/tests/           # 274 файлов тестов хуков + 24 mcp (см. секцию 5)
```

## 4. Правила разработки

**MANDATORY READ перед добавлением фичи / изменением кода:** `docs/development.md` — как добавлять фичи (хук/библиотека/скилл/знание/сервер), как менять код (характеризующий тест перед рефактором, единый источник, хирургические правки), как вести документацию (числа и статусы из генераторов, не руками; стражи). Архитектурные решения — `docs/decisions.md` (ADR).

### Версионирование и коммиты

| Правило | Действие |
|---------|---------|
| Версионирование | semver (major.minor.patch) |
| Коммиты | На русском, атомарные |
| Каждое изменение | → CHANGELOG.md |
| Каждая сессия | → SESSION.md |
| Архитектурные решения | → docs/decisions.md |

### Формат знаний (v0.2)

**MANDATORY READ:** Load `knowledge/META.md` — полная спецификация формата.

| Группа | Поля |
|--------|------|
| Обязательные | confidence (1-5), impact (1-5), outcome, status |
| Якоря (9) | domain, situation, trigger, stakes, actors, environment, circumstances, purpose, method |
| Demand | need, urgency, availability |
| Связи | related, edges (caused_by, similar_to, contradicts, led_to, specializes, generalizes) |

`reliability = confirmed_count - contradicted_count` (без ограничений)
`priority = impact × (1 + ln(1 + max(0, reliability)))`

### Seed-база знаний (`knowledge/`)

`knowledge/` — seed для чистой установки, **генерируется** из рабочей базы (`~/.claude/global-lessons`) скриптом `scripts/regen-seed.py`: все принципы (универсальны по определению) + паттерны со `scope: universal`; личные кейсы/сущности и `per-speaker` не шипаются; счётчики `confirmed_count`/`contradicted_count` сброшены к базовым (confidence/impact сохранены). **Не править руками** — правь рабочую базу и пересобирай. Перед релизом: `regen-seed.py --check` (падает при дрейфе). CI-страж: `mcp-server/tests/test_seed_integrity.py`.

### Skill contract

**MANDATORY READ:** Load `docs/skill-contract.md` — контракт для SKILL.md файлов.

Каждый скилл: YAML frontmatter, `**Type:** worker`, `## Definition of Done` с чекбоксами, Version + Last Updated.

### Глобальные правила
Мастер-копия: `rules/CLAUDE.md` → `~/.claude/CLAUDE.md` через install.sh (там же —
принцип неопределённости и прочие сквозные правила; здесь не дублируем — канон D1/D3).

## 5. Текущий статус

> Состояние на **v1.31.1** (2026-08-30). Это документ состояния: «как есть сейчас». Что менялось и когда — `CHANGELOG.md`;
> долг — `BACKLOG.md`; состояние мостов — `bridges/_index.md`. Хронику сюда не писать.

| Компонент | Состояние |
|-----------|-----------|
| Когнитивные слои 1-6 + каскадность | Реализованы кодом |
| Слой 7 (Co-Cognition) | Наблюдается в данных (записи `origin: co-cognition`), собственного кода не имеет; контур несогласия — код есть |
| Хуки alive learning system | 61 активный + 28 библиотек |
| Скиллы | 23: user-invocable + координатор + оркестратор |
| Знания, operational-контур | case/pattern/principle: 9 якорей, demand, edges, FSRS decay, кросс-доменный перенос; seed генерируется `regen-seed.py` |
| Знания, encyclopedic-контур | entity/fact/relation: /ingest, /enrich, /wiki; кросс-контурные аналогии |
| Мосты L2-L7 | 16 всего: 6 реализовано, 1 формализован, 3 неявных, 6 спроектировано |
| Конвейер L1→L2 | capture (activity-flush) → /compile (кросс-проектный) → нудж |
| Интрузивность (L6) | 4D gate + state classifier; авторизация — состояние задачи; budget-gate — исполнитель бюджета (ADR-010) |
| Разбор причин (модуль root-cause) | одна доктрина на всю систему из `hooks/root-cause-lib.sh`: порядок (проявления → цепочки → сверка → братья корня вбок → зависимости вниз), спуск двумя линиями (по исполнению и по входам узла), остановка по признаку корня — дробь специфичности и признак с одним последствием тяжелеют при подъёме и держат спуск; схождение доказывает родство, корней бывает несколько (ADR-016). Последствия починки — чек-лист регрессии. Поводов восемь, включая внешние события мира (красный CI своего коммита, откат, воскресшее закрытие пункта, сбой проверки дрейфа); у каждого пишется ИСХОД, включая успех стража, и след разбора — формы доктрины в тексте хода, по ним же определяется «цепочка произнесена» (ADR-017). Замеры: доля исходов, доля «сказал против промолчал», молчащие признаки, точность классификатора авторизации — окна в сессиях |
| Контуры самоконтроля | опровержение, метрики вмешательства с гейтом выборки, условия возврата долга гейтятся состоянием BACKLOG, замеры с реестром сроков, эскалации с возрастом |
| MCP-сервер | semantic search, 9 tools, sqlite-vec + fastembed |
| Визуализация | граф знаний 2D/3D + dashboard метрик; export/import Brain |
| Публикация наружу | снимок из git archive → exclude → replace → redact → согласование производных чисел → гейт по выходу (запреты + pytest по копии снимка); способ выбирается замером истории публичного репозитория: чистая → force-push (issues и звёзды живут), грязная → пересоздание |
| Обратимость установки | `install.sh --dry-run` печатает правки без записи; `uninstall.sh` снимает своё по сверке с репозиторием, чужие хуки и скиллы не трогает, база знаний не удаляется никогда |
| Ablation-замер | prereg-протокол 1.4 (`docs/ablation-protocol.md`): три плеча на одном наборе задач — Full / Core (плоское извлечение top-k) / Vanilla; контрасты Δ_all, Δ_structure (гейтится иерархией), Δ_memory. Запускалка end-to-end (`scripts/ablation/`: журнал, сэмплер с beacon, тени, чекер, анализ); фаза видима и защищена (маркер + сигнал + страж); ни одна задача не зарегистрирована, старт/закрытие — слово владельца |
| Документация модулей | .claude-docs/modules/ (трекается); страж module-doc-check: новый модуль → док в том же коммите |
| Долг | BACKLOG ClaudSoul (кросс-проектно) + локальный BACKLOG.md инициированного проекта (по cwd); архив не считается. Цикл проблемы: повод разбора → пункт с измеримым результатом и командой проверки → сверка при починке (`backlog-touch-check`) → закрытие с показанием → архив (☑ без «Проверки» и ⊘ без «Вердикта» не переносятся) |
| Session Registry | lifecycle, дельты, startup context |
| Автономность | автосканер, weekly knowledge audit, monthly bridge health |
| Тесты | 274 файлов тестов хуков + 24 mcp (121 mcp-тест); зелёные на macOS и в чистом контейнере Linux; drift-check по 7 парам |
