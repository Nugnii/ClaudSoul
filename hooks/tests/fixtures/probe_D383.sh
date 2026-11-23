#!/usr/bin/env bash
# СУДИТ: scripts/probes/R2.sh scripts/signal-precision.sh hooks/backfill-compliance.sh
# D383: три журнала, названных пунктом (реакции response-<SID>, trust-guard-authorized, canary-debug), не вернулись
# в «журналы без читателя», а читатели на месте. Остальные строки пробы R2 (иные журналы, живое состояние
# дерева) не судятся — их мерит замок реестра и их владельцы. 0 — держится; 1 — нарушено; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
[ -f "$R/scripts/probes/R2.sh" ] || { echo "рамка: нет пробы R2" >&2; exit 2; }
out=$(CLAUDSOUL_REPO="$R" bash "$R/scripts/probes/R2.sh" 2>/dev/null) || { echo "рамка: проба R2 упала" >&2; exit 2; }
for j in 'response-' 'trust-guard-authorized' 'canary-debug'; do
  grep -qF "$j" <<<"$out" && { echo "журнал $j снова без читателя: $(grep -F "$j" <<<"$out" | head -1)"; exit 1; }
done
grep -q 'response-\${sid}.jsonl' "$R/hooks/backfill-compliance.sh" || { echo "читатель реакций (backfill-compliance --live) потерян"; exit 1; }
grep -q 'trust-guard-authorized.jsonl' "$R/scripts/signal-precision.sh" || { echo "читатель authorized (signal-precision) потерян"; exit 1; }
exit 0
