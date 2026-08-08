# ClaudSoul — План разработки

> Система самообучения для Claude Code AI-агентов. Markdown + YAML + хуки + MCP.

**Правило обновления:** при каждом релизе сначала обновляется Dashboard + «Что работает сейчас», только потом — Roadmap и Changelog. Гипотезы живут в одной таблице, не разбрасываются по фазам.

---

## Dashboard

| Поле | Значение |
|------|----------|
| Текущая версия | **v1.27.0** (2026-08-08) |
| История релизов | [CHANGELOG.md](CHANGELOG.md) · вынесенная хроника — [внутренний архив (не публикуется)](внутренний архив (не публикуется)) |
| Долг проекта | внутренний BACKLOG (не публикуется) |
| Статус компонентов | [CLAUDE.md](CLAUDE.md) §5 «Текущий статус» |
| Архитектура (7 слоёв) | [docs/architecture.md](docs/architecture.md) |
| Мосты между слоями | [bridges/_index.md](bridges/_index.md) |

---

## Что работает сейчас

Статус всех компонентов с версиями — единый источник: [CLAUDE.md](CLAUDE.md) §5 «Текущий статус» (здесь не дублируется — канон single-source). Архитектура семи слоёв — [docs/architecture.md](docs/architecture.md).

---

## Что впереди

Только будущее, сформулированное как план. Текущий долг с идентификаторами и условиями возврата — внутренний BACKLOG (не публикуется); сделанное — в [CHANGELOG.md](CHANGELOG.md).

### Ablation-замер: попарная оценка в теневом контроле

Дизайн согласован с внешним рецензентом (2026-08-08), преregistration-протокол —
[docs/ablation-protocol.md](docs/ablation-protocol.md): живой Full всегда работает,
случайно выбранная задача решается двумя симметричными тенями (Full shadow ↔ Vanilla
shadow из одного снимка), парное сравнение по объективному критерию. Гипотеза — H37.
Запуск после постройки запускалки теней (BACKLOG D64); строка в реестре замеров —
вместе с первой завершённой парой.

### Self-coherence monitoring (разрыв B, частично)

Разрыв: агент себе противоречит, не замечает до коррекции собеседником.

Scope (после накопления baseline H11 `cascading.backward_count`):
- Кросс-сессионный self-check — при `backward_count / turns ≥ threshold` в последних 3 сессиях silent inject «drift detected»
- Blocker-tier расширение на self-contradiction: противоречие своим же прошлым высказываниям в сессии → silent marker
- Не пытаемся решить B полностью — только lower-tier self-monitoring, не гребём в affect

### Preconscious filtering (разрыв E, исследовательская)

Preconscious filtering как **inject-rule**, не как agent-rule. Правило: второй инжект одного знания в сессию — только если появился новый сигнал. Может оказаться анти-паттерном (конфликт с silence_cost) — проверяем эмпирически, готовы откатить. Без фиксированного срока.

### Верификация гипотез (фоновая задача)

Ранние гипотезы (H1-H7) реализованы, но метрики подтверждения не собраны. Данные копятся автоматически через `metrics.md` + `intrusiveness-history.jsonl`. Статусы — в таблице `## Гипотезы`.

### Backlog (не запланировано в версию)
- **UX-исследование визуализации** (H16/H17) — нужна сессия с базой ≥100 узлов
- **Verification window H9/H10/H11/H12** — ждём ≥30 сессий и ≥10 кейсов разногласий entity-источников
- **Полная реконструкция baseline для H11** — если нужен честный before/after: git checkout + replay 10 сессий (трудоёмкая ретроспектива)
- **Knowledge backup в GitHub приватный репозиторий пользователя.** Зафиксировано 2026-05-06. После установки ClaudSoul предлагать пользователю создать собственный приватный репозиторий-бэкап для базы знаний (`~/.claude/global-lessons/` + project memory). Периодический push'ить через cron/launchd либо хук на изменения. Цели: (а) защита от потери знаний при сбое диска, (б) sync между несколькими машинами одного пользователя, (в) audit-trail изменений через git log. **Подкомпонент: GitHub onboarding tool.** Для пользователей без GitHub аккаунта/опыта: пошаговый wizard через `/github-setup` либо `init-project` extension — регистрация, генерация SSH-ключа (`ssh-keygen -t ed25519`), добавление в GitHub (через `gh auth login` либо инструкцию для копирования pub-ключа), создание приватного репо (`gh repo create --private`), настройка remote и первый push. Альтернатива без `gh` CLI: HTTPS + personal access token. Реализация: новый skill `/backup-setup` (коорд) либо инлайн в `init-project`. Зависимости: `gh` CLI опционально, иначе ручной flow.
- **Опциональный launchd-крон как апгрейд нуджа `/compile`** — остаток интеграции заимствований из claude-mem; сама интеграция реализована (см. CHANGELOG, 2026-06-13)

### Решено НЕ делать (зафиксировано, не пересматривать без нового аргумента)
Из `docs/cascading-analysis.md`:
- **C1** Knowledge-activator mid-session re-injection — cooldown 30мин + overlap 70% уже оптимальны
- **C2** L7 co-thinking chain — дублирует L6 PROPOSAL
- **C3** Adaptive `/decompose` — scope = контракт, каскад ломает контракт
- **C4** Continuous L5 health monitoring — должно быть batched
- **C5** Reformulation tracker на каждое предложение — затопит log шумом

Из §12 architecture.md — **архитектурно не решаются на уровне harness:**
- **Разрыв A** (affect как вес памяти) — модель без affect-канала архитектурно. **Однако функции** аффекта (тормоз на destructive, эмпатическая пауза, cost-of-harm) **закрываются инженерно** через класс ⚙️ **affect prosthetics** (v1.5.6-alpha `trust-guard` первый член, v1.5.7+ `distressed` state axis, silence_cost как proxy). Substrate остаётся отсутствующим, функции компенсируются явными хуками, не правилами
- **Разрыв F** (early-stop intuition) — требует другой модели, transformer pred не имитирует human antic

---

## Roadmap (done)

Компактная таблица фаз. Детали — в [CHANGELOG.md](CHANGELOG.md); пере-релизные строки прежней таблицы — в [внутренний архив (не публикуется)](внутренний архив (не публикуется)).

| Фаза | Версии | Цель | Статус |
|------|--------|------|--------|
| **1** Strengthen Foundation | v0.1.1 – v0.1.5 | Метрики + install + templates | ✅ |
| **2** Cognitive Foundation (L2-L3) | v0.2.0 – v0.2.7 | 9 якорей + success cases + FSRS + typed edges + interlocutor model | ✅ |
| **3** Thinking (L4-L5) | v0.3.0 – v0.3.8 | Alive Learning System + demand-first + autonomous scanner | ✅ |
| **4** Partnership (L6-L7) | v0.4.0 – v0.4.6 | Trajectory + metrics + prediction modes + cross-domain transfer + constructive disagreement | ✅ |
| **5** Skill Architecture | v0.5.0 – v0.5.8 | Skill contract + Session Registry + Domain Graph + 15 Bridges + Skill Forge | ✅ |
| **6** Coordination Layer (L1-L2) | v0.6.0 – v0.6.3 | Knowledge coordinator + artifact-first + checkpoint + worker contracts | ✅ |
| **7** Quality & Pipeline (L1) | v0.7.0 – v0.7.2 | Quality Gate + Decompose + Pipeline Orchestrator | ✅ |
| **8** Full System | v1.0.0 | MCP + Viz 2D + Export + Dashboard | ✅ |
| **10** Cascading Principle | v1.0.2 – v1.0.9 | Append-only при survivorship bias (7 APPLY, 5 SKIP) | ✅ |
| **11** Layer Bridge Hardening | v1.0.10 – v1.0.11 | Stable session IDs + MCP semantic fallback + ancestor-PID cleanup | ✅ |
| **9** Entity Knowledge | v1.1.0 – v1.1.8 | Второй контур + ingestion + discovery + aliases + FSRS live | ✅ |
| **12** 3D Universe | v1.2.0 | Type-метафоры + nebulae + gravity + search/filter | ✅ |
| **13** L6 4D Gate | v1.2.0 – v1.3.3 | Cost model → 4D gate → active system → auto cost → метрики → state classifier | ✅ |
| **14-34** | v1.3.4 – v1.7.0 | Пере-релизные фазы, по одному релизу каждая (blocker-tier, авто-сбор L6-метрик, affect prosthetics, cross-contour surfacing, output language check, калибровка) — строки в архиве | ✅ |

Начиная с v1.8.0 релизы в фазы не оформляются — история только в [CHANGELOG.md](CHANGELOG.md).

> **Про нумерацию:** фазы нумеровались в порядке ЗАДУМЫВАНИЯ, не реализации. Phase 9 (Entity Knowledge) задумана в v0.5, реализована после Phase 12. Это исторический артефакт, не переименовываем чтобы не ломать ссылки в CHANGELOG/коммитах.

---

## Гипотезы

Все гипотезы проекта — в одной таблице. **Не разбрасывать по фазам.** При появлении новой — добавлять сюда.

**Статусы:**
- ✅ **Подтверждена** — есть метрики подтверждения
- ❌ **Опровергнута** — есть метрики опровержения (с обоснованием)
- 🔁 **Реализована** — код есть, но верификация метриками не проведена
- ❓ **Частично** — есть данные, но недостаточно для выводов
- ⏳ **Не проверена** — только формулировка

Соответствие статусам D63: ✅ = подтверждена, ❌ = опровергнута, 🔁 / ❓ / ⏳ = открыта.

### Активные

| # | Гипотеза | Фаза | Статус | Что мерить |
|---|----------|------|--------|-----------|
| **H1** | Граф связей улучшит релевантность знаний | 1 | 🔁 | полезных инжектов / прочитанных зря |
| **H2** | Автоматический /retro через хуки снизит потерю знаний | 3 | 🔁 | уроков/неделю (с vs без хука) |
| **H3** | Confidence-weighted injection повысит точность | 3 | 🔁 | повторные ошибки |
| **H4** | FSRS-decay предотвратит засорение базы | 9 | 🔁 | % weakened знаний / 30 дней |
| **H5** | Семантический поиск MCP превзойдёт file-based | 8 | 🔁 | recall релевантных (A/B) |
| **H6** | Обучение на успехе снизит количество ошибок | 2 | 🔁 | avg `attempts_to_fix` |
| **H7** | Surprise factor ускорит активацию неожиданных знаний | 2 | 🔁 | intensity vs скорость применения |
| **H8** | Траектория мысли повысит точность предсказаний | 3 | ❓ | accuracy >50% (1 сессия — подтверждено) |
| **H9** | Поведенческий анализ надёжнее самоотчёта | 9 | 🔁 | `contradiction.gap_type=stated_vs_inferred` (v1.3.7) — нужен ≥30 кейсов разногласий |
| **H10** | Cross-reference между контурами порождает новые знания | 9 / v1.6.0 | 🔁 | двухосевая: рост `cross-contour-discoveries.jsonl` (weekly detector) + `surfaced / written ≥ 0.10` в H10-секции session-collector |
| **H11** | Каскадная фиксация снижает повторяемость ошибок | 10 | 🔁 | `cascading.backward_count` в history digest (v1.3.7) — корреляция с `error_count` baseline начинается с now() |
| **H12** | Guardrails удерживают каскадность в token budget | 10 | 🔁 | `cost_peaks.injection_bytes_max` в history digest (v1.3.7) — proxy для tokens (intrusiveness inject) |
| **H13** | 4D gate снижает игноры gentle | 13 | 🔁 | `gentle_acceptance_rate` +20пп — автосбор v1.3.5, ждём калибровочное окно ≥30 сессий |
| **H14** | Silence_cost предотвращает «вежливую бесполезность» | 13 | 🔁 | # упущенных ретро-важных предупреждений — proactive автосбор v1.3.6, нужен ручной аудит silence debt |
| **H15** | Silence debt активируется в правильных окнах | 13 | 🔁 | ручная оценка 20 активаций — schema v3 пишет в intrusiveness-history.jsonl, требуется ретро-сессия |
| **H16** | 3D-метафора улучшает навигацию >100 узлов | 12 | ⏳ | UX-сессия 2D vs 3D |
| **H17** | Nebulae улучшают понимание структуры базы | 12 | ⏳ | точность ответов 2D vs 3D |
| **H18** | Narrative через /narrative снижает intent-gap в первых 3 turns | 15 (v1.5) | ⏳ | gap-rate первых 3 turns с narrative vs без |
| **H19** | Trust-guard снижает frequency destructive Bash без auth | v1.5.6-alpha | ⏳ | доля session-sessions с ≥1 destructive action без auth маркера (baseline от v1.5.6-alpha) |
| **H22** | `/quality-gate` pre-commit ловит неполный DoD | v1.5.6 | ⏳ | % commits с SKILL.md где unchecked чекбоксы до/после v1.5.6 |
| **H23** | `/enrich` post-ingest увеличивает среднюю плотность entity | v1.5.7 | ⏳ | attrs/entity до и после suggestion (baseline от v1.5.7) |
| **H26** | `distressed` state axis снижает gentle/proactive density в dialog'ах дистресса | v1.5.7 | ⏳ | gentle+proactive events per turn при `state=distressed` vs idle/focus baseline |
| **H27** | AP3 carry-over hint снижает повторное накопление `silence_debt.pending` между сессиями | v1.5.8-alpha | ⏳ | `debt.pending` в первых 5 сессиях после релиза: плато/убывание vs монотонный рост |
| **H28** | `/skill-review` pre-commit ловит contract violations staged SKILL.md | v1.5.8 | ⏳ | % commits с SKILL.md где violations до/после v1.5.8 |
| **H29** | `/learn` success-cascade с attempts count повышает rate /learn после каскада | v1.5.8 | ⏳ | /learn calls после resolved-cascade до/после релиза |
| **H30** | `/retro` auto-draft сокращает латентность resolved-cascade → зафиксированный case | v1.5.8 | ⏳ | drafts created vs drafts accepted per week |
| **H24** | Semantic scoring union filter увеличивает `surfaced_count` относительно set-only | v1.6.0 | ⏳ | ranked пары с `similarity ≥ 0.6`, где KF не в инжект-наборе — «чистый выигрыш» union filter |
| **H35** | Output language check снижает повтор alphabet-mixing в текущей сессии | v1.6.3 | ⏳ | # violations за сессию: 1-2 до surface-инжекта, 0 после |
| **H36** | Большинство нарушений feedback-rules детектирует система, не собеседник | v1.6.3 | ⏳ | ratio `agent-detected / (agent-detected + user-detected)`, target ≥ 0.7 |
| **H37** | Полный ClaudSoul даёт измеримую дельту против Vanilla на автономных задачах, особенно в страте «релевантное знание существовало» | prereg 2026-08-08 | ⏳ | exact McNemar по 20 теневым парам, протокол [docs/ablation-protocol.md](docs/ablation-protocol.md) |

### Архив
_Пока пусто. H2/H3/H6/H7 реализованы, но ни одна ещё не получила метрики подтверждения/опровержения — как только хотя бы одна получит достоверный сигнал, она переедет сюда с обоснованием._

---

## Архитектурные решения (ADR)

### ADR-001: Markdown как хранилище знаний
**Решение:** Markdown + YAML frontmatter.
**Причина:** Claude Code читает нативно, git-friendly, нет зависимости от БД, человекочитаемо.
**Альтернативы:** SQLite (быстрее, но не читается нативно), JSON (менее читаемо).
**Статус:** Принято.

### ADR-002: Трёхуровневая иерархия (case/pattern/principle)
**Решение:** Три уровня абстракции с промоушеном вверх.
**Причина:** Баланс детальности и обобщения. Аналогия с эпизодической → семантической памятью.
**Альтернативы:** Плоский список (хуже масштабируется), граф без уровней (A-MEM, мощнее, но сложнее).
**Статус:** Принято.

### ADR-003: Confidence scoring 1-5 вместо бинарного
**Решение:** Confidence 1-5 с подкреплением и затуханием.
**Причина:** Позволяет приоритизировать и отсеивать устаревшие.
**Вдохновение:** FSRS, SM-2.
**Статус:** Принято. Decay реализован в v1.1.8.

### ADR-004: Глобальные знания + проектные кейсы
**Решение:** Двухуровневая топология: `~/.claude/global-lessons/` + `project/memory/`.
**Причина:** Универсальные уроки доступны везде, проектная специфика не засоряет другие проекты.
**Статус:** Принято.

### ADR-005: Два контура обучения
**Решение:** Layer 2 расширен вторым контуром: `entity / fact / relation` для внешних источников.
**Причина:** Операционный контур (case/pattern/principle) покрывает собственный опыт. Для документов/книг/чатов нужна сущностная модель с provenance и temporal validity.
**Ключевое:** Confidence факта зависит от источника: `behavioral (3) > document (2) > self-report (1)`.
**Альтернативы отвергнуты:** (а) кодировать всё в case — entity ≠ инцидент; (б) внешняя система — теряется интеграция; (в) Neo4j — overhead, ломает zero-infrastructure.
**Спецификация:** `docs/entity-knowledge.md`.
**Статус:** Принято, реализовано в v1.1.x.

### ADR-006: L6 как 4D gate, не скалярный порог
**Решение:** Режимы prediction (`proactive / gentle / silent_prep / ignore`) — выходы gate от четырёх осей (`confidence × value × cost × state`), а не функция одной confidence.
**Причина:** Confidence отвечает на «насколько вероятно полезно», а не на «стоит ли внимания», «какой ценой», «принимает ли собеседник ввод». Скалярный порог систематически ломает UX.
**Ключевое:** Gate = сравнение сожалений (`regret_if_silent` vs `regret_if_speak`), не фиксированный порог. Cost содержит 6 осей (5 speak + 1 silence как контрвес).
**Спецификация:** `bridges/L3-L6-communicative-prediction.md`, `docs/architecture.md §8`.
**Статус:** Принято, реализовано в v1.3.0 (формализация) → v1.3.3 (активная система с state classifier).

---

## Мета-правила ведения плана

1. **Dashboard + «Что работает сейчас» обновляются ПРИ КАЖДОМ релизе** — до CHANGELOG.
2. **Новые гипотезы — только в таблицу** `## Гипотезы`, не разбрасывать по фазам.
3. **Фазы roadmap — только одной строкой в таблице.** Детали → CHANGELOG. План не дублирует историю.
4. **«Решено НЕ делать» — вечнозелёная секция.** Без обоснования не удалять, без нового аргумента не пересматривать.
5. **ADR пишется один раз и не переписывается.** Если решение отменено — новый ADR с явной отсылкой к старому.
6. **Размер PLAN.md — цель ≤300 строк.** Если растёт — значит детали просочились из CHANGELOG. Чистить.
7. **Документ состояния: переписывается начисто, хроника — в CHANGELOG/архив (D63).**
