#!/usr/bin/env bash
# СУДИТ: hooks/own-frame-notice.sh
# test_own_frame_notice.sh — свидетель подсказки о владельце факта.
#
# Результат: подсказка звучит на строящейся рамке, молчит на её правках и на обычных
#            командах, и НЕ глушится для второй рамки того же хода
# Проверка результата: bash hooks/tests/test_own_frame_notice.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$(cd "$DIR/.." && pwd)/own-frame-notice.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

run() {  # run <команда> [сессия]
    printf '{"tool_name":"Bash","session_id":"%s","tool_input":{"command":%s}}' \
        "${2:-t-1}" "$(jq -Rn --arg c "$1" '$c')" \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

F1="cat > /tmp/x/scratchpad/measure.sh <<'EOF'"
F2="cat > /tmp/x/scratchpad/trace.sh <<'EOF'"

# T1 — рамка строится: подсказка звучит и называет предмет вопроса.
O=$(run "$F1")
grep -q 'own-frame\|СВОЯ рамка' <<< "$O" && ok || bad T1 "подсказки нет: ${O:0:120}"
grep -q 'назови прибор' <<< "$O" && ok || bad T1b "вопрос о владельце факта не задан"

# T2 — правка ТОЙ ЖЕ рамки молчит: вопрос уже задан.
[ -z "$(run "$F1")" ] && ok || bad T2 "повтор той же рамки не заглушён"

# T3 — ВТОРАЯ рамка того же хода спрашивает заново (поправка владельца 21 сентября 2026:
# «в ход может быть несколько разборов»). Дедуп по сессии здесь глушил бы вопрос,
# у которого СВОЙ предмет.
[ -n "$(run "$F2")" ] && ok || bad T3 "вторая рамка того же хода заглушена — дедуп судит сессию, а не предмет"

# T4 — обычная команда молчит.
[ -z "$(run "ls -la /tmp && grep -r foo .")" ] && ok || bad T4 "подсказка на обычной команде"

# T5 — скрипт ВНЕ scratchpad не рамка замера: это правка дерева, у неё свои стражи.
[ -z "$(run "cat > hooks/new-hook.sh <<'EOF'")" ] && ok || bad T5 "подсказка на правке дерева"

# T6 — другая сессия спрашивает заново: ключ несёт и сессию.
[ -n "$(run "$F1" t-2)" ] && ok || bad T6 "вторая сессия заглушена ключом первой"

echo "own frame notice: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
