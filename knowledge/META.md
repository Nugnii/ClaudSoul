# Knowledge System — Meta Rules

> Правила эволюции знаний ClaudSoul v0.3

## Область применения

Система знаний **не ограничена разработкой**. Знания могут быть о чём угодно: технологии, бизнес, коммуникация, исследования, управление. Все правила ниже применяются одинаково независимо от домена.

## Два контура, шесть типов

Контур 1 — операционный (обучение на своём опыте):

### Layer 1: Cases (Кейсы)
Конкретный случай: что произошло, как разрешилось.
File prefix: `case-`
→ Raw material. Полезен для конкретной ситуации.

### Layer 2: Patterns (Паттерны)
Повторяющееся наблюдение, выведенное из 2+ кейсов.
File prefix: `pattern-`
→ "Когда X, обычно причина Y". Применяется в похожих ситуациях.

### Layer 3: Principles (Принципы)
Фундаментальное правило, выведенное из паттернов. Не зависит от домена/проекта.
File prefix: `principle-`
→ "Всегда делай X перед Y". Применяется везде.

Контур 2 — энциклопедический (обучение из внешних источников, v1.1.0+):

### Entity (Сущность)
Конкретный объект реального мира: человек, компания, продукт, концепция, событие, место, произведение.
File prefix: `entity-`
Шаблон: `templates/entity.md.tmpl`
→ Атрибуты со своим confidence и provenance, траектория во времени, связи с операционным контуром через `edges`.

### Fact (Факт)
Атрибут сущности или самостоятельное утверждение о мире (event/rule/definition).
File prefix: `fact-`
Шаблон: `templates/fact.md.tmpl`
→ Temporal validity (valid_from/valid_until), provenance списком, привязка к сущностям через `entity_refs`.

### Relation (Связь)
Типизированная связь между двумя сущностями (role_in, works_at, knows, created, contradicts...).
File prefix: `relation-`
Шаблон: `templates/relation.md.tmpl`
→ directed/bidirectional, temporal validity, провенанс источников.

Два контура взаимодействуют через Domain Graph и `edges` (entity.edges → case/pattern/principle).

## Promotion rules

```
Case (1 случай) → Pattern (2+ похожих кейса) → Principle (устойчивый паттерн)
```

- Case → Pattern: тот же вывод подтверждён в 2+ независимых ситуациях, ИЛИ 1 кейс с impact ≥ 4 → кандидат в паттерн (confidence=1, требует подтверждения)
- Pattern → Principle: работает across доменов/проектов
- При промоушене — кейсы НЕ удаляются, а ссылаются на паттерн/принцип

## Precedence chain — порядок применения правил

Когда несколько правил срабатывают одновременно — порядок следования:

```
1. demand-before-supply         (зачем это нужно — потребность)
2. continuous-learning-gated-action  (как решаем — вариативность и согласие)
3. verify-before-acting / false-obviousness  (проверяем факты и интерпретации)
4. completeness-over-speed      (scope реализации — полно, а не частично)
5. inside-out-blindness checklist  (после дизайна — чеклист слепых зон)
```

**Почему этот порядок:**
- Правила выше по цепи задают **рамку**, правила ниже — **исполнение внутри рамки**. Нельзя применять completeness до gated-action: рискуешь расширить scope без согласия.
- Каждое следующее правило предполагает что предыдущее уже отработало. Если на шаге 2 вариативность неразрешена — шаги 3-5 ждут.
- Цепь не строгая очередь: правила 3-5 могут применяться параллельно, но ДО них 1-2 должны отработать.

**Когда цепь нарушается — это сигнал.** Если completeness сработало без demand — вероятно, решаем не ту задачу. Если tool action принят без gated-action — возможно, проигнорирована вариативность.

## Метаданные знания

```yaml
# Обязательные
confidence: 1-5           # Уверенность (растёт с подтверждениями)
impact: 1-5               # Серьёзность последствий при игнорировании
intensity: 0-5            # Surprise factor: 0=ожидаемо, 5=полная неожиданность
confirmed_count: N
contradicted_count: N
last_confirmed: date
source_cases: []
source_session: ""        # (v1.11) UUID сессии записи = $CLAUDE_CODE_SESSION_ID на момент
                          #   /learn или /retro. Переменной нет → оставить ПУСТЫМ, не выдумывать:
                          #   выдуманный UUID хуже пустого, он выглядит как данные.
                          #   Ретроспективно не восстанавливается — у знаний до v1.11 пусто.
                          #   Зачем: «пережило N независимых сессий» сейчас считается прокси по
                          #   уникальным датам в source_cases; с этим полем станет точным.
                          #   Дату здесь НЕ дублируем — она уже в имени файла и last_confirmed.
status: active|weakened|deprecated|branched

# Контекстные якоря (универсальные)
domain: []                 # Область: next.js, b2b_sales, cognitive_science...
situation: ""              # Тип ситуации: deploy, negotiation, research...
trigger: ""                # Что активирует: error, deadline, contradiction...
stakes: ""                 # Что на кону: data_loss, deal_loss, trust_erosion...
actors: []                 # Кто вовлечён: system, client, team...
environment: ""            # Среда: multi_session, production, ci_cd, local_dev...
circumstances: ""          # Условия/ограничения: no_rollback, armed, team_unavailable...
purpose: ""                # Зачем: hotfix, new_feature, escape, learning...
method: ""                 # Как: ci_cd, manual_scp, bare_hands, automated...
tags: []                   # Свободные ассоциативные маркеры

# Demand-компоненты (кому и зачем нужно это знание)
need: ""                   # Какую потребность решает: avoid_regression, speed_up, reduce_risk,
                           #   prevent_misunderstanding, save_time, improve_quality...
urgency: ""                # Когда применять: immediate (прямо сейчас, блокер),
                           #   next_session (при следующем релевантном контексте),
                           #   when_relevant (когда контекст совпадёт),
                           #   background (полезно знать, не срочно)
availability: ""           # Есть ли альтернативы: unique (только это знание спасёт),
                           #   has_alternatives (есть другие способы),
                           #   common_knowledge (очевидно опытному специалисту)

# Связи
related: []                # Связанные знания
edges: []                  # Типизированные: caused_by, similar_to, contradicts,
                           #   led_to, specializes, generalizes

# Modification lineage (v1.0.8) — только для patterns/principles
# История всех модификаций знания: narrowing, branching, deprecation attempts
modification_history: []   # Каждая запись:
                           #   - date: YYYY-MM-DD
                           #     kind: narrowed|branched|deprecated|reinforced_after_challenge|scope_widened
                           #     reason: одна строка почему
                           #     trigger_case: case-YYYY-MM-DD-*.md (что спровоцировало)
fragile: false             # Авто-флаг: true когда modification_history содержит ≥ 3 записей

# Происхождение и направление причинности (v1.14.5)
#
# Две РАЗНЫЕ оси, их легко перепутать, поэтому описаны рядом.
origin: ""                 # КАК инсайт родился. Заполняется /learn Step 2b.
                           #   solo             — в одиночку, из своей работы
                           #   co-cognition     — в совместном обсуждении с собеседником
                           #   trajectory_pivot — из поворота в траектории мысли
                           # Поле живёт в базе с апреля и используется в 58 знаниях, но до
                           # v1.14.5 в этой спецификации отсутствовало — схема расходилась
                           # с практикой. Значения писались и в кавычках, и без; канон —
                           # БЕЗ кавычек. Встречалось постороннее `interlocutor_correction`;
                           # такой случай это `solo` (знание из коррекции, не из со-мышления).

preceded_artifact: ""      # ЧТО БЫЛО РАНЬШЕ — знание или артефакт, который на него ссылается.
                           #   yes  — знание существовало ДО того, как построили хук/скилл,
                           #          и построили его ИЗ знания
                           #   no   — артефакт был раньше, знание записано после и ссылается
                           #          на него как на обоснование
                           #   n/a  — артефакта нет, вопрос не стоит
                           #
                           # Зачем отдельное поле. Измерение 2026-07-29: из 8 хуков, которые
                           # ссылаются на знания, ПО ФАКТУ ноль построены из знания,
                           # существовавшего раньше — включая три, где ссылки не было даже
                           # в первом коммите. То есть ссылка в коде измеряет не применение
                           # знания, а поиск обоснования задним числом. Отвергнутый вариант
                           # `embodied_in` («во что воплотилось») считал бы ровно эти ссылки
                           # и давал бы красивую, но неверную цифру.
                           #
                           # Имя выбрано так, чтобы не путалось с `origin`: та ось про способ
                           # рождения инсайта, эта — про порядок во времени относительно кода.

# Promotion & scope (v1.0.9) — только для patterns/principles
promotion_tier: 2                # 1=auto-create, 2=ask, 3=mandatory-ask (см. «Promotion gradation»)
scope: universal                 # universal | per-speaker | mixed
origin_domain: ""                # Домен из которого pattern был промоутнут (для domain_factor)

# Per-speaker state (v1.0.9) — только для scope: per-speaker | mixed
valid_for: []                    # speaker_ids где pattern подтверждён
invalid_for: []                  # speaker_ids где pattern зафиксировано противоречил
pending_for: []                  # speaker_ids где видели, но не хватило данных
per_speaker_state:               # Per-speaker счётчики и статус
  {}                             #   primary:
                                 #     confidence: 3
                                 #     confirmed_count: 5
                                 #     contradicted_count: 0
                                 #     last_confirmed: 2026-04-16
                                 #     status: active

# Adaptive degradation (v1.0.9)
effective_contradicted: 0.0      # Взвешенный counter; триггерит weakened (≥1.0) / deprecated (≥2.5)
contradiction_log: []            # Append-only, каждая запись:
                                 #   - date: YYYY-MM-DD
                                 #     case: case-*.md
                                 #     speaker: primary | anomaly_*
                                 #     contradiction_domain: string
                                 #     weight: 1.04
                                 #     factors: {source: 1.0, domain: 1.2}
                                 #     resulting_action: weaken|narrow|branch|deprecate|none

# Blocker-tier (v0.3) — только для patterns/principles с подтверждённым knowledge-action gap
blocker: false                   # true = pre-action hook проверяет detection_signals
blocker_reminder: ""             # Одна строка — что напомнить при срабатывании.
                                 # Показывается агенту как часть silent additionalContext.
                                 # Явное поле, а не извлечение из «How to apply» — избегаем
                                 # heuristic parsing, оставляем контроль у автора pattern'а.
detection_signals: []            # Список именованных сигналов. Формат — см. раздел
                                 # «Blocker-tier knowledge (v0.3)» ниже.

# Заявка на инженерную эскалацию (v0.3, документировано 2026-07-31 — D46)
# Смысл: знание уровня blocker подтверждается снова и снова, значит нынешней защиты мало
# и назрел следующий уровень. Заявку выдвигает сама система в недельном дайджесте.
escalation_threshold: 0          # confirmed_count, при котором заявка открывается.
                                 # 0 или отсутствие поля = заявки нет.
escalation_opened: ""            # YYYY-MM-DD, ставится МЕХАНИЧЕСКИ при первом
                                 # срабатывании (knowledge-audit-digest.sh). Не править
                                 # руками: это точка отсчёта возраста заявки.
escalation_hint: ""              # Что именно построить. Одна-две фразы, конкретно.
escalation_mechanism_needed: true # false при закрытии заявки. Оставленный `true` у
                                 # закрытой заявки вводит в заблуждение — так три месяца
                                 # висел флаг у `pattern-shell-portability` после того,
                                 # как её подняли до blocker-tier.

# Почему возраст, а не счётчик подтверждений. До 2026-07-31 единственным меняющимся
# числом в разделе эскалации был `confirmed_count`. Он измеряет, насколько знание
# ПОДКРЕПИЛОСЬ, а не насколько долго по нему не действуют, — и растущее число читалось
# как «всё под контролем». Замер: строка эскалации стояла дословно одинаковой в 13
# дайджестах подряд (W19…W31). Возраст заявки растёт от БЕЗДЕЙСТВИЯ и роняет проверку
# `scripts/escalation-age.sh` (реестр замеров, период 7).
```

### Modification lineage (v1.0.8)

Для pattern/principle фиксируется append-only история изменений. Когда знание сужают, ветвят, или снова подтверждают после challenge — добавляется запись.

**Цель каскадности:** пара `confirmed_count / contradicted_count` — скаляр, он теряет информацию о том, как знание эволюционировало. «3 подтверждения, 2 противоречия» может означать стабильно полезное правило С оговорками или расшатанный паттерн, который вот-вот развалится. Modification_history различает эти сценарии.

**Правило fragile:**
- 3+ модификаций → автоматически `fragile: true`
- Fragile знание показывается при инжекте с маркером `⚠️ fragile — N модификаций, сверь контекст`
- Fragile pattern не повышается до principle (автопромоушен блокируется)
- Fragile — это не deprecated: знание ещё работает, но его scope уже много раз перекраивали, применять надо с особой осторожностью

**Когда добавлять запись в modification_history:**
- `narrowed` — сузили How to apply / scope
- `branched` — создали branch для другого контекста (ссылка в `related`)
- `deprecated` — сам акт депрекации (одной записью)
- `reinforced_after_challenge` — был challenge через /retro, но знание устояло и подкрепилось
- `scope_widened` — расширили применимость (напр. после cross-domain подтверждения)

**Когда НЕ добавлять:**
- Обычный `confirmed_count++` без изменения правила — это не модификация
- Правка опечатки / форматирования

Скилл `/retro` и `/learn` при изменении pattern/principle **обязаны** добавить запись в modification_history и пересчитать `fragile`. Инкремент счётчиков — механический, через `hooks/knowledge-counter-bump.sh`, а не правкой файла руками: текстовое правило «не забудь обновить счётчик» здесь уже один раз не сработало (`contradicted_count` = 0 во всех 265 знаниях к v1.10).

В `modification_history` `source_session` не дублируется: у 31 записи из 32 есть `trigger_case`/`by_case`, то есть до сессии один переход через кейс.

### Правило hold-out (v1.11)

**Множества «измеряемое» и «инжектируемое» не пересекаются.**

Знание о мире фальсифицирует мир: тест краснеет, сборка падает, собеседник поправляет. Знание о собственном поведении, показанное экземпляру, перестаёт быть описанием и становится инструкцией — модель исполняет контекст, а не сверяется с ним. Инжект производит поведение, поведение записывается как подтверждение, петля замыкается без внешнего арбитра.

Практические следствия:
- Черта, попавшая в инжект, немедленно выбывает из измеряемых и переходит в разряд интервенции. Её эффект меряется только по логам исхода «до/после», не счётчиком подтверждений.
- Отчёт «Знание о себе» (`_audit-history/audit-*.md`) сознательно **не** попадает в `audit-hint.txt` и не читается активатором. Это проверяемо: все потребители базы обходят её на глубину 1 (`"$DIR"/pattern-*.md`, `find -maxdepth 1`, `.glob("*.md")`), рекурсивных обходов нет.
- Сегодня под правило подпадает `pattern-inside-out-blindness`: инжектится blocker-tier (237 срабатываний из 258) и одновременно накапливает подтверждения, которые пишет получивший инжект экземпляр. Его `confirmed_count: 36` **нельзя** приводить как свидетельство устойчивости черты.

### Promotion gradation (v1.0.9)

Ранее было правило «при промоушене case → pattern ВСЕГДА спрашивать подтверждение». Это давало избыточное трение, когда случай очевиден. Замена — градация по tier'ам:

| Tier | Критерии | Действие | Коэффициент source (baseline) |
|------|----------|----------|-------------------------------|
| **1 (auto-create)** | 2+ кейса с identical trigger + identical outcome + существует parent principle, на который можно `specializes` | Создать pattern без подтверждения. В отчёте указать: «Создан pattern X — 2 кейса Y/Z, specializes principle W» | 1.0 (адаптируется) |
| **2 (ask)** | 2+ кейса, но триггеры adjacent (не identical) ИЛИ parent principle отсутствует ИЛИ cross-domain | Предложить `(y/n)`: «Создать pattern?» | 1.0 |
| **3 (mandatory-ask)** | Новый pattern **противоречит** существующему (contradicted edge) ИЛИ создаёт branching | Обязательно спросить, обязательно объяснить alternatives | 1.0 |

Tier фиксируется в `promotion_tier` при создании — используется для адаптивной деградации (см. ниже).

### Scope: universal vs per-speaker (v1.0.9)

Критическое уточнение **v1.0.9**: паттерн — не универсальная вещь. Для собеседника А может быть паттерном, для Б — нет. И даже для А со временем может перестать быть паттерном.

| scope | Когда | Поведение при противоречии |
|-------|-------|----------------------------|
| **universal** | Технические паттерны (bash, next.js, ci_cd — не зависят от личности) | Глобальная деградация по weight-формуле |
| **per-speaker** | Коммуникативные паттерны (domain содержит `communication`, `dialogue`, `agent_design`) | Противоречие меняет `per_speaker_state[speaker_id]`, а не глобальный status |
| **mixed** | Паттерн может быть и техническим, и коммуникативным (пограничные) | По ситуации: если противоречие в communication-контексте → per-speaker; иначе universal |

**Auto-detect scope при создании:**
- `domain` ∩ {`communication`, `dialogue`, `agent_design`} непуст → `scope: per-speaker`
- `domain` содержит только технические (`next.js`, `bash`, `hooks`, `ci_cd`, ...) → `scope: universal`
- Пересечение и то и другое → `scope: mixed`

**Поведение per-speaker pattern:**
- При создании → `valid_for: [current_speaker_id]`, `per_speaker_state[current].confidence: 1`
- Противоречие от speaker из `valid_for` → обновляется только `per_speaker_state[speaker].contradicted_count`, не глобальный
- Все `valid_for` ушли в `invalid_for` → глобальный `status: deprecated`
- Подтверждение от speaker, которого нет в `valid_for` — пост добавляется в `pending_for`; через 2+ подтверждения — в `valid_for`
- Промоушен в universal — только когда `valid_for` содержит **2+ разных** speaker_id, подтверждённых разными сессиями

### Adaptive degradation (v1.0.9)

Противоречие не всегда весит 1. Его вес зависит от двух адаптивных множителей (speaker обрабатывается через scope, а не множителем).

```
weight = source_factor × domain_factor
effective_contradicted += weight
```

#### source_factor (по tier'у pattern'а)

Старт: все tier'ы = 1.0. После 5+ patterns в системе — `/knowledge-audit` пересчитывает на основе `natural_rate`:

```
natural_rate[t] = weakened_in_tier[t] / total_in_tier[t]
source_factor[t] = natural_rate[t] / natural_rate[2]     # tier 2 = baseline
# clamped to [0.3, 2.0]
```

Логика: если auto-created patterns (tier 1) на практике чаще ослабевают — система сама увеличит их source_factor, то есть будущие противоречия будут «бить сильнее». Если tier 3 (mandatory-ask) почти не ослабевают — фактор снизится, их труднее раскачать.

Состояние: `~/.claude/hooks/state/adaptive-stats.json`.

#### domain_factor (через domain graph)

Расстояние между `origin_domain` pattern'а и `contradiction_domain` кейса в графе `domains/`:

| Path length | factor | Действие при срабатывании порога |
|-------------|--------|----------------------------------|
| 0 (same domain) | 1.2 | weaken → при ≥2.5 → deprecate |
| 1 (1 edge) | 0.9 | narrow: добавить запись в modification_history (kind=narrowed), сузить scope |
| 2 (2 edges) | 0.6 | narrow |
| 3+ или unreachable | 0.3 | branch: создать новый pattern для другого домена, старый оставить нетронутым |

#### Пороги

- `effective_contradicted ≥ 1.0` → `status: weakened`
- `effective_contradicted ≥ 2.5` → действие выбирается по domain distance: deprecate | narrow | branch
- При **narrow/branch** — обязательно запись в `modification_history` (см. v1.0.8)

#### Fragile + adaptive

`fragile: true` при 3+ `modification_history` записей — блокирует промоушен в principle и дополнительно увеличивает `source_factor × 1.2` при следующих противоречиях.

### Blocker-tier knowledge (v0.3)

Некоторые patterns достигают `confidence: 5` и `confirmed_count ≥ 9`, но **продолжают срабатывать** в реальной жизни. Это значит — знание накапливается, но не используется. Обычная retrieval-цепочка (knowledge-activator + semantic search) не долетает до действия: либо anchor match не происходит, либо score проигрывает конкуренции с более «громкими» знаниями.

Для таких pattern'ов существует явный `blocker: true` флаг. Blocker-tier pattern проверяется отдельным хуком **перед** Edit/Write/Bash действием, independently от обычной retrieval цепочки.

#### Когда помечать pattern как blocker

- `confirmed_count ≥ 5` (устойчивое повторение, не просто несколько кейсов)
- Существует **свежий** knowledge-action gap: новое срабатывание уже после того как pattern в базе с высокой confidence (т.е. retrieval не сработал)
- Срабатывания происходят в **распознаваемых** ситуациях: Edit конкретного класса файлов, Bash конкретной команды, prompt содержит конкретную фразу. Если pattern срабатывает «где угодно без явного триггера» — blocker не спасёт, нужна другая работа со структурой знания

**НЕ делать автоматически по `confirmed_count`.** Решение явное — в ответ на подтверждённый gap, не на число подтверждений. Это защита от избытка blocker'ов (каждый blocker — cost на каждом PreToolUse).

#### Schema

```yaml
blocker: false               # По умолчанию для всей базы
detection_signals: []        # Список сигналов. Хотя бы один matched →
                             # pattern инжектится в additionalContext перед действием
```

#### Detection signals — формат

Detection signals хранятся как **JSON внутри YAML block literal** (`|`). Это компромисс: YAML фронтматтер для метаданных, но сами сигналы — JSON, чтобы hook мог парсить их через `jq` без внешних YAML-зависимостей.

```yaml
blocker: true
detection_signals: |
  [
    {
      "name": "long_lived_markdown_doc_edit",
      "all_of": [
        {"tool_matches": ["Edit", "Write"]},
        {"file_path_regex": "^.*/(PLAN|SESSION|README|architecture|roadmap)(\\.md|/.*\\.md)$"},
        {"file_size_min_lines": 300}
      ]
    },
    {
      "name": "destructive_bash_on_shared_state",
      "all_of": [
        {"tool_matches": ["Bash"]},
        {"any_of": [
          {"tool_input_contains": "rm -rf"},
          {"tool_input_contains": "git push --force"}
        ]}
      ]
    }
  ]
```

**Базовые матчеры:**

| Матчер | Значение | Применяется к |
|--------|----------|---------------|
| `tool_matches` | массив tool names | текущий tool_use |
| `file_path_regex` | regex (POSIX ERE) | `tool_input.file_path` |
| `file_size_min_lines` | число | `wc -l` файла (0 если не существует) |
| `prompt_contains` | substring | последний user prompt в сессии |
| `tool_input_contains` | substring | JSON-stringified `tool_input` |

**Композиторы:** `all_of` (все matched), `any_of` (хотя бы один). Вложенность разрешена (один уровень достаточен).

**Почему JSON block, а не native YAML:** pure-bash hooks не имеют надёжного YAML-парсера (нет `yq`, нет PyYAML). Вместо написания парсера — делегируем парсинг `jq`. Экстракция блока из YAML тривиальна (`awk`).

#### Ответ — silent по умолчанию

Хук `blocker-tier-check.sh` при срабатывании инжектит **silent `additionalContext`** — не `permissionDecision: "ask"`. Агент читает сигнал, корректирует внутренне, без внешнего output — если коррекция не меняет действие значимо.

Формат инжекта:
```
🛑 Blocker: {signal_name}
Pattern: {pattern_name} (confirmed {N}×, confidence {C})
{blocker_reminder}
```

Visible reaction — только если pattern реально меняет планируемое действие или требуется genuine clarification. См. `feedback_silent_correct_decisions.md` — **раздувание/шум — это failure mode**, не соответствие.

Исключение: destructive действие где reversal дорог/невозможен (`rm -rf /`, `git push --force` на main). Там `permissionDecision: "ask"` оправдан, но это выходит за рамки blocker-tier — это уже domain `bash-cost-detector`.

#### Throttle

Один и тот же `(file, pattern)` сигнал инжектится **не чаще чем раз за сессию**. Состояние: `~/.claude/hooks/state/blocker-fired-${SESSION_ID}.jsonl`. Переоткрытие сессии — сброс.

Resonance: если pattern A сработал в файле X, и через 5 минут снова — второй раз инжекта не происходит. Если тот же pattern в файле Y — инжектится (другой ключ).

#### Cross-reference

Механизм реализован в:
- `hooks/detection-signals-lib.sh` — pure-функция `ds_evaluate` (матчеры, композиторы)
- `hooks/blocker-tier-check.sh` — PreToolUse hook, scan blocker-tier, throttle, инжект

### Reliability (надёжность)

Неограниченный параметр, растущий с каждым подтверждением:

```
reliability = confirmed_count - contradicted_count
```

В отличие от confidence (1-5, качественная шкала типа), reliability — количественная мера, основанная на накопленных доказательствах. Знание, подтверждённое 50 раз, надёжнее подтверждённого 5 раз — reliability это отражает, confidence нет.

### Приоритет

```
priority = impact × (1 + ln(1 + max(0, reliability)))
```

Логарифм: первые подтверждения весят больше (разница между 0 и 5 важнее, чем между 50 и 55), но рост не ограничен.

## Источники знаний

### Технические (из ошибок и решений)
Извлекаются через /retro после ошибки или нетривиального решения.

### Коммуникативные (из диалога)
Извлекаются из взаимодействия с собеседником:
- **Intent gap** — запрос ≠ реальное намерение
- **Decision pattern** — из какого набора вариантов и почему выбран этот
- **Satisfaction signal** — реакция на результат (подтверждение, корректировка, молчание)

### Success cases (из удачных решений)
Не только ошибки. Удачные стратегии тоже записываются как кейсы:
```yaml
type: case
outcome: success           # ← отличие от обычного кейса
what_worked: "описание стратегии"
why_worked: "гипотеза почему"
```

## Entity Knowledge (Контур 2)

Полная спецификация: `docs/entity-knowledge.md`. Ниже — только правила, релевантные метауровню.

### Confidence по типу источника

| source_type | Базовый вес | Примеры |
|-------------|-------------|---------|
| self-report | 1 | "Я знаю Python" |
| document | 2 | PDF, описание, спецификация |
| third-party | 2 | "Иван — ведущий разработчик" (от коллеги) |
| behavioral | 3 | Вопросы в чате, код, действия, реакции |
| cross-reference | 4 | Подтверждено 2+ независимыми источниками разного типа |

Расчёт confidence факта/атрибута:
```
confidence = min(5, mean(source_weights) + bonus)
bonus = +1 если 2+ независимых источника разных типов подтверждают
```

### Противоречия как сигнал (не ошибка)

При расхождении источников (например, `stated_level: senior` vs `inferred_level: junior`):
- НЕ перезаписывать — сохранить оба значения в `contradiction:` блоке
- Повышает "интересность" сущности (аналог intensity в операционном контуре)
- Может стать кейсом: расхождение заявленного и реального → паттерн поведения → entity.edges → pattern-*.md

### Дедупликация сущностей

Перед созданием нового `entity-*.md`:
1. Проверить существующие entity с совпадающим `name`, `aliases`, или доменом
2. Если совпадение — обогатить существующую сущность (добавить attributes, sources)
3. Если неясно — создать новую с `edges: [similar_to: candidate.md]` и пометить `status: merged_candidate`

### Привязка к операционному контуру

Entity/fact/relation связываются с case/pattern/principle через поле `edges` тем же механизмом, что и операционные знания:
- `edges: [similar_to: pattern-X.md]` — сущность проявляет известный паттерн
- `edges: [caused_by: case-Y.md]` — конкретный инцидент сформировал это знание
- `edges: [applied_to: principle-Z.md]` — принцип проявляется на этой сущности

## Knowledge evolution

### Reinforcement (Подкрепление)
When a new case CONFIRMS an existing pattern/principle:
- confidence += 1 (max 5)
- confirmed_count += 1
- last_confirmed = today
- Add case to source_cases
- DO NOT create a new lesson — update the existing one

### Contradiction (Противоречие)
When a new case CONTRADICTS an existing lesson:
- contradicted_count += 1
- If contradicted_count >= confirmed_count → status: weakened
- DO NOT immediately delete — investigate WHY it contradicted
- Possible outcomes:
  a) The old lesson was WRONG → status: deprecated, create new one
  b) The old lesson needs SCOPING → narrow its "How to apply" conditions
  c) The context was different → BRANCH (see below)

### Branching (Ветвление)
When a lesson is true in context A but false in context B:
- Keep the original with narrowed scope
- Create a branch: same topic, different conditions
- Link them: `related: [original-lesson.md]`

### Decay (FSRS-adapted)
```
stability = base_stability × (1 + confirmed_count × 0.5) × impact_factor
interval_days = stability × ln(desired_retention) / ln(0.9)
next_review = last_confirmed + interval_days

base_stability = 7 дней
impact_factor = 1.0 + (impact - 1) × 0.25
desired_retention = 0.9
```
- Knowledge past next_review → flag for review
- Lessons with contradicted_count > confirmed_count → status: weakened
- Weakened lessons are still read but shown with ⚠️ caveat

## Принцип неопределённости

**Любой вывод может быть ошибочным.** Это касается:
- Извлечённых правил (совпадение ≠ закономерность)
- Модели собеседника (интерпретация ≠ реальность)
- Предсказаний (совпало ≠ понял)

Коммуникативные знания дополнительно зависят от **конкретного собеседника** — одно мнение не является универсальным правилом. Confidence для коммуникативных паттернов ограничен 2 до подтверждения от разных собеседников.

## When processing /retro results

After writing a case, ALWAYS:
1. Search existing patterns/principles for overlap
2. If overlap found → reinforce (update confidence) or contradict (investigate)
3. If no overlap but 2+ similar cases exist → extract a pattern
4. If pattern is domain/project-agnostic → promote to principle
5. Check for communication insights: was there an intent gap, decision pattern, or satisfaction signal?
6. State the extracted knowledge explicitly to the user
