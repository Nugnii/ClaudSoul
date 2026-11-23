#!/usr/bin/env bash
# backfill-intrusiveness.sh — разовый добор событий gentle/proactive из архивных расшифровок ~/.claude/projects/*/*.jsonl. Не хук: запускается по требованию.
# en: One-off backfill of gentle/proactive events from archived transcripts; not a hook, runs on demand.
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
# Коды: 0 — реплей прошёл либо список пуст и реплея нет («nothing to replay»); 1 — нет воркера, каталога расшифровок или jq (проверяются
# до разбора аргументов) либо `--limit` без значения; 2 — неизвестный аргумент либо отказ воркера («реплей неисправен»,
# сводки и дайджеста нет).

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
BAK=""   # унаследованная из окружения назвала бы в строке отказа несуществующий прежний итог (скептик D1155, L5)
if [ -f "$OUT_FILE" ]; then
    BAK="${OUT_FILE}.bak.$(date +%s)"
    mv "$OUT_FILE" "$BAK"
fi
: > "$OUT_FILE"
# Пустой список — реплея нет, и решает это явное условие, а не `xargs` машины: BSD на пустом входе воркер не зовёт, GNU
# без `-r` зовёт его без аргумента (код 123 и ложное «реплей неисправен», скептик D1150, четвёртый круг, H1). Ключ `-r`
# судился только на GNU, где пробу не исполняет никто (D1162); условие судит `test_backfill.sh` (T7) и на macOS.
[ "$SELECTED" -gt 0 ] || { echo "--- no transcripts selected, nothing to replay"; exit 0; }

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
# Отказ воркера — сбой реплея, а не «событий нет»: код воркера идёт в итог, его stderr не глушится (D1150, скептик
# третьего круга, H2: прежде `2>/dev/null` и код в трубе давали «total events: 0» молча). Строку причины воркер пишет
# сам, где она у него есть (нет библиотеки ввода либо её старая редакция); прочие его отказы (нет файла, нет песочницы)
# — только кодом.
# Граница записи — NUL, а не пробел (D1208, корень R6): без `-0` `xargs` делил путь с пробелом на обрывки и разбирал
# кавычки (апостроф — «unterminated quote»). Список подаётся here-string'ом в `tr`, чтобы `xargs` остался вторым звеном
# трубы: его код читается ниже как `_bf_rc[1]`.
tr '\n' '\0' <<< "$TRANSCRIPTS" | xargs -0 -n 1 -P "$PARALLEL" "$WORKER" \
    | grep -v '^$' > "$OUT_FILE"
_bf_rc=("${PIPESTATUS[@]}")
if [ "${_bf_rc[1]:-0}" -ne 0 ]; then
    rm -rf "$TMP_DIR"
    echo "backfill-intrusiveness: воркер отказал (код xargs ${_bf_rc[1]}) — реплей неисправен: сводки нет, $OUT_FILE неполон${BAK:+, прежний итог — $BAK}" >&2
    exit 2
fi

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
