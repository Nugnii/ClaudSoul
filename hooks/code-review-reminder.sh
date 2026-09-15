#!/usr/bin/env bash
# code-review-reminder.sh — PreToolUse[Bash] на `git commit`: крупный кодовый дифф идёт в коммит без адверсариального прогона — поручает СКАЗАТЬ собеседнику про `/adversary`.
# en: PreToolUse[Bash] on `git commit`: a large code diff heading into a commit without an adversarial run — instructs to tell the interlocutor about `/adversary`.
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
#    поиск подтверждения вместо поиска ошибки. Теперь зовёт `/adversary`:
#    критика ведёт субагент в чистом контексте (pattern-multi-round-adversarial-review).
#
# Молчит, если адверсариальный прогон в этой сессии уже был — факт читается из
# расшифровки (скилл `adversary`, субагент с его промптом либо воркфлоу, гоняющий
# противника), а не из файла состояния: писателя нет, значит нет ни уборщика, ни
# требований D44/D49.
# Цена решения: прогон из ДРУГОЙ сессии виден лишь после времени HEAD (D373) — иначе напомним лишний раз. Ошибка в
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
# КОНТРПРИМЕР: расширения вне перечня — `.vue`, `.svelte`, `.zig`, `.lua`, `.tf` — кодом
# не считаются и напоминания о ревью не получат. Перечень назван перечнем: он растёт по
# мере встречи новых языков в проекте, а не выводится из правила «это исходный код».
CODE_EXT="${CODE_REVIEW_EXT:-ts|tsx|js|jsx|mjs|cjs|py|sh|bash|go|rs|rb|java|kt|php|c|cc|cpp|h|hpp|sql}"
CODE=$(printf '%s\n' "$NUMSTAT" | grep -E "	.*\.($CODE_EXT)\"?$" || true)
[ -z "$CODE" ] && exit 0

FILE_COUNT=$(printf '%s\n' "$CODE" | grep -c . )
LINE_COUNT=$(printf '%s\n' "$CODE" | awk '{a+=$1; d+=$2} END{print a+d+0}')

# Крупный дифф?
if [ "$LINE_COUNT" -le "$LINES_THRESHOLD" ] && [ "$FILE_COUNT" -le "$FILES_THRESHOLD" ]; then
  exit 0
fi

# Отсюда и ниже признак СОВПАЛ: крупный кодовый дифф идёт в коммит. Дальше три исхода, и
# все три обязаны попасть в журнал знаменателя (D372) — иначе доля «ушло без прогона»
# неисчислима по построению, ровно как описано в root-cause-lib.sh про `*-fired-*`.
#
# Почему подпись и сессия считаются ЗДЕСЬ, а не у троттла ниже. До 9 сентября 2026 обе
# переменные рождались после ветки «прогон был» (`exit 0` стоял выше них), и на диск
# попадал ТОЛЬКО случай «прогона не было»: 52 файла, 77 строк, знаменателя нет.
# Замер того же дня: 33 настоящих вызова противника в 10 расшифровках из 55 — то есть
# треть событий уходила в невидимую ветку.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
KEY=$(printf '%s' "$CODE" | (command -v md5sum >/dev/null 2>&1 && md5sum || md5) 2>/dev/null | awk '{print $1}')

_RC_LIB="${RC_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/root-cause-lib.sh}"
[ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
# shellcheck source=/dev/null
[ -f "$_RC_LIB" ] && . "$_RC_LIB"

# Подпись — хеш диффа, а не сессия: без неё знаменатель считал бы объём работы (сколько
# раз агент позвал `git commit`), а не частоту предмета (сколько РАЗНЫХ диффов ушло).
# Тот же контрпример назван в root-cause-lib.sh про подпись.
# ЗАПИСЬ ОТЛОЖЕНА ДО ИСХОДА (9 сентября 2026, второй раунд противника). Хук стоит на
# PreToolUse, то есть ДО исполнения: коммита в мире ещё нет и может не быть вовсе —
# собеседник, услышав напоминание, вызов отменяет. Прежде запись шла в знаменатель сразу,
# и число для состоявшегося коммита не отличалось от числа для отменённого ни байтом.
# Замер: 63 вызова из 896 в живом корпусе не породили ни одного коммита (7%).
# Теперь исход подтверждает `hooks/code-review-outcome.sh` на PostToolUse — событие,
# которого на упавшей команде НЕ БЫВАЕТ (измерено, шапка `error-tracker.sh`).
_note() {  # _note <act> [src] — `src` (D373: elsewhere) остаётся в записи ожидания; в
           # знаменатель уходит `act`, словарь журнала не растёт. Откуда был прогон,
           # различает ретро-прогон, а не живой замер — так названо в его шапке.
  mkdir -p "$STATE_DIR" 2>/dev/null
  jq -cn --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg a "$1" --arg k "$KEY" --arg s "${2:-}" \
      '{ts:$ts, act:$a, key:$k} + (if $s == "" then {} else {src:$s} end)' >> "$STATE_DIR/crr-pending-${SID}.jsonl" 2>/dev/null
  return 0
}

# Прогон противника в этой сессии уже был? Тогда напоминать не о чем.
#
# Правило детекта живёт в `hooks/lib/adversary-run-lib.sh` и здесь только ЗОВЁТСЯ: тот же
# вопрос задаёт ретро-прогон `scripts/adversary-replay.sh`, меряющий точность признака по
# корпусу. Две копии разошлись бы на первой правке, и замер мерил бы не то, что делает
# страж, — род K реестра дефектов. Вынесено 9 сентября 2026 вместе с заведением замера.
#
# Библиотеки нет — детект НЕ считается пройденным: молчание стража тогда означало бы
# «прогон был», хотя проверить это было нечем. Отсутствие прибора громче тишины.
SKILL_NAME="${ADVERSARY_SKILL_NAME:-adversary}"
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
_AR_LIB="${ADVERSARY_RUN_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/lib/adversary-run-lib.sh}"
[ -f "$_AR_LIB" ] || _AR_LIB="$HOME/.claude/hooks/lib/adversary-run-lib.sh"
# shellcheck source=/dev/null
[ -f "$_AR_LIB" ] && . "$_AR_LIB"

if command -v adversary_run_count >/dev/null 2>&1; then
  RAN=$(adversary_run_count "$TRANSCRIPT")
  RAN_RC=$?
  case "${RAN:-}" in ''|*[!0-9]*) RAN=0 ;; esac

  # Расшифровку прочитать не удалось. Поведение стража прежнее — напомнить (ошибка в
  # безопасную сторону), но в ЖУРНАЛ идёт `unread`, а не `said`: `said` есть утверждение
  # «крупный дифф ушёл в коммит без прогона», а здесь неизвестно, был прогон или нет.
  # Оба читателя журнала отбирают `said|muted` явно, поэтому такой ход не попадает ни в
  # числитель, ни в знаменатель — и это верно: измеренной тишиной непрочитанный вход не
  # является (`root-cause-lib.sh`, третье значение словаря).
  if [ "$RAN_RC" -ne 0 ]; then
    _note unread
    THROTTLE="$STATE_DIR/code-review-reminder-${SID}.txt"
    if [ -f "$THROTTLE" ] && grep -qxF "$KEY" "$THROTTLE" 2>/dev/null; then exit 0; fi
    printf '%s\n' "$KEY" >> "$THROTTLE" 2>/dev/null
    MSG="🥊 Крупный кодовый дифф (${LINE_COUNT} строк / ${FILE_COUNT} файлов); расшифровку прочитать не удалось, поэтому был ли адверсариальный прогон — неизвестно. СКАЖИ собеседнику одной строкой: перед коммитом стоит прогнать \`/${SKILL_NAME}\`. Решение за ним."
    jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
    exit 0
  fi

  # Признак совпал, условие ВЫПОЛНЕНО — страж молчит законно. Это не `muted` (там молчание
  # по троттлу, предмет тот же и неразобранный), а отдельный исход: событие мира случилось
  # и кончилось хорошо. Оба читателя журнала отбирают `said|muted` явно
  # (detection-share.sh:50, violation-class.sh:38), поэтому их числа четвёртое значение
  # не сдвигает — проверено чтением 9 сентября 2026, как предписывает словарь.
  if [ "$RAN" -gt 0 ]; then
    _note satisfied
    exit 0
  fi

  # Прогон в ДРУГОЙ сессии того же проекта (D373). Сессии одного каталога делят рабочее
  # дерево, поэтому чужой прогон засчитывается, если случился ПОСЛЕ времени HEAD: диффа
  # старше HEAD не бывает, а прогон старше HEAD его видеть не мог. Единица окна — работа
  # (коммит), не календарь. Нечитаемые соседи (код 2) прогоном не считаются: напоминание
  # выйдет — ошибка в безопасную сторону, а `unread` здесь не пишется, потому что СВОЯ
  # расшифровка прочитана и утверждение «в этой сессии прогона не было» верно.
  if command -v adversary_run_elsewhere >/dev/null 2>&1; then
    _HEAD_TS=$(git -C "$CWD" log -1 --format=%ct 2>/dev/null)
    case "${_HEAD_TS:-}" in ''|*[!0-9]*) _HEAD_TS=0 ;; esac
    ELSE=$(adversary_run_elsewhere "$TRANSCRIPT" "$_HEAD_TS"); ELSE_RC=$?
    case "${ELSE:-}" in ''|*[!0-9]*) ELSE=0 ;; esac
    if [ "$ELSE_RC" -eq 0 ] && [ "$ELSE" -gt 0 ]; then
      _note satisfied elsewhere
      exit 0
    fi
  fi
fi

# Throttle per-session per-diff-hash. SID и KEY посчитаны выше — там же, где признак совпал.
THROTTLE="$STATE_DIR/code-review-reminder-${SID}.txt"
if [ -f "$THROTTLE" ] && grep -qxF "$KEY" "$THROTTLE" 2>/dev/null; then
  # Признак совпал, страж промолчал по троттлу — знаменатель (D205).
  _note muted
  exit 0
fi
printf '%s\n' "$KEY" >> "$THROTTLE" 2>/dev/null
_note said

MSG="🥊 Крупный кодовый дифф (${LINE_COUNT} строк / ${FILE_COUNT} файлов), адверсариального прогона в этой сессии не было. СКАЖИ собеседнику одной строкой: перед коммитом стоит прогнать \`/${SKILL_NAME}\` — субагент в чистом контексте доказывает, что код ломается, и каждую атаку воспроизводит тестом. Решение за ним; правка тривиальна — так и скажи."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
