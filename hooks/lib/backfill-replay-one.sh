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
WORK_DIR=$(mktemp -d "${BACKFILL_TMP:-${TMPDIR:-/tmp}}/backfill-worker.XXXXXX") || exit 1
# Песочница снимается на любом выходе: без этого прерванный прогон оставлял каталог навсегда (33 в /tmp за 29–31
# октября 2026, D1154 L3); корень — TMPDIR вызывающего, а не общий /tmp.
trap 'rm -rf "$WORK_DIR"' EXIT
export HOME="$WORK_DIR"
# Каталог состояния песочницы задаётся здесь и читается ниже из той же переменной (D1154). Унаследованный `STATE_DIR`
# сохранял `paths-lib.sh`, `ITR_STATE_DIR` библиотека состояния ставит первым: детектор писал туда, воркер читал
# `$HOME/…` — файла нет, событий 0, молча.
export STATE_DIR="$HOME/.claude/hooks/state"
unset ITR_STATE_DIR
mkdir -p "$STATE_DIR"

# Откуда берём хук-файлы: каталог рядом с этим скриптом (hooks/ репозитория
# либо установленный ~/.claude/hooks — install.sh кладёт lib/ туда же).
# Раньше источником был строго $HOME/.claude/hooks. На машине разработчика
# установка есть, поэтому всё работало; на чистой Linux-машине (контейнер, CI)
# каталога ~/.claude/hooks нет вовсе — копировать было нечего, детектор
# не запускался, и реплей молча выдавал ноль событий.
HOOKS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOOKS_SRC/itr-event-detector.sh" ] || HOOKS_SRC="$REAL_HOME/.claude/hooks"

# Каталог хуков копируется ЦЕЛИКОМ, а не перечнем (D1205, круг скептика, H1). Перечень был вторым владельцем факта
# «что подключает детектор» и отстал от библиотек: `lib/unread-lib.sh`, которую `authorization-lib.sh` подключает с
# 4 сентября 2026, в него не попала — `unread_or` не находился, правило «содержательная реплика авторизует» отвечало
# «не измерено», и реплей молча записывал в самовольные 54% событий. Цена копии — 0,2 с на расшифровку.
cp "$HOOKS_SRC"/*.sh "$HOME/.claude/hooks/" 2>/dev/null
[ -d "$HOOKS_SRC/lib" ] && cp -R "$HOOKS_SRC/lib" "$HOME/.claude/hooks/" 2>/dev/null

SID_BASE="backfill-$(basename "$TRANSCRIPT" .jsonl)"
INDEX="$WORK_DIR/index.ndjson"
SLICE="$WORK_DIR/slice.jsonl"

# Index: for each user/assistant record emit {idx, role, text, ts}.
# Note: historical timestamp is on the user record itself.
# Реплика, набранная посреди хода (вложение `queued_command`), — тоже точка реплея (D1144): живой детектор на ней
# срабатывает (хук подачи реплики) — с сентября 2026; на архивах июля–августа хук подачи на вложении не срабатывал
# (по корпусу 0 из 192), и события там — реконструкция ответа владельца, а не хронология хука. Вживую вложение уже записано в расшифровку, в срезе его нет; детектор судит
# по последней реплике ДО последнего ответа агента, и оба среза дают ему одну границу. Приводилка —
# `HIL_AS_REPLY_JQ` из hook-input-lib; без библиотеки (либо её старой редакции без `HIL_OWNER_REPLY_JQ`) реплей не идёт — ниже.
[ -f "$HOOKS_SRC/hook-input-lib.sh" ] && . "$HOOKS_SRC/hook-input-lib.sh"
# Точку реплея судит правило владельца (D1150). Библиотеки нет — реплей не идёт и говорит об этом: молчаливый ноль
# событий неотличим от «событий не было» (тот же отказ, что описан в шапке выше).
[ -n "${HIL_OWNER_REPLY_JQ:-}" ] || { echo "backfill-replay-one: нет правила владельца реплики (HIL_OWNER_REPLY_JQ): hook-input-lib.sh нет либо старая редакция — точки реплея судить нечем" >&2; rm -rf "$WORK_DIR"; exit 2; }
jq -sc "${HIL_AS_REPLY_JQ:-def as_reply: .;}${HIL_OWNER_REPLY_JQ:-def owner_reply: false;}"'
  map(as_reply) | to_entries[]
  # Точкой реплея служит РЕПЛИКА владельца, правилом владельца `owner_reply` (D1150): вставка харнесса, уведомление
  # задачи, сводка сжатия или ветка субагента дали бы ложную точку и событие, которого не было (8 сентября 2026).
  | select((.value | owner_reply) or .value.type == "assistant")
  | .key as $k
  | (.value.message.content // .value.content // []) as $c
  | (.value.timestamp // "") as $ts
  | ( if ($c | type) == "array"
      then ($c | map(select(.type == "text") | .text) | join("\n"))
      elif ($c | type) == "string" then $c
      else "" end
    ) as $text
  # Слеш-команда записана в расшифровку эхом `<command-name>/x</command-name>`, а живой хук подачи получает набранное
  # `/x args` и пишет по нему состояние; эхо режет фильтр служебных ходов, и поручение реплики ДО команды переходило
  # через неё (D1205, круг скептика, L1). Подача восстанавливается только для имени со слешем: эхо без слеша — скилл,
  # вызванный агентом (`<skill-format>`), на нём хук подачи не срабатывает.
  | ( if ($text | test("<command-name>/")) then
        ($text | capture("<command-name>(?<n>/[^<]*)</command-name>").n) as $n
        | (($text | capture("<command-args>(?<a>[\\s\\S]*?)</command-args>").a) // "") as $a
        | $n + (if $a == "" then "" else " " + $a end)
      else $text end
    ) as $text
  # Точку реплея отбирает вердикт владельца `own`, а не роль записи: роль, судимая оболочкой второй раз, — своя копия
  # признака (D1156).
  | {idx: $k, own: (.value | owner_reply), text: $text, ts: $ts}
' "$TRANSCRIPT" > "$INDEX" 2>/dev/null

[ -s "$INDEX" ] || { rm -rf "$WORK_DIR"; exit 0; }

# For each user record: slice transcript to records BEFORE it, feed detector.
while IFS= read -r rec; do
    OWN=$(echo "$rec" | jq -r '.own' 2>/dev/null) || continue
    [ "$OWN" = true ] || continue
    UIDX=$(echo "$rec" | jq -r '.idx')
    UTEXT=$(echo "$rec" | jq -r '.text')
    UTS=$(echo "$rec" | jq -r '.ts')
    [ -z "$UTEXT" ] || [ "$UTEXT" = "null" ] && continue
    [ "$UIDX" -le 1 ] && continue

    head -n "$UIDX" "$TRANSCRIPT" > "$SLICE" 2>/dev/null || continue
    grep -q '"type":"assistant"' "$SLICE" 2>/dev/null || continue

    # Один SID на всю расшифровку, как вживую одна сессия (D1205): состояние, ключённое сессией, — поручение
    # `authorization-<sid>.json`, дедуп хода `itr_event_last_fire_<sid>` — переходит из хода в ход. SID на каждый ход
    # начинал сессию заново, и плечо A замера ab-authorization-replay совпадало с плечом B по построению.
    SID="$SID_BASE"
    PAYLOAD=$(jq -cn --arg sid "$SID" --arg tp "$SLICE" --arg up "$UTEXT" \
        '{session_id: $sid, transcript_path: $tp, prompt: $up}')
    # Pass UTS through env so we could later inject it; for now detector uses
    # date -u. We override after: read back state file and replace ts.
    printf '%s' "$PAYLOAD" | bash "$HOME/.claude/hooks/itr-event-detector.sh" >/dev/null 2>&1 || true

    # If detector recorded event(s) in this SID's state file, emit with real ts
    SF="$STATE_DIR/intrusiveness-${SID}.json"
    if [ -f "$SF" ]; then
        # Перезаписываются РОВНО три поля, объявленные в шапке. Четвёртое, `backfill_sid`,
        # писалось с 25 апреля 2026 и не читалось ни разу: ни структурно, ни текстом, ни
        # именем-аргументом — проверено по всему дереву, по истории (`git log -S`) и по
        # цепочке потребителей (`backfill-aggregate-digest.sh:70-99` собирает НОВЫЙ объект,
        # поле в дайджест не проходит). Цена измерена: 38 181 байт из 162 649 в живом
        # журнале — 23,5% файла при 575 записях из 575. Убрано (род G).
        jq -c --arg ts "$UTS" --arg sid "$SID_BASE" \
            '(.events // [])[] | . + {ts: $ts, source: "backfill", aggregate_sid: $sid}' \
            "$SF" 2>/dev/null
        rm -f "$SF"
    fi
done < "$INDEX"

rm -rf "$WORK_DIR"
