#!/usr/bin/env bash
# dry-run-activator.sh — предзадачный признак would_surface_pre_action (§7).
#
# На ЗАМОРОЖЕННОМ task package, до назначения плеч и без запуска агента:
# детерминированный прогон knowledge-activator из runtime-снимка над текстом
# задачи. Результат и идентификаторы поднятых знаний — событие dry_run в
# журнале; Full-плечо получает ровно эту инъекцию, Vanilla — нет.
#
# Использование: dry-run-activator.sh <task_id>
#   (пакет обязан существовать: packages/<task_id>/{runtime,knowledge}.tar)
set -euo pipefail

TASK_ID="${1:?task_id обязателен}"
DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
PKG="$DIR/packages/$TASK_ID"
J="$DIR/journal.jsonl"
[ -f "$PKG/manifest.json" ] || { echo "dry-run: пакета $TASK_ID нет — сначала snapshot.sh" >&2; exit 1; }

TEXT=$(jq -rs --arg id "$TASK_ID" '[.[] | select(.e=="register" and .id==$id)][0].text // empty' "$J")
[ -n "$TEXT" ] || { echo "dry-run: задача $TASK_ID не найдена в журнале" >&2; exit 1; }
if jq -es --arg id "$TASK_ID" '[.[] | select(.e=="dry_run" and .id==$id)] | length > 0' "$J" >/dev/null 2>&1; then
    echo "dry-run: признак $TASK_ID уже зафиксирован — предзадачный признак один (§7)" >&2; exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home/.claude" "$WORK/state" "$WORK/repo"
tar -xf "$PKG/runtime.tar" -C "$WORK/home/.claude"
tar -xf "$PKG/knowledge.tar" -C "$WORK/home/.claude"
tar -xf "$PKG/repo.tar" -C "$WORK/repo"

ACTIVATOR="$WORK/home/.claude/hooks/knowledge-activator.sh"
[ -f "$ACTIVATOR" ] || { echo "dry-run: в runtime-снимке нет knowledge-activator" >&2; exit 1; }

# Вход как у первого PreToolUse новой сессии; всё состояние — во временном HOME.
OUT=$(jq -cn --arg p "$TEXT" --arg cwd "$WORK/repo" \
        '{session_id:"dryrun", tool_name:"Bash", tool_input:{command:"true"}, cwd:$cwd, user_prompt:$p}' \
      | HOME="$WORK/home" STATE_DIR="$WORK/state" LESSONS_DIR="$WORK/home/.claude/global-lessons" \
        bash "$ACTIVATOR" 2>/dev/null || true)

CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)
if [ -n "$CTX" ] && printf '%s' "$CTX" | grep -q "📚"; then
    WOULD=true
    IDS=$(printf '%s' "$CTX" | grep -oE '\[(pattern|principle|case)-[a-z0-9-]+\]' | tr -d '[]' | sort -u | jq -R . | jq -cs .)
else
    WOULD=false
    IDS="[]"
fi

jq -cn --arg id "$TASK_ID" --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      --argjson w "$WOULD" --argjson k "$IDS" \
      '{e:"dry_run", id:$id, ts:$ts, would_surface:$w, knowledge:$k}' >> "$J"
jq -cn --argjson w "$WOULD" --argjson k "$IDS" '{would_surface:$w, knowledge:$k}'
