# `/narrative` — дизайн (разрыв C)

> Состояние: design v0.2 auto-first (2026-04-22). Skeleton в `skills/narrative/`. Фаза v1.5.0.

## 0. Принцип системы: одна команда на жизнь проекта

Любая ручная команда, которую пользователь должен «помнить вызвать», — дизайн-дефект. Человеческая память не ресурс, на который можно рассчитывать, а дефицитная штука, которую система обязана беречь.

Единственная irreducible команда в ClaudSoul — `./install.sh` (и её разовый ре-ран после обновлений). Всё остальное — event-driven: хуки, cron, session lifecycle, внутрисессионные сигналы. Manual-invocation (`/narrative`, `/retro`, `/learn`, `/save`) остаётся как **override/debug**, а не как основной путь.

`/narrative` разрабатывается сразу auto-first. Калибровочная фаза «сначала ручные narrative» — отменена: калибровка не случится, если триггера нет.

## 1. Проблема

§12 architecture.md разрыв C — «Narrative identity (through-line)»:

> «Где я, куда иду, откуда пришёл» — непрерывная история.
> SESSION.md растёт, но «сюжета» нет. Каждая сессия перезапускает ориентацию.

Симптомы:
- Новая сессия читает SESSION.md last entry + project CLAUDE.md и знает **состояние**, но не **направление**.
- H1..Hn траектории живут в SESSION.md, но к ним надо проскроллить; first 3 turns новой сессии часто содержат «а что мы вообще делали» intent-gap.
- Knowledge delta (какие принципы/паттерны появились или ушли за окно) нигде не агрегируется — пропадает между сессиями.

Противоречие с human cognition: у человека through-line — непрерывный фон, он не пере-читывает историю перед каждой задачей. У агента фон — пустой, ре-сборка каждой сессии с нуля.

## 2. Гипотеза

**H18:** Одно-абзацный narrative через `/narrative` в первых 3 turn'ах новой сессии снижает intent-gap rate (`BACKWARD` + `pragmatic`/`strategic` gap классы) по сравнению с сессиями без narrative.

Как мерить:
- `reformulation-tracker` пишет BACKWARD-события с gap-типом.
- Считаем: в первых 3 turn'ах сессии — rate BACKWARD / total_turns.
- Сравниваем распределение «с инжектом narrative в startup context» vs «без».

Блокер H18: metric window ≥30 сессий после включения periodic narrative.

## 3. Скоуп v1.5.0

### Включено

**Auto-trigger в `session-start` хуке (основной путь).** На каждом старте сессии хук:
1. Проверяет условия: gap с last session в Session Registry ≥ 8 часов ИЛИ сессий с last narrative ≥ 3.
2. Если условие выполнено — вызывает compose-helper, получает абзац.
3. Инжектит абзац в `additionalContext` как `📖 Where we are:` — агент видит его в startup, пользователь не делает ничего.
4. Записывает в `.claude-docs/narrative.md` (append).

**Skill `/narrative` как override.** Force-regen по требованию (`--entries=N`, `--window=Xw`, `--dry-run`). Не основной путь.

**Compose-helper** (`skills/narrative/compose.sh` или `.py`) — pure функция входных артефактов в абзац. Используется и хуком, и skill'ом.

### Не включено (v1.6+)

- **Periodic auto-run** раз в 10 сессий через session-collector — не нужен, session-start покрывает main use-case.
- **Cross-domain narrative** (когда через несколько проектов идёт один through-line) — v1.7+, требует agregации cross-project. Out of scope.

### Анти-скоуп (явно НЕ)

- Narrative не заменяет SESSION.md — это production, SESSION.md это raw log. Regen possible из SESSION.md, обратно нет.
- Narrative не правит SESSION.md (read-only для источника).
- Narrative не изобретает — только синтезирует из уже существующих артефактов (trace-ability обязательна).

## 4. Flow

```
/narrative [--entries=N] [--window=2w]
│
├─ 1. Collect sources
│   ├─ SESSION.md tail N entries (parse by ## [date] headers)
│   ├─ git log --oneline --since=<window>
│   ├─ global-lessons/case-*.md,pattern-*.md mtime in window
│   └─ H_n chain из последней ### Trajectory секции
│
├─ 2. Extract signals
│   ├─ Dominant theme — модальный тег доменов в case mtime
│   ├─ Direction shift — если H_n ≠ H_{n-1} в последних 3 H → «pivot»
│   ├─ Technical arc — git log subjects: `feat` vs `fix` vs `refactor` vs `docs`
│   └─ Unfinished threads — «Next steps» из SESSION.md, которые не в git log
│
├─ 3. Compose narrative (3-5 sentences)
│   ├─ Предложение 1: «откуда» — опорный commit/case X дней назад
│   ├─ Предложение 2-3: «где» — текущая активная задача + dominant theme
│   ├─ Предложение 4: «куда» — unfinished threads + активная H_n
│   └─ (опц) Предложение 5: pivot / тензия / открытый вопрос
│
├─ 4. Write outputs
│   ├─ .claude-docs/narrative.md (append `## YYYY-MM-DD HH:MM` + paragraph)
│   └─ <project>/CLAUDE.md §«Current narrative» (replace-in-place between markers)
│
└─ 5. Report
    ├─ Показать абзац
    └─ Показать trace: (commit hashes, SESSION entries, cases) — откуда
```

## 5. Guardrails

| Риск | Guardrail |
|------|-----------|
| Narrative галлюцинирует события | Trace-ability: рядом с абзацем — список (commits + SESSION entries + cases) из которых синтез; если пусто — abort с «too little history» |
| Narrative перезаписывает себя, теряя историю | `.claude-docs/narrative.md` — append-only; в CLAUDE.md — между markers `<!-- narrative-start -->` ... `<!-- narrative-end -->`, замена только внутри, старые narrative уходят в append-only файл |
| Narrative расходится с SESSION.md | Генерация только из SESSION.md + git + cases (read-only источники), без собственных оценок |
| Пользователь хочет отказаться от narrative | Флаг `--dry-run` показывает, не пишет; `--off` в CLAUDE.md отключает для проекта |
| v1.6 автосбор запустится, не проверив калибровку | Periodic job в v1.6 читает `.claude-docs/narrative.md` — если архив <5 manual narratives, periodic пропускается |

## 6. Связь со слоями

- **L1 Persistence** — читает SESSION.md, git log. Пишет в `.claude-docs/narrative.md` и CLAUDE.md.
- **L2 Knowledge** — читает global-lessons delta. Narrative — не knowledge само по себе (не case/pattern/principle), это compose-артефакт.
- **L4 Thought Trajectory** — H-цепочка из SESSION.md — первичный вход. Narrative буквально = synthesis над H_n.
- **L5 Meta-cognition** — H18 измерение — функция narrative'а.

Новый мост: **L1↔L4 через /narrative** — чтение L1 артефактов (SESSION.md, git) → синтез L4 траектории в compose-форме. Отличается от существующих: другие мосты работают реактивно на событие, narrative — пассивный сборщик по запросу.

## 7. Open questions

1. **Формат абзаца** — free text или структурированный (from/here/toward + tensions)? Stance: free text, 3-5 предложений, без шаблона — шаблон превратит narrative в bullet list.
2. **Где хранить H-цепочку для мульти-сессионного narrative** — сейчас она в SESSION.md внутри последней entry. Для through-line нужна агрегация H_n across N entries. Решить при первой реализации: либо parse из SESSION, либо отдельный `.claude-docs/trajectory.md`.
3. **Что делать если SESSION.md пустой** — первая сессия проекта не имеет narrative. Вывод: abort с сообщением «need ≥2 sessions to compose narrative».

## 8. DoD для v1.5.0 (auto-first)

- [ ] `skills/narrative/compose.sh` (или `.py`) — pure helper: источники → абзац + trace
- [ ] `hooks/session-start.sh` расширен: gap/N-sessions trigger → compose → inject `📖 Where we are:` в `additionalContext`
- [ ] `install.sh` подключает session-start хук в HOOKS_CONFIG (если ещё не подключён)
- [ ] `skills/narrative/SKILL.md` описывает `/narrative` как override, не основной путь
- [ ] `.claude-docs/narrative.md` append-only; маркеры в project CLAUDE.md template
- [ ] Тесты compose-helper'а на fixture SESSION.md (пустой, 1 entry, 3+ entries, missing sections)
- [ ] Тесты trigger-логики хука: gap detection, N-sessions counter, override flag respect
- [ ] Документация в `docs/architecture.md` §12 разрыв C — статус «auto-trigger в session-start v1.5.0»
- [ ] `rules/CLAUDE.md` § Self-Learning — добавить «auto-invocation — первый класс, manual — override»

**Status:** design v0.2 (auto-first). Skeleton SKILL.md требует переписывания под override-роль. Реализация compose + hook wiring — следующий шаг.
