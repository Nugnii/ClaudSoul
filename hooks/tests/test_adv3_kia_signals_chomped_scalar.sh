#!/usr/bin/env bash
# test_adv3_kia_signals_chomped_scalar.sh
#
# АТАКА: `detection_signals: |-` — валидный YAML, для замера «сигналов нет».
#
# Регулярка `signals()` (строка 96) требует буквально `detection_signals: |` и перевод
# строки сразу за палкой. Индикатор обрезки `|-` — обычная и полностью законная форма
# блочного скаляра; `yaml.safe_load` отдаёт из неё ту же строку JSON (проверено).
#
# Итог двойной: головное число «действует» занижено, а знание попадает в раздел
# «Объявлены инструментом, но не работают» — то есть отчёт обвиняет работающий гейт
# в неработоспособности. Раздел не влияет на код возврата: замер выходит с 0, и
# `measurement-due.sh` печатает «→ выполнен, находок нет», отправив stdout в /dev/null.
#
# Ожидание: сигналы, записанные валидным YAML, разбираются; ложного обвинения нет.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)"
SCRIPT="$REPO/scripts/knowledge-instrument-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"; mkdir -p "$L" "$S"

FAIL=0
fail() { printf 'ПРОВАЛ: %s\n' "$*"; FAIL=1; }
ok()   { printf 'ok: %s\n' "$*"; }

cat > "$L/pattern-chomped.md" <<'EOF'
---
description: гейт, сигналы записаны блочным скаляром с обрезкой
outcome: error
status: active
confirmed_count: 30
blocker: true
detection_signals: |-
  {"tool_input_regex": "rm -rf /"}
---
тело
EOF

out="$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$SCRIPT" 2>&1)"; rc=$?
report="$(cat "$S/knowledge-instrument.md" 2>/dev/null)"

printf -- '--- вывод замера (rc=%s) ---\n%s\n' "$rc" "$out"

if grep -q 'действует 1' <<< "$out"; then
    ok "гейт посчитан действующим"
else
    fail "сигналы в форме '|-' не разобраны: $(grep -o 'действует [0-9]*' <<< "$out")"
fi

if grep -q 'но не работают' <<< "$report"; then
    fail "рабочий гейт объявлен сломанным: $(grep 'pattern-chomped' <<< "$report")"
else
    ok "ложного обвинения нет"
fi

exit "$FAIL"
