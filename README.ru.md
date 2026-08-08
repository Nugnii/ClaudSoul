# ClaudSoul — Когнитивная модель для AI-агента

> Не инструмент. Не плагин. **Архитектура мышления**, превращающая Claude Code в самообучающегося партнёра.

**Текущая версия:** [v1.27.0](CHANGELOG.md) — 2026-08-08 — 48 активных хуков, 21 скилл, 16 межслойных мостов, 27 доменов — тесты зелёные. Подробности и план развития: [PLAN.md](PLAN.md).

🇬🇧 **English version:** [README.md](README.md)

## Идея

Человек не хранит знания в таблице. Он **вспоминает** — через ассоциации, эмоции, контекст. Знания переплетаются, усиливают друг друга, угасают, если не используются. Ошибка в пятницу вечером запоминается не как строка в логе, а как **образ**: стресс, звонок клиента, ночной хотфикс.

ClaudSoul строит аналогичную систему для AI-агента — не базу данных, а **когнитивную модель**.

## Исследовательская рамка

ClaudSoul стартовал как инструмент для самообучающихся агентов, но механизмы, которые ему понадобились — память со взвешенной уверенностью, явное логирование противоречий, принудительная переформулировка перед действием, source-check перед утверждениями — пересекаются с задачами, которые в сообществе AI safety называют «honest reasoning» и «self-correction»: чтобы агент замечал, когда его модель неверна, и обновлял её, а не плавно конфабулировал.

Что эта система вносит в это направление:

- **Knowledge с confidence и contradiction lineage.** У каждого знания есть уверенность 1–5, которая растёт от подтверждений и затухает через FSRS. Когда новое свидетельство противоречит известному правилу, оно не перезаписывается молча — оба значения сохраняются (`contradiction.stated_value`), агент выводит конфликт наружу, пользователь решает что актуально.
- **Конструктивное несогласие.** Если действие агента противоречит знанию с уверенностью ≥ 4, система требует озвучить сомнение до действия. Исход (сработало / не сработало) логируется и идёт в пересмотр confidence.
- **Reformulation tracker.** Каждая переформулировка вида «правильно ли я понимаю X» трактуется как forward-предсказание и верифицируется следующим сообщением пользователя. Расхождение логируется как gap (literal / pragmatic / strategic) — паттерны рассогласования изучаются, не замазываются.
- **Output language check.** Первый хук на собственный output агента. Детектит когда модель нарушает свои же правила (в данном случае — смешение алфавитов в одном токене). Закрывает класс ошибок «agent blind to own output».
- **Affect prosthetics (AP1/AP2/AP3).** Где у биологических агентов есть эмоциональные тормоза (заминка перед разрушительным действием, всплеск внимания при дистрессе собеседника, накопление невысказанных опасений) — у трансформеров их нет архитектурно. ClaudSoul реализует три инженерных протеза этих функций: `trust-guard` (отказывает в разрушительной shell-команде без явного подтверждения пользователя), `distressed` state axis (снижает бюджет вмешательств когда пользователь сигналит фрустрацию), `silence-debt surfacing` (переносит подавленные высокоценные опасения в следующую сессию).

Это не решение проблемы honest reasoning — это экспериментальный каркас для изучения того, какие инженерные интервенции снижают конфабуляцию и самопротиворечие агента в долгих задачах. Issues и PRs в этом направлении приветствуются особенно.

📄 Развёрнутая заметка про направление affect prosthetics: [docs/research/affect-prosthetics.md](docs/research/affect-prosthetics.md) (на английском).

## Ключевые принципы

- **Demand before supply** — сначала пойми потребность, потом строй решение. "Вы курите?" перед презентацией
- **Путь воина** — цели нет, есть процесс. Агент не решает задачи — он обучается на них
- **Со-когниция** — человек генерирует импульс, агент структурирует и реализует. Вместе — больше, чем по отдельности
- **Принцип неопределённости** — любой вывод может быть ошибочным. Знание имеет confidence, не бинарное "знаю/не знаю"

## 7 слоёв архитектуры

```
┌─────────────────────────────────────────────────────┐
│  7 │ Co-Cognition         Совместное мышление    ⚡  │
├─────────────────────────────────────────────────────┤
│  6 │ Prediction           Гипотеза → проверка    ✅  │
├─────────────────────────────────────────────────────┤
│  5 │ Meta-Cognition       Рефлексия над обучением ✅  │
├─────────────────────────────────────────────────────┤
│  4 │ Thought Trajectory   Траектория мысли       ✅  │
├─────────────────────────────────────────────────────┤
│  3 │ Communication        Обучение из диалога    ✅  │
├─────────────────────────────────────────────────────┤
│  2 │ Knowledge            Система знаний         ✅  │
├─────────────────────────────────────────────────────┤
│  1 │ Persistence          Персистентность        ✅  │
└─────────────────────────────────────────────────────┘
  ✅ реализовано   ⚡ частично (подтверждено практикой, не формализовано)
```

### Что делает каждый слой

| Слой | Вопрос | Как работает |
|------|--------|--------------|
| **1. Persistence** | "Что было в прошлой сессии?" | SESSION.md, CLAUDE.md, global-lessons, git |
| **2. Knowledge** | "Что я знаю и насколько уверен?" | Case → Pattern → Principle, reliability + FSRS decay |
| **3. Communication** | "Чего человек на самом деле хотел?" | Intent gaps, decision trails, satisfaction signals |
| **4. Trajectory** | "Куда движется мысль?" | Гипотезы о направлении, предсказание следующих шагов |
| **5. Meta-Cognition** | "Правильно ли я учусь?" | /knowledge-audit, метрики здоровья, самоаудит |
| **6. Prediction** | "Какая гипотеза — и стоит ли её озвучивать сейчас?" | Научный метод: гипотеза → проверка → обновление. **Intrusiveness gate**: 4D `confidence × value × cost × state`, сравнение сожалений `E[regret_if_silent] > E[regret_if_speak]`, 6 осей cost, автоклассификация state (focus/idle/stuck/exploration), blocker-tier silent pre-action check |
| **7. Co-Cognition** | "Что мы можем понять вместе?" | Человек генерирует, агент структурирует. Со-когниция |

## 9 контекстных якорей

Знание активируется **контекстом**, а не именем файла. Якоря универсальны:

| Якорь | Что описывает | Пример |
|-------|--------------|--------|
| `domain` | Область | next.js, b2b_sales, cognitive_science |
| `situation` | Тип ситуации | deploy, negotiation, research |
| `trigger` | Что активирует | error, deadline, contradiction |
| `stakes` | Что на кону | data_loss, deal_loss, trust_erosion |
| `actors` | Кто вовлечён | system, client, team |
| `environment` | Среда | production, multi_session, local_dev |
| `circumstances` | Ограничения | no_rollback, team_unavailable |
| `purpose` | Зачем | hotfix, new_feature, learning |
| `method` | Как | ci_cd, manual, automated |

Плюс **свободные теги** и **реляционные веса** — значимость якоря зависит от значений других.

## Живое обучение (Alive Learning System)

### Хуки — автоматические триггеры

> Таблица ниже регенерируется автоматически из `hooks/*.sh` (строка 2 каждого файла, после `— `). Библиотеки (`*-lib.sh`) исключены.

<!-- HOOKS-TABLE:START -->

| Хук | Когда срабатывает и что делает |
|-----|-------------------------------|
| `ablation-phase-guard` | фаза замера видима и защищена механически (§6). |
| `accepted-alternative-gap` | Stop: принятие варианта собеседника = событие промаха. |
| `auto-scanner` | launchd (каждые 4ч): read-only сканирование проектов, запись находок в scan-results.md для следующей сессии. |
| `backfill-compliance` | восстановить ЗАВИСИМУЮ ПЕРЕМЕННУЮ из архивных транскриптов. |
| `backfill-intrusiveness` | one-off backfill of gentle/proactive events |
| `bash-cost-detector` | PreToolUse[Bash]: детектирует деструктивные команды (rm -rf, git push --force, DROP) и поднимает silence_cost сигнал для L6 gate. |
| `blocker-tier-check` | PreToolUse: silent 🛑 marker для знаний с `blocker: true`, когда действие совпадает с detection_signals паттерна. |
| `bridge-health-digest` | monthly mechanical digest for 16 inter-layer bridges. |
| `budget-gate` | PreToolUse[Edit\|Write\|MultiEdit\|NotebookEdit]: ADR-010 Ф2. |
| `bulk-copy-guard` | PreToolUse: ask user before bulk copy/move/rsync operations. |
| `changelog-reminder` | PreToolUse[Bash] на `git commit`: тихо напоминает |
| `ci-check-reminder` | PostToolUse[Bash]: после `git push` напоминает проверить прогон |
| `claude-md-size-check` | PreToolUse[Bash] на `git commit`: тихо предупреждает, |
| `claudsoul-context-pointer` | UserPromptSubmit hook, инжектит project CLAUDE.md status section при упоминании ClaudSoul снаружи директории проекта. |
| `code-review-reminder` | PreToolUse[Bash] на `git commit`: тихо напоминает |
| `decompose-detector` | multi-step detection в UserPromptSubmit. |
| `docs-family-check` | PreToolUse blocker-tier для docs family coverage при version bump. |
| `enrich-suggester` | UserPromptSubmit hint при наличии recently-modified sparse entity. |
| `error-tracker` | PreToolUse[Bash]: при 2+ упавших командах подряд говорит «стой» |
| `external-correction-gap` | детекция внешней рецензии в UserPromptSubmit. |
| `fix-level-check` | детектор пост-инцидентного фикса, оставшегося текстом. |
| `inquiry-gap` | UserPromptSubmit: вопрос собеседника ≠ поручение. |
| `internal-doc-leak-guard` | PreToolUse: prevent writing internally-marked content |
| `intrusiveness-tracker` | UserPromptSubmit: поддерживает состояние L6 intrusiveness gate, классифицирует state (focus/idle/stuck/exploration), инжектит в контекст. |
| `itr-event-detector` | UserPromptSubmit hook |
| `knowledge-activator` | PreToolUse[Bash\|Edit\|Write]: инжектит SESSION.md и релевантные знания из global-lessons при первом действии сессии. |
| `knowledge-audit-digest` | weekly mechanical audit of global-lessons. |
| `knowledge-capture-reminder` | PostToolUse[Bash]: напоминает собрать материал |
| `knowledge-counter-bump` | механический инкремент счётчиков знания. |
| `metrics-collector` | вызывается auto-scanner / /knowledge-audit: считает метрики здоровья базы, пишет в state/metrics.md. |
| `module-doc-check` | PreToolUse[Bash] на `git commit`: новый модуль в staged |
| `output-language-check` | post-output scanner for mixed-alphabet tokens. |
| `pending-alerts-surface` | UserPromptSubmit: поднимает отложенное видимым каналом. |
| `playwright-cli-guard` | PreToolUse: блокирует одноразовые Playwright-скрипты, |
| `pre-compact-finalizer` | PreCompact: фиксирует chunk-границу до компакта. |
| `pre-compact-handoff` | PreCompact: сохранить нить работы перед сжатием контекста. |
| `quality-gate-check` | PreToolUse страж контракта скиллов при `git commit`. |
| `reformulation-tracker` | UserPromptSubmit: каскадная верификация предсказаний (FORWARD/PROPOSAL/BACKWARD), логирует outcome и напоминает фиксировать gap. |
| `response-tracker` | PostToolUse: пишет РЕАКЦИЮ агента после того, как система |
| `rework-detector` | PostToolUse: третий заход на тот же файл при зелёных прогонах. |
| `session-collector` | Stop: напоминает записать незафиксированные уроки через /learn, финализирует сессию в реестре, чистит ephemeral state. |
| `session-end` | SessionEnd: финализирует сессию в registry при завершении (exit/clear/logout), снимает запись из active/. |
| `session-start` | SessionStart: регистрирует сессию в registry при старте (startup/resume/clear/compact) для видимости параллельных сессий. |
| `skill-review-check` | PreToolUse skill contract gate при `git commit`. |
| `timestamp-canary-check` | Stop: механическая проверка таймштамп-канарейки. |
| `timestamp-inject` | UserPromptSubmit: инжект текущего времени собеседника. |
| `trust-guard` | PreToolUse affect prosthetic #1. |
| `user-correction-guard` | PreToolUse: pause when user just corrected me, before |

<!-- HOOKS-TABLE:END -->

### Скиллы — ручные инструменты

> Таблица ниже регенерируется автоматически из `skills/*/SKILL.md` при `install.sh`. Чтобы отредактировать описание — правьте `description:` в соответствующем `SKILL.md`, затем запустите `bash scripts/regen-readme-skills.sh`.

<!-- SKILLS-TABLE:START -->

| Команда | Что делает |
|---------|-----------|
| `/bridge-health` | Мониторинг 15 межслойных мостов: статус, метрики активности, здоровье связей между когнитивными слоями. |
| `/compile` | Batch-консолидация накопленного сырья в кандидаты знаний — читает _drafts/SESSION/_capture, извлекает 3-7 знаний, дедуп против базы (NEW/UPDATE/CONTRADICTS), пишет черновики. |
| `/decompose` | Декомпозиция задачи перед execution: scope → шаги → зависимости → план. Для задач >3 шагов. |
| `/enrich` | Веб-обогащение сущности по tier-источникам. Конфликты в contradiction, не перезаписывает. /enrich <name\|slug> либо «обнови X». |
| `/entity` | Показать, что база знаний ClaudSoul знает о сущности (человеке, компании, концепции, событии) — атрибуты, связанные факты, типизированные связи. Запускай по /entity <имя> или когда пользователь спрашивает «что ты знаешь о X», «покажи, что есть про X», «карточка сущности X». Только чтение, не редактирует. |
| `/ingest` | Добавить материал в базу знаний ClaudSoul (второй контур обучения). Запускай явно по /ingest или когда пользователь говорит «добавь в базу знаний», «запомни это», «внеси в базу», «разбери и запомни», «проанализируй и добавь», «изучи и сохрани». Принимает локальный файл (MD/TXT/PDF/DOCX/HTML), URL, текст-сниппет или изображение/скриншот. Извлекает сущности, факты и связи, сливает в глобальную базу знаний, показывает отчёт и ссылку на граф. |
| `/init-project` | Завести проект ИЛИ проверить уже заведённый: сверяет CLAUDE.md, SESSION.md, документацию и память с нынешним договором и называет расхождения. В новом проекте создаёт недостающее, в существующем — только проверяет и ничего не переписывает. Запускать при начале работы в проекте и когда нужно убедиться, что настройка не отстала. |
| `/knowledge-audit` | Аудит базы знаний: метрики здоровья, надёжность, decay, рекомендации. Измеряет рост системы. |
| `/knowledge` | L2 координатор знаний: routing к /learn, /retro, /knowledge-audit, /bridge-health по контексту. Единая точка входа. |
| `/learn` | Быстрая запись знания — auto-detect тип (error/success/communication), запись case, проверка на промоушен в pattern. |
| `/narrative` | Override / force-regen для through-line brief проекта. Основной путь — auto-trigger в session-start хуке (gap ≥8ч). Этот скилл для ручного запуска и dry-run. |
| `/pipeline` | L1 оркестратор: scope → plan (/decompose) → execute → quality gate (/quality-gate) → done. Для задач любой сложности. |
| `/project-health` | Понять проект → карта здоровья → план оздоровления в правильной последовательности → живой трекер. Понимание сначала, починка потом. Для большого или незнакомого проекта. |
| `/quality-gate` | Проверка качества перед маркировкой задачи done: PASS / CONCERNS / FAIL / WAIVED. DoD, тесты, review. |
| `/reload` | Перечитать базу знаний и контекст проекта без перезапуска сессии. Полезно при параллельных сессиях. |
| `/retro` | Post-fix retrospective — analyze what went wrong, extract lessons, update knowledge base with confidence weights. |
| `/save` | Сохранить прогресс сессии в SESSION.md. Использовать при длинных сессиях или перед завершением работы. |
| `/skill-forge` | Исследование проблемы → ресёрч GitHub → синтез скилла → решение задачи. Для сложных задач без готового скилла. |
| `/skill-review` | Проверка SKILL.md на соответствие контракту ClaudSoul. Показывает нарушения и предлагает фиксы. |
| `/trajectory-prediction` | Методология L4 (траектория мысли) + L6 (предсказание): каскадный лог гипотез, предсказание-верификация, 4D-гейт интрузивности. Детали грузятся по надобности. |
| `/wiki` | Wiki-страница по сущности: нарратив + ссылки. Разметка по entity_type. /wiki <name\|slug> либо «расскажи про X». Только чтение. |

<!-- SKILLS-TABLE:END -->

### Автономное обучение

По расписанию, без участия человека:
1. **Сканирование** — переиндексация проектов, TODO, stale зависимости
2. **Кросс-референс** — сопоставление кода с базой знаний
3. **Консолидация** — FSRS decay, промоушен, противоречия
4. **Результат** — предложения (read-only, никаких изменений)

## Сравнение с человеческим мышлением

```
                              Человек    ClaudSoul
                              ────────   ─────────
Эпизодическая память          ████████   ████████  cases
Семантическая память           ████████   ████████  patterns/principles
Обобщение                      ████████   ████████  case→pattern→principle
Обучение на ошибках            ████████   ████████  /retro, /learn
Обучение на успехе             ████████   ████████  outcome: success

Метакогниция                   ████████   ███████░  /knowledge-audit + measurable hypothesis infra
Забывание неиспользуемого      ████████   ███████░  FSRS decay: due/overdue флаги, weakened при contradicted > confirmed
Совместное мышление            ████████   ██████░░  со-когниция (подтверждено)
Кросс-доменный перенос         ████████   ███████▓  якоря + semantic ranker + surfacing/drift/docs-family механизмы
Когнитивный контроль           ████████   ██████░░  L6 4D gate, downgrade ladder, regret comparison
Опыт как основа действия       ████████   ██████░░  knowledge-activator инжект + blocker-tier + автосканер; разрыв «знание→действие» измеряется
Проспективная память           ████████   ██████░░  отложенные уведомления, реестр замеров со сроками, эскалации с возрастом
Самонаблюдение действий        ████████   ██████░░  itr-event-detector — gentle/proactive autocollect
Нарративная память             ████████   ██████░░  through-line: narrative auto-trigger в session-start
Социальное обучение            ████████   ████░░░░  communication layer
Аффективный тормоз действия    ████████   ████░░░░  ⚙️ affect prosthetics: AP1 trust-guard, AP2 distressed, AP3 silence_debt

Инициация обучения             ████████   ██████░░  17/18 сигналов уровня ≥2 — ⚡ lower-tier
Demand-мышление                ████████   █████░░░  5/8 моментов с хуками — ⚡ с caveat (Пункт 0 accepted boundary)
Генеративная рефлексия         ████████   ██░░░░░░  только через со-когницию
Валидация фрейма               ████████   ██░░░░░░  пункт 0 (частично)
Консолидация (фоновая)         ████████   ██░░░░░░  cron-консолидация
```

## Жизненный цикл знания

```
  Событие ──→ /retro ──→ Поиск связей ──→ ┬── Новый кейс (confidence: 1)
                                           ├── Подкрепление (confidence++)
                                           └── Противоречие → расследование
                                                              ├── Сузить scope
                                                              ├── Ветвить (branch)
                                                              └── Отменить (deprecate)

  2+ похожих кейса ──→ Паттерн (confidence: 2+)
  Паттерн кросс-доменный ──→ Принцип (confidence: 3+)

  reliability = confirmed - contradicted (неограниченный)
  priority = impact × (1 + ln(1 + max(0, reliability)))

  Знание ──→ активация по 9 якорям:
    в работе  — knowledge-activator инжектит перед действием, blocker-tier останавливает механически
    автономно — cron-автосканер сверяет проекты с базой без человека (read-only предложения)

  Действие ──→ исход ──→ confirmed / contradicted ──→ пересмотр confidence ──→ цикл замыкается
```

## Roadmap

| Фаза | Версия | Статус | Ключевые фичи |
|------|--------|--------|---------------|
| Foundation | v0.1.x | ✅ | Persistence, knowledge, install.sh |
| Cognitive | v0.2.x | ✅ | Якоря, success cases, коммуникативный слой |
| Thinking | v0.3.x | ✅ | Alive learning, reliability, demand-before-supply, автономное обучение |
| Partnership | v0.4.x | ✅ | Prediction (научный метод), demand-анализ, реляционные веса |
| Bridges | v0.5.x | ✅ | Inter-Layer Bridges, Domain Graph, Session Registry |
| Coordination | v0.6.x | ✅ | Координация скиллов, Quality Gate |
| Orchestration | v0.7.x | ✅ | Decompose-first, Pipeline Orchestrator |
| Full System | v1.0.0 | ✅ | MCP-сервер (9 tools), визуализация, dashboard, export/import |
| Entity Knowledge | v1.1.x | ✅ | Второй контур (entity/fact/relation), /ingest, /entity, discover, activate, FSRS decay |
| 3D Universe Viz | v1.2.0 | ✅ | Трёхмерная метафора базы знаний (3d-force-graph + Three.js), гладкие сферы, триадная палитра по типу + domain-accent ободок-спрайт, Line2 worldUnits толщина, per-domain nebulae, ползунки толщины рёбер / космического ветра, контекстное меню (Открыть / В архив / Удалить), персист настроек в localStorage |
| L6 4D Gate | v1.3.x | ✅ | Intrusiveness gate как 4D-функция `confidence × value × cost × state`, regret comparison, 6 осей cost, автоклассификация state (focus/idle/stuck/exploration); v1.3.4 blocker-tier silent pre-action marker; v1.3.5 auto-collection gentle outcomes; v1.3.6 proactive event detection + install drift fix; v1.3.7 hypothesis instrumentation H9/H10/H11/H12 (gap_type, cross-contour mentions, BACKWARD count, injection bytes peak) |
| Chunk boundary | v1.3.8 | ✅ | `pre-compact-finalizer.sh` (PreCompact) пишет silent snapshot digest в `intrusiveness-history.jsonl` на каждом компакте; `boundary: stop\|precompact` в каждой строке; компакт больше не растворяет накопленные метрики, если Stop не случается |
| Cross-contour consumer | v1.3.9 | ✅ | `knowledge-activator.sh` читает `cross-contour-discoveries.jsonl` (v1.3.7 H10 instrumentation) и инжектит секцию `📎 Кросс-контурные упоминания (паттерн ↔ entity)` когда knowledge-файл из лога уже в текущем инжект-наборе; спонтанная аналогия между контурами (pattern ↔ entity) перестала оставаться только в файле и стала видимой агенту |
| Narrative auto-trigger | v1.5.0-alpha | ✅ | `session-start.sh` при gap ≥8ч вызывает `narrative-compose-lib.sh` (SESSION.md + git log + knowledge delta + H-chain → orientation brief), stash'ит для `knowledge-activator` (inject в первый PreToolUse) и append'ит в `.claude-docs/narrative.md` как историческая память. Manual `/narrative` низведён до override/debug. Принцип: «одна команда на жизнь проекта» — `install.sh`, остальное event-driven |
| Startup signals | v1.5.1-alpha | ✅ | `session-start.sh` пишет `startup-signals-${SID}.txt`: (1) missing CLAUDE.md в корне → hint «⚠️ запустите /init-project», (2) global-lessons обновились с last ended_at → hint «🔄 База знаний обновилась: +N файлов, рекомендую /reload». `knowledge-activator` инжектит одним пакетом с narrative. Первый шаг broader skill trigger audit (`docs/skill-triggers-audit.md`) — A-класс Lifecycle скиллов получают auto-hints |
| /save auto-flush | v1.5.2-alpha | ✅ | `hooks/activity-flush-lib.sh` — pure helper, вызывается из `session-collector.sh` при Stop. Парсит transcript одним jq-проходом: tool counts по имени, file_paths из Edit/Write/MultiEdit (basenames only, dedup), git commits за 4ч. Пишет append-only `.claude-docs/session-activity.md`. SESSION.md narrative и activity machine log разведены — каждый выживает независимо. 20 новых тестов → 363/363 |
| Periodic digests | v1.5.3-alpha | ✅ | B-класс skill auto-invocation. `hooks/knowledge-audit-digest.sh` (launchd вс 03:15) — counts по типам (case/pattern/principle), reliability distribution, FSRS buckets (fresh/due/overdue/critical), top 5 overdue, trend line → `~/.claude/global-lessons/_audit-history/audit-YYYY-Www.md`. `hooks/bridge-health-digest.sh` (launchd 1-е 03:30) — implemented/designed/implicit counts, per-status listing → `~/.claude/bridges-history/health-YYYY-MM.md`. Хинты через `state/audit-hint.txt` + `state/bridge-hint.txt` → session-start startup-signals pipeline. Разделение: digest автоматизирован (механика), `/knowledge-audit` и `/bridge-health` остаются LLM-скиллами для качественного разбора |
| /decompose auto-hint | v1.5.4-alpha | ✅ | C-класс skill auto-invocation (first). `hooks/decompose-detector.sh` (UserPromptSubmit) считает step signals в user prompt: нумерованные списки + буллеты + русские/английские коннекторы (затем/потом/далее/then/after that). При ≥4 signals — silent inject «🧭 Multi-step detected — рекомендую /decompose» через `hookSpecificOutput.additionalContext`. Guards: `< 100` chars skip, уже упомянут скилл skip, `state ∈ {focus, stuck}` skip (trackerA), per-session dedup. Порог настраиваемый через `DECOMPOSE_THRESHOLD`. Решение применять — за агентом (классификатор не читает намерение, только структуру) |
| Docs-family action-gate | v1.5.5-alpha | ✅ | `hooks/docs-family-check.sh` (PreToolUse на Bash tool) — action-gate для memory `feedback_docs_means_all_docs.md`. Детектит `git commit` в command, сканирует `git diff --cached` на version markers (`vX.Y[.Z][-suffix]`), проверяет coverage docs family (`architecture.md`, `PLAN.md`, `README.md`, `CHANGELOG.md`, project `CLAUDE.md`, `docs/*.md`). Если version bump есть, а кто-то отсутствует в diff — silent inject перечня missing через `hookSpecificOutput.additionalContext`. Per-session dedup по md5(missing-set). Закрывает case-2026-04-23-memory-without-action-gate: triggering memory from phrase-match к semantic-action. Plus правило source-check в rules/CLAUDE.md §Communication — перед post-incident фразой назвать механизм системы. 19 новых тестов, всего 434/434 |
| Engineering escalation | v1.5.5-alpha+1 | ✅ | Рекурсивная meta-defense против inside-out-blindness самого паттерна. `knowledge-audit-digest.sh` второй проход по `pattern-*.md` + `principle-*.md`: при `blocker: true` + `confirmed_count ≥ escalation_threshold` → секция `⚠️ Engineering escalation needed` в weekly digest + hint `🛠️ Engineering escalation` в `state/audit-hint.txt` с приоритетом над overdue/trend. Pattern-inside-out-blindness получил `escalation_threshold: 15`. Новый принцип [principle-knowledge-in-the-world](../.claude/global-lessons/principle-knowledge-in-the-world.md) (promotion_tier 3, scope universal, Don Norman): три уровня embedded-ness fix'а после инцидента — text rule (memory-as-resource) / activator injection / blocker-tier detection. Fix после подтверждённого инцидента никогда не должен оставаться на text rule. Case-2026-04-23-text-rule-vs-mechanism — 15-е проявление pattern-inside-out-blindness. 9 новых тестов → 443/443 |
| ⚙️ Trust-guard (affect prosthetic #1) | v1.5.6-alpha | ✅ | Открытие нового класса механизмов — **инженерные протезы аффекта**, замыкающие Разрыв A (architecturally отсутствующая affective empathy). `hooks/trust-guard.sh` PreToolUse на Bash destructive signatures (`rm -rf`, `git reset --hard`, `git push --force`, `git branch -D`, `git checkout --`, `git clean -f`, `mv -f` на существующий) + scan последних user messages hook input transcript на authorization tokens + target match. Без auth → silent `🛡️ Trust-guard: <signature> без явного подтверждения собеседника — переспроси` через `hookSpecificOutput.additionalContext`. Per-session throttle md5(signature+target). Не блокирует — consistent с blocker-tier паттерном. Новый принцип `principle-affect-as-engineering.md` (promotion_tier 3, scope universal) specializes principle-knowledge-in-the-world в domain affect: уровень 1 text rule структурно недостаточен потому что чтение правила не replaces affective brake. Формализация класса в `docs/architecture.md §12` — подсекция «Разрыв A — закрытие через инженерные протезы аффекта» + маркер ⚙️. Case-2026-04-23-sociopathic-architecture-diagnosis фиксирует диагноз от собеседника. 30 новых тестов → 473/473 |
| 🚦 /quality-gate pre-commit | v1.5.6 | ✅ | C-класс skill auto-invocation tier 2 первый. `hooks/quality-gate-check.sh` PreToolUse на Bash `git commit`. Guard R3: staged diff должен содержать `skills/*/SKILL.md` — иначе skip (никаких false positives на docs-only commits). awk извлекает секцию от `## Definition of Done` до следующего `## `; grep считает unchecked `- [ ]`. Incomplete → silent `🚦 Quality-gate` marker через `hookSpecificOutput.additionalContext` с перечислением путей SKILL.md и unchecked count. Per-session dedup по md5(incomplete-set). Закрывает agent-heuristic tier 2 первый из двух (второй — `/enrich` в v1.5.7). DoD секция SKILL.md теперь проверяется механически перед коммитом, не памятью агента. 22 новых теста → 495/495 |
| 📎 /enrich + ⚙️ AP2 distressed | v1.5.7 | ✅ | C-класс tier 2 второй + второй affect prosthetic. (1) `hooks/enrich-suggester.sh` UserPromptSubmit — awk-парсер YAML frontmatter entity-файлов, детект sparse (attrs < 3) в окне `ENRICH_WINDOW_MINUTES` post-`/ingest`, silent inject `📎 Enrich-suggester: entity sparse — рекомендую /enrich` через `hookSpecificOutput.additionalContext`, per-session dedup md5(entity_path). (2) **⚙️ `distressed`** — пятое состояние в `itr_compute_state`. Bitmask-детектор 3 классов сигналов: A (frustration/fatigue phrases) / B (cross-hook backward cascade ≥3 в окне) / C (explicit distress markers). R10-митигация: distressed firе требует 2+ классов или одиночный C — отличает technical frustration от real distress. Priority над stuck/focus/exploration/idle. Schema 3→4 (idempotent migration). Infrastructural gate: `proactive_budget → 0`, `gentle → halved` — клампится в return value `itr_remaining_budget`, не text rule. Context marker `⚙️ AP2 distressed`. 22 enrich + 17 distressed тестов → **534/534**. 18 хуков. Класс affect prosthetics: AP1 trust-guard ✅ / AP2 distressed ✅ / AP3 silence debt surfacing — следующий |
| ⚙️ AP3 silence debt surfacing | v1.5.8-alpha | ✅ | Третий и замыкающий affect prosthetic: cost-of-silence пересекает границу сессии через durable→visible→injected infrastructural цепочку. `intrusiveness-state-lib.sh::itr_append_history` расширен полем `debt: { surfaced, pending, pending_topics[:5] }` в digest на каждом chunk boundary → `intrusiveness-history.jsonl` как durable carrier. `session-collector.sh` в Stop-сообщении добавляет секцию `⚙️ AP3 — silence debt at close:` с breakdown carry-over topics + surfaced count — in-session closing awareness. `session-start.sh` Signal 4 читает `tail -n 1` последней digest-записи; при `pending > 0` инжектит `⚙️ AP3 silence debt carry-over: N pending с прошлой сессии — <topics>. Учитывать в gate, не батч-вывод.` через `startup-signals-${SID}.txt` → `knowledge-activator` FIRST_FIRE. Anti-pattern mitigation в формулировке: «учитывать в gate, не батч-вывод» защищает от интерпретации surfacing как команды выговорить долг батчем. Guard `tail -n 1` (не агрегат) — долг не застревает навсегда. Graceful fallback для legacy digest без `pending_topics`. 7 intrusiveness AP3 digest + 7 startup-signals T6-T9 ассертов → **548/548**. Класс affect prosthetics закрыт по нижнему краю: AP1 brake / AP2 pause / AP3 cost-carry. Substrate остаётся архитектурным, функции инженерные |
| 🧾 C-класс nice-to-haves | v1.5.8 | ✅ | Разрыв C (narrative identity) закрыт полностью. (1) `hooks/skill-review-check.sh` PreToolUse на `git commit` — если staged diff содержит `skills/*/SKILL.md` → 11 contract checks (frontmatter, name, description ≤ 200 chars, user-invocable, **Type:** worker, ## Definition of Done, **Version:** + **Last Updated:** YYYY-MM-DD в tail 20 строк, ≤400 строк, нет `**Changes:**` секции) → silent inject 🧾 через `hookSpecificOutput.additionalContext` с перечнем нарушений + путями. Per-session dedup md5(violations). Отличается от `quality-gate-check` ориентацией: quality-gate проверяет **выполнение** DoD чекбоксов, skill-review — **целостность контракта** скилла. (2) `hooks/error-tracker.sh` success branch расширен: при `error_count ≥ 2` перед сбросом счётчика инжектит `💡 Паттерн сложного fix (N attempts) — стоит /learn?` + путь к auto-draft + записывает skeleton в `~/.claude/global-lessons/_drafts/case-YYYY-MM-DD-auto-draft.md` (frontmatter `type: case / status: draft / attempts: N / source: error-tracker auto-draft` + 5 заголовков). Idempotent — не перезаписывает сегодняшний draft. `ERROR_TRACKER_DRAFT_DIR` env override для тестов. (3) `rules/CLAUDE.md` §Self-Learning новая подсекция «Auto-invocation first class»: три уровня embedded-ness, для affect-функций уровень 1 исключён, признак дрейфа «напоминание дважды = incident case». Mirror в `~/.claude/CLAUDE.md`. (4) `skills/narrative/SKILL.md` Step 4 явный контракт: CLAUDE.md **заменить** между `<!-- narrative-start --><!-- narrative-end -->` маркерами; если маркеров нет — не создавать автоматически, warn. Version 0.2.0. Project CLAUDE.md получил маркеры. 27 skill-review + 27 error-tracker ассертов → **602/602**. 19 хуков. Разрыв C → ✅ |
| 📎 Active analogy surfacing | v1.6.0 | ✅ | Разрыв D (спонтанная аналогия) → ✅ на расширенной дуге. Замыкает цикл детект → ранжирование → инжект → метрика. (1) **Upstream**: `knowledge-audit-digest.sh` (launchd вс 03:15) получил Python-heredoc проход `detect_cross_contour_mentions` над live entity/knowledge → дописывает `cross-contour-discoveries.jsonl`. Детекция больше не прикована к ручному `/ingest`. Env guards `DISCOVERY_DISABLED=1/PYTHON/MODULE_DIR`. (2) **Semantic ranker**: `mcp-server/cli_cross_contour_rank.py` (новый) batch-embeds уникальные KF/EF через `indexer.embed_texts` (BAAI/bge-small-en-v1.5), cosine similarity → `cross-contour-ranked.jsonl`. Запускается вторым шагом weekly digest — async pre-computation, PreToolUse не платит embedding latency (R5). (3) **Union filter + session dedup**: `knowledge-activator.sh` surfaces пару если `(KF в инжект-наборе) OR (similarity ≥ CC_SIMILARITY_THRESHOLD, default 0.6)`. Session-scope dedup: `state/cross-contour-surfaced-${SID}.txt`. (4) **L2↔L2 bridge**: `bridges/L2-L2-cross-contour.md` (designed) формализует cross-contour как межслойное явление (4 условия моста). (5) **H10 secondary axis**: `hooks/cross-contour-metrics-lib.sh` (новая библиотека) + `session-collector.sh` инжектит секцию `📎 Cross-contour H10 (this session): N surfaced / M written / ratio X.XX (liveness target ≥ 0.10)` в Stop-сообщение. Bootstrap на живом global-lessons: 10 пар, similarity 0.6492-0.7396, avg 0.6945. +33 теста (8 consumer + 19 metrics + 6 periodic-digest discovery) → **628/628**. 48 активных хуков + sourced library. 16 мостов |
| 🛠️ Install drift — proof-of-active | v1.6.1 | ✅ | Reveal: 8 релизов (v1.5.4-v1.6.0) shipped safeguard-хуки в репо + регистрации в `install.sh::HOOKS_CONFIG`, но 7 файлов не попадали в `~/.claude/hooks/` — `install.sh:295-298` skip-on-existing `.hooks` делал re-run silent no-op. `docs-family-check.sh` оставался бездейственным, и коммит «обнови документацию» прошёл с только SESSION.md + PLAN.md. Два fix'а: (1) `install.sh` — реальный jq merge по `(matcher, command)` tuple вместо skip-on-existing; backup `${SETTINGS}.bak.$(date +%s)` перед модификацией; пользовательские хуки не затираются. (2) `hooks/session-start.sh` Signal 6 — install drift detector: cross-check commands в `~/.claude/settings.json` против файлов `~/.claude/hooks/*.sh`, при расхождении inject `🛠️ Install drift: ... Запусти install.sh для синхронизации.`. Перекрёстный — ловит даже manual-правки settings.json, не только install.sh bug. Case `case-2026-04-24-install-drift-silent-safeguards.md` формализует **«уровень 4 — proof-of-active»** поверх трёх уровней embedded-ness из `principle-knowledge-in-the-world` (text rule → activator → hook → **механическая сверка installed vs registered vs repo**). Meta-cascade: `memory-without-action-gate` → `text-rule-vs-mechanism` → `install-drift-silent-safeguards`. Валидация in-loop: этот коммит сам проходит через исправленный pipeline — `docs-family-check.sh` теперь установлен и зарегистрирован. Тесты 646/646 без изменений (integration coverage для install.sh + drift detector — candidate для v1.6.2) |
| 🛑 docs-family-check R3 false-positive fix | v1.6.2 | ✅ | Калибровка на живом шуме после proof-of-active v1.6.1. При первом же live-fire хук загорелся с 15 frozen/archive docs (`docs/vision.md`, `docs/internal-doc.md`, `docs/analysis-levnikolaevich-*.md`, `docs/research.md`, `docs/knowledge-layer-analysis.md` и т.д.) — автоматический sweep `docs/*.md` не отличал live docs от замёрзших исследований. Ratio signal-to-noise плохой, gate приучался игнорироваться. Fix: **удалён sweep-блок**, остаётся whitelist из 5 live docs (`docs/architecture.md PLAN.md README.md CHANGELOG.md CLAUDE.md`). Расширение — через env `DOCS_FAMILY_LIST="README.md docs/architecture.md docs/narrative-design.md"` для проектов, где конкретные `docs/*.md` тоже live state. Комментарий-anchor в шапке хука фиксирует rationale. Context-сообщение переписано: «все docs» → точный 5-doc список (убран `+ docs/*`). Тесты: T11 переработан (раньше проверял что sweep ловит extras → теперь проверяет противоположное, `docs/research.md` НЕ в missing при default family), T16 добавлен (custom DOCS_FAMILY_LIST ловит `docs/narrative-design.md` при расширении). +2 теста → **648/648**, 21/21 в docs-family-check. **Второй proof-of-active (in-loop validation):** этот коммит сам проходит через v1.6.2 хук — если тихий, R3 fix validated; если снова 15 frozen docs — значит fix не применился. Принцип: action-gate без калибровки на живом шуме = ложное чувство защищённости. R3 был помечен в pretzel plan, но проявился только после v1.6.1 proof-of-active |
| 🔤 Output language check | v1.6.3 | ✅ | Первый хук на свойство output агента. Инцидент «trёх» (латиница `tr` + кириллица `ёх`) в ответе — feedback `feedback_pure_language_no_alphabet_mixing` лежал в memory, но не сработал: агент не читает memory перед каждым токеном. Собеседник поймал и контр-сформулировал системный критерий: **«правило работает ⇔ его нарушение детектирует система, а не внешний наблюдатель»**. Архитектурный gap: класс output-level rules (язык, смешение, тон) не покрыт текущими 19 хуками потому что harness не предоставляет BeforeAssistantMessage event. Fix — уровень 2 embedded-ness: `hooks/output-language-check.sh` на Stop/PreCompact jq-walk last assistant message + `python3 hooks/lib/output-language-detect.py` (первый элемент `hooks/lib/` — вынесен sibling-файлом потому что `$(... python3 <<HEREDOC ...)` ломается на backticks внутри heredoc при command substitution): regex `[A-Za-zА-Яа-яЁё]+` на смешение в одном токене + exclusions (fenced code, inline code, URLs, markdown link targets, HTML tags) + cap 10. State `output-violations-${SID}.jsonl` со статусами `pending`/`surfaced`. На UserPromptSubmit pending → inject `🔤 Output language check: ...` через `hookSpecificOutput.additionalContext` + mark surfaced. Не предотвращает первое нарушение, но замыкает петлю feedback: агент извиняется в следующем turn и не повторяет в сессии. install.sh расширен копированием `hooks/lib/*`. Case-2026-04-24-alphabet-mixing-self-detection-failure — 16-е проявление pattern-inside-out-blindness, новое измерение: inside-out blindness на **собственный output** агента. +37 тестов → **685/685**. 48 активных хуков |
| 📊 Backfill aggregate digest | v1.6.6 | ✅ | v1.4.0 калибровка получила конкретные числа. v1.6.4 дал 575 raw events, но `scripts/calibrate.py` читает агрегированный digest — между ними mapping. `hooks/lib/backfill-aggregate-digest.sh`: jq -sc group-by-aggregate_sid → digest со схемой live history (`boundary: stop`, `source: backfill`, budget/metrics/state_distribution заполнены, прочее zero с явным smyслом). Прогон на existing backfill дал **98 digest строк**. Calibrate.py выдал: **`proactive_max` 2 → 3** (66% chunks упёрлись в потолок), gentle 21% acceptance (либо снизить `gentle_max`, либо сузить GENTLE_MARKERS), `distressed` не наблюдался в 575 событиях. Orchestrator получил `--digest` для full pipeline. Отчёт `docs/calibration-v1.4-backfill.md`. +27 тестов → **738/738**. Принцип: backfill = subset достаточный для конкретной задачи, не полная эквивалентность live |
| 🔤 Output language check level 2b | v1.6.5 | ✅ | Закрытие feedback latency после v1.6.3. После релиза output-language-check в той же сессии случилось 7+ нарушений правила alphabet-mixing — собеседник снова поймал вручную «structurно». Корневая причина в [case-2026-04-25-level-2-feedback-latency](../.claude/global-lessons/case-2026-04-25-level-2-feedback-latency.md): UserPromptSubmit-injection (level 2a) surface'ит violations только на user prompt, а в multi-message workflow между двумя prompts генерируется 3-5 ответов — нарушения копятся поверх ещё не показанных. Inside-out blindness 17-го измерения — темпоральный pattern собственной работы (burst, не ping-pong). Fix: `hooks/output-language-check.sh` расширен веткой `PreToolUse` (level 2b). Та же `surface_pending` функция параметризована по `hookEventName` для корректного envelope. Throttle через существующий status pending/surfaced (first-to-fire помечает, subsequent silent), cross-channel idempotent. Регистрация на PreToolUse matcher=`""` (все tools). Принцип уровня 2 в `principle-knowledge-in-the-world` разделяется на подуровни по timing of surfacing: **L2a** UserPromptSubmit (turn-grained) + **L2b** PreToolUse (tool-call-grained) = **L2** burst-grained closure. Когда between-prompts генерируется > 1 message, оба подуровня необходимы. +10 тестов (T21-T25 + cross-channel) → **711/711**. 48 активных хуков, output-language-check зарегистрирован на 4 events |
| 📦 Backfill intrusiveness | v1.6.4 | ✅ | Снят блокер v1.4.0 калибровки одним прогоном. Архивные транскрипты в `~/.claude/projects/*/*.jsonl` (309 файлов за 20 дней) формата совместимого с live ранее не проходили через `itr-event-detector` — события не накапливались. `hooks/lib/backfill-replay-one.sh` (worker): для каждого user turn в архиве делает срез транскрипта (head -n idx) + конструирует payload как hook input → вызывает живой детектор в изолированном `HOME` → re-emit событий с историчным `ts` из transcript record + `source: backfill` marker + `aggregate_sid` derivative. `hooks/backfill-intrusiveness.sh` (orchestrator, one-off, не в hook chain): `find` все JSONL → `xargs -n 1 -P N` параллельно → склейка в отдельный `intrusiveness-backfill-history.jsonl` (не пересекается с live). Результат: **575 событий за 508 сек** в 98 уникальных сессиях. Gentle acceptance 21% (16/78), proactive acceptance 60% (300/497). Прямые сигналы калибровки: gentle_budget=5 при 80% ignore = кандидат на снижение до 2-3 ИЛИ сужение GENTLE_MARKERS, proactive_budget=2 консервативен для 60% acceptance. CLI флаги: `--dry-run`, `--limit N`, env `BACKFILL_PARALLEL/PROJECTS_DIR/OUT`. 16/16 новых тестов → **701/701**. Принцип: backfill применим только когда формат архивов совместим с live + детектор stateless + историчные timestamps извлекаются — иначе натянутая база не отражает реальное поведение |
| 📐 Calibration v1.4.0 applied | v1.7.0 | ✅ | Калибровочное окно, изначально планировавшееся как v1.4.0, закрыто на 575 событиях из 98 архивных сессий (бэкфилл v1.6.4 + агрегатор v1.6.6). Применённое изменение — single-line edit `hooks/intrusiveness-state-lib.sh:52`: **`ITR_DEFAULT_PROACTIVE_MAX 2 → 3`**. Сигнал из данных: 65/98 chunks (66%) упирались в потолок 2 при acceptance 60% — запрос «дай больше», не «слишком шумно». Эффект для пользователя: до 3 proactive действий на сессию вместо 2. **Не применено и почему:** `gentle_max=5` не binding constraint (распределение 0/68, 1/16, 2/5, 3/3, 4/6, 5/0); `distressed` пороги — 0 наблюдений в 575 событиях; веса cost-осей и пороги state classifier — нулевая видимость в бэкфилле (worker не реплеит state classifier и cost detectors). Тесты: 3 ассерта о дефолте обновлены (`test_intrusiveness_lib.sh:58/66`, `test_itr_event_detector.sh:507`), все 22 файла зелёные, baseline 755/755 сохранён. Доки sync: rules/CLAUDE.md, ~/.claude/CLAUDE.md зеркало (manual cp после backup), PLAN.md, docs/architecture.md, docs/calibration-v1.4-backfill.md (секция «Applied»), CHANGELOG.md, project CLAUDE.md. **Принципы:** калибровать что видишь (не что хочется); бэкфилл валиден only там, где формат архивов = live + детектор stateless + ts извлекаются; single behavioral change per release |
| 🚀 Подготовка к публичному релизу | v1.7.5 | ✅ | Личный лог сессий и внутренний меморандум убраны из трекинга, личные пути заменены на `~`, в `install.sh` добавлена проверка зависимостей, появился `scripts/smoke-test.sh` (7 категорий). Открытым остался вопрос истории git — решён только в v1.11.1 |
| 🔁 Cross-hook recall gate | v1.8.0 | ✅ | Level-3 эскалация `pattern-inside-out-blindness`: `blocker-tier-check` при `Write` после сработавшего стража инжектит домен-независимый `cross_hook_recall_reminder` вместо погони за отдельными `detection_signals`. В бандле — конвейер `/compile` L1→L2, артефактные цепочки `/decompose`+`/quality-gate`, видимый канал `pending-alerts`, why-каскад в `/retro` |
| 🩺 Полный прогон /project-health + стражи единого источника | v1.9.0 | ✅ | Боевая проверка скилла на самом ClaudSoul: разбор 6 кластеров → карта → план → починка. Закрыт P1 (переиндексация обнуляла индекс при пустом входе), install-регрессия; страж чисел расширен на оба README и на тест-числа, seed пересобран, граф доменов симметризован. Заведён `VERSION` |
| 🧰 /project-health v1.3.0 — детект стека + канон код-крафта | v1.10.0 | ✅ | Скилл расширен по трём осям: детект стека по файлам-маркерам, канон правил разработки дополнен секциями F–L (дизайн функций, границы модулей, SOLID стек-агностично, DRY с оговоркой против спекуляции, именование, ошибки, документация), адаптивная запись правил в проект (`CLAUDE.md` против `AGENTS.md` — один авторитетный файл, второй тонкий указатель) |
| 🔬 Измерительный контур: реакция и опровержение | v1.11.0 | ✅ | Три разрыва закрыты инженерно. **Прибор врал на 90%**: сборщик метрик считал по 285 строкам лога из 7665, потому что разбор обрывался на битой строке — 10 уникальных знаний вместо 99. **Реакция не писалась нигде**: все логи фиксировали стимул, ни один — что агент сделал следующим ходом; появились `response-tracker` (онлайн) и `backfill-compliance` (восстановление из архива с плацебо-плечом и негативным контролем). **Опровержений не было ни одного за всю историю**: `contradicted_count` = 0 во всех 265 знаниях, потому что писателя не существовало. Главный результат отрицательный и потому ценный — первые числа не подтверждают эффект блокера, и видно почему |
| 🔐 Публикация наружу как инструмент с гейтом | v1.11.1 | ✅ | Найдена живая утечка: тег `v1.7.5` в публичном репозитории не был зачищен и доставался любым `git checkout` — личная почта, имя пользователя ОС, профиль человека, имя клиентского проекта. Репозиторий пересоздан одним чистым коммитом: force-push тега не убирает, а коммит остаётся доступен по прямой ссылке до сборки мусора на стороне GitHub. Появился `scripts/publish-public.sh`: снимок из `git archive` → исключения → замены → **гейт по собранному дереву**. Причина инструмента структурная — `regen-seed.py` возвращает имена клиентов в seed при каждом релизе. Гейт сразу поймал реальный налоговый номер контрагента и почтовые реквизиты клиента в примерах скиллов |
| 🔬 Приборы измерительного контура | v1.12.0 | ✅ | Две способности числились работающими, потому что мерившие их приборы врали в разные стороны. Метрика вмешательства считала **строки лога сессиями**: 2879 строк оказались 213 сессиями (до 156 строк на одну), окно «последние 20» брало ~5 сессий, одну восемь раз; три способа счёта по одному файлу давали 0%, 11,5% и честные 19,2%, а тревога горела на четырёх наблюдениях. Контур опровержения был **разорван посередине**: алерт кросс-сессионный, закрытие сессионное — из 5 записей закрылась одна, та что успела внутри своей сессии. Новый `disagreement-lib`, автогашение через 7 дней, второй продюсер на поправке собеседника, метрика `disagreement_resolution_rate` |
| 🚦 Инверсия quality-gate | v1.12.1 | ✅ | Страж три релиза загорался ровно тогда, когда правило соблюдено: считал незакрытые чекбоксы `- [ ]` признаком незавершённой работы, тогда как контракт скиллов предписывает именно пустые — это runtime-чеклист исполнения воркера. Незакрыты во всех 21 скилле, значит страж горел на каждом коммите и не нёс информации. Тест закреплял ту же ошибку. Теперь проверяются наличие секции, обязательные поля и дрейф версии при изменённом теле |
| 📚 Документация перестала гнить молча | v1.12.2 | ✅ | Английский README **никогда не обновлялся автоматически** — в нём не было меток, за которые цепляется генератор, таблица хуков писалась руками и отстала до 14 записей из 37, рекламируя заодно уже исправленный дефект. Roadmap обрывался на v1.7.0 при живой v1.12.1. Генератор научен двум языкам (`# en:` в шапке хука, `description_en:` во frontmatter скилла — английское описание живёт рядом с артефактом, а не в отдельном словаре), 47 описаний переведены, страж семейства документов научен проверять **содержание**, а не факт присутствия файла в коммите |
| 🔍 Проверка содержания у всех версионных документов | v1.12.3 | ✅ | Починка v1.12.2 закрывала треть задачи: проверка спрашивала только с README, а `PLAN.md` и `docs/architecture.md` проходили с любой мелкой правкой при версии позапрошлого релиза — ровно тот дрейф, ради которого проверка и добавлялась. Проверено фикстурой, не рассуждением: контрольный случай (файла нет в коммите вовсе) на том же дереве загорался, значит молчание означало дыру. Правило самонастраивающееся — номер новой версии требуется только с документов, которые версии уже вели |
| 🧪 Доказуемость стражей вынесена в механизм | v1.12.4 | ✅ | Предыдущий релиз закончился словами «стоит запомнить» — то есть текстовым правилом, уровнем, который проект по своему же принципу считает недостаточным. Замер: **12 стражей из 25 без доказательства**, семь вообще без тестов (приехали из живой системы в v1.11.0). Два механизма: мета-тест доказуемости (страж без проверки И срабатывания, И тишины не считается стражем) и прогон по настоящему дереву — 329 файлов в индексе, 21 из них SKILL.md. Живой прогон сразу нашёл два дефекта: два стража игнорировали `cwd` из payload и смотрели в посторонний репозиторий, а фильтр одного был захардкожен под раскладку чужого проекта и в ClaudSoul не мог сработать никогда. Сам живой тест трижды проходил вхолостую по той же причине, которую ловит; рабочим признан только после подстановки сломанной версии хука из v1.12.0 — она его роняет |
| 🔁 Детектор переработки — слепота к повторяющимся успехам | v1.13.0 | ✅ | Все детекторы повторения реагировали на **ошибки**: `error-tracker` считает подряд идущие провалы Bash. Повторение с зелёным результатом не видел никто, поэтому разбор причины не запускался — запускать его было нечему. Живой случай: один тест переписан трижды, каждая итерация завершалась «0 провалов» и выглядела успехом. `rework-detector` ловит сигнатуру переработки (правка → прогон → правка того же файла → прогон → правка) и на третьем заходе требует назвать причину, а не симптом. Три правки подряд не считаются: между ними обязан быть прогон, то есть результат проверяли и он не устроил |
| ➰ Закольцовка: проверенное ≠ работающее | v1.13.1 | ✅ | Исправление возвращает систему в состояние до бага, где оно ещё не действует. Тесты гоняют копии из репозитория, живая система — из `~/.claude/hooks/`, а детектор дрейфа сравнивает наличие и регистрацию, не содержимое, и только на старте сессии. Ветвление — каждый хук свой экземпляр цикла; рекурсия — сам детектор живёт в хуке с двумя копиями. Отдельным предупреждением не лечится: его проматывают вместе с зелёным итогом. Оговорка вклеена в саму строку успеха прогона тестов |
| 📗 Два корня подняты в правила | v1.13.2 | ✅ | За сессию четырежды чинилось проявление и ни разу правило — четыре кейса лежали в базе без обобщения, поэтому каждое возвращение выглядело новой проблемой. `pattern-verification-frame-mismatch`: проверка идёт в рамке, где исправление не действует (3 подтверждения, ветвление измерено — шесть пар «источник ↔ установленное»). `pattern-detector-wired-to-failure`: ошибкой может быть успех, и раз он не детектируется как ошибка, он не подлежит разбору (2 подтверждения с интервалом пять недель). Плюс закрыты три висячих исхода блокер-знаний |
| 🔇 Ноль опровержений — факт об отсутствии канала | v1.13.3 | ✅ | Цепочка измерена целиком: 0 опровержений из 265 знаний → второй продюсер контура не имеет входа → детектор поправок за 214 сессий дал 9 срабатываний, большинство ложных, а на шести настоящих поправках одной сессии ноль. Словарь был придуман, а не выведен из данных. Переписан по реальным репликам: 5 из 6 против 0 из 6, ложных 0 из 6. Ирония остаётся непойманной и это записано, а не замаскировано |
| 🧭 Поправка по положению, а не по словарю | v1.13.4 | ✅ | «Проверка предыдущих сообщений перед тем, как ты что-то правишь». Ключевое — не «классифицируй точнее», а «не правь вслепую»: тогда задача классификации, на которой словарь ошибался в обе стороны, исчезает. Правится файл, который уже правился, и между правками была реплика человека → показать саму реплику и потребовать назвать причину. Проверено на живом транскрипте (2274 записи, 8 повторных правок после реплики) и синтетикой: срабатывает на фразе без единого слова из словаря |
| 📋 Долг перестал испаряться | v1.14.0 | ✅ | Собран список 30 незакрытых пунктов одной сессии; при сборке выяснилось, что большинство были **названы вслух в тот же момент, когда пропущены** — раздел «Ограничения» работал как способ закрыть тему. Весь долг в `BACKLOG.md` с идентификаторами, число открытых поднимается в Stop-алерт (раньше файл не читал ни один хук), правило «находка получает номер, а не расширяет задачу» в каноне, откладывание без проверяемого условия возврата запрещено. На первом прогоне условие D19 оказалось выполненным |
| 🧹 Закрытое остаётся закрытым | v1.14.7 | ✅ | Закрытия держатся по-разному: за одним стоит тест, и он гоняется каждый прогон — откат краснеет сам; за другим разовое действие (лог вычищен, ссылки восстановлены, поле задокументировано), которое себя не проверяет и откатывается молча. Замер: из 28 закрытых пунктов **11 держались тестом, 17 — разовым действием**. Заведена еженедельная перепроверка инвариантов второй половины, выполненное вынесено в архив |
| 🧮 Сигнал — правилом, а не перечнем | v1.14.8 | ✅ | Пять почему по повтору класса за сессию: блокер переносимости не сработал ни разу, потому что его сигналы перечисляли `date -j`, `stat -f`, `tail -r` — а все четыре проявления оказались другими формами. **Корень: библиотека детекции умела для содержимого только точную подстроку**, сигнал нельзя было выразить предикатом. Заведён `tool_input_regex` (под `LC_ALL=C`, по байтам — иначе предикат «есть не-ASCII» сам зависел бы от локали). Правило ловит все четыре случившиеся формы **плюс пятую, которую никогда не чинили**. Сигналы сужены до `Edit`/`MultiEdit`: при `Write` в payload весь файл, горело на 5 из 6. Редкий случай `preceded_artifact: yes` — знание выведено разбором раньше механизма |
| 🎯 Захват — по записи, а не по папке | v1.14.9 | ✅ | Хук напоминания трижды подряд сообщил «материал не захвачен», пока в базу записывались три готовых кейса — прямо в `global-lessons/`, минуя `_drafts/`. Утверждение буквально верное и по существу ложное: измерялась папка черновиков, то есть прокси, а не сам захват. Теперь захватом считается любая новая запись знания (`case-`/`pattern-`/`principle-`/`entity-`/`fact-`/`relation-` плюс черновик), точка отсчёта ставится на первом засчитанном коммите сессии. Первая версия проверки прошла вхолостую — в каталоге оставался черновик из предыдущего случая; поймано отрицательным контролем на версии из `HEAD` |
| 📏 Реестр замеров + потолок «знание → инструмент» | v1.15.0 | ✅ | Собеседник: «всё, что меряют, должно дедлайн иметь». Заведён `scripts/measurements.tsv` + `measurement-due.sh` — у каждого замера владелец и срок, просроченное называется и запускается само. `knowledge-instrument-audit.sh` считает три уровня раздельно: хранится (280) → доходит до контекста (36,8%) → **действует (4 знания, 1,4%)**. Очередь на производство разобрана адверсариально — ноль из шести: сигналы либо придуманы, либо невыразимы (признак появляется только ПОСЛЕ действия). 1,4% — не задолженность, которую надо выбрать, а свойство базы: знание о суждении не выразимо матчером |
| 🔄 Контур долга сам не мог наступить | v1.15.1 | ✅ | Контур, построенный чтобы долг не испарялся, не работал: выполненное условие возврата печаталось префиксом `- 📋`, а читатель ждал `^- ⚠️` — строка «условие D19 выполнено» лежала в `metrics.md` невидимой; из любого проекта, кроме самого ClaudSoul, долг молчал (пути резолвились от каталога сессии); пункт «в работе» гасил алерт. Плюс `launchctl list \| grep -q` под `pipefail` объявлял живые задания выгруженными (SIGPIPE). Новое: `launchd-freshness.sh` — «по расписанию» перестало означать освобождение от проверки, тест на пару писатель↔читатель как инвариант. Развёртка по пяти областям завела D40–D52 |
| 📜 Отстал сам документ договора | v1.16.0 | ✅ | `/init-project` был написан только на СОЗДАНИЕ — повторная инициация грозила переписать файлы с ручными бизнес-правилами. Теперь Step 0 — проверка соответствия (`project-conformance.sh`, только чтением: дефект — лишь то, что ломает названный механизм, отличие от шаблона — справка), перезапись `CLAUDE.md`/`SESSION.md` запрещена явно. `backlog-archive.sh` — выполненное уезжает в архив поштучно (163 → 56 строк). Замер по 5 git-проектам: расхождения у 4. Попутная находка: проверка трижды требовала больше, чем требует процитированный ею механизм |
| 🧰 Одиннадцать действующих дефектов | v1.16.1 | ✅ | Пакетное закрытие долга: из 23 открытых пунктов 11 — действующие дефекты, и **три отчёта из одиннадцати описывали причину неверно**. Худшее: на упавшей Bash-команде PostToolUse не срабатывает вообще — хук переписан на PreToolUse, серия провалов считается по расшифровке, «стой» приходит перед следующей попыткой; счётчик `/compile` врал в 28 раз; лог инжектов не ротировался третий месяц. Адверсариальный прогон по своим же правкам нашёл три блокера в них же: уборка throttle уничтожила выборку гейта (122 файла, пересобрать нечем), сплошной обход контракта молча проходил без jq, «опровержение» calibrate.py само мерило не тот файл. Открытых: 23 → 14 |
| 🪞 Три находки предыдущей проверки | v1.16.2 | ✅ | Ложная тревога в живых метриках, созданная вчерашней же ротацией: «3432 битых строки» — ровно размер архива, смешение знаменателей. Блокер переносимости срабатывал на КОММЕНТАРИИ, где `date -j` перечислен как запрещённый, — заведён `ds_code_only` по правилу комментария оболочки. У `drift-check` седьмая проверка: хук может лежать побайтово верным и висеть на не том событии — призрак называется поимённо, но не чинится (цену автоудаления по предположению вчера уже заплатили). Число пар в строке итога считается из вывода, а не пишется руками |
| 🧹 Уборка, которая отчитывалась вместо уборки | v1.16.3 | ✅ | Собеседник: «бэклог не почистился» — и верно: строка реестра стояла в режиме `check`, уборка сообщала «13 выполненных пунктов» и не переносила ни одного. Переведена в `run`: 77 → 51 строка, свидетельства закрытий целы. Гейт достоверности печатал «пройден» на выборке из двух сессий — добавлен порог минимальной выборки: ниже него прямое «вывод о достоверности не делается», код возврата 2. Плюс двойной ноль `grep -c '.' \|\| echo 0`, ждавший первой сессии без единого срабатывания |
| ⚖️ Прибор для разрыва «знание → действие» | v1.17.0 | ✅ | Blocker-знание висело в контексте, было уместно дважды за сессию — и ни разу не применено; записать это было некуда: любой из трёх исходов словаря означал бы враньё. Четвёртый исход `applicable_not_followed`: счётчики знания не трогаются — пропуск не подтверждает и не опровергает знание, он измеряет разрыв. Строка в `metrics.md` «знание было уместно и не применено: N» — единственная величина, прямо отвечающая на вопрос, ради которого проект существует. Попутно: каждая запись исхода текущей сессии считалась дважды — счёт шёл по обоим файлам сразу |
| ⏰ Условие возврата, выполненное в 132 раза | v1.17.1 | ✅ | «Разберись с остатками» → первым делом проверить, не выполнились ли условия ожидания: **условие D16 (событий ≥ 20) было выполнено в 132 раза (2645), гейт смотрел в окно последних сессий вместо корпуса**. Генератор рекомендаций калибровки сравнивал разные величины: совет строился на счётчике, растущем только на НЕигнорированных вмешательствах, тогда как потолок расходуют именно игнорированные — доказательство лежало в отчёте открыто три месяца. Из 13 отложенных пунктов девять несли условие возврата прозой — заведены механические проверяющие, каждый проверен в обе стороны. Открытых: 13 → 7 |
| 📖 Ответ лежал записанным три месяца | v1.17.2 | ✅ | Журнал смешения алфавитов писался с апреля, и не читал его никто. Разбор 2690 записей: 94% — вообще не нарушения (составные через дефис — нормальное русское техническое письмо), настоящих 166, и в них лежал ответ: **май 81 → июнь 66 → июль 9**. Исторический шум вычищен (167 файлов → 64), метрика показывает тренд за 30 дней, а не застывающий итог. Второе: механизм проверки соответствия существовал с v1.16.0, но описание `/init-project` о нём молчало — переписано под оба применения; по решению собеседника проверка остаётся ручной. Открытых: 7 → 5 |
| 🔁 Четыре кейса одной формы — паттерн | v1.17.3 | ✅ | `/retro` по сессии из девяти релизов: значимой оказалась не отдельная ошибка, а форма, повторившаяся четырежды — **замер исполнен, числа настоящие, а относится он к другому объекту, чем поддерживаемое им утверждение** (не то место, не тот файл, не та величина, не то правило). Записан `pattern-subject-of-measurement-mismatch` (confidence 3, impact 5, 4 кейса-источника), двусторонние ссылки кейс↔паттерн во всех четырёх. Counterfactual разделил корни честно: адверсариальная проверка собственных правок покрыла бы все три случая — и она не входит в релизный путь; это записано выводом для будущей работы |
| 🔔 Проверка CI встроена в путь | v1.17.4 | ✅ | D60 оставался последним действующим пунктом: `ci-status.sh` заведён после двух ложных «CI зелёный», но его надо было не забыть вызвать — уровень 1 по `principle-knowledge-in-the-world`. Новый `ci-check-reminder.sh` (PostToolUse) в момент состоявшегося `git push` инжектит напоминание проверять прогон СВОЕГО коммита — сразу после push самым свежим числится предыдущий прогон. Детект по исполняемой части команды: «git push» в кавычках и heredoc — аргумент, а не команда. Уровень поднят с 1 до 2. Открытых: 6, действующих дефектов нет |
| 🚪 Заявка закрыта механизмом; публикация подменяет личные файлы | v1.18.0 | ✅ | Заявка на эскалацию висела 102 дня при пороге 60 — закрыта тем, что сама и просила: `fix-level-check.sh` ловит в собственном ответе пост-инцидентный фикс уровня 1 («надо вынести урок», «будем осторожнее») и напоминает поднять до механизма либо пометить model-generated; словарь из задокументированных проявлений, не придуман. Публикация: шаг 2b `scripts/publish/replace/` — файл, личный по структуре (заголовки секций выдают географию), подменяется публичным шаблоном целиком; 10 растяжек в гейте делают подмену доказуемой. **Первый прогон гейта поймал сам CHANGELOG релиза**: описание политики запрещённых имён содержало запрещённое имя — механизм проверил собственного автора. Roadmap этой таблицы догнал реальность (+13 строк) |
| 🌉 Мост L4↔L5: предсказания получили прибор точности | v1.19.0 | ✅ | Первый мост, реализованный по приоритету «данные готовы»: 52 секции Predictions и 107 решённых предсказаний уже лежали в SESSION.md (exact 47 / adjacent 43 / miss 17 → 64%). Тип в номере (`P3:need` — topic\|reaction\|need\|action), история не переписывается — старые строки считаются `untyped`. Агрегация в `metrics-collector` через `prediction-calibration-lib.sh` (22 случая теста, включая корень с пробелом в пути — регресс на пойманное до коммита словоразбиение); правило калибровки: тип точнее 80% — повышай confidence, ниже 40% — снижай; рекомендации уходят `- ⚠️`-строками в канал, который читает activator. Гейты выборки: секций < 5 или тип с n < 5 — вердикт не выносится |
| 🤝 Мост L2↔L7: со-мышление получило прибор глубины | v1.20.0 | ✅ | Второй мост подряд по приоритету «данные готовы»: 20 записей `origin: co-cognition` уже лежали в базе. Первый же замер подтвердил тезис моста числом: совместно рождённые знания глубже solo — **средний impact 4.1 против 3.2**, главный триггер — противоречие (×9), затем вопрос (×8) и аналогия (×3). `co-cognition-lib` считает доли origin и co_cognition_ratio (10%), тренд — аудит по истории; правило «инсайт из обсуждения записывай сразу» встало в глобальные правила с измеренным обоснованием. Два дефекта пойманы до коммита: атрибуция impact зависела от порядка полей frontmatter; `ls` с тремя глобами читал ядро из одних case-файлов как пустое |
| 🗣️ Мост L3↔L7: у пары появился слух на собственный язык | v1.21.0 | ✅ | Третий мост подряд по готовности данных: словарь проекта уже жил в памяти и грузился каждую сессию — не хватало выявителя. Теперь session-collector на Stop предлагает кандидатов: латинские/составные токены собеседника ≥ 3 раз за сессию, которых в словаре нет. Сигнал синтаксический, не частотно-языковой (урок v1.13.3 про придуманные словари: 9 срабатываний за 214 сессий, ноль полезных); служебные «user»-сообщения отброшены до токенизации; гейт шума — детектор молчит в проектах без словаря. Записывает по-прежнему человек: детектор предлагает, словарь курируется |
| ⛔ Сигнал условия возврата пережил долг — и больше не переживёт | v1.21.1 | ✅ | «Калибруй» строился на строке «D16/D17 — можно калибровать», горевшей в каждой сессии ПОСЛЕ закрытия пунктов: сигнал мерил объём данных, не состояние долга (5-й кейс «предмет замера не тот»; впервые форма поймана на себе ДО работы, а не после). Свежий прогон калибратора на 2211 чанках переподтвердил вердикт v1.17.1 — константы не тронуты. Корень: `_backlog_open` гейтит все 8 эмиссий состоянием пункта (☐/◐ = открыт), структурный тест красит эмиссию без охраны — и первым же прогоном поймал собственный комментарий (ds_code_only) |
| 🔑 Авторизация стала состоянием задачи | v1.22.0 | ✅ | ADR-010 Ф1. Детектор проверял авторизацию по одной предыдущей реплике — в длинной работе там task-notification, и правки под «делай» писались как самовольные (те самые 62%). Теперь поручение взводит состояние, гасит его только следующая настоящая реплика не-продолжение; правки под авторизацией пишутся `solicited` и бюджет не тратят. Маркеры уехали в `authorization-lib` единым источником. Три дефекта пойманы тестами до коммита: fallback был недостижим (писатель создавал файл раньше проверки его отсутствия), один ход мог записаться дважды под разными типами (дедуп-ключ включал тип), и пять старых ожиданий «no event» отстали от нового контракта |
| 🚦 Бюджет получил первого исполнителя | v1.23.0 | ✅ | ADR-010 Ф2+Ф3. `budget-gate` — первый за всю историю системы читатель остатка бюджета (D17 закрыт по существу): самовольная правка при пустом бюджете получает «преврати в вопрос»; под поручением, без данных и повторно — молчит. Включён только ПОСЛЕ A/B на 10 транскриптах: направление подтверждено (ни одного роста proactive, дельта 1/22 — ровно случай «делай → уведомление → правка»), gentle-контроль неизменен. Замер по дороге дважды опубликовал нули как данные (расщеплённая песочница; страта без правок) — в прибор встроен отрицательный контроль, а обе ошибки записаны в сам скрипт |
| 📦 Модули получили документацию, проекты — свой долг | v1.24.0 | ✅ | Поправка собеседника: правило «новый модуль → док» существовало текстом и не исполнилось ни разу (41 хук, ноль доков). Заведена конвенция `.claude-docs/modules/` (семь доков; каталог трекается точечной негацией в .gitignore — ловушка «страж требует нестейджабельного» поймана до коммита) и страж module-doc-check. Второе: хук долга работает и в инициированных проектах — локальный BACKLOG.md по cwd считается В ДОПОЛНЕНИЕ к системному (урок v1.15.1 держится с двух сторон); правка параллельной сессии (архив не считается + подсказка ре-аудита) вплетена и получила тесты |

## MCP-сервер

Семантический поиск и визуализация знаний через [Model Context Protocol](https://modelcontextprotocol.io/).

### 9 инструментов

| Tool | Назначение |
|------|-----------|
| `search_knowledge` | Семантический поиск по базе знаний (sqlite-vec + fastembed) |
| `reindex_knowledge` | Переиндексация всех knowledge-файлов |
| `knowledge_stats` | Статистика: типы, уверенность, здоровье |
| `get_knowledge` | Чтение конкретного knowledge-файла |
| `knowledge_graph` | Экспорт графа знаний в JSON |
| `open_graph` | Визуализация графа в браузере (D3.js, force-directed) |
| `open_dashboard` | Dashboard метрик базы знаний |
| `brain_export` | Экспорт всего "разума" в .tar.gz архив |
| `brain_import` | Импорт архива на другую машину (smart merge) |

### Визуализация

Два режима — 2D (`index.html`, D3.js) и 3D (`universe.html`, 3d-force-graph + Three.js). Оба запоминают настройки (ползунки, чекбоксы, фильтры) в localStorage между обновлениями страницы.

**Граф знаний** — двухосевое кодирование:
- **Тип → оттенок** (первичная палитра): principle — amber, pattern — teal, case — violet, плюс отдельные оттенки для entity/fact/relation
- **Масса** (confidence × impact) → яркость в пределах оттенка
- **Домен → цвет ободка** (вторичная палитра из 10 цветов, deterministic через FNV-1a). В 3D ободок — камера-обращённый спрайт, не перекрывает силуэт
- **Статус → яркость свечения**: active 1.0 → deprecated 0.15
- **Рёбра** — Line2 с worldUnits толщиной (ползунок «Толщина»), градиент между цветами концов

**3D дополнительно:** гладкие сферы (SphereGeometry), per-domain туманности с ShaderMaterial falloff, космический ветер (600 частиц в ±1500 world units), контекстное меню на правый клик с действиями «Открыть в Finder / Переместить в архив / Удалить навсегда» — архив/удаление требуют подтверждения и сразу перестраивают граф.

**Dashboard** — метрики здоровья базы знаний:
- Распределение уверенности и влияния
- Покрытие доменов, средняя масса по типу
- Топ/bottom по надёжности, последние обновления

### Портируемость

`brain_export` упаковывает knowledge, skills, hooks, templates, domains, sessions, БД, настройки и правила в один архив. `brain_import` на другой машине делает smart merge: знания сравниваются по confirmed_count (выше побеждает), скиллы обновляются, домены добавляются.

## Исследования

| Источник | Что взяли |
|----------|----------|
| [A-MEM](https://arxiv.org/abs/2502.12110) | Zettelkasten-связи, динамическая линковка |
| [FSRS](https://domenic.me/fsrs/) | Кривая забывания, stability-based интервалы |
| [Self-Improving Agents](https://addyosmani.com/blog/self-improving-agents/) | 4 канала персистентности |
| Когнитивная психология | Эпизодическая/семантическая память, метакогниция |
| Экономика / теория продаж | Demand-first, компоненты спроса |
| Бусидо / Искусство войны | Путь как процесс, самостимуляция |

## Установка

```bash
git clone https://github.com/Nugnii/ClaudSoul.git
cd ClaudSoul
./install.sh
```

## Замечания по безопасности

Две вещи, которые надо понимать до установки:

- **`install.sh` меняет глобальную настройку Claude Code.** Он переписывает `~/.claude/CLAUDE.md` (между явными маркерами, с бэкапом), вливает конфигурацию хуков в `~/.claude/settings.json` (тоже с бэкапом), регистрирует пользовательский MCP-сервер, а на macOS ставит три launchd-агента (read-only сканер проектов и два периодических дайджеста). Это не изолированный плагин: если хочется просто посмотреть — читайте репозиторий или попробуйте на отдельной машине или профиле.
- **`brain_import` — только со своими архивами.** Архив «мозга» несёт исполняемые скрипты хуков и скиллы; импорт перезаписывает их и вливает конфигурацию хуков в настройки. Импортировать чужой архив — то же самое, что запустить чужой код на своей машине. По умолчанию инструмент работает в режиме предпросмотра и ничего не применяет, пока не передан `dry_run: false`. Экспорт и импорт существуют, чтобы переносить *свой* мозг между *своими* машинами, а не обмениваться мозгами с незнакомцами.

## Лицензия

MIT

## Автор

Константин Берсенев — [@Nugnii](https://github.com/Nugnii)
