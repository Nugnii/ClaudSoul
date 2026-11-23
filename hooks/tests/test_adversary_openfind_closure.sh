#!/usr/bin/env bash
# СУДИТ: scripts/outcome.sh
# test_adversary_openfind_closure.sh — АТАКА 4: число не умеет падать.
#
# Свод требует действия: «Довести до исхода либо назвать "показалось" с обоснованием»
# (session-collector.sh, строка ~597). Единственный названный способ довести — команда
# `scripts/outcome.sh` (её шапка: «записать исход повода разбора»).
#
# Но исход пишется НОВОЙ строкой с другим ключом: `KEY="manual-$(… cksum)"`
# (scripts/outcome.sh:43), а прежняя строка `deferred` остаётся в журнале навсегда.
# `of_open_counts` считает СТРОКИ, а не обнаружения, и знать о закрытии не может.
# Тот же разрыв у автоматического пути: в следующем ходе тот же сигнал пишется с новым
# ключом хода, и `chain-spoken` кладётся РЯДОМ с прежним `deferred`.
#
# Ожидание: выполненное требование свода уменьшает число.
# Факт: число не меняется ни от ручного закрытия, ни от автоматического — требование
#       свода невыполнимо по построению, а «115 незакрытых» растёт монотонно.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/lib/open-findings-lib.sh"
OUTCOME_SH="$REPO/scripts/outcome.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)   # ничего не удаляем
S="$TMP/state"; mkdir -p "$S"
# shellcheck source=/dev/null
. "$LIB"

# Обнаружение отложено гейтом — форма записи взята из живого журнала.
cat > "$S/outcome-sess1.jsonl" <<'J'
{"ts":"2026-09-01T10:00:00Z","key":"7","signal":"discovery","outcome":"deferred","ref":""}
J
BEFORE=$(of_open_counts "$S" | awk '{print $1}')
[ "${BEFORE:-}" = "1" ] || { echo "SKIP: базовое плечо не даёт 1 (получено «${BEFORE}»)"; exit 0; }

# D1. РУЧНОЕ ЗАКРЫТИЕ ровно тем способом, который назван в своде. С D1104 исход ссылается на ЗАПИСЬ разбора:
# пункт долга с корнем и адресом проявления в бэклоге проекта (здесь — песочница-проект, команда идёт из неё).
# С D1106 адрес обязан разрешаться: файл по адресу пункта лежит в песочнице.
P1="$TMP/proj"; mkdir -p "$P1/hooks"; seq 1 20 > "$P1/hooks/x.sh"
printf '%s\n' '# BACKLOG' '' '- ☑ **D901** Находка.' '  **Повод.** `hooks/x.sh:12` ломается.' '  **Корень.** R6 — два состояния одним значением.' > "$P1/BACKLOG.md"
# Своя карта корней: без неё прибор исходов берёт карту ClaudSoul, а в открытом снимке её нет (D1364).
printf '%s\n' '# ROOTS' '' '## R6 — два состояния мира отвечают одним значением канала' > "$P1/ROOTS.md"
if [ -f "$OUTCOME_SH" ]; then
    ( cd "$P1" && env STATE_DIR="$S" DIS_SESSION=advclose bash "$OUTCOME_SH" fixed discovery "D901 починен в этом же ходе" >/dev/null 2>&1 )
    AFTER=$(of_open_counts "$S" | awk '{print $1}')
    [ "${AFTER:-}" = "0" ] \
        && ok || bad D1 "исход записан командой outcome.sh, а счёт остался «${AFTER}» — требование свода не влияет на его же число"
else
    echo "SKIP D1: нет $OUTCOME_SH"
fi

# D2. АВТОМАТИЧЕСКОЕ ЗАКРЫТИЕ: в следующем ходе тот же сигнал разобран (chain-spoken).
cat > "$S/outcome-sess2.jsonl" <<'J'
{"ts":"2026-09-01T11:00:00Z","key":"8","signal":"discovery","outcome":"chain-spoken","ref":""}
J
AFTER2=$(of_open_counts "$S" | awk '{print $1}')
[ "${AFTER2:-}" = "0" ] \
    && ok || bad D2 "цепочка произнесена в следующем ходе, а отложенное всё ещё «${AFTER2}» — закрыть обнаружение нечем"

echo "adversary openfind closure: $PASS passed, $FAIL failed (песочница: $TMP)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
