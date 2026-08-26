#!/usr/bin/env bash
# code-review-reminder.sh — PreToolUse[Bash] на `git commit`: крупный кодовый дифф идёт в коммит без адверсариального прогона — поручает СКАЗАТЬ собеседнику про `/противник`.
# en: PreToolUse[Bash] on `git commit`: a large code diff heading into a commit without an adversarial run — instructs to tell the interlocutor about `/противник`.
#
# Механизирует канон A6 (ревью дифа свежим контекстом перед «готово») —
# always-fire правило лучше хуком, чем текстом (канон D5).
#
# Две вещи, исправленные в v1.13.0 после разбора приёма «адверсариальное ревью»:
#
# 1. Текст был адресован АГЕНТУ и звучал как статус с готовой отмазкой
#    («если ещё не делал — прогони»). Замер 2026-08-21 по другим нуджам: статус,
#    адресованный агенту, доходит до собеседника в единицах процентов случаев,
#    поручение «СКАЖИ собеседнику» доходит всегда. Теперь это поручение.
# 2. Хук звал агента покритиковать СЕБЯ — тот же контекст, те же допущения,
#    поиск подтверждения вместо поиска ошибки. Теперь зовёт `/противник`:
#    критика ведёт субагент в чистом контексте (pattern-multi-round-adversarial-review).
#
# Молчит, если адверсариальный прогон в этой сессии уже был — факт читается из
# расшифровки (скилл `противник`, субагент с его промптом либо воркфлоу, гоняющий
# противника), а не из файла состояния: писателя нет, значит нет ни уборщика, ни
# требований D44/D49.
# Цена решения: прогон из ДРУГОЙ сессии не виден — напомним лишний раз. Ошибка в
# безопасную сторону: пропущенное напоминание дороже лишнего.
#
# Порог «крупный»: > LINES изменённых строк ИЛИ > FILES кодовых файлов.
# Scoped против ложных срабатываний: docs-only / tests-only / мелкие правки не триггерят.
# Throttle per-session per-diff-hash (тот же дифф не напоминаем дважды). Silent.
#
# Input  (stdin): {tool_name, tool_input, session_id, transcript_path, cwd} (PreToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} или пусто
# Exit:  always 0 (degrade gracefully).

set -uo pipefail

# Детект коммита — по ИСПОЛНЯЕМОЙ части команды (single source — command-scope-lib.sh):
# `git commit` в кавычках или в теле heredoc — текст, а не команда.
SCOPE_LIB="${SCOPE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-scope-lib.sh}"
[ -f "$SCOPE_LIB" ] || SCOPE_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
if [ -f "$SCOPE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$SCOPE_LIB"
else
    is_git_commit() { grep -qE 'git[[:space:]]+commit' <<< "${1:-}"; }
fi

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

LINES_THRESHOLD=80
FILES_THRESHOLD=4

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
is_git_commit "$COMMAND" || exit 0

# numstat по staged кодовым файлам.
#
# Два дефекта, найденных первым же написанным для этого хука тестом (v1.12.4):
#
# 1. `cwd` не читался из payload. Процесс хука не обязан стоять в каталоге сессии,
#    и без `-C` страж смотрел diff постороннего репозитория.
# 2. Фильтр был `web/(lib|app|components)/*.ts(x)` — раскладка того проекта, откуда
#    хук импортировали в v1.11.0. В репозитории из bash, python и markdown он не мог
#    сработать НИКОГДА: молчал не потому что диффы мелкие, а потому что не понимал
#    ни одного здешнего файла. Молчание было структурно независимо от предмета проверки.
#
# Теперь набор расширений общий и переопределяется через `CODE_REVIEW_EXT`.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
# `core.quotepath=false` обязателен: без него git отдаёт имена вне ASCII в кавычках с
# восьмеричными escape ("\321\204….py"), фильтр по расширению их не узнаёт, и страж
# молчит на крупном диффе. Найдено адверсариальным прогоном 2026-08-22; хвостовая `"?`
# в фильтре добирает остаток — имена со спецсимволами git кавычит и при quotepath=false.
NUMSTAT=$(git -C "$CWD" -c core.quotepath=false diff --cached --numstat 2>/dev/null) || exit 0
[ -z "$NUMSTAT" ] && exit 0
CODE_EXT="${CODE_REVIEW_EXT:-ts|tsx|js|jsx|mjs|cjs|py|sh|bash|go|rs|rb|java|kt|php|c|cc|cpp|h|hpp|sql}"
CODE=$(printf '%s\n' "$NUMSTAT" | grep -E "	.*\.($CODE_EXT)\"?$" || true)
[ -z "$CODE" ] && exit 0

FILE_COUNT=$(printf '%s\n' "$CODE" | grep -c . )
LINE_COUNT=$(printf '%s\n' "$CODE" | awk '{a+=$1; d+=$2} END{print a+d+0}')

# Крупный дифф?
if [ "$LINE_COUNT" -le "$LINES_THRESHOLD" ] && [ "$FILE_COUNT" -le "$FILES_THRESHOLD" ]; then
  exit 0
fi

# Прогон противника в этой сессии уже был? Тогда напоминать не о чем.
#
# Два шага: дешёвый grep по сырой расшифровке отсекает подавляющее большинство
# сессий, где имени нет вовсе; точный jq нужен потому, что имя скилла встречается
# и в обычном РАЗГОВОРЕ о нём. Считается только фактический вызов инструмента:
# Skill{skill:"противник"}, Agent с промптом противника либо Workflow, чей скрипт
# этот промпт содержит.
#
# У Workflow два способа передать скрипт, и в расшифровке они выглядят по-разному:
# `script` кладёт текст целиком, `scriptPath` — только путь, а промпт остаётся на
# диске. Второй случай не экзотика: именно так воркфлоу переzапускают после правки.
# Поэтому пути дочитываются с диска отдельным шагом. Поле `description` намеренно
# не считается: его пишут свободным текстом, и «обсуждаем противника» стало бы
# ложным зачётом прогона — та же граница «вызов, а не упоминание".
SKILL_NAME="${ADVERSARY_SKILL_NAME:-противник}"
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
# Дешёвый фильтр пропускает и расшифровки со `scriptPath`: при запуске воркфлоу по
# пути имени скилла в расшифровке нет вовсе, и фильтр по имени отсекал бы ровно тот
# случай, ради которого ветка ниже и написана (поймано тестом T14 до выпуска).
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] &&
   { grep -qF "$SKILL_NAME" "$TRANSCRIPT" 2>/dev/null || grep -qF '"scriptPath"' "$TRANSCRIPT" 2>/dev/null; }; then
  RAN=$(jq -rs --arg s "$SKILL_NAME" '
    [ .[]
      | (.message.content? // [])
      | if type == "array" then .[] else empty end
      | select(type == "object" and .type == "tool_use")
      | if (.name == "Skill" and ((.input.skill // "") == $s)) then 1
        elif (.name == "Agent" or .name == "Task") and (((.input.prompt // "") | contains("Ты " + $s))) then 1
        elif (.name == "Workflow") and (((.input.script // "") | contains("Ты " + $s))) then 1
        else empty end
    ] | length
  ' "$TRANSCRIPT" 2>/dev/null)
  case "${RAN:-0}" in ''|*[!0-9]*) RAN=0 ;; esac

  # Воркфлоу, запущенный по пути: промпт лежит в файле, а не в расшифровке.
  if [ "$RAN" -eq 0 ]; then
    WF_PATHS=$(jq -rs '
      [ .[]
        | (.message.content? // [])
        | if type == "array" then .[] else empty end
        | select(type == "object" and .type == "tool_use" and .name == "Workflow")
        | (.input.scriptPath // empty)
      ] | .[]
    ' "$TRANSCRIPT" 2>/dev/null)
    while IFS= read -r WF; do
      [ -n "$WF" ] && [ -f "$WF" ] || continue
      if grep -qF "Ты $SKILL_NAME" "$WF" 2>/dev/null; then RAN=1; break; fi
    done <<< "$WF_PATHS"
  fi

  [ "$RAN" -gt 0 ] && exit 0
fi

# Throttle per-session per-diff-hash.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
KEY=$(printf '%s' "$CODE" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')
THROTTLE="$STATE_DIR/code-review-reminder-${SID}.txt"
if [ -f "$THROTTLE" ] && grep -qxF "$KEY" "$THROTTLE" 2>/dev/null; then exit 0; fi
printf '%s\n' "$KEY" >> "$THROTTLE" 2>/dev/null

MSG="🥊 Крупный кодовый дифф (${LINE_COUNT} строк / ${FILE_COUNT} файлов), адверсариального прогона в этой сессии не было. СКАЖИ собеседнику одной строкой: перед коммитом стоит прогнать \`/${SKILL_NAME}\` — субагент в чистом контексте доказывает, что код ломается, и каждую атаку воспроизводит тестом. Решение за ним; правка тривиальна — так и скажи."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
