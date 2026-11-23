#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh hooks/backlog-open-write-guard.sh scripts/backlog-return-check.sh hooks/completion-gate.sh
# test_adv3_cmdring_depth_max_zero_padded.sh — предел глубины ограды кольца (D503), записанный нулём с ведущим нулём («00»), читается оболочечными исполнителями так же, как питоновскими, и не отключает исполнение команд на нулевой глубине.
#
# Атака (противник ограды кольца, раунд 3, 1 октября 2026; вход закрытого класса 7 — «предел не
# сверялся»). Сверка предела в библиотеке — `case … in ''|*[!0-9]*|0) BACKLOG_CMD_DEPTH_MAX=2`: она
# ловит пустое, нечисловое и ЛИТЕРАЛ «0», но не «00». Два читателя одного значения расходятся:
#   · питоновские исполнители (архиватор, гейт, пересчёт) считают `int("00")` = 0 → «меньше 1» → 2;
#   · оболочечные (страж возврата, страж записи, свидетель) сравнивают `[ "$n" -ge 00 ]`, то есть
#     n ≥ 0 — ИСТИНА уже при пустом BACKLOG_CMD_RUNNING. Каждая команда отбивается «вложенность
#     … глубже 00» на нулевой глубине: страж записи не отказывает зелёной «Проверке» открытого
#     пункта никогда (отказ уровня 4 по виду «зелёная» снят; «нет строки» и «синтаксис» судятся до
#     ограды и остаются), страж возврата не исполняет ни одного условия, свидетель — ни одной ноги.
# Значение передаётся вниз по дереву: архиватор экспортирует его как есть, гейт и пересчёт кладут
# его в окружение питона, откуда его наследуют все команды.
#
# Рамка: песочница, пустой BACKLOG_CMD_RUNNING. Контроль у каждой ноги — тот же вход без ручки;
# нога G — питоновский исполнитель при той же ручке команду исполняет (значение для него законно).
set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"

# --- (W) страж записи: открытый пункт с ЗЕЛЁНОЙ «Проверкой» обязан получить отказ
W="$T/w"; mkdir -p "$W/s0" "$W/s1"; : > "$W/BACKLOG.md"
jq -cn --arg f "$W/BACKLOG.md" --arg c "$(printf -- '- ☐ **D9701** открытый пункт\n  **Проверка.** `true` → 0\n')" \
    '{tool_name:"Write", session_id:"adv3-dm00", tool_input:{file_path:$f, content:$c}}' > "$W/payload.json"
OW0=$(STATE_DIR="$W/s0" bash "$REPO/hooks/backlog-open-write-guard.sh" < "$W/payload.json" 2>/dev/null)
grep -q '"deny"' <<< "$OW0" && ok || bad WC "контроль: без ручки страж записи не отказал зелёной «Проверке» открытого D9701 — рамка не собралась: «${OW0}»"
OW1=$(BACKLOG_CMD_DEPTH_MAX=00 STATE_DIR="$W/s1" bash "$REPO/hooks/backlog-open-write-guard.sh" < "$W/payload.json" 2>/dev/null)
grep -q '"deny"' <<< "$OW1" && ok \
    || bad W "при BACKLOG_CMD_DEPTH_MAX=00 и ПУСТОМ BACKLOG_CMD_RUNNING страж записи пропустил открытый пункт с зелёной «Проверкой» — отказ уровня 4 по виду «зелёная» снят: «${OW1}»"

# --- (R) страж возврата: условие `true` на нулевой глубине обязано исполниться («НАСТУПИЛО»)
R="$T/r"; mkdir -p "$R"; git -C "$R" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv3_cmdring_depth_max_zero_padded.sh:$LINENO" >&2; exit 1; }
printf -- '- ☐ **D9702** ожидание\n  **Проверка.** `false` → 0\n  **Проверка возврата:** `true`\n' > "$R/BACKLOG.md"
OR0=$( (cd "$R" && bash "$REPO/scripts/backlog-return-check.sh") 2>&1 )
grep -q 'НАСТУПИЛО.*D9702' <<< "$OR0" && ok || bad RC "контроль: без ручки страж возврата не исполнил условие D9702: «${OR0}»"
OR1=$( (cd "$R" && BACKLOG_CMD_DEPTH_MAX=00 bash "$REPO/scripts/backlog-return-check.sh") 2>&1 )
grep -q 'НАСТУПИЛО.*D9702' <<< "$OR1" && ok \
    || bad R "при BACKLOG_CMD_DEPTH_MAX=00 страж возврата не исполнил ни одного условия на нулевой глубине: «$(printf '%s' "$OR1" | tr '\n' ' ' | cut -c1-300)»"

# --- (G) питоновский исполнитель при той же ручке команду исполняет: значение для него законно (2)
G="$T/g"; mkdir -p "$G/s"
printf -- '- ☑ **D9703** закрытие с красной «Проверкой»\n  **Результат.** проба\n  **Проверка.** `false` → 0\n' > "$G/BACKLOG.md"
printf '{"session_id":"adv3-dm00-g","cwd":"/"}' | env BACKLOG_CMD_DEPTH_MAX=00 CG_BACKLOG="$G/BACKLOG.md" STATE_DIR="$G/s" \
    bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv3_cmdring_depth_max_zero_padded.sh:$LINENO" >&2; exit 1; }
AG=$(alerts_of "$G/s" || true)
{ grep -q 'D9703' <<< "$AG" && grep -q 'расходится' <<< "$AG"; } && ok \
    || bad G0 "рамка: гейт при BACKLOG_CMD_DEPTH_MAX=00 не исполнил «Проверку» D9703 — сравнивать не с чем: «${AG}»"

echo "adv3 cmdring depth max zero padded: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
