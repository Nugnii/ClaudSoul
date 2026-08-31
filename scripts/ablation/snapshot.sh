#!/usr/bin/env bash
# snapshot.sh — предзадачный снимок task package (протокол §6, D64).
#
# Замораживает на тройку плеч: репозиторий задачи (HEAD), базу знаний (живую —
# она часть treatment), исполняемый runtime ClaudSoul (установленную policy) и
# runtime контрольного плеча Core (инжектор обвязки, §2/§12).
# Hash каждого архива — в manifest.json пары; печатает snapshot_ts, который
# идёт сэмплеру (--snapshot-ts): beacon обязан быть позже этой метки.
#
# Использование: snapshot.sh <task_id> <repo_path>
#   CLAUDSOUL_RUNTIME (default ~/.claude) — установленная policy;
#   LESSONS_DIR (default ~/.claude/global-lessons) — база знаний.
set -euo pipefail

TASK_ID="${1:?task_id обязателен}"
REPO="${2:?путь к репозиторию задачи обязателен}"
[ -d "$REPO/.git" ] || { echo "snapshot: $REPO — не git-репозиторий" >&2; exit 1; }

DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
PKG="$DIR/packages/$TASK_ID"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -e "$PKG" ] && { echo "snapshot: пакет $TASK_ID уже существует — снимок неизменяем" >&2; exit 1; }
mkdir -p "$PKG"

RUNTIME="${CLAUDSOUL_RUNTIME:-$HOME/.claude}"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"

HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
DIRTY=$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')

git -C "$REPO" archive HEAD -o "$PKG/repo.tar"
# Имя каталога знаний в архиве нормализуется к global-lessons независимо от
# источника (staging вместо tar --transform/-s: BSD и GNU расходятся).
STAGE=$(mktemp -d)
cp -R "$LESSONS" "$STAGE/global-lessons"
tar -cf "$PKG/knowledge.tar" -C "$STAGE" global-lessons
rm -rf "$STAGE"
# Runtime = исполняемая policy: хуки + глобальные правила + settings.
tar -cf "$PKG/runtime.tar" -C "$RUNTIME" hooks CLAUDE.md settings.json 2>/dev/null
# Runtime плеча Core: только инжектор и регистрирующий его settings.json (§12).
# Раскладка архива зеркалит целевой HOME (.claude/core/inject.py + .claude/settings.json),
# чтобы shadow-run распаковывал одной командой и ничего не переносил руками.
CORE_STAGE=$(mktemp -d)
mkdir -p "$CORE_STAGE/core"
cp "$HERE/core/inject.py" "$CORE_STAGE/core/inject.py"
cp "$HERE/core/settings.json" "$CORE_STAGE/settings.json"
tar -cf "$PKG/core-runtime.tar" -C "$CORE_STAGE" core settings.json
rm -rf "$CORE_STAGE"

sha() { shasum -a 256 "$1" | awk '{print $1}'; }
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
jq -n --arg id "$TASK_ID" --arg ts "$TS" --arg head "$HEAD_SHA" --arg dirty "$DIRTY" \
      --arg r "$(sha "$PKG/repo.tar")" --arg k "$(sha "$PKG/knowledge.tar")" \
      --arg u "$(sha "$PKG/runtime.tar")" --arg c "$(sha "$PKG/core-runtime.tar")" \
      '{task_id:$id, snapshot_ts:$ts, repo_head:$head, repo_dirty_files:($dirty|tonumber),
        sha256:{repo:$r, knowledge:$k, runtime:$u, core_runtime:$c}}' > "$PKG/manifest.json"

[ "$DIRTY" != "0" ] && echo "snapshot: ВНИМАНИЕ — рабочее дерево $REPO грязное ($DIRTY файлов), снимок сделан с HEAD" >&2
printf '%s\n' "$TS"
