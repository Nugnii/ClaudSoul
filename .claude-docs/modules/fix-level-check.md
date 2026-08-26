# Модуль: детектор текстового фикса (fix-level-check)

**Назначение.** Ловить в собственном ответе агента пост-инцидентный фикс уровня 1 — текстовое правило вместо механизма — и напоминать поднять до activator/blocker либо пометить model-generated.

**Файлы.** `hooks/fix-level-check.sh` (скан Stop/PreCompact, инжект UserPromptSubmit/PreToolUse).

**Зависимости.** Транскрипт; словарь фраз — из задокументированных проявлений (case-2026-04-23-model-vs-system-source-blindness, правило Source-check), не придуман.

**Правила.** Подавление при названном механизме или пометке model-generated в том же ответе; дедуп за сессию. Закрыл заявку на эскалацию pattern-inside-out-blindness (открыта 2026-04-23). Тест: test_fix_level_check.
