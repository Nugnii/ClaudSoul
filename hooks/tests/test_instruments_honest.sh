#!/usr/bin/env bash
# test_instruments_honest.sh — прибор обязан отличать «нет расхождения» от «не измеряли» (D52).
#
# Два случая одного класса: показатель равен нулю, и ноль ничего не означает.
#
#   auto-scanner — «код ушёл вперёд документации» считался по `-- web/ bot/`, то есть по
#   именам каталогов ОДНОГО конкретного проекта. В любом репозитории без них показатель
#   был нулевым всегда. Замер на проекте, где `web/` есть: жёсткие пути дали 1 коммит,
#   «всё кроме доков» — 2.
#
#   calibrate.py — на файле СОБЫТИЙ вместо файла ФРАГМЕНТОВ печатал
#   «wrote ... (0 valid chunks)» и выходил с кодом 0. Отчёт при этом писался: полный,
#   связный и построенный ни на чём. Найдено собственным прогоном при разборе D52.
#
#   calibrate.py, второе — здесь была МОЯ ошибка. Я объявил отчёт развёртки неверным,
#   померив на файле, который выбрал сам (`intrusiveness-backfill-digest.jsonl`). На файле
#   ПО УМОЛЧАНИЮ (`intrusiveness-history.jsonl`, DEFAULT_HIST :32) всё наоборот:
#   `injection_bytes_max` строкой в 1619 записях из 2923, сессий 216 при 193 с несколькими
#   записями, и голый `python3 scripts/calibrate.py` падал с TypeError целиком. Отчёт был
#   прав по обоим пунктам. Случаи T8-T10 проверяют поведение, а не мою выборку.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

# ============================================================================
# auto-scanner: код считается по «всё, кроме доков», а не по перечню каталогов
# ============================================================================
R="$TMP/repo"; mkdir -p "$R/src"
git -C "$R" init -q; git -C "$R" config user.email t@e; git -C "$R" config user.name t
echo x > "$R/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -q -m docs
echo y > "$R/src/app.py";   git -C "$R" add -A; git -C "$R" commit -q -m code1
echo z >> "$R/src/app.py";  git -C "$R" add -A; git -C "$R" commit -q -m code2

LAST=$(git -C "$R" log -1 --format=%H -- CHANGELOG.md PLAN.md docs/architecture.md README.md CLAUDE.md .claude-docs/modules/)
OLD=$(git -C "$R" rev-list "$LAST..HEAD" --count -- web/ bot/ 2>/dev/null || echo 0)
NEW=$(git -C "$R" rev-list "$LAST..HEAD" --count -- . \
        ':(exclude)CHANGELOG.md' ':(exclude)PLAN.md' ':(exclude)docs/architecture.md' \
        ':(exclude)README.md' ':(exclude)CLAUDE.md' ':(exclude).claude-docs/*' \
        ':(exclude)SESSION.md' 2>/dev/null || echo 0)

# T1: проект без web/ и bot/ — прежний способ слеп, новый видит два коммита кода
[ "$OLD" -eq 0 ] && ok || bad "T1a" "фикстура не воспроизводит слепоту (жёсткие пути дали $OLD)"
[ "$NEW" -eq 2 ] && ok || bad "T1b" "новый способ насчитал $NEW вместо 2"

# T2: коммит, тронувший ТОЛЬКО документы, кодом не считается
echo w >> "$R/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -q -m docs2
LAST2=$(git -C "$R" log -1 --format=%H -- CHANGELOG.md PLAN.md docs/architecture.md README.md CLAUDE.md .claude-docs/modules/)
N2=$(git -C "$R" rev-list "$LAST2..HEAD" --count -- . \
        ':(exclude)CHANGELOG.md' ':(exclude)PLAN.md' ':(exclude)docs/architecture.md' \
        ':(exclude)README.md' ':(exclude)CLAUDE.md' ':(exclude).claude-docs/*' \
        ':(exclude)SESSION.md' 2>/dev/null || echo 0)
[ "$N2" -eq 0 ] && ok || bad "T2" "после обновления доков насчитано $N2 вместо 0"

# T3: в хуке не осталось перечня каталогов одного проекта
grep -q 'rev-list.*-- web/ bot/' "$REPO/hooks/auto-scanner.sh" \
    && bad "T3" "жёсткие пути web/ bot/ вернулись" || ok

# ============================================================================
# calibrate.py: нулевая выборка — отказ, а не пустой отчёт
# ============================================================================
CAL="$REPO/scripts/calibrate.py"
[ -f "$CAL" ] || { echo "FAIL: нет $CAL"; exit 1; }

# Журнал СОБЫТИЙ — не то, что скрипт умеет разбирать.
python3 - "$TMP/events.jsonl" <<'PY'
import json, sys, pathlib
rows = [json.dumps({"ts": "2026-07-01T00:00:00Z", "type": "gentle", "outcome": "ignored"}) for _ in range(20)]
pathlib.Path(sys.argv[1]).write_text("\n".join(rows) + "\n")
PY
python3 "$CAL" --history "$TMP/events.jsonl" --output "$TMP/r1.md" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok || bad "T4a" "нулевая выборка не признана отказом"
OUT=$(python3 "$CAL" --history "$TMP/events.jsonl" --output "$TMP/r1.md" 2>&1 || true)
grep -q 'не тот файл' <<< "$OUT" && ok || bad "T4b" "причина не названа: $OUT"

# Агрегат по сессиям — то, что скрипт умеет.
python3 - "$TMP/digest.jsonl" <<'PY'
import json, sys, pathlib
rows = []
for i in range(5):
    rows.append(json.dumps({
        "session_id": f"s{i}", "boundary": "stop",
        "budget": {"gentle_used": 1, "proactive_used": 1, "shrink_events": 0,
                   "gentle_max": 5, "proactive_max": 3},
        "metrics": {"gentle_accepted": 1, "gentle_ignored": 0, "proactive_events": 1,
                    "proactive_accepted": 1},
        "cost_peaks": {"injection_bytes_max": 100 + i},
        "debt": {}, "state_distribution": {}, "cascading": {},
    }))
pathlib.Path(sys.argv[1]).write_text("\n".join(rows) + "\n")
PY
python3 "$CAL" --history "$TMP/digest.jsonl" --output "$TMP/r2.md" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok || bad "T5a" "корректный агрегат не разобран"
grep -q 'injection_bytes_max' "$TMP/r2.md" && ok || bad "T5b" "показатель не попал в отчёт"

# T6: отрицательный контроль — отчёт на пустом файле тоже отказ, а не «всё хорошо».
: > "$TMP/empty.jsonl"
python3 "$CAL" --history "$TMP/empty.jsonl" --output "$TMP/r3.md" >/dev/null 2>&1
[ "$?" -ne 0 ] && ok || bad "T6 отрицательный контроль" "пустой вход прошёл как успех"

# T7: у калибровки есть срок в реестре
grep -q '^calibration' "$REPO/scripts/measurements.tsv" && ok || bad "T7" "калибровки нет в реестре замеров"

# ============================================================================
# T8-T10: приведение типа и свёртка по сессии — на файле ПО УМОЛЧАНИЮ
# ============================================================================
# Здесь была моя ошибка, и она стоила ложного утверждения в четырёх документах.
# Я «опроверг» отчёт замером на `intrusiveness-backfill-digest.jsonl` — файле, который
# выбрал сам. Но `calibrate.py` по умолчанию читает `intrusiveness-history.jsonl`
# (`DEFAULT_HIST`, :32), и там `injection_bytes_max` строкой в 1619 записях из 2923,
# а сессий 216 при 193 с несколькими записями. Голый `python3 scripts/calibrate.py` —
# ровно тот вызов, что предлагает `session-start.sh:194` — падал с TypeError целиком.
#
# Тот же класс, что и с каталогами документации часом раньше: померил не тот артефакт.
# Поэтому случаи ниже смотрят на ПОВЕДЕНИЕ, а не на выбранную мной выборку.

CAL_PY="$REPO/scripts/calibrate.py"

# T8: смешанные типы не роняют разбор
python3 - "$TMP/mixed.jsonl" <<'PYEOF'
import json, pathlib, sys
rows = []
for i in range(6):
    rows.append(json.dumps({
        "session_id": "s%d" % i, "boundary": "stop",
        "closed_at": "2026-07-0%dT00:00:00Z" % (i + 1),
        "budget": {"gentle_used": 1, "proactive_used": 1, "shrink_events": 0,
                   "gentle_max": 5, "proactive_max": 3},
        "metrics": {"gentle_accepted": 1, "gentle_ignored": 0, "proactive_events": 1,
                    "proactive_accepted": 1},
        "cost_peaks": {"injection_bytes_max": (str(100 + i) if i % 2 else 100 + i),
                       "timing_max": str(i), "silence_max": i},
        "debt": {}, "state_distribution": {}, "cascading": {"backward_count": str(i)},
    }))
pathlib.Path(sys.argv[1]).write_text("\n".join(rows) + "\n")
PYEOF
python3 "$CAL_PY" --history "$TMP/mixed.jsonl" --output "$TMP/rmix.md" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok || bad "T8a" "смешанные типы роняют разбор — приведение не работает"
grep -qE 'injection_bytes_max.*max=10[0-9]' "$TMP/rmix.md" && ok \
    || bad "T8b" "строковые значения не учтены в показателе"

# T9: свёртка по сессии — одна запись на сессию
python3 - "$TMP/dupes.jsonl" <<'PYEOF'
import json, pathlib, sys
rows = []
for i in range(10):
    rows.append(json.dumps({
        "session_id": "same", "boundary": "stop",
        "closed_at": "2026-07-%02dT00:00:00Z" % (i + 1),
        "budget": {"gentle_used": i, "proactive_used": 1, "shrink_events": 0,
                   "gentle_max": 5, "proactive_max": 3},
        "metrics": {"gentle_accepted": 1, "gentle_ignored": 0, "proactive_events": 1,
                    "proactive_accepted": 1},
        "cost_peaks": {"injection_bytes_max": 0}, "debt": {},
        "state_distribution": {}, "cascading": {},
    }))
rows.append(json.dumps({
    "session_id": "other", "boundary": "stop", "closed_at": "2026-07-01T00:00:00Z",
    "budget": {"gentle_used": 0, "proactive_used": 1, "shrink_events": 0,
               "gentle_max": 5, "proactive_max": 3},
    "metrics": {"gentle_accepted": 1, "gentle_ignored": 0, "proactive_events": 1,
                "proactive_accepted": 1},
    "cost_peaks": {"injection_bytes_max": 0}, "debt": {},
    "state_distribution": {}, "cascading": {},
}))
pathlib.Path(sys.argv[1]).write_text("\n".join(rows) + "\n")
PYEOF
OUT=$(python3 "$CAL_PY" --history "$TMP/dupes.jsonl" --output "$TMP/rdup.md" 2>&1)
grep -q '2 valid chunks' <<< "$OUT" && ok \
    || bad "T9" "сессии не свёрнуты: болтливая сессия весит больше молчаливой ($OUT)"

# T10: отрицательный контроль — без свёртки вышло бы 11.
# Без него зелёный T9 не отличим от «фикстура и так даёт 2».
LINES=$(grep -c '' "$TMP/dupes.jsonl")
[ "$LINES" -eq 11 ] && ok || bad "T10 отрицательный контроль" "фикстура содержит $LINES записей вместо 11"

echo ""
echo "instruments honest tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
