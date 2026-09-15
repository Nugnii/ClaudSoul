#!/usr/bin/env bash
# session-registry-lib.sh — Session Registry library for ClaudSoul
#
# ПРЕФИКСЫ: sr_
# Объявление пространства имён (11 сентября 2026, D390). Функция этой библиотеки
# носит один из названных префиксов; имя с ведущим `_` считается внутренним и под
# правило не подпадает. Сверяет `hooks/lib-prefix-guard.sh` при записи файла.
# Список собран ИЗ ФАКТА, а не придуман: он фиксирует нынешнее состояние, чтобы
# разнобой не рос дальше — из 21 библиотеки с 3+ функциями лишь 10 держали 80%+
# имён под одним префиксом, а объявления не было ни у одной из 29.
# Provides functions for managing session lifecycle across Claude Code sessions.
#
# Usage: source this file from other hooks:
#   source "$HOME/.claude/hooks/session-registry-lib.sh"
#
# Functions:
#   sr_register_session [dir] — create active session record (call at session start);
#                             dir — каталог СЕССИИ (payload `.cwd`); без него берётся $PWD
#   sr_update_knowledge     — add knowledge delta to active session
#   sr_finalize_session     — move active session to registry (call at session end)
#   sr_cleanup_stale        — remove orphaned active files (dead PID, ancestor PID, UUID older than 24h)
#   sr_get_startup_context  — build startup message from registry data
#   sr_detect_parallel      — check for other active sessions
#   sr_detect_interrupted   — find stale active sessions (likely interrupted)

# Разбор меток времени — из общего portable-lib.sh: ключ `date -j` есть только у BSD date
# (macOS), на Linux парсинг обязан идти через `date -d`.
# Общий замок и правка под ним (род H): запись активной сессии правят несколько ходов сразу.
STATE_LOCK_LIB="${STATE_LOCK_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/state-lock-lib.sh}"
[ -f "$STATE_LOCK_LIB" ] || STATE_LOCK_LIB="$HOME/.claude/hooks/state-lock-lib.sh"
# shellcheck source=/dev/null
if [ -f "$STATE_LOCK_LIB" ]; then . "$STATE_LOCK_LIB"; fi
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
else
    # Библиотека не задеплоена рядом. `exit` здесь убил бы вызывающий хук (файл источается),
    # поэтому отдаём ноль — то же значение, что раньше давала ветка `|| echo 0`.
    iso_epoch() { echo 0; }
fi

# Directories
# Каталог переопределяем, чтобы прогон в песочнице не писал в БОЕВОЙ реестр. Повод
# измерен 2 сентября 2026: в `~/.claude/sessions/registry.jsonl` лежат три записи с
# тестовыми фикстурами (`case-broken.md`, `plain.md`, `pattern-block.md`) — их принесли
# прогоны `test_adv2_bump_*`, которые подменяют LESSONS_DIR и STATE_DIR, но не HOME, а
# `knowledge-counter-bump.sh:604-609` зовёт `sr_update_knowledge` по живому пути. Пока
# запись терялась на отсутствующем носителе, загрязнение было редким; с пересозданием
# носителя (D270) оно стало постоянным — то есть починка расширила радиус, и это её
# зависимость, а не отдельная беда. Умолчание прежнее.
SR_SESSIONS_DIR="${SR_SESSIONS_DIR:-$HOME/.claude/sessions}"
SR_ACTIVE_DIR="$SR_SESSIONS_DIR/active"
SR_REGISTRY="$SR_SESSIONS_DIR/registry.jsonl"
SR_LAST_SESSION="$SR_SESSIONS_DIR/last-session.json"
# Срок метки живости в минутах (D298). Живость — «сессия подала признак жизни не позже
# срока», а не «файл существует»: метку обновляет КАЖДЫЙ Stop, поэтому у работающей
# сессии она свежая всегда, а у завершённой стареет. Значение — компромисс: короче —
# теряется параллельная сессия, у которой собеседник ушёл думать; длиннее — только что
# закончившаяся сессия ещё числится параллельной.
SR_LIVE_TTL_MIN="${SR_LIVE_TTL_MIN:-120}"

# Current session ID
# Priority: caller-provided SR_OVERRIDE_SESSION_ID (parsed from hook stdin payload)
#           > CLAUDE_CODE_SESSION_ID env > PPID fallback.
# Hooks should parse `.session_id` from their stdin JSON and export
# SR_OVERRIDE_SESSION_ID before sourcing this lib for stable identification.
SR_SESSION_ID="${SR_OVERRIDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-$PPID}}"

# Ensure directories exist
mkdir -p "$SR_ACTIVE_DIR"

# --- Helper: JSON escaping ---

_sr_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# --- Helper: liveness marker ---
# Живость сессии — ОТДЕЛЬНЫЙ носитель (D298, 6 сентября 2026). Прежде она читалась по
# наличию `active/<sid>.json`, а этот файл — накопитель записи ХОДА: `sr_finalize_session`
# уносит его в реестр на каждом Stop (`session-collector.sh:239`), и Stop есть конец хода,
# не сессии. Один носитель нёс две роли с несовместимыми сроками: сброс требует удаления,
# живость — сохранения; побеждало удаление, и после первого же хода живая параллельная
# сессия объявлялась несуществующей.
# Каталог выводится в момент ВЫЗОВА, а не при подключении: SR_SESSIONS_DIR переопределяют
# после `source` (hooks/tests/test_lib_shell_parity.sh:81), и вычисленный заранее путь
# увёл бы чтение в боевой каталог.
_sr_live_dir() {
    echo "${SR_LIVE_DIR:-$SR_SESSIONS_DIR/live}"
}

# Кладёт (или обновляет) метку живости по содержимому активного файла. Обновление даёт
# метке свежий mtime — это и есть «признак жизни», по которому считается срок.
_sr_mark_live() {
    local src="$1" dir
    [ -f "$src" ] || return 0
    dir="$(_sr_live_dir)"
    mkdir -p "$dir" 2>/dev/null || return 0
    cp -f "$src" "$dir/${SR_SESSION_ID}.json" 2>/dev/null || return 0
}

# Стоит ли за записью реестра процесс (D337, корень R3). Решается ПРИЗНАКОМ жизни, а не
# формой записи: числовой sid — это PID, и он жив, пока жив процесс; UUID подаёт признак
# жизни меткой `live/<sid>.json`, которую кладёт регистрация и обновляет каждый Stop (D298),
# — метки нет или она старше SR_LIVE_TTL_MIN, значит признака нет. Предшественник
# `sr_cleanup_stale` остаётся, предмет у него другой: КОГДА запись можно удалить. Накопитель
# хода в `active/` он держит сутки не потому, что сессия жива, а потому, что его уносит в
# реестр finalize; снести раньше — потерять ход. Здесь же решается, защищать ли состояние
# сессии (`scripts/state-prune.sh`), и срок берётся у метки живости.
# Usage: sr_record_alive <sid>  → 0 процесс есть, 1 запись без процесса
sr_record_alive() {
    case "$1" in
        ''|*[!0-9]*) [ -n "$(find "$(_sr_live_dir)/$1.json" -mmin -"$SR_LIVE_TTL_MIN" 2>/dev/null)" ] ;;
        *) ps -p "$1" >/dev/null 2>&1 ;;
    esac
}

# --- Helper: detect project from CWD ---
# Каталог — ПАРАМЕТР, а не $PWD (D277, 3 сентября 2026). Процесс хука не обязан стоять в
# каталоге сессии: Claude Code запускает его из своего cwd, и вход у узла есть — поле
# `.cwd` payload. Прежде параметра не было вовсе, и безопасность держалась дисциплиной
# вызывающих: `session-start.sh` и `session-end.sh` делали `cd`, а
# `knowledge-activator.sh:847` — нет, и регистрация из `/` давала `"project_name": "/"`,
# то есть Session Registry приписывал сессию каталогу процесса. Замер 3 сентября 2026 на
# прогоне активатора из `/` при cwd сессии в payload: было `project=/`, стало `project`
# = каталог сессии. `cd` в вызывающем эту роль не закрывает — он сдвигает $PWD ВСЕМУ хуку
# (`knowledge-activator.sh:41` ищет `$PWD/domains`, `:936` — `$PWD/mcp-server`).
# Умолчание $PWD сохранено: у CLI-вызывающего (`knowledge-counter-bump.sh:609`) payload'а
# нет, и каталог процесса там законный вход.
#
# Usage: _sr_detect_project [dir]
_sr_detect_project() {
    local dir="${1:-$PWD}"
    local start="$dir"
    # Условие выхода — «подъём перестал двигать путь», а не только «дошли до /»: на
    # относительном входе dirname упирается в точку и возвращает её же (`sub` → `.` → `.`
    # → …), и цикл не кончается никогда — тот же вечный подъём, что описан в
    # `paths-lib.sh:70-75`. Вход теперь приходит извне, и на форму его никто не влияет.
    local prev=""
    while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$prev" ]; do
        # `-e`, а не `-d`: в worktree и подмодуле `.git` — ФАЙЛ («gitdir: …»), и проверка
        # на каталог перешагивала корень worktree, отдавая родительский репозиторий —
        # хуки писали SESSION.md и проектную память соседнего проекта, молча. Единый
        # walk-up `hooks/paths-lib.sh` перешёл на `-e` раньше, здесь копия правила
        # отстала: две копии расходятся без единого падения. Worktree — штатный режим,
        # инструмент Agent умеет isolation:"worktree" (D287).
        if [ -e "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
            echo "$dir"
            return
        fi
        prev="$dir"
        dir="$(dirname "$dir")"
    done
    echo "$start"
}

# --- Register session ---

# Usage: sr_register_session [dir]  — dir = каталог сессии из payload `.cwd` (D277)

sr_register_session() {
    local active_file="$SR_ACTIVE_DIR/${SR_SESSION_ID}.json"

    # Don't re-register
    if [ -f "$active_file" ]; then
        return 0
    fi

    local project_path
    project_path="$(_sr_detect_project "${1:-}")"
    local project_name
    project_name="$(basename "$project_path")"
    local started_at
    started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    cat > "$active_file" <<ENDJSON
{
  "session_id": "$SR_SESSION_ID",
  "project": "$(_sr_json_escape "$project_path")",
  "project_name": "$(_sr_json_escape "$project_name")",
  "started_at": "$started_at",
  "knowledge_delta": {
    "created": [],
    "updated": [],
    "confirmed": [],
    "contradicted": []
  }
}
ENDJSON
    _sr_mark_live "$active_file"
}

# --- Update knowledge delta ---
# Usage: sr_update_knowledge "created" "case-new-finding.md"
#    or: sr_update_knowledge "updated" "pattern-some.md"

sr_update_knowledge() {
    local action="$1"  # created | updated | confirmed | contradicted
    local filename="$2"
    local active_file="$SR_ACTIVE_DIR/${SR_SESSION_ID}.json"

    # Носитель живёт один ХОД, а не сессию: sr_finalize_session зовётся из
    # session-collector на КАЖДОМ Stop (Stop — конец хода, не сессии) и уносит
    # active/<sid>.json в реестр, а sr_register_session зовётся один раз, на старте.
    # После первой границы хода файла нет, и `|| return 0` терял дельту молча — замер
    # 2 сентября 2026: сессия d5116580-… имеет в реестре 2 записи, а записанный в ней
    # паттерн не попал ни в одну (D270).
    # Носитель пересоздаётся, а не финализируется позже: дельта уходит в запись ТОГО
    # хода, в котором записана, и до реестра доходит вся. Снять finalize со Stop нельзя —
    # носитель прожил бы всю сессию и попал под уборку по возрасту (sr_cleanup_stale,
    # ветка UUID: старше 24 ч → rm), которую дёргает ЧУЖАЯ сессия через
    # sr_detect_parallel; терялась бы вся сессия целиком, а не дельта одного хода.
    [ -f "$active_file" ] || sr_register_session
    [ -f "$active_file" ] || return 0

    if command -v jq &>/dev/null; then
        atomic_filter "$active_file" jq --arg action "$action" --arg file "$filename" \
            '.knowledge_delta[$action] += [$file] | .knowledge_delta[$action] |= unique'
    fi
}

# Полей `commits` и `notes` в схеме больше нет, и функций sr_update_commits / sr_add_note
# тоже (D258, 2 сентября 2026). Оба поля были объявлены схемой и не имели НИ ОДНОГО
# писателя вне этой библиотеки и НИ ОДНОГО читателя: за 3622 сессии `commits` непуст ноль
# раз, `notes` — один (ручной тест 2026-04-15). Поле без читателя, которому дописывают
# писателя, — спекулятивная фича; удаление честнее. Исторические записи реестра свои ключи
# сохраняют: их никто не читает, чинить нечего.

# --- Finalize session ---
# Moves active session to registry.jsonl + updates last-session.json
# Args: $1 = summary (optional, from session-collector)

sr_finalize_session() {
    local summary="${1:-}"
    local active_file="$SR_ACTIVE_DIR/${SR_SESSION_ID}.json"

    [ -f "$active_file" ] || return 0

    if ! command -v jq &>/dev/null; then
        # Without jq, just clean up
        rm -f "$active_file"
        return 0
    fi

    local ended_at
    ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local started_at
    started_at="$(jq -r '.started_at' "$active_file")"

    # Calculate duration in minutes
    local start_epoch end_epoch duration_min
    start_epoch=$(iso_epoch "$started_at")
    end_epoch=$(date +%s)
    duration_min=$(( (end_epoch - start_epoch) / 60 ))

    # Поля `files_changed` здесь больше нет (D265, 2 сентября 2026). Имя обещало объём
    # СЕССИИ, а величину давал литерал `git diff --name-only HEAD~1 HEAD` — файлы
    # ПОСЛЕДНЕГО КОММИТА, не читающие ни одного входа записи. Поле было заполнено в 2846
    # записях из 3622, то есть выглядело живым и меряло не тот предмет
    # (pattern-subject-of-measurement-mismatch). Читателей значения — ноль: 13 упоминаний
    # по дереву, все либо писатель, либо описание, либо якорь фикстуры в тесте.
    # Считать «за сессию» значило бы завести базовую ссылку и накопление тронутых файлов
    # ради потребителя, которого нет; тем же ножом D258 снял `commits` и `notes`.

    # Поля `status` здесь больше нет (D273, 2 сентября 2026). Оно было литералом
    # `"completed"` и второго значения не принимало никогда: во всех 3641 записи реестра
    # стояло `completed`, при том что `docs/architecture.md` обещал пометку `interrupted`.
    # Замена литерала на переменную ничего бы не дала — переменной неоткуда взяться: оба
    # вызывающих finalize (`session-collector.sh` на Stop, `session-end.sh` на SessionEnd)
    # суть пути НОРМАЛЬНОГО завершения, где «completed» правда, а путь распознавания
    # чужой прерванной сессии оканчивается `rm -f` (`sr_cleanup_stale`) и `echo`
    # (`sr_detect_interrupted`), а не записью: реестр умеет записывать только то, что
    # сессия знает о СЕБЕ. Читателей поля во всём дереве ноль. Тем же ножом сняты
    # `commits`/`notes` (D258) и `files_changed` (D265). Прерванность по-прежнему
    # распознаётся и ПОКАЗЫВАЕТСЯ в startup context — обещание в документе приведено к
    # этому. Исторические записи свои ключи сохраняют: их никто не читает.

    # Build finalized record
    local finalized
    finalized=$(jq \
        --arg ended "$ended_at" \
        --arg summary "$(_sr_json_escape "$summary")" \
        --argjson duration "$duration_min" \
        '. + {
            ended_at: $ended,
            duration_min: $duration,
            summary: $summary
        }' "$active_file")

    # Append to registry (one JSON per line)
    echo "$finalized" | jq -c '.' >> "$SR_REGISTRY"

    # Update last-session.json (pretty-printed for easy reading)
    echo "$finalized" | jq '.' > "$SR_LAST_SESSION"

    # Признак жизни обновлён ДО удаления накопителя: сессия жива, кончился только ход.
    _sr_mark_live "$active_file"

    # Remove active session
    rm -f "$active_file"
}

# --- Helper: collect current process ancestry ---
# Walks up the process tree from $$ to init, returns space-separated PIDs.
# Used by cleanup to detect pre-fix PID-based registrations of the *current*
# Claude session (when SR_SESSION_ID is now UUID-based but a stale PID file
# from the same process tree is still on disk).

_sr_process_ancestors() {
    local pid=$$
    local out=""
    local guard=0
    while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
        out="$out $pid"
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        guard=$((guard + 1))
        [ "$guard" -gt 20 ] && break
    done
    echo "$out"
}

# --- Cleanup stale active sessions ---
# Removes active session files that no longer represent a live distinct session:
#   - PID-based file whose PID is dead → orphan, remove
#   - PID-based file whose PID is in current process tree → pre-fix duplicate of
#     current UUID session, remove
#   - UUID-based file older than 24h → assume orphan, remove
# Current SR_SESSION_ID is always preserved.

sr_cleanup_stale() {
    local sid
    local files=()
    # Перечисление через `find`, а не через шаблон оболочки. Было `compgen -G` — встроенная
    # команда bash, в zsh её нет: условие проваливалось, массив оставался пустым, цикл не
    # выполнялся, и функция возвращала «параллельных сессий нет» вместо семи. Тихий
    # ложноотрицательный. Замена на голый шаблон не годится тоже: в zsh несовпавший шаблон
    # по умолчанию не остаётся литералом, а обрывает выполнение с «no matches found».
    # `find` ведёт себя одинаково в обеих оболочках и на пустом каталоге просто молчит.
    while IFS= read -r _srf; do
        [ -n "$_srf" ] && files+=("$_srf")
    done <<EOF
$(find "$SR_ACTIVE_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
EOF

    local ancestors=" $(_sr_process_ancestors) "

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        sid="$(basename "$f" .json)"
        [ "$sid" = "$SR_SESSION_ID" ] && continue

        case "$sid" in
            ''|*[!0-9]*)
                # Non-numeric (UUID or test stub) — TTL 24h
                if [ -n "$(find "$f" -mmin +1440 2>/dev/null)" ]; then
                    rm -f "$f"
                fi
                ;;
            *)
                # Numeric = PID. Two reasons to remove:
                # 1. PID is dead → orphan from a crashed session
                # 2. PID is in current process tree → duplicate of current session
                #    (pre-fix registration that used $PPID before UUID stdin override)
                if ! ps -p "$sid" >/dev/null 2>&1; then
                    rm -f "$f"
                elif [[ "$ancestors" == *" $sid "* ]]; then
                    rm -f "$f"
                fi
                ;;
        esac
    done

    # Метки живости (D298) — свой носитель, свой срок. Считается возраст ПОСЛЕДНЕГО
    # признака жизни (mtime обновляет каждый Stop), а не возраст сессии: иначе метка
    # завершённой сессии числилась бы живой до общего суточного порога, и стартовый
    # контекст называл бы параллельными все сессии за сутки.
    # Цикл без массива: `for f in "${arr[@]}"` на пустом каталоге под `set -u` и bash 3.2
    # (умолчание macOS) обрывает вызывающий хук.
    while IFS= read -r _srf; do
        [ -n "$_srf" ] || continue
        [ "$(basename "$_srf" .json)" = "$SR_SESSION_ID" ] && continue
        rm -f "$_srf"
    done <<EOF
$(find "$(_sr_live_dir)" -maxdepth 1 -type f -name '*.json' -mmin +"$SR_LIVE_TTL_MIN" 2>/dev/null | sort)
EOF
}

# --- Detect parallel sessions ---
# Returns JSON array of currently-live active sessions (excluding current).
# Runs cleanup first so dead PID-based files don't leak into the count.

sr_detect_parallel() {
    local sid entry
    sr_cleanup_stale

    local result="[]"
    # Каждая сессия называется ОДИН раз: у сессии в первом своём ходу есть и накопитель
    # `active/<sid>.json`, и метка `live/<sid>.json`, и без отсева она попала бы в ответ
    # дважды.
    local seen=" "

    local files=()
    # Перечисление через `find`, а не через шаблон оболочки. Было `compgen -G` — встроенная
    # команда bash, в zsh её нет: условие проваливалось, массив оставался пустым, цикл не
    # выполнялся, и функция возвращала «параллельных сессий нет» вместо семи. Тихий
    # ложноотрицательный. Замена на голый шаблон не годится тоже: в zsh несовпавший шаблон
    # по умолчанию не остаётся литералом, а обрывает выполнение с «no matches found».
    # `find` ведёт себя одинаково в обеих оболочках и на пустом каталоге просто молчит.
    while IFS= read -r _srf; do
        [ -n "$_srf" ] && files+=("$_srf")
    done <<EOF
$(find "$SR_ACTIVE_DIR" "$(_sr_live_dir)" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
EOF

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        sid="$(basename "$f" .json)"
        [ "$sid" = "$SR_SESSION_ID" ] && continue
        case "$seen" in *" $sid "*) continue ;; esac
        seen="$seen$sid "

        if command -v jq &>/dev/null; then
            entry=$(jq -c '{session_id, project_name, started_at}' "$f" 2>/dev/null) || continue
            result=$(echo "$result" | jq --argjson e "$entry" '. += [$e]')
        fi
    done

    echo "$result"
}

# --- Detect interrupted sessions ---
# Active sessions older than threshold (default 6 hours) are likely interrupted
# Returns JSON array

sr_detect_interrupted() {
    local sid started_at start_epoch age entry
    sr_cleanup_stale

    local threshold_hours="${1:-6}"
    local threshold_sec=$((threshold_hours * 3600))
    local now
    now=$(date +%s)
    local result="[]"

    # Handle no-match case (bash nullglob or explicit check)
    local files=()
    # Перечисление через `find`, а не через шаблон оболочки. Было `compgen -G` — встроенная
    # команда bash, в zsh её нет: условие проваливалось, массив оставался пустым, цикл не
    # выполнялся, и функция возвращала «параллельных сессий нет» вместо семи. Тихий
    # ложноотрицательный. Замена на голый шаблон не годится тоже: в zsh несовпавший шаблон
    # по умолчанию не остаётся литералом, а обрывает выполнение с «no matches found».
    # `find` ведёт себя одинаково в обеих оболочках и на пустом каталоге просто молчит.
    while IFS= read -r _srf; do
        [ -n "$_srf" ] && files+=("$_srf")
    done <<EOF
$(find "$SR_ACTIVE_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
EOF

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        sid="$(basename "$f" .json)"
        [ "$sid" = "$SR_SESSION_ID" ] && continue

        # After cleanup, surviving PID-based ids are alive — they're parallel, not interrupted.
        case "$sid" in
            ''|*[!0-9]*) ;;  # UUID — keep checking (no liveness signal)
            *)
                if ps -p "$sid" >/dev/null 2>&1; then
                    continue
                fi
                ;;
        esac

        if command -v jq &>/dev/null; then
            started_at=$(jq -r '.started_at' "$f" 2>/dev/null) || continue

            start_epoch=$(iso_epoch "$started_at")

            age=$((now - start_epoch))
            if [ "$age" -gt "$threshold_sec" ]; then
                entry=$(jq -c --argjson age_h "$((age / 3600))" \
                    '{session_id, project_name, started_at, age_hours: $age_h}' "$f" 2>/dev/null) || continue
                result=$(echo "$result" | jq --argjson e "$entry" '. += [$e]')
            fi
        fi
    done

    echo "$result"
}

# --- Get startup context ---
# Builds a human-readable startup message for injection
# Returns empty string if no useful context

sr_get_startup_context() {
    local msg=""

    # 1. Last completed session
    if [ -f "$SR_LAST_SESSION" ] && command -v jq &>/dev/null; then
        local last_project last_summary last_ended last_duration
        last_project=$(jq -r '.project_name // "unknown"' "$SR_LAST_SESSION" 2>/dev/null)
        last_summary=$(jq -r '.summary // ""' "$SR_LAST_SESSION" 2>/dev/null)
        last_ended=$(jq -r '.ended_at // ""' "$SR_LAST_SESSION" 2>/dev/null)
        last_duration=$(jq -r '.duration_min // 0' "$SR_LAST_SESSION" 2>/dev/null)

        # Calculate time since last session
        local time_ago=""
        if [ -n "$last_ended" ] && [ "$last_ended" != "null" ]; then
            local last_epoch now_epoch
            last_epoch=$(iso_epoch "$last_ended")
            now_epoch=$(date +%s)
            local diff_min=$(( (now_epoch - last_epoch) / 60 ))

            if [ "$diff_min" -lt 60 ]; then
                time_ago="${diff_min} мин назад"
            elif [ "$diff_min" -lt 1440 ]; then
                time_ago="$(( diff_min / 60 ))ч назад"
            else
                time_ago="$(( diff_min / 1440 ))д назад"
            fi
        fi

        # Knowledge delta from last session
        local k_created k_updated
        k_created=$(jq -r '.knowledge_delta.created | length' "$SR_LAST_SESSION" 2>/dev/null || echo 0)
        k_updated=$(jq -r '.knowledge_delta.updated | length' "$SR_LAST_SESSION" 2>/dev/null || echo 0)

        msg+="📍 Последняя сессия: ${time_ago} (${last_project}, ${last_duration}мин)"
        if [ -n "$last_summary" ] && [ "$last_summary" != "" ] && [ "$last_summary" != "null" ]; then
            msg+="\\n   → ${last_summary}"
        fi
        if [ "$k_created" -gt 0 ] || [ "$k_updated" -gt 0 ]; then
            msg+="\\n   📚 Знания: +${k_created} новых, ↑${k_updated} обновлённых"
            # List created knowledge files
            if [ "$k_created" -gt 0 ]; then
                local created_list
                created_list=$(jq -r '.knowledge_delta.created[]' "$SR_LAST_SESSION" 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//')
                msg+="\\n      Новые: ${created_list}"
            fi
        fi
    fi

    # 2. Parallel sessions
    local parallel
    parallel=$(sr_detect_parallel)
    local parallel_count
    parallel_count=$(echo "$parallel" | jq 'length' 2>/dev/null || echo 0)

    if [ "$parallel_count" -gt 0 ]; then
        msg+="\\n\\n⚡ Параллельные сессии: ${parallel_count}"
        echo "$parallel" | jq -r '.[] | "   → \(.project_name) (с \(.started_at | split("T")[1] | split("Z")[0]))"' 2>/dev/null | while IFS= read -r line; do
            msg+="\\n${line}"
        done
    fi

    # 3. Interrupted sessions
    local interrupted
    interrupted=$(sr_detect_interrupted 6)
    local interrupted_count
    interrupted_count=$(echo "$interrupted" | jq 'length' 2>/dev/null || echo 0)

    if [ "$interrupted_count" -gt 0 ]; then
        msg+="\\n\\n⚠️ Прерванные сессии: ${interrupted_count}"
        echo "$interrupted" | jq -r '.[] | "   → \(.project_name) (\(.age_hours)ч назад)"' 2>/dev/null | while IFS= read -r line; do
            msg+="\\n${line}"
        done
    fi

    # 4. Knowledge created since last session by OTHER sessions (from registry)
    # This catches knowledge from parallel sessions we didn't see
    if [ -f "$SR_REGISTRY" ] && [ -f "$SR_LAST_SESSION" ] && command -v jq &>/dev/null; then
        local my_last_ended
        my_last_ended=$(jq -r '.ended_at // ""' "$SR_LAST_SESSION" 2>/dev/null)
        # Find sessions that ended after our last session (from other sessions)
        if [ -n "$my_last_ended" ] && [ "$my_last_ended" != "null" ]; then
            local other_knowledge
            other_knowledge=$(tail -20 "$SR_REGISTRY" 2>/dev/null | jq -s --arg after "$my_last_ended" --arg mysid "$SR_SESSION_ID" \
                '[.[] | select(.ended_at > $after and .session_id != $mysid) | .knowledge_delta.created[]] | unique | .[]' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
            if [ -n "$other_knowledge" ]; then
                msg+="\\n\\n🆕 Знания из других сессий: ${other_knowledge}"
            fi
        fi
    fi

    echo "$msg"
}
