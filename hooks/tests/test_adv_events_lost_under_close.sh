#!/usr/bin/env bash
# test_adv_events_lost_under_close.sh — журнал внешних поводов теряет запись:
# писатель дописывает БЕЗ ЗАМКА, а закрыватель переписывает файл целиком ПОД замком.
#
# Шапка root-cause-lib.sh:25 объявляет: «Общий замок и правка под ним (род H): журнал
# поводов разбора общий на сессию», и `rc_close_events` (:271) действительно идёт через
# `atomic_filter` — то есть читает файл, строит рядом временный и делает `mv`.
# А `rc_note_event` (:242) дописывает голым `>>`, замка не берёт вовсе.
#
# Значит любая запись, легшая между «фильтр прочитал» и «mv переименовал», исчезает
# молча: `mv` кладёт на место снимок, сделанный ДО неё. Ни ошибки, ни следа — повод
# разбора, заведённый миром, просто перестаёт существовать.
#
# Писатели и закрыватель — РАЗНЫЕ процессы, и их одновременность не гипотетична:
#   писатели  — revert-signal.sh (PostToolUse[Bash]), subagent-outcome.sh (SubagentStop),
#               scripts/ci-status.sh и scripts/backlog-recheck.sh (launchd, по расписанию);
#   закрыватель — declared-problem-recorded.sh:201 (Stop).
# Прибор по расписанию и хук границы хода про существование друг друга не знают.
#
# Как гонка сделана воспроизводимой. Настоящий `atomic_filter` — «прочитать → записать
# рядом → переименовать»; окно между первым и третьим шагом на живой машине микроскопично.
# Подставной `jq` в PATH ТОЛЬКО у закрывателя делает ровно то же самое, но с паузой между
# чтением и выдачей: снимок входа — сон — вывод. Механизм не выдуман, расширено окно.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/root-cause-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: не найден $LIB"; exit 1; }
REAL_JQ=$(command -v jq 2>/dev/null) || { echo "SKIP: jq недоступен"; exit 0; }
[ -n "${REAL_JQ:-}" ] || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

STATE="$TMP/state"; mkdir -p "$STATE"
PROJ="$TMP/proj";   mkdir -p "$PROJ"
EV="$STATE/pending-events.jsonl"

# Подставной jq: снимок входа, пауза, настоящий jq. Ставится в PATH только закрывателю.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/jq" <<'SHIM'
#!/usr/bin/env bash
printf 'called\n' >> "$SHIM_LOG"
IN=$(cat)
sleep "${SLOW_JQ_S:-1}"
printf '%s' "$IN" | "$REAL_JQ" "$@"
SHIM
chmod +x "$TMP/bin/jq"

# --- Контроль: без гонки закрытие работает как обещано ---------------------------
(
    # shellcheck source=/dev/null
    . "$LIB"
    RC_EVENT_PROJECT="$PROJ"
    rc_note_event "$STATE" "ci-red" "первое событие"
    rc_close_events "$STATE" "$PROJ"
)
if [ "$(grep -c '' "$EV" 2>/dev/null || true)" -eq 1 ] \
   && grep -q '"status":"closed"' "$EV" 2>/dev/null; then
    ok "контроль: событие заведено и закрыто, запись на месте"
else
    bad "контроль не сработал — фикстура негодна: $(cat "$EV" 2>/dev/null)"
fi

# --- Атака: запись, легшая во время переписывания файла ---------------------------
(
    # shellcheck source=/dev/null
    . "$LIB"
    RC_EVENT_PROJECT="$PROJ"
    rc_note_event "$STATE" "revert" "откат, который нужно разобрать"
)
BEFORE=$(grep -c '' "$EV" 2>/dev/null || true)

SHIM_LOG="$TMP/shim.log"; : > "$SHIM_LOG"
(
    PATH="$TMP/bin:$PATH" REAL_JQ="$REAL_JQ" SLOW_JQ_S=4 SHIM_LOG="$SHIM_LOG" \
    bash -c '. "$1"; rc_close_events "$2" "$3"' _ "$LIB" "$STATE" "$PROJ"
) &
CLOSER=$!
# Ждём, пока подставной фильтр ДЕЙСТВИТЕЛЬНО прочитал файл и ушёл в паузу: иначе
# гонка не воспроизводится и зелёный был бы ложным.
i=0
while [ ! -s "$SHIM_LOG" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i+1)); done
sleep 0.3
(
    # shellcheck source=/dev/null
    . "$LIB"
    RC_EVENT_PROJECT="$PROJ"
    rc_note_event "$STATE" "hotfix-repeat" "СРОЧНЫЙ повод, заведённый во время закрытия"
)
wait "$CLOSER" 2>/dev/null || true

AFTER=$(grep -c '' "$EV" 2>/dev/null || true)
if [ ! -s "$SHIM_LOG" ]; then
    bad "гонка НЕ воспроизведена: подставной фильтр не вызывался — результат ниже недействителен"
fi
if grep -q 'СРОЧНЫЙ повод' "$EV" 2>/dev/null; then
    ok "повод, заведённый во время закрытия, уцелел (строк было $BEFORE, стало $AFTER)"
else
    bad "ПОВОД ПОТЕРЯН МОЛЧА: строк было $BEFORE, стало $AFTER, записи «СРОЧНЫЙ повод» нет"
    echo "       журнал сейчас:"
    sed 's/^/         /' "$EV" 2>/dev/null
fi

# --- Свидетельство: закрыватель замок берёт, писатель — нет -----------------------
if grep -q 'atomic_filter' "$LIB"; then
    ok "свидетельство: rc_close_events идёт через atomic_filter (замок есть)"
else
    bad "свидетельство не получено: atomic_filter в библиотеке не найден"
fi
if grep -qE '^\s+jq -cn .*>> "\$_rc_ef"' "$LIB" \
   || grep -q '>> "$_rc_ef"' "$LIB"; then
    ok "свидетельство: rc_note_event дописывает голым >> — замка на этой стороне нет"
else
    bad "свидетельство не получено: форма записи в rc_note_event не найдена"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
