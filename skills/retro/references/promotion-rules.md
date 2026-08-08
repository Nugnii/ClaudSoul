# Knowledge Promotion Rules

## 5a. Search for existing knowledge

Read ALL files in `~/.claude/global-lessons/`. For each:
- Does this case CONFIRM an existing pattern/principle?
- Does this case CONTRADICT one?
- Is this case UNRELATED?

## 5b. If CONFIRMS existing knowledge → REINFORCE

Update the existing pattern/principle file:
- `confidence` += 1 (max 5)
- `confirmed_count` += 1
- `last_confirmed` = today
- Add this case to `source_cases` list
- Tell the user: "Подкрепляет существующий паттерн/принцип: [name] (confidence теперь N)"

## 5c. If CONTRADICTS existing knowledge → INVESTIGATE

Do NOT delete the old lesson. Instead:
- Compute **contradiction weight** (v1.0.9) — см. 5c.2
- Update `effective_contradicted` += weight
- Append entry в `contradiction_log`
- Для **per-speaker** pattern: обновить только `per_speaker_state[speaker]`, не глобальный счётчик
- Analyze WHY it contradicted:
  - **Old lesson was wrong** → `status: deprecated`, create replacement
  - **Old lesson needs narrower scope** → update "How to apply" with conditions
  - **Different context** → BRANCH: create new lesson with `related: [old-lesson.md]`
- Tell the user: "Противоречит [name]. Причина: [analysis]. Действие: [deprecate/narrow/branch]"

### 5c.1 Modification lineage (v1.0.8) — обязательно при любой модификации pattern/principle

Когда меняешь pattern/principle (narrow/branch/deprecate/reinforce_after_challenge/scope_widened) — добавь запись в `modification_history`:

```yaml
modification_history:
  - date: 2026-04-16
    kind: narrowed               # narrowed | branched | deprecated | reinforced_after_challenge | scope_widened
    reason: "применим только к staging, не production"
    trigger_case: case-2026-04-16-brief.md
```

Затем пересчитай `fragile`:
- Если `modification_history.length >= 3` → установить `fragile: true`
- Fragile-знание при инжекте показывается с ⚠️ маркером и НЕ автопромоется до principle

**Когда НЕ записывать:** обычный `confirmed_count++` без изменения правила — не модификация. Только реальные изменения scope/status/direction.

### 5c.2 Contradiction weight (v1.0.9) — адаптивная деградация

Вместо скалярного `contradicted_count++` вычисляется **weight** и прибавляется к `effective_contradicted`:

```
weight = source_factor × domain_factor
```

#### source_factor (по promotion_tier pattern'а)

Адаптивный, старт = 1.0. Читается из `~/.claude/hooks/state/adaptive-stats.json` через `compute_source_factor(tier)` в `adaptive-stats-lib.sh`. Пересчитывается на `/knowledge-audit`.

До 5+ patterns в системе — все tier'ы возвращают 1.0.

Если `fragile: true` → source_factor дополнительно × 1.2.

#### domain_factor (через domain graph)

Distance между `origin_domain` pattern'а и `contradiction_domain` кейса — BFS в `domains/`:

| Path length | factor | Действие при срабатывании ≥2.5 |
|-------------|--------|-------------------------------|
| 0 (same) | 1.2 | deprecate (если status уже weakened) |
| 1 | 0.9 | **narrow** — добавить constraint в How to apply + запись modification_history (kind=narrowed) |
| 2 | 0.6 | narrow |
| 3+ / unreachable | 0.3 | **branch** — создать новый pattern для другого домена, оригинал не трогать |

Функция: `get_domain_distance(origin, contradiction)` из `adaptive-stats-lib.sh`.

#### Пороги

- `effective_contradicted ≥ 1.0` → `status: weakened`
- `effective_contradicted ≥ 2.5` → action выбирается по dominant domain_factor:
  - path 0 → deprecate
  - path 1-2 → narrow + modification_history
  - path 3+ → branch + modification_history

#### Per-speaker patterns

Для `scope: per-speaker` weight считается в `per_speaker_state[speaker]`, не в глобальном `effective_contradicted`:

```yaml
per_speaker_state:
  primary:
    effective_contradicted: 1.1   # локальный для этого speaker'а
    status: weakened
  anomaly_2026-04-20_abc:
    effective_contradicted: 0.0
    status: active
```

Глобальный `status: deprecated` — только когда все speaker_id из `valid_for` переместились в `invalid_for`.

#### Запись в contradiction_log

```yaml
contradiction_log:
  - date: 2026-04-16
    case: case-2026-04-16-brief.md
    speaker: primary
    contradiction_domain: bash
    weight: 1.08
    factors: {source: 1.2, domain: 0.9}
    resulting_action: narrow
```

Append-only, не переписывать.

## 5d. If NO overlap but 2+ similar cases exist → EXTRACT PATTERN (v1.0.9 gradation)

Определить **tier** и действовать по нему:

| Tier | Критерии | Действие |
|------|----------|----------|
| **1 — auto-create** | 2+ кейсов с identical trigger + identical outcome + parent principle существует | Создать без подтверждения |
| **2 — ask** | 2+ кейсов, adjacent triggers / no parent / cross-domain | Спросить `(y/n)` |
| **3 — mandatory-ask** | Новый pattern противоречит существующему ИЛИ branching | Обязательно спросить + показать alternatives |

Create `pattern-brief-name.md` in `~/.claude/global-lessons/`:
```yaml
type: pattern
confidence: 2
confirmed_count: 2
contradicted_count: 0
last_confirmed: today
source_cases: [case1, case2]
status: active

# v1.0.9 поля
promotion_tier: 1                # 1 | 2 | 3
scope: universal                 # universal | per-speaker | mixed (auto-detect по domain)
origin_domain: "bash"            # domain из кейсов
effective_contradicted: 0.0
contradiction_log: []

# Per-speaker scope — если scope != universal
valid_for: [primary]
invalid_for: []
pending_for: []
per_speaker_state:
  primary:
    confidence: 2
    confirmed_count: 2
    contradicted_count: 0
    last_confirmed: today
    status: active

# Modification lineage (v1.0.8)
modification_history: []
fragile: false
```

Scope auto-detect:
- `domain` ∩ {communication, dialogue, agent_design} непуст → `per-speaker`
- Только технические → `universal`
- Смешанный → `mixed`

После создания — обновить adaptive stats:
```bash
source ~/.claude/hooks/adaptive-stats-lib.sh 2>/dev/null && \
  update_stats_on_promotion $PROMOTION_TIER 2>/dev/null || true
```

Tell the user: "Выделен новый паттерн: [description] (tier N, scope X)"

## 5e. If pattern works across tech/projects → PROMOTE TO PRINCIPLE

Create `principle-brief-name.md` in `~/.claude/global-lessons/`:
```yaml
type: principle
confidence: 3
```
Tell the user: "Паттерн повышен до принципа: [description]"

## Session registry update

After writing/updating knowledge, record in session registry:

```bash
# Created new case
source ~/.claude/hooks/session-registry-lib.sh 2>/dev/null && \
  sr_update_knowledge "created" "case-YYYY-MM-DD-brief-name.md" 2>/dev/null || true

# Reinforced existing knowledge
sr_update_knowledge "updated" "pattern-or-principle-name.md" 2>/dev/null || true

# Contradicted existing knowledge
sr_update_knowledge "contradicted" "pattern-or-principle-name.md" 2>/dev/null || true
```
