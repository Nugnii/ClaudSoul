#!/usr/bin/env bash
# test_adv3_kia_blocker_capital_true.sh
#
# АТАКА: `blocker: True` и `blocker: yes` — истина по YAML, ложь для замера.
#
# `is_blocker` — побайтовое `^blocker: true` (строка 154). `yaml.safe_load` читает `True`,
# `TRUE`, `yes`, `on` как булеву истину (проверено: yaml.safe_load('blocker: True') ->
# {'blocker': True}). Тот же класс уже ловили у вердикта — там нормализация появилась
# («побайтовое сравнение выпускало `Candidate`»), у `blocker` нет.
#
# Последствий два, и оба хуже, чем недосчёт:
#   1. головное число «действует» занижено — работающий гейт не виден;
#   2. это же знание попадает в ОЧЕРЕДЬ НА ПРОИЗВОДСТВО как «ещё не ставшее гейтом»,
#      получает запись в реестре входа и начинает копить срок. Через 31 день замер
#      покраснеет требованием построить инструмент, который уже стоит.
#
# Ожидание: `blocker: True` = гейт: «действует 1», в очередь не попадает, реестр входа пуст.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)"
SCRIPT="$REPO/scripts/knowledge-instrument-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"; mkdir -p "$L" "$S"

FAIL=0
fail() { printf 'ПРОВАЛ: %s\n' "$*"; FAIL=1; }
ok()   { printf 'ok: %s\n' "$*"; }

cat > "$L/pattern-capital-true.md" <<'EOF'
---
description: гейт стоит, в шапке написано True
outcome: error
status: active
confirmed_count: 30
blocker: True
detection_signals: |
  {"tool_input_regex": "rm -rf /"}
---
тело
EOF

out="$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$SCRIPT" 2>&1)"; rc=$?
report="$(cat "$S/knowledge-instrument.md" 2>/dev/null)"
ledger="$(cat "$S/knowledge-instrument-queue.json" 2>/dev/null)"

printf -- '--- вывод замера (rc=%s) ---\n%s\n--- реестр входа ---\n%s\n' "$rc" "$out" "$ledger"

if grep -q 'действует 1' <<< "$out"; then
    ok "действующий гейт посчитан"
else
    fail "гейт с 'blocker: True' не посчитан: $(grep -o 'действует [0-9]*' <<< "$out")"
fi

if grep -q 'очередь на производство: 0' <<< "$out"; then
    ok "в очередь на производство не попал"
else
    fail "уже построенный гейт стоит в очереди на производство: $(grep -o 'очередь на производство: [0-9]*' <<< "$out")"
fi

if grep -q 'pattern-capital-true' <<< "$ledger"; then
    fail "гейту заведена запись в реестре входа — он начал копить срок бездействия"
else
    ok "реестр входа его не содержит"
fi

exit "$FAIL"
