---
name: "Guard-scope blindness — страж слеп к границе собственного покрытия"
description: "Между тем, что страж или тест ПРОВЕРЯЕТ, и тем, что его зелёный или красный статус ПОДРАЗУМЕВАЕТ, лежит необъявленный зазор — в нём прячется дрейф: статус читается шире области проверки, а щель между стражами разных областей закрывает лишь сверщик по дереву"
type: pattern
outcome: error
confidence: 4
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-13
source_cases: [case-2026-08-28-fix-moved-the-boundary-and-kept-the-key.md, case-2026-08-27-claimed-closure-vs-counted-closure.md, case-2026-06-21-guard-scope-seed-false-green.md, case-2026-06-21-guard-scope-doc-links-historical.md, "ClaudSoul: хук PREDICTION→BACKWARD сработал на «не совсем» внутри tool-result (текст канона H3), не в речи собеседника — детектор скан не той области (2026-06-21, compile-2026-06-21-update-guard-scope-detector-text-source)", "ClaudSoul install-drift обратное направление (2026-07-25, commit 1e7dbd61): страж дрейфа source↔copy проверял лишь одно направление; 9 рабочих зарегистрированных хуков без копии в репозитории копились молча 8 релизов — silent guards не сигналят об отсутствии", case-2026-08-08-session-throttle-downgrades-hook-to-text-rule.md, case-2026-08-22-cheap-prefilter-excludes-its-own-target.md, case-2026-09-13-tree-scanner-outside-the-selective-run.md, case-2026-09-13-two-guards-two-scopes-one-gap.md, case-2026-09-13-filtered-stream-attributes-rows-to-last-seen-header.md, case-2026-09-13-guard-registered-on-the-path-the-work-does-not-take.md]
source_session: ""
provenance_traced: low
status: active
preceded_artifact: yes   # знание существовало и было прочитано ДО постройки: шапка hook-input-lib.sh цитировала его с 21.06, и command-scope-lib.sh (v1.14.1) написан после того, как эта шапка была прочитана и класс опознан — а не наоборот

domain: [ci_cd, testing, knowledge_system]
situation: guard_design
trigger: implicit_guard_scope
stakes: false_confidence
actors: [system]
environment: ci_cd
circumstances: scope_not_declared
purpose: prevent_regression
method: scope_bounding

need: avoid_false_confidence
urgency: when_relevant
availability: has_alternatives

promotion_tier: 2
scope: universal
origin_domain: testing
effective_contradicted: 0.0
contradiction_log: []

modification_history: []
provenance_log:
  - date: 2026-07-28
    kind: reinforced
    reason: "install-drift обратное направление, 9 хуков вне репо (commit 1e7dbd61)"
  - date: 2026-07-29
    kind: reinforced
    reason: "trust-guard и playwright-cli-guard искали сигнатуру во всей строке команды, включая шаблоны grep и тела heredoc; playwright-guard дважды заблокировал реальную работу"
    trigger_case: v1.14.1 command-scope-lib
  - date: 2026-07-31
    kind: reinforced
    reason: "проверка соответствия трижды требовала больше, чем требует процитированный ею механизм — тот же класс в новом месте: сопоставление с собственным допущением вместо самого правила"
    trigger_case: case-2026-07-31-check-stricter-than-cited-mechanism.md
  - date: 2026-08-08
    kind: reinforced
    reason: "временное измерение scope: не какую область страж покрывает, а сколько РАЗ — throttle раз-за-сессию"
    trigger_case: case-2026-08-08-session-throttle-downgrades-hook-to-text-rule.md
  - date: 2026-08-22
    kind: reinforced
    reason: "дешёвый grep-предфильтр отсекал вход в точный разбор ровно для случая, ради которого написана новая ветка детекта — область сузила оптимизация стража"
    trigger_case: case-2026-08-22-cheap-prefilter-excludes-its-own-target.md
  - date: 2026-08-23
    kind: reinforced
    reason: "дефект «сигнатура ищется во всей строке команды» найден ещё у восьми стражей разом; матчер сведён в один источник, разбор переписан на сканер с состоянием"
    trigger_case: case-2026-08-23-narrow-fix-breaks-common-form.md
  - date: 2026-08-27
    kind: reinforced
    reason: "Третий инстанс, домен вне CI/тестов: backlog-recheck.sh перепроверяет ЗАКРЫТОЕ, его зелёный статус читался как «закрытое проверено», а единственный реально закрытый пункт был ему невидим — метка говорила «открыт». Граница покрытия стража не объявлена, зазор поймал собеседник."
    session: ""
  - date: 2026-08-28
    kind: reinforced
    reason: "Гейт «пяти почему»: граница покрытия дедупа не объявлена — ключ называл вид сигнала, и зелёные тесты после починки 27 августа читались как «повтор больше не уплывает», хотя внутри хода он уплывал по-прежнему."
    session: ""
  - date: 2026-09-01
    kind: reinforced
    reason: "rules-write-bypass судил по всему тексту команды: путь внутри строки Python и «>=» внутри awk в разных местах одной команды вместе давали отказ на чтении, трижды за сессию"
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "страж уровня 4 судит текст команды, тест — строку вызова grep; файл через python-heredoc и диапазон в переменной прошли между областями"
    trigger_case: case-2026-09-13-two-guards-two-scopes-one-gap.md
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "выборочный прогон выбирает тесты по правкам, сканер дерева связан со всем — дважды красный только в CI (beac9d6, 006a06d)"
    trigger_case: case-2026-09-13-tree-scanner-outside-the-selective-run.md
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "T5e: судились команды открытых пунктов, а поток приписывал соседу команды закрытых — зазор между проверяемым и подразумеваемым"
    trigger_case: case-2026-09-13-filtered-stream-attributes-rows-to-last-seen-header.md
    session: ""
  - date: 2026-09-13
    kind: reinforced
    reason: "хук карты висел на Edit|Write, правки шли Bash: 11 файлов, 0 срабатываний; класс — 9 стражей из 28, трое отказывают"
    session: ""
fragile: false

related: [pattern-inside-out-blindness.md, principle-single-source-of-truth.md]
edges: [similar_to: pattern-inside-out-blindness.md, similar_to: principle-single-source-of-truth.md]
detection_signals:
  where: "путь файла + содержимое правки (tool_input) на PreToolUse[Write]"
  form: "all_of: [ {\"tool_matches\": [\"Write\"]}, {\"file_path_regex\": \"(^|/)hooks/[^/]*(check|guard|gate|detector|tracker|reminder)[^/]*\\\\.sh$\"}, {\"none_of\": [ {\"tool_input_contains\": \"НЕ покрывает\"}, {\"tool_input_contains\": \"не покрывает\"}, {\"tool_input_contains\": \"КОНТРПРИМЕР\"}, {\"tool_input_contains\": \"Область:\"}, {\"tool_input_contains\": \"предел\"} ]} ] — то есть целиком пишется файл-страж, и в его тексте нет ни одной формы объявления границы покрытия"
  consequence: "Страж уходит в дерево с необъявленной границей: его зелёный статус и его молчание будут прочитаны как свойство шире того, что он проверил (ровно исход всех 12 подтверждений — от test_seed_integrity до backlog-recheck)."
  counterexample: "Точечный Edit регулярки в уже существующем страже (например правка сигнатуры в hooks/rules-write-bypass.sh) — не ловится по построению, tool_matches сужен до Write. Также вне признака: hooks/tests/test_*_check.sh (путь содержит второй слэш, [^/]* его не переходит) и hooks/lib/*.sh — у теста и библиотеки вопрос о границе другой."
  status: "ИЗМЕРЕНО 2026-09-06: 12 срабатываний на 7620 действий над файлами (0,157%), ложных 0 — все 12 суть стражи, записанные целиком без единой формы объявления границы. Контрпримеры подтверждены молчанием: ни одного hooks/tests/*, ни одного точечного Edit. Из 11 файлов в дереве у 5 граница появилась позже, у 6 не объявлена до сих пор. НО В УРОВЕНЬ 4 НЕ ПЕРЕВОДИТСЯ, и причина найдена этим же замером: сам признак построен ПЕРЕЧНЕМ словоформ (НЕ покрывает|не покрывает|КОНТРПРИМЕР|Область:|предел), то есть является носителем pattern-subject-checked-by-enumeration. Перечень неполон по построению: автор, объявивший границу иными словами, получит ЛОЖНЫЙ отказ. Условие снятия — инверсия перечня в правило (чем объявление границы БЫВАЕТ, а не какими словами)."
---

# Guard-scope blindness — страж слеп к границе собственного покрытия

**Наблюдение (2 инстанса за сессию):** между тем, что страж/тест **проверяет**, и
тем, что его зелёный/красный статус **подразумевают**, возникает необъявленный
зазор. В этом зазоре прячется дрейф.

- **Инстанс 1 (false-green):** `test_seed_integrity` зелёный → читался как «seed
  актуален», хотя проверял лишь интринсик-свойства, не content-drift.
- **Инстанс 2 (false-red):** `test_doc_links` сканировал append-логи → покраснел
  при легитимном удалении файла, на который ссылалась историческая запись.

Оба — один корень: **scope стража имплицитен**. Никто не задал явно «что этот
страж ДОЛЖЕН охранять» — поэтому его охват либо уже подразумеваемого (false-green),
либо шире намерения (false-red).

**Связь с другими знаниями:**
- `similar_to pattern-inside-out-blindness` — слепота к собственной границе/зазору.
- `similar_to principle-single-source-of-truth` — там страж над ОДНОЙ из N копий
  даёт ложную уверенность в синхронности всех; тот же зазор «покрытие vs
  подразумеваемое».

**How to apply (правило):**
1. При создании стража явно назови его **scope** — что он гарантирует и чего НЕ
   покрывает (в docstring/комментарии).
2. Если зелёный читается как более широкое свойство — закрой непокрытое отдельным
   механизмом ИЛИ явно задокументируй границу.
3. Ограничь область проверки **намерением**: не «все файлы», а «целевой класс».
   Append-логи и историческое — вне проверок «текущего состояния».

**When НЕ применять:** для стража, где scope тривиально полон и совпадает с
намерением (напр. «функция возвращает int») — явная декларация scope избыточна.
