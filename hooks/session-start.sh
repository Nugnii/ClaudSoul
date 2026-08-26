#!/usr/bin/env bash
# session-start.sh — SessionStart: регистрирует сессию в registry при старте (startup/resume/clear/compact) для видимости параллельных сессий.
# en: SessionStart: registers the session in the registry on startup/resume/clear/compact for cross-session visibility.
# Fires immediately when a Claude Code session begins (startup/resume/clear/compact).
# Registers the session in the registry eagerly, so parallel sessions can see each
# other without waiting for the first Bash/Edit/Write tool call.
#
# Input: JSON on stdin from Claude Code (SessionStart event)
#   { "session_id": "<uuid>", "source": "startup|resume|clear|compact",
#     "cwd": "<path>", "hook_event_name": "SessionStart" }
# Output: empty (registration is silent; startup context is injected by
#         knowledge-activator on first PreToolUse to keep all injected info in one place)

set -euo pipefail

INPUT="$(cat)"

# Resolve stable session_id from payload (UUID); fall back to env/PPID
PAYLOAD_SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$PAYLOAD_SID" ]; then
    export SR_OVERRIDE_SESSION_ID="$PAYLOAD_SID"
fi

# CWD from payload — registry uses it to resolve project name
PAYLOAD_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [ -n "$PAYLOAD_CWD" ] && [ -d "$PAYLOAD_CWD" ]; then
    cd "$PAYLOAD_CWD" || true
fi

# Библиотека ищется СНАЧАЛА рядом с собой, и лишь потом в установленном каталоге.
# Прежде стоял только установленный путь, и на машине без ClaudSoul хук молча
# выходил целиком. Тесты этого не видели: они шли на машине, где установка есть,
# то есть проверяли установленную копию, а не репозиторий.
REGISTRY_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/session-registry-lib.sh"
[ -f "$REGISTRY_LIB" ] || REGISTRY_LIB="$HOME/.claude/hooks/session-registry-lib.sh"
if [ -f "$REGISTRY_LIB" ]; then
    # shellcheck disable=SC1090
    source "$REGISTRY_LIB"
    sr_register_session
    sr_cleanup_stale
fi

# Narrative auto-trigger: if gap from last session ≥ NARRATIVE_GAP_HOURS (default 8),
# compose orientation brief and stash for knowledge-activator to inject on first PreToolUse.
# Silent — no stdout; brief appears in agent context, not user terminal.
NARRATIVE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/narrative-compose-lib.sh"
[ -f "$NARRATIVE_LIB" ] || NARRATIVE_LIB="$HOME/.claude/hooks/narrative-compose-lib.sh"
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"; : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"; : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
# Разбор времени и mtime — через portable-lib.sh: у BSD (macOS) и GNU (Linux) разный
# синтаксис `date -j` / `stat -f`, и хук молча терял сигналы на чужой системе.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
# Запасная ветка (тот же порядок проб GNU → BSD) — чтобы неполная установка гасила
# библиотеку, а не сигналы: без функций хук упал бы на первом же вызове.
if [ -f "$PORTABLE_LIB" ]; then source "$PORTABLE_LIB"; else
    iso_epoch() { date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || echo 0; }
    file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
fi
NARRATIVE_GAP_HOURS="${NARRATIVE_GAP_HOURS:-8}"
SR_LAST_SESSION="${SR_LAST_SESSION:-$HOME/.claude/hooks/state/last-session.json}"
# STATE_DIR — из paths-lib (источается выше)
mkdir -p "$STATE_DIR"

if [ -f "$NARRATIVE_LIB" ] && [ -n "${PAYLOAD_CWD:-}" ] && [ -d "$PAYLOAD_CWD" ]; then
    narrative_should_fire=0
    if [ -f "$SR_LAST_SESSION" ] && command -v jq >/dev/null 2>&1; then
        last_ended=$(jq -r '.ended_at // empty' "$SR_LAST_SESSION" 2>/dev/null)
        if [ -n "$last_ended" ] && [ "$last_ended" != "null" ]; then
            last_epoch=$(iso_epoch "$last_ended")
            now_epoch=$(date +%s)
            gap_hours=$(( (now_epoch - last_epoch) / 3600 ))
            if [ "$gap_hours" -ge "$NARRATIVE_GAP_HOURS" ]; then
                narrative_should_fire=1
            fi
        else
            # No prior ended_at → first real session, fire once
            narrative_should_fire=1
        fi
    else
        # No registry yet → fire to bootstrap
        narrative_should_fire=1
    fi

    if [ "$narrative_should_fire" = "1" ]; then
        # shellcheck disable=SC1090
        source "$NARRATIVE_LIB"
        SID="${SR_OVERRIDE_SESSION_ID:-$$}"
        PENDING_FILE="$STATE_DIR/narrative-pending-${SID}.txt"
        NARR_ROOT="$PAYLOAD_CWD"; command -v find_project_root >/dev/null 2>&1 && NARR_ROOT=$(find_project_root "$PAYLOAD_CWD")
        if narrative_compose "$NARR_ROOT" 3 14 "$LESSONS_DIR" > "$PENDING_FILE" 2>/dev/null; then
            if [ -s "$PENDING_FILE" ]; then
                # Append to project append-only archive (history survives even if inject missed)
                ARCHIVE_DIR="$PAYLOAD_CWD/.claude-docs"
                ARCHIVE_FILE="$ARCHIVE_DIR/narrative.md"
                mkdir -p "$ARCHIVE_DIR" 2>/dev/null || true
                if [ -d "$ARCHIVE_DIR" ]; then
                    {
                        printf '\n## %s (session %s)\n' "$(date '+%Y-%m-%d %H:%M')" "${SID:0:8}"
                        cat "$PENDING_FILE"
                        printf '\n'
                    } >> "$ARCHIVE_FILE" 2>/dev/null || true
                fi
            else
                rm -f "$PENDING_FILE"
            fi
        else
            rm -f "$PENDING_FILE"
        fi
    fi
fi

# Startup signals (v1.5.1-alpha) — собираем additive signals в отдельный pending-файл.
# knowledge-activator инжектит их одним блоком после narrative.
# Signals:
#   (1) Missing project CLAUDE.md → suggest /init-project
#   (2) Global-lessons обновились с last ended_at → suggest /reload (knowledge delta)
SIGNALS_SID="${SR_OVERRIDE_SESSION_ID:-$$}"
SIGNALS_FILE="$STATE_DIR/startup-signals-${SIGNALS_SID}.txt"
: > "$SIGNALS_FILE" 2>/dev/null || true

# Signal 1: missing CLAUDE.md in project root
if [ -n "${PAYLOAD_CWD:-}" ] && [ -d "$PAYLOAD_CWD" ] && [ ! -f "$PAYLOAD_CWD/CLAUDE.md" ]; then
    printf '⚠️ В корне проекта нет CLAUDE.md. Рекомендую запустить /init-project для инициализации проектного контекста (CLAUDE.md + SESSION.md + .claude-docs/).\n' >> "$SIGNALS_FILE"
fi

# Signal 2: global-lessons обновлены с last ended_at (v1.5.1-alpha — /reload auto-hint)
if [ -f "$SR_LAST_SESSION" ] && [ -d "$LESSONS_DIR" ] && command -v jq >/dev/null 2>&1; then
    last_ended=$(jq -r '.ended_at // empty' "$SR_LAST_SESSION" 2>/dev/null)
    if [ -n "$last_ended" ] && [ "$last_ended" != "null" ]; then
        last_epoch=$(iso_epoch "$last_ended")
        if [ "${last_epoch:-0}" -gt 0 ]; then
            # Count knowledge files with mtime > last_epoch.
            # BSD find на macOS не понимает -newermt "@epoch", поэтому сравниваем сами —
            # mtime берём через file_mtime, у stat ключ различается (GNU -c / BSD -f).
            # Цена: по одному вызову stat на файл (~0.6 с на 172 знаниях) вместо одного
            # прохода awk. Хук стартовый, раз за сессию; если база вырастет на порядок —
            # нужна пакетная функция в portable-lib.sh, а не условие про stat здесь.
            new_count=0
            while IFS= read -r kfile; do
                [ -n "$kfile" ] || continue
                if [ "$(file_mtime "$kfile")" -gt "$last_epoch" ]; then
                    new_count=$((new_count + 1))
                fi
            done < <(find "$LESSONS_DIR" -maxdepth 1 -type f \( -name 'case-*.md' -o -name 'pattern-*.md' -o -name 'principle-*.md' \) 2>/dev/null)
            if [ "${new_count:-0}" -gt 0 ]; then
                printf '🔄 База знаний обновилась с прошлой сессии: +%s файлов. При необходимости — /reload для явной синхронизации контекста.\n' "$new_count" >> "$SIGNALS_FILE"
            fi
        fi
    fi
fi

# Signal 3 (v1.5.3-alpha): audit-hint.txt / bridge-hint.txt — periodic digest hints
# written by launchd jobs (knowledge-audit-digest.sh weekly, bridge-health-digest.sh monthly).
# Append to startup signals; hint files stay on disk (overwritten on next digest run).
for HINT in "$STATE_DIR/audit-hint.txt" "$STATE_DIR/bridge-hint.txt"; do
    if [ -f "$HINT" ] && [ -s "$HINT" ]; then
        cat "$HINT" >> "$SIGNALS_FILE"
    fi
done

# Signal 4 (v1.5.8 — ⚙️ AP3 silence debt surfacing): carry-over hint from last session.
# Reads most recent entry in intrusiveness-history.jsonl (digest format v1.5.8 has
# debt.pending_topics). If pending > 0 — surface as silent inject signal. This is
# the third affect prosthetic: cost-of-silence made visible across session boundary
# (infrastructural, not text rule — the hint appears without agent remembering).
AP3_HISTORY="$STATE_DIR/intrusiveness-history.jsonl"
if [ -f "$AP3_HISTORY" ] && [ -s "$AP3_HISTORY" ] && command -v jq >/dev/null 2>&1; then
    AP3_LAST=$(tail -n 1 "$AP3_HISTORY" 2>/dev/null)
    if [ -n "$AP3_LAST" ]; then
        AP3_PENDING=$(printf '%s' "$AP3_LAST" | jq -r '.debt.pending // 0' 2>/dev/null || echo 0)
        if [ "${AP3_PENDING:-0}" -gt 0 ]; then
            AP3_TOPICS=$(printf '%s' "$AP3_LAST" | jq -r '(.debt.pending_topics // []) | join(", ")' 2>/dev/null || true)
            if [ -n "$AP3_TOPICS" ] && [ "$AP3_TOPICS" != "null" ]; then
                printf '⚙️ AP3 silence debt carry-over: %s pending с прошлой сессии — %s. Учитывать в gate, не батч-вывод.\n' "$AP3_PENDING" "$AP3_TOPICS" >> "$SIGNALS_FILE"
            else
                printf '⚙️ AP3 silence debt carry-over: %s pending с прошлой сессии. Учитывать в gate.\n' "$AP3_PENDING" >> "$SIGNALS_FILE"
            fi
        fi
    fi
fi

# Signal 5 (v1.4.0 Phase 3 step 3.2): calibration progress inject.
# metrics-collector writes state/calibration-progress.json with valid_chunks.
# Show X/30 while < 30 as "накапливаем", switch to "готово" once threshold
# reached — actionable hint that /calibrate can run. Silent after successful
# calibration run (absence of marker file), managed by step 3.3 artifact.
CALIB_FILE="$STATE_DIR/calibration-progress.json"
CALIB_DONE_MARKER="$STATE_DIR/calibration-v1.4-done.flag"
if [ -f "$CALIB_FILE" ] && [ ! -f "$CALIB_DONE_MARKER" ] && command -v jq >/dev/null 2>&1; then
    CALIB_VALID=$(jq -r '.valid_chunks // 0' "$CALIB_FILE" 2>/dev/null || echo 0)
    CALIB_GE=$(jq -r '.gentle_events_total // 0' "$CALIB_FILE" 2>/dev/null || echo 0)
    CALIB_PE=$(jq -r '.proactive_events_total // 0' "$CALIB_FILE" 2>/dev/null || echo 0)
    CALIB_THR=$(jq -r '.threshold // 30' "$CALIB_FILE" 2>/dev/null || echo 30)
    if [ "${CALIB_VALID:-0}" -ge "${CALIB_THR:-30}" ]; then
        printf '📊 Калибровка v1.4.0 готова: %s/%s valid chunks (gentle=%s proactive=%s). Можно запускать scripts/calibrate.py (шаг 3.3 pretzel plan).\n' \
            "$CALIB_VALID" "$CALIB_THR" "$CALIB_GE" "$CALIB_PE" >> "$SIGNALS_FILE"
    elif [ "${CALIB_VALID:-0}" -gt 0 ]; then
        printf '📊 Калибровка v1.4.0: %s/%s valid chunks (копим историю gate-событий для scripts/calibrate.py).\n' \
            "$CALIB_VALID" "$CALIB_THR" >> "$SIGNALS_FILE"
    fi
fi

# Signal 6 (v1.6.1 — install drift detector): hooks registered in settings.json
# but physically absent in ~/.claude/hooks/, or present but not registered.
# Closes case-2026-04-24-install-drift-silent-safeguards (docs-family-check
# existed in repo + install.sh + settings.json config, but ~/.claude/hooks/ was
# never synced — safeguards silently inactive across 8 releases).
#
# Detection: cross-check files in $HOME/.claude/hooks/*.sh against commands in
# $HOME/.claude/settings.json. If any registered hook file is missing, or any
# installed hook is unregistered, inject a 🛠️ drift hint pointing to install.sh.
DRIFT_SETTINGS="$HOME/.claude/settings.json"
DRIFT_HOOKS_DIR="$HOME/.claude/hooks"
if [ -f "$DRIFT_SETTINGS" ] && [ -d "$DRIFT_HOOKS_DIR" ] && command -v jq >/dev/null 2>&1; then
    DRIFT_REGISTERED=$(jq -r '
        (.hooks // {}) | to_entries | .[] | .value[]? | .hooks[]? | .command // empty
    ' "$DRIFT_SETTINGS" 2>/dev/null | grep -oE 'hooks/[A-Za-z0-9._-]+\.sh' | sed 's|hooks/||' | sort -u)
    # `ls` по глобу без совпадений возвращает 1, и под `set -euo pipefail` этот код
    # доходил до присваивания и ронял ВЕСЬ хук: exit 1, stderr пуст, ни одного сигнала.
    # Состояние «каталог есть, .sh нет» — это чистая машина до install.sh, ровно тот
    # случай, ради которого сигнал дрейфа и заведён. Он единственный и не срабатывал.
    DRIFT_INSTALLED=$(
        find "$DRIFT_HOOKS_DIR" -maxdepth 1 -name '*.sh' -exec basename {} \; 2>/dev/null | sort -u || true
    )
    DRIFT_MISSING_FILES=""
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        if ! grep -Fxq "$name" <<< "$DRIFT_INSTALLED"; then
            DRIFT_MISSING_FILES="${DRIFT_MISSING_FILES}${name} "
        fi
    done <<< "$DRIFT_REGISTERED"
    if [ -n "$DRIFT_MISSING_FILES" ]; then
        printf '🛠️ Install drift: зарегистрированы, но не установлены — %s. Запусти %s/install.sh для синхронизации.\n' \
            "$(printf '%s' "${DRIFT_MISSING_FILES% }")" \
            "${CWD:-$PWD}" >> "$SIGNALS_FILE"
    fi

    # Обратное направление дрейфа (v1.11). Шапка Signal 6 обещала «or present but
    # not registered» с v1.6.1, но код сверял только live↔live. Настоящая слепая
    # зона оказалась третьей: хук работает и зарегистрирован, но копии в репозитории
    # нет — на другой машине его не будет, и install.sh об этом не узнает. За 8
    # релизов так накопилось 9 хуков (v1.11 импортировал 8, девятый проектный).
    # Это второй проход того же кейса case-2026-04-24-install-drift-silent-safeguards:
    # там дрейф был «репозиторий → установка», здесь «установка → репозиторий».
    #
    # Хук может принадлежать ДРУГОМУ проекту — тогда его дом там, и «копии нет»
    # относится не к нему. Сообщение сигнала само предлагало такой исход («либо
    # перенеси в репозиторий проекта, которому они принадлежат»), но не проверяло,
    # что он уже наступил: `projecta-security-gate.sh` лежал в git своего проекта с
    # 2026-07-05 и всё равно попадал в сигналы старта каждую сессию.
    #
    # Признак — маркер `claudsoul-foreign-hook` в самом файле, а не список здесь.
    # Список означал бы имена чужих проектов в публикуемом дереве ClaudSoul, а они
    # в forbidden.txt: гейт публикации на них и падает.
    if [ -d "$CLAUDSOUL_ROOT/hooks" ]; then
        DRIFT_UNTRACKED=""
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            [ -f "$CLAUDSOUL_ROOT/hooks/$name" ] && continue
            # Маркер засчитывается только как объявление в шапке — `# claudsoul-foreign-hook:`.
            # Простое вхождение подстроки выводило хук из-под проверки собственным
            # комментарием: строка встречается в этом же файле и в тесте install-drift,
            # то есть достаточно процитировать соглашение, чтобы перестать его соблюдать.
            grep -qE '^[[:space:]]*#[[:space:]]*claudsoul-foreign-hook:' \
                "$DRIFT_HOOKS_DIR/$name" 2>/dev/null && continue
            DRIFT_UNTRACKED="${DRIFT_UNTRACKED}${name} "
        done <<< "$DRIFT_REGISTERED"
        if [ -n "$DRIFT_UNTRACKED" ]; then
            printf '🛠️ Install drift (обратный): работают, но копии в репозитории нет — %s. На другой машине их не будет; импортируй в %s/hooks/ и зарегистрируй в install.sh, либо перенеси в репозиторий проекта, которому они принадлежат.\n' \
                "$(printf '%s' "${DRIFT_UNTRACKED% }")" \
                "$CLAUDSOUL_ROOT" >> "$SIGNALS_FILE"
        fi
    fi
fi

# If signals file empty — remove it to avoid injection overhead
if [ ! -s "$SIGNALS_FILE" ]; then
    rm -f "$SIGNALS_FILE"
fi

exit 0
