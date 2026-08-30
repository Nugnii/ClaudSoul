---
name: Проверяй перед действием
description: Любое утверждение (пользователя, из памяти, из документации) — верифицируй в реальном коде перед тем как действовать
type: principle
outcome: error
confidence: 5
impact: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-16
source_cases:
  - case-2026-08-19-anti-bot-202-mistaken-for-missing-source.md
  - case-2026-08-08-data-check-beats-code-inference.md
  - case-2026-06-24-dryrun-proxy-vs-prod-state-blindness.md
  - case-2026-06-24-background-network-block-and-blind-wait.md
  - case-2026-06-20-subagent-claims-need-verification.md
  - case-2026-06-21-line-transform-breaks-on-control-flow.md
  - case-2026-06-21-empirical-reachability-before-deleting-dead-code.md
  - case-2026-06-21-empty-state-test-shared-cleanup-gap.md
  - "ProjectA: пользователь сказал что фичи нет — она была"
  - "ProjectA: пользователь сказал поле не работает — работало, но скрыто ролью"
  - "ProjectC: memory утверждала что файл существует — его уже удалили"
  - "ClaudSoul: собеседник дал аналогию 'продажники и сигареты' — агент интерпретировал на лету вместо того чтобы загуглить каноничный ответ"
  - "ClaudSoul: редактировал хук в репо, тестировал старую копию в ~/.claude/hooks/ — 2 попытки впустую, не проверив какой файл запускается"
  - "ClaudSoul: установил скиллы в commands/, не проверив что дубли уже лежат в skills/ — пользователь увидел двойные записи"
  - "ClaudSoul: 3 ошибки API при создании MCP-сервера — sqlite-vec syntax, FastMCP init args, межмодульный type/type_ — всё из-за предположений вместо проверки docs"
  - "ProjectA: scp flat-destination — файл bot-auth.ts не лёг в web/lib/, ребилд на старом коде, 401 (case-2026-04-20-scp-flat-destination.md)"
  - "ClaudSoul: прыгнул на 'малый hitbox' фикс для 3D click — реальная причина OrbitControls drag detection, обнаружено только после Playwright пробы (case-2026-04-21-hover-works-click-fails.md)"
  - "ProjectB: Meta API code 190 диагностировал как 'wrong env token', не проверив формат токена в leaked URL (f8c39050... вместо EAA-prefix); реальная причина — Caddy reverse_proxy пробросил Authorization в backend (case-2026-04-29-bearer-token-bleeding-through-proxy.md)"
  - "ProjectB: smoke-check curl /static/tailwind.css | grep — пусто, диагностировал 'build broken', 3 неверных attempt'a; реально curl получал 401 (basic-auth), CSS был правильный с первого деплоя (case-2026-05-03-curl-grep-blind-to-http-status.md)"
  - "ClaudSoul: пользователь сказал '/compile не собирает в других проектах' — захват работал везде, силос был в агрегации; плюс команда find падала в zsh, поймана тестом до записи (case-2026-06-14-cross-project-pipeline-silo.md)"
  - "ClaudSoul: 3 попытки чинил 'невидимые напоминания' — тишина была намеренным дизайном (задокументированным), не проверил замысел перед действием (case-2026-06-15-silence-by-design-debugged-as-defect.md)"
  - "ProjectA: субагент-аудит дал 3 завышенных claim'а за сессию (withAuth-фантом / round2-EPSILON / 14 мёртвых скриптов) — проверка перед действием не дала удалить рабочее (case-2026-06-20-subagent-claims-need-verification.md)"
  - "ClaudSoul: SESSION.md Pending перечислял 3 хвоста — git fetch/ls/smoke показали, что 2 уже закрыты параллельной сессией; действие по устаревшему TODO переделало бы закрытое (2026-06-21, compile-2026-06-21-update-verify-stale-session-todo)"
  - case-2026-07-05-numbers-need-source-in-public-content.md
  - case-2026-04-14-false-autonomy-attribution.md
  - case-2026-04-14-stale-credential-helper.md
  - case-2026-04-15-first-impulse-chain.md
  - case-2026-04-15-no-clarifying-questions.md
  - case-2026-04-20-write-instead-of-read-edit.md
  - case-2026-06-20-characterization-test-before-monolith-cut.md
  - case-2026-06-22-multistep-publish-verify-each-step.md
  - case-2026-06-29-review-finding-dismissed-by-reframe.md
provenance_traced: low
status: active

# Контекстные якоря
domain: [software_development, knowledge_management]
situation: "implementation, debugging, recommendation"
trigger: "unverified_claim, action_based_on_assumption"
stakes: "wasted_time, broken_code, wrong_recommendation"
actors: [agent, interlocutor, system]
tags: [verification, assumptions, trust, facts_over_claims]

need: "prevent_action_on_unverified_assumption"
urgency: "immediate"
availability: "foundational"

# Связи
related: []
edges:
  - generalizes: principle-completeness-over-speed.md

# Modification lineage
modification_history:
  - date: 2026-04-20
    kind: scope_widened
    reason: "добавлен post-deploy verify (grep на сервере после scp/rsync) — exit code 0 не гарантирует nested path"
    trigger_case: case-2026-04-20-scp-flat-destination.md
provenance_log:
  - date: 2026-07-25
    kind: reinforced
    reason: "гейт verify-log прогнан до выводов; пилотные числа перепроверены перед публикацией"
  - date: 2026-07-28
    kind: reinforced
    reason: "версии ПО из памяти устаревают (Opus 5 вышел, cutoff не знал — спас web-чек) + идентичность инструмента (у пользователя «Whisper» = Wispr Flow, облачный диктатор): сверяй внешний факт/тождество, не из памяти/имени"
  - date: 2026-07-29
    kind: reinforced
    reason: "проверка отсылки «двойная закольцовка» и версии стража перед выводами: оба раза факт разошёлся бы с догадкой"
    trigger_case: case-2026-07-29-verification-frame-loop.md
  - date: 2026-08-08
    kind: reinforced
    reason: "PDF закона по умолчанию первичная публикация; действующая редакция только через ELI API с changeDate"
    trigger_case: case-2026-08-08-polish-law-consolidated-text-via-eli-api.md
  - date: 2026-08-09
    kind: reinforced
    reason: "объяснил собеседнику причину срабатывания timestamp-canary-check.sh по выводу из поведения; исходник показал другую логику — сравнения с инжектом в хуке нет"
    trigger_case: case-2026-08-09-hook-behaviour-explained-without-reading-source.md
  - date: 2026-08-16
    kind: reinforced
    reason: "перед заносом дефекта в BACKLOG прочитал session-collector.sh — вывод о завышенном счётчике опровергнут"
    trigger_case: case-2026-08-16-indirect-count-vs-code-truth.md
fragile: false

# Blocker-tier (промоут 2026-05-18 после retro ProjectA AML hold ProjectD)
# Retrospective: confirmed_count 11, инжектировался knowledge-activator'ом и
# был проигнорирован в сессии ProjectA (запись «CRBR обновлён» и «возраст 5,5 лет
# у Платона» в память без verification). Уровень 2 (injection) недостаточен.
# Промоут до уровня 3 (mechanical blocker) согласно principle-knowledge-in-the-world.
# 2026-06-21 (retro, case-2026-06-21-empty-state-test-shared-cleanup-gap): рассмотрено
# расширение blocker'а на под-случай «сослался на символ/хелпер/константу из чужого
# модуля, не прочитав» — РЕШЕНО НЕ ДОБАВЛЯТЬ (владелец): этот промах не имеет
# детектируемого триггера в tool_input (нельзя по входу понять, что символ не прочитан),
# а blanket-сигнал на каждый Edit/Bash = шум (META.md: «fires everywhere → blocker не
# спасёт»). Остаётся на уровне 2 (injection knowledge-activator'ом). Узкие сигналы ниже
# (memory-write registry/attribute claims) — НЕ трогать/не расширять без явного запроса.
blocker: true
blocker_reminder: "Перед записью утверждения о статусе/регистре/возрасте/реквизите в память — где источник? Если со слов клиента или из ранней внутренней заметки без проверки — НЕ пиши факт, либо явно зафиксируй provenance (со слов кого, дата, верификация pending)."
detection_signals: |
  [
    {
      "name": "memory_write_external_registry_claim",
      "all_of": [
        {"tool_matches": ["Edit", "Write"]},
        {"file_path_regex": "memory/.*\\.md$"},
        {"any_of": [
          {"tool_input_contains": "CRBR"},
          {"tool_input_contains": "KRS"},
          {"tool_input_contains": "REGON"},
          {"tool_input_contains": "NIP"},
          {"tool_input_contains": "VAT"},
          {"tool_input_contains": "зарегистрир"},
          {"tool_input_contains": "обновлён"},
          {"tool_input_contains": "обновлен"}
        ]}
      ]
    },
    {
      "name": "memory_write_personal_attribute_claim",
      "all_of": [
        {"tool_matches": ["Edit", "Write"]},
        {"file_path_regex": "memory/.*\\.md$"},
        {"any_of": [
          {"tool_input_contains": "возраст"},
          {"tool_input_contains": "родился"},
          {"tool_input_contains": "родилась"},
          {"tool_input_contains": "проживает"}
        ]}
      ]
    }
  ]
---

**Принцип:** Не действуй на основании утверждений — действуй на основании фактов. Проверяй в коде/файлах/логах.

Это касается:
- Утверждений пользователя ("этого нет", "это сломано")
- Собственной памяти (файлы могли измениться)
- Документации (может быть устаревшей)

**Why:** Многократно подтверждено: пользователь может ошибаться, память устаревает, документация врёт. Действие без проверки = потраченное время или поломка.

**How to apply:**
- Перед реализацией "отсутствующей" фичи → grep/glob по кодовой базе
- Перед исправлением "бага" → воспроизвести через Playwright
- Перед рекомендацией из памяти → проверить что файл/функция ещё существует
- Перед интерпретацией аналогии/отсылки собеседника → загуглить/проверить источник
- Перед отладкой "сломанного" кода → проверить что тестируешь актуальную версию файла
- После любого деплоя (scp/rsync) → grep критического изменения прямо на сервере; exit code 0 не гарантирует что файл лёг в правильный nested путь
- При smoke-проверке HTTP-эндпоинта через `curl ... | grep` → ВСЕГДА сначала `curl -I` или `-w "%{http_code}\n"`; пустое тело при 401/403/404/5xx неотличимо от валидного тела без совпадений (case-2026-05-03-curl-grep-blind-to-http-status.md)

**Limitations:** Не применяется к тривиальным операциям (создание нового файла, форматирование). Проверка нужна когда действие основано на чужом утверждении о текущем состоянии.
