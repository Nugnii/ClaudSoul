---
name: У факта уже есть владелец в дереве, и его не спросили
description: "Задача решается СВОЕЙ реализацией там, где в дереве уже лежит владелец того же факта — разбор, индекс, реестр, рамка. Копия пишется не по незнанию: указатель на владельца бывает записан прямо в файле, который автор читал. Итог один — два владельца одного факта, расходящиеся молча, и копия ломается там, где оригинал держит. Измерено на четырёх случаях; в последнем противник пробил копию шестью способами, из которых оригинал не пропускал ни одного"
type: pattern
outcome: error
confidence: 4
impact: 5
intensity: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-22
source_cases:
  - case-2026-11-22-waiver-verdict-line-form-not-taken-from-archiver.md
  - case-2026-11-22-output-format-rule-built-from-one-line-description.md
  - case-2026-11-21-guard-borrowed-unknown-from-advisory-parser.md
  - case-2026-11-08-new-instrument-rebuilt-owner-lock-and-contract.md
  - case-2026-11-07-owner-asked-with-own-number.md
  - case-2026-11-04-failure-mechanism-inferred-from-symptom-not-read.md
  - case-2026-10-31-test-expectation-from-own-model-of-guard.md
  - case-2026-10-30-rule-chosen-against-declared-contract.md
  - case-2026-10-25-new-consumer-of-journal-exposed-bypassing-writer.md
  - case-2026-10-26-widening-the-boundary-owner-blinds-readers-inside-it.md
  - case-2026-10-21-guard-rebuilt-the-commit-from-command-text.md
  - case-2026-10-20-own-busy-lock-beside-state-lock-lib.md
  - case-2026-10-20-code-comment-asserted-prod-state.md
  - case-2026-10-20-four-copies-of-temp-root-rule-beside-its-owner.md
  - case-2026-10-11-item-from-code-reading-contradicted-a-test-pinned-contract.md
  - case-2026-10-11-git-state-assumed-after-chained-command-three-slips.md
  - case-2026-09-09-instrument-wrote-its-own-copy-of-three-owned-rules.md
  - case-2026-09-13-edges-for-the-answer-already-lay-in-the-index.md
  - case-2026-09-15-i-built-a-second-frame-while-the-first-lay-in-the-tree.md
  - case-2026-09-27-fixer-brief-made-the-attack-the-unit-of-repair.md
  - case-2026-10-05-format-taken-by-guess-while-caller-knew-it.md
  - case-2026-10-23-record-predicate-placed-at-the-owner.md
  - case-2026-10-26-state-doc-edit-deferred-to-another-session.md
  - case-2026-11-03-shown-text-produced-after-last-check.md
  - case-2026-11-12-second-copy-of-identity-rules-drifts.md
  - case-2026-11-19-share-tag-updated-sibling-tag-not.md
  - case-2026-11-20-batch-triage-by-consequence-before-item.md
source_session: ""
status: active

promotion_tier: 2
scope: universal
origin_domain: agent_design

domain: [agent_design, architecture, tooling, verification]
situation: "нужно ответить на вопрос о мире — что исполнит оболочка, какие рёбра у узла, какова рамка прогона, какой путь тронет команда — и ответ пишется своими средствами прямо в потребителе"
trigger: "в задаче появляется слово «разобрать», «посчитать», «собрать рамку», «определить» — и рука тянется к регулярке или циклу вместо вопроса «кто в дереве уже это знает»"
stakes: "копия отвечает ПОХОЖЕ, поэтому расхождение не видно на прогоне: тесты зелёные у обоих. Цена всплывает у потребителя-отказчика либо на атаке — и тогда правка сносит не копию, а доверие к механизму, который на ней стоял"
actors: [agent]
environment: "ClaudSoul; проявления — CMD_BARE в git-add-sweep-guard против hooks/lib/write_targets.py, своя рамка прогона против scripts/measure-linux-parity.sh, свой счётчик корней против scripts/root-map.py --count, свой обход дерева против .claude-docs/dep-index.tsv"
circumstances: "указатель на владельца чаще всего УЖЕ прочитан: в двух случаях из четырёх правило «разбирать надо разбором, а не вырезанием» стояло в том же файле, куда автор смотрел минутой раньше. Копия пишется в спешке починки, когда предметом переживается симптом, а не устройство"
purpose: "отвечать на факт одним владельцем, чтобы расхождение было невозможно, а не маловероятно"
method: "перед первой строкой новой логики назвать вслух: какой механизм дерева уже отвечает на этот вопрос, и что с ним делаем — зовём, расширяем режимом, либо оба нужны и названо, чем предметы различаются"

need: "правка, которая переживёт атаку и вторую реализацию"
urgency: high
availability: "поиск занимает минуту: git grep по предмету, чтение шапки ближайшей библиотеки, dep-index.py --impact"

related: [pattern-new-instrument-carries-its-own-defect, pattern-class-closure-without-a-carrier-count]
edges:
  - similar_to: pattern-new-instrument-carries-its-own-defect
  - caused_by: case-2026-09-13-mechanized-rules-held-text-rules-did-not
provenance_log:
  - date: 2026-09-20
    kind: reinforced
    reason: "20 сентября 2026: три провала набора подряд от одного корня — форма подачи строки в grep (владелец test_assert_no_sigpipe.sh), форма строк договора инструмента (владелец test_instrument_contract.sh), производные числа (владельцы count-stats.sh и docs-refresh-claims.sh). Каждый раз форма бралась по привычке, а у неё был владелец, называющий её дословно"
    session: ""
  - date: 2026-09-20
    kind: reinforced
    reason: "20 сентября 2026: канал вердикта выбран по привычке (stdout), а владелец вопроса — штатный свидетель механизма — читает очередь pending-alerts.txt и объясняет почему. Свидетель был зелен при любом поведении предмета"
    session: ""
  - date: 2026-09-22
    kind: reinforced
    reason: "перечень неразрешённых спросил у прибора, кандидатов у индекса зависимостей, замок у state-lock-lib — ни одного факта не выводил заново"
    session: ""
  - date: 2026-09-23
    kind: reinforced
    reason: "расчёт срока теста был ЗАПЕРТ функцией внутри run_all.sh: владелец есть, но второму потребителю недоступен — прибор поставил свою константу 30 с и записывал в «не уложился» дорогие по природе тесты"
    session: ""
  - date: 2026-09-24
    kind: reinforced
    reason: "знание инжектилось весь ход, и я всё равно вписал две строки РУКОЙ в таблицу, которую генерирует regen-readme-skills.sh; страж автотаблиц отбил коммит — разрыв «знание → действие», а не отсутствие знания"
    session: ""
  - date: 2026-09-27
    kind: reinforced
    reason: "2026-09-27 ProjectA: у метода «корень→карта→регрессия→починка» был владелец в дереве — /adversary (ClaudSoul) и ROOTS.md проекта; оркестровка собрана с нуля, их не спросили; хук поднимал это знание много раз за сессию"
    trigger_case: case-2026-09-27-fixer-brief-made-the-attack-the-unit-of-repair.md
    session: ""
  - date: 2026-10-03
    kind: reinforced
    reason: "D506/D508: прежде своей обвязки сверки спросил владельца факта — scripts/signal-precision-corpus.py полного прогона стража не делает, своя обвязка оправдана; починка D508 взяла форму ${CLAUDSOUL_STATE_DIR:-${STATE_DIR:-…}}, которой уже держались три файла дерева"
    session: ""
  - date: 2026-10-05
    kind: reinforced
    reason: "2026-10-05 ProjectA: формат вывода Workflow и тело SendPulse get-list взяты по догадке, хотя владельцы факта (первые строки вывода, комментарий listDeals) лежали в дереве; 422 от боевого API"
    trigger_case: case-2026-10-05-format-taken-by-guess-while-caller-knew-it.md
    session: ""
  - date: 2026-10-11
    kind: reinforced
    reason: "SHA main в карточке корня R74 вписан по памяти, а не от git (rev-parse)"
    trigger_case: case-2026-10-11-git-state-assumed-after-chained-command-three-slips.md
    session: ""
  - date: 2026-10-11
    kind: reinforced
    reason: "B282: дефект уже был корнем R17, а «отметка остаётся» — контрактом R16 в тесте; пункт их не назвал"
    trigger_case: case-2026-10-11-item-from-code-reading-contradicted-a-test-pinned-contract.md
    session: ""
  - date: 2026-10-19
    kind: reinforced
    reason: "Biznes-sovetnik 19.10: срок PIT-11 верно стоял в 60-buhgalteriya/politika-vedeniya.md:79-80 (31 января в urząd, конец февраля подрядчикам), утренняя «поправка» его не открыла"
    session: ""
  - date: 2026-10-20
    kind: reinforced
    reason: "D1011→D1013: четыре копии предиката «временный корень» при живом _rc_path_is_private; найден поиском по литералу корня"
    trigger_case: case-2026-10-20-four-copies-of-temp-root-rule-beside-its-owner.md
    session: ""
  - date: 2026-10-20
    kind: reinforced
    reason: "B501: достижимость класса оценена по комментарию о проде (копия), а владелец факта — настройка прода sendpulse_payout_mirror_enabled=true"
    trigger_case: case-2026-10-20-code-comment-asserted-prod-state.md
    session: ""
  - date: 2026-10-20
    kind: reinforced
    reason: "D1014: самописная занятость рядом с hooks/state-lock-lib.sh — два круга скептика на дефекты, решённые в D500"
    trigger_case: case-2026-10-20-own-busy-lock-beside-state-lock-lib.md
    session: ""
  - date: 2026-10-21
    kind: reinforced
    reason: "страж прямого коммита переписал правила bash и git вместо ловушки git commit-msg: три круга скептика, новая форма в каждом"
    trigger_case: case-2026-10-21-guard-rebuilt-the-commit-from-command-text.md
    session: ""
  - date: 2026-10-21
    kind: reinforced
    reason: "D1021 (7ac272b1): суд прямого коммита перенесён к владельцу фактов — git, ловушка commit-msg видит готовые сообщение и индекс; пять редакций разбора текста команды удалены"
    session: ""
  - date: 2026-10-22
    kind: reinforced
    reason: "D1022: репозиторий, индекс и сообщение коммита есть готовыми у git (ловушки), а четыре стража восстанавливали их из текста команды — перенос к владельцу закрыл и исходный дефект, и три брата"
    session: ""
  - date: 2026-10-23
    kind: reinforced
    reason: "роль «запись» заведена у владельца соседних ролей, цель heredoc прочитана у ds_heredoc_writes, прибор спросил владельцев одним вызовом — второй копии правила не появилось"
    trigger_case: case-2026-10-23-record-predicate-placed-at-the-owner.md
    session: ""
  - date: 2026-10-25
    kind: reinforced
    reason: "/compile 25.10: D1087 — предикат построен на готовом git_calls, поиск по устройству свёл четыре копии факта в одну"
    session: ""
  - date: 2026-10-25
    kind: reinforced
    reason: "D1098: инвариант D27 переписан сперва вторым владельцем факта (история git); инжект знания развернул на владельца carry_diverged (lib/carry-log.sh) до коммита — у первой редакции был ложный «✗» на переносе из незакоммиченного дерева"
    session: ""
  - date: 2026-10-26
    kind: reinforced
    reason: "/save отложил правку CLAUDE.md на «другую сессию», не спросив git log"
    trigger_case: case-2026-10-26-state-doc-edit-deferred-to-another-session
    session: ""
  - date: 2026-10-26
    kind: reinforced
    reason: "D1139: первая редакция команды исхода решала «исход принят» сама — по наличию строки manual- после якоря хода, — а у факта есть владелец, сверка стража rc_record_verdict; нога D1106 (подделка мимо команды) покраснела, вторая редакция спрашивает владельца"
    session: ""
  - date: 2026-10-27
    kind: reinforced
    reason: "точка последней речи искалась scan_back мимо тёплой метки turn_offset — владелец факта «тёплая точка» (D498) не спрошен, +2,3 с на вызов"
    trigger_case: case-2026-10-26-widening-the-boundary-owner-blinds-readers-inside-it.md
    session: ""
  - date: 2026-10-28
    kind: reinforced
    reason: "переход на журнал переноса верен, но install.sh клал META мимо журнала — владелец факта знал не всё (ClaudSoul D1098/D1099, 25.10)"
    trigger_case: case-2026-10-25-new-consumer-of-journal-exposed-bypassing-writer.md
    session: ""
  - date: 2026-10-30
    kind: reinforced
    reason: "D1073 два круга: правило «вход → ключ» выбрано без вопроса к владельцу ключа (вход объявлен «от корня», ключи учёта — имена git) — оба раза регресс на объявленном входе"
    trigger_case: case-2026-10-30-rule-chosen-against-declared-contract.md
    session: ""
  - date: 2026-11-01
    kind: reinforced
    reason: "D1151, пять кругов скептиков: проба probe_D1151 сама перечисляла виды повода и формы записи, а владельцы этих множеств — у стража (RC_KINDS_RE в root-cause-lib.sh:144, признаки записи five-whys-gate.sh:894-956); каждый круг скептик находил вид или форму вне перечня; корень записан в D1206 (R3)"
    session: ""
  - date: 2026-11-01
    kind: reinforced
    reason: "D1160, 1 ноября 2026, круг 2 скептика opus по 6ee336f8: хозяина тела heredoc я написал своим выражением по сырому тексту рядом с владельцем позиции команды _cmd_pos — регресс на 2>&1, $(…), <(…) и обёртках с ключами; знание стояло в инжекте этого хода и не применено при правке"
    session: ""
  - date: 2026-11-03
    kind: reinforced
    reason: "совет R4 «ответьте сразу» выведен из вопроса чата, практику («предупредить заранее») знал Костя"
    trigger_case: case-2026-11-03-shown-text-produced-after-last-check
    session: ""
  - date: 2026-11-07
    kind: reinforced
    reason: "Swift в карте, скептик opus по 9dc31762 (H1 инкремент ≠ сборка; H2 фикстура XCTest против #expect мира; M1 копия библиотеки исполнителя не сверена): знание было применимо и не применено"
    session: ""
  - date: 2026-11-08
    kind: reinforced
    reason: "D1249, 8 ноября 2026: прибор архивных «Проверок» строил свой замок mkdir и выбор ☑/⊘, хотя замок с владельцем (state-lock-lib) и договор исполнителя (только ☑, probe_D1196) уже были в дереве — скептик opus H1, M1"
    session: ""
  - date: 2026-11-08
    kind: reinforced
    reason: "8 ноября 2026 вечер: D1253 — свой проход тел подстановок при живом _substs (снят до коммита); D1250 — граница хода без вопроса к with_final D1210, владельцу факта «файл не догнал итог» (скептик opus H1)"
    session: ""
  - date: 2026-11-11
    kind: reinforced
    reason: "D1292: outcome.sh держал свою копию правила «повод закрыт» вместо вопроса стражу; D1243 расширил окно стража, копию не тронул — «показалось» легло на закрытую поправку (ProjectA 10.11.2026)"
    session: ""
  - date: 2026-11-12
    kind: reinforced
    reason: "B606: поиск дублей пересказывал правила тождества рядом с mergeCounterparties/isPersonRecord — три редакции по расхождению"
    trigger_case: case-2026-11-12-second-copy-of-identity-rules-drifts.md
    session: ""
  - date: 2026-11-16
    kind: reinforced
    reason: "D1299 v3/v4: факт «какие файлы изменила команда» взят у владельца — bashEditDiff клиента — вместо заместителя (время файла); снял M1–M3 скептика по 99d31c91"
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 14.11 (B625): правило сетки align-items:start введено при правиле того же гайда «карточки ряда — одной высоты»; подпись места лаунчера в i18n не тронута"
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ProjectA 14.11 (B629): ключ порядка «по номеру» по контейнеру, а номер на карточке — по карточке; разошлись на смешанной доске"
    session: ""
  - date: 2026-11-17
    kind: reinforced
    reason: "ClaudSoul 15.11: правило «пункт долга называет откат» строчным литералом у двух потребителей — заголовок «Откат D474» не видел ни один"
    session: ""
  - date: 2026-11-18
    kind: reinforced
    reason: "18.11.2026, ClaudSoul D1323: страж правил судил запись своим регулярным выражением, хотя владелец лексики write_targets.py отвечал верно на 18 из 19 форм генератора; починка — спросить владельца, 61 провал → 0"
    session: ""
  - date: 2026-11-19
    kind: reinforced
    reason: "19.11.2026 пульт, карточка Илоны: метка ЛТЛ не сверена с fakty-i-doli/блоком «Компании», хотя метку ProjectA по нему исправил"
    trigger_case: case-2026-11-19-share-tag-updated-sibling-tag-not.md
    session: ""
  - date: 2026-11-20
    kind: reinforced
    reason: "D1341, 20 ноября 2026: разбор строк документации питона написан своим, владелец py_prose_rows найден в дереве на втором заходе и поставлен вместо копии"
    trigger_case: case-2026-11-20-batch-triage-by-consequence-before-item
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "D1356/D1358 22.11.2026: формат печати снимка взят из пересказа соседней сессии, у автора формата не спрошен"
    trigger_case: case-2026-11-22-output-format-rule-built-from-one-line-description.md
    session: ""
  - date: 2026-11-22
    kind: reinforced
    reason: "22.11.2026 ClaudSoul: три ⊘ (D408, D307, D310) записаны строкой «**Вердикт (дата, решение).**» по образцу соседних «**Показание (дата).**», а владелец формы — scripts/backlog-archive.sh:419 — ищет подстроку «**Вердикт.**»; архиватор отказал унести их 14 запусков подряд, пока не спросили владельца"
    session: ""
instrument_verdict: inexpressible   # own-frame-notice ловит одну форму — heredoc скрипта замера в scratchpad (34 из 40 582 вызовов); своя регулярка, копия правила, перезапись по устаревшей записи от законной работы по входу вызова не отличить
instrument_assessed: 2026-11-10
---

# У факта уже есть владелец в дереве, и его не спросили

## Признак

Пишется логика, отвечающая на вопрос **о мире**, а не о задаче: что исполнит оболочка,
какие у узла рёбра, какова рамка прогона, сколько чего в дереве, какой путь тронет команда.
Такие вопросы почти никогда не бывают новыми — у них есть владелец.

## Чем это НЕ является

Это не запрет писать код. Предмет узок: **факт о мире** против **логики задачи**. Своя
логика обработки ответа — нормально; свой способ ДОБЫТЬ ответ, когда добытчик уже есть, —
это и есть признак.

## Почему указатель не помогает сам по себе

В двух случаях из четырёх правило, называющее владельца, стояло в файле, который автор
читал минутой раньше (`command-scope-lib.sh:319` — «разбирать кавычки надо РАЗБОРОМ, а не
вырезанием»). Это правило уровня 1, и замер проекта по ним однозначен: правила с механизмом
исполнялись 7 раз из 7, правила текстом нарушены трижды.

## Что делать

Перед первой строкой новой логики назвать ВСЛУХ три вещи:

1. какой механизм дерева уже отвечает на этот вопрос (`git grep` по предмету, шапка соседней
   библиотеки, `dep-index.py --impact`);
2. судьба найденного: **зовём** · **расширяем режимом у владельца** · **оба нужны, и названо,
   чем предметы различаются**;
3. если владельца нет — сказать это явно, а не умолчать: умолчание неотличимо от «не смотрел».

## Цена, измеренная 20 сентября 2026

Своя копия разбора грамматики оболочки в `git-add-sweep-guard` была пробита противником
**шестью** способами за один прогон — тремя в сторону молчания на настоящем захвате, тремя
в сторону помехи законной работе. Владелец (`hooks/lib/write_targets.py`) не пропускал
**ни одного** из шести: метку heredoc в кавычках и с цифрой он узнаёт, терминатор ищет
настоящим совпадением, экранированную кавычку ест `shlex`. Седьмую форму — heredoc с
перенаправлением после метки — не держал и владелец (50 мест из 897 в дереве), и она
починена **у него**, то есть разом для всех потребителей.

## Предел паттерна

Владелец бывает УЖЕ своего предмета: `--targets` отвечает «что вызов создаёт», а не «что
правит», и на шести реальных формах правки видит две. Позвать владельца — не то же, что
получить нужный ответ: у ответа проверяется ПРЕДМЕТ, а не факт вызова. Расширять владельца
можно лишь с измеренной ценой: расширение словаря на `sed -i` и `tee` уронило свидетеля
потребителя-отказчика с 27/27 до 24/27 и было откачено целиком.

Второй предел — полнота владельца. Владелец знает только то, что ему сообщают ВСЕ дороги к факту: журнал переноса,
который пишет `carry`, не знает о файле, положенном установщиком через голый `cp` (ClaudSoul, D1098 → D1099, 25 октября
2026: 177 записей install.sh в журнале, ни одной о META — `case-2026-10-25-new-consumer-of-journal-exposed-bypassing-writer`).
Поэтому переход прибора на владельца начинается с перечня писателей факта поиском по носителям; дорога мимо владельца
чинится в дороге, а не исключением в приборе.
