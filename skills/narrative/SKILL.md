---
name: narrative
description: "Override / force-regen для through-line brief проекта. Основной путь — auto-trigger в session-start хуке (gap ≥8ч). Этот скилл для ручного запуска и dry-run."
description_en: "Override / forced regeneration of the project through-line brief. The main path is the auto-trigger in the session-start hook."
user-invocable: true
argument-hint: "[--entries=N] [--window=Xd] [--dry-run]"
---

# Narrative — Override for Auto-Compose

**Type:** worker

Ручной запуск orientation brief. Основной путь — автоматический: `hooks/session-start.sh` вызывает `narrative-compose-lib.sh` при gap ≥8ч с last session и стэшит результат; `knowledge-activator` на первом PreToolUse инжектит его как `📖 Where we are:`.

Этот скилл нужен когда:
- Auto-trigger не сработал (gap <8ч), но нужна ориентация.
- Nужен narrative с другим окном (`--entries=5`, `--window=4w`).
- Хочется посмотреть brief не сохраняя (`--dry-run`).

## Process

1. **Parse flags:** `--entries=N` (default 3), `--window=Xd|Xw` (default 14d), `--dry-run` (no writes).
2. **Call compose:** `bash $HOME/.claude/hooks/narrative-compose-lib.sh "$PWD" "$ENTRIES" "$WINDOW_DAYS" "$HOME/.claude/global-lessons"`.
3. **Abort on error code:**
   - Exit 1 → «project root / SESSION.md не найдены».
   - Exit 2 → «мало истории: нужно ≥2 session entries И (commits в окне ИЛИ cases в окне)».
4. **Output** (если не `--dry-run`):
   - `<project_root>/.claude-docs/narrative.md` — append-only блок (date header + body + trace).
   - `<project_root>/CLAUDE.md` — **заменить контент между маркерами** `<!-- narrative-start -->` и `<!-- narrative-end -->`. Если маркеров нет — НЕ создавать их автоматически; выдать предупреждение «markers missing — add `<!-- narrative-start --><!-- narrative-end -->` to CLAUDE.md to enable replace».
5. **Report** пользователю — показать brief, путь сохранения, предупреждение о markers если релевантно.

## Rules

- Без галлюцинаций: compose возвращает только факты из SESSION.md / git / global-lessons.
- `.claude-docs/narrative.md` — append-only (историческая память brief'ов).
- Метрики не собирает — это делает session-start-path автоматически.
- Не заменяет SESSION.md; source of truth остаётся SESSION.md.

## Definition of Done

- [ ] narrative-compose-lib.sh вызван с корректными аргументами
- [ ] Exit code обработан (abort при 1/2 с понятным сообщением)
- [ ] `.claude-docs/narrative.md` append (если не dry-run)
- [ ] CLAUDE.md заменён между маркерами (если маркеры присутствуют и не dry-run)
- [ ] Report показан пользователю

**Version:** 0.2.1
**Last Updated:** 2026-07-29