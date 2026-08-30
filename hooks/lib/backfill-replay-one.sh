#!/usr/bin/env bash
# backfill-replay-one.sh — replay itr-event-detector on ONE archived transcript.
#
# Worker script for the one-off backfill tool. Reads an archived transcript,
# walks each user turn, constructs a synthetic hook payload with a transcript
# slice (everything BEFORE the current user message), and feeds it to the
# live itr-event-detector.sh. Captured events are re-emitted as NDJSON to
# stdout with:
#   - historical `ts` extracted from the transcript record (NOT date -u)
#   - `source: "backfill"` marker so consumers can filter/separate
#   - synthetic `sid` derived from transcript filename
#
# Isolation: creates a private STATE_DIR under $BACKFILL_TMP, never touches
# live state. The detector is run with HOME overridden to the synthetic tree.
#
# Usage: backfill-replay-one.sh <transcript.jsonl>
# Stdout: NDJSON events (one per line). Empty if no events captured.

set -uo pipefail

TRANSCRIPT="${1:?usage: $0 <transcript.jsonl>}"
[ -f "$TRANSCRIPT" ] || exit 1

REAL_HOME="$HOME"
WORK_DIR=$(mktemp -d "${BACKFILL_TMP:-/tmp}/backfill-worker.XXXXXX") || exit 1
export HOME="$WORK_DIR"
mkdir -p "$HOME/.claude/hooks/state"

# Откуда берём хук-файлы: каталог рядом с этим скриптом (hooks/ репозитория
# либо установленный ~/.claude/hooks — install.sh кладёт lib/ туда же).
# Раньше источником был строго $HOME/.claude/hooks. На машине разработчика
# установка есть, поэтому всё работало; на чистой Linux-машине (контейнер, CI)
# каталога ~/.claude/hooks нет вовсе — копировать было нечего, детектор
# не запускался, и реплей молча выдавал ноль событий.
HOOKS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOOKS_SRC/itr-event-detector.sh" ] || HOOKS_SRC="$REAL_HOME/.claude/hooks"

# Install minimum hook set required by itr-event-detector
for f in itr-event-detector.sh authorization-lib.sh portable-lib.sh hook-input-lib.sh intrusiveness-state-lib.sh intrusiveness-cost-lib.sh intrusiveness-classify-lib.sh intrusiveness-format-lib.sh intrusiveness-metrics-lib.sh detection-signals-lib.sh session-registry-lib.sh fsrs-lib.sh adaptive-stats-lib.sh hash-lib.sh paths-lib.sh; do
    [ -f "$HOOKS_SRC/$f" ] && cp "$HOOKS_SRC/$f" "$HOME/.claude/hooks/"
done

SID_BASE="backfill-$(basename "$TRANSCRIPT" .jsonl)"
INDEX="$WORK_DIR/index.ndjson"
SLICE="$WORK_DIR/slice.jsonl"

# Index: for each user/assistant record emit {idx, role, text, ts}.
# Note: historical timestamp is on the user record itself.
jq -sc '
  to_entries[]
  | select(.value.type == "user" or .value.type == "assistant")
  | .key as $k
  | (.value.message.role // .value.role // "") as $r
  | (.value.message.content // .value.content // []) as $c
  | (.value.timestamp // "") as $ts
  | ( if ($c | type) == "array"
      then ($c | map(select(.type == "text") | .text) | join("\n"))
      elif ($c | type) == "string" then $c
      else "" end
    ) as $text
  | {idx: $k, role: $r, text: $text, ts: $ts}
' "$TRANSCRIPT" > "$INDEX" 2>/dev/null

[ -s "$INDEX" ] || { rm -rf "$WORK_DIR"; exit 0; }

# For each user record: slice transcript to records BEFORE it, feed detector.
while IFS= read -r rec; do
    ROLE=$(echo "$rec" | jq -r '.role' 2>/dev/null) || continue
    [ "$ROLE" = "user" ] || continue
    UIDX=$(echo "$rec" | jq -r '.idx')
    UTEXT=$(echo "$rec" | jq -r '.text')
    UTS=$(echo "$rec" | jq -r '.ts')
    [ -z "$UTEXT" ] || [ "$UTEXT" = "null" ] && continue
    [ "$UIDX" -le 1 ] && continue

    head -n "$UIDX" "$TRANSCRIPT" > "$SLICE" 2>/dev/null || continue
    grep -q '"type":"assistant"' "$SLICE" 2>/dev/null || continue

    SID="${SID_BASE}-${UIDX}"
    PAYLOAD=$(jq -cn --arg sid "$SID" --arg tp "$SLICE" --arg up "$UTEXT" \
        '{session_id: $sid, transcript_path: $tp, prompt: $up}')
    # Pass UTS through env so we could later inject it; for now detector uses
    # date -u. We override after: read back state file and replace ts.
    printf '%s' "$PAYLOAD" | bash "$HOME/.claude/hooks/itr-event-detector.sh" >/dev/null 2>&1 || true

    # If detector recorded event(s) in this SID's state file, emit with real ts
    SF="$HOME/.claude/hooks/state/intrusiveness-${SID}.json"
    if [ -f "$SF" ]; then
        jq -c --arg ts "$UTS" --arg sid "$SID_BASE" --arg src_sid "$SID" \
            '(.events // [])[] | . + {ts: $ts, source: "backfill", backfill_sid: $src_sid, aggregate_sid: $sid}' \
            "$SF" 2>/dev/null
        rm -f "$SF"
    fi
done < "$INDEX"

rm -rf "$WORK_DIR"
