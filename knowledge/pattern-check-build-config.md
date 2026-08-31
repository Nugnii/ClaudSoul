---
name: Проверяй конфиг сборки перед деплоем
description: NODE_OPTIONS, memory limits, env vars — читай из package.json/config, не переопределяй вслепую
type: pattern
outcome: error
confidence: 2
impact: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-07
source_cases:
  - "ProjectA: передали NODE_OPTIONS=4096 через SSH, а в package.json стояло 7168 — сборка падала OOM"
status: active

# Контекстные якоря
domain: [software_development, devops]
situation: "deploy, build, ci_cd"
trigger: "build_failure, oom_error, env_override"
stakes: "failed_deploy, downtime"
actors: [agent, system]
tags: [build_config, node_options, memory_limits, deploy_checklist]

need: "prevent_deploy_failure_from_overridden_config"
urgency: "when_relevant"
availability: "has_alternatives"

# Связи
related: []
edges:
  - similar_to: pattern-deploy-exclude-data.md

# v1.0.9 — gradation + scope + adaptive
promotion_tier: 2
scope: universal
origin_domain: software_development
effective_contradicted: 0.0
contradiction_log: []
modification_history: []
provenance_log:
  - date: 2026-08-07
    kind: reinforced
    reason: "перед прогоном mcp-тестов конфиг запуска прочитан из CI-workflow (uv run --frozen по uv.lock), а не угадан — все прогоны сессии шли верной командой"
---

**Паттерн:** Перед деплоем проверяй конфигурацию сборки в проекте (package.json scripts, .env, Makefile). Не переопределяй параметры вслепую.

**Why:** Проект может иметь свои настройки памяти, переменных окружения, флагов сборки. Переопределение меньшими значениями ломает сборку.

**How to apply:** Перед `npm run build` на сервере — прочитать package.json scripts секцию. Если NODE_OPTIONS уже задан — не передавать свой.

**Limitations:** Не применяется к локальной разработке, где конфиг обычно стандартный.
