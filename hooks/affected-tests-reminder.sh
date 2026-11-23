#!/usr/bin/env bash
# affected-tests-reminder.sh — PreToolUse[Bash] на `git commit`: набор затронутых тестов для этих изменений не собран — называет команду.
# en: PreToolUse[Bash] on `git commit`: names the command that collects the affected-test set when it was not collected.
#
# Команда — `scripts/affected-tests.sh` ClaudSoul: к тестам по именам файлов она добавляет сканеры дерева и старый текст.
#
# Повод (D1296, 15 ноября 2026, ProjectA). Трижды за две сессии «затронутый набор», отобранный по импортам, пропустил
# сканеры дерева и e2e-спеку со старой подписью, и красное нашёл CI релиза. Знание держалось текстом; скрипт без вызова —
# тоже текст («помни позвать»), поэтому зов стоит на коммите.
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ. В ClaudSoul выбор держит `hooks/tests/run_all.sh --changed` с реестром «всегда» и картой
# зависимостей; здесь хук молчит (признак — `hooks/tests/run_all.sh` в корне), иначе у одного предмета два голоса.
# Отпечаток изменений и след набора — у владельца, `scripts/affected-tests.sh --was-run`: своей копии сверки здесь нет.
#
# Три состояния прибора: скрипта нет — молчать (другая установка); код 0 — набор собран, молчать; 1 — назвать команду;
# иной код — сказать, что прибор не ответил (молчание тут читалось бы «собран»).
# Подсказка, а не отказ: точность признака «набор не собран → красное после коммита» не мерена.
# Коммит узнаёт владелец разбора команды (`command-scope-lib.sh`): `git commit` внутри `bash -c '…'` он не видит, и хук
# там молчит — предел владельца, своей копии разбора здесь нет.
# НАЗВАННЫЙ ПРЕДЕЛ: судится «набор собран для этих изменений», а не «набор прогнан» — запуск тестов проекта хук не видит.
# Условие снятия: у проекта появится журнал прогона тестов, который можно сверить с набором.
# Проверка снятия: `grep -q "^# ЖУРНАЛ ПРОГОНА:" scripts/affected-tests.sh`
#
# Input  (stdin): {tool_name, tool_input:{command}, cwd, session_id} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
# Exit:  always 0 (degrade gracefully).
set -uo pipefail

SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
[ -f "$SCOPE_LIB" ] || SCOPE_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
if [ -f "$SCOPE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$SCOPE_LIB"
else
    is_git_commit() { grep -qE 'git[[:space:]]+commit' <<< "${1:-}"; }
fi
command -v executable_commit_dir >/dev/null 2>&1 || executable_commit_dir() { return 2; }
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && source "$PATHS_LIB"
: "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
INPUT=$(cat); [ -z "$INPUT" ] && exit 0
[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
is_git_commit "$COMMAND" || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null); [ -n "$CWD" ] || CWD="$PWD"
_CD=$(executable_commit_dir "$CWD" "$COMMAND") && CWD="$_CD"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$ROOT/hooks/tests/run_all.sh" ] && exit 0   # ClaudSoul: выбор у run_all.sh --changed
TOOL="$CLAUDSOUL_ROOT/scripts/affected-tests.sh"
[ -f "$TOOL" ] || exit 0
# Правка одних документов `.md` тестов не трогает — молчать (иначе каждый коммит журнала сессии звал бы набор).
# Пути без кавычек git (кириллица в имени не прячет `.md`), переименование — двумя путями, правка только в индексе
# (`git add -p`, а рабочее дерево вернули) — тоже правка: коммит берёт индекс (скептик D1296, M1 и L1).
_G() { git -C "$ROOT" -c core.quotepath=off "$@" 2>/dev/null; }
CHANGED=$(_G diff HEAD --name-only --no-renames; _G diff --cached --name-only --no-renames; _G ls-files --others --exclude-standard)
NONDOC=$(grep -v '^$' <<< "$CHANGED" | grep -v '\.md$')
[ -n "$NONDOC" ] || exit 0
bash "$TOOL" --was-run --root "$ROOT" >/dev/null 2>&1; rc=$?
case "$rc" in
    0) exit 0 ;;
    1) MSG="🧪 Набор затронутых тестов для этих изменений не собирался. Собери и прогони до коммита: \`bash \"$TOOL\" --root \"$ROOT\"\` — к тестам по именам файлов он добавляет все сканеры дерева и тесты со старым текстом интерфейса, которых выборка по импортам не видит (D1296)." ;;
    *) MSG="🧪 Прибор затронутых тестов не ответил (код $rc): \`bash \"$TOOL\" --was-run --root \"$ROOT\"\`. Собран ли набор для этих изменений — неизвестно, это не «собран»." ;;
esac
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
