#!/usr/bin/env bash
# test_adv5_completion_gate_spaced_local_backlog.sh
#
# АТАКА: completion-gate.sh, строка `for f in "$BACKLOG" $LOCAL_BACKLOG`.
# $LOCAL_BACKLOG раскрывается БЕЗ кавычек. Когда путь локального бэклога содержит
# пробел (проект под "Documents/Claude Projects/…" или "My Project/…"), слово дробится,
# `[ -f "$f" ]` промахивается по фрагментам, и локальный бэклог НЕ проверяется вовсе:
# красный ☑ в нём на Stop не всплывает.
#
# Ожидание (верно): красный ☑ D200 из локального бэклога попадает в systemMessage.
# Факт (баг): при пробеле в пути вывод пуст — пункт молча пропущен.
#
# Тест ПАДАЕТ на текущем коде: контроль (путь без пробела) находку даёт, атака (тот же
# файл под путём с пробелом) — нет. Разница доказывает, что виноват именно пробел.
set -u
GATE="$(cd "$(dirname "$0")/.." && pwd)/completion-gate.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

TMP=$(mktemp -d)
mkdir -p "$TMP/main" "$TMP/nospace" "$TMP/with space" "$TMP/state1" "$TMP/state2"
printf '# main backlog\nnothing done here\n' > "$TMP/main/BACKLOG.md"

ITEM='# local backlog

### D200 ☑ демо-пункт, чья проверка красная

**Проверка.** `false`
'
printf '%s' "$ITEM" > "$TMP/nospace/BACKLOG.md"
printf '%s' "$ITEM" > "$TMP/with space/BACKLOG.md"

run_gate() {  # <local-backlog-path> <cwd> <state>
    printf '{"session_id":"adv5","cwd":"%s"}' "$2" | \
        CG_BACKLOG="$TMP/main/BACKLOG.md" \
        CG_LOCAL_BACKLOG="$1" \
        STATE_DIR="$3" \
        bash "$GATE" 2>/dev/null
}

CTRL=$(run_gate "$TMP/nospace/BACKLOG.md"   "$TMP/nospace"    "$TMP/state1")
ATTACK=$(run_gate "$TMP/with space/BACKLOG.md" "$TMP/with space" "$TMP/state2")

echo "control (no space) output: [$CTRL]"
echo "attack  (space)    output: [$ATTACK]"

FAIL=0
if ! printf '%s' "$CTRL" | grep -q 'D200'; then
    echo "PREREQ FAIL: контроль без пробела не нашёл D200 — фикстура/окружение сломаны"
    FAIL=1
fi
if printf '%s' "$ATTACK" | grep -q 'D200'; then
    echo "OK: локальный бэклог под путём с пробелом проверен (баг исправлен)"
else
    echo "BUG ВОСПРОИЗВЕДЁН: локальный бэклог с пробелом в пути пропущен —"
    echo "красный ☑ D200 не попал в systemMessage (word-split на \$LOCAL_BACKLOG)."
    FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
    echo "TEST FAILED (fixtures: $TMP)"
    exit 1
fi
echo "TEST PASSED"
exit 0
