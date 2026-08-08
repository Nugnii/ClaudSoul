#!/usr/bin/env bash
# ci-check-reminder.sh — PostToolUse[Bash]: после `git push` напоминает проверить прогон
# СВОЕГО коммита, а не «самый свежий».
# en: PostToolUse[Bash]: after `git push`, reminds to check the run for THIS commit.
#
# Повод (D60). Я дважды объявил собеседнику «CI зелёный», когда прогон был красным
# (v1.17.0 и v1.17.2): цикл опрашивал `gh run list -L 1` — «самый свежий прогон», — а
# сразу после push самым свежим ещё числится ПРЕДЫДУЩИЙ. Инструмент `scripts/ci-status.sh`
# заведён, но оставался уровнем 1 по `principle-knowledge-in-the-world`: его надо было
# не забыть вызвать. Этот хук делает напоминание механическим — оно приходит ровно в тот
# момент, когда пуш состоялся.
#
# PostToolUse выбран сознательно: на УСПЕШНОЙ команде он срабатывает (D41 установил, что
# не срабатывает он на упавшей — а после упавшего пуша напоминать не о чем).
#
# Детект по ИСПОЛНЯЕМОЙ части команды (command-scope-lib), не по всему тексту: строка
# «git push» в heredoc или в кавычках — аргумент, а не команда (pattern-guard-scope-blindness).

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
[ -f "$SCOPE_LIB" ] || SCOPE_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
[ -f "$SCOPE_LIB" ] || exit 0
# shellcheck source=/dev/null
source "$SCOPE_LIB"

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -n "$CMD" ] || exit 0

EXEC=$(executable_part "$CMD" 2>/dev/null || printf '%s' "$CMD")
printf '%s' "$EXEC" | grep -qE '(^|[[:space:]]|;|&&|\|\|)git[[:space:]]+push([[:space:]]|$)' || exit 0

# Совет называет scripts/ci-status.sh — он существует не везде. cwd из payload,
# совет только там, где инструмент есть; иначе чужой проект получает ложную
# инструкцию (аудит переносимости 2026-08-08).
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null); [ -n "$CWD" ] || CWD="$PWD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$ROOT/scripts/ci-status.sh" ] || exit 0

jq -n '{
  systemMessage: "🚦 Пуш ушёл. Прогон проверяй для СВОЕГО коммита, не «самый свежий»: bash scripts/ci-status.sh — сразу после push самым свежим числится ПРЕДЫДУЩИЙ прогон, и `gh run list -L 1` дважды выдал ложное «зелено»."
}'
exit 0
