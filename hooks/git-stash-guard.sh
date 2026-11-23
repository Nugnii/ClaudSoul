#!/usr/bin/env bash
# git-stash-guard.sh — PreToolUse[Bash]: `git stash`, меняющий рабочую копию, отбивается отказом.
# en: PreToolUse[Bash] — a working-copy-changing `git stash` (anything but list/show) is denied.
#
# Результат: команда агента не прячет и не достаёт рабочие правки общей папки: `git stash` в любой
#            форме, кроме `list` и `show`, получает отказ с названной заменой.
# Проверка результата: bash hooks/tests/test_git_stash_guard.sh
#
# Повод (11 октября 2026, ProjectA, D525). Правило «не stash» трижды жило текстом и трижды не
# удержалось: stash во время фонового прогона; `git stash -- <пути> && …; git stash pop` достал
# ЧУЖУЮ запись (в репозитории лежат stash других сессий, `pop` не знает, чья сверху); хвост
# проверочной команды `…; git stash -q 2>/dev/null; true` спрятал рабочие правки и чужой файл.
# Замер по 320 расшифровкам: 211 вызовов с `git stash`, из них `list` 56 и `show` 4 — остальное
# меняет рабочую копию. Уровень — отказ, решение владельца 11 октября 2026: последствие одно
# (рабочая копия общей папки меняется), а текстом правило уже не держалось.
#
# Чем заменять: «код до правки» — `git show <ref>:<путь>` или `git worktree add --detach <каталог>
# <ref>` (отдельная копия, рабочая не трогается); «отложить правки» — коммит в ветку.
# НАЗВАННЫЕ ПРЕДЕЛЫ: чужие интерпретаторы (`python3 -c`, `xargs sh`) и подстановки в теле heredoc без кавычек
# в метке не раскрываются; команда, которую оболочка не разбирает (незакрытая кавычка), проходит.
#
# Input  (stdin): {tool_name, tool_input:{command}, session_id}
# Output (stdout): {hookSpecificOutput:{permissionDecision:"deny", ...}} либо пусто
# Exit:  всегда 0.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ "$(jq -r '.tool_name // ""' <<< "$INPUT" 2>/dev/null)" = Bash ] || exit 0
CMD=$(jq -r '.tool_input.command // ""' <<< "$INPUT" 2>/dev/null)
SID=$(jq -r '.session_id // "unknown"' <<< "$INPUT" 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Разбор — у владельца лексики оболочки `hooks/lib/write_targets.py` (`git_calls`): кавычки, все
# глобальные опции git, перенаправления, тела heredoc, позиция команды — за ОДИН проход. Первая
# редакция судила `is_git_subcommand` + свою копию опций в sed и сломана противником 11 октября
# 2026: `git -C "<путь>" stash list` получал отказ (путь вырезался вместе с кавычками), `--no-pager`
# и `list>файл` — тоже; второй проход `executable_part` по суженному тексту терял `stash pop` после
# `it\'s`, `=$(git stash pop)` и `"git" stash` не узнавались.
case "$CMD" in *stash*) ;; *) exit 0 ;; esac
_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"
[ -f "$_LIBDIR/write_targets.py" ] || _LIBDIR="$HOME/.claude/hooks/lib"
[ -f "$_LIBDIR/write_targets.py" ] && command -v python3 >/dev/null 2>&1 || exit 0
_VERDICT=$(python3 -I - "$CMD" "$_LIBDIR" <<'PY' 2>/dev/null
import sys
sys.path.insert(0, sys.argv[2])
from write_targets import git_calls, stash_changes
for g in git_calls(sys.argv[1]):
    if stash_changes(g):
        print("deny")
        break
PY
)
_rc=$?
# Прибор сломан (исключение питона: установленный write_targets без git_calls, слишком длинная
# команда) — сказать, а не промолчать: у стража уровня отказа тишина читается как «чисто»
# (`.claude/rules/claudsoul-hooks.md`, три состояния прибора; раунд 2 противника, N6).
if [ "$_rc" -ne 0 ]; then
    jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"⚠️ git-stash-guard: разбор команды не исполнился (прибор сломан) — `git stash` в этом вызове не проверен."}}'
    exit 0
fi
[ "$_VERDICT" = deny ] || exit 0

STATE_DIR="${STATE_DIR:-${HOME:-}/.claude/hooks/state}"
mkdir -p "$STATE_DIR" 2>/dev/null
jq -cn --arg c "${CMD:0:300}" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$t,cmd:$c}' \
    >> "$STATE_DIR/git-stash-fired-${SID}.jsonl" 2>/dev/null || true

jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:
  ("⛔ ОТКАЗ (вызов не выполнен): `git stash` меняет рабочую копию общей папки — в ней работают параллельные сессии и фоновые прогоны, а `pop` достаёт верхнюю запись, не обязательно твою.\n\nЗамена:\n  · код до правки — `git show HEAD:<путь>` или отдельная копия `git worktree add --detach <каталог> HEAD` (рабочая не трогается);\n  · отложить правки — коммит в ветку;\n  · посмотреть записи — `git stash list` / `git stash show` (они не отбиваются).\n\nРешение владельца 11 октября 2026 (D525): правило трижды не удержалось текстом.")}}'
exit 0
