---
type: pattern
confidence: 4
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-23
source_cases: [case-2026-06-21-guard-scope-seed-false-green.md, case-2026-06-21-guard-scope-doc-links-historical.md, "ClaudSoul: хук PREDICTION→BACKWARD сработал на «не совсем» внутри tool-result (текст канона H3), не в речи собеседника — детектор скан не той области (2026-06-21, compile-2026-06-21-update-guard-scope-detector-text-source)", "ClaudSoul install-drift обратное направление (2026-07-25, commit 1e7dbd61): страж дрейфа source↔copy проверял лишь одно направление; 9 рабочих зарегистрированных хуков без копии в репозитории копились молча 8 релизов — silent guards не сигналят об отсутствии"]
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
    trigger_case: /Users/user/.claude/global-lessons/case-2026-07-31-check-stricter-than-cited-mechanism.md
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
fragile: false

related: [pattern-inside-out-blindness.md, principle-single-source-of-truth.md]
edges: [similar_to: pattern-inside-out-blindness.md, similar_to: principle-single-source-of-truth.md]
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
