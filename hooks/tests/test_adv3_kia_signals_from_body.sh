#!/usr/bin/env bash
# test_adv3_kia_signals_from_body.sh
#
# АТАКА: `detection_signals` читаются из ВСЕГО файла, а не из шапки.
#
# Скрипт объявляет (докстринг `frontmatter`): «Поля знания живут В ШАПКЕ. Чтение по всему
# файлу делает утверждением любой пример в прозе: `blocker: true` из тела поднимал головное
# число замера». Для `blocker` это и вправду починено — `is_blocker` смотрит в
# `frontmatter(t)`. А `signals(t)` (строка 96) ищет по всему тексту.
#
# Значит знание, у которого в шапке `blocker: true` и НЕТ сигналов, но в прозе приведён
# ПРИМЕР записи сигналов, засчитывается как «действует» и как «выражает правило, а не
# перечень» — то есть головное число замера поднимает пример из текста. Разобранный гейт
# при этом не попадает в раздел «Объявлены инструментом, но не работают».
#
# Ожидание: знание с `blocker: true` без сигналов В ШАПКЕ — сломанный гейт: «действует 0»,
# и оно названо в разделе «не работают».

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)"
SCRIPT="$REPO/scripts/knowledge-instrument-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"; mkdir -p "$L" "$S"

FAIL=0
fail() { printf 'ПРОВАЛ: %s\n' "$*"; FAIL=1; }
ok()   { printf 'ok: %s\n' "$*"; }

cat > "$L/pattern-signals-in-body.md" <<'EOF'
---
description: знание о том, как пишутся сигналы
outcome: error
status: active
confidence: 5
impact: 5
confirmed_count: 9
blocker: true
---

## Как надо писать сигнал

Пример правильной записи (в шапке этого знания сигналов нет — их ещё не написали):

detection_signals: |
  {"tool_input_regex": "rm -rf"}

Конец примера.
EOF

out="$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$SCRIPT" 2>&1)"; rc=$?
report="$(cat "$S/knowledge-instrument.md" 2>/dev/null)"

printf -- '--- вывод замера (rc=%s) ---\n%s\n' "$rc" "$out"

# 1. Головное число: сигналов в шапке нет, «действует» обязано быть 0.
if grep -q 'действует 0' <<< "$out"; then
    ok "«действует 0» — пример из прозы не засчитан"
else
    fail "«действует» поднято примером из тела файла: $(grep -o 'действует [0-9]*' <<< "$out")"
fi

# 2. Такое знание — сломанный гейт, и оно обязано быть названо.
if grep -q 'Объявлены инструментом, но не работают' <<< "$report" \
   && grep -q 'pattern-signals-in-body' <<< "$report"; then
    ok "сломанный гейт назван в отчёте"
else
    fail "гейт без сигналов в шапке не назван сломанным — отчёт считает его рабочим"
fi

# 3. Строка «выражают правило, а не перечень» считает `tool_input_regex` из ТЕЛА.
if grep -qE '^\| из них выражают правило, а не перечень \| 0 \|' <<< "$report"; then
    ok "предикатных сигналов 0"
else
    fail "предикат посчитан по тексту тела: $(grep 'выражают правило' <<< "$report")"
fi

exit "$FAIL"
