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
- `contradicted_count++` механически: `hooks/knowledge-counter-bump.sh <name> contradicted "<что разошлось>"`
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
- В этом поле лежат ТОЛЬКО перекройки правила (`narrowed` | `branched` | `deprecated` |
  `reinforced_after_challenge` | `scope_widened`). Провенанс подтверждений
  (`kind: reinforced`/`contradicted`, пишет `hooks/knowledge-counter-bump.sh`) с 2026-08-11
  живёт в отдельном поле `provenance_log` и на `fragile` не влияет
- Fragile-знание при инжекте показывается с ⚠️ маркером и НЕ автопромоется до principle

**Когда НЕ записывать:** обычный `confirmed_count++` без изменения правила — не модификация. Только реальные изменения scope/status/direction. В `provenance_log` руками не писать вовсе — это механическое поле счётчика.

### 5c.2 Взвешивание противоречий — снято 2026-08-28 (D90)

Здесь стояла адаптивная деградация: `weight = source_factor × domain_factor`, пороги
`effective_contradicted ≥ 1.0 / ≥ 2.5`, таблица `domain_factor` по графу доменов и запись
в `contradiction_log`.

**Замер 2026-08-28:** `effective_contradicted` и `contradiction_log` — по 0 исполняемых
файлов на 13 документов каждое; `compute_source_factor` определён и ниоткуда не вызывается.
Цепочка не исполнялась ни разу. Решение владельца — снять из спецификации, а не строить.

Противоречие весит **единицу**, счётчик целый, инкремент механический:

```
bash ~/.claude/hooks/knowledge-counter-bump.sh <name> contradicted "<что разошлось>"
```

Выбор действия — `deprecate | narrow | branch` — остаётся суждением по разбору 5c, а не
порогом. Раньше текст обещал порог; механизма под ним не было, и обещание убрано.
Канон — `knowledge/META.md`, раздел «Взвешивание противоречий».

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
