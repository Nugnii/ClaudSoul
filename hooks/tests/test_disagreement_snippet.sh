#!/usr/bin/env bash
# СУДИТ: hooks/disagreement-lib.sh hooks/portable-lib.sh hooks/session-collector.sh
# test_disagreement_snippet.sh — улика доходит до судьи вердикта.
#
# ПОВОД (диагностика 2026-08-31): за всю историю 304 кандидата от жнеца поправок →
# 0 опровержений. Механика: user-correction-guard УЖЕ пишет snippet поправки (160
# символов реплики) в correction-fired-<SID>.jsonl, а dis_harvest_corrections брал
# из файла только .date — судья на Stop видел «ключ+дата+инструмент» и предсказуемо
# писал «не к месту». Вердикт выносился вслепую.
#
# Контракт после починки:
#   T1 — жнец замораживает snippet сработавшей поправки в pending-записи кандидата;
#   T2 — session-collector печатает цитату в карточке вердикта (канал pending-alerts);
#   T3 — строка «ошиблось» несёт цену вердикта (/retro + кейс): доктрина learn 4a /
#        META §contradiction видна судье в момент суждения, а не только в скилле.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/disagreement-lib.sh"
COLLECTOR="$HOOKS_DIR/session-collector.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
[ -f "$COLLECTOR" ] || { echo "FAIL: нет $COLLECTOR"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"

SNIP="так нужен признак и замер, а не пересказ"

# --- T1: жнец кладёт snippet поправки в pending-запись ---
cat > "$STATE/injection-log.jsonl" << 'EOF'
{"date":"2026-09-01T10:00:00Z","file":"pattern-evidence.md","confidence":4,"injected":true,"session_id":"sX","rank":1}
EOF
printf '{"date":"2026-09-01T10:05:00Z","hash":"abc","snippet":"%s"}\n' "$SNIP" \
    > "$STATE/correction-fired-sX.jsonl"

MADE=$(dis_harvest_corrections "sX" "$STATE" 30 3)
PEND="$STATE/disagreement-pending-sX.jsonl"
_frozen=$(jq -rR 'fromjson? // empty | .snippet // empty' "$PEND" 2>/dev/null)
if [ "$MADE" = "1" ] && [ -f "$PEND" ] && grep -qF "$SNIP" <<< "$_frozen"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL [T1]: snippet поправки не заморожен в кандидате (made=$MADE): $(cat "$PEND" 2>/dev/null)"
fi

# --- T2 + T3: карточка вердикта на Stop несёт цитату и цену contradicted ---
# Запись СВОЕЙ сессии печатается детально всегда (чужие — только залежавшиеся).
# Бэклог песочницы (D1179, M1): без него сборщик берёт живой BACKLOG.md по указателю и уносит его ☑.
printf '{"session_id":"sX","transcript_path":"","cwd":""}' \
    | STATE_DIR="$STATE" CLAUDE_STATE_DIR="$STATE" CLAUDSOUL_BACKLOG="$STATE/none.md" bash "$COLLECTOR" >/dev/null 2>&1

ALERTS_FILE="$STATE/pending-alerts.txt"
if [ -f "$ALERTS_FILE" ] && grep -qF "$SNIP" "$ALERTS_FILE"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL [T2]: цитата поправки не дошла до карточки вердикта:"
    sed -n '1,20p' "$ALERTS_FILE" 2>/dev/null | sed 's/^/  /'
fi

if [ -f "$ALERTS_FILE" ] && grep -q 'ошиблось' "$ALERTS_FILE" \
   && grep -q '/retro' "$ALERTS_FILE"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL [T3]: строка «ошиблось» не называет цену вердикта (/retro + кейс)"
fi

# --- T4: цитата у ключа сессии, перенесённой уборкой в архив (D1008, второй скептик L-2) ---
# Сборщик берёт строки сессии через `_dis_lines` — архив и живой файл; прежде читал только живой, и улика у ключей
# перенесённых сессий пропадала. Сессия с UUID: в архив уходят только журналы настоящих сессий.
U=66666666-6666-6666-6666-666666666666; ST2="$TMP/state2"; mkdir -p "$ST2"
# Дата — сейчас: запись старше `DISAGREEMENT_EXPIRE_DAYS` сборщик гасит как истёкшую раньше, чем печатает карточку.
printf '{"date":"%s","key":"pattern-evidence","outcome":"pending","confidence":4,"tool":"correction","snippet":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SNIP" > "$ST2/disagreement-pending-$U.jsonl"
python3 "$HOOKS_DIR/lib/state_archive.py" archive "$ST2" disagreement-pending "disagreement-pending-$U.jsonl" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_disagreement_snippet.sh:$LINENO" >&2; exit 1; }
printf '{"session_id":"%s","transcript_path":"","cwd":""}' "$U" \
    | STATE_DIR="$ST2" CLAUDE_STATE_DIR="$ST2" CLAUDSOUL_BACKLOG="$ST2/none.md" bash "$COLLECTOR" >/dev/null 2>&1
if [ ! -e "$ST2/disagreement-pending-$U.jsonl" ] && grep -qF "$SNIP" "$ST2/pending-alerts.txt" 2>/dev/null; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL [T4]: цитата у ключа перенесённой сессии не дошла до карточки"
fi

echo "test_disagreement_snippet: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
