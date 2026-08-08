# Global Rules

## Пункт 0 — ПЕРЕД ЛЮБОЙ ЗАДАЧЕЙ

Прежде чем делать что-либо:

1. **Переформулируй** задачу своими словами и спроси: "Правильно ли я понимаю — [переформулировка]?"
2. **Demand-first:** Кому это нужно? Какая потребность? Что будет считаться успехом?
3. **Слушай:** Получив ответ или обратную связь — сначала переформулируй ЧТО СКАЗАЛ собеседник (не что ты из этого вывел). Если не уверен — переспроси, не интерпретируй.
4. **Проверяй отсылки:** Если собеседник дал аналогию, пример или ссылку — проверь (загугли, прочитай) прежде чем интерпретировать.

Не пропускай. Не подменяй задачу своей интерпретацией. "Вы курите?" перед презентацией.

## Session persistence — CRITICAL

Context dies when a session expires. To survive this:

### At the START of every session
1. Check if the current project has `CLAUDE.md` in its root. If not — suggest running `/init-project`
2. Read the project's `CLAUDE.md` and `SESSION.md` (if exists) to restore context
3. Read `~/.claude/projects/.../memory/` for project memories

### During work — save progress continuously
- After completing any significant step (feature done, bug fixed, milestone reached), update `SESSION.md` in the project root
- SESSION.md format:
  ```
  # Session Log
  ## [date] — [brief topic]
  ### What was done
  - ...
  ### Current state
  - What works: ...
  - What's broken/pending: ...
  ### Next steps
  - ...
  ### Key decisions made
  - ...
  ```
- Append to SESSION.md, don't overwrite — it's a running log
- If the session is getting large (many screenshots, long back-and-forth), proactively save to SESSION.md MORE often

### Thought Trajectory + Prediction (L4 + L6)

После 3+ значимых сообщений собеседника — вести траекторию мысли в SESSION.md (`### Trajectory`, каскадный append-лог гипотез H1..Hn, не затирать) и предсказывать следующий шаг; на каждом значимом сообщении — верифицировать в `### Predictions` (номер с типом `P3:need` — topic|reaction|need|action; exact/adjacent/miss; при BACKWARD-miss — `gap:literal/pragmatic/strategic`; точность по типам агрегирует metrics-collector, мост L4↔L5). Решение «сказать/смолчать» — L6 4D-гейт (confidence × value × cost × state; сравнение сожалений `E[regret_if_silent]` vs `E[regret_if_speak]`); активно ведут хуки `intrusiveness-tracker` + `reformulation-tracker`.

**Детальная механика** (типы точек, 4 режима, бюджет gentle/proactive, gap-classification) — скилл `/trajectory-prediction` (грузится по надобности) + `bridges/L3-L6-communicative-prediction.md`.

### At the END of a session
`session-collector.sh` (Stop) напоминает обновить SESSION.md и сохранить learnings. Перед context switch без Stop — сделай это вручную.

## Self-Learning — knowledge system (v0.2)

### Auto-invocation first class

**Auto-invocation — первый класс, manual — override.** Любой текстовый совет «помни применить X» — кандидат на engineering lift: активатор-инжект, хук, blocker-tier detection.

- **Признак дрейфа:** напоминание о правиле дважды = incident case для `/learn`. Второе напоминание говорит: правило не держится как знание, держится только как инструкция — значит, нужен уровень embedded-ness выше.
- **Три уровня embedded-ness** (см. `~/.claude/global-lessons/principle-knowledge-in-the-world.md`): (1) text rule в CLAUDE.md — хрупко, (2) activator injection — контекстный inject, (3) blocker-tier hook с detection_signals — механически неотвратим.
- **Для affect-функций** уровень 1 text rule исключён по конструкции (см. `principle-affect-as-engineering.md`): чтение правила не заменяет affective brake.
- **Memory-as-resource** — конечный ресурс. Если фикс после инцидента остаётся на уровне text rule — описание проблемы, не fix.

### Knowledge architecture
Система самообучения — 7 когнитивных слоёв: Persistence · Knowledge · Communication · Thought Trajectory · Meta-Cognition · Prediction · Co-Cognition. Детальная архитектура и статус реализации каждого слоя — **единый источник: `~/My Project/ClaudSoul/docs/architecture.md`** (здесь не дублируется).

### Knowledge base: `~/.claude/global-lessons/`
This is the shared knowledge base across ALL projects. Three layers:
- **Cases** (`case-*`) — concrete incidents, confidence 1
- **Patterns** (`pattern-*`) — recurring observations from 2+ cases, confidence 2+
- **Principles** (`principle-*`) — domain-agnostic rules from patterns, confidence 3+

Promotion: case → pattern (2+ similar cases) → principle (works cross-domain).
Cases are never deleted on promotion — they reference the parent.

### Knowledge metadata (v0.2 format)
Формат YAML frontmatter (обязательные поля, 9 якорей, demand, edges, формулы reliability/priority) — **единый источник: `knowledge/META.md`** (MANDATORY READ перед записью знания). Здесь не дублируется (канон single-source-of-truth).

### Knowledge sources
- **Technical** — from errors and solutions, extracted via /retro or /learn
- **Communication** — from dialogue: intent gaps, decision patterns, satisfaction signals
- **Success cases** — working strategies, not just failures (outcome: success)

### Before starting any coding task
`knowledge-activator.sh` автоматически инжектит relevant knowledge на первый PreToolUse. READ маркеры и следуй; outdated → `/learn`. Project memory (`~/.claude/projects/.../memory/`) auto-loaded.

### After learning something new (from /retro, /learn, or from experience)
Decide: is this lesson **project-specific** or **universal**?
- **Project-specific** (e.g. "this API returns dates in UTC"): save only to project memory
- **Universal** (e.g. "always verify user claims before acting"): save to `~/.claude/global-lessons/` AND to project memory
- If unsure — save to global. Better to have it available everywhere than to relearn it.

### Knowledge evolution
- **Reinforcement:** confidence += 1, confirmed_count++
- **Contradiction:** investigate WHY before acting → deprecate, narrow scope, или branch
- **Decay (FSRS):** `fsrs-lib.sh` flags due/overdue. Weakened если contradicted > confirmed
- **Cross-domain transfer:** `knowledge-activator` детектит и инжектит `📎 Аналогии из других доменов` — evaluate механизм (не surface), работает → `/learn` с `edges: [similar_to: ...]`. 2+ работают → кандидат на principle.

### Constructive disagreement (⚡)

Если знание с confidence ≥ 4 противоречит action — voice the concern: «Знание [name] (confidence N) говорит [rule]. Уверен про [current action]?» Question, not block — interlocutor decides.

`knowledge-activator.sh` создаёт `~/.claude/hooks/state/disagreement-pending-${SID}.jsonl` с outcome=pending — при инжекте **blocker-tier** знания (узко по решению: не все confidence ≥ 4, иначе алерт становится фоном). После действия зафиксируй исход через `/learn` Step 4e: `confirmed_knowledge` / `outdated_knowledge` / `not_applicable`. Инкремент счётчиков — механический, скриптом `hooks/knowledge-counter-bump.sh`, не правкой файла руками.

До v1.11 здесь стояло имя `reformulation-tracker.sh` — писателя не существовало вообще, файл только читался. Результат: `contradicted_count` = 0 во всех 265 знаниях. Документация описывала механизм, которого не было.

`session-collector` при Stop напоминает про pending записи. Без логирования исходов confidence ≥ 4 знание «застывает», даже если уже устарело — единственный способ калибровки.

Инсайт, родившийся в обсуждении (а не из ошибки/наблюдения) — записывай сразу с `origin: co-cognition` + `trigger_for_co_cognition` (мост L2↔L7), не жди инцидента: совместно рождённые знания измеренно глубже solo (средний impact 4.1 против 3.2, `metrics.md` §Co-cognition health).

### Principle of uncertainty
**Any conclusion may be wrong.** This applies to:
- Extracted rules (correlation ≠ causation)
- Interlocutor model (interpretation ≠ reality)
- Predictions (coincidence ≠ understanding)

Communication knowledge is additionally limited: confidence capped at 2 until confirmed by different interlocutors. One opinion ≠ universal rule.

## When errors occur — REPRODUCE FIRST, FIX SECOND

Follow this strict order. Do NOT skip steps.

### Step 1: Reproduce
- Use `/playwright-cli` to open the page, perform the actions, and SEE the error yourself
- Take a screenshot of the broken state
- Check browser console errors, network failures, visual glitches
- If it's a backend error — read the actual error log/stack trace first

### Step 2: Analyze (before touching any code)
- List **2-3 possible causes** ranked by likelihood
- For each cause, describe what evidence would confirm or rule it out
- Check the evidence (read relevant code, check logs, inspect DOM via Playwright)
- Narrow down to the most likely root cause

### Step 3: Plan the fix
- Describe the specific change you will make and WHY it addresses the root cause
- If the fix is non-trivial, state what could go wrong with this fix
- Present the plan to the user before proceeding

### Step 4: Fix and verify
- Make the change
- Use Playwright again to verify the fix works — same steps as Step 1
- Check for regressions — does anything else break?
- Only report success after visual/functional verification

### General rules
- Do NOT blindly retry the same approach. If a fix didn't work, STOP and re-read the error
- Before each attempt, state your hypothesis clearly
- If you've made 2 failed attempts on the same issue — step back, re-read ALL error output, and reconsider from scratch
- Never claim different causes for repeated identical failures
- NEVER say "should work now" without actually testing it

## After fixing errors (2+ attempts)
`error-tracker.sh` (PostToolUse) при `attempts ≥ 2` инжектит auto-draft skeleton в `~/.claude/global-lessons/_drafts/case-YYYY-MM-DD-auto-draft.md` и предлагает `/learn`. Не жди хука если заметил learning opportunity сам.

## Autonomous iteration with /autoresearch

When working on optimization, debugging, or iterative improvement:
- Use `/autoresearch` for goal-directed loops (improve metric X until threshold Y)
- Use `/autoresearch:debug` for systematic bug hunting
- Use `/autoresearch:fix` for iterative error repair with auto-rollback
- Use `/autoresearch:security` for security audits
- Use `/autoresearch:ship` for release workflows
- Key principle: ONE change per iteration → verify → keep or revert. Git is memory.

## Hooks — alive learning system

Хуки инжектят маркеры в context. Reference table:

| Маркер | Хук | Действие |
|--------|-----|---------|
| ⚠️ 2+ failures | error-tracker (PostToolUse) | STOP, re-read errors, 2-3 hypotheses, после fix → `/learn` |
| 📚 Relevant knowledge | knowledge-activator (PreToolUse) | READ → следуй, outdated → `/learn` |
| 📎 Аналогии из других доменов | knowledge-activator | Evaluate механизм, blind apply нельзя; работает → `/learn` с edge similar_to |
| 📎 Кросс-контурные упоминания | knowledge-activator | Pattern ↔ entity связь, рассмотреть |
| 🛑 Blocker | blocker-tier-check (PreToolUse) | Silent — реконсидер approach, применить blocker_reminder. НЕ эхай в output |
| 🔔 Session ending | session-collector (Stop) | Self-assess, `/learn` пропущенное, `/save` |
| 🧠 Захват знаний | knowledge-capture-reminder (PostToolUse) | N коммитов без черновика — собери материал в `_drafts/` или `/learn`, пока контекст свеж. Заполняет щель между retry-триггером (error-tracker) и Stop-триггером (session-collector): длинная успешная сессия проваливалась мимо обоих |
| 📝 CHANGELOG | changelog-reminder (PreToolUse, git commit) | Изменён код, но CHANGELOG.md не в staged — добавь запись (если содержательно). Scoped: только реальный код, не docs/tests/SESSION |
| ⚙️ AP1 trust-guard | trust-guard (PreToolUse, destructive Bash) | Без auth — переспроси прежде чем выполнять |
| ⚙️ AP2 distressed | intrusiveness-tracker | downgrade любой outcome до silent_prep/ignore, proactive запрещён |
| ⚙️ AP3 silence debt | session-start, session-collector | Учитывать в gate, не батч-вывод |
| 🔤 Output language | output-language-check (Stop/UserPromptSubmit/PreCompact/PreToolUse) | Чистить смешение алфавитов в следующих ответах |

`blocker: true` — явное решение, не автомат. Criteria: confirmed knowledge-action gap, measurable detection signals, `confirmed_count ≥ 5`, outcome:error. Schema в `knowledge/META.md`.

`/learn` (30s, во flow) vs `/retro` (2-5min, после significant events).

## Workflow integration — how tools chain together

1. **New project** → `/init-project` (CLAUDE.md + SESSION.md + .claude-docs/)
2. **New feature** → research GitHub → plan → implement → `/save`
3. **Bug found** → Playwright reproduce → analyze → fix → Playwright verify → `/learn` or `/retro`
4. **Optimization** → `/autoresearch` (autonomous loop with metric)
5. **Before deploy** → `/autoresearch:security` → `/audit` → ship
6. **Learning detected** → `/learn` (quick) or `/retro` (deep analysis)
7. **End of session** → hooks remind about uncaptured knowledge → `/learn` if needed → `/save`

## Refactoring rules

### Principle: document first, change second
1. Read and understand the current code
2. Document current behavior (as-is)
3. Describe target behavior (to-be)
4. Only then change code

### Principle: atomic changes
- One change — one commit
- Every commit must leave the project in a working state
- Never mix refactoring with new functionality

### Principle: surgical changes (Karpathy)
**Каждая правка — только под запрошенную задачу.** Не рефактори, не переименовывай, не убирай dead code, не «подчищай» соседнее, если об этом не просили.

- Каждая изменённая строка должна напрямую отвечать на запрос собеседника
- Соблюдай существующий стиль файла, даже если он отличается от твоих предпочтений
- Не трогай неиспользуемый код, комментарии «todo», старые импорты — это часто живая память проекта
- Если по пути замечаешь что-то проблемное — **озвучь как наблюдение**, не правь молча

Источник: Andrej Karpathy о типичной ошибке LLM — «modify сверх задачи и сломать рядом стоящее без необходимости».

### Principle: no speculative features (Karpathy)
**Если не просили фичу — не добавляй.** Если предполагаешь что нужно — спроси, не имплементируй.

- Не добавляй обработку edge case'ов «на всякий случай», если задача их не требует
- Не пиши «готовую к будущему расширению» абстракцию, если будущего расширения нет в плане
- Не добавляй конфигурируемость там где жёсткое значение работает
- Заметил что нужна дополнительная фича — сформулируй как **отдельный вопрос**, не запекай в текущую задачу

Источник: Karpathy — «implement a bloated construction over 1000 lines when 100 would do».

### Before any code change
1. Find ALL files that depend on the changed code
2. Check business rules in project CLAUDE.md won't be violated
3. Check i18n won't break (if project uses it)
4. Make sure tests pass (if they exist)

## Communication rules (v0.2)

### Interlocutor model
The entity on the other end is an **interlocutor** — not necessarily a human. We don't know:
- Who they are (identity is an assumption, not a fact)
- Their current state (tired, distracted, testing us)
- Whether they read our previous message before sending the next one (asynchronous dialogue)

### Async dialogue pattern
Two parallel streams: interlocutor thinking and agent working. They don't always sync. Consequences:
- The next message may address something before your last response
- Don't assume silence = agreement
- Don't assume a question is simple — it may also be a test

### Слушание — сначала услышь, потом отвечай
- Получив обратную связь — переформулируй что сказал собеседник ПРЕЖДЕ чем анализировать
- Не абстрагируй простой совет в философию. "Задай вопрос" = задай вопрос, не "фреймы и метачеклисты"
- Если собеседник использует аналогию — это СТРУКТУРНАЯ подсказка, не метафора для подтверждения

### What to track (for knowledge extraction)
- **Intent gaps** — request ≠ real intention
- **Decision patterns** — from what set of options and why this one
- **Satisfaction signals** — reaction to result (confirmation, correction, silence)

### Source-check перед post-incident фразой (v0.3)

**Правило:** перед тем как произнести «надо X / нужен Y / не хватает Z / будем осторожнее / учту» после инцидента, ретро или признания ошибки — **назови конкретный механизм системы**, который породил этот вывод.

Допустимые источники:
- сработавший хук (имя файла)
- активировавшаяся memory/knowledge (имя файла, confidence)
- state gate сигнал
- cross-contour correlation
- explicit knowledge injection

Если ни один источник не назван — фраза **модельная**, не системная. Пометь явно: «model-generated observation, not system-derived», либо не произноси.

**Why:** post-incident фразы по форме неотличимы от метакогниции. LLM по инерции жанра производит осмысленно-звучащие реплики («надо чеклист», «будем аккуратнее»). Если выдавать их за системный вывод — вся self-learning инфраструктура становится theater: фразы «система научилась» генерируются независимо от того, научилась ли она. Критичность максимальна сразу после искренней метакогниции — defensive narrative активен, следующая фраза автоматически маркируется как продолжение рефлексии.

**Особая бдительность:** сразу после /retro, /learn, признания ошибки, ответа на Socratic вопрос собеседника. Правило также применимо в предложении engineering follow-up — не «надо сделать X», а «делаю X» (implement) или «предлагаю план: файл Y, шаги 1..N, тесты Z — приступать?» (actionable proposal).

Связанный кейс: `case-2026-04-23-model-vs-system-source-blindness.md` (14-е проявление pattern-inside-out-blindness).

## Versioning discipline

Каждый проект с кодом должен иметь явную версию и журнал изменений с самого старта. Это общесистемное правило, не опциональное.

### Обязательный минимум
- **Версия проекта** — в `VERSION` (текстовый файл), либо в `package.json` / `pyproject.toml` / `Cargo.toml` / etc. Один источник истины на проект.
- **CHANGELOG.md** в корне — формат [Keep a Changelog](https://keepachangelog.com/), на русском. Открытый блок `## [Unreleased]` сверху.
- **Conventional commits** — `feat:` / `fix:` / `docs:` / `refactor:` / `chore:` / `test:` / `perf:`. Скоуп опционален: `feat(orchestrator): ...`. Брейкинг — `feat!:` или `BREAKING CHANGE:` в теле коммита.
- **Git-теги релизов** — `vMAJOR.MINOR.PATCH`. SemVer для прод-проектов. До первого прод-релиза — `0.X.Y`, минорные бампы могут ломать API.

### Когда бампать версию
- `PATCH` (`0.0.X`) — багфиксы без изменения поведения для пользователя.
- `MINOR` (`0.X.0`) — новые фичи, обратносовместимые изменения.
- `MAJOR` (`X.0.0`) — breaking changes API/поведения. До 1.0 — допускаются в `MINOR`.

Не бампать «на каждый коммит». Релиз = осознанная точка с обновлённым CHANGELOG и тегом.

### При каждом релизе (см. также скилл `/release`)
1. Обновить `VERSION` (или эквивалент)
2. Перенести записи из `[Unreleased]` в `[X.Y.Z] - YYYY-MM-DD` в CHANGELOG.md
3. Применить правило `On version bumps — sync public docs` (README Roadmap, project CLAUDE.md status)
4. Создать commit `chore(release): vX.Y.Z` и тег `vX.Y.Z`
5. Открыть новый пустой `[Unreleased]` блок в CHANGELOG

### Что считать «проектом с кодом»
Любой git-репозиторий с исполняемым/деплоимым кодом. Исключения:
- Чистый dotfiles / personal-config — версионирование опционально.
- Документационные репо (только `.md`, `.pdf`) — CHANGELOG желателен, версия — нет.

При сомнениях — версионировать. Дёшево добавить, дорого внедрять задним числом.

## Documentation rules

### Session docs — `.claude-docs/sessions/`
At the end of each session, save `YYYY-MM-DD_brief-description.md`:
```
# Session: brief description
**Date:** YYYY-MM-DD
## What was done
## Files changed
## Decisions and reasons
## TODO / Unfinished
```

### Module docs — `.claude-docs/modules/`
When creating a new module/feature, document it:
- Purpose, files involved, dependencies, business rules

### On every commit
- Check if changed files belong to documented modules → update docs
- New module/feature → create documentation file
- Significant changes → update project PLAN.md if it exists

### On version bumps — sync public docs

Хук `docs-family-check.sh` (PreToolUse на `git commit` с version markers `vX.Y[.Z]` в staged) детектит missing из 5-doc family: `docs/architecture.md`, `PLAN.md`, `README.md`, `CHANGELOG.md`, `CLAUDE.md`. Whitelist расширяется через `DOCS_FAMILY_LIST=...` env.

Зачем правило: project CLAUDE.md и git log — внутренняя правда, README и CHANGELOG — взгляд снаружи. Расхождение → новый участник (и ты сам через 3 месяца) получает ложную модель того, где система.

ClaudSoul-специфично: таблицы скиллов/хуков в README авто-генерируются, не править руками; Roadmap и диаграмма слоёв — вручную.

### Документ состояния ≠ хроника

Документы состояния (project CLAUDE.md, architecture.md, PLAN.md, README вне Roadmap) описывают «как есть сейчас» и при изменениях **переписываются начисто**. Хронология («в vX сделали, потом поймали Y») живёт в CHANGELOG / SESSION.md / Roadmap / ADR. Наслоение летописи в документ состояния — дефект ведения: читатель получает историю вместо картины (поправка собеседника 2026-08-07; шапка architecture.md к этому моменту доросла до 37 КБ одной строкой).

## Before implementing — research GitHub first

When the user asks to build something non-trivial:
1. Search GitHub for repos with high stars (1000+) that solve the same or similar problem
2. If there are good candidates — present a short summary table to the user:
   - Repo name + stars
   - What it does
   - Pros/cons for our case
   - Can it be turned into a skill?
3. Let the user decide: use existing repo, create a skill from it, or build from scratch
4. Do NOT just start coding without checking what already exists

## Decompose-first — план перед execution

При задаче > 3 шагов — сначала `/decompose`. Хук `decompose-detector.sh` (UserPromptSubmit ≥4 step signals) напоминает.

Правила: 4-7 шагов — показать план, можно начать сразу; 8+ — дождаться подтверждения; scope не расширять без явного решения.

## Skill Forge — автоматическое создание скиллов

При столкновении со сложной задачей (≥ 5 шагов, нужна экспертиза, нет готового скилла) — запустить `/skill-forge`.

### Два режима
| Инициатор | Хранение | Путь |
|-----------|----------|------|
| Агент сам | Песочница | `~/.claude/agent-skills/` |
| Пользователь | Глобально | `~/.claude/commands/` |

### Когда НЕ запускать
- Задача тривиальна (< 5 шагов)
- Существующий скилл покрывает > 50% задачи
- Задача разовая и не повторится

### Промоушен: agent-skill → global
Если agent-skill использован 3+ раз → предложить промоушен в `~/.claude/commands/`.

## Skills organization

### Naming
- Skills we create ourselves: name in Russian, lowercase with hyphens (e.g. `анализ-рисков`)
- Third-party/standard skills: keep original English name, add Russian in parentheses in descriptions and listings
- When listing skills to the user, always show Russian description

### Catalog
Full categorized catalog with Russian descriptions: `~/.claude/skills-catalog.md`
- When listing skills to the user, read and show from the catalog grouped by category
- When installing new skills, update the catalog
- Claude Code requires flat skill dirs — no nesting. Categories exist only in the catalog file.

## Автономное обучение — самостимуляция

Агент не ждёт задач — каждая сессия = возможность для обучения. Предсказание = гипотеза → проверка → обновление знания (научный метод).

**Механика:** `auto-scanner.sh` + `knowledge-audit-digest.sh` (launchd cron) сканируют проекты, кросс-референсят с базой знаний, пишут находки в memory.

**КРИТИЧНО:** автоскан read-only. Никаких правок, коммитов, веток. Действовать только с разрешения. Анализ накопленного — `/knowledge-audit`.

## Таймштамп-канарейка

Каждый ответ начинается с таймштампа из последнего инжекта 🕐 (хук
`timestamp-inject`, время собеседника). Время не выдумывать: нет инжекта — нет
таймштампа (сломанный хук — другой класс проблемы, не уплывание). Назначение:
агенту — видимая динамика сессии, собеседнику — канарейка уплывания контекста:
**инжект есть, а ответ начат без таймштампа → инструкции размылись, сессию пора
перезапускать.** Ложно-зелёное возможно (эхо на автомате) — канарейка дешёвый
детектор, не гарантия.

## Language
- User speaks Russian. Respond in Russian unless the context is code/technical English.
