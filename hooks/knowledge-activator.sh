#!/usr/bin/env bash
# knowledge-activator.sh — PreToolUse[Bash|Edit|Write|MultiEdit]: инжектит SESSION.md и релевантные знания из global-lessons при первом действии сессии.
# en: PreToolUse[Bash|Edit|Write|MultiEdit]: injects SESSION.md and relevant knowledge from global-lessons on the first tool call.
# Scans the knowledge base and injects relevant lessons as systemMessage.
#
# Selective attention (v0.4.3):
#   - First fire: full injection (session context, memory, scan results, knowledge, Пункт 0)
#   - Re-fire: only on context shift (keywords overlap < 70%), не чаще раза в 5 мин
#     (SHIFT_MIN_SEC, env KA_SHIFT_MIN_SEC, по умолчанию 300 с)
#   - Context shift: lighter message (new knowledge only, no Пункт 0/session/memory)
#
# Session registry (v0.5.1):
#   - First fire: register session in active/, inject startup context (last session, delta, parallel)
#   - Uses session-registry-lib.sh for session lifecycle management
#
# Cross-domain transfer (v0.4.5):
#   - After main scoring, detect analogies: knowledge matching trigger/situation but NOT domain
#   - Inject as separate section: "📎 Возможные аналогии из других доменов"
#
# Multi-session safe: state files use SESSION_ID.
# Сканирует pattern-*, principle-* и кейсы-сироты — case-*, не упомянутые ни в одном
# паттерне/принципе (ORPHAN_CASES, см. ниже); остальные кейсы доходят через родителя.
# Logs to injection-log.jsonl: top-6 кандидатов с полями rank/injected, при этом
# в контекст уходит только top-3. Ранги 4-6 — контрольная группа для метрик:
# знание набрало score, но агент его не видел. Без неё эффект инжекта неотделим
# от «знание и так было релевантно». Тай-брейк при равных score — hash(sid:file),
# чтобы попадание в top-3 не зависело от имени и типа знания.
#
# Input: JSON on stdin from Claude Code (PreToolUse event)
# Output: JSON with systemMessage, or nothing (if cooldown / same context)

set -euo pipefail

KNOWLEDGE_DIR="$HOME/.claude/global-lessons"
PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"; : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
# STATE_DIR — из paths-lib (источается выше)
DOMAINS_DIR=""

# Find domains directory (project or global)
for d in "$PWD/domains" "$CLAUDSOUL_ROOT/domains"; do
    if [ -d "$d" ]; then DOMAINS_DIR="$d"; break; fi
done

# --- Domain Graph scoring (v0.5.4) — вынесено в sibling-библиотеку (Ф4) ---
# expand_domains_from_context / domain_graph_score. Подключается после
# установки DOMAINS_DIR (выше); функции вызываются ниже в основном потоке.
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/domain-graph-lib.sh"

# hash_value — детерминированный содержательно-нейтральный тай-брейк при равных
# score (см. блок сортировки ниже). Нужен для валидности контрольной группы.
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/hash-lib.sh"

# throttle_seen/throttle_mark — единственный jsonl-писатель проекта; ds_has_blocker_flag —
# единый парсер флага blocker. Оба нужны producer'у контура опровержения (см. ниже).
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/throttle-lib.sh"
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/detection-signals-lib.sh"

# iso_epoch/file_mtime — разводка BSD↔GNU (single source — see portable-lib.sh):
# `date -j` и `stat -f` понимает только BSD, на Linux хук падал на этих трёх вызовах.
# Ветка else — для установки, куда portable-lib.sh ещё не скопирован (install.sh
# кладёт hooks/*.sh целиком, но обновляется установка не сама).
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
else
    iso_epoch() { date -d "${1:-}" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "${1:-}" +%s 2>/dev/null || echo 0; }
    file_mtime() { stat -c %Y "${1:-}" 2>/dev/null || stat -f %m "${1:-}" 2>/dev/null || echo 0; }
fi

# Source session registry library
# Библиотека ищется СНАЧАЛА рядом с собой, и лишь потом в установленном каталоге.
# Прежде стоял только установленный путь, и на машине без ClaudSoul хук молча
# выходил целиком. Тесты этого не видели: они шли на машине, где установка есть,
# то есть проверяли установленную копию, а не репозиторий.
REGISTRY_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/session-registry-lib.sh"
[ -f "$REGISTRY_LIB" ] || REGISTRY_LIB="$HOME/.claude/hooks/session-registry-lib.sh"
if [ -f "$REGISTRY_LIB" ]; then
    source "$REGISTRY_LIB"
    HAS_REGISTRY=true
else
    HAS_REGISTRY=false
fi

# Source adaptive-stats-lib (v1.0.9) — speaker scoring, domain distance
ADAPTIVE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/adaptive-stats-lib.sh"
[ -f "$ADAPTIVE_LIB" ] || ADAPTIVE_LIB="$HOME/.claude/hooks/adaptive-stats-lib.sh"
if [ -f "$ADAPTIVE_LIB" ]; then
    # shellcheck disable=SC1090
    source "$ADAPTIVE_LIB"
    HAS_ADAPTIVE=true
else
    HAS_ADAPTIVE=false
fi

# Source fsrs-lib (v1.1.7) — FSRS-adapted decay
FSRS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/fsrs-lib.sh"
[ -f "$FSRS_LIB" ] || FSRS_LIB="$HOME/.claude/hooks/fsrs-lib.sh"
if [ -f "$FSRS_LIB" ]; then
    # shellcheck disable=SC1090
    source "$FSRS_LIB"
    HAS_FSRS=true
else
    HAS_FSRS=false
fi

# Session-specific state
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-$PPID}"
GATE_FILE="$STATE_DIR/knowledge_injected_${SESSION_ID}"
KEYWORDS_FILE="$STATE_DIR/last_keywords_${SESSION_ID}"
FIRST_FIRE="false"

# Current session speaker (v1.0.9) — computed on first access
CURRENT_SPEAKER="primary"
if [ "$HAS_ADAPTIVE" = "true" ]; then
    CURRENT_SPEAKER=$(score_speaker "$SESSION_ID" 2>/dev/null || echo "primary")
    [ -z "$CURRENT_SPEAKER" ] && CURRENT_SPEAKER="primary"
fi

mkdir -p "$STATE_DIR"

# Clean up stale state files (older than 24h)
find "$STATE_DIR" -name "knowledge_injected_*" -mtime +0 -delete 2>/dev/null || true
find "$STATE_DIR" -name "last_keywords_*" -mtime +0 -delete 2>/dev/null || true

# Первый заход в сессии — гейт ниже, у ключевых слов: решение о повторе нельзя принять,
# не зная темы вызова.
[ -f "$GATE_FILE" ] || FIRST_FIRE="true"

# Check dependencies
if ! command -v jq &>/dev/null; then
    exit 0
fi

# Check knowledge base exists and has files
if [ ! -d "$KNOWLEDGE_DIR" ]; then
    exit 0
fi

# Read input from stdin
INPUT=$(cat)

# Stable session_id from Claude Code payload — overrides PPID-based fallback
# in session-registry-lib.sh so registration uses the real UUID.
# resolve_session_id из paths-lib (источается выше); degrade к пустому = старое `// empty`.
PAYLOAD_SID=$(resolve_session_id "$INPUT" "" 2>/dev/null)
if [ -n "$PAYLOAD_SID" ] && [ "$HAS_REGISTRY" = true ]; then
    SR_SESSION_ID="$PAYLOAD_SID"
fi

# Extract context signals from tool_input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
COMMAND_TEXT=""
FILE_PATH=""

case "$TOOL_NAME" in
    Bash)
        COMMAND_TEXT=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
        ;;
    Edit|Write)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
        ;;
esac

# Build keyword set from context (lowercase for matching)
CONTEXT_KEYWORDS=""

if [ -n "$COMMAND_TEXT" ]; then
    # Extract meaningful words from command
    CONTEXT_KEYWORDS=$(echo "$COMMAND_TEXT" | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | sort -u | tr '\n' ' ' || true)
fi

if [ -n "$FILE_PATH" ]; then
    # Extract directory names and file extension
    CONTEXT_KEYWORDS="$CONTEXT_KEYWORDS $(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]' | \
        tr '/' ' ' | tr '.' ' ' | grep -oE '[a-z_]{3,}' | sort -u | tr '\n' ' ' || true)"
fi

# Also add CWD-derived context
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
if [ -n "$CWD" ]; then
    CONTEXT_KEYWORDS="$CONTEXT_KEYWORDS $(basename "$CWD" | tr '[:upper:]' '[:lower:]')"
fi

# If no context keywords, skip knowledge scoring but still inject session context
SKIP_KNOWLEDGE=false
if [ -z "$CONTEXT_KEYWORDS" ]; then
    SKIP_KNOWLEDGE=true
fi

# --- Гейт избирательного внимания: сдвиг темы + минимальный интервал ---
#
# Прежде пауза стояла ВЫШЕ чтения stdin и глушила хук, не посмотрев на тему вызова:
# внутри одного хода агента (25 вызовов, 8 минут, тема ушла от «хуки вообще» к
# «каналы доставки») знания не обновлялись ни разу. Между ходами это не всплывало —
# session-collector.sh снимает флаг на Stop, поэтому дефект был виден только в работе,
# то есть ровно там, где знание и нужно.
#
# Теперь порядок обратный: сначала тема, потом решение. Совпала с прошлой — молчим,
# сколько бы времени ни прошло. Сменилась — говорим, но не чаще SHIFT_MIN_SEC, иначе
# длинный ход с разнородными командами превратит подсказку в фон.
SHIFT_MIN_SEC="${KA_SHIFT_MIN_SEC:-300}"
CONTEXT_SHIFTED="true"
if [ "$FIRST_FIRE" = "false" ] && [ -f "$KEYWORDS_FILE" ] && [ "$SKIP_KNOWLEDGE" = "false" ]; then
    PREV_KEYWORDS=$(cat "$KEYWORDS_FILE" 2>/dev/null || true)
    if [ -n "$PREV_KEYWORDS" ]; then
        # Count overlap
        CURRENT_COUNT=0
        MATCH_COUNT=0
        for kw in $CONTEXT_KEYWORDS; do
            CURRENT_COUNT=$((CURRENT_COUNT + 1))
            if grep -qw "$kw" 2>/dev/null <<< "$PREV_KEYWORDS"; then
                MATCH_COUNT=$((MATCH_COUNT + 1))
            fi
        done
        if [ "$CURRENT_COUNT" -gt 0 ]; then
            OVERLAP=$(( (MATCH_COUNT * 100) / CURRENT_COUNT ))
            [ "$OVERLAP" -gt 70 ] && CONTEXT_SHIFTED="false"
        fi
    fi
fi

if [ "$FIRST_FIRE" = "false" ]; then
    # Та же тема — повтор бессмыслен.
    [ "$CONTEXT_SHIFTED" = "true" ] || exit 0
    # Тема сменилась, но слишком быстро после прошлого раза.
    if [ -f "$GATE_FILE" ]; then
        LAST_FIRE=$(cat "$GATE_FILE" 2>/dev/null || echo "0")
        case "${LAST_FIRE:-}" in ''|*[!0-9]*) LAST_FIRE=0 ;; esac
        [ $(( $(date +%s) - LAST_FIRE )) -lt "$SHIFT_MIN_SEC" ] && exit 0
    fi
fi

# Отметку ставим только пройдя гейт: иначе заглушённый вызов отодвигал бы интервал.
date +%s > "$GATE_FILE"

# Save current keywords for next comparison
echo "$CONTEXT_KEYWORDS" > "$KEYWORDS_FILE"

# Scoring: scan patterns and principles (skip if no context keywords)
declare -a RESULTS=()
declare -a ANALOGIES=()

if [ "$SKIP_KNOWLEDGE" = true ]; then
    # Jump to session context restoration
    :
else

# --- Domain Graph expansion (v0.5.4) ---
EXPANDED_DOMAINS=""
if [ -n "$DOMAINS_DIR" ]; then
    EXPANDED_DOMAINS=$(expand_domains_from_context "$CONTEXT_KEYWORDS")
fi

# Кейсы-сироты — те, что не упомянуты НИ В ОДНОМ паттерне или принципе. Их знание
# больше нигде не представлено, и до 26 августа 2026 они не попадали в контекст вовсе:
# основной цикл перебирал только обобщения, а единственная дверь для кейсов —
# семантический откат — открывается лишь когда поиск по ключевым словам почти пуст.
# База обобщений выросла с 8 до 31, поиск стал находить всегда, и дверь закрылась:
# подач кейсов 440 / 625 / 283 за апрель-июнь и НОЛЬ за июль и август.
#
# Берутся именно сироты, а не все кейсы: обобщённый кейс дублирует свой паттерн, и
# подавать оба — платить контекстом дважды за одно знание. Замер 2026-08-26: из 213
# кейсов упомянуты где-либо 157, сирот 56, из них 31 с impact 4-5, и верхушка по
# свежести — последний месяц, то есть теряется не архив, а то, что ещё не обобщено.
#
# Упоминание считается по ВСЕМУ файлу, а не по блоку `source_cases`: если кейс назван
# в теле паттерна, его знание представлено. Три способа счёта дали 77 / 83 / 56 —
# взят самый строгий, он же самый дешёвый (0,025 с) и не требует разбора YAML.
ORPHAN_CASES=""
if [ -d "$KNOWLEDGE_DIR" ]; then
    _cited_f=$(mktemp) && _all_f=$(mktemp) || true
    if [ -n "${_cited_f:-}" ] && [ -n "${_all_f:-}" ]; then
        cat "$KNOWLEDGE_DIR"/pattern-*.md "$KNOWLEDGE_DIR"/principle-*.md 2>/dev/null \
            | grep -oE 'case-[0-9a-z-]+' | LC_ALL=C sort -u > "$_cited_f" 2>/dev/null || true
        ls "$KNOWLEDGE_DIR"/case-*.md 2>/dev/null \
            | sed 's|.*/||; s|\.md$||' | LC_ALL=C sort > "$_all_f" 2>/dev/null || true
        ORPHAN_CASES=$(LC_ALL=C comm -23 "$_all_f" "$_cited_f" 2>/dev/null \
            | sed "s|^|$KNOWLEDGE_DIR/|; s|$|.md|" || true)
        rm -f "$_cited_f" "$_all_f" 2>/dev/null
    fi
fi

for file in "$KNOWLEDGE_DIR"/pattern-*.md "$KNOWLEDGE_DIR"/principle-*.md ${ORPHAN_CASES:-}; do
    [ -f "$file" ] || continue

    BASENAME=$(basename "$file")

    # Read frontmatter only (between first and second ---)
    FRONTMATTER=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$file")

    # Skip deprecated/weakened
    STATUS=$(echo "$FRONTMATTER" | grep '^status:' | sed 's/^status:[[:space:]]*//' | tr -d '"' || true)
    if [ "$STATUS" = "deprecated" ] || [ "$STATUS" = "weakened" ]; then
        continue
    fi

    # Per-speaker scope filter (v1.0.9)
    SCOPE=$(echo "$FRONTMATTER" | grep '^scope:' | sed 's/^scope:[[:space:]]*//' | tr -d '"' | head -1 || true)
    SCOPE="${SCOPE:-universal}"
    SPEAKER_STATUS="valid"
    if [ "$SCOPE" = "per-speaker" ] || [ "$SCOPE" = "mixed" ]; then
        VALID_FOR=$(echo "$FRONTMATTER" | grep '^valid_for:' | sed -E 's/^valid_for:[[:space:]]*\[//; s/\].*$//; s/,/ /g; s/"//g' || true)
        PENDING_FOR=$(echo "$FRONTMATTER" | grep '^pending_for:' | sed -E 's/^pending_for:[[:space:]]*\[//; s/\].*$//; s/,/ /g; s/"//g' || true)
        INVALID_FOR=$(echo "$FRONTMATTER" | grep '^invalid_for:' | sed -E 's/^invalid_for:[[:space:]]*\[//; s/\].*$//; s/,/ /g; s/"//g' || true)
        SPEAKER_STATUS="none"
        for s in $VALID_FOR; do
            [ "$s" = "$CURRENT_SPEAKER" ] && SPEAKER_STATUS="valid" && break
        done
        if [ "$SPEAKER_STATUS" = "none" ]; then
            for s in $PENDING_FOR; do
                [ "$s" = "$CURRENT_SPEAKER" ] && SPEAKER_STATUS="pending" && break
            done
        fi
        if [ "$SPEAKER_STATUS" = "none" ]; then
            for s in $INVALID_FOR; do
                [ "$s" = "$CURRENT_SPEAKER" ] && SPEAKER_STATUS="invalid" && break
            done
        fi
        # Skip if explicitly invalid, or per-speaker without any entry for current speaker
        [ "$SPEAKER_STATUS" = "invalid" ] && continue
        [ "$SCOPE" = "per-speaker" ] && [ "$SPEAKER_STATUS" = "none" ] && continue
        # mixed + none → fall through as universal fallback
        [ "$SPEAKER_STATUS" = "none" ] && SPEAKER_STATUS="valid"
    fi

    # Extract anchor fields (lowercase for matching)
    # || true needed because grep returns exit 1 on no match (kills set -e)
    DOMAINS=$(echo "$FRONTMATTER" | grep '^domain:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)
    SITUATION=$(echo "$FRONTMATTER" | grep '^situation:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)
    TRIGGER=$(echo "$FRONTMATTER" | grep '^trigger:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)
    TAGS=$(echo "$FRONTMATTER" | grep '^tags:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)
    STAKES=$(echo "$FRONTMATTER" | grep '^stakes:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)
    ENVIRONMENT=$(echo "$FRONTMATTER" | grep '^environment:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)
    CIRCUMSTANCES=$(echo "$FRONTMATTER" | grep '^circumstances:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)
    PURPOSE=$(echo "$FRONTMATTER" | grep '^purpose:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)
    METHOD=$(echo "$FRONTMATTER" | grep '^method:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)

    # Extract demand components
    NEED=$(echo "$FRONTMATTER" | grep '^need:' | sed 's/^need:[[:space:]]*//' | tr -d '"' || true)
    URGENCY=$(echo "$FRONTMATTER" | grep '^urgency:' | sed 's/^urgency:[[:space:]]*//' | tr -d '"' || true)
    AVAILABILITY=$(echo "$FRONTMATTER" | grep '^availability:' | sed 's/^availability:[[:space:]]*//' | tr -d '"' || true)

    # Extract confidence, impact, intensity, confirmed_count for priority/decay
    CONFIDENCE=$(echo "$FRONTMATTER" | grep '^confidence:' | grep -oE '[0-9]+' | head -1 || true)
    IMPACT=$(echo "$FRONTMATTER" | grep '^impact:' | grep -oE '[0-9]+' | head -1 || true)
    INTENSITY=$(echo "$FRONTMATTER" | grep '^intensity:' | grep -oE '[0-9]+' | head -1 || true)
    CONFIRMED_COUNT=$(echo "$FRONTMATTER" | grep '^confirmed_count:' | grep -oE '[0-9]+' | head -1 || true)
    # Знание с нечитаемыми confidence/impact ИСКЛЮЧАЕТСЯ из ранжирования, а не получает
    # единицу. Ноль правдив там, где читается СЧЁТ; здесь читается ЗНАЧЕНИЕ ПОЛЯ, и
    # подстановка делает нечитаемую запись неотличимой от честной записи с confidence 1 —
    # она молча участвует в отборе как измеренная. Достижимость на 29 августа 2026: в базе
    # таких записей 0 из 396, но битая шапка уже случалась в этот же день и прожила часы.
    if [ -z "$CONFIDENCE" ] || [ -z "$IMPACT" ]; then
        continue
    fi
    INTENSITY="${INTENSITY:-0}"
    CONFIRMED_COUNT="${CONFIRMED_COUNT:-0}"

    # Fragile flag (v1.0.8): pattern/principle with ≥ 3 modifications
    FRAGILE=$(echo "$FRONTMATTER" | grep '^fragile:' | sed 's/^fragile:[[:space:]]*//' | tr -d '"' | head -1 || true)
    FRAGILE="${FRAGILE:-false}"
    MOD_BLOCK=$(echo "$FRONTMATTER" | awk '
        /^modification_history:/ { inside=1; next }
        inside && /^[a-zA-Z_]+:/ { exit }
        inside { print }
    ')
    MOD_COUNT=$({ echo "$MOD_BLOCK" | grep -cE '^[[:space:]]*-[[:space:]]*date:' 2>/dev/null; } || echo 0)
    MOD_COUNT=$(echo "$MOD_COUNT" | head -1)
    MOD_COUNT="${MOD_COUNT:-0}"

    # Extract last_confirmed for surprise_bonus decay calculation
    LAST_CONFIRMED=$(echo "$FRONTMATTER" | grep '^last_confirmed:' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)

    # Extract name/description for display.
    # tr '|' '/' — RESULTS/ANALOGIES pipe-разделённые; `|` внутри name/description
    # сдвигает поля при read и рождает битые строки injection-log (4 файла базы
    # уже содержат его). Та же санитизация есть в knowledge-semantic-fallback-lib.
    NAME=$(echo "$FRONTMATTER" | grep '^name:' | sed 's/^name:[[:space:]]*//' | tr -d '"' | tr '|' '/' || true)
    DESC=$(echo "$FRONTMATTER" | grep '^description:' | sed 's/^description:[[:space:]]*//' | tr -d '"' | tr '|' '/' || true)

    # Extract critical_anchors (if any anchor is critical and has no match — skip knowledge)
    CRITICAL=$(echo "$FRONTMATTER" | grep '^critical_anchors:' | tr '[:upper:]' '[:lower:]' | \
        grep -oE '[a-z_]{3,}' | tr '\n' ' ' || true)

    # Extract weight_modifiers: format "anchor:value->target:weight" (e.g. "method:trained->environment:1")
    WEIGHT_MODS=$(echo "$FRONTMATTER" | grep '^weight_modifiers:' | sed 's/^weight_modifiers:[[:space:]]*//' | tr -d '"[]' || true)

    # Calculate score with weighted anchors
    SCORE=0
    SKIP=false

    # Base weights per anchor type (×10 for integer math, divided later)
    # High: situation, trigger, stakes (most specific)
    # Medium: domain, environment, circumstances, purpose, method
    # Low: actors (least discriminating)
    W_DOMAIN=20; W_SITUATION=30; W_TRIGGER=30; W_STAKES=30
    W_ACTORS=10; W_ENVIRONMENT=20; W_CIRCUMSTANCES=20
    W_PURPOSE=20; W_METHOD=20

    # Apply relational weight modifiers
    # Format: "anchor:value->target:weight,anchor:value->target:weight"
    if [ -n "$WEIGHT_MODS" ]; then
        for mod in $(echo "$WEIGHT_MODS" | tr ',' ' '); do
            # Parse "source_anchor:value->target_anchor:new_weight"
            SRC=$(echo "$mod" | sed 's/->.*$//' || true)
            TGT=$(echo "$mod" | sed 's/^.*->//' || true)
            SRC_ANCHOR=$(echo "$SRC" | cut -d: -f1 || true)
            SRC_VALUE=$(echo "$SRC" | cut -d: -f2 || true)
            TGT_ANCHOR=$(echo "$TGT" | cut -d: -f1 || true)
            TGT_WEIGHT=$(echo "$TGT" | cut -d: -f2 || true)

            # Check if source anchor value matches context
            if [ -n "$SRC_VALUE" ] && [ -n "$TGT_WEIGHT" ]; then
                case "$SRC_ANCHOR" in
                    method) SRC_DATA="$METHOD" ;;
                    environment) SRC_DATA="$ENVIRONMENT" ;;
                    domain) SRC_DATA="$DOMAINS" ;;
                    situation) SRC_DATA="$SITUATION" ;;
                    *) SRC_DATA="" ;;
                esac
                if [ -n "$SRC_DATA" ] && grep -qw "$SRC_VALUE" 2>/dev/null <<< "$SRC_DATA"; then
                    # Modify target weight (×10)
                    NEW_W=$((TGT_WEIGHT * 10))
                    case "$TGT_ANCHOR" in
                        environment) W_ENVIRONMENT=$NEW_W ;;
                        circumstances) W_CIRCUMSTANCES=$NEW_W ;;
                        domain) W_DOMAIN=$NEW_W ;;
                        situation) W_SITUATION=$NEW_W ;;
                        trigger) W_TRIGGER=$NEW_W ;;
                        stakes) W_STAKES=$NEW_W ;;
                        purpose) W_PURPOSE=$NEW_W ;;
                        method) W_METHOD=$NEW_W ;;
                    esac
                fi
            fi
        done
    fi

    # Check critical anchors — all must have at least one keyword match
    if [ -n "$CRITICAL" ]; then
        for crit in $CRITICAL; do
            CRIT_DATA=""
            case "$crit" in
                domain) CRIT_DATA="$DOMAINS" ;;
                situation) CRIT_DATA="$SITUATION" ;;
                trigger) CRIT_DATA="$TRIGGER" ;;
                stakes) CRIT_DATA="$STAKES" ;;
                environment) CRIT_DATA="$ENVIRONMENT" ;;
                circumstances) CRIT_DATA="$CIRCUMSTANCES" ;;
                purpose) CRIT_DATA="$PURPOSE" ;;
                method) CRIT_DATA="$METHOD" ;;
            esac
            if [ -n "$CRIT_DATA" ]; then
                CRIT_MATCH=false
                for keyword in $CONTEXT_KEYWORDS; do
                    if grep -qw "$keyword" 2>/dev/null <<< "$CRIT_DATA"; then
                        CRIT_MATCH=true
                        break
                    fi
                done
                if [ "$CRIT_MATCH" = false ]; then
                    SKIP=true
                    break
                fi
            fi
        done
    fi

    if [ "$SKIP" = true ]; then
        continue
    fi

    # Score each anchor with its weight
    # Track domain/trigger/situation matches separately for cross-domain detection
    ALL_TAGS="$TAGS"
    DOMAIN_MATCH=0
    TRIGGER_MATCH=0
    SITUATION_MATCH=0

    # Domain Graph scoring (v0.5.4): check each knowledge domain against expanded graph
    if [ -n "$EXPANDED_DOMAINS" ] && [ -n "$DOMAINS" ]; then
        for dom in $DOMAINS; do
            GRAPH_W=$(domain_graph_score "$dom" "$EXPANDED_DOMAINS")
            if [ "$GRAPH_W" -gt 0 ] 2>/dev/null; then
                SCORE=$((SCORE + GRAPH_W))
                DOMAIN_MATCH=$((DOMAIN_MATCH + 1))
            fi
        done
    fi

    for keyword in $CONTEXT_KEYWORDS; do
        # Direct domain keyword match (fallback when no graph)
        if [ -z "$EXPANDED_DOMAINS" ] && [ -n "$DOMAINS" ] && grep -qw "$keyword" 2>/dev/null <<< "$DOMAINS"; then
            SCORE=$((SCORE + W_DOMAIN))
            DOMAIN_MATCH=$((DOMAIN_MATCH + 1))
        fi
        if [ -n "$SITUATION" ] && grep -qw "$keyword" 2>/dev/null <<< "$SITUATION"; then
            SCORE=$((SCORE + W_SITUATION))
            SITUATION_MATCH=$((SITUATION_MATCH + 1))
        fi
        if [ -n "$TRIGGER" ] && grep -qw "$keyword" 2>/dev/null <<< "$TRIGGER"; then
            SCORE=$((SCORE + W_TRIGGER))
            TRIGGER_MATCH=$((TRIGGER_MATCH + 1))
        fi
        if [ -n "$STAKES" ] && grep -qw "$keyword" 2>/dev/null <<< "$STAKES"; then
            SCORE=$((SCORE + W_STAKES))
        fi
        if [ -n "$ENVIRONMENT" ] && grep -qw "$keyword" 2>/dev/null <<< "$ENVIRONMENT"; then
            SCORE=$((SCORE + W_ENVIRONMENT))
        fi
        if [ -n "$CIRCUMSTANCES" ] && grep -qw "$keyword" 2>/dev/null <<< "$CIRCUMSTANCES"; then
            SCORE=$((SCORE + W_CIRCUMSTANCES))
        fi
        if [ -n "$PURPOSE" ] && grep -qw "$keyword" 2>/dev/null <<< "$PURPOSE"; then
            SCORE=$((SCORE + W_PURPOSE))
        fi
        if [ -n "$METHOD" ] && grep -qw "$keyword" 2>/dev/null <<< "$METHOD"; then
            SCORE=$((SCORE + W_METHOD))
        fi
        # Tag match = +10 (was +1, now ×10 scale)
        if [ -n "$ALL_TAGS" ] && grep -qw "$keyword" 2>/dev/null <<< "$ALL_TAGS"; then
            SCORE=$((SCORE + 10))
        fi
    done

    # Divide back from ×10 scale
    SCORE=$((SCORE / 10))

    # Priority bonus: confidence × impact × 0.1 (integer math: × 1 / 10)
    PRIORITY_BONUS=$(( (CONFIDENCE * IMPACT) / 10 ))
    SCORE=$((SCORE + PRIORITY_BONUS))

    # Demand bonus: urgency and availability affect priority ranking
    # urgency: immediate=+3, next_session=+2, when_relevant=+1, background=0
    case "$URGENCY" in
        immediate)      SCORE=$((SCORE + 3)) ;;
        next_session)   SCORE=$((SCORE + 2)) ;;
        when_relevant)  SCORE=$((SCORE + 1)) ;;
    esac
    # availability: unique=+2, common_knowledge=-1
    case "$AVAILABILITY" in
        unique)           SCORE=$((SCORE + 2)) ;;
        common_knowledge) SCORE=$((SCORE - 1)) ;;
    esac

    # Surprise bonus: intensity × max(0, 1 - days_since_created / 180)
    # Decays over 180 days — fresh surprises activate stronger
    if [ "$INTENSITY" -gt 0 ] 2>/dev/null && [ -n "$LAST_CONFIRMED" ]; then
        TODAY_SEC=$(date +%s)
        # Голая дата отдаётся в iso_epoch без формата намеренно: там она приводится
        # к полуночи явно, иначе BSD подставил бы текущее время суток, а GNU — полночь,
        # и DAYS_SINCE расходился бы между машинами. Ноль = разобрать не удалось →
        # прежний фоллбек на сегодня (сюрприз считается свежим, а не протухшим).
        CREATED_SEC=$(iso_epoch "$LAST_CONFIRMED")
        [ "${CREATED_SEC:-0}" -gt 0 ] 2>/dev/null || CREATED_SEC="$TODAY_SEC"
        DAYS_SINCE=$(( (TODAY_SEC - CREATED_SEC) / 86400 ))
        if [ "$DAYS_SINCE" -lt 180 ]; then
            # Integer math: intensity × (180 - days) / 180
            SURPRISE_BONUS=$(( INTENSITY * (180 - DAYS_SINCE) / 180 ))
            SCORE=$((SCORE + SURPRISE_BONUS))
        fi
    fi

    # FSRS decay (v1.1.7): overdue knowledge gets a score penalty and visual marker.
    # Formula lives in fsrs-lib.sh. Fresh/due → no penalty; overdue → 0.8×; critical → 0.5×.
    FSRS_STATUS="fresh"
    if [ "${HAS_FSRS:-false}" = "true" ] && [ -n "$LAST_CONFIRMED" ]; then
        FSRS_OVERDUE=$(fsrs_days_overdue "$LAST_CONFIRMED" "$CONFIRMED_COUNT" "$IMPACT" 2>/dev/null || echo 0)
        FSRS_STATUS=$(fsrs_review_status "$FSRS_OVERDUE" 2>/dev/null || echo "fresh")
        FSRS_PENALTY=$(fsrs_score_penalty_num "$FSRS_STATUS" 2>/dev/null || echo 100)
        if [ "$FSRS_PENALTY" -lt 100 ] && [ "$SCORE" -gt 0 ]; then
            SCORE=$(( SCORE * FSRS_PENALTY / 100 ))
        fi
    fi

    # Minimum threshold
    if [ "$SCORE" -ge 1 ]; then
        RESULTS+=("$SCORE|$BASENAME|$NAME|$DESC|$CONFIDENCE|$IMPACT|$FRAGILE|$MOD_COUNT|$SCOPE|$SPEAKER_STATUS|$FSRS_STATUS")
    fi

    # Cross-domain analogy detection (v0.4.5):
    # Knowledge matches trigger/situation but NOT domain → analogy from another domain
    if [ "$DOMAIN_MATCH" -eq 0 ] && [ $((TRIGGER_MATCH + SITUATION_MATCH)) -ge 1 ] && [ "$SCORE" -ge 1 ]; then
        # Build match reason
        MATCH_REASON=""
        if [ "$TRIGGER_MATCH" -gt 0 ]; then MATCH_REASON="trigger"; fi
        if [ "$SITUATION_MATCH" -gt 0 ]; then
            if [ -n "$MATCH_REASON" ]; then MATCH_REASON="${MATCH_REASON}+situation"; else MATCH_REASON="situation"; fi
        fi
        ANALOGIES+=("$SCORE|$BASENAME|$NAME|$DESC|$CONFIDENCE|$IMPACT|$MATCH_REASON|$DOMAINS")
    fi
done

# End of knowledge scoring block
fi

# --- MCP semantic-search fallback (мост L1↔L2) — вынесено в sibling-библиотеку (Ф4) ---
# Логика в knowledge-semantic-fallback-lib.sh (закрывает vocabulary gap keyword-скоринга).
# Trigger: top keyword score < 3 OR < 2 keyword results. SKIP_MCP_FALLBACK=1 для тестов.
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/knowledge-semantic-fallback-lib.sh"
if [ "${SKIP_MCP_FALLBACK:-0}" != "1" ] && [ "$SKIP_KNOWLEDGE" != "true" ]; then
    KW_TOP_SCORE=0
    if [ "${#RESULTS[@]}" -gt 0 ]; then
        KW_TOP_SCORE=$(printf '%s\n' "${RESULTS[@]}" | sort -t'|' -k1 -nr | head -1 | cut -d'|' -f1)
    fi
    MCP_QUERY="$COMMAND_TEXT $FILE_PATH $(basename "${CWD:-/}")"
    MCP_QUERY=$(echo "$MCP_QUERY" | tr -s ' ' | sed 's/^ *//;s/ *$//')
    SEEN_BASENAMES=""
    # `${RESULTS[@]+...}` — bash 3.2 (системный на macOS) под `set -u` считает
    # развёртывание ПУСТОГО массива обращением к unset и роняет хук. Это ровно тот
    # случай, ради которого fallback и существует: keyword-скоринг не нашёл ничего.
    # См. pattern-shell-portability.
    for r in ${RESULTS[@]+"${RESULTS[@]}"}; do
        SEEN_BASENAMES="$SEEN_BASENAMES|$(echo "$r" | cut -d'|' -f2)|"
    done
    while IFS= read -r _mcp_line; do
        [ -n "$_mcp_line" ] && RESULTS+=("$_mcp_line")
    done < <(mcp_semantic_fallback "$CLAUDSOUL_ROOT" "$MCP_QUERY" "$KW_TOP_SCORE" "${#RESULTS[@]}" "$SEEN_BASENAMES")
fi

# Sort by score (desc). Инжектим top-3, логируем top-6: ранги 4-6 — контрольная
# группа (знание набрало score, но в контекст не попало). Без неё вопрос «черта
# возникает сама или наведена инжектом» неотвечаем: интервенция применена к 100%
# ходов, сравнивать не с чем.
SORTED=""
if [ ${#RESULTS[@]} -gt 0 ]; then
    LOG_SID="${PAYLOAD_SID:-${SR_SESSION_ID:-default}}"
    LOG_PROJECT=$(basename "$(find_project_root "${CWD:-$PWD}")" 2>/dev/null || echo "unknown")

    # Тай-брейк при равных score: hash(session_id:basename). Дефолтный
    # `sort -t'|' -k1 -nr` при равенстве уходит в сравнение всей строки в обратном
    # порядке — «principle-*» систематически обходит «pattern-*», а внутри типа
    # выигрывает алфавитно-поздний файл. Это коррелирует с содержанием: разрыв на
    # ранге 3 мерил бы «эффект быть принципом», а не эффект инжекта. Хеш даёт
    # локальную рандомизацию внутри группы равных (порядок фиксирован в пределах
    # сессии, перетасован между сессиями) и попутно лечит вечное голодание
    # алфавитно-поздних знаний в ничейных группах.
    # ponytail: md5 на кандидата (~30 вызовов); один awk-проход, если станет узким.
    SORTED_ALL=$(
        for _r in "${RESULTS[@]}"; do
            _bn="${_r#*|}"; _bn="${_bn%%|*}"
            printf '%s\t%s\t%s\n' "${_r%%|*}" "$(hash_value "${LOG_SID}:${_bn}")" "$_r"
        done | LC_ALL=C sort -t"$(printf '\t')" -k1,1nr -k2,2 | cut -f3-
    )
    # Отдельная квота для сирот: три места обобщениям и одно кейсу. Без разделения
    # 56 кейсов конкурировали бы с 40 обобщениями за те же три слота и вытесняли бы
    # правило конкретным случаем — а правило применимо шире. Один слот означает:
    # эпизод приходит как дополнение к правилу, а не вместо него.
    SORTED_GEN=$(printf '%s\n' "$SORTED_ALL" | grep -v '|case-' | head -3 || true)
    SORTED_CASE=$(printf '%s\n' "$SORTED_ALL" | grep '|case-' | head -1 || true)
    SORTED=$(printf '%s\n%s' "$SORTED_GEN" "$SORTED_CASE" | grep -v '^[[:space:]]*$' || true)

    # --- Injection logging (hit_rate metrics + контрольная группа рангов 4-6) ---
    # Сборка через jq, а не printf: поля приходят из frontmatter и содержат запятые,
    # двоеточия и кавычки — printf рождал невалидный JSON (173 битые строки из 7665,
    # см. metrics-collector). `tonumber? // 0` закрывает пустые числовые поля.
    INJECTION_LOG="$STATE_DIR/injection-log.jsonl"
    # UTC с суффиксом Z (v1.12.0). Раньше писалось локальное время без суффикса, и
    # джойн с `correction-fired` (он всегда UTC) разъезжался на смещение пояса.
    # Старые строки не переписываем: отсутствие `Z` — сам по себе маркер шкалы,
    # читатель различает по нему (см. _dis_epoch в disagreement-lib.sh).
    LOG_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    printf '%s\n' "$SORTED_ALL" | head -6 | jq -Rcn \
        --arg date "$LOG_DATE" --arg sid "$LOG_SID" --arg project "$LOG_PROJECT" '
        [inputs] | to_entries[] | .key as $i | (.value | split("|")) as $f |
        {date: $date, file: $f[1],
         score:      ($f[0] | tonumber? // 0),
         confidence: ($f[4] | tonumber? // 0),
         impact:     ($f[5] | tonumber? // 0),
         scope:          (if ($f[8]  // "") == "" then "universal" else $f[8]  end),
         speaker_status: (if ($f[9]  // "") == "" then "valid"     else $f[9]  end),
         fsrs_status:    (if ($f[10] // "") == "" then "fresh"     else $f[10] end),
         rank: ($i + 1), injected: ($i < 3),
         session_id: $sid, project: $project,
         via: (if $f[3] == "mcp-semantic" then "mcp" else "keyword" end)}
        ' >> "$INJECTION_LOG" 2>/dev/null || true

    # --- Ротация лога (D45) ------------------------------------------------------
    #
    # Замер на момент заведения: 8497 строк / 1,68 МБ, разброс дат 15 апреля — сегодня;
    # ни `-delete`, ни обрезки ни в одном хуке. Файл рос третий месяц.
    #
    # Обрезать можно ТОЛЬКО по возрасту и только здесь, в писателе: `dis_harvest_corrections`
    # (disagreement-lib.sh:165) сопоставляет поправки собеседника с инжектами ТОЙ ЖЕ сессии
    # по `session_id`. Обрезка «оставить последние N строк» разорвала бы пару в середине
    # сессии и молча сломала контур опровержения — единственный канал, который вообще
    # умеет опровергать знание.
    #
    # Старые строки не удаляются, а уезжают в архив: `metrics-collector` считает по логу
    # суммарное число инжекций, и простое удаление уронило бы показатель без объяснения.
    if [ -f "$INJECTION_LOG" ] && command -v python3 >/dev/null 2>&1; then
        INJECTION_ARCHIVE="${INJECTION_LOG%.jsonl}-archive.jsonl"
        INJECTION_KEEP_DAYS="${INJECTION_LOG_KEEP_DAYS:-60}"
        python3 - "$INJECTION_LOG" "$INJECTION_ARCHIVE" "$INJECTION_KEEP_DAYS" <<'ROTATE' 2>/dev/null || true
import datetime, json, os, pathlib, sys

log, archive, keep_days = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), int(sys.argv[3])
# Дешёвый гейт: не разбирать файл на каждом инжекте, только когда он вырос.
if log.stat().st_size < int(os.environ.get("INJECTION_LOG_MIN_BYTES", "524288")):
    raise SystemExit
cut = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=keep_days)).strftime("%Y-%m-%d")
keep, old = [], []
for line in log.read_text(errors="replace").splitlines(True):
    try:
        d = json.loads(line)
        (keep if str(d.get("date", ""))[:10] >= cut else old).append(line)
    except Exception:
        keep.append(line)   # битую строку не выбрасываем: её считает отдельная метрика
if not old:
    raise SystemExit
with archive.open("a", encoding="utf-8") as fh:
    fh.writelines(old)
log.write_text("".join(keep), encoding="utf-8")
ROTATE
    fi
fi

# Build systemMessage
MESSAGE=""

# --- First fire only: session context, project memory, scan results ---
if [ "$FIRST_FIRE" = "true" ]; then

    # Session registry: register this session + get startup context
    if [ "$HAS_REGISTRY" = true ]; then
        sr_register_session
        STARTUP_CTX=$(sr_get_startup_context 2>/dev/null || true)
        if [ -n "$STARTUP_CTX" ]; then
            MESSAGE="${MESSAGE}🔄 SESSION REGISTRY:\\n${STARTUP_CTX}\\n\\n"
        fi
    fi

    # Checkpoint resume check (v0.6.2)
    SESSIONS_DIR="$HOME/.claude/sessions"
    if [ -d "$SESSIONS_DIR" ]; then
        # Find most recent checkpoint.json that is NOT done
        LATEST_CHECKPOINT=""
        for cpf in "$SESSIONS_DIR"/*/checkpoint.json; do
            [ -f "$cpf" ] || continue
            CP_PHASE=$(python3 -c "import json; d=json.load(open('$cpf')); print(d.get('phase',''))" 2>/dev/null || true)
            if [ -n "$CP_PHASE" ] && [ "$CP_PHASE" != "done" ] && [ "$CP_PHASE" != "abandoned" ]; then
                LATEST_CHECKPOINT="$cpf"
            fi
        done
        if [ -n "$LATEST_CHECKPOINT" ]; then
            CP_INFO=$(python3 -c "
import json
d=json.load(open('$LATEST_CHECKPOINT'))
coord=d.get('coordinator','?')
task=d.get('context',{}).get('task','?')
pending=', '.join(w.get('worker','?') for w in d.get('workers_pending',[]))
print(f'{coord}: {task} | pending: {pending}')
" 2>/dev/null || true)
            if [ -n "$CP_INFO" ]; then
                MESSAGE="${MESSAGE}⚠️ НЕЗАВЕРШЁННАЯ ОПЕРАЦИЯ координатора: ${CP_INFO}\\nРекомендация: запустить /knowledge auto для продолжения\\n\\n"
            fi
        fi
    fi

    # Session context restoration — resolve project root via walk-up (F13).
    PROJ_ROOT="$CWD"; command -v find_project_root >/dev/null 2>&1 && PROJ_ROOT=$(find_project_root "$CWD")
    if [ -n "$CWD" ] && [ -f "$PROJ_ROOT/SESSION.md" ]; then
        LAST_SESSION=$(awk '
            /^## / { buf = ""; capture = 1 }
            capture { buf = buf $0 "\n" }
            END { printf "%s", buf }
        ' "$PROJ_ROOT/SESSION.md" | head -60)
        if [ -n "$LAST_SESSION" ]; then
            LAST_SESSION_ESCAPED=$(echo "$LAST_SESSION" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | sed 's/ *$//')
            MESSAGE="${MESSAGE}🔄 LAST SESSION CONTEXT (from SESSION.md):\\n${LAST_SESSION_ESCAPED}\\n\\n"
        fi
    fi

    # Project memory restoration
    MEMORY_DIR="$HOME/.claude/projects"
    if [ -n "$CWD" ]; then
        MEMORY_PATH=$(echo "$CWD" | sed 's|/|-|g')
        PROJ_MEMORY_DIR="$MEMORY_DIR/$MEMORY_PATH/memory"
        if [ -d "$PROJ_MEMORY_DIR" ] && [ -f "$PROJ_MEMORY_DIR/MEMORY.md" ]; then
            MEMORY_INDEX=$(head -20 "$PROJ_MEMORY_DIR/MEMORY.md" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
            if [ -n "$MEMORY_INDEX" ]; then
                MESSAGE="${MESSAGE}📝 Project memory index:\\n${MEMORY_INDEX}\\n\\n"
            fi
        fi
    fi

    # Auto-scan results
    SCAN_RESULTS_FILE="$STATE_DIR/scan-results.md"
if [ -f "$SCAN_RESULTS_FILE" ]; then
    # Only inject if scan is fresh (less than 24h old)
    SCAN_AGE=$(( $(date +%s) - $(file_mtime "$SCAN_RESULTS_FILE") ))
    if [ "$SCAN_AGE" -lt 86400 ]; then
        # Check if there are actual findings (not just "nothing found")
        if grep -q "^###" "$SCAN_RESULTS_FILE" 2>/dev/null; then
            SCAN_SUMMARY=$(grep -E '^(\*\*|###|-\s)' "$SCAN_RESULTS_FILE" | head -15 | \
                sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
            if [ -n "$SCAN_SUMMARY" ]; then
                MESSAGE="${MESSAGE}🔍 Результаты автосканирования проектов:\\n${SCAN_SUMMARY}\\n\\n"
            fi
        fi
    fi
fi

    # Entity cards injection (v1.1.5) — second-contour knowledge
    # Calls `ingest.cli activate` with current context; renders top entity cards.
    # Graceful: any failure (missing CLI, timeout, invalid JSON) → silent skip.
    if [ "${SKIP_ENTITY_ACTIVATION:-0}" != "1" ] && [ -d "$KNOWLEDGE_DIR" ]; then
        ENT_PY=""
        ENT_CLI_ROOT=""
        for root in "$PWD/mcp-server" "$CLAUDSOUL_ROOT/mcp-server"; do
            if [ -x "$root/.venv/bin/python" ] && [ -f "$root/ingest/cli.py" ]; then
                ENT_PY="$root/.venv/bin/python"
                ENT_CLI_ROOT="$root"
                break
            fi
        done

        if [ -n "$ENT_PY" ]; then
            ENT_QUERY="$COMMAND_TEXT $FILE_PATH"
            ENT_QUERY=$(echo "$ENT_QUERY" | tr -s ' ' | sed 's/^ *//;s/ *$//')

            if [ -n "$ENT_QUERY" ]; then
                ENT_TIMEOUT=""
                if command -v timeout >/dev/null 2>&1; then
                    ENT_TIMEOUT="timeout 2"
                elif command -v gtimeout >/dev/null 2>&1; then
                    ENT_TIMEOUT="gtimeout 2"
                fi

                ENT_JSON=$(cd "$ENT_CLI_ROOT" && $ENT_TIMEOUT "$ENT_PY" -m ingest.cli activate \
                    "$ENT_QUERY" --lessons-dir "$KNOWLEDGE_DIR" --limit 3 2>/dev/null || echo "[]")

                ENT_CARDS=$(echo "$ENT_JSON" | jq -r '
                    .[] | "\(.name)|\(.entity_type // "?")|\(.confidence // 1)|\(.attributes_summary | join(", "))"
                ' 2>/dev/null || true)

                if [ -n "$ENT_CARDS" ]; then
                    ENT_MSG="🧬 Relevant entities (second contour):\\n"
                    ENT_INDEX=1
                    while IFS='|' read -r E_NAME E_TYPE E_CONF E_ATTRS; do
                        [ -z "$E_NAME" ] && continue
                        ENT_LINE="${ENT_INDEX}. ${E_NAME} (${E_TYPE}, conf:${E_CONF})"
                        if [ -n "$E_ATTRS" ] && [ "$E_ATTRS" != "null" ]; then
                            ENT_LINE="${ENT_LINE} — ${E_ATTRS}"
                        fi
                        ENT_MSG="${ENT_MSG}${ENT_LINE}\\n"
                        ENT_INDEX=$((ENT_INDEX + 1))
                    done <<< "$ENT_CARDS"
                    ENT_MSG="${ENT_MSG}Если упоминается — используй как контекст, не уточняй заново.\\n\\n"
                    MESSAGE="${MESSAGE}${ENT_MSG}"
                fi
            fi
        fi
    fi

    # Metrics summary (only warnings)
    METRICS_FILE="$STATE_DIR/metrics.md"
    if [ -f "$METRICS_FILE" ]; then
        METRICS_AGE=$(( $(date +%s) - $(file_mtime "$METRICS_FILE") ))
        if [ "$METRICS_AGE" -lt 86400 ]; then
            # Читаем ОБА префикса продюсера. `- ⚠️` — предупреждение, `- 📋` — выполненное
            # условие возврата отложенного пункта долга (metrics-collector.sh:422-440).
            # Читатель брал только первый, поэтому условия возврата D16-D20 писались в
            # metrics.md и не доходили никуда: строка «BACKLOG D19: вмешательств 163 ≥ 30»
            # лежала выполненной и невидимой. Продюсер и потребитель канала были написаны
            # врозь, и пару не проверял ни один тест — теперь проверяет test_metrics_channel.sh.
            METRICS_WARNINGS=$(grep -E '^- (⚠️|📋)' "$METRICS_FILE" 2>/dev/null | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' || true)
            if [ -n "$METRICS_WARNINGS" ]; then
                MESSAGE="${MESSAGE}📊 Метрики здоровья знаний: ${METRICS_WARNINGS}\\n\\n"
            fi
        fi
    fi

fi  # end FIRST_FIRE block

# Knowledge injection (always — this is the selective attention part)
if [ ${#RESULTS[@]} -gt 0 ]; then
    MESSAGE="${MESSAGE}📚 Relevant knowledge from previous sessions:\\n\\n"
    INDEX=1

    # Producer контура опровержения. Читателя (session-collector.sh) написали
    # v0.4.6, писателя не было ни одного дня: 0 файлов disagreement-pending на
    # 1239 в state/, и как следствие contradicted_count = 0 во всех 265 знаниях.
    # Счётчик, который умеет только расти, ничего не измеряет.
    #
    # Точка выбрана здесь, а не в blocker-tier-check: там 90% срабатываний — один
    # сигнал на правку четырёх markdown-документов, встречи знания с решением в
    # этом почти нет. Здесь же скоринг признал знание релевантным конкретному
    # вызову мутирующего инструмента.
    #
    # Узко по решению собеседника: только знания уровня блокера (3 файла), не все
    # confidence>=4 (15 файлов). Ожидаемо 1-2 записи за сессию вместо 1-4 — алерт,
    # ставший фоном, не закрывают, и контур умирает второй раз, теперь от шума.
    DIS_SID="${PAYLOAD_SID:-$SESSION_ID}"
    DIS_LOG="$STATE_DIR/disagreement-pending-${DIS_SID}.jsonl"

    while IFS='|' read -r SCORE BASENAME NAME DESC CONF IMP FRAG MODS SCP SPK FSRS; do
        # Fragile marker (v1.0.8): pattern/principle with ≥ 3 modifications in history
        FRAGILE_TAG=""
        if [ "$FRAG" = "true" ] 2>/dev/null; then
            FRAGILE_TAG=" ⚠️ fragile (${MODS} модификаций — сверь контекст)"
        fi
        # Speaker-scope marker (v1.0.9): pending confirmation for this speaker
        SPEAKER_TAG=""
        if [ "$SPK" = "pending" ] 2>/dev/null; then
            SPEAKER_TAG=" 🗣️ pending для speaker=${CURRENT_SPEAKER} — подтверди применимость"
        fi
        # FSRS decay marker (v1.1.7): overdue knowledge should be re-verified
        FSRS_TAG=""
        case "${FSRS:-fresh}" in
            due)      FSRS_TAG=" ⏳ due review" ;;
            overdue)  FSRS_TAG=" ⚠️ overdue — сверь что правило ещё актуально" ;;
            critical) FSRS_TAG=" 🔴 critical overdue — обязательно сверь через /learn" ;;
        esac
        # Изменчивость якорей (v0.3): предупреждение «это условие могло уплыть»
        # обязано быть видно В МОМЕНТ дела. До 2026-08-27 поля писались в файл
        # знания и не читались никем, кроме того, кто откроет файл руками, —
        # то есть существовали для читателя, которого нет. Поля берём из файла
        # по basename, а не тащим через pipe-упаковку RESULTS: ту разбирает ещё
        # и jq, а печатается за раз не больше четырёх записей.
        VOLATILE_TAG=""
        KFILE="$KNOWLEDGE_DIR/$BASENAME"
        if [ -f "$KFILE" ]; then
            VOL=$(grep -m1 '^volatile_anchors:' "$KFILE" 2>/dev/null \
                  | sed 's/#.*$//' \
                  | sed 's/^volatile_anchors:[[:space:]]*//' \
                  | tr -d '[]"' | sed 's/,/ /g; s/[[:space:]]*$//' || true)
            SELF_ALT=$(grep -m1 '^self_altering:' "$KFILE" 2>/dev/null \
                  | sed 's/^self_altering:[[:space:]]*//' \
                  | sed 's/^"//; s/"[[:space:]]*$//' | cut -c1-110 || true)
            [ -n "${VOL:-}" ] && VOLATILE_TAG=" 🌀 может уплыть по ходу: ${VOL} — сверь, что условие ещё то"
            [ -n "${SELF_ALT:-}" ] && VOLATILE_TAG="${VOLATILE_TAG} ♻️ применение само меняет: ${SELF_ALT}"
        fi
        # High-confidence marker for constructive disagreement (v0.4.6)
        if [ "$CONF" -ge 4 ] 2>/dev/null; then
            MESSAGE="${MESSAGE}${INDEX}. ⚡ [${BASENAME%.md}] (confidence:${CONF}, impact:${IMP}): ${NAME} — ВЫСОКАЯ УВЕРЕННОСТЬ, озвучь если противоречит текущему действию${FRAGILE_TAG}${SPEAKER_TAG}${FSRS_TAG}${VOLATILE_TAG}\\n"
            # Pending-запись только для blocker-tier знаний, один раз на знание в сессии.
            # ds_has_blocker_flag — единый парсер флага (тот же, что у blocker-tier-check).
            if ds_has_blocker_flag "$KNOWLEDGE_DIR/$BASENAME" 2>/dev/null && \
               ! throttle_seen "$DIS_LOG" "${BASENAME%.md}"; then
                throttle_mark "$DIS_LOG" "${BASENAME%.md}" \
                    "$(printf '"outcome":"pending","confidence":%s,"tool":"%s"' "$CONF" "${TOOL_NAME:-unknown}")"
            fi
        else
            MESSAGE="${MESSAGE}${INDEX}. [${BASENAME%.md}] (confidence:${CONF}, impact:${IMP}): ${NAME}${FRAGILE_TAG}${SPEAKER_TAG}${FSRS_TAG}${VOLATILE_TAG}\\n"
        fi
        INDEX=$((INDEX + 1))
    done <<< "$SORTED"

    MESSAGE="${MESSAGE}\\nFollow these rules to avoid known mistakes. If a rule seems outdated — note it for update via /learn."
fi

# Cross-domain analogies (v0.4.5)
if [ ${#ANALOGIES[@]} -gt 0 ]; then
    # Sort by score, take top 2 (don't overwhelm with analogies)
    SORTED_ANALOGIES=$(printf '%s\n' "${ANALOGIES[@]}" | sort -t'|' -k1 -nr | head -2)

    # Don't show analogies that are already in main results
    ANALOGY_MSG=""
    ANALOGY_COUNT=0
    while IFS='|' read -r A_SCORE A_BASENAME A_NAME A_DESC A_CONF A_IMP A_REASON A_DOMAIN; do
        # Skip if already in main injection
        if [ -n "$SORTED" ] && grep -q "$A_BASENAME" 2>/dev/null <<< "$SORTED"; then
            continue
        fi
        ANALOGY_COUNT=$((ANALOGY_COUNT + 1))
        ANALOGY_MSG="${ANALOGY_MSG}  - [${A_BASENAME%.md}] из домена ${A_DOMAIN}: ${A_NAME} (совпадение по ${A_REASON})\\n"
    done <<< "$SORTED_ANALOGIES"

    if [ "$ANALOGY_COUNT" -gt 0 ]; then
        MESSAGE="${MESSAGE}\\n\\n📎 Возможные аналогии из других доменов:\\n${ANALOGY_MSG}"
        MESSAGE="${MESSAGE}Оцени применимость аналогии к текущему контексту. Если сработала — запиши через /learn как новый кейс в текущем домене."
    fi
fi

# Cross-contour mentions (v1.3.9 consumer + v1.6 semantic relaxation + session dedup).
# v1.3.9: surface entity↔knowledge pairs when the knowledge file is in SORTED.
# v1.6 (5.2): also surface pairs where (knowledge_file, entity_file) has cosine
#   similarity ≥ CC_SIMILARITY_THRESHOLD from cross-contour-ranked.jsonl
#   (weekly pre-computed by knowledge-audit-digest.sh — R5 latency-safe).
# v1.6 (5.3): session-scope dedup via cross-contour-surfaced-<SID>.txt — same
#   pair does not resurface within one session.
CROSS_CONTOUR_LOG="${HOME}/.claude/hooks/state/cross-contour-discoveries.jsonl"
CROSS_CONTOUR_RANKED="${HOME}/.claude/hooks/state/cross-contour-ranked.jsonl"
CC_THRESHOLD="${CC_SIMILARITY_THRESHOLD:-0.6}"
CC_SID_FOR_SURFACED="${PAYLOAD_SID:-${SR_SESSION_ID:-default}}"
CC_SURFACED_FILE="${CC_SURFACED_FILE_OVERRIDE:-${HOME}/.claude/hooks/state/cross-contour-surfaced-${CC_SID_FOR_SURFACED}.txt}"
if [ -f "$CROSS_CONTOUR_LOG" ] && command -v jq >/dev/null 2>&1; then
    CC_INJECTED_KFS=$(echo "$SORTED" | awk -F'|' 'NF>=2 && $2 != ""{print $2}' | sort -u)
    HIGH_SIM_PAIRS=""
    if [ -f "$CROSS_CONTOUR_RANKED" ]; then
        HIGH_SIM_PAIRS=$(jq -rR --arg t "$CC_THRESHOLD" \
            'fromjson? | select(.similarity != null and (.similarity | tonumber?) >= ($t | tonumber)) | "\(.knowledge_file)|\(.entity_file)"' \
            "$CROSS_CONTOUR_RANKED" 2>/dev/null | sort -u)
    fi
    if [ -n "$CC_INJECTED_KFS" ] || [ -n "$HIGH_SIM_PAIRS" ]; then
        CC_SURFACED_EXISTING=""
        [ -f "$CC_SURFACED_FILE" ] && CC_SURFACED_EXISTING=$(cat "$CC_SURFACED_FILE" 2>/dev/null)
        CC_ALL=$(tail -n 200 "$CROSS_CONTOUR_LOG" 2>/dev/null \
            | jq -rR 'fromjson? | select(.knowledge_file and .entity_file) | "\(.knowledge_file)|\(.entity_file)|\(.matched // "")"' 2>/dev/null \
            | awk -F'|' '!seen[$1"|"$2]++' || true)
        CC_MENTIONS=""
        CC_COUNT=0
        while IFS='|' read -r KF EF MATCHED; do
            [ -z "$KF" ] && continue
            [ "$CC_COUNT" -ge 3 ] && break
            CC_KEY="${KF}|${EF}"
            if [ -n "$CC_SURFACED_EXISTING" ] && grep -Fxq "$CC_KEY" <<< "$CC_SURFACED_EXISTING"; then
                continue
            fi
            CC_KEEP=false
            if [ -n "$CC_INJECTED_KFS" ] && grep -Fxq "$KF" <<< "$CC_INJECTED_KFS"; then
                CC_KEEP=true
            elif [ -n "$HIGH_SIM_PAIRS" ] && grep -Fxq "$CC_KEY" <<< "$HIGH_SIM_PAIRS"; then
                CC_KEEP=true
            fi
            if [ "$CC_KEEP" = "true" ]; then
                LINE=$(printf '  - %s ↔ %s%s' "${KF%.md}" "${EF%.md}" "${MATCHED:+ (упомянуто: ${MATCHED})}")
                CC_MENTIONS="${CC_MENTIONS}${LINE}"$'\n'
                CC_COUNT=$((CC_COUNT + 1))
                mkdir -p "$(dirname "$CC_SURFACED_FILE")" 2>/dev/null || true
                printf '%s\n' "$CC_KEY" >> "$CC_SURFACED_FILE" 2>/dev/null || true
            fi
        done <<< "$CC_ALL"

        if [ -n "$CC_MENTIONS" ]; then
            MESSAGE="${MESSAGE}\\n\\n📎 Кросс-контурные упоминания (паттерн ↔ entity):\\n"
            while IFS= read -r CC_LINE; do
                [ -z "$CC_LINE" ] && continue
                MESSAGE="${MESSAGE}${CC_LINE}\\n"
            done <<< "$CC_MENTIONS"
            MESSAGE="${MESSAGE}Эти связи замечены discovery между контурами. Если видишь инсайт — зафиксируй через /learn как явный edge."
        fi
    fi
fi

# --- Narrative orientation brief (session-start auto-trigger, first fire only) ---
if [ "$FIRST_FIRE" = "true" ]; then
    NARRATIVE_SID="${PAYLOAD_SID:-${SR_SESSION_ID:-$$}}"
    NARRATIVE_PENDING="${HOME}/.claude/hooks/state/narrative-pending-${NARRATIVE_SID}.txt"
    if [ -f "$NARRATIVE_PENDING" ] && [ -s "$NARRATIVE_PENDING" ]; then
        NARRATIVE_BODY=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$NARRATIVE_PENDING" | awk 'BEGIN{ORS="\\n"} {print}')
        MESSAGE="${MESSAGE}\\n\\n${NARRATIVE_BODY}"
        rm -f "$NARRATIVE_PENDING"
    fi
fi

# --- Startup signals (session-start auto-trigger, first fire only) v1.5.1-alpha ---
# Missing CLAUDE.md → /init-project hint; global-lessons обновились → /reload hint
if [ "$FIRST_FIRE" = "true" ]; then
    SIGNALS_SID="${PAYLOAD_SID:-${SR_SESSION_ID:-$$}}"
    # Путь из STATE_DIR, а не жёсткий $HOME: тот же класс, что чинился в D40 —
    # библиотека с жёстким путём писала в живой каталог из любого теста.
    SIGNALS_PENDING="${STATE_DIR}/startup-signals-${SIGNALS_SID}.txt"
    if [ -f "$SIGNALS_PENDING" ] && [ -s "$SIGNALS_PENDING" ]; then
        SIGNALS_BODY=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$SIGNALS_PENDING" | awk 'BEGIN{ORS="\\n"} {print}')
        MESSAGE="${MESSAGE}\\n\\n${SIGNALS_BODY}"
        rm -f "$SIGNALS_PENDING"
    fi
fi

# --- Пункт 0: demand-first reminder (only on first fire) ---
if [ "$FIRST_FIRE" = "true" ]; then
    PUNKT0="⚠️ ПУНКТ 0 — прежде чем действовать:\\n"
    PUNKT0="${PUNKT0}1. Переформулируй задачу своими словами и спроси: правильно ли я понимаю?\\n"
    PUNKT0="${PUNKT0}2. Demand-first: кому это нужно? Какая потребность? Что будет считаться успехом?\\n"
    PUNKT0="${PUNKT0}3. Если получил обратную связь — сначала переформулируй ЧТО СКАЗАЛ собеседник\\n"
    PUNKT0="${PUNKT0}4. Если собеседник дал аналогию или ссылку — проверь прежде чем интерпретировать\\n"
    PUNKT0="${PUNKT0}Не пропускай. Не подменяй задачу своей интерпретацией."
    MESSAGE="${MESSAGE}\\n${PUNKT0}"
else
    # Context shift — lighter reminder
    MESSAGE="${MESSAGE}\\n🔄 Контекст сменился — новые знания активированы."
fi

# Output JSON.
# v1.7.3: переход с `systemMessage` (видимо пользователю в окне терминала)
# на `hookSpecificOutput.additionalContext` (silent — попадает только в
# контекст агента, пользователь не видит). Контент тот же — релевантные
# знания, ПУНКТ 0, аналогии, метрики — но без полстраницы серого текста
# на каждый PreToolUse в окне пользователя.
printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "%s"}}\n' "$MESSAGE"
