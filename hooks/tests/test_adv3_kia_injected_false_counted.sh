#!/usr/bin/env bash
# test_adv3_kia_injected_false_counted.sh
#
# АТАКА: уровень «доходило до контекста» считает записи журнала с `injected: false`.
#
# Писатель журнала — `hooks/knowledge-activator.sh:682`: `rank: ($i + 1), injected: ($i < 3)`.
# То есть в `injection-log.jsonl` пишутся ШЕСТЬ кандидатов, а инжектируются ТРИ; ранги 4-6
# помечены `injected: false` — «рассматривалось, в контекст не попало».
#
# Замер (строки 112-130) берёт из строки только `file` и `date`; поле `injected` он не
# смотрит вовсе. Поэтому строка отчёта «доходило до контекста (за всю историю)» и строка
# «доходило за 30 дней» считают отвергнутых кандидатов наравне с инжектированными.
#
# На боевом журнале (3,3 МБ): 5169 строк `injected: true`, 5169 строк `injected: false`,
# и 11 знаний встречаются ТОЛЬКО с `injected: false` — они не доходили до контекста ни разу,
# но замером посчитаны как дошедшие.
#
# Ожидание: «доходит» считает то, что дошло, — только `injected: true`.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)"
SCRIPT="$REPO/scripts/knowledge-instrument-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"; mkdir -p "$L" "$S"

FAIL=0
fail() { printf 'ПРОВАЛ: %s\n' "$*"; FAIL=1; }
ok()   { printf 'ok: %s\n' "$*"; }

for n in reached-really never-injected; do
    cat > "$L/pattern-$n.md" <<EOF
---
description: $n
outcome: success
status: active
confirmed_count: 3
---
тело
EOF
done

TODAY="$(python3 -c 'import datetime;print(datetime.datetime.now().isoformat(timespec="seconds"))')"
{
  printf '{"date":"%s","file":"pattern-reached-really.md","rank":1,"injected":true}\n'   "$TODAY"
  printf '{"date":"%s","file":"pattern-never-injected.md","rank":5,"injected":false}\n' "$TODAY"
} > "$S/injection-log.jsonl"

out="$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$SCRIPT" 2>&1)"; rc=$?
report="$(cat "$S/knowledge-instrument.md" 2>/dev/null)"

printf -- '--- вывод замера (rc=%s) ---\n%s\n' "$rc" "$out"

if grep -q 'доходит 1,' <<< "$out"; then
    ok "«доходит 1» — отвергнутый кандидат не посчитан"
else
    fail "«доходит» считает injected:false — $(grep -o 'доходит [0-9]*' <<< "$out") при одной реально дошедшей записи"
fi

if grep -qE '^\| доходило до контекста \(за всю историю\) \| 1 \|' <<< "$report"; then
    ok "строка «доходило до контекста» = 1"
else
    fail "строка отчёта: $(grep 'доходило до контекста' <<< "$report")"
fi

if grep -qE '^\| доходило за 30 дней \| 1 \|' <<< "$report"; then
    ok "строка «доходило за 30 дней» = 1"
else
    fail "строка отчёта: $(grep 'доходило за 30 дней' <<< "$report")"
fi

exit "$FAIL"
