#!/usr/bin/env bash
# test_adv3_kia_guessed_age_hidden.sh
#
# АТАКА: пункт с провенансом `guessed` НИКОГДА не показывает возраст в отчёте —
# ни числа, ни ⏰, — хотя в счёт «Просрочено: N» он входит.
#
# `age_mark()` (строка 319): если `source == "guessed"`, возвращается «дата входа не
# записана» — БЕЗ числа. Провенанс же остаётся `guessed` навсегда: он ставится один раз,
# при первом появлении пункта, и переживает все следующие прогоны. Значит через 240 дней
# ячейка выглядит ровно так же, как в день входа: «дата входа не записана».
#
# А `overdue` считает такой пункт по фактической дате (240 дн. > 30), и отчёт печатает
# «Просрочено: 2». Читатель отчёта ищет в таблице два ⏰ и находит одно.
#
# Отчёт — единственный переживающий артефакт: `measurement-due.sh:107` запускает замер как
# `eval "$cmd" >/dev/null 2>&1`, то есть stdout со строкой «· 240 дн. — pattern-...»
# выбрасывается, а на экран выводится «→ выполнен, ЕСТЬ НАХОДКИ — смотри вывод замера».
#
# Достижимость не гипотетическая: в боевом реестре
# `~/.claude/hooks/state/knowledge-instrument-queue.json` пункт
# `pattern-subject-of-measurement-mismatch` записан с `"source": "guessed"` — тот самый,
# ради которого D106 и делался (вердикт `candidate` с 29 июля).
#
# Ожидание: в ячейке «В очереди» стоит число дней и признак просрочки.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)"
SCRIPT="$REPO/scripts/knowledge-instrument-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"; mkdir -p "$L" "$S"

FAIL=0
fail() { printf 'ПРОВАЛ: %s\n' "$*"; FAIL=1; }
ok()   { printf 'ok: %s\n' "$*"; }

cat > "$L/pattern-old-guessed.md" <<'EOF'
---
description: кандидат без записанной даты разбора
outcome: error
status: active
confirmed_count: 28
instrument_verdict: candidate
---
тело
EOF

LONG_AGO="$(python3 -c 'import datetime;print(datetime.date.today()-datetime.timedelta(days=240))')"
cat > "$S/knowledge-instrument-queue.json" <<EOF
{"pattern-old-guessed": {"since": "$LONG_AGO", "source": "guessed"}}
EOF

out="$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$SCRIPT" 2>&1)"; rc=$?
report="$(cat "$S/knowledge-instrument.md" 2>/dev/null)"
row="$(grep 'pattern-old-guessed' <<< "$report")"

printf -- '--- вывод замера (rc=%s) ---\n%s\n--- строка таблицы ---\n%s\n' "$rc" "$out" "$row"

if grep -q '240 дн\.' <<< "$row"; then
    ok "возраст пункта показан числом"
else
    fail "пункт стоит 240 дн., а в таблице отчёта: «$(sed 's/.*| \([^|]*\) | .pattern-old-guessed.*/\1/' <<< "$row")» — ни числа, ни ⏰"
fi

if grep -q '⏰' <<< "$row"; then
    ok "просрочка помечена в строке таблицы"
else
    fail "в отчёте «$(grep -o 'Просрочено: [0-9]*' <<< "$report")», а в таблице ни одного ⏰ — искать просроченный пункт не по чему"
fi

exit "$FAIL"
