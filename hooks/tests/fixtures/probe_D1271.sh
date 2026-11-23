#!/usr/bin/env bash
set -u
. "$(dirname "$0")/../alerts-read.sh"
# СУДИТ: hooks/session-collector.sh hooks/lib/archive_relay.py scripts/backlog-archive.sh
# probe_D1271 — отказ архиватора, держащий закрытый пункт запуск за запуском, доходит до напоминаний владельца строкой
#   «СКАЖИ» с номером и причиной и гаснет, когда итог хода его назвал. Рамка сквозная (скептик opus по b8f9cb64, M2:
#   прежняя проба видела сборщик только поиском текста): НАСТОЯЩИЙ сборщик границы хода с песочными HOME и каталогом
#   состояния, песочный бэклог с ☑ под меткой «судит по форме» (настоящий архиватор отказывает), журнал отказов
#   трёхдневной давности. Срок считается запусками, а не часами (D1352), и подаётся сборщику окружением
#   (`ARCHIVE_RELAY_RUNS=2`): граница 1, итог без номера — «СКАЖИ» ещё НЕТ, хотя отказу по журналу три дня; граница 2,
#   итог без номера — в очереди «СКАЖИ владельцу» с номером и причиной; граница 3, итог «Архиватор держит B491» —
#   строки нет. 0 — так; 1 — нет; 2 — рамка не собралась.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
R="$PWD"; C=hooks/session-collector.sh; A=scripts/backlog-archive.sh
for f in "$C" "$A"; do [ -f "$f" ] || exit 2; done
command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/state" "$W/home/.claude/hooks" "$W/proj"
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX
printf '# Бэклог\n\n- ☑ **B491** закрыт по форме\n  **Результат.** проба\n  **Проверка.** `true` → 0\n  Метка: судит по форме\n\n' > "$W/proj/BACKLOG.md"
: > "$W/proj/BACKLOG-archive.md"
old=$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(days=3)).isoformat())')
printf '{"ts":"%s","item":"B491","why":"x","mode":"run"}\n' "$old" > "$W/state/backlog-archive-fired-2026-01-01.jsonl"
stop() {  # <итог хода> → очередь напоминаний этой границы
    alerts_clear "$W/state"
    jq -cn --arg c "$W/proj" --arg m "$1" '{session_id:"p1271", cwd:$c, last_assistant_message:$m}' \
        | HOME="$W/home" STATE_DIR="$W/state" CLAUDSOUL_ROOT="$R" CLAUDSOUL_BACKLOG="$W/proj/BACKLOG.md" \
          CLAUDSOUL_BACKLOG_ARCHIVER="$R/$A" CLAUDSOUL_MEASURE_DUE="$W/none.sh" ARCHIVE_RELAY_RUNS=2 bash "$R/$C" >/dev/null 2>&1 \
        || { echo "рамка: сборщик вышел с ошибкой"; exit 2; }
    alerts_of "$W/state"
}
bad=0
q=$(stop "итог без номера") || exit 2
grep -q 'СКАЖИ владельцу' <<< "$q" && { echo "граница 1: один запуск, а «СКАЖИ» уже в очереди — срок считается не запусками"; bad=1; }
q=$(stop "итог без номера") || exit 2
grep -q 'СКАЖИ владельцу.*B491.*судит по форме' <<< "$q" || { echo "граница 2: «СКАЖИ» с номером и причиной не встала в очередь"; bad=1; }
q=$(stop "Архиватор держит B491: метка «судит по форме».") || exit 2
grep -q 'СКАЖИ владельцу' <<< "$q" && { echo "граница 3: итог назвал номер, а «СКАЖИ» осталась"; bad=1; }
exit "$bad"
