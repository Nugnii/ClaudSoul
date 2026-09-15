# Справочник — хуки и команды

Генерируется из исходников командой `README_FILE=docs/reference.ru.md bash scripts/regen-readme-skills.sh` (без `README_FILE` скрипт пересобирает `README.md`, а не этот файл). Таблицы руками не править: описания хуков берутся из второй строки шапки каждого хука, описания команд — из поля `description` во frontmatter каждого `SKILL.md`. Правьте там и запускайте команду заново.

Назад в [README](../README.ru.md).

## Хуки

Хуки — скрипты оболочки. К событиям жизненного цикла Claude Code (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`, `Stop`, `SessionEnd`) подключены 75 хука из 82 — они замечают, подставляют и записывают, не дожидаясь вызова; остальные запускаются по расписанию launchd, вызываются другими хуками или командами либо запускаются вручную как разовые досчёты.

Вмешаться в вызов могут 14 из них, и делают это по-разному. 4 поднимают `permissionDecision: ask` и передают выбор вам — `bash-cost-detector`, `user-correction-guard`, `bulk-copy-guard`, `internal-doc-leak-guard`. 10 возвращают `deny` и отказывают агенту, вас не тревожа: `playwright-cli-guard`, `rules-write-bypass`, `five-whys-gate`, `skill-name-ascii-guard` и `blocker-tier-check` — последний лишь для тех знаний, у которых признак помечен `enforcement: deny`. Всё остальное молча пишет в контекст агента и оставляет решение за ним: шум — это отдельный способ сломать систему.

<!-- HOOKS-TABLE:START -->

| Хук | Когда срабатывает и что делает |
|-----|-------------------------------|
| `ablation-phase-guard` | фаза замера видима и защищена механически (§6). |
| `absent-tool-guard` | PreToolUse[Bash]: команда зовёт инструмент, которого на ЭТОЙ машине нет, и отказывается исполняться впустую. |
| `accepted-alternative-gap` | Stop: принятие варианта собеседника = событие промаха. |
| `auto-scanner` | launchd (каждые 4ч): read-only сканирование проектов, запись находок в scan-results.md для следующей сессии. |
| `backfill-compliance` | восстановить ЗАВИСИМУЮ ПЕРЕМЕННУЮ из архивных транскриптов. |
| `backfill-intrusiveness` | разовый добор событий gentle/proactive из архивных расшифровок ~/.claude/projects/*/*.jsonl. Не хук: запускается по требованию. |
| `backlog-open-write-guard` | PreToolUse[Edit\|Write\|MultiEdit] на BACKLOG.md: открытый пункт с зелёной или отсутствующей «Проверкой» не записывается. |
| `backlog-reading-refresh` | PostToolUse: показания бэклога пересчитаны по правке и сверены при чтении. |
| `backlog-touch-check` | PreToolUse[Edit\|Write\|MultiEdit]: правишь файл, который назван в открытом пункте долга. |
| `backlog-vanish-check` | PreToolUse[Bash] на `git commit`: пункт долга не должен исчезать бесследно. |
| `bash-cost-detector` | PreToolUse[Bash]: детектирует деструктивные команды (rm -rf, git push --force, DROP) и поднимает silence_cost сигнал для L6 gate. |
| `bash-write-dispatch` | PostToolUse[Bash]: правка, сделанная КОМАНДОЙ, подаётся стражам записи, которые видят только инструмент Edit. |
| `blocker-tier-check` | PreToolUse: silent 🛑 marker для знаний с `blocker: true`, когда действие совпадает с detection_signals паттерна. |
| `bridge-health-digest` | ежемесячный механический свод по 16 мостам в bridges/ (межслойные плюс внутрислойный L2↔L2): состояние, слои, версии, сводные счётчики. |
| `budget-gate` | PreToolUse[Edit\|Write\|MultiEdit\|NotebookEdit]: самовольная правка при исчерпанном бюджете проактивных действий получает инжект «преврати в вопрос собеседнику» (ADR-010 Ф2). |
| `bulk-copy-guard` | PreToolUse: спрашивает владельца перед оптовым копированием, переносом и rsync. |
| `carrier-growth-check` | Stop: прирост носителей рода называется вместе с файлом. |
| `changelog-reminder` | PreToolUse[Bash] на `git commit`: тихо напоминает добавить запись в CHANGELOG.md, если в staged diff есть изменения КОДА, а CHANGELOG.md в staged нет. |
| `ci-check-reminder` | PostToolUse[Bash]: после `git push` напоминает проверить прогон СВОЕГО коммита, а не «самый свежий». |
| `claude-md-size-check` | PreToolUse[Bash] на `git commit`: тихо предупреждает, если CLAUDE.md проекта раздулся выше порога стоимости контекста. |
| `claudsoul-context-pointer` | UserPromptSubmit hook, инжектит project CLAUDE.md status section при упоминании ClaudSoul снаружи директории проекта. |
| `code-review-outcome` | PostToolUse[Bash] на `git commit`: подтверждает, что коммит СОСТОЯЛСЯ, и только тогда переводит запись стража в знаменатель замера. |
| `code-review-reminder` | PreToolUse[Bash] на `git commit`: крупный кодовый дифф идёт в коммит без адверсариального прогона — поручает СКАЗАТЬ собеседнику про `/adversary`. |
| `completion-gate` | Stop: пункт сверяется со СВОИМ критерием, а не с отчётом; пункт, заведённый в этой сессии, берётся сразу за текущей починкой. |
| `declared-problem-recorded` | Stop: названная проблема обязана лечь в носитель (D103). |
| `decompose-detector` | pre-execution router в UserPromptSubmit: шаги→/decompose, решения→/grilling. |
| `doc-impact-check` | PreToolUse[Bash] на `git commit`: называет документы, описывающие изменённое, и требует решения по документу состояния при правке поведения. |
| `docs-family-check` | PreToolUse blocker-tier для docs family coverage при version bump. |
| `enrich-suggester` | UserPromptSubmit hint при наличии recently-modified sparse entity. |
| `error-tracker` | PreToolUse[Bash]: при 2+ упавших командах в окне последних 6 говорит «стой» ПЕРЕД следующей попыткой, а не после упавшей. |
| `external-correction-gap` | детекция внешней рецензии в UserPromptSubmit. |
| `five-whys-gate` | PreToolUse: повтор замечен, а разбора причин не было — требует «5 почему». |
| `fix-level-check` | детектор пост-инцидентного фикса, оставшегося текстом. |
| `impact-inject` | PreToolUse[Edit\|Write\|MultiEdit] и PostToolUse[Bash]: при правке файла ЛЮБЫМ путём подаёт ПОЛНЫЙ ПУТЬ по карте связей — кто на этом файле стоит (тесты, документы, знания, пункты долга, рода, корни) и на скольких стоит он сам; новый файл вносит в карту и говорит об этом, а если он попал в СЧИТАЕМОЕ множество (хуки, библиотеки, тесты, скиллы, домены, мосты) — называет сдвиг чисел документов и команду пересчёта; рядом называет, чем проверить после сохранения. |
| `inquiry-gap` | UserPromptSubmit: вопрос собеседника ≠ поручение. |
| `install-drift-notice` | Stop: правка, не дошедшая до установленной копии, не действует. |
| `internal-doc-leak-guard` | PreToolUse: не даёт записать помеченное внутренним в каталоги, которыми делятся наружу (lawyer / counsel / advisor). |
| `intrusiveness-tracker` | UserPromptSubmit: поддерживает состояние L6 intrusiveness gate, классифицирует state (focus/idle/stuck/exploration), инжектит в контекст. |
| `itr-event-detector` | UserPromptSubmit: находит мягкое предложение в прошлом ответе агента, определяет, принял его собеседник или проигнорировал, и записывает исход — иначе бюджеты слоя 6 не набираются. |
| `knowledge-activator` | PreToolUse[Bash\|Edit\|Write\|MultiEdit]: инжектит SESSION.md и релевантные знания из global-lessons при первом действии сессии. |
| `knowledge-audit-digest` | еженедельный механический аудит global-lessons: счёт записей, распределение надёжности, корзины FSRS. |
| `knowledge-capture-reminder` | PostToolUse[Bash]: напоминает собрать материал в черновики базы знаний, когда за сессию накопилось N коммитов, а с прошлого напоминания захвата не было. |
| `knowledge-counter-bump` | механический инкремент счётчиков знания. |
| `knowledge-frontmatter-check` | PostToolUse[Bash\|Write\|Edit\|MultiEdit]: битый YAML frontmatter и НЕПОЛНАЯ шапка записанного знания называются СРАЗУ, а не когда-нибудь при прогоне тестов; набор обязательных полей выводится из шаблона контура. |
| `knowledge-link-symmetry` | PostToolUse[Bash\|Write\|Edit\|MultiEdit]: ссылка кейс → паттерн получает встречную. |
| `lib-prefix-guard` | PreToolUse[Write\|Edit\|MultiEdit]: новая функция библиотеки носит имя из ОБЪЯВЛЕННОГО пространства имён, а не выведенное из ряда соседних. |
| `mcp-orphan-reap` | SessionEnd: осиротевший сервер MCP снимается по признаку сиротства. |
| `mechanism-has-consumer` | PreToolUse[Bash] на `git commit`: механизм, которого никто не зовёт, называется ДО фиксации. |
| `metrics-collector` | вызывается auto-scanner / /knowledge-audit: считает метрики здоровья базы, пишет в state/metrics.md. |
| `module-context-inject` | PreToolUse[Edit\|Write\|MultiEdit]: при правке файла подаёт модуль документации, который его описывает, заголовки его бизнес-правил и напоминание обновить модуль тем же коммитом; файл, не описанный ни одним модулем, называет отдельно. |
| `module-doc-check` | PreToolUse[Bash] на `git commit`: новый модуль в staged без модульного дока — тихое напоминание завести .claude-docs/modules/<имя>.md. |
| `output-language-check` | Stop/PreCompact/UserPromptSubmit/PreToolUse: находит в ответе слова со смешением алфавитов и показывает их следующим ходом. |
| `partial-read-guard` | PostToolUse[Read]: называет числом, сколько строк файла прочитано. |
| `pending-alerts-surface` | UserPromptSubmit: поднимает отложенное видимым каналом. |
| `pipefail-grep-q-notice` | PreToolUse[Write\|Edit\|MultiEdit]: пайп в `grep -q` под `set -o pipefail`, чей статус проверяется, назван до записи. |
| `playwright-cli-guard` | PreToolUse: блокирует одноразовые Playwright-скрипты, вынуждая использовать CLI (codegen / test / show-trace). |
| `pre-compact-finalizer` | PreCompact: фиксирует chunk-границу до компакта. |
| `pre-compact-handoff` | PreCompact: сохранить нить работы перед сжатием контекста. |
| `publish-guard` | PreToolUse: публикация наружу ждёт показанного сухого прогона. |
| `quality-gate-check` | PreToolUse страж контракта скиллов при `git commit`. |
| `reformulation-tracker` | UserPromptSubmit: каскадная верификация предсказаний (FORWARD/PROPOSAL/BACKWARD), логирует outcome и напоминает фиксировать gap. |
| `relative-date-check` | Stop/PreCompact: относительное время («вчера», «на днях», «час назад») без абсолютного якоря рядом — находка; в следующем ходе показывает её вместе с текущими датой и временем. |
| `response-tracker` | PostToolUse: пишет РЕАКЦИЮ агента после того, как система его о чём-то предупредила. |
| `revert-signal` | PostToolUse[Bash]: откат коммита и повторный hotfix одного файла — повод разбора. |
| `rework-detector` | PostToolUse: ВТОРОЙ заход на тот же файл при зелёных прогонах (разворот); цели правки берутся у мира, а не из формы команды. |
| `rules-write-bypass` | PreToolUse[Bash]: запись в установленные правила только через библиотеку (D101). |
| `secret-guard` | PreToolUse[Edit\|Write\|MultiEdit]: секрет, вписываемый в файл, отбивается отказом, а не напоминанием. |
| `semantic-prefetch` | UserPromptSubmit: фоновый предкэш семантического поиска по теме реплики. |
| `session-collector` | Stop: напоминает записать незафиксированные уроки через /learn, финализирует сессию в реестре, чистит ephemeral state. |
| `session-end` | SessionEnd: финализирует сессию в registry при завершении (exit/clear/logout), снимает запись из active/. |
| `session-start` | SessionStart: регистрирует сессию в registry при старте (startup/resume/clear/compact) для видимости параллельных сессий. |
| `skill-name-ascii-guard` | PreToolUse[Bash]: имя скилла вне латиницы отбивается отказом, а не напоминанием. |
| `skill-review-check` | PreToolUse skill contract gate при `git commit`. |
| `subagent-outcome` | SubagentStop: субагент, кончившийся БЕЗ ответа, становится поводом разбора. |
| `test-cost-notice` | PostToolUse[Write\|Edit\|MultiEdit]: правка теста, чья ИЗМЕРЕННАЯ цена выше порога, называет её числом и приёмы удешевления. |
| `test-exit-explicit-guard` | PreToolUse[Write\|Edit\|MultiEdit]: тест, чей код возврата берётся у последней команды, а не у явного exit, в дерево не записывается. |
| `timestamp-canary-check` | Stop: механическая проверка таймштамп-канарейки. |
| `timestamp-inject` | UserPromptSubmit: инжект текущего времени собеседника; шапку несёт ПЕРВЫЙ текстовый блок хода, в следующих блоках она не повторяется. |
| `tool-gate-check` | PostToolUse: вызов инструмента без гейта и печать отказа на Stop. |
| `trust-guard` | PreToolUse: разрушительная команда без явного разрешения собеседника в последних репликах останавливается вопросом (аффект-протез №1: тормоза, которого в архитектуре нет). |
| `undefined-function-check` | PostToolUse[Bash\|Write\|Edit\|MultiEdit]: вызов функции, которой нет, называется в момент записи файла, а не в рантайме. |
| `user-correction-guard` | PreToolUse: собеседник только что поправил — следующий вызов инструмента останавливается вопросом, пока поправка не переформулирована. |

<!-- HOOKS-TABLE:END -->

## Команды

Скиллы — вызываемые пользователем сценарии, устанавливаются в `~/.claude/commands/`.

<!-- SKILLS-TABLE:START -->

| Команда | Что делает |
|---------|-----------|
| `/adversary` | Адверсариальное ревью кода: субагент в чистом контексте доказывает, что код ломается, каждую атаку воспроизводит падающим тестом и ничего не чинит. Раундами, каждый раунд новым критиком. Зови перед коммитом, деплоем, сдачей — и когда сам уверен, что готово. «Проверь что ломается», «прожарь код», «адверсариальное ревью», «найди дыры перед деплоем». |
| `/bridge-health` | Мониторинг 16 мостов (15 межслойных + 1 внутрислойный): статус, метрики активности, здоровье связей между когнитивными слоями. |
| `/compile` | Batch-консолидация накопленного сырья в кандидаты знаний — читает _drafts/SESSION/_capture, извлекает 3-7 знаний, дедуп против базы (NEW/UPDATE/CONTRADICTS), пишет черновики. |
| `/decompose` | Декомпозиция задачи перед execution: scope → шаги → зависимости → план. Для задач >3 шагов. |
| `/enrich` | Веб-обогащение сущности по tier-источникам. Конфликты в contradiction, не перезаписывает. /enrich <name\|slug> либо «обнови X». |
| `/entity` | Показать, что база знаний ClaudSoul знает о сущности (человеке, компании, концепции, событии) — атрибуты, связанные факты, типизированные связи. Запускай по /entity <имя> или когда пользователь спрашивает «что ты знаешь о X», «покажи, что есть про X», «карточка сущности X». Только чтение, не редактирует. |
| `/grilling` | Безжалостное интервью по дереву решений: вытащить молчаливые допущения из плана/идеи до действия. Раундами по фронтиру, каждый вопрос с рекомендованным ответом, факты ищет агент сам. /grilling <план или идея>. |
| `/ingest` | Добавить материал в базу знаний ClaudSoul (второй контур обучения). Запускай явно по /ingest или когда пользователь говорит «добавь в базу знаний», «запомни это», «внеси в базу», «разбери и запомни», «проанализируй и добавь», «изучи и сохрани». Принимает локальный файл (MD/TXT/PDF/DOCX/HTML), URL, текст-сниппет или изображение/скриншот. Извлекает сущности, факты и связи, сливает в глобальную базу знаний, показывает отчёт и ссылку на граф. |
| `/init-project` | Завести проект ИЛИ проверить уже заведённый: сверяет CLAUDE.md, SESSION.md, документацию и память с нынешним договором и называет расхождения. В новом проекте создаёт недостающее, в существующем — только проверяет и ничего не переписывает. Запускать при начале работы в проекте и когда нужно убедиться, что настройка не отстала. |
| `/knowledge-audit` | Аудит базы знаний: метрики здоровья, надёжность, decay, рекомендации. Измеряет рост системы. |
| `/knowledge` | L2 координатор знаний: routing к /learn, /retro, /knowledge-audit, /bridge-health по контексту. Единая точка входа. |
| `/learn` | Быстрая запись знания — auto-detect тип (error/success/communication), запись case, проверка на промоушен в pattern. |
| `/narrative` | Override / force-regen для through-line brief проекта. Основной путь — auto-trigger в session-start хуке (gap ≥8ч). Этот скилл для ручного запуска и dry-run. |
| `/pipeline` | L1 оркестратор: scope → plan (/decompose) → execute → quality gate (/quality-gate) → done. Для задач любой сложности. |
| `/project-health` | Понять проект → карта здоровья → план оздоровления в правильной последовательности → живой трекер. Понимание сначала, починка потом. Для большого или незнакомого проекта. |
| `/quality-gate` | Проверка качества перед маркировкой задачи done: PASS / CONCERNS / FAIL / WAIVED. DoD, тесты, review. |
| `/release` | Выпустить релиз проекта: bump SemVer → CHANGELOG из conventional commits → sync README/CLAUDE.md → commit + tag. Применяет global `## Versioning discipline`. |
| `/reload` | Перечитать базу знаний и контекст проекта без перезапуска сессии. Полезно при параллельных сессиях. |
| `/retro` | Разбор после починки: что именно пошло не так, какие уроки из этого следуют, и запись их в базу знаний с оценкой уверенности. |
| `/save` | Сохранить прогресс сессии в SESSION.md. Использовать при длинных сессиях или перед завершением работы. |
| `/skill-forge` | Исследование проблемы → ресёрч GitHub → синтез скилла → решение задачи. Для сложных задач без готового скилла. |
| `/skill-review` | Проверка SKILL.md на соответствие контракту ClaudSoul. Показывает нарушения и предлагает фиксы. |
| `/trajectory-prediction` | Методология L4 (траектория мысли) + L6 (предсказание): каскадный лог гипотез, предсказание-верификация, 4D-гейт интрузивности. Детали грузятся по надобности. |
| `/wiki` | Wiki-страница по сущности: нарратив + ссылки. Разметка по entity_type. /wiki <name\|slug> либо «расскажи про X». Только чтение. |

<!-- SKILLS-TABLE:END -->
