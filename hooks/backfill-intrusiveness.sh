#!/usr/bin/env bash
# backfill-intrusiveness.sh — one-off backfill of gentle/proactive events
# from ~/.claude/projects/*/*.jsonl archived transcripts.
#
# NOT a hook. Runs on demand:
#
#   bash hooks/backfill-intrusiveness.sh            # full scan, all archives
#   bash hooks/backfill-intrusiveness.sh --dry-run  # count transcripts, no replay
#   bash hooks/backfill-intrusiveness.sh --limit N  # first N transcripts
#   BACKFILL_PARALLEL=8 bash hooks/backfill-intrusiveness.sh
#
# Outputs events to:
#   ~/.claude/hooks/state/intrusiveness-backfill-history.jsonl
#
# This file is SEPARATE from the live intrusiveness-history.jsonl, so
# backfilled events never pollute live metrics. Consumers can opt in by
# reading both files.
#
# Parallelism: xargs -P controls worker count (default 4).

set -uo pipefail

PROJECTS_DIR="${BACKFILL_PROJECTS_DIR:-$HOME/.claude/projects}"
OUT_FILE="${BACKFILL_OUT:-$HOME/.claude/hooks/state/intrusiveness-backfill-history.jsonl}"
PARALLEL="${BACKFILL_PARALLEL:-4}"
WORKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/backfill-replay-one.sh"

[ -f "$WORKER" ] || { echo "worker not found: $WORKER" >&2; exit 1; }
[ -x "$WORKER" ] || chmod +x "$WORKER"
[ -d "$PROJECTS_DIR" ] || { echo "no $PROJECTS_DIR" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

DRY_RUN=0
LIMIT=0
RUN_DIGEST=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --limit) shift; LIMIT="$1" ;;
        --digest) RUN_DIGEST=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

AGGREGATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/backfill-aggregate-digest.sh"

# Build list of transcripts
TRANSCRIPTS=$(find "$PROJECTS_DIR" -name "*.jsonl" -type f 2>/dev/null | sort)
TOTAL=$(echo "$TRANSCRIPTS" | grep -c '.')

if [ "$LIMIT" -gt 0 ]; then
    TRANSCRIPTS=$(echo "$TRANSCRIPTS" | head -n "$LIMIT")
fi
SELECTED=$(echo "$TRANSCRIPTS" | grep -c '.')

echo "=== Backfill scan"
echo "projects dir: $PROJECTS_DIR"
echo "transcripts found: $TOTAL (selected: $SELECTED)"
echo "parallelism: $PARALLEL"
echo "output: $OUT_FILE"

if [ "$DRY_RUN" = "1" ]; then
    echo "--- dry run, no replay"
    exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
# Back up existing backfill file (don't merge — full replay regenerates)
if [ -f "$OUT_FILE" ]; then
    mv "$OUT_FILE" "${OUT_FILE}.bak.$(date +%s)"
fi
: > "$OUT_FILE"

# mktemp -t: BSD дописывает случайный суффикс к любому префиксу, GNU требует
# в шаблоне минимум три X ("too few X's in template") и падает — TMP_DIR
# оставался пустым. Полный шаблон с X'ами понимают обе реализации.
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/backfill-agg.XXXXXX")
export BACKFILL_TMP="$TMP_DIR"

echo "--- replaying ($SELECTED transcripts, $PARALLEL workers)..."
T0=$(date +%s)

# Parallel replay: xargs -P runs N workers in parallel, each writes events
# (small JSON lines < PIPE_BUF) to stdout; kernel serializes <= PIPE_BUF
# writes across processes, so simple concatenation is atomic per line.
echo "$TRANSCRIPTS" | xargs -n 1 -P "$PARALLEL" "$WORKER" 2>/dev/null \
    | grep -v '^$' > "$OUT_FILE"

rm -rf "$TMP_DIR"

T1=$(date +%s)
ELAPSED=$((T1 - T0))

# Summary
TOTAL_EVENTS=$(wc -l < "$OUT_FILE" | tr -d ' ')
GENTLE=$(grep -c '"type":"gentle"' "$OUT_FILE" 2>/dev/null) || GENTLE=0
PROACTIVE=$(grep -c '"type":"proactive"' "$OUT_FILE" 2>/dev/null) || PROACTIVE=0
ACCEPTED=$(grep -c '"outcome":"accepted"' "$OUT_FILE" 2>/dev/null) || ACCEPTED=0
DECLINED=$(grep -c '"outcome":"declined"' "$OUT_FILE" 2>/dev/null) || DECLINED=0
MOVED_ON=$(grep -c '"outcome":"moved_on"' "$OUT_FILE" 2>/dev/null) || MOVED_ON=0

echo ""
echo "=== Backfill complete ($ELAPSED sec)"
echo "total events:   $TOTAL_EVENTS"
echo "  gentle:       $GENTLE"
echo "  proactive:    $PROACTIVE"
echo "outcomes:"
echo "  accepted:     $ACCEPTED"
echo "  declined:     $DECLINED"
echo "  moved_on:     $MOVED_ON"
if [ "$TOTAL_EVENTS" -gt 0 ]; then
    echo ""
    echo "sample (first event):"
    head -1 "$OUT_FILE"
fi

if [ "$RUN_DIGEST" = "1" ] && [ "$TOTAL_EVENTS" -gt 0 ] && [ -x "$AGGREGATOR" ]; then
    echo ""
    echo "--- aggregating to history-digest format..."
    DIGEST_OUT="${OUT_FILE%-history.jsonl}-digest.jsonl"
    "$AGGREGATOR" "$OUT_FILE" "$DIGEST_OUT" 2>&1 | tail -10
    echo ""
    echo "Run calibrate.py:"
    echo "  python3 scripts/calibrate.py --history $DIGEST_OUT"
fi
