---
name: При деплое исключай файлы данных
description: SCP/rsync/copy деплой — никогда не копировать БД, кеши, env-файлы, логи
type: pattern
outcome: error
confidence: 2
impact: 5
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-06-17
source_cases:
  - "ProjectA: scp -r web/prisma перезаписал продовый SQLite локальным dev.db"
status: active

# Контекстные якоря
domain: [software_development, devops]
situation: "deploy, file_transfer"
trigger: "scp_command, rsync_command, recursive_copy"
stakes: "data_loss, production_data_overwrite"
actors: [agent, system]
tags: [deploy, scp, rsync, data_protection, exclude_list]

need: "preserve_user_data"
urgency: "when_relevant"
availability: "has_alternatives"

# Связи
related:
  - deploy-never-copy-db.md
edges:
  - similar_to: pattern-check-build-config.md

# v1.0.9 — gradation + scope + adaptive
promotion_tier: 2
scope: universal
origin_domain: software_development
effective_contradicted: 0.0
contradiction_log: []
modification_history: []
provenance_log:
  - date: 2026-08-09
    kind: reinforced
    reason: "ProjectA 74f6fd2 (06-15): deploy.sh переведён на rsync --delete, прод-БД выведена из синка — применение правила; 90404e6 (06-17): rsync --delete перезаписал боевой .env локальным и удалил .env.local — прод смотрел на dev-базу"
  - date: 2026-08-09
    kind: reinforced
    reason: "второй эпизод того же кластера (см. предыдущую запись)"
---

**Паттерн:** При файловом деплое (SCP, rsync, cp) всегда исключать:
- Файлы БД (*.db, *.sqlite, data/)
- Env-файлы (.env, .env.production)
- Логи и кеши (logs/, .cache/, node_modules/)
- Секреты и ключи

**Why:** Одна команда `scp -r` может перезаписать продовые данные локальными. Необратимо.

**How to apply:** 
- Деплой только поименованными файлами/папками, не рекурсивным копированием корня
- Лучше: скрипт деплоя с явным exclude-списком
- Проверять: содержит ли копируемая директория файлы данных

**Limitations:** Не применяется к контейнерному деплою (Docker), где данные монтируются отдельно.
