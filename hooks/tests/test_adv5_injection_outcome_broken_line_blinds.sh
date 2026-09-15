#!/usr/bin/env bash
# test_adv5_injection_outcome_broken_line_blinds.sh
#
# АТАКА: injection-outcome.sh читает оба журнала через `jq --slurpfile`. slurpfile НЕ
# терпит невалидный JSON: одна битая строка в injection-log.jsonl роняет весь jq, вывод
# (2>/dev/null) пустеет, REPORT пуст, находки нет → exit 0. Метрика ослеплена.
#
# Битые строки в этом журнале — норма, не гипотеза: писатель исторически рождал
# «173 битые строки из 7665» (комментарий в knowledge-activator.sh), а блок ROTATE их
# СОХРАНЯЕТ (sid="?"). Сестринский anchor-review-queue.sh те же строки терпит
# (`fromjson? // empty`) — асимметрия, хотя комментарии обоих обещают «общий шаблон окна».
#
# Ожидание (верно): чистые данные дают находку (доля «не к месту» 100% > 50%, exit 1);
# одна битая строка НЕ должна прятать эту находку.
# Факт (баг): с битой строкой находка исчезает, exit 0.
#
# Тест ПАДАЕТ на текущем коде: сначала показывает находку на чистых данных (prereq),
# затем добавляет одну битую строку и требует, чтобы находка осталась.
set -u
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/../scripts/injection-outcome.sh"
[ -f "$SCRIPT" ] || SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/injection-outcome.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

TMP=$(mktemp -d)
python3 - "$TMP" <<'PY'
import json, sys, pathlib
d = pathlib.Path(sys.argv[1])
il, ol = [], []
# 20 сессий: у каждой ровно один инжект и один исход not_applicable, все сматчены,
# все в окне (данные с 2026-08-31, окно 20 сессий). 100% «не к месту» → находка.
for i in range(20):
    s = f"sess{i:02d}"; k = f"know{i:02d}.md"
    il.append(json.dumps({"date": "2026-08-31T10:00:00Z", "file": k,
                          "session_id": s, "injected": True, "slot": "main"}))
    ol.append(json.dumps({"date": "2026-08-31T11:00:00Z", "session": s,
                          "knowledge": k, "outcome": "not_applicable", "case": ""}))
(d / "injection-log.jsonl").write_text("\n".join(il) + "\n")
(d / "disagreement-outcomes.jsonl").write_text("\n".join(ol) + "\n")
PY

echo "--- prereq: чистые данные ---"
CLEAN=$(STATE_DIR="$TMP" bash "$SCRIPT" 2>/dev/null); CLEAN_RC=$?
echo "$CLEAN"
echo "exit=$CLEAN_RC"
if [ "$CLEAN_RC" -ne 1 ]; then
    echo "PREREQ FAIL: чистые данные не дали находку (ожидался exit 1)"
    echo "TEST FAILED (fixtures: $TMP)"
    exit 1
fi

echo "--- атака: одна битая строка в injection-log.jsonl ---"
printf 'это не json\n' >> "$TMP/injection-log.jsonl"
DIRTY=$(STATE_DIR="$TMP" bash "$SCRIPT" 2>/dev/null); DIRTY_RC=$?
echo "$DIRTY"
echo "exit=$DIRTY_RC"

if [ "$DIRTY_RC" -eq 1 ]; then
    echo "OK: находка пережила битую строку (баг исправлен)"
    echo "TEST PASSED"
    exit 0
fi

echo "BUG ВОСПРОИЗВЕДЁН: одна битая строка обнулила метрику —"
echo "находка исчезла (exit $DIRTY_RC вместо 1). slurpfile не терпит невалидный JSON."
echo "TEST FAILED (fixtures: $TMP)"
exit 1
