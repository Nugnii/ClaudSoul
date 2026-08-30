#!/usr/bin/env bash
# freeze-policy.sh — старт экспериментальной фазы (протокол §6): experimental-тег
# + отдельная read-only установка frozen runtime.
#
# Запуск этого скрипта = осознанное решение владельца начать фазу. После него
# действуют правила §6: разрабатывать можно, активировать — только между фазами.
#
#   freeze-policy.sh <phase> [claudsoul_repo]
#     - annotated tag ablation-<phase> на чистом HEAD репозитория ClaudSoul
#       (грязное дерево = отказ: policy заморожена быть не может);
#     - read-only копия исполняемой policy (CLAUDSOUL_RUNTIME, default ~/.claude:
#       hooks + CLAUDE.md + settings.json) в ABLATION_DIR/frozen-runtime-<phase>/,
#       chmod a-w рекурсивно + sha256-манифест;
#     - событие phase_frozen в журнал.
#
# Для задач по разработке самого ClaudSoul Full shadow управляется ЭТОЙ
# read-only установкой, а mutable-репозиторий остаётся объектом задачи (§6):
# код, написанный агентом в рабочей копии, не становится хуком посреди прогона.
set -euo pipefail

PHASE="${1:?имя фазы (например, phase-1)}"
REPO="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
RUNTIME="${CLAUDSOUL_RUNTIME:-$HOME/.claude}"
FROZEN="$DIR/frozen-runtime-$PHASE"
TAG="ablation-$PHASE"

[ -f "$DIR/active-phase.json" ] && {
    echo "freeze: уже идёт фаза '$(jq -r '.phase' "$DIR/active-phase.json")' — сначала phase.sh close" >&2; exit 1; }
[ -e "$FROZEN" ] && { echo "freeze: фаза $PHASE уже заморожена" >&2; exit 1; }
git -C "$REPO" rev-parse -q --verify "refs/tags/$TAG" >/dev/null && {
    echo "freeze: тег $TAG уже существует" >&2; exit 1; }
[ -z "$(git -C "$REPO" status --porcelain)" ] || {
    echo "freeze: рабочее дерево $REPO грязное — замораживать нечего, сначала коммит" >&2; exit 1; }

git -C "$REPO" tag -a "$TAG" -m "Ablation policy freeze: $PHASE"

mkdir -p "$FROZEN"
cp -R "$RUNTIME/hooks" "$FROZEN/hooks"
cp "$RUNTIME/CLAUDE.md" "$FROZEN/CLAUDE.md"
cp "$RUNTIME/settings.json" "$FROZEN/settings.json"
( cd "$FROZEN" && find . -type f -exec shasum -a 256 {} \; | sort -k2 ) > "$FROZEN.manifest"
chmod -R a-w "$FROZEN"

jq -cn --arg p "$PHASE" --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      --arg tag "$TAG" --arg head "$(git -C "$REPO" rev-parse HEAD)" \
      --arg m "$(shasum -a 256 "$FROZEN.manifest" | awk '{print $1}')" \
      '{e:"phase_frozen", phase:$p, ts:$ts, tag:$tag, head:$head, manifest_sha256:$m}' \
      >> "$DIR/journal.jsonl"

# Маркер активной фазы — источник истины для стража и сигнала сессий:
# никто (ни владелец, ни агент) не обязан помнить, идёт ли фаза.
jq -cn --arg p "$PHASE" --arg tag "$TAG" --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{phase:$p, tag:$tag, since:$ts}' > "$DIR/active-phase.json"

echo "freeze: фаза $PHASE — тег $TAG, read-only runtime: $FROZEN"
echo "Правила §6 действуют: подключение хуков/скиллов, activation/retrieval, пороги,"
echo "инъекции, MCP — только после конца фазы. База знаний живёт (часть treatment)."
