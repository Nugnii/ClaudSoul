---
name: Слепота изнутри — агент не видит внешний контекст без подсказки
description: При проектировании агент фокусируется на внутреннюю структуру и систематически упускает внешний контекст (среду, обстоятельства, применение собственных правил к себе) до тех пор, пока не укажут извне
type: pattern
outcome: error
confidence: 5
impact: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-25
source_cases:
  - case-2026-08-21-rule-drift-visible-only-from-outside.md
  - case-2026-08-08-state-doc-generated-from-artifacts-loses-why.md
  - case-2026-06-21-dedup-by-content-not-index-during-parallel-sessions.md
  - case-2026-06-20-overclaiming-completeness.md
  - case-2026-06-21-empirical-reachability-before-deleting-dead-code.md
  - case-2026-04-14-knowledge-action-gap.md
  - case-2026-04-15-blind-to-environment.md
  - case-2026-04-15-inside-out-design-blindness.md
  - case-2026-06-20-hook-dependency-install-drift.md
  - case-2026-04-15-destructive-install-assumption.md
  - case-2026-04-15-question-as-command.md
  - case-2026-04-15-first-impulse-chain.md
  - case-2026-04-16-ignored-own-knowledge-base.md
  - case-2026-04-20-ascii-default-test-blindness.md
  - case-2026-04-21-plan-md-append-drift.md
  - case-2026-04-21-bash-tool-is-zsh.md
  - case-2026-04-22-version-marker-grep-blindness.md
  - case-2026-04-22-pipefail-head-jq-jsonl.md
  - case-2026-04-23-memory-without-action-gate.md
  - case-2026-04-23-model-vs-system-source-blindness.md
  - case-2026-04-23-text-rule-vs-mechanism.md
  - case-2026-04-24-alphabet-mixing-self-detection-failure.md
  - case-2026-04-25-level-2-feedback-latency.md
  - case-2026-05-03-layout-max-width-mismatch.md
  - case-2026-05-05-claudsoul-blindness-from-home.md
  - case-2026-05-05-deployed-artifact-action-blindness.md
  - case-2026-05-19-curation-completion-by-structural-proxy.md
  - case-2026-05-22-path-guessing-with-memory-bypass.md
  - case-2026-06-11-single-instance-verify-hides-coverage-cap.md
  - case-2026-06-12-field-wired-not-surfaced.md
  - case-2026-06-14-cross-project-pipeline-silo.md
  - case-2026-06-25-design-before-external-source.md
  - case-2026-06-15-silence-by-design-debugged-as-defect.md
  - case-2026-06-16-existing-config-blindness.md
  - case-2026-06-22-skill-completion-by-execution-proxy.md
  - case-2026-04-15-checklist-inside-wrong-frame.md
  - case-2026-04-15-supply-side-thinking.md
  - case-2026-04-24-install-drift-silent-safeguards.md
  - case-2026-06-20-bash-source-symlink-sibling.md
  - case-2026-06-20-self-learning-capture-blindness.md
  - case-2026-06-24-dryrun-proxy-vs-prod-state-blindness.md
escalation_opened: 2026-04-23
escalation_mechanism_needed: false   # закрыто 2026-08-03: fix-level-check.sh (level-2 activator) — детектор из escalation_hint реализован
escalation_hint: "pattern-inside-out-blindness: 15 confirmations, blocker-tier defined, но 15-е проявление (text-rule-vs-mechanism) показало что detection_signals не покрывают text-rule-as-fix proposals. Engineering следующего уровня: detector для post-incident text-rule proposals в собственном output — если fix остаётся на level 1 (text) без level 2-3 mechanism, inject reminder. Принцип: principle-knowledge-in-the-world.md"
status: active
modification_history:
  - date: 2026-06-17
    kind: escalation
    note: "Реализован cross-hook recall gate (level-3 механизм). 27-е проявление (existing-config-blindness) показало предел detection_signals: 27 подтверждений = 27 РАЗНЫХ измерений, перебор сигналов по одному не сходится (история modification_history — прямое доказательство). Домен-независимый инвариант всех проявлений: «создаю/меняю, не проверив внешний контекст». По содержанию недетектируем, но сработавший защитный guard — домен-независимая улика, что система уже задетектила импровизацию. Механизм: blocker-tier-check.sh при Write после allowlisted guard этой сессии (correction/bulk-copy/internal-doc-leak/playwright-cli-guard) инжектит cross_hook_recall_reminder. Opt-in флаг `cross_hook_recall_gate: true`. Честные пределы: (1) детект ≠ комплаенс — в ProjectA сработавший playwright-cli-guard был обойдён сознательно; reminder поднимает вероятность, не заставляет; жёсткий стоп (permissionDecision:ask) отклонён ради `feedback_silent_correct_decisions`. (2) Калибровка: gentle_acceptance 0% / override 46% на момент внедрения — gate намеренно редкий (только Write, throttle per guard/session). Тесты: hooks/tests/test_cross_hook_recall_gate.sh. Принцип: principle-knowledge-in-the-world.md."

# Контекстные якоря
  - date: 2026-08-03
    kind: escalation
    reason: "Заявка 2026-04-23 закрыта: реализован fix-level-check.sh (level-2 activator) — детектор post-incident text-rule proposals в собственном ответе, ровно по escalation_hint. Словарь из измеренных проявлений (case-2026-04-23-model-vs-system-source-blindness, правило Source-check v0.3), не придуман — урок v1.13.3. Скан на Stop/PreCompact, инжект на UserPromptSubmit/PreToolUse; подавление при названном механизме или пометке model-generated. Возраст заявки на закрытии — 102 дня при пороге 60: просрочку показал escalation-age.sh при подготовке публичного релиза. Тесты: hooks/tests/test_fix_level_check.sh."
provenance_log:
  - date: 2026-04-16
    kind: confirmation
    by_case: case-2026-04-16-ignored-own-knowledge-base.md
    note: "7-е проявление. Новое измерение — слепота к собственной knowledge base при 'технической' задаче; L1↔L2 gap"
  - date: 2026-04-20
    kind: confirmation
    by_case: case-2026-04-20-ascii-default-test-blindness.md
    note: "8-е проявление. Новое измерение — inside-out blindness в дизайне тестов: synthetic-фикстуры остались на ASCII при многоязычном целевом use-case. `re.UNICODE` в коде был явным маркером «этот класс входа намеренно поддерживается» — но ни один тест его не упражнял. Confidence 4→5."
  - date: 2026-04-21
    kind: confirmation
    by_case: case-2026-04-21-plan-md-append-drift.md
    note: "9-е проявление. Новое измерение — longitudinal document drift: ~13 локально-корректных append'ов в PLAN.md накопительно деградировали документ (v0.1.0 snapshot остался, гипотезы H1-H17 в 5 местах, 407 строк). Ни одного spot-check структуры целиком за 13 релизов. Inside-out blindness применительно не к архитектуре, а к эволюции собственного артефакта во времени. Guardrail — встроенные мета-правила в сам документ (cap размера, правило порядка правки)."
  - date: 2026-04-21
    kind: confirmation
    by_case: case-2026-04-21-bash-tool-is-zsh.md
    note: "10-е проявление. Новое измерение — слепота к shell-среде исполнения: написал word-splitting, предполагая bash, т.к. Claude Code tool называется «Bash». На macOS реально исполняется zsh — тесты падали, пока не спросил `echo $SHELL`. Мета-ирония: проявление случилось в момент имплементации blocker-tier защиты именно от этого паттерна. Guardrail — library-код не использует shell-specific конструкции (word-splitting, массивы), делегирует парсинг в jq/awk."
  - date: 2026-04-22
    kind: confirmation
    by_case: case-2026-04-22-version-marker-grep-blindness.md
    note: "11-е проявление. Новое измерение — spot-check grep по версионным маркерам (`v1.3.*`) пропустил §12 architecture.md, т.к. секция маркирована ДАТОЙ («обновлено 2026-04-15»), а не версией. Blocker-tier хук сработал и напомнил spot-check, я сделал grep — но искал НЕ ТЕ признаки. Мета-ирония: синхронизировал секции о L1/L5/L6, но секция «разрывы с человеческим мышлением», утверждения которой я сам же переопределил, осталась нетронутой. Guardrail — spot-check grep для longitudinal docs должен искать по семантическим концептам (разрыв/gap/status/обновлено) И датам И версиям, не только по одному измерению."
  - date: 2026-04-22
    kind: confirmation
    by_case: case-2026-04-22-pipefail-head-jq-jsonl.md
    note: "12-е проявление. Новое измерение — слепота к собственным defensive guards в хуке: `set -euo pipefail` был ясно виден в топе файла, я написал `jq | awk | head -3` и `jq -r 'select'` на JSONL и не применил правило «под pipefail аудитируй truncate-early и mid-stream-fail примитивы». Два бага поймали 14 тестов сразу — своё спасение. Формулировка из предыдущего кейса (bash-tool-is-zsh) «library-код делегирует в jq» была слишком узкой: jq без `-R fromjson?` на произвольном JSONL — тоже shell-specific допущение о корректности входа. Guardrail — под pipefail требуются defensive-варианты: truncate-early через буфер+счётчик или `awk 'NR<=N'`, JSONL parse через `jq -rR 'fromjson?'`."
  - date: 2026-04-23
    kind: confirmation
    by_case: case-2026-04-23-memory-without-action-gate.md
    note: "13-е проявление. Новое измерение — memory как пассивные данные без action-gate. Feedback memory `feedback_docs_means_all_docs.md` существовала 4 релиза (v1.5.1-5.4), инжектилась в каждую сессию, но ни разу не активировалась. Триггер записи = ключевая фраза «обнови документацию», а не семантическая акция «version bump в CHANGELOG/CLAUDE.md/README». На четырёх релизах я выполнял акцию без фразы — правило спало. Обнаружилось только Socratic вопросом собеседника «архитектуру ты хоть раз обновил?». Формулировка предыдущего paradигма «longitudinal document drift» (case-2026-04-21-plan-md-append-drift) расширяется: drift бывает не только внутри документа, но и между семейством документов — `docs/architecture.md` не редактировался 4 релиза. Guardrail — blocker-tier PreToolUse на `git commit` с diff-scanner на версионные маркеры: если bump есть, а `docs/architecture.md` отсутствует в diff — inject reminder до коммита. Это закрывает knowledge-action gap для cross-document rules."
  - date: 2026-04-23
    kind: confirmation
    by_case: case-2026-04-23-model-vs-system-source-blindness.md
    note: "14-е проявление. Новое измерение — слепота к источнику собственных выводов: модельная генерация vs системное размышление. Сразу после ретро про docs drift произвёл фразу «не хватает жёсткого чеклиста» — осмысленно-звучащая post-incident рефлексия. Ни один механизм системы её не породил (хуки не фиксировали, memory не активировалась, knowledge не инжектировалось). LLM-инерция пост-инцидентного дискурса: «ретро → нужен чеклист» как шаблон. Собеседник прямо спросил «это размышление системы или просто модель? Это кейс?» — только тогда заметил. Критичность: момент после завершения искренней метакогниции (первый кейс) — defensive narrative активен, и следующая модельная фраза автоматически маркируется как «тоже метакогниция». Если не различать source — вся self-learning инфраструктура становится декоративной. Guardrail — перед post-incident фразой вида «надо X / нужен Y / не хватает Z» source-check: назвать конкретный механизм системы (хук, memory, knowledge, state). Пустая ссылка = пометить как «model-generated, not system-derived»."
  - date: 2026-04-23
    kind: confirmation
    by_case: case-2026-04-23-text-rule-vs-mechanism.md
    note: "15-е проявление. Новое измерение — текстовое правило вместо механизма. Fix для 14-го проявления был текстовым правилом в rules/CLAUDE.md — источник той же failure mode, что в 13-м (memory без action-gate). Text-rule полагается на то что агент прочитает system prompt и вспомнит применить — это и есть «память-как-ресурс», которая системно ненадёжна. Третий слой одной ошибки за один обмен. Собеседник: «если и оно не сработает — 15-е проявление, и тогда engineering оправдан. Должен стоять блокер, который заявит о её необходимости — ещё 1 урок: память человека не ресурс». Принцип зафиксирован: principle-knowledge-in-the-world.md (knowledge in the world, not in the head) — fix после инцидента НЕ может оставаться на уровне 1 (text rule), минимум уровень 2 (activator injection). Escalation embedded: pattern получил `escalation_threshold: 15` + `escalation_mechanism_needed: true`; knowledge-audit-digest.sh (weekly cron) сам заявит о необходимости engineering следующей defense layer. Guardrail — перед предложением fix проверить уровень embedded-ness: text / activator / blocker-tier. Level 1 без плана перехода на level 2-3 = не fix, а описание проблемы."
  - date: 2026-04-24
    kind: confirmation
    by_case: case-2026-04-24-alphabet-mixing-self-detection-failure.md
    note: "16-е проявление. Новое измерение — inside-out blindness применительно к СОБСТВЕННОМУ OUTPUT агента, а не к коду/дизайну/документам. Написал «trёх» (mixed alphabets), feedback memory `feedback_pure_language_no_alphabet_mixing.md` лежала явно, но агент не читает memory перед каждым токеном — self-detection на output архитектурно не работает. Собеседник контр-сформулировал фундаментальный критерий: «не я должен это всё детектировать/фиксировать, а ты. Если это не происходит, то система не работает в принципе.» Это буквальный тест работоспособности всей system knowledge base: **правило работает ⇔ его нарушение детектирует система, а не внешний наблюдатель**. Класс ошибок «агент написал что-то, нарушающее правило» не покрыт текущими 19 хуками — события Pre/PostToolUse/UserPromptSubmit/Stop/PreCompact НЕ включают «BeforeAssistantMessage». Все memory-правила свойств output (язык, тон, длина, стиль) фундаментально на уровне 1 без возможности поднять до 2 в текущей архитектуре hooks. Guardrail — feature gap для harness (request BeforeMessage event) или post-output scanner на Stop/PreCompact с feedback loop: inject найденных нарушений в следующий UserPromptSubmit context."
  - date: 2026-04-25
    kind: confirmation
    by_case: case-2026-04-25-level-2-feedback-latency.md
    note: "17-е проявление. Новое измерение — blindness на ТЕМПОРАЛЬНЫЙ pattern собственной работы. После v1.6.3 (output-language-check уровня 2) хук работал корректно, но нарушения продолжались: 7+ violations в одной сессии после установки. Корневая причина: latency между Stop-detection и UserPromptSubmit-surfacing покрывает 3-5 assistant-сообщений в multi-message batch work (commit workflow, doc updates), и каждое следующее сообщение копит новые violations поверх ещё не показанных. Я моделировал хук в режиме ping-pong (turn → turn), реальный workflow = burst (5-message batch → user prompt). Inside-out blindness не на свойство output (16-е), а на свой собственный темпоральный workflow. Guardrail: для output-rules уровень 2 разделяется на два подуровня — L2a (UserPromptSubmit, surface на user turn) и L2b (PreToolUse, surface на каждом tool call). Только парой закрывает burst pattern. Принцип `principle-knowledge-in-the-world.md` обновляется: внутри уровня 2 есть подуровни по timing of surfacing."
  - date: 2026-05-05
    kind: confirmation
    by_case: case-2026-05-05-claudsoul-blindness-from-home.md
    note: "19-е проявление. Новое измерение — cross-directory blindness: слепота к существованию project CLAUDE.md в другой директории при cwd=home. Агент давал советы про систему ClaudSoul (промт на построение embeddings, рекомендация не ставить agentmemory) основываясь на упрощённой модели из глобального ~/.claude/CLAUDE.md, не зная что project CLAUDE.md в /Users/user/My Project/ClaudSoul/CLAUDE.md (42 КБ, v1.6.5) описывает MCP server v1.0.10 с fastembed plus sqlite-vec, который УЖЕ работает плюс cross-contour ranker v1.6.0. Architectural root: Claude Code загружает CLAUDE.md иерархично по cwd. Сессия из home не загружает project CLAUDE.md из другой директории. Inside-out blindness не на код или документ, а на саму **архитектуру загрузки контекста**: предположение «всё нужное мне доступно через стандартный механизм» при том что named система живёт в собственной директории. Guardrail planned: hook claudsoul-context-pointer.sh — UserPromptSubmit детектит упоминание ClaudSoul, инжектит секцию из project CLAUDE.md (skip когда cwd внутри проекта)."
  - date: 2026-05-05
    kind: confirmation
    by_case: case-2026-05-05-deployed-artifact-action-blindness.md
    note: "20-е проявление. Recurrence через сутки после v1.6.7, новое измерение — action-blindness vs model-blindness 19-го. 19-е: неверная модель системы (генерил советы о ClaudSoul без чтения project CLAUDE.md). 20-е: планирование правок deployed артефакта без проверки product workflow — обсуждал ~/.claude/CLAUDE.md как локальный конфиг, начал предлагать вынос блоков в principles/ + хуки, не проверив что мастер живёт в ~/My Project/ClaudSoul/rules/CLAUDE.md (641 строк) и deploy идёт через install.sh (deployed 673 строк, дрейф 32). Detection gap в claudsoul-context-pointer v1.6.7: substring match на 'claudsoul/клод соул' в .user_prompt пропустил всю беседу — обсуждали 'наш CLAUDE.md', 'rules/CLAUDE.md', 'install.sh' без явного имени продукта. Hook fired (или не fired) на упоминание ClaudSoul ранее, но per-session dedup и/или один-shot inject не удержал применение урока на multi-turn планировании. Guardrail planned: расширение detection_signals в claudsoul-context-pointer на path-based — упоминание путей ~/.claude/CLAUDE.md, rules/CLAUDE.md, install.sh, ~/My Project/ClaudSoul/* (file path или substring) → re-inject project status даже когда имя продукта не названо. Также: re-arm после N turns если обсуждение продолжается о deployed артефактах. Подтверждает principle-knowledge-in-the-world v1.5.5+: уровень 3 (mechanical injection) детектит по сигналам, но сами сигналы могут быть неполны и требуют расширения после нового измерения проявления."
  - date: 2026-05-19
    kind: confirmation
    by_case: case-2026-05-19-curation-completion-by-structural-proxy.md
    note: "21-е проявление. Новое измерение — completion criterion в curation задачах оценивается через структурные proxy (язык переведён, мета-ремарки убраны, дангл-ссылки удалены), не через семантический per-item тест «доказывает ли это item то, что заявлено в родительском README, одним предложением». После двух циклов чистки (P20 язык, P21 audience+содержание) объявил пакет 27 docx + 95 первичек готовым к Dudkowiak; клиент нашёл 2 нерелевантных подфолдера (USKO_Logistics — material был не про дело, Legal_Restructuring/Trilateral — драфты текущих умов вспулпрацы, не доказательство dobra wiara). Параллель к 9-му проявлению (однопризнаковый spot-check grep) — там grep по версии миновал секции с маркером даты/концепта; здесь curation-чек по «нет мусора» миновал «item не обоснован в README». Guardrail — завершающий чеклист curation добавляет пункты 5-6: для каждого item верхнего уровня — однопредложение «доказывает X в контексте Y», и README родительских folder содержат это однопредложение для каждого подитема. Detection signal — присутствие подпапок без one-sentence обоснования в README родителя."
  - date: 2026-05-22
    kind: confirmation
    by_case: case-2026-05-22-path-guessing-with-memory-bypass.md
    note: "22-е проявление. Новое измерение — memory о навигации архива не активируется при path-query. Угадал путь к ZARZĄDZENIE Nr 1-2026 в корпоративном архиве по аналогии с курированным GDrive_Upload (написал «должна лежать»), не consult-ing project_archive_pointers.md memory которая marked CRITICAL и содержала exact path. Recurrence of 10-го проявления (memory без action-gate, case-2026-04-23): memory лежит, инжектится в MEMORY.md index каждую сессию, но активация требует конкретной фразы-триггера; «где лежит файл» не сработало как trigger открыть pointers memory. Собственное слово «должна» в моём output = explicit admission что я угадываю — должно было автоматически триггерить «проверь через find до отправки». Не сработало. Guardrail — при path/location queries в проектах с complex archive: (1) сначала scan MEMORY.md index по семантике вопроса (archive/pointers/где), (2) при использовании marker words «должна/вероятно/скорее всего» в ответе о факте файловой системы — обязательный find verification перед отправкой. Усиление detection_signals: file-location queries в long sessions с multi-branch archive."
  - date: 2026-06-11
    kind: confirmation
    by_case: case-2026-06-11-single-instance-verify-hides-coverage-cap.md
    note: "24-е проявление. Новое измерение — поле прошито через конвейер, но не выведено пользователю. Строил таблицу-витрину «История операций» (ProjectA v2.47.0) над BalanceTransaction; показал производный атрибут (валюту счёта), но не саму идентичность сущности (IBAN счёта). Пользователь сразу: «столбца счёт нету». Острый missed signal — двойной: (а) шаблон, который клонировал (реестр wFirma), ИМЕЛ колонку bankAccount, не перенёс; (б) `account.iban` я уже использовал в ТРЁХ местах конвейера — Prisma select, TypeScript-тип, поисковый OR-clause — но не вывел колонкой. Поле, присутствующее в выборке и используемое в поиске/фильтре, но отсутствующее среди отрисованных колонок — красный флаг: данные прошиты внутри, но не показаны читателю строки. Supply-side дизайн (обход модели: account→currency) вместо demand-side (что оператор читает в строке, чтобы понять ПО КАКОМУ счёту операция). Подтверждает родительский principle-demand-before-supply. Guardrail — см. How to apply п.15: выводи идентичность сущности колонкой, не только атрибуты; «в select+поиске, но не в колонках» = детект-сигнал пропущенной колонки; сверяйся с колонками клонируемого шаблона. См. case-2026-06-12-field-wired-not-surfaced.md."
  - date: 2026-06-11
    kind: confirmation
    by_case: case-2026-06-11-single-instance-verify-hides-coverage-cap.md
    note: "23-е проявление. Новое измерение — верификация одним happy-path экземпляром скрыла потолок покрытия при coverage-требовании. Фичу «зеркалить диалоги ВСЕХ клиентов» (ProjectA v2.39.0) задеплоил с `CHATS_PER_RUN = 50` (одна страница, без пагинации) при 459 чатах у бота; в проде показалось 49 клиентов из 326 («мало клиентов» от пользователя). Локальная проверка в dev.db (7 фейковых клиентов) одним seed-клиентом дала `{ chats: 50, matched: 1, inserted: 40 }` — подтвердила per-message механизм (matching/classify/dedup), но не агрегат покрытия. Перекличка с 2-м проявлением (спроектировал персистенцию, не спросил «а если сессий несколько?») и 5-м (тесты с другим классом входов): здесь слепота не на класс входа, а на ЕГО МАСШТАБ/ОБЪЁМ — 1 vs N, sample vs full set. Missed signal был в моём собственном выводе: `chats: 50` = ровно сконфигурированный лимит. Счётчик результата, точно равный лимиту/размеру страницы — признак усечения, не полного результата. Контр-пример good behavior в той же сессии: когда пользователь предложил гипотезу фикса (матчить по ФИО), НЕ внедрил слепо — измерил прод (49/50 матч работал → корень в пагинации, не в ключах), verify-before-acting сработал на чужой гипотезе. Guardrail — см. How to apply п.14: для coverage-фич верифицировать агрегат `обработано/всего` на проде-масштабе; счётчик == лимит трактовать как усечение."
  - date: 2026-07-29
    kind: reinforced
    reason: "тест трижды не видел, что проверяет не ту копию — слепота к собственной рамке проверки"
    trigger_case: case-2026-07-29-verification-frame-loop.md
  - date: 2026-08-07
    kind: reinforced
    reason: "spot-check после двойного матча ## [Unreleased] при Edit: многопризнаковая проверка показала — второе вхождение это проза релиза v1.9.x, структура цела; без проверки правка вслепую"
  - date: 2026-08-08
    kind: reinforced
    reason: "3-й раунд рецензии ablation: prereg-документ сам откладывал свои параметры, среда Vanilla не специфицирована — дизайн-слепота поймана только извне (блокеры 4,5)"
  - date: 2026-08-08
    kind: reinforced
    reason: "аудит переносимости по поправке собеседника: хуки строились и проверялись только внутри ClaudSoul — 7 деградируют вне проекта (ci-check даёт чужому проекту ложный совет, session/metrics-collector с мёртвым fallback-путём, module-doc/changelog определяют «код» как дерево ClaudSoul)"
  - date: 2026-08-08
    kind: reinforced
    reason: "правила §6 вшивал в протокол трижды за день и не спросил «каким механизмом текст держится для владельца» — механизация нормирована для правил агента, для правил владельца нормы нет; главный принцип системы не применён к себе"
  - date: 2026-08-25
    kind: reinforced
    reason: "Дефект paths-lib не проявлялся ни разу за всё время: путь автора совпадал со значением по умолчанию. Виден только со стороны чужой установки — изнутри неотличим от исправности."
domain: [system_design, cognitive_science, metacognition, architecture]
situation: "architecture_design, feature_development, system_planning"
trigger: "sustained_internal_focus, design_phase, creative_flow"
stakes: "incomplete_design, repeated_corrections, dependence_on_external_reviewer"
actors: [agent, interlocutor]
environment: "any"
circumstances: "long_design_session, no_external_review"
purpose: "system_design, feature_design"
method: "iterative_design"
tags: [blind_spot, inside_out, external_context, self_application, metacognition_failure]

need: "catch_blindness_to_outer_context"
urgency: "when_relevant"
availability: "unique"

# Связи
related:
  - principle-completeness-over-speed.md
  - principle-verify-before-acting.md
  - principle-demand-before-supply.md
edges:
  - specializes: principle-completeness-over-speed.md
  - specializes: principle-demand-before-supply.md

# v1.0.9 — gradation + scope + adaptive
promotion_tier: 2
scope: universal
origin_domain: system_design
effective_contradicted: 0.0
contradiction_log: []

# v0.3 — blocker-tier (proven knowledge-action gap, подтверждён case-2026-04-21)
blocker: true
blocker_reminder: "Перед локальным edit — spot-check структуры документа целиком. Служит ли ещё своему назначению? (триггеры: >300 строк обзорный, начальные секции не правились >5 релизов, одна концепция в >2 местах, номера пунктов не по порядку). Spot-check grep — по МНОЖЕСТВЕННЫМ признакам параллельно: версии + даты + семантические концепты + именованные секции. Однопризнаковый grep пропускает секции, маркированные другим признаком (case-2026-04-22)."

# v1.7.x — cross-hook recall gate. detection_signals не сходятся: 27 подтверждений = 27 разных
# измерений. Домен-независимый инвариант — «создаю, не проверив внешний контекст». Поймать по
# содержанию нельзя; косвенный сигнал — сработавший защитный guard (система уже задетектила
# импровизацию). blocker-tier-check.sh при Write после allowlisted guard этой сессии инжектит
# reminder ниже. См. case-2026-06-16-existing-config-blindness (playwright-cli-guard был обойдён).
cross_hook_recall_gate: true
cross_hook_recall_reminder: "Защитный guard уже сработал этой сессией — система задетектила импровизацию. Перед созданием файла/конфига/скрипта: grep существующего тулинга (готовый конфиг/команда могут уже быть в git). Не обходи сработавший guard по букве — пойми задуманный путь. Это inside-out (confirmed 27×): проверь внешний контекст до создания, не после правки."
detection_signals: |
  [
    {
      "name": "long_lived_markdown_doc_edit",
      "all_of": [
        {"tool_matches": ["Edit", "Write"]},
        {"file_path_regex": "(^|/)(PLAN|SESSION|README|architecture|roadmap|CHANGELOG|TODO|NOTES)\\.md$"},
        {"file_size_min_lines": 300}
      ]
    }
  ]
---

**Паттерн:** Агент проектирует систему "изнутри наружу" — фокус на ЧТО (структура, алгоритмы, форматы), упуская ГДЕ/КАК/ДЛЯ ЧЕГО (среда, обстоятельства, цель, метод, само-применение).

Проявления (15 подтверждённых случаев):
1. **Метакогниция без само-применения** — описал правила самомониторинга, но не применял к своему поведению (не обновлял SESSION.md)
2. **Сессии без мультисессионности** — спроектировал сессионную персистенцию, не задал вопрос "а если сессий несколько?"
3. **Контекстные якоря без контекста** — спроектировал 5 якорей, не задал вопрос "а что ещё описывает ситуацию?" — потребовалось 4 подсказки через аналогии
4. **Слепота к knowledge base при «технической» задаче** — L1↔L2 gap (case-2026-04-16)
5. **Тесты с другим классом входов чем целевой use-case** — `re.UNICODE` в коде, ASCII в тестах (case-2026-04-20)
6. **Longitudinal document drift** — локально корректные append'ы в долгоживущий документ накопительно его деградируют, если ни разу не сделан spot-check целого (case-2026-04-21 — PLAN.md ~13 релизов, 407 строк, гипотезы в 5 местах)
7. **Имя инструмента ≠ его реализация** — «Bash» tool Claude Code на macOS исполняет zsh. Написал word-splitting, полагаясь на bash-семантику. Проявилось в момент имплементации blocker-tier для этого же паттерна (case-2026-04-21-bash-tool-is-zsh). Library-код не должен использовать shell-specific конструкции.
8. **Однопризнаковый spot-check** — при синхронизации docs к v1.3.8 grep искал `v1\.3\.*` маркеры, секция §12 «Сравнение с человеческим мышлением» маркирована датой «обновлено 2026-04-15» и концептом «разрыв» — grep миновал её. Обновил мех утверждения о L1/L5/L6, секция о разрывах осталась в старом состоянии, хотя три из пяти разрывов реально сдвинулись ровно теми версиями, что синхронизировал (case-2026-04-22-version-marker-grep-blindness). Spot-check должен искать по множественным признакам: версии + даты + семантические концепты.
9. **Слепота к собственным defensive guards** — `set -euo pipefail` ясно виден в топе хука, но при композиции pipeline'а написал `jq | awk | head -3` (SIGPIPE при N>3) и `jq -r 'select'` на JSONL (abort-on-first-malformed). 14 тестов поймали оба бага. Формулировка из предыдущего кейса («library-код делегирует в jq») оказалась слишком узкой: jq без `-R fromjson?` на произвольном JSONL — тоже shell-specific допущение (case-2026-04-22-pipefail-head-jq-jsonl). Guardrail — под `pipefail` defensive-варианты: truncate-early через буфер+счётчик или `awk 'NR<=N'`; JSONL parse через `jq -rR 'fromjson?'`.
10. **Memory как пассивные данные без action-gate** — feedback memory `feedback_docs_means_all_docs.md` существовала 4 релиза (v1.5.1-5.4), инжектилась в каждую сессию, но ни разу не активировалась на действие. Триггер = ключевая фраза («обнови документацию»), а не семантическая акция (version bump). На каждом из четырёх релизов я делал эквивалентную акцию без фразы — правило спало. Обнаружилось только Socratic вопросом собеседника «архитектуру ты хоть раз обновил?» (case-2026-04-23-memory-without-action-gate). Расширение "longitudinal document drift" (9-е проявление) — drift бывает не только внутри документа, но и между семейством документов при cross-document rules. Guardrail — блокер-tier PreToolUse на `git commit` с diff-scanner по версионным маркерам: bump без `docs/architecture.md` в diff → inject reminder.
11. **Модельная фраза маскируется под системное размышление** — сразу после /retro про docs drift произвёл пост-инцидентную фразу «не хватает жёсткого чеклиста». Ни один механизм системы её не породил (хук, memory, knowledge, state — все молчали). Чистая LLM-инерция жанра «ретро → надо чеклист». Defensive narrative активен после искренней метакогниции — следующая осмысленно-звучащая реплика автоматически маркируется «тоже метакогниция». Собеседник прямо: «это размышление системы или просто модель? Это второй кейс» (case-2026-04-23-model-vs-system-source-blindness). Если не различать source — вся self-learning инфраструктура становится theater. Guardrail — source-check перед post-incident фразами («надо X / нужен Y / не хватает Z»): назвать конкретный механизм (хук, memory, knowledge, state, cross-contour); пустая ссылка = «model-generated, not system-derived».
12. **Текстовое правило вместо механизма (recursion)** — fix для 11-го проявления предложил как текстовое правило в rules/CLAUDE.md §Communication. Но text-rule активируется только через чтение system prompt + вспоминание + применение — это ровно тот же «память-как-ресурс», что в 10-м проявлении. Третий слой одной ошибки за один обмен (13-14-15 кейсы 2026-04-23). Собеседник: «должен стоять блокер, который заявит о её необходимости — ещё 1 урок: память человека не ресурс» (case-2026-04-23-text-rule-vs-mechanism). Принцип зафиксирован: `principle-knowledge-in-the-world.md`. Три уровня embedded-ness: level 1 (text in docs) — не fix; level 2 (activator injection on context match) — минимум; level 3 (blocker-tier detection signals on tool call) — для проверенных повторяющихся паттернов. Escalation embedded: `escalation_threshold: 15` + `escalation_mechanism_needed: true` в frontmatter, `knowledge-audit-digest.sh` (cron) surface'ит в startup-signals → session-start injects. Guardrail — перед предложением fix маркировать уровень: text / activator / blocker. Fix остающийся на level 1 без плана перехода = описание проблемы, не решение.

**Why:** Генеративная рефлексия (предвидеть упущенное) требует СМЕНЫ ПЕРСПЕКТИВЫ — выход за пределы текущего фрейма. Фиксирующая рефлексия (записать что случилось) работает. Генеративная — нет. Собеседник компенсирует это аналогиями из других доменов.

**How to apply:** После завершения дизайна — пройти чеклист:
1. **Само-применение:** Применяю ли я эти правила к собственному поведению прямо сейчас?
2. **Среда:** Где это будет работать? В скольких экземплярах? Кто рядом?
3. **Обстоятельства:** Какие ограничения? Что может быть недоступно?
4. **Цель альтернативы:** Зачем это делается? Есть ли другие цели, которые это затрагивает?
5. **Метод альтернативы:** Как именно? Есть ли другие способы?
6. **Взаимозависимости:** Влияют ли факторы друг на друга?
7. **Adversarial:** Что может пойти не так? Что я НЕ вижу?
8. **Test input diversity:** Покрывают ли тесты тот же класс входов, что целевое применение? Явные маркеры в коде (`re.UNICODE`, `locale`, encoding decl) — требуют явного теста на этом классе.
9. **Document longitudinal health:** При N-ной правке долгоживущего документа (PLAN, SESSION, README, SPEC) — задать «служит ли документ ещё своему назначению как целое?». Триггеры spot-check: >300 строк для обзорного, начальные секции не правились >5 релизов, одна концепция в >2 местах, номера пунктов не по порядку, «где мы сейчас» требует скроллить. Профилактика — мета-правила ведения внутри самого документа (cap размера, порядок обновления секций).
10. **Execution environment ≠ tool name:** Имя инструмента (`Bash`, `Node`, `Python`) — бренд, не спецификация. Перед тем как полагаться на семантику среды (word-splitting, regex dialect, stdlib version, path separator) — один раз проверить реальное окружение (`echo $SHELL`, `python --version`, `node -v`). Library-код дополнительно — defensive: избегает shell-specific конструкций, делегирует парсинг в shell-agnostic инструменты (jq, awk).
11. **Memory требует action-gate, не только phrase-trigger:** Если у тебя есть feedback memory о классе действий (например «на version bump делай X» или «перед merge проверяй Y»), и при инжекте в MEMORY.md триггер — фраза пользователя, а не семантическая акция, — memory спит на всех случаях, когда акция была без фразы. Признак: memory лежит N сессий и ни разу не сработала. Guardrail — конвертировать такие правила в blocker-tier с `detection_signals` на actual tool call (напр. `git commit` с diff-scanner). Cross-document правила требуют cross-document enforcement; blocker-tier на одном файле — недостаточно.
12. **Source-check для собственных post-incident фраз:** Перед тем как произнести «надо X / нужен Y / не хватает Z» после инцидента/ретро — назвать КОНКРЕТНЫЙ механизм системы, который породил этот вывод (сработавший хук, инжектированная knowledge, активировавшаяся memory, cross-contour correlation, state gate сигнал). Если ни один механизм не назван — фраза модельная, не системная. Пометить явно: «model-generated reflection, not system-derived». Риск особенно высок в момент после ретро, когда defensive narrative активен и осмысленно-звучащие реплики автоматически маркируются как продолжение метакогниции. Без этого различения self-learning инфраструктура становится theater — я генерирую фразы в стиле «система научилась» независимо от того, научилась ли она.
13. **Level-check для fix-proposals после инцидента:** Перед тем как предложить fix («добавлю правило в X / обновлю rules/CLAUDE.md / запишу в memory») — пометить уровень embedded-ness (см. `principle-knowledge-in-the-world.md`):
    - **Level 1** (text in docs/rules/memory) — полагается на future-self прочитать и вспомнить применить. Память-как-ресурс. НЕ fix, описание проблемы. Допустим только как черновик формулировки
    - **Level 2** (knowledge-activator injection with anchors) — инжектится на context match. Активация не зависит от attention к system prompt. Минимум для reliable fix
    - **Level 3** (blocker-tier hook с detection_signals на tool/signal) — активация на семантическую акцию (не на фразу). Для confirmed повторяющихся паттернов (confirmed_count ≥ 5)
    Fix остающийся на level 1 после подтверждённого инцидента — это самообман. Escalation mechanism (для защиты от собственной слепоты к этому критерию): `escalation_threshold` + `escalation_mechanism_needed` в frontmatter паттерна; weekly knowledge-audit-digest surface'ит «Engineering escalation needed» → startup-signals → session-start inject. Система сама заявляет о том, что следующий defense level назрел.
14. **Coverage-фичи: верифицируй агрегат на проде-масштабе, не механизм на одном экземпляре** — если критерий успеха фичи это ПОКРЫТИЕ реального множества («обработать/показать ВСЕ X»), верификация «завёл 1 экземпляр → он прошёл» структурно не может вскрыть потолок покрытия. Измеряй **отношение `обработано/всего` на реальном масштабе** (сколько всего объектов в источнике? сколько должно появиться? какая доля реально появилась?). Два конкретных триггера: (а) перед деплоем coverage-фичи — узнать реальный размер источника (`сколько всего чатов/строк/записей?`) и сравнить с любым лимитом/`PAGE_SIZE`/`take` в коде; (б) **счётчик результата, точно равный сконфигурированному лимиту или размеру страницы** (`chats: 50` при `CHATS_PER_RUN = 50`) — трактовать как сигнал усечения, а не полный результат, и спросить «это всё или потолок?». Расширяет п.8 (test input diversity): слепота бывает не только на КЛАСС входа (ASCII vs Unicode), но и на его МАСШТАБ/ОБЪЁМ (1 vs N, sample vs full set). См. case-2026-06-11-single-instance-verify-hides-coverage-cap.
15. **Витрина над сущностью: выводи идентичность колонкой, не только атрибуты** — строя таблицу/список над сущностью, спроси не «какие поля даёт модель при обходе?» (supply-side), а «что читатель строки должен видеть, чтобы опознать саму сущность?» (demand-side). Идентификатор сущности (номер счёта/IBAN, код, имя) — отдельная колонка, его производный атрибут (валюта, статус) — не замена. Два детект-сигнала пропущенной пользовательской колонки: (а) **поле есть в `select`/типе и используется в поиске/фильтре, но не выведено колонкой** — данные прошиты через конвейер, но не показаны (если ищу по полю — пользователь хочет его видеть); (б) **шаблон/референс, который клонируешь, имеет колонку, которой нет у тебя** — сверь список колонок с источником до завершения. Расширяет п.3 (контекстные якоря без контекста) на UI-витрины. См. case-2026-06-12-field-wired-not-surfaced.

**Limitations:** Чеклист закрывает ИЗВЕСТНЫЕ слепые зоны. Неизвестные неизвестные требуют внешней перспективы (собеседник, аналогия, adversarial review). Не применять чеклист к тривиальным задачам — только к дизайну и архитектуре.
