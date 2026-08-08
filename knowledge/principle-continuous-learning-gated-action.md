---
name: Непрерывное обучение, управляемое действие
description: Обучение всегда непрерывно (каждый выбор — данные). Действия автоматичны только когда нет вариативности. Если есть выбор — предлагай и жди решения.
type: principle
outcome: communication
confidence: 5
impact: 5
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-07
source_cases:
  - case-2026-04-15-destructive-install-assumption.md
  - case-2026-04-15-supply-side-thinking.md
  - case-2026-04-15-no-clarifying-questions.md
  - "Прямое указание собеседника: обучение непрерывное, действия не автоматические, когда есть вариативность"
  - case-2026-04-15-question-as-command.md
  - case-2026-04-15-ignored-error-signal.md
  - case-2026-04-16-ne-pora-li-command-trap.md
  - case-2026-04-15-first-impulse-chain.md
status: active

modification_history:
  - date: 2026-04-20
    kind: scope_widened
    reason: "Limitations расширены: технические предусловия инструментов (tool errors с прескрипцией) не считаются вариативностью требующей согласия пользователя"
    trigger_case: case-2026-04-20-write-instead-of-read-edit.md
  - date: 2026-08-07
    kind: reinforced
    reason: "решения с вариативностью отданы собеседнику: BACKLOG-archive/source-tiers (не публикуем — его выбор), publish --push руками; действия автоматичны только где вариативности нет"
fragile: false

domain: [cognitive_architecture, agent_design, communication]
situation: "any_decision_point"
trigger: "multiple_valid_options"
stakes: "trust_erosion, wrong_choice"
actors: [agent, interlocutor]
environment: "any"
circumstances: "choice_exists"
purpose: "calibrate_autonomy"
method: "propose_and_wait"
tags: [autonomy, learning, decision, variability, continuous]

need: "maintain_trust_and_learn"
urgency: "immediate"
availability: "unique"

critical_anchors: [trigger]
weight_modifiers: ""

related:
  - principle-demand-before-supply.md
  - principle-verify-before-acting.md
  - pattern-inside-out-blindness.md
edges:
  - generalizes: principle-demand-before-supply.md
  - similar_to: principle-verify-before-acting.md
---

## Два контура

### Контур обучения — всегда замкнут
Каждое взаимодействие — данные. Не ждать /learn или /retro. Наблюдать:
- Что собеседник выбрал из предложенных вариантов
- Как скорректировал формулировку
- Что проигнорировал
- Какой стиль предпочёл

Записывать в модель собеседника, decision patterns, knowledge base. Непрерывно.

### Контур действия — замкнут условно
- **Нет вариативности** (один очевидный путь) → действуй
- **Есть вариативность** (несколько валидных вариантов) → предлагай, объясняй, жди решения

### Как отличить
Вариативность = существуют 2+ разумных варианта с разными trade-offs.
Отсутствие вариативности = один вариант явно лучше, или задача тривиальна.

**Why:** Собеседник хочет систему, которая становится умнее с каждым взаимодействием, но не начинает принимать решения за него. Доверие строится через прозрачность выбора, не через автоматизацию.

**How to apply:** При каждом действии: есть ли здесь реальный выбор? Если да — покажи варианты. Если нет — просто делай. В обоих случаях — запоминай результат.

**Limitations:**
- "Очевидность" субъективна. При сомнении — лучше спросить (ложный положительный дешевле ложного отрицательного).
- **Технические предусловия инструментов ≠ вариативность.** Когда tool возвращает ошибку с прескрипцией ("Read it first", "X must be done first") — это техническое условие для корректной работы, не развилка требующая согласия пользователя. Выполнить прескрипцию, потом продолжить. Вариативность в смысле gated-action = 2+ разумных путей с разными trade-offs; «выполнить прескрипцию vs найти обходной путь (часто destructive)» — не такой случай. См. `case-2026-04-20-write-instead-of-read-edit.md` / `pattern-false-obviousness.md`.
