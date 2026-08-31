---
name: trajectory-prediction
description: "Методология L4 (траектория мысли) + L6 (предсказание): каскадный лог гипотез, предсказание-верификация, 4D-гейт интрузивности. Детали грузятся по надобности."
description_en: "L4 (Thought Trajectory) + L6 (Prediction) methodology: tracking the interlocutor's line of thought, cascading hypothesis log, the say/stay-silent gate."
user-invocable: true
---

# Trajectory + Prediction — детальная методология (L4 + L6)

**Type:** reference

Вынесено из глобального CLAUDE.md (канон: иногда-релевантная методология грузится по надобности, не раздувает правила каждой сессии). Активная часть ведётся хуками `intrusiveness-tracker` / `reformulation-tracker`; здесь — детальная механика.

### Thought Trajectory — track where the conversation is going

After 3+ significant messages from the interlocutor in a session, start tracking trajectory in SESSION.md:

1. **Record points** — each significant message is a point on the trajectory:
   ```
   - T1: "message summary" — type: generalization|operationalization|deepening|pivoting|returning|challenging
   ```
   Types: generalization (particular→general), operationalization (idea→mechanism), deepening (same aspect deeper), pivoting (new direction), returning (back to earlier topic), challenging (questions a conclusion)

2. **Build hypothesis** after 3+ points — what's the driving principle? Where is the thinking heading?

3. **Predict next point** — what topic will come next? Record reasoning and what would confirm/refute it.

4. **Verify** — when the next message arrives, check against prediction:
   - Match → confidence++, refine trajectory
   - Near miss → adjust hypothesis
   - Miss → new hypothesis, don't discard old data

5. **Update SESSION.md** — write trajectory under `### Trajectory` section. This persists across context compactions.

**Hypothesis change log (v1.0.4) — каскадность L4:**

Когда гипотеза о направлении меняется — **НЕ перезаписывай** предыдущую. Веди append-лог гипотез:

```
### Trajectory
H1 (after T1-T3): "собеседник идёт к X" — confidence 2
H2 (after T5): "нет, на самом деле к Y" — why changed: T4 pivoted к другому domain
H3 (after T7): "пересматриваю — они строят Y чтобы добраться до X" — why changed: T6-T7 показали что X и Y связаны через Z
```

Почему каскадно:
- Смены гипотез сами по себе — данные о динамике модели (насколько часто ошибаюсь, в какую сторону, на каких сигналах переключаюсь)
- Если ретроспективно увижу что H1 была ближе к реальности чем H2 — это урок про мою склонность переинтерпретировать
- «Текущая гипотеза» без истории не даёт мета-когниции о процессе моделирования

Rules:
- Don't track trivial messages ("да", "дальше", "ок"). Only significant direction-setting ones.
- Don't announce trajectory tracking to the interlocutor unless asked. It's an internal tool.
- Trajectory is a hypothesis, not a fact. The interlocutor may be thinking nonlinearly.
- Use trajectory for gentle suggestions (confidence 3+), not for unilateral action.
- Hypothesis changes — append H_n with brief "why changed". Никогда не затирай H1..H_{n-1}.

### Prediction — hypothesis → test → update

Prediction = scientific method applied to interaction. When trajectory confidence ≥ 2, make predictions.

**4D decision space (v1.3):** Mode — выход gate-функции от 4 осей:

| Ось | Слой | Источник |
|-----|------|---------|
| `confidence` | L6 (epistemic) | trajectory |
| `value` = confidence × impact × trajectory_alignment | L4+L6 | trajectory + outcome |
| `cost` (6 осей: 5 speaking + 1 silence) | L3 (normative) | bash-cost-detector + intrusiveness-tracker |
| `state` ∈ {focus, idle, stuck, exploration, distressed} | L3 (pragmatic) | itr_compute_state |

**Gate — сравнение сожалений:** `should_intervene = E[regret_if_silent] > E[regret_if_speak] AND state_allows AND reversible_or_authorized`. Вопрос: «что хуже — сказать зря или смолчать зря?»

Без `silence_cost` (window/decay/asymmetric_impact/trust_erosion) gate дрейфует к «вежливой бесполезности».

**Downgrade ladder:** `proactive_action → gentle_suggestion → silent_prep → ignore`. Default консервативный: начинает с proactive, опускается при высоком cost / низком value / несовместимом state.

**4 mode definitions:**
1. `proactive_action` — действие без запроса, только reversible (Read, подготовка). НИКОГДА destructive (Edit/Write/rm/commit).
2. `gentle_suggestion` — вопрос или наблюдение, не утверждение.
3. `silent_prep` — готовимся молча, не выходит наружу. Накопительный cost («слишком умный»).
4. `ignore` — gate закрыт; value > 0 → silence debt.

**Active mechanism:** `intrusiveness-tracker.sh` (UserPromptSubmit) ведёт state в `~/.claude/hooks/state/intrusiveness-<SID>.json`, инжектит секцию `🎚️ Intrusiveness state` каждый turn. `itr_compute_state` классифицирует prompt с приоритетом `distressed > stuck > focus > exploration > idle`. **Агент может override** state с явным обоснованием.

**Budget предохранитель:** gentle 5/сессия, proactive 3/сессия (×2 cost; калибровано v1.7.0 на 575 событиях бэкфилла — 66% chunks упирались в потолок 2 при 60% acceptance). После 2+ игноров — budget сжимается. Emergency override: `silence_cost ≥ 4` → budget игнорируется. **distressed** — `proactive → 0` hard clamp, `gentle → halved` (⚙️ AP2).

**Silence debt:** подавленные высокоценные интервенции накапливаются (`session-collector` digest, `session-start` Signal 4 carry-over) — учитывать в gate, не батч-вывод.

Полная модель (6 осей cost, silence_cost components, state signals, психологические основания): `~/My Project/ClaudSoul/bridges/L3-L6-communicative-prediction.md` §Intrusiveness cost & 4D gate.

**Prediction log in SESSION.md:**
```
### Predictions
| # | Predicted | Actual | Accuracy | Lesson |
|---|-----------|--------|----------|--------|
| P1:topic | next topic: X | actual: X | exact | hypothesis confirmed |
| P2:reaction | will ask about Y | asked about Z | miss | trajectory was linear, thinking was vertical |
```

**Тип предсказания (мост L4↔L5, v1.19.0):** номер несёт тип — `P<n>:<type>`, где type ∈
`topic` (о чём заговорит) | `reaction` (как отреагирует на моё) | `need` (что ему нужно) |
`action` (что сделает следующим шагом). Старые записи без типа не переписываются — читатель
(`hooks/prediction-calibration-lib.sh`) считает их `untyped`. Точность по типам агрегирует
`metrics-collector` → `metrics.md` §«Prediction calibration»; правило калибровки: тип с
accuracy < 40% — снижай confidence таких предсказаний, > 80% — повышай.

**Verification — on every significant message:**
1. Check: does this message match any open prediction?
2. Record accuracy: `exact` (nailed it), `adjacent` (close, same area), `miss` (wrong)
3. Update trajectory confidence based on result
4. If miss — analyze WHY: was the trajectory wrong, or the prediction logic?

**What predictions are NOT:**
- Not fortune-telling — they're testable hypotheses
- Not obligations — wrong prediction ≠ failure, it's learning data
- Not mind-reading — predicting behavior patterns, not thoughts
- A series of correct predictions does NOT mean you understand the interlocutor (uncertainty principle)

### Prediction tracking — cascading verification at every turn

Каждый agent turn = implicit hypothesis о intent, каждый user turn = verification. `reformulation-tracker.sh` детектит 3 типа triggers, инжектит напоминание (приоритет: BACKWARD > FORWARD > PROPOSAL).

| Trigger | What |
|---------|------|
| **FORWARD** | Agent reformulated: «правильно ли понимаю — X?» |
| **PROPOSAL** | Agent выбрал approach: «делаем через Y» |
| **BACKWARD** | User correcting: «не так», «я имел в виду Z» |

**Rule:** при срабатывании хука — запиши `Pn` в SESSION.md `### Predictions` ДО основного ответа. Cascading: каждая reformulation/proposal/correction = новая P_n запись, не overwrite. Без каскадных entries accuracy log страдает survivorship bias.

### Gap classification (v1.0.2) — для BACKWARD триггеров

При `miss`/`adjacent` после BACKWARD — маркер в Lesson колонке:

| Маркер | Что значит | Коррекция |
|--------|-----------|-----------|
| `[gap:literal]` | Слова/идентификаторы прочитал не так | Внимательность к тексту |
| `[gap:pragmatic]` | Слова верны, intent/речевой акт нет | Переформулировка с явным уточнением |
| `[gap:strategic]` | Intent верный, larger goal пропущен | Demand-first — кому это нужно? |

При 2+ gap'ах одного типа в сессии хук инжектит предупреждение о системном рассогласовании → `/learn` (communication) + ревизия user_profile.md. Обязательно только для BACKWARD; FORWARD/PROPOSAL с accuracy=exact — не нужна.

## Definition of Done

- [ ] Траектория ведётся в SESSION.md (`### Trajectory`, каскадный лог гипотез H1..Hn)
- [ ] Предсказания логируются (`### Predictions`) и верифицируются на каждом значимом сообщении
- [ ] Gap-классификация применена при BACKWARD miss/adjacent

**Version:** 1.0.1
**Last Updated:** 2026-07-29