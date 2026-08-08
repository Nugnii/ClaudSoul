---
name: retro
description: "Post-fix retrospective — analyze what went wrong, extract lessons, update knowledge base with confidence weights."
user-invocable: true
argument-hint: "[short description of what was fixed]"
---

# Retro — Post-Fix Retrospective

**Type:** worker

You just fixed something that didn't work on the first try. Now do an honest retrospective.

**MANDATORY READ:** Load `~/.claude/global-lessons/META.md` — knowledge system rules.

## Step 1: Reconstruct the timeline

Look back through THIS conversation and identify:
- What was the original task/request
- What went wrong (error, wrong approach, failed attempt)
- How many attempts it took to fix
- What was the final working solution

## Step 2: Analyze the chain of reasoning

For EACH attempt, document:
1. **What I thought was the cause** — my hypothesis at that moment
2. **What I did** — the specific change/action
3. **What happened** — the actual result
4. **Was the reasoning correct?** — yes/no and why

Be brutally honest. If I was guessing randomly — say so. If I repeated the same fix — say so.

## Step 3: Why-каскад (root cause через цепочку «почему»)

Метод восходит к Тайити Оно (Toyota Production System). Цель — не остановиться на симптоме, а дойти до **системной** причины (хук, правило, архитектурное решение, отсутствующая инвариант).

### 3.1 Построй цепочку

Начни с наблюдаемой проблемы. Спроси «почему?» к ответу предыдущего шага. Повторяй пока не дойдёшь до системного уровня.

```
Q0: [что произошло — наблюдаемый симптом]
  Why? → A1: [ближайшая причина]
    Why? → A2: [причина A1]
      Why? → A3: ...
        ...
          → A_final: [системная причина]
```

**Критерий остановки — НЕ глубина 5**, а ответ на вопрос: «это **system-level** причина или ещё симптом?» Системная причина — то, что можно изменить структурно (правило, хук, проверка, абстракция). Если ответ всё ещё «человек ошибся / был невнимателен» — копай глубже.

Глубина обычно 3-7. Если меньше 3 — вероятно остановился рано. Если больше 7 — вероятно ушёл в спекуляции, вернись и проверь эмпирически.

### 3.2 Разреши ветвление (если есть)

Toyota'вская критика (Minoura, Allspaw): линейная цепочка скрывает множественные причины. Если на каком-то шаге причин **две и больше параллельно** — запиши как ветви:

```
A2: ...
  Why? → A3.a: [причина по линии X]
       → A3.b: [причина по линии Y]
```

Каждая ветвь продолжается отдельно до своего системного уровня. Может оказаться что разные ветви сходятся в общий корень — это сильный сигнал.

### 3.3 Counterfactual test финального звена

Для каждого системного корня (включая ветви) проверь:

> «Если бы A_final не было — инцидент бы не произошёл?»

Если ответ «всё равно произошёл бы, потому что есть Z» — Z и есть истинный корень, добавь следующий шаг. Если «нет, не произошёл бы» — корень найден.

Эта проверка соответствует правилу `Reproduce first, fix second` — корень эмпирически связан с симптомом, не только логически.

### 3.4 Зафиксируй пропущенные сигналы

Для каждого звена каскада: какой **сигнал** в тот момент уже указывал на эту причину? (Сообщение об ошибке, лог, поведение, ранее зафиксированное знание.) Что я не прочитал, не запросил, не сопоставил?

Это второй слой обучения — не только «что было причиной», но и «почему я её не увидел раньше».

### 3.5 Маппинг на edges

Каждое звено каскада, которое выходит за рамки одного case'а, становится `caused_by` edge между сущностями знания:

- Симптомы — текущий case
- Промежуточные звенья — могут указывать на существующие case/pattern
- Финальный корень — pattern или principle, если уже формализован

При записи case в Step 4 включи `edges: [caused_by: <parent>]` для каждого звена, где `<parent>` уже есть в базе. Для звеньев, которых ещё нет в базе — кандидаты на новый case/pattern.

## Step 4: Write the CASE

**MANDATORY READ:** Load `references/case-template.md` — full YAML template for the case file.

Save to `~/.claude/global-lessons/` as `case-YYYY-MM-DD-brief-name.md` using the template.

## Step 5: Extract PATTERN or PRINCIPLE

This is the critical step. Don't just save the case — abstract upward.

**MANDATORY READ:** Load `references/promotion-rules.md` — search, reinforce, contradict, promote, registry update.

## Step 5.5: Chain linking (v1.0.7)

Проверь Session Registry на совпадения по `domain + trigger` с только что созданным case'ом.

**MANDATORY READ:** Load `references/chain-linking.md` — алгоритм, типы edges, guardrails.

Если нашёл совпадения — предложи edges пользователю (не добавляй автоматически). Если нашёл 3+ strong matches — это сильнее обычного порога 2+ и означает вероятный общий корень → рекомендуй промоушен в pattern.

## Step 6: Report to user

```
📋 РЕТРОСПЕКТИВА
━━━━━━━━━━━━━━━
Проблема: [one line]
Why-каскад:
  Q0 [симптом] → A1 → A2 → ... → A_final [системная причина]
  (если есть ветвление — показать)
Корневая причина: [одна строка, либо несколько если ветви сошлись в разных корнях]
Counterfactual: [✓ если "без корня не произошло бы" подтверждено]
Попыток: N
Пропущенный сигнал: [one line]

📊 ВЛИЯНИЕ НА БАЗУ ЗНАНИЙ
- Кейс: [saved where]
- [Подкрепляет паттерн X (confidence N→N+1)] или
- [Новый паттерн: Y] или
- [Противоречие с Z → branched/narrowed/deprecated]

🎯 ПРАВИЛО
[The extracted rule — one sentence, starts with "When..." or "If..."]
```

## Rules

- Do NOT write vague lessons like "be more careful" or "check more thoroughly"
- Every lesson MUST produce a concrete, actionable rule
- ALWAYS try to connect to existing knowledge (reinforce or contradict)
- If the fix took only 1 attempt — still write the case if the error was non-obvious
- If I was just guessing — admit it and write WHY I couldn't reason properly
- NEVER blame the user, external tools, or "complexity"
- When in doubt about scope — save to global. Redundancy > amnesia
- The goal is not a diary — it's a GROWING INTELLIGENCE that changes behavior

## Definition of Done

- [ ] Timeline reconstructed with all attempts documented
- [ ] Why-каскад построен до системного уровня (3-7 звеньев), ветвления разрешены если есть
- [ ] Counterfactual test пройден для каждого финального корня
- [ ] Пропущенные сигналы зафиксированы для каждого звена
- [ ] `caused_by` edges добавлены к существующим case/pattern из звеньев каскада
- [ ] Case file saved to `~/.claude/global-lessons/case-*.md`
- [ ] Existing knowledge checked for reinforcement/contradiction
- [ ] Pattern promotion evaluated (2+ similar cases)
- [ ] Chain linking checked (Session Registry, propose edges if domain+trigger match)
- [ ] Modification_history updated (v1.0.8) if pattern/principle was narrowed/branched/deprecated/scope-widened/reinforced-after-challenge; fragile flag recomputed
- [ ] Report shown to user in standard format

**Version:** 1.5.0
**Last Updated:** 2026-05-15
