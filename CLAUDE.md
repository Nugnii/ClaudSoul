# ClaudSoul — CLAUDE.md

> Система самообучения для Claude Code

<!-- narrative-start -->
<!-- narrative-end -->

## 1. О проекте

ClaudSoul — система управления знаниями и самообучения для AI-агентов. Не отдельное приложение, а набор скиллов, правил и структур файлов, которые превращают Claude Code в самообучающегося агента.

Когнитивная модель из 7 слоёв (слои 1-6 несут собственный код; слой 7 наблюдается
в данных, но своего кода не имеет — см. секцию 5 и таблицу слоёв в README):
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
| Метаданные знаний | YAML frontmatter по `knowledge/META.md` (confidence, impact, 9 якорей, demand) |
| Skills API | Claude Code native |
| Семантический поиск | сервер MCP (sqlite-vec + fastembed) |

## 3. Структура

Выборочно: показано то, на что ссылается этот документ; полный список — `git ls-files`.

```
ClaudSoul/
├── CLAUDE.md              # Этот файл
├── README.md              # Документация; README.ru.md — русская версия
├── PLAN.md                # План: что впереди, гипотезы
├── CHANGELOG.md           # История изменений; внутренний архив (не публикуется) — вынесенная хроника
├── VERSION                # Версия проекта, источник истины
├── BACKLOG.md             # Долг проекта: только открытое + как файл живёт
├── BACKLOG-archive.md     # Разделы без открытых пунктов (свидетельства закрытий)
├── SESSION.md             # Лог сессий разработки
├── install.sh             # Скрипт установки на чистую машину
├── uninstall.sh           # Снятие своего по сверке с репозиторием
├── bin/                   # claudsoul.js (канал npm, ADR-009), resolve-claudsoul-repo.sh
├── lib/                   # claude-md-merge.sh — слияние правил в проектный CLAUDE.md
├── launchd/               # plist автосканера, weekly knowledge-audit, monthly bridge-health, daily замеры
├── mcp-server/            # сервер MCP: server.py (9 tools), indexer.py, storage.py, brain.py, visualization/, tests/
├── .claude-docs/          # modules/ (доки модулей), specs/, dep-index.tsv, project-map.json, narrative и журнал активности
├── docs/
│   ├── architecture.md    # Когнитивная архитектура (7 слоёв)
│   ├── research.md        # Результаты исследований
│   └── decisions.md       # Архитектурные решения (ADR)
├── hooks/                 # 98 активных хуков + 34 библиотек alive learning system + tests/
│   └── *.sh               # error-tracker, knowledge-activator, session-collector,
│                          # intrusiveness-tracker, trust-guard, output-language-check, ...
├── skills/                # 24 скилла: user-invocable + координатор + оркестратор
│   └── */SKILL.md         # /retro, /learn, /knowledge, /knowledge-audit, /skill-forge,
│                          # /quality-gate, /decompose, /pipeline, /enrich, /wiki, ...
├── templates/             # Шаблоны файлов
│   ├── CLAUDE.md.tmpl     # Шаблон проектного CLAUDE.md
│   ├── SESSION.md.tmpl    # Шаблон SESSION.md
│   └── knowledge.md.tmpl  # Шаблон записи знания (формат — knowledge/META.md)
├── rules/                 # Глобальные правила
│   └── CLAUDE.md          # Мастер-копия глобальных правил (v0.2)
├── bridges/               # Inter-Layer Bridges (16 мостов)
│   ├── _index.md          # Индекс мостов между слоями
│   └── L*-L*-*.md         # По файлу на каждый из 16 мостов
├── domains/               # Граф доменов (7 root + depth 1-2)
│   ├── _roots.md          # Индекс 7 корневых доменов
│   └── *.md               # Узлы доменов (name, aliases, depth, связи)
├── knowledge/             # Seed базы знаний (для чистой установки)
│   ├── META.md            # Мета-правила эволюции знаний и формат записи
│   └── *.md               # 10 принципов + 67 universal-паттернов (генерируется scripts/regen-seed.py)
├── scripts/               # regen-seed, count-stats, smoke-test, calibrate,
│   ├── publish-public.sh  # публикация снимка наружу: archive → exclude → redact → гейт
│   ├── backlog-recheck.sh # закрытый пункт долга остался ли закрытым; `--archive` — «Проверки» архива
│   ├── measurements.tsv   # реестр замеров: у каждого период и команда
│   ├── measurement-due.sh # просроченные замеры: `check` называет, `run` запускает
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
└── hooks/tests/           # 689 файлов тестов хуков + 25 mcp (см. секцию 5)
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

### Формат знаний

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

`knowledge/` — seed для чистой установки, **генерируется** из рабочей базы (`~/.claude/global-lessons`) скриптом `scripts/regen-seed.py`: все принципы (универсальны по определению) + паттерны со `scope: universal`; личные кейсы/сущности и `per-speaker` не шипаются; счётчики `confirmed_count`/`contradicted_count` сброшены к базовым (confidence/impact сохранены); машинно-локальное вычищается — идентификаторы сессий и значения-пути, целиком являющиеся абсолютным путём (упоминание пути в прозе — история, её чистит `redact.sed` при публикации); родословная (`source_cases`) СОХРАНЯЕТСЯ, хотя названные кейсы не отгружаются — решение владельца 4 сентября 2026: ссылка говорит получателю, что за правилом стоят случаи и сколько их, а чистка стёрла бы это, не дав ничего взамен. **Не править руками** — правь рабочую базу и пересобирай. Перед релизом: `regen-seed.py --check` (падает при дрейфе). CI-страж: `mcp-server/tests/test_seed_integrity.py`.

### Skill contract

**MANDATORY READ:** Load `docs/skill-contract.md` — контракт для SKILL.md файлов.

Каждый скилл: YAML frontmatter, `**Type:**` (worker, coordinator, orchestrator или reference), `## Definition of Done` с чекбоксами, Version + Last Updated.

### Глобальные правила
Мастер-копия: `rules/CLAUDE.md` → `~/.claude/CLAUDE.md` через install.sh (там же —
принцип неопределённости и прочие сквозные правила; здесь не дублируем — канон D1/D3).

## 5. Текущий статус

> Состояние на **v1.37.4** (2026-11-23). Подробности компонентов — `docs/component-status.md`. Это документ состояния: «как есть сейчас». Что менялось и когда — `CHANGELOG.md`;
> долг — `BACKLOG.md`; состояние мостов — `bridges/_index.md`. Хронику сюда не писать.

| Компонент | Состояние |
|-----------|-----------|
| Когнитивные слои 1-6 + каскадность | Реализованы кодом |
| Слой 7 (Co-Cognition) | Наблюдается в данных (записи `origin: co-cognition`), собственного кода не имеет; контур несогласия — код есть |
| Хуки alive learning system | 98 активных + 34 библиотек |
| Граница хода (Stop) | синхронны только дешёвые хуки и те, чей вывод перезапускает ход; сборщик, completion-gate, `declared-problem-recorded` и `carrier-growth-check` — фоновые (`async`, D1000, D1235); собственную цену синхронных мерит `scripts/stop-hook-latency.sh`, писатели BACKLOG.md сверяют файл перед записью |
| Скиллы | 24: user-invocable + координатор + оркестратор |
| Знания, operational-контур | case/pattern/principle: 9 якорей, demand, edges, FSRS decay (дни опыта, календарь — фоллбек), кросс-доменный перенос; seed генерирует `regen-seed.py`; двусторонность ссылок кейс ↔ родитель — `hooks/lib/link_symmetry.py` |
| Знания, encyclopedic-контур | entity/fact/relation: /ingest, /enrich, /wiki; кросс-контурные аналогии |
| Мосты L2-L7 | 16 всего: 6 реализовано, 1 формализован, 3 неявных, 6 спроектировано |
| Конвейер L1→L2 | capture (activity-flush) → /compile (кросс-проектный) → нудж |
| Интрузивность (L6) | 4D gate + state classifier; авторизация — состояние задачи; budget-gate — исполнитель бюджета (ADR-010) |
| Разбор причин (модуль root-cause) | одна доктрина из `hooks/root-cause-lib.sh` (ADR-016, ADR-017): проявления → цепочки → сверка → братья корня → зависимости. Разбор кончается картой `ROOTS.md`, её исполняет и сверяет `scripts/root-map.py`. Нынешний лес — 6 корней, порядок починки прибор считает из связей. Исход разбора читается по действиям хода, актор вызова — по `agent_id` (`hooks/paths-lib.sh`). Отказ стража снимает исход `scripts/outcome.sh`, сверенный с записью разбора для СВОЕГО повода, а не всех поводов хода (пункт, которого не было или который изменился с первого взгляда стража на этот повод — снимок у каждого повода свой, — с корнем из карты и адресом по первой цели записи или предмету повода; новое знание; довод «показалось»; сверку повторяет страж), либо след разбора — не чтения, не речь и не голая правка бэклога (D1035, ADR-025, D1104, D1106, D1108–D1110, D1115, D1116); сверщик на Stop пишет `recorded` только за сверенный исход, тронутый носитель — `touched` (D1107); бьёт по механизму, не по записи (D1036); обрывы фильтра и доля отказов не по механизму мерятся по сроку |
| Контуры самоконтроля | опровержение, метрики вмешательства с гейтом выборки, условия возврата долга, реестр замеров со сроками, эскалации; контракт результата инструмента сверяется поведением — `scripts/instrument-result-measured.sh` ищет свидетеля, красного на выпотрошенном инструменте (ADR-021) |
| MCP-сервер | semantic search, 9 tools, sqlite-vec + fastembed |
| Визуализация | граф знаний 2D/3D + dashboard метрик; export/import Brain |
| Публикация наружу | `scripts/publish-public.sh`: снимок из git archive → exclude → маркер `.public-snapshot` → redact → числа по снимку (`scripts/doc-claims.tsv`) → гейт по выходу (запреты, pytest и набор хуков в контейнере `scripts/measure-linux-parity.sh`) → свидетельство свежего критика → журнал `state/publications.jsonl` |
| Обратимость установки | `install.sh --dry-run`; `uninstall.sh` снимает своё по сверке с репозиторием, базу знаний не трогает; перенос в `~/.claude` идёт через журнал `lib/carry-log.sh` — приёмник, правленный после переноса, называется, а не перезаписывается (ADR-019) |
| Ablation-замер | prereg-протокол 1.4 (`docs/ablation-protocol.md`): плечи Full / Core / Vanilla, запускалка `scripts/ablation/`; регистраций 2, классификаций 2, eligible 0, завершённых пар 0; старт и закрытие — слово владельца |
| Документация модулей | .claude-docs/modules/ (трекается); страж module-doc-check: новый модуль → док в том же коммите |
| Рода дефекта | единица работы с долгом — РОД, а не место. Реестр `scripts/defect-class-carriers.py`: 15 родов, буквы A–O; признак с контрпримером и измеренной точностью заведён у 11, у C, I, N, O — исход «не заведён»; контрпримеры подаются машинно (`test_defect_registry_counterexamples.sh`); `--genus <буква>` печатает род |
| Долг | BACKLOG.md ClaudSoul + локальный BACKLOG проекта. Цикл: повод разбора → пункт с корнем из карты (R<N> либо «не дефект») и командой «Проверки» → открытый пункт с не-красной «Проверкой» или без корня из карты не записывается (`backlog-open-write-guard`); починка входит в main только с пунктом и корнем — слиянием (`merge-root-gate`) и прямым коммитом в любой форме команды (его судит ловушка git `commit-msg` судимого репозитория, ставит `commit-trap.sh --install`; обход `commit-msg` агентом снимает ловушка `post-commit`) → зелёная сторона `green_<ID>` в `test_backlog_green_side.sh` → закрытие с показанием (пункт с путём в `hooks/` — только со строкой «Скептик.» opus, D1137) → completion-gate на Stop → архив |
| Session Registry | lifecycle, дельты, startup context |
| Автономность | автосканер, weekly knowledge audit, monthly bridge health, daily прогон просроченных замеров |
| Тесты | 689 файлов тестов хуков + 25 mcp (142 mcp-теста); зелёные на macOS; CI — набор хуков в контейнере `ubuntu:26.04` рецептом замера `suite-linux` (coreutils uutils, версия закреплена), закрытый репозиторий — на домашнем сервере (исполнитель `home-server`), открытый снимок — на машинах GitHub; drift-check по 10 парам; ход прогона — `state/suite-run.tsv`, дорогие тесты — `scripts/costly-tests.sh` |
