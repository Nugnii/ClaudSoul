---
name: Форма входа проверки взята не из мира
description: Фикстура, канарейка или аргумент замера задают вход в форме, которой настоящий писатель не производит. Признак при этом исправен, лжив вход — и проверка зелена вхолостую либо краснеет не по делу, а «до» и «после» дают одинаковое число.
type: pattern
outcome: error
confidence: 3
impact: 5
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-22
source_cases:
  - case-2026-11-22-test-matcher-written-from-memory-of-output.md
  - case-2026-11-22-ui-verified-on-mockup-data-not-live.md
  - case-2026-11-22-ssh-double-died-by-signal-hid-ctrl-c-defect.md
  - case-2026-11-22-secret-boundary-delegated-to-gitignore.md
  - case-2026-11-07-name-linking-ignored-module-visibility.md
  - case-2026-10-30-leg-for-reported-input-not-verbatim.md
  - case-2026-10-27-fixture-off-world-held-by-scattered-copies.md
  - case-2026-10-28-exemption-leg-exited-on-prefilter.md
  - case-2026-10-21-test-examples-from-memory-wrong.md
  - case-2026-10-12-fix-method-from-fixture-refuted-by-prod-shape.md
  - case-2026-09-14-named-root-was-latent-the-live-cause-was-another.md
  - case-2026-09-14-leg-measured-length-on-a-message-too-short-to-cut.md
  - case-2026-09-12-item-check-held-a-fabricated-form-and-stayed-red-after-the-fix.md
  - case-2026-09-02-fixture-green-on-a-form-the-world-never-produces.md
  - case-2026-09-07-fixture-form-written-from-memory.md
  - case-2026-09-11-check-read-before-it-was-shown-to-see.md
  - case-2026-09-15-absent-by-design-read-as-a-defect.md
  - case-2026-09-17-declared-limit-is-a-hypothesis-too.md
  - case-2026-10-10-rule-only-at-trust-boundary-fixtures-pin-unreachable-state.md
  - case-2026-11-15-ui-library-selector-written-from-memory-again.md
  - case-2026-11-16-css-override-selector-by-memory-antd-dom.md
  - case-2026-11-18-ci-only-red-reproduced-in-wrong-runner-image.md
  - case-2026-11-18-antd-sibling-selector-from-memory-third-time.md
  - case-2026-11-19-css-override-written-without-measuring-library-specificity.md
  - case-2026-11-20-spec-locator-text-taken-from-code-not-page.md
  - case-2026-11-20-probe-opener-guessed-instead-of-reading-page-snapshot.md
source_session: ""
status: active
scope: universal
promotion_tier: 2

domain: [verification, testing, measurement, agent_design]
situation: пишется проверка, и вход для неё сочиняется в тексте самой проверки
trigger: "вход фикстуры задан по памяти о форме либо по форме чужого механизма, а не извлечён из настоящего носителя: разделитель, кавычки, обязательное поле, окружение файла"
stakes: ложная зелень защиты, которой в бою нет; замер, где «до» и «после» совпали, читается как «эффекта нет»
actors: [agent]
environment: любая проверка со своей фикстурой — тест, канарейка прибора, разовый замер «до/после», аргумент замера
circumstances: настоящая форма существует в дереве и добывается одним поиском, но пишется по памяти, потому что «очевидна»
purpose: чтобы зелёный результат проверки означал состояние мира, а не согласие фикстуры с собой
method: форму входа ДОБЫВАТЬ из носителя (поиск по дереву, git show прежней редакции, копирование живой строки), рамку прогона собирать полной; при совпадении «до» и «после» первым делом подозревать рамку, а не отсутствие эффекта
tags: [fixture, canary, verification-frame, false-green, measurement-validity]

need: "improve_quality"
urgency: "when_relevant"
availability: "unique"

related: [pattern-verification-frame-mismatch, pattern-marker-matches-form-not-role, pattern-subject-of-measurement-mismatch]
edges:
  - specializes: pattern-verification-frame-mismatch
  - similar_to: pattern-marker-matches-form-not-role
origin: solo
preceded_artifact: "no"
provenance_log:
  - date: 2026-09-07
    kind: reinforced
    reason: "фикстура битого байта взята из мира верно (русский текст через head -c), и именно поэтому положительный контроль вскрыл, что последствие плавает: сочинённая фикстура этого бы не показала"
    session: ""
  - date: 2026-09-10
    kind: reinforced
    reason: "род события внесён в реестр сродов хода: форма имени взята по памяти, а соседи по списку (ci-red, revert, resurrected) там не значатся ни один"
    session: ""
  - date: 2026-09-10
    kind: reinforced
    reason: "команда «Проверки» D388 писалась в файл одним экранированием, а проверялась терминальной версией с другим: в прибор уходило echo  без формы; носитель, держащий метку, не прогонялся как есть"
    session: ""
  - date: 2026-09-12
    kind: reinforced
    reason: "дешёвый признак «до и после одинаково → подозревай рамку» сработал как детектор; фикстура гейта из ЗАКРЫТЫХ пунктов не рождала предмет (unchecked наполняется только для открытых)"
    trigger_case: case-2026-09-11-check-read-before-it-was-shown-to-see.md
    session: ""
  - date: 2026-09-12
    kind: reinforced
    reason: "«Проверка» пункта D356 подавала форму без полей харнесса и краснела 4 дня после починки"
    trigger_case: case-2026-09-12-item-check-held-a-fabricated-form-and-stayed-red-after-the-fix.md
    session: ""
  - date: 2026-09-12
    kind: reinforced
    reason: "фикстура test_knowledge_coverage: name = стем файла; в мире name — заголовок, самоупоминание путём в другом поле (2 из 58); форма исправлена по замеру после красной ноги"
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "времена фикстуры «сегодня 08:00–10:00 UTC» при 04:44 UTC текущего времени: соседи из будущего честно отсеяны окном и mtime; даты фикстур — во вчера либо от date (13 сентября 2026)"
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "фикстуры ног T7-T10 собраны из ПЯТИ форм живой базы (поточные пары, комментарий внутри блока, хвостовой комментарий, запятые в кавычках, экранированная кавычка) — придуманные формы дали бы зелёный тест при 73 расхождениях"
    session: ""
  - date: 2026-09-14
    kind: reinforced
    reason: "нога потолка обрезки взяла стража с сообщением 326 знаков при потолке 400 — мутант не покрасил; длинное сообщение было у другого, 564"
    session: ""
  - date: 2026-09-14
    kind: reinforced
    reason: "третий носитель за день: фикстура публикации копировала библиотеку без объявленного ею соседа, и исход теста повис на состоянии хоста"
    session: ""
  - date: 2026-09-15
    kind: reinforced
    reason: "песочница снимка собрана без .git — приборы судили пустой универсум; фикстура свидетеля публикатора без hooks/tests уронила новый гейт"
    trigger_case: case-2026-09-15-absent-by-design-read-as-a-defect
    session: ""
  - date: 2026-09-17
    kind: reinforced
    reason: "две фикстуры построены под подстрочный признак: форма фикстуры signal-precision в корпусе 0 раз, фикстура phantom изображала маркер не в начале при настоящем предмете 5 случаев"
    trigger_case: case-2026-09-17-declared-limit-is-a-hypothesis-too.md
    session: ""
  - date: 2026-09-18
    kind: reinforced
    reason: "18.09.2026: три фикстуры подряд изображали мир формой, которой харнесс не производит — имя agent-*.jsonl вместо поля agent_id, плоская раскладка вместо <sid>/subagents/, текст последним вместо StructuredOutput у агента волны"
    session: ""
  - date: 2026-09-22
    kind: reinforced
    reason: "зелёная сторона D474 сперва писала строку журнала САМА — предъявляла зелень поддельного следа; образец взят у соседней фикстуры, которая прогоняет прибор"
    session: ""
  - date: 2026-10-10
    kind: reinforced
    reason: "ProjectA R45: 105 тестовых файлов строили вход сервиса, который роут отбил бы (несохранённый номер «Себе»)"
    trigger_case: case-2026-10-10-rule-only-at-trust-boundary-fixtures-pin-unreachable-state.md
    session: ""
  - date: 2026-10-11
    kind: reinforced
    reason: "11.10.2026 D527: фикстуры test_deny_mark_lib держали голую форму отказа (форма корпуса 16.09); с 26.09 харнесс пишет 'PreToolUse:<инструмент> hook error: ⛔ …', выражение не узнало ≈370 отказов за 15 дней. Черновик case-2026-10-11-corpus-measured-signature-silently-expired"
    session: ""
  - date: 2026-10-12
    kind: reinforced
    reason: "B456: способ починки из фикстуры скептика опровергнут замером прода до правки"
    trigger_case: case-2026-10-12-fix-method-from-fixture-refuted-by-prod-shape.md
    session: ""
  - date: 2026-10-21
    kind: reinforced
    reason: "blalb: 6 примеров тестов раскладки взяты по памяти и неверны (клавиша o=щ, z — польское слово, косячок в uk)"
    trigger_case: case-2026-10-21-test-examples-from-memory-wrong.md
    session: ""
  - date: 2026-10-22
    kind: reinforced
    reason: "D1027 22.10: ноги T11 подавали строки носителей без выравнивания колонки роли, которого прибор не печатать не умеет; первая редакция слила носителей одной роли, опровергнута финальным скептиком; ноги T12 взяты с живой формы"
    session: ""
  - date: 2026-10-28
    kind: reinforced
    reason: "проба пути оболочки зелена только с поднятым потолком диспетчера (D1158)"
    trigger_case: case-2026-10-28-exemption-leg-exited-on-prefilter.md
    session: ""
  - date: 2026-10-28
    kind: reinforced
    reason: "фикстуры записей user без type держались на узких копиях признака; единый владелец уронил 17 тестов (D1150, D1153)"
    trigger_case: case-2026-10-27-fixture-off-world-held-by-scattered-copies.md
    session: ""
  - date: 2026-10-30
    kind: reinforced
    reason: "compile 25: нога под вход скептика набрана не буквально (K80 D1042, f06 D1075) — не различала"
    trigger_case: case-2026-10-30-leg-for-reported-input-not-verbatim
    session: ""
  - date: 2026-11-01
    kind: reinforced
    reason: "D1156: фикстура rec_user теста стража поправок без message.role — после перехода на owner_reply нога T6d молчала от формы, а не от флага; в мире role user у 99 255 записей из 99 255"
    session: ""
  - date: 2026-11-03
    kind: reinforced
    reason: "B545 2026-11-03: заглушка wFirma в тестах отвечала на негодный токен HTTP 200 + AUTH; замер мира — HTTP 401 + {status:{code:AUTH}}; заглушки переведены на измеренную форму, атака «401 без кода» закрыта замером, а не рассуждением"
    session: ""
  - date: 2026-11-06
    kind: reinforced
    reason: "D1220, H1 скептика opus: в пробе присваивания стояли в начале строки и после «;», а в мире основная форма — «cd X && S=…» (127 отказов); знание относилось к делу и не применено при записи пробы"
    session: ""
  - date: 2026-11-07
    kind: reinforced
    reason: "Swift в карте, скептик opus по 9dc31762 (H1 инкремент ≠ сборка; H2 фикстура XCTest против #expect мира; M1 копия библиотеки исполнителя не сверена): знание было применимо и не применено"
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 12.11: селекторы e2e-спеки написаны по догадке о компонентах — красные прогоны чинили спеку"
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 13.11: селекторы проверки глазами по памяти об AntD (.ant-modal-content, calc() во встроенном стиле, первая .anticon-bell) — три захода"
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 15.11: .ant-message-notice по памяти, в установленной версии элемента нет"
    trigger_case: case-2026-11-15-ui-library-selector-written-from-memory-again.md
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 16.11: селектор .ant-modal .ant-modal-content .ant-modal-body — в AntD 6 у тела нет такого предка"
    trigger_case: case-2026-11-16-css-override-selector-by-memory-antd-dom.md
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 14.11: прибор искал лаунчер по тексту style «position: fixed», SSR пишет без пробела"
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 14.11: узкие ширины мерились сужением страницы, загруженной на 1920, а телефон грузит её сразу узкой"
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 14.11: радиус размытия 8 px подобран на снимках 390 px с мелким шрифтом — на 1440 имя и сумма читались"
    session: ""
  - date: 2026-11-18
    kind: reinforced
    reason: "D1320: подделка mkdir в свидетеле построена по наблюдённой гонке uutils, а не по замеру всех свойств — брала -p и создавала родителя, которого uutils не создаёт; тупик L2b был артефактом подделки"
    session: ""
  - date: 2026-11-18
    kind: reinforced
    reason: "D1316: повтор CI-only красного в образе по памяти (debian, ubuntu:24.04), а раннер — ubuntu-26.04 с uutils; рамка повтора не взята из журнала прогона"
    trigger_case: case-2026-11-18-ci-only-red-reproduced-in-wrong-runner-image.md
    session: ""
  - date: 2026-11-21
    kind: reinforced
    reason: "21.11.2026, D1346: проба писала служебную запись питоном с пробелом после двоеточия, клиент пишет слитно; признак, взятый у мира (слитная форма), пробу не проходил, а признак «под пробу» прошёл бы мимо мира — сделан устойчивым к обеим формам, свидетель подаёт обе"
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "22.11.2026: фикстура теста on-server.sh писала свой .gitignore с .env.*, настоящий проекта его не знает — .env.test уехал бы, тест зелёный"
    trigger_case: case-2026-11-22-secret-boundary-delegated-to-gitignore.md
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "/compile 22.11.2026, принято владельцем: форма интерфейса по памяти при сохранённом снимке страницы (error-context.md)"
    trigger_case: case-2026-11-18-antd-sibling-selector-from-memory-third-time.md
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "/compile 22.11.2026, принято владельцем: форма интерфейса по памяти при сохранённом снимке страницы (error-context.md)"
    trigger_case: case-2026-11-19-css-override-written-without-measuring-library-specificity.md
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "/compile 22.11.2026, принято владельцем: форма интерфейса по памяти при сохранённом снимке страницы (error-context.md)"
    trigger_case: case-2026-11-20-spec-locator-text-taken-from-code-not-page.md
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "/compile 22.11.2026, принято владельцем: форма интерфейса по памяти при сохранённом снимке страницы (error-context.md)"
    trigger_case: case-2026-11-20-probe-opener-guessed-instead-of-reading-page-snapshot.md
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "Мод context-weather: тест строки на числах макета (окно 200k, оба лимита) зелёный, вживую окно 1M — график слился в плашку, «5ч» не показан; case-2026-11-22-ui-verified-on-mockup-data-not-live"
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "Тест context-weather: шаблон /%$/ по памяти не взял «36% · 357k/1M»; case-2026-11-22-test-matcher-written-from-memory-of-output"
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "D1359 22.11.2026: первая редакция взяла форму обрезанного вывода из одного описанного случая (tail -8), скептик нашёл в корпусе ProjectA 114 из 381 отчётов без единого разобранного падения (tail -3); второе — имя каталога снимка пробы бралось по памяти (основа имени спеки), а Playwright называет его по пути спеки, что видно в настоящем снимке"
    session: ""
instrument_verdict: inexpressible   # верность формы фикстуры писателю мира не видна в тексте записи: кавычки, разделитель, поле те же у верной фикстуры, отличие только в происхождении
instrument_assessed: 2026-11-10
---

Вход проверки — фикстуру, канарейку, аргумент замера — ДОБЫВАЙ ИЗ НОСИТЕЛЯ, а не сочиняй по
памяти о форме. Способ называется: поиск по дереву настоящих носителей, `git show` прежней
редакции, копирование живой строки. Рамка прогона собирается полной — файл кладётся туда, где
рядом лежат его библиотеки, иначе он выйдет раньше, чем дойдёт до предмета.

**Why:** два случая за пять дней, устройство одно. 2 сентября 2026 фикстура задала вход в
форме, которой настоящий писатель никогда не пишет, и тест доказывал защиту, не существующую
в бою. 7 сентября то же повторилось ЧЕТЫРЕЖДЫ за одну сессию: фикстура печатала `.` там, где
прибор разбирает `·` (замер дал одинаковый ноль до и после починки); историческая редакция
хука запущена без соседних библиотек и вышла на пустом корне, не дойдя до дефекта; канарейка
написана в jq-форме с экранированными кавычками, где подстроки `"Stop"` нет вовсе — признак
был исправен, лжива фикстура; транскрипт-фикстура не содержала `tool_use`, и исправный
писатель выглядел сломанным. Каждый раз проверка была зелено-пустой либо краснела не по делу.

**How to apply:** в момент, когда рука тянется набрать форму по памяти — «там же обычный
путь», «там обычные кавычки», «хватит одной строки». Сначала добудь строку из носителя.
Отдельный признак промаха, дешёвый и надёжный: **«до» и «после» дали ОДИНАКОВОЕ число** — это
не доказательство отсутствия эффекта, а первое подозрение на негодную рамку.

**Limitations:** не относится к фикстурам, у которых носителя ещё нет (проверка пишется до
механизма) — там форму задаёт сама проверка, и сверить её надо с первым же настоящим
носителем. Не относится и к смежному классу, где фикстура верна, а универсум проверки
включает саму проверку: у него другой разделитель и другая починка.

**Проявление 2026-11-16 (ProjectA, B668).** Заготовка теста слияния завела пользователя полем `password` по памяти — в схеме
`passwordHash`; контрольный тест упал вместе с атакой, `PrismaClientValidationError` вместо различающего красного. Форма взята
из соседнего теста того же сервиса (`b611-duplicates-safe-means-merge-accepts.test.ts:18`) — после этого красный только у атаки.

**Проявление 2026-11-18…20 (ProjectA, AntD 6, четыре кейса).** Форма интерфейса взята по памяти, из кода или угадана:
селектор соседа меню (`.ant-menu-inline + div` — «третий раз»), сила CSS-правила (`.ant-card-head-title` 0,1,0 против
`:where(хеш).ant-card .ant-card-head-title` 0,2,0), текст подписи из комментария кода, способ открыть карточку. В двух
случаях ответ уже лежал в снимке DOM упавшего прогона (`error-context.md`) с первой неудачи. Признак для этого рода:
упал локатор — прочитать `error-context.md` до второй попытки; CSS-правило не подействовало — сперва вычисленные стили
и выигравшее правило библиотеки. Подсказки «прочитай снимок» нет ни в хуках, ни в ProjectA (поиск `error-context` 22.11 —
0 совпадений): текстом это держится со второй-третьей попытки.
