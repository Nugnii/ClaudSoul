---
name: Удаление по ярлыку, а не по содержимому
description: Решение «это можно удалить» держится на ярлыке, который агент сам повесил по внешнему признаку («дубль», «наши остатки», «не используется»), а не на осмотре того, что внутри; внутри оказываются данные владельца
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-31
source_cases:
  - case-2026-04-15-destructive-install-assumption.md
  - case-2026-10-31-app-folder-deleted-without-checking-data.md
source_session: ""
status: active

domain: [file_management, disk_cleanup, install_scripts]
situation: "удаление файлов, папок или программ: чистка диска, установщик, уборка дублей"
trigger: "объект назван «дублем / мусором / неиспользуемым» по внешнему признаку — имя, дата, место, метка Spotlight"
stakes: "data_loss"
actors: [agent, owner]
environment: ""
circumstances: "удаление необратимо: нет корзины, нет резервной копии"
purpose: "освободить место / убрать конфликт"
method: "rm -rf, автоочистка в скрипте"
tags: [rm-rf, destructive_action, duplicates, cleanup, owner_data]
volatile_anchors: []
self_altering: ""
outcome_signals: []

need: "avoid_data_loss"
urgency: "when_relevant"
availability: "has_alternatives"

related: [principle-verify-before-acting.md, pattern-absence-claimed-from-the-tools-window.md]
edges:
  - specializes: principle-verify-before-acting.md
  - similar_to: pattern-absence-claimed-from-the-tools-window.md

promotion_tier: 2
scope: universal
origin_domain: disk_cleanup
modification_history: []
provenance_log: []
fragile: false

origin: solo
trigger_for_co_cognition: ""
bridge_layer: ""
preceded_artifact: n/a
---

# Удаление по ярлыку, а не по содержимому

Ярлык «дубль», «мусор», «не используется» вешается по внешнему признаку: совпало имя,
пуста метка Spotlight, программа похожа на знакомую. Удаление идёт по ярлыку. Содержимое
объекта при этом никто не открывал, а владелец одобрял именно ярлык, то есть описание
агента, а не сам объект.

**Случаи:**
- 15 апреля 2026: установщик ClaudSoul должен был удалять «дубли» скиллов в `~/.claude/skills/`.
  На чужой системе это могли быть собственные скиллы пользователя с тем же именем. Поймал
  собеседник до записи кода.
- 31 октября 2026: при чистке диска `/Applications/MAMP` удалён как «дубль» локального сервера.
  На следующем же пункте у XAMPP с ярлыком «Spotlight не видел ни одного запуска» нашлись
  проекты `job`/`oloi` и базы MySQL. Есть ли данные в MAMP, доказать уже нельзя.

**Правило:** перед удалением открой объект и назови, ЧТО в нём лежит (папки данных, размер,
даты), а не КАК ты его назвал. Владельцу показывай содержимое: одобрение ярлыка не одобряет
объект. Где содержимое может принадлежать владельцу, а осмотр невозможен, — не удаляй
автоматически, предупреди.

**Признаки, что ярлык внешний:** совпадение имени или хеша без проверки, кто владелец копии;
дата последнего запуска из Spotlight; «похоже на установщик / кэш / дубль»; вывод о
неиспользовании без поиска данных внутри.

**Limitations:** кэши и сборочные артефакты, которые программа восстанавливает сама
(`.next`, npm-кэш, образы Docker), удаляются по ярлыку законно: их содержимое по определению
не данные владельца. Граница — восстановимость, а не тип файла.
