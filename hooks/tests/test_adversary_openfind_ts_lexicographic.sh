#!/usr/bin/env bash
# test_adversary_openfind_ts_lexicographic.sh — АТАКА 5: возраст считается по алфавиту.
#
# hooks/lib/open-findings-lib.sh:100 — `if d and (not oldest or d < oldest)`. Сравниваются
# СТРОКИ. Для меток одного формата алфавит совпадает с хронологией, для разных — нет:
#   «2026-09-08T00:30:00+03:00» это 2026-09-07T21:30Z — раньше, чем «2026-09-07T23:00:00Z»,
#   а по алфавиту «2026-09-08…» > «2026-09-07…», и старейшей объявляется вторая.
# Дробная часть даёт то же расхождение при равном моменте.
# Ошибка выходит наружу числом: session-collector.sh:588-591 переводит эту метку в
# «самому старому N дн.» — правдоподобное число, которое неоткуда проверить.
#
# ДОСТИЖИМОСТЬ НЕ ДОКАЗАНА: нынешний писатель (rc_log_outcome, root-cause-lib.sh:126)
# ставит `date -u '+%Y-%m-%dT%H:%M:%SZ'`, и в 402 живых метках 43 журналов смещений нет.
# Вход требует стороннего или будущего писателя; поле разбирается как строка, а не как время,
# то есть защиты от него нет никакой.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/lib/open-findings-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)   # ничего не удаляем
S="$TMP/state"; mkdir -p "$S"
# shellcheck source=/dev/null
. "$LIB"

# E1. Смещение зоны против Z. Старейшая по времени — первая (21:30Z).
cat > "$S/outcome-tz.jsonl" <<'J'
{"ts":"2026-09-08T00:30:00+03:00","key":"a","signal":"discovery","outcome":"deferred","ref":""}
{"ts":"2026-09-07T23:00:00Z","key":"b","signal":"discovery","outcome":"deferred","ref":""}
J
OLD=$(of_open_counts "$S" | awk '{print $3}')
[ "${OLD}" = "2026-09-08T00:30:00+03:00" ] \
    && ok || bad E1 "старейшей названа «${OLD}», хотя 2026-09-08T00:30:00+03:00 = 21:30Z, то есть раньше"

# E2. Доли секунды при одном моменте: «…:00.500Z» позже «…:00Z», а алфавит ставит наоборот.
cat > "$S/outcome-tz.jsonl" <<'J'
{"ts":"2026-09-07T10:00:00.500Z","key":"c","signal":"discovery","outcome":"deferred","ref":""}
{"ts":"2026-09-07T10:00:00Z","key":"d","signal":"discovery","outcome":"deferred","ref":""}
J
OLD=$(of_open_counts "$S" | awk '{print $3}')
[ "${OLD}" = "2026-09-07T10:00:00Z" ] \
    && ok || bad E2 "старейшей названа «${OLD}» — метка с долями секунды позже, а не раньше"

echo "adversary openfind ts-lexicographic: $PASS passed, $FAIL failed (песочница: $TMP)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
