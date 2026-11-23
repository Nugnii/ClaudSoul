---
name: Проверка идёт в рамке, где исправление не действует
description: Исправление внесено в один экземпляр артефакта, проверка запускает другой. Зелёный результат относится к проверенной копии, а работает непроверенная — возврат в состояние до бага без осознания.
type: pattern
outcome: error
confidence: 4
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-22
source_cases:
  - case-2026-11-23-archive-check-inherits-executor-repo-var.md
  - case-2026-11-04-executor-private-env-leaks-into-judged-check.md
  - case-2026-11-09-first-fixes-defective-seven-items-one-day.md
  - case-2026-11-08-checklist-line-checked-in-tall-trial-window.md
  - case-2026-11-06-trial-copy-built-before-its-safety-fix.md
  - case-2026-11-01-zsh-source-resolves-installed-library.md
  - case-2026-10-28-ranges-from-copy-text-from-live-file.md
  - case-2026-10-28-suite-locale-differs-from-hook-locale.md
  - case-2026-10-25-witness-inherits-caller-repo-var.md
  - case-2026-10-07-suite-before-staging-blind-to-new-files.md
  - case-2026-10-19-open-item-check-verified-in-own-home-judged-on-ci.md
  - case-2026-10-01-ring-guard-marker-cleared-by-frame-witness.md
  - case-2026-09-18-silence-explained-by-state-not-reachability.md
  - case-2026-09-15-frame-built-for-likeness-diverged-more-than-the-original.md
  - case-2026-09-15-gate-declared-frame-parity-and-ran-half-of-it.md
  - case-2026-09-13-invariant-unprovable-in-its-own-frame.md
  - case-2026-09-06-atomicity-and-mutual-exclusion-close-different-failures.md
  - case-2026-07-31-writer-is-not-always-a-script.md
  - case-2026-09-04-negation-checked-by-a-command-whose-failure-looks-like-it.md
  - case-2026-09-03-adversary-finds-what-own-tests-cannot.md
  - case-2026-08-20-patch-waves-degrade-spoken-text.md
  - case-2026-04-15-test-stale-file.md
  - case-2026-04-24-install-drift-silent-safeguards.md
  - case-2026-07-29-verification-frame-loop.md
  - case-2026-08-11-verifier-runs-pre-edit-code.md
  - case-2026-09-05-closure-checked-by-an-instrument-weaker-than-the-writer.md
  - case-2026-09-07-fixture-form-written-from-memory.md
  - case-2026-09-09-compensation-without-commit-discriminator.md
  - case-2026-09-11-check-read-before-it-was-shown-to-see.md
  - case-2026-09-12-clean-frame-unchecked-while-commits-piled-up.md
  - case-2026-09-16-recorded-root-is-a-hypothesis-measured.md
source_session: ""
status: active
instrument_verdict: covered   # класс уже ловит hooks/tests/drift-check.sh — проверено исполнением: сравнивает 60 файлов хуков и называет расхождение; второй сигнал был бы дублем, инжектируемым параллельно
instrument_assessed: 2026-07-29
preceded_artifact: yes   # дисциплина отрицательного контроля взята из него: drift-check.sh (v1.14.2) и оба теста к нему построены после того, как паттерн был записан (v1.13.2), и прямо по его предписанию

# Контекстные якоря
domain: [verification, deployment, testing, system_design, agent_design]
situation: артефакт существует в двух экземплярах — редактируемом и исполняемом
trigger: "правка внесена, проверка прогнана, но рамка проверки не та, где правка действует: другой экземпляр из пары (источник/установленное), кэш или вход, состоявшийся до правки"
stakes: ложное «починено»; цикл правка→проверка→правка повторяется, пока не укажут извне
actors: [agent, system]
environment: любая система с раздельными «источник» и «установленное» (repo ↔ deploy, src ↔ build, конфиг ↔ работающий процесс)
circumstances: детектор расхождения либо отсутствует, либо сравнивает не то (наличие вместо содержимого) либо не тогда (старт сессии вместо момента проверки)
purpose: чтобы «проверено» означало «работает то, что проверено»
method: оговорку о расхождении вклеивать в САМУ строку успеха, а не выводить отдельной; при совпадении явно это утверждать, чтобы отсутствие оговорки не читалось как умолчание
tags: [stale-copy, deploy-drift, verification-frame, loop, green-means-nothing]

# Demand-компоненты
need: make_success_signal_refer_to_running_system
urgency: when_relevant
availability: unique

related:
  - pattern-measurement-validity.md
  - pattern-detector-wired-to-failure.md
edges:
  - specializes: pattern-measurement-validity.md
  - similar_to: pattern-detector-wired-to-failure.md

promotion_tier: 2
scope: universal
origin_domain: verification
effective_contradicted: 0.0
contradiction_log: []
modification_history:
  - date: 2026-08-31
    kind: narrowed
    reason: "триггер «правка внесена, проверка зелёная» совпадал с любым успешным фиксом; anchor-review-queue 2026-08-31 — 5 «не к месту» в окне 30 сессий, живой повод: «здесь нет двух экземпляров артефакта — рамка задана чужой формулировкой». Триггер дополнен отличительным условием: рамка проверки не та, где правка действует"
    trigger_case: "anchor-review-queue 2026-08-31"
  - date: 2026-08-11
    kind: scope_widened
    reason: "исход бывает не только ложно-зелёным: при замере по НЕправленому экземпляру результат не меняется вовсе и читается как «фикс не сработал» — это толкает чинить уже исправное. Паттерн не был опознан применимым именно потому, что описывал лишь зелёную сторону"
    trigger_case: case-2026-08-11-verifier-runs-pre-edit-code.md
provenance_log:
  - date: 2026-07-29
    kind: reinforced
    reason: "D31: docs-family-check читает индекс до git add в той же составной команде — проверка в рамке, где изменение ещё не действует"
    trigger_case: v1.14.1
  - date: 2026-07-29
    kind: reinforced
    reason: "три средства за сессию прошли вхолостую тем же способом, против которого построены"
    trigger_case: case-2026-07-29-fix-inherits-its-own-defect.md
  - date: 2026-07-31
    kind: reinforced
    reason: "требование объявлено мёртвым по отсутствию ссылок в хуках; писателем был агент по правилу, в живом проекте 19 и 40 файлов — ошибка выпущена релизом"
    trigger_case: case-2026-07-31-writer-is-not-always-a-script.md
  - date: 2026-08-01
    kind: reinforced
    reason: "дважды за сессию замер был исполнен и относился не к тому артефакту: ссылки в хуках вместо артефактов; выбранный вручную файл вместо файла по умолчанию"
    trigger_case: case-2026-07-31-report-of-a-defect-is-a-hypothesis.md
  - date: 2026-08-07
    kind: reinforced
    reason: "v1.19.0: mcp-стражи прогнаны ДО правки канонных строк README, после — нет; CI поймал сломанный формат «(4 implemented)» — проверка предшествовала правке, рамка не покрыла её"
  - date: 2026-08-07
    kind: reinforced
    reason: "v1.23.0: тесты гонялись до перегенерации автотаблиц README, guards-live проверяет HEAD — рамка локальной проверки не покрывала коммит; Linux CI поймал после пуша"
  - date: 2026-08-07
    kind: reinforced
    reason: "тесты гонялись в рамке полного репозитория, а публиковался урезанный снимок — красный CI жил ровно в непроверяемой рамке; fix переносит pytest в рамку снимка (гейт 4d)"
  - date: 2026-08-08
    kind: reinforced
    reason: "test_ablation_finish зелёный локально (глобальный gitconfig есть), красный в CI (нет идентичности для git tag -a) — рамка проверки маскировала; контейнерный рецепт development.md перед релизом не гонялся"
  - date: 2026-08-09
    kind: reinforced
    reason: "?test не мог читать файлы из file:// — проверка шла в рамке, где расхождение ненаблюдаемо; починено запеканием метки в HTML"
  - date: 2026-08-09
    kind: reinforced
    reason: "сага видимости фазы: три поверхности подряд (additionalContext, systemMessage, statusline) проверены в CLI-рамке, владелец живёт в VSCode-расширении, которое не рендерит ни одну; рамка владельца не была установлена ДО выбора поверхности"
  - date: 2026-08-09
    kind: reinforced
    reason: "Дважды: (1) прежний урок '.DS_Store → rm -rf .next' проверялся в рамке до сборки, а файл пишется В ХОДЕ неё; (2) страж canary требует сегмент фазы, хотя он в шапке есть — проверяет не тот носитель"
  - date: 2026-08-09
    kind: reinforced
    reason: "трижды за сессию: кабинет/настройки/модалки давали зелёное, где рамка не отличала покрытие от редиректа"
  - date: 2026-08-21
    kind: reinforced
    reason: "case-2026-08-20-patch-waves-degrade-spoken-text: проверка голосом шла до патч-волн и не перепроверяла ушедший текст"
  - date: 2026-08-21
    kind: reinforced
    reason: "Первая версия test_usage_outcome_audit проверяла перекос в рамке, где он не мог проявиться: одинаковый session_id во всех записях схлопнул 6 сессий в одну, проверка шла вхолостую"
  - date: 2026-08-21
    kind: reinforced
    reason: "regen-readme-skills запускался с README=... вместо README_FILE=... — генератор молча перегенерировал английский README и отчитался «50 hooks», хотя русская таблица не менялась: проверка шла в рамке, где правка не действовала"
  - date: 2026-08-23
    kind: reinforced
    reason: "отладочная копия теста в /tmp вычисляла путь к хукам от $0 и получала /: проверялся не тот экземпляр, пустой вывод читался как «страж молчит», выводы пришлось выбросить"
    trigger_case: case-2026-08-23-check-never-ran-looks-like-check-passed.md
  - date: 2026-08-26
    kind: reinforced
    reason: "Разбор готовности к деплою вёлся по устаревшей локальной копии прод-данных: три из четырёх блокеров оказались ложными, а настоящая мина (186 списаний августа без отметок notifiedAt/mirroredAt) была не видна вовсе. Проверка в верной рамке — свежий дамп прода + запросы к самому серверу — перевернула вывод целиком."
  - date: 2026-08-26
    kind: reinforced
    reason: "1393 зелёных теста проверяли логику цены (она сходилась до гроша), а сломан был смысл подписи на экране — рамка проверки не покрывала предмет утверждения о готовности"
  - date: 2026-08-26
    kind: reinforced
    reason: "прочитал $? после пайпа — это код tail, а не regen-seed.py; вывод «страж вернул 0» относился к другой команде. Перепроверено без пайпа: настоящий код 1, страж работает как задокументировано"
  - date: 2026-08-26
    kind: reinforced
    reason: "зелёные тесты репозитория не доказывали ничего про установленную копию: проверка повторена на функции из ~/.claude и в bash, как исполняются хуки"
    trigger_case: case-2026-08-26-keep-list-is-a-copy-not-a-derivation.md
  - date: 2026-08-26
    kind: reinforced
    reason: "дважды за сессию: соседняя сессия пересобрала .next и вернула прод-домен кабинета; локальная база отстала от миграции релиза (P2022) — оба раза симптом выглядел дефектом теста, а не дрейфом рамки"
    trigger_case: case-2026-08-26-constant-indicator-stops-being-signal.md
    session: ""
  - date: 2026-09-01
    kind: reinforced
    reason: "test_completion_gate_hostile_backlog: 5/5 напрямую и rc=1 из архиватора — исполнитель Проверок ставит BACKLOG_CHECKS_NESTED=1, и гейт внутри теста выходил первой строкой"
    session: ""
  - date: 2026-09-02
    kind: reinforced
    reason: "инжект пришёл в момент записи пунктов бэклога; прогнал все шесть команд «Проверки» — D260 оказалась красной не по названной причине (падала на слове adjacent)"
    session: ""
  - date: 2026-09-04
    kind: reinforced
    reason: "Проверка мутации шла в рамке, где починка не действует: подменил число, отфильтровал вывод сверщика по слову «mcp», а описание строки реестра — «проверок в наборе сервера». Сверщик сработал, а я прочёл тишину как его молчание и решил, что строка реестра не работает"
    session: ""
  - date: 2026-09-05
    kind: reinforced
    reason: "Реплей по корпусу давал 11 освобождений и 0 ложных — и по построению молчал о полноте; дыры нашлись только у противника. Плюс мутацию я сперва прогнал на git archive HEAD, где правки нет вовсе"
    session: ""
  - date: 2026-09-05
    kind: reinforced
    reason: "прогон run_all стартовал до трёх последних правок; его зелёный был о прежнем дереве, перепрогнал"
    trigger_case: case-2026-09-05-closure-checked-by-an-instrument-weaker-than-the-writer.md
    session: ""
  - date: 2026-09-06
    kind: reinforced
    reason: "проверка «доступна ли hash_value» через source хука с /dev/null дала «НЕ ДОСТУПНА» у всех трёх — рамка неверная: хук выходит рано без payload. Прогон с настоящим payload показал permissionDecision:ask, то есть функция отработала; знание было подано активатором ровно перед этой проверкой"
    session: ""
  - date: 2026-09-07
    kind: reinforced
    reason: "все 12 ног теста звали страж с явным CLAUDSOUL_REPO, а дефект живёт там, где корень выводится из расположения файла — рамка проверки не совпадала с миром установленной копии"
    session: ""
  - date: 2026-09-07
    kind: reinforced
    reason: "три проявления за сессию: фикстура с неверным разделителем, прогон без соседних библиотек, канарейка в несуществующей форме — каждый раз проверка шла в рамке, где предмет не действует"
    trigger_case: case-2026-09-07-fixture-form-written-from-memory.md
    session: ""
  - date: 2026-09-09
    kind: reinforced
    reason: "проверка фичи дважды шла в чужой рамке: спека на localhost:3000 вместо прода, затем клиент 227, предоплаченный насквозь до конца 2027 — исправление действовало, а рамка проверки его не видела"
    trigger_case: case-2026-09-09-compensation-without-commit-discriminator.md
    session: ""
  - date: 2026-09-12
    kind: reinforced
    reason: "сверка маркера базиса шла через git archive HEAD, где моей правки нет вовсе — повтор записи от 2026-09-05; поймал контраст «починенный/прежний», давший одинаковый ответ"
    trigger_case: case-2026-09-11-check-read-before-it-was-shown-to-see.md
    session: ""
  - date: 2026-09-12
    kind: reinforced
    reason: "рамка проверки — машина с установленной копией, рамка CI — чистая; 8 красных при 438 зелёных локально"
    trigger_case: case-2026-09-12-clean-frame-unchecked-while-commits-piled-up.md
    session: ""
  - date: 2026-09-12
    kind: reinforced
    reason: "рамка контейнера (mawk, POSIX-локаль, без procps) отличалась от раннера; после выравнивания по названным расхождениям 5 красных → 0, а mawk оставлен как более строгая рамка, нашедшая дефект хука (D404)"
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "атаки, строящие песочницу из git archive HEAD, судят закоммиченное: правка свидетеля в рабочем дереве их не зеленит до коммита (13 сентября 2026)"
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "инжектнулось ровно тогда, когда я собрался положить outcome_signals в кейс: читатель fix-level-check глобит только pattern/principle, механизм не сработал бы ни разу — проверено до записи, а не после"
    session: ""
  - date: 2026-09-15
    kind: reinforced
    reason: "гейт публикации объявлял «та же рамка, что публичный CI» и прогонял одну работу из двух — 5 публикаций красными"
    trigger_case: case-2026-09-15-gate-declared-frame-parity-and-ran-half-of-it
    session: ""
  - date: 2026-09-16
    kind: reinforced
    reason: "проба владельца дала пустой результат под zsh (BASH_SOURCE там нет), и это выглядело дефектом кода; в рамке bash всё сходится"
    trigger_case: case-2026-09-16-recorded-root-is-a-hypothesis-measured.md
    session: ""
  - date: 2026-09-18
    kind: reinforced
    reason: "третья переработка project-conformance.sh 18 сентября 2026: две первые редакции проверялись прогоном на ЖИВЫХ файлах, где разметка цела и красная ветка недостижима по построению. Дефекты (os.environ без import os; оба счёта одним признаком backlog_item_re, из-за чего расхождение недостижимо) вскрылись за одну команду, как только построена фикстура сломанной разметки. Брат того же устройства в тот же день — зонд A2, судивший по присутствию файла в живом дереве и давший 0 из 4"
    session: ""
  - date: 2026-10-01
    kind: reinforced
    reason: "1 октября 2026: «Проверку» D499 проверял прямым прогоном (зелёная, 1 с), а под исполнителем она замыкала кольцо — свидетель снимал маркер вложенности и звал архиватор на живом бэклоге; 298 процессов"
    session: ""
  - date: 2026-10-05
    kind: reinforced
    reason: "ClaudSoul 5 октября 00:10: полный набор во временной копии с выставленной CLAUDSOUL_REPO — 606 из 631, тесты получали временную копию вместо ожидаемого корня; 45 минут без вердикта"
    session: ""
  - date: 2026-10-19
    kind: reinforced
    reason: "«Проверка» D1006 дважды проверена в своём доме (красна), а судилась сторожем completion-gate в рамке CI (песочный STATE_DIR, затем HOME без установки) — зелёная у открытого, три красных CI"
    trigger_case: case-2026-10-19-open-item-check-verified-in-own-home-judged-on-ci.md
    session: ""
  - date: 2026-10-25
    kind: reinforced
    reason: "/compile 25.10: case-2026-10-07-suite-before-staging-blind-to-new-files — прогон судил индекс без нового файла, коммит его нёс (7.10 и 25.10)"
    session: ""
  - date: 2026-10-28
    kind: reinforced
    reason: "хук выбрал ROOT, индексатор взял корень из унаследованной CLAUDSOUL_REPO — 19 красных ног (ClaudSoul D1076, 25.10)"
    trigger_case: case-2026-10-25-witness-inherits-caller-repo-var.md
    session: ""
  - date: 2026-10-28
    kind: reinforced
    reason: "свидетель сроков унаследовал CLAUDSOUL_REPO вызывающего (ClaudSoul D1074, 25.10)"
    trigger_case: case-2026-10-25-witness-inherits-caller-repo-var.md
    session: ""
  - date: 2026-10-30
    kind: reinforced
    reason: "D1169 r2: имитация гонки писала в копию, а не в живой файл — воспроизводила гонку на исправном коде"
    trigger_case: case-2026-10-28-ranges-from-copy-text-from-live-file
    session: ""
  - date: 2026-10-30
    kind: reinforced
    reason: "D1158/D1171: набор под C.UTF-8, хуки терминала под ru_RU.UTF-8 — 4 файла красны только под рабочей локалью"
    trigger_case: case-2026-10-28-suite-locale-differs-from-hook-locale
    session: ""
  - date: 2026-11-01
    kind: reinforced
    reason: "D1156: сверка до/после воркера backfill-compliance-one на копии без соседнего output-language-detect.py дала «разнится 40 из 40» — класс C молчал у копии; с детектором рядом 40 из 40 одинаково"
    session: ""
  - date: 2026-11-01
    kind: reinforced
    reason: "1.11.2026: функция библиотеки хука под zsh взяла установленную копию разбора (BASH_SOURCE пуст) — проверка мерила не ту редакцию"
    trigger_case: case-2026-11-01-zsh-source-resolves-installed-library.md
    session: ""
  - date: 2026-11-06
    kind: reinforced
    reason: "Litara 2026-11-06: защита в исходниках, запущена сборка до неё — побочный эффект на живой машине"
    trigger_case: case-2026-11-06-trial-copy-built-before-its-safety-fix.md
    session: ""
  - date: 2026-11-07
    kind: reinforced
    reason: "D1233, 7 ноября 2026: проба гоняла тесты с унаследованным CLAUDSOUL_REPO — рамка, где снятая CLAUDSOUL_ROOT ничего не меняла; сверка мутантом в копии поймала до закрытия"
    session: ""
  - date: 2026-11-09
    kind: reinforced
    reason: "Litara B50: осмотр B29 в пробной сборке с высоким окном не мог показать переполнение окна 720"
    session: ""
  - date: 2026-11-09
    kind: reinforced
    reason: "D1263, 9 ноября 2026: проба сверки зелёная обычным запуском и красная во вложенном режиме (BACKLOG_CHECKS_NESTED=1) — архиватор под маркером отвечал «перенос пропущен» кодом 0; поймал прогон «Проверки» перед ☑ в рамке исполнителя (05453de3)"
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "ProjectA B737, 22.11.2026: тест печати снимка зелёный, а в настоящем прогоне Playwright снимок вставал до разбора ошибок и срезался | tail; и первые две пробы CI шли на коде без коммита, не задевая тест-закрепление B699"
    session: ""
---

## Суть

Артефакт живёт в двух экземплярах: тот, который правят, и тот, который работает. Исправление попадает в первый, проверка запускает первый, вывод «починено» делается про второй. Второй не менялся.

Собеседник дал точное имя структуре: **закольцовка** — исправление возвращает систему в состояние, бывшее до бага, но в этом состоянии исправление ещё не действует.

**У расхождения две стороны, и вторую легко не узнать.** Ложно-зелёная: проверили правленый
экземпляр, работает непроверенный, вывод «починено» ложен. Ложно-**красная**: замер идёт по
НЕправленому экземпляру, результат не меняется вовсе — и читается как «фикс неверен», толкая
чинить уже исправный код. Признак второй стороны точный: результат совпадает с прежним
**побайтно**, включая дробные значения, а не «похож». Такое совпадение после реальной правки
физически невозможно — значит отвечает не тот экземпляр (2026-08-11: MCP-сервер сессии держал
код, загруженный при её старте; в той же сессии часом ранее — dev-сервер Next с Prisma-клиентом,
сгенерированным до миграции).

## Почему повторяется, а не случается один раз

Баг не воспроизводит себя сам. Воспроизводит себя **способ убедиться, что баг исчез**. Каждое новое исправление создаёт артефакт, у артефакта снова две копии — петля порождается заново уровнем ниже. Отсюда наблюдаемая периодичность.

**Ветвление**: экземпляров столько, сколько пар «источник ↔ установленное». В ClaudSoul на 2026-07-29 их шесть — хуки, библиотеки, скиллы, правила, seed знаний, `bin`. Детектор построен для одной.

## Три подтверждения

1. `case-2026-04-15-test-stale-file` — правил файл в репозитории, тестировал старую копию в `~/.claude/hooks/`; две попытки впустую.
2. `case-2026-04-24-install-drift-silent-safeguards` — восемь релизов подряд safeguard-хуки лежали в репозитории и в `install.sh`, но не попадали в `~/.claude/hooks/`. Пометка в кейсе: «любой новый хук между install-запусками попадает в эту же ловушку» — то есть ветвление было названо ещё тогда.
3. `case-2026-07-29-verification-frame-loop` — тесты гоняют репозиторий, живая система работает установленным; детектор дрейфа сравнивает наличие, а не содержимое, и только на старте сессии.

## Как применять

Перед тем как считать проверку доказательством, ответить: **какой именно экземпляр она запускала?** Если у артефакта есть отдельная работающая копия — зелёный результат про неё ничего не говорит.

Лечится не отдельным предупреждением: его проматывают вместе с зелёным итогом. Оговорка должна менять **саму строку успеха**, а при совпадении копий — утверждать совпадение явно, чтобы тишина не читалась как «всё хорошо».

## Ограничения

Детектор расхождения сам является артефактом с двумя копиями и, устарев, не сообщает о собственной устарелости. Это предел механизации: последний уровень рекурсии закрывается только внешней сверкой.
