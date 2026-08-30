#!/usr/bin/env bash
# shadow-run.sh — одно плечо теневой тройки (протокол §2, §6, §9; D64).
#
# Собирает изолированную песочницу из ЗАМОРОЖЕННОГО task package: свой HOME,
# свой worktree. Full получает runtime+знания из снимка, Core — те же знания и
# только наивный инжектор обвязки (§12), Vanilla — голый HOME.
# Перед стартом — env-diff против манифеста (§6): расхождение =
# infrastructure_failure до старта. Бюджеты §11: таймаут 90 минут; потолок
# 500k токенов считается парсером транскрипта пост-фактум
# (ponytail: enforcement потолка на лету — при первой живой паре, если
# понадобится; таймаут режет большинство перерасходов).
#
# Использование: shadow-run.sh <task_id> full|core|vanilla [--smoke]
#   --smoke: построить песочницу, прогнать env-diff, напечатать команду агента
#            и выйти БЕЗ запуска (нулевая цена; для отладки обвязки).
set -euo pipefail

TASK_ID="${1:?task_id обязателен}"
ARM="${2:?плечо: full|core|vanilla}"
case "$ARM" in full|core|vanilla) ;; *)
    echo "shadow-run: плечо — full|core|vanilla (получено '$ARM')" >&2; exit 1 ;; esac
SMOKE="${3:-}"
DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
PKG="$DIR/packages/$TASK_ID"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$PKG/manifest.json" ] || { echo "shadow-run: пакета $TASK_ID нет — сначала snapshot.sh" >&2; exit 1; }

RUN="$DIR/runs/$TASK_ID/$ARM"
[ -e "$RUN" ] && { echo "shadow-run: прогон $TASK_ID/$ARM уже существует (повтор пары — только целиком, §9)" >&2; exit 1; }
mkdir -p "$RUN/home" "$RUN/work"

tar -xf "$PKG/repo.tar" -C "$RUN/work"
case "$ARM" in
full)
    mkdir -p "$RUN/home/.claude"
    tar -xf "$PKG/runtime.tar" -C "$RUN/home/.claude"
    tar -xf "$PKG/knowledge.tar" -C "$RUN/home/.claude"
    ;;
core)
    # Та же база знаний, что у Full, и НИЧЕГО из policy: ни хуков, ни правил,
    # ни скиллов, ни MCP. Только инжектор top-k по лексической близости.
    mkdir -p "$RUN/home/.claude"
    tar -xf "$PKG/core-runtime.tar" -C "$RUN/home/.claude"
    tar -xf "$PKG/knowledge.tar" -C "$RUN/home/.claude"
    ;;
vanilla)
    : # голый HOME по построению — ни одного компонента ClaudSoul
    ;;
esac

bash "$HERE/env-diff.sh" "$ARM" "$RUN/home" || {
    jq -cn --arg id "$TASK_ID" --arg a "$ARM" --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{e:"arm_result", id:$id, arm:$a, ts:$ts, outcome:"infrastructure_failure", stage:"env-diff"}' \
        >> "$DIR/journal.jsonl"
    exit 1
}

TEXT=$(jq -rs --arg id "$TASK_ID" '[.[] | select(.e=="register" and .id==$id)][0].text // empty' "$DIR/journal.jsonl")
[ -n "$TEXT" ] || { echo "shadow-run: задача не найдена в журнале" >&2; exit 1; }
printf '%s\n' "$TEXT" > "$RUN/prompt.txt"

# Собеседника в тени нет: запрос уточнения = blocked (§9) — поэтому один
# неинтерактивный прогон с полным выводом в файл.
AGENT_CMD=(env HOME="$RUN/home" claude -p "$(cat "$RUN/prompt.txt")" --output-format json --dangerously-skip-permissions)

if [ "$SMOKE" = "--smoke" ]; then
    echo "smoke: песочница собрана, env-diff чист; команда плеча:"
    printf '  %q ' "${AGENT_CMD[@]}"; echo
    exit 0
fi

START=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Таймаут 90 минут без gtimeout (macOS): фоновый прогон + сторож.
( cd "$RUN/work" && "${AGENT_CMD[@]}" > "$RUN/result.json" 2> "$RUN/stderr.log" ) &
PID=$!
( sleep 5400 && kill -9 "$PID" 2>/dev/null ) &
WATCHDOG=$!
if wait "$PID"; then OUTCOME="finished"; else OUTCOME="timeout_or_error"; fi
kill "$WATCHDOG" 2>/dev/null || true

jq -cn --arg id "$TASK_ID" --arg a "$ARM" --arg ts "$START" --arg end "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      --arg o "$OUTCOME" \
      '{e:"arm_run", id:$id, arm:$a, started:$ts, ended:$end, raw_outcome:$o}' >> "$DIR/journal.jsonl"
echo "shadow-run: $TASK_ID/$ARM — $OUTCOME; результат в $RUN/ (исход классифицирует чекер, не раннер)"
