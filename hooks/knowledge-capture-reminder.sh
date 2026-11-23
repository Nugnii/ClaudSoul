#!/usr/bin/env bash
# knowledge-capture-reminder.sh — PostToolUse[Bash]: напоминает собрать материал в черновики базы знаний, когда за сессию накопилось N коммитов, а с прошлого напоминания захвата не было.
# en: PostToolUse[Bash]: reminds to collect material after N commits in the session when nothing was captured since the previous reminder.
#
# Закрывает щель между двумя существующими триггерами захвата знаний:
#   error-tracker  (gated на retry: attempts >= 2)
#   session-collector (gated на Stop)
# Длинная УСПЕШНАЯ непрерывная сессия проваливается мимо обоих — знания теряются.
# Incident: за 18-коммитную сессию /project-health не захвачено ни одного знания,
# пока не указал пользователь (см. _drafts/session-2026-06-20-...; урок 1).
#
# Логика: считает `git commit` за сессию; на каждом окне THRESHOLD коммитов
# проверяет, появился ли новый черновик в _drafts/ с прошлой проверки
# (find -newer marker). Нет нового черновика → silent inject напоминания.
# Уровень 2 embedded-ness (механизм, не текстовое правило —
# principle-knowledge-in-the-world: правило, которое держится только памятью, не держится).
#
# Input  (stdin): {session_id, tool_name, tool_input} (PostToolUse JSON)
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
if [ -f "$PATHS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PATHS_LIB"
else
    : "${STATE_DIR:=$HOME/.claude/hooks/state}"
    : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"
fi

mkdir -p "$STATE_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
# Только реальные коммиты.
is_git_commit "$COMMAND" || exit 0

if command -v resolve_session_id >/dev/null 2>&1; then
    SID=$(resolve_session_id "$INPUT" "unknown" 2>/dev/null || echo unknown)
else
    SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)
fi
[ -z "$SID" ] && SID="unknown"

THRESHOLD="${KCR_THRESHOLD:-5}"
STATE="$STATE_DIR/knowledge-capture-${SID}"
MARKER="$STATE_DIR/knowledge-capture-marker-${SID}"

# Состояние: "count last_reminded"
count=0; last_reminded=0
if [ -f "$STATE" ]; then
    read -r count last_reminded < "$STATE" 2>/dev/null || { count=0; last_reminded=0; }
fi
case "$count" in ''|*[!0-9]*) count=0 ;; esac
case "$last_reminded" in ''|*[!0-9]*) last_reminded=0 ;; esac

count=$((count + 1))

# Точка отсчёта ставится на ПЕРВОМ засчитанном коммите сессии, а не при первой проверке
# окна. Иначе у первого окна нет базы для сравнения, и «новых записей нет» было бы
# утверждением из ничего — ровно то, что чинилось в этом же файле.
[ -f "$MARKER" ] || touch "$MARKER" 2>/dev/null

# Окно ещё не набрано с прошлого напоминания → просто сохранить счётчик.
if [ "$count" -lt "$THRESHOLD" ] || [ $((count - last_reminded)) -lt "$THRESHOLD" ]; then
    printf '%s %s\n' "$count" "$last_reminded" > "$STATE"
    exit 0
fi

# Окно достигнуто. Был ли захват знания с прошлой проверки (marker)?
#
# Считается ЛЮБАЯ новая запись знания, а не только черновик. Прежняя версия смотрела
# исключительно в `_drafts/`, и за сессию 2026-07-29 трижды сообщила «материал не захвачен»,
# когда в базу было записано три готовых кейса — прямо в `global-lessons/`, минуя черновики.
# Буквально верно, по существу нет: измерялась папка черновиков, а не захват. Черновик —
# один из путей записи, а не сам захват (тот же класс, что чинился весь тот день:
# детектор смотрит на прокси вместо предмета).
# ── ЗАХВАТ СЧИТАЕТСЯ ПО ДЕЙСТВИЯМ ЭТОГО АГЕНТА, А НЕ ПО СВЕЖЕСТИ ФАЙЛА (D400) ────
# База знаний — каталог, ОБЩИЙ для всех сессий и проектов: в неё пишут параллельная сессия,
# `/learn` соседнего проекта, механизм симметрии ссылок, дописывающий обратную ссылку в чужой
# кейс. До 12 сентября 2026 признаком служило `find -newer "$MARKER"`, то есть «в каталоге
# что-то появилось», и любой такой писатель гасил напоминание ЭТОМУ агенту. Измерено
# подготовленным состоянием: маркер старше, в каталоге лежит `case-neighbour.md`, действий
# хода нет — хук молчал. Тот же корень R6, что у `declared-problem-recorded.sh` (D396, закрыт
# в тот же день): время файла отвечает на вопрос «трогали ли», а не «кто трогал».
#
# Теперь предмет наблюдения — РАСШИФРОВКА ЭТОЙ СЕССИИ: запись засчитана, если в ней есть
# вызов инструмента с целью в базе знаний или в черновиках, и он НОВЕЕ маркера (окно то же,
# что у счётчика). Признак цели берётся у владельца — `RC_OUT_KNOWLEDGE_RE` и
# `RC_OUT_WRITE_RE` из `root-cause-lib.sh`, — чтобы у факта «это запись знания» не завелось
# второго определения, которое разойдётся молча. Инструмент не перечисляется именем: у `Bash`
# осматривается команда и только при форме записи
# (`case-2026-08-27-tool-name-detection-blind-to-work-mode`).
#
# НАЗВАННЫЙ ПРЕДЕЛ: без расшифровки захват не засчитывается — напоминание выйдет, даже если
# запись была. Выбрано осознанно: ложное МОЛЧАНИЕ гасит напоминание навсегда и неотличимо от
# «записал сосед», ложное напоминание видно и стоит одной строки. Правка субагента лежит в
# отдельной расшифровке и сюда не попадает — тот же предел, что у `declared-problem-recorded`.
# Условие снятия: расшифровки субагентов станут читаться вместе с расшифровкой сессии.
KCR_RC_LIB="${KCR_RC_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/root-cause-lib.sh}"
[ -f "$KCR_RC_LIB" ] || KCR_RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
# shellcheck source=/dev/null
[ -f "$KCR_RC_LIB" ] && . "$KCR_RC_LIB" 2>/dev/null
# Запасная ветка объявляет ВСЕ имена, читаемые ниже: под `set -u` недостающее убило бы хук
# на первом же чтении, молча и до начала работы.
: "${RC_OUT_KNOWLEDGE_RE:=global-lessons/}"
: "${RC_OUT_WRITE_RE:=(>>?[ ]*[^ |&]|sed -i|[ ]tee[ ]|^tee[ ])}"

KCR_PORTABLE="${KCR_PORTABLE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
[ -f "$KCR_PORTABLE" ] || KCR_PORTABLE="$HOME/.claude/hooks/portable-lib.sh"
# shellcheck source=/dev/null
[ -f "$KCR_PORTABLE" ] && . "$KCR_PORTABLE" 2>/dev/null

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
MARKER_TS=0
if command -v file_mtime >/dev/null 2>&1; then
    MARKER_TS=$(file_mtime "$MARKER" 2>/dev/null)
    case "${MARKER_TS:-}" in ''|*[!0-9]*) MARKER_TS=0 ;; esac
fi

captured=false
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    # Доли секунды срезаются ДО разбора: `fromdateiso8601` их не принимает, и запись с долями
    # молча получила бы время 0, то есть «старше маркера» — захват пропал бы.
    _kcr_hits=$(jq -rs --argjson since "${MARKER_TS:-0}" \
        --arg kn "$RC_OUT_KNOWLEDGE_RE" --arg wr "$RC_OUT_WRITE_RE" '
        def ts(x): ((x.timestamp // "") | if . == "" then 0
                    else ((sub("\\.[0-9]+Z$"; "Z")) | (fromdateiso8601? // 0)) end);
        def blocks(x): (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then $c else [] end;
        [ .[] | select(ts(.) > $since) | blocks(.)[]
          | select(.type == "tool_use")
          | if (.input.file_path // "") != "" then (.input.file_path)
            elif ((.input.command // "") | test($wr)) then (.input.command // "")
            else empty end ]
        | map(select(test($kn) or test("_drafts/")))
        | length' "$TRANSCRIPT" 2>/dev/null)
    case "${_kcr_hits:-}" in ''|*[!0-9]*) _kcr_hits=0 ;; esac
    [ "$_kcr_hits" -gt 0 ] && captured=true
fi

# Продвинуть окно и обновить marker в любом случае (это окно проверено).
printf '%s %s\n' "$count" "$count" > "$STATE"
touch "$MARKER" 2>/dev/null

[ "$captured" = "true" ] && exit 0      # захват был — не напоминаем

# Поручение сказать, а не статус — по той же причине, что в compile-reminder-lib.sh:
# замер 2026-08-21 показал 2 озвучивания на 45 приходов в контекст.
# ОБЛАСТЬ УТВЕРЖДЕНИЯ РАВНА ОБЛАСТИ ЗАМЕРА (9 сентября 2026, род L).
# Прежде текст говорил «за сессию … новых записей в базе знаний нет», а замер смотрел
# ýже: `$MARKER` продвигается на КАЖДОМ вызове хука (строка ниже, «в любом случае»),
# поэтому окно захвата — «с прошлого напоминания», а не сессия. Наблюдено на себе:
# две записи (`case-2026-09-09-opposing-defects-mask-each-other`,
# `case-2026-09-09-green-check-not-about-the-defect`) сделаны за сорок минут до
# срабатывания, между ними хук вызывался ещё дважды и трогал маркер — и страж сообщил
# «новых записей нет», будучи буквально верным и по существу ложным.
# Счётчик коммитов при этом ДЕЙСТВИТЕЛЬНО сессионный, поэтому в тексте разведены две
# области: коммиты за сессию, записи — с прошлого напоминания.
MSG="🧠 Захват знаний — СКАЖИ собеседнику одной строкой: коммитов за сессию ${count}, а с прошлого напоминания в базу знаний не записано ничего; накопился материал — записать кейс через /learn либо собрать в _drafts/, пока контекст свеж."
jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
