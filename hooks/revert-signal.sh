#!/usr/bin/env bash
# revert-signal.sh — PostToolUse[Bash]: откат коммита и повторный hotfix одного файла — повод разбора.
# en: PostToolUse[Bash]: a revert or a repeated hotfix of the same file becomes an analysis trigger.
#
# Результат: откат принятого решения не проходит молча — он становится поводом разбора
#            наравне с полосой провалов и переделкой файла
# Проверка результата: bash hooks/tests/test_external_events.sh даёт 0
#
# Зачем (D201). Контур разбора запускался на ущерб или повтор. Зрелые практики запускают
# его ещё и на ВКЛЮЧЕНИЕ МЕХАНИЗМА РЕАГИРОВАНИЯ: у Google SRE откат релиза обязывает к
# разбору сам по себе, независимо от того, был ли ущерб, — потому что откат есть признание,
# что принятое решение оказалось неверным. У нас `git revert` не смотрел никто: поиск по
# хукам давал только `bash-cost-detector`, и тот ловит `push --force` как разрушительную
# команду, а не как отмену решения.
#
# ПОЧЕМУ POSTTOOLUSE. Откат — свершившийся факт, а не намерение: тормозить его бессмысленно
# и вредно (иногда откат и есть правильное действие). Повод заводится ПОСЛЕ выполнения.
#
# КОНТРПРИМЕР, объявлен: `git commit --amend` до публикации сюда НЕ относится — это правка
# черновика, а не отмена принятого решения. Так же не считается `git revert --abort` и
# упоминание слова в кавычках или в сообщении коммита: разбирается ИСПОЛНЯЕМАЯ часть
# команды (`command-scope-lib.sh`), а не её текст.
#
# НАЗВАННЫЙ ПРЕДЕЛ: повторный hotfix одного файла в окне N коммитов признаётся по истории
# git, то есть виден только для файлов, попавших в коммиты. Правка, не дошедшая до
# коммита, тут невидима — её ловит `rework-detector` по другому признаку.
# Условие снятия: предел уйдёт, когда «принятое решение» станет наблюдаемо не по коммиту,
# а по исходу задачи (пункт долга закрыт → открыт заново).
#
# Input  (stdin): {session_id, tool_name, tool_input:{command}} (PostToolUse JSON)
# Output (stdout): пусто — повод пишется в состояние, говорит о нём гейт разбора
# Exit:  always 0 (degrade gracefully).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -n "$CMD" ] || exit 0

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "$PATHS_LIB" ] || PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && . "$PATHS_LIB"

RC_LIB="${RC_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/root-cause-lib.sh}"
[ -f "$RC_LIB" ] || RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
# shellcheck source=/dev/null
{ [ -f "$RC_LIB" ] && . "$RC_LIB"; } || exit 0
command -v rc_note_event >/dev/null 2>&1 || exit 0

SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/command-scope-lib.sh}"
[ -f "$SCOPE_LIB" ] || SCOPE_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
# shellcheck source=/dev/null
[ -f "$SCOPE_LIB" ] && . "$SCOPE_LIB"
command -v executable_commit_dir >/dev/null 2>&1 || executable_commit_dir() { return 2; }   # без разбора — папка сессии

# Исполняемая часть команды: слово в кавычках или в сообщении коммита командой не является.
EXEC="$CMD"
if command -v executable_part >/dev/null 2>&1; then
    EXEC=$(executable_part "$CMD" 2>/dev/null || printf '%s' "$CMD")
fi

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"

# Проект события берётся у PAYLOAD, а не у каталога процесса (10 сентября 2026). Прежде
# `CWD` читался ниже — уже ПОСЛЕ первого `rc_note_event`, — и событие `revert` уходило в
# журнал с проектом, выведенным из `$PWD` хука. Читатель (`five-whys-gate.sh:93`) выводит
# ключ из `payload.cwd`, и при несовпадении каталогов событие пишется под одним ключом, а
# ищется под другим: сигнал `event` умирает молча. Комментарий внутри `rc_project_of`
# формулирует это правило дословно — «каталог процесса хуку не вход», — а продюсер его и
# нарушал. Пустой payload не меняет поведения: переменная не выставляется, и `rc_note_event`
# падает на прежний путь.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] && command -v rc_project_of >/dev/null 2>&1 \
    && RC_EVENT_PROJECT=$(rc_project_of "$CWD")

# --- Откат коммита ------------------------------------------------------------
# `--abort` и `--continue` — управление уже идущим откатом, а не новая отмена решения.
# Матчер — у ВЛАДЕЛЬЦА (`is_git_subcommand`), а не свой: своя пара grep не пускала между
# `git` и подкомандой ни одной глобальной опции, и `git -C /repo revert HEAD` откатом не
# считался (находка противника 10 сентября 2026, род K).
if is_git_subcommand revert "$CMD" \
   && ! grep -qE 'revert[[:space:]]+--(abort|continue|quit)' <<< "$EXEC"; then
    rc_note_event "$STATE" "revert" "откат коммита: $(printf '%s' "$EXEC" | head -c 80)"
    exit 0
fi

# --- Повторный hotfix одного файла --------------------------------------------
# Признак: файл правился коммитами с сообщением `fix(...)` дважды и больше в окне
# последних REVERT_WINDOW коммитов. Порог 2, потому что второй fix того же файла и есть
# «первая починка не удержалась»; окно в КОММИТАХ, а не в днях — ритм работы неравномерный.
is_git_commit "$CMD" || exit 0
command -v git >/dev/null 2>&1 || exit 0
[ -n "$CWD" ] || exit 0
# Каталог КОММИТА — у разбора команды (`cd` и `-C`), а не папка сессии (D1282, братья D1278). Разбор не ответил — папка сессии.
_CD=$(executable_commit_dir "$CWD" "$CMD") && CWD="$_CD"
REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

WINDOW="${REVERT_WINDOW:-10}"
THRESHOLD="${HOTFIX_THRESHOLD:-2}"
# Генерируемые и учётные файлы из предмета исключены: их не ЧИНЯТ, их пересобирают или
# дописывают, и они входят почти в каждый коммит. Поймано на первом же живом срабатывании
# 29 августа 2026: повод завёлся на `.claude-docs/dep-index.tsv`, который пересобирается
# скриптом после каждой правки механизма. Та же калибровка, что у `rework-detector`
# (D18/D23): повторная правка хроники — норма жанра, а не переработка.
# КОНТРПРИМЕР: журнальные файлы вне этого перечня (`docs/*.md`) исключением не покрыты —
# перечень назван перечнем, он растёт по мере встречи новых генерируемых носителей.
# D520 (6 октября 2026): свидетель зелёной стороны `test_backlog_green_side.sh` — реестр фикстур,
# дописываемый ногой на каждый пункт долга; вошёл в 21 из 60 fix-коммитов, повод горел по устройству.
HOTFIX_EXCLUDE_RE="${HOTFIX_EXCLUDE_RE:-(dep-index\.tsv|measurements\.tsv|doc-claims\.tsv|CHANGELOG|CHANGELOG-archive|SESSION|BACKLOG|BACKLOG-archive|README|README\.ru|test_backlog_green_side)\.?[a-z]*$}"
HOT=$(project_git -C "$REPO" log -n "$WINDOW" --grep='^fix' --name-only --pretty=format: 2>/dev/null \
      | grep -v '^$' | grep -vE "$HOTFIX_EXCLUDE_RE" \
      | sort | uniq -c | sort -rn | awk -v t="$THRESHOLD" '$1 >= t {print $2; exit}')
[ -n "${HOT:-}" ] || exit 0
rc_note_event "$STATE" "hotfix-repeat" "$HOT чинился $THRESHOLD+ раз в окне $WINDOW коммитов"
exit 0
