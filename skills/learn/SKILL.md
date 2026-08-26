---
name: learn
description: "Быстрая запись знания — auto-detect тип (error/success/communication), запись case, проверка на промоушен в pattern."
description_en: "Quick knowledge capture — auto-detects the type (error/success/communication), writes a case, checks for promotion to a pattern."
user-invocable: true
argument-hint: "[тип: error|success|communication] [что произошло]"
---

# Learn — Quick Knowledge Capture

**Type:** worker

Быстрая запись знания на ходу. Для глубокого анализа — `/retro`. Для быстрого захвата — `/learn`.

| | /retro | /learn |
|---|--------|--------|
| Глубина | Полная реконструкция таймлайна | Быстрый захват одного знания |
| Когда | После значимых событий | В любой момент, low friction |
| Вывод | Многосекционный отчёт | 3-4 строки |
| Время | 2-5 минут | 30 секунд |

**MANDATORY READ:** Load `~/.claude/global-lessons/META.md` — knowledge system rules.

## Step 1: Auto-detect тип

Определить тип из контекста или из аргумента пользователя:

| Сигнал | Тип |
|--------|-----|
| Были ошибки, несколько попыток, только что починили | **error** |
| Задача решена гладко, стратегия сработала | **success** |
| Собеседник поправил, удивил, указал на ложное допущение | **communication** |
| Аргумент начинается с "error", "success", "communication" | Использовать указанный тип |

Если тип неочевиден — спросить одним вопросом: "Это ошибка, успех или коммуникативный инсайт?"

## Step 2: Quick extraction

Извлечь ОДНО знание. Не развёрнутый анализ — одно конкретное правило.

### Error:
- **Что сломалось:** [одна строка]
- **Корневая причина:** [одна строка]
- **Правило:** [конкретное, actionable]

### Success:
- **Что сработало:** [одна строка]
- **Почему:** [гипотеза]
- **Правило:** [когда использовать этот подход]

### Communication:
- **Что предполагал:** [одна строка]
- **Что оказалось:** [одна строка]
- **Правило:** [как интерпретировать такие сигналы]

## Step 2b: Bridge origin detection

Определить, связано ли знание с межслойным мостом:

| Сигнал | origin | bridge_layer |
|--------|--------|-------------|
| Инсайт родился в совместном обсуждении | `co-cognition` | L2↔L7, L5↔L7 |
| Pivot в траектории привёл к знанию | `trajectory_pivot` | L4↔L7 |
| Промах предсказания породил инсайт | `co-cognition` | L6↔L7 |
| Знание из коррекции собеседника | `solo` | L2↔L3 |
| Нет со-мышления | `solo` | — |

Если `origin: co-cognition` — записать `trigger_for_co_cognition` (analogy, contradiction, question, predictive_miss).

## Step 3: Write case

**MANDATORY READ:** Load `references/case-template.md` — full YAML template + impact scale + bridge metadata + registry update.

Save to `~/.claude/global-lessons/` as `case-YYYY-MM-DD-brief-name.md` using the template.

## Step 4: Pattern promotion check

Быстро просканировать `~/.claude/global-lessons/`:

### 4a. Поиск подтверждения
Есть ли существующий pattern/principle с похожим trigger+situation+domain?
- **Да, подтверждает** → `bash ~/.claude/hooks/knowledge-counter-bump.sh <name> confirmed "<почему>" <case-файл>`
  (инкрементит `confirmed_count`, ставит `last_confirmed`, пишет в `provenance_log` — НЕ в `modification_history`, та только для перекроек правила). `confidence` += 1 отдельно.
- **Да, противоречит** → `bash ~/.claude/hooks/knowledge-counter-bump.sh <name> contradicted "<что разошлось>" <case-файл>`
  Затем отметить: «Противоречит [name]. Глубокий разбор (narrow / branch / deprecate) — `/retro`.»

> До v1.11 здесь стоял запрет «НЕ трогать автоматически, нужен /retro». Его цена измерима:
> `contradicted_count` был равен нулю во **всех 265** знаниях базы при 156 знаниях с
> подтверждениями. Счётчик, который умеет только расти, не измеряет ничего, а FSRS и
> `reliability` считались по половине формулы. Инкремент — механический (скрипт), решение о
> судьбе знания — по-прежнему человеческое и по-прежнему в `/retro`.

### 4b. Промоушен case → pattern (v1.0.9 — gradation)

Проверить количество кейсов + контекст. Определить **tier** и действовать по нему:

| Tier | Критерии | Действие |
|------|----------|----------|
| **1 — auto-create** | 2+ кейсов с **identical** trigger + identical outcome + parent principle существует (specializes) | Создать pattern сразу, без подтверждения. В отчёте: «Создан pattern X (tier 1 — identical trigger, specializes principle Y)» |
| **2 — ask** | 2+ кейсов, но триггеры adjacent (не identical) ИЛИ parent отсутствует ИЛИ cross-domain | Спросить: «Вижу N кейсов с trigger≈[X]. Создать pattern? (y/n)» |
| **3 — mandatory-ask** | Новый pattern противоречит существующему ИЛИ создаёт branching | Обязательно спросить + объяснить что именно противоречит и какие alternatives |
| **нет** | 0-1 кейс с таким trigger | Ничего не делать |

При создании pattern — обязательно заполнить `promotion_tier` в frontmatter (1/2/3) — используется для адаптивной деградации.

### 4c. Scope auto-detect (v1.0.9)

Определить `scope` pattern'а по `domain`:

| Условие | scope |
|---------|-------|
| `domain` ∩ {communication, dialogue, agent_design} непуст | `per-speaker` |
| Только технические домены (next.js, bash, hooks, ci_cd, ...) | `universal` |
| И то и другое | `mixed` |

Для `per-speaker | mixed`:
- При создании → `valid_for: [primary]` (или текущий speaker_id из `~/.claude/hooks/state/session-speaker_*`)
- Инициализировать `per_speaker_state[primary]` с confidence:1, confirmed_count:1

### 4d. Communication caveat
Коммуникативные знания (`scope: per-speaker`): confidence на уровне speaker'а растёт только до 2, пока не подтверждено от **разных** speaker_id.

### 4e. Закрытие pending-исхода (v1.11)

Триггер: всплыл алерт «⚡ N blocker-tier знание(й) без исхода» (Stop → `pending-alerts-surface`),
либо ты сам знаешь, что blocker-tier знание было в работе.

Открытые ключи — **по всем сессиям**, не только по текущей (v1.12.0):
```bash
source ~/.claude/hooks/disagreement-lib.sh
dis_scan_open          # строки `sid|key|date|confidence|tool`
```

До v1.12.0 здесь стоял `grep` по файлу текущей сессии. Это и было местом разрыва:
алерт про висячие записи показывается на СЛЕДУЮЩЕЙ сессии, а закрывать предлагалось
в файле ТЕКУЩЕЙ, где их нет. Из 5 живых записей закрылась одна — та единственная,
что успела закрыться внутри своей же сессии. Счётчик `contradicted_count` оставался
нулевым во всех 265 знаниях не потому, что нечего опровергать.

Запись, провисевшая дольше `DISAGREEMENT_EXPIRE_DAYS` (по умолчанию 7), гасится
автоматически как `not_applicable` с пометкой `expired`. Счётчики при этом **не
трогаются**: истечение — отсутствие данных, а не подтверждение.

По каждому ключу — один из трёх исходов:

| outcome | когда | что делать |
|---------|-------|-----------|
| `confirmed_knowledge` | знание применялось и оказалось верным | `knowledge-counter-bump.sh <key> confirmed` |
| `outdated_knowledge` | знание противоречило делу / было неверным здесь | `knowledge-counter-bump.sh <key> contradicted` + Step 4a |
| `applicable_not_followed` | знание ОТНОСИЛОСЬ к делу и НЕ БЫЛО применено | только запись исхода, счётчики не трогать |
| `not_applicable` | знание просто не относилось к тому, что делали | только запись исхода, счётчики не трогать |

> **Про четвёртый исход (2026-08-01).** Трёх не хватало ровно на тот случай, ради которого
> проект существует. Правило о поведении агента бывает не только верным, неверным или
> посторонним — оно бывает **уместным и проигнорированным**. Раньше такой случай приходилось
> записывать как `not_applicable` («не относилось»), что прямая неправда, либо как
> `confirmed` («применялось»), что завышает счётчик. Первый живой случай: за сессию
> 2026-07-31 запущены две долгие проверки (65 и 64 мин), знание
> `progress-visibility-long-async` предписывает назвать ориентир заранее — не названо ни
> разу, при том что знание висело в контексте. Счётчики не трогаются: пропуск не
> подтверждает и не опровергает знание, он измеряет РАЗРЫВ между знанием и действием,
> и у него отдельная строка в `metrics.md`.

Затем закрыть pending и записать в durable-журнал. `SID` берётся из первой колонки
`dis_scan_open` — закрывать надо в том файле, где запись создана, а не в текущем:
```bash
S="$HOME/.claude/hooks/state"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"date":"%s","key":"%s","outcome":"%s"}\n' "$TS" "$KEY" "$OUTCOME" \
  >> "$S/disagreement-pending-$SID.jsonl"
printf '{"date":"%s","session":"%s","knowledge":"%s.md","confidence":%s,"outcome":"%s","case":"%s"}\n' \
  "$TS" "$SID" "$KEY" "$CONF" "$OUTCOME" "$CASE" >> "$S/disagreement-outcomes.jsonl"
```

Первая запись гасит алерт (сессионный файл), вторая переживает сессию и служит
источником для `/knowledge-audit`. **Не пропускать `not_applicable`** — «знание
всплыло не к месту» это тоже измерение: если один ключ даёт его раз за разом,
проблема в якорях знания, а не в знании.

## Step 5: Report (3-4 строки)

```
📝 Записано: case-YYYY-MM-DD-brief.md (outcome, impact:N)
🔗 [Подкрепляет: pattern-X (confidence N→N+1)] или [Новый кейс, совпадений пока нет]
🏷️ domain: [...] | trigger: [...] | tags: [...]
[Противоречит: pattern-Y — нужен /retro]
```

Не больше 4 строк. Это /learn, не /retro.

## Rules

- БЫСТРО. Не разворачивать в полную ретроспективу. Если нужен глубокий анализ — предложить /retro
- Каждое правило КОНКРЕТНО и ACTIONABLE. Не "быть внимательнее" — а "проверять X перед Y"
- Якоря извлекать автоматически, не спрашивать у собеседника
- При сомнении — save to global (лучше иметь везде, чем потерять)
- Если хук error-tracker подсказал — контекст ошибки УЖЕ в диалоге, не переспрашивать
- При промоушене в pattern — действовать по tier'у (v1.0.9): tier 1 auto-create, tier 2/3 спрашивать. Не спрашивать по умолчанию — это создаёт избыточное трение когда случай очевиден

## Definition of Done

- [ ] Type auto-detected or confirmed with user
- [ ] One actionable rule extracted
- [ ] Case file saved to `~/.claude/global-lessons/case-*.md`
- [ ] Pattern promotion check completed
- [ ] Report shown (≤4 lines)

**Version:** 1.5.0
**Last Updated:** 2026-08-01