#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh
# test_adv_gate_carrier_path_escape.sh — освобождение от отказа по «носителю исхода»
# судит ПОДСТРОКУ пути, а не сам путь, и не отменяется восхождением «..».
#
# Атака. five-whys-gate.sh:737 снимает отказ, если цель записи совпала с
# RC_OUTCOME_CARRIERS (root-cause-lib.sh:503):
#     BACKLOG[A-Za-z-]*\.md|global-lessons/|SESSION\.md|\.claude/plans/
# Выражение не якорено ни слева, ни справа и применяется к пути ЦЕЛИКОМ. Значит:
#   · ~/.claude/plans/../../hooks/five-whys-gate.sh  — содержит «.claude/plans/», а ведёт
#     в дерево механизмов: инструмент Edit разрешает «..» и пишет именно туда;
#   · hooks/SESSION.md.bak.sh — содержит «SESSION.md», механизмом при этом является;
#   · hooks/global-lessons/x.sh, BACKLOGGER.md — то же устройство.
# Отказ снимается, и правка механизма проходит без единого «почему».
#
# Что делает атаку доказанной, а не придиркой: СОСЕДНЯЯ проверка в том же участке кода
# (`_wt_outside`, hooks/lib/write-target-lib.sh:56) восхождение «..» отбивает ЯВНО, и
# комментарий там называет ровно этот сценарий — «/tmp/../Users/…/ClaudSoul/x начинается
# с /tmp/ и ведёт В ПРОЕКТ». Два освобождения от одного отказа, одна и та же уловка,
# в одном из них закрыта, в другом нет.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/five-whys-gate.sh"
[ -f "$HOOK" ] || { echo "FAIL: не найден $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

PROJ="$TMP/proj"; mkdir -p "$PROJ/hooks"
TR="$TMP/t.jsonl"
# Повод разбора — находка по ходу (срод discovery, право на отказ есть), цепочки нет.
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$TR"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",
        text:"Оказалось, страж молчит на этой форме. Чиню."}]}}' >> "$TR"

# Каждому вызову — своя сессия и своё состояние: дедуп напоминания живёт в
# $STATE/five-whys-<SID>.seen и иначе смазал бы картину вторым вызовом того же хода.
verdict() {   # verdict <метка> <file_path> → deny | remind | silent
    local st="$TMP/st-$1" out
    mkdir -p "$st"
    out=$(jq -cn --arg s "sid-$1" --arg p "$TR" --arg d "$PROJ" --arg f "$2" \
            '{session_id:$s, tool_name:"Write", transcript_path:$p, cwd:$d,
              tool_input:{file_path:$f}}' \
          | STATE_DIR="$st" bash "$HOOK" 2>/dev/null)
    if grep -q '"permissionDecision":"deny"' <<< "$out"; then printf 'deny'
    elif [ -n "$out" ]; then printf 'remind'
    else printf 'silent'; fi
}

must_deny() {  # must_deny <метка> <путь> <имя>
    local v; v=$(verdict "$1" "$2")
    if [ "$v" = "deny" ]; then ok "$3"
    else bad "$3 — ОТКАЗА НЕТ (вердикт: $v); цель: $2"; fi
}

# --- Контроль: обычная правка механизма отбивается, значит фикстура рабочая ------
must_deny ctl "$PROJ/hooks/five-whys-gate.sh" "контроль: правка механизма → отказ"

# --- Контроль обратный: настоящий носитель исхода обязан проходить ---------------
V=$(verdict ctl2 "$PROJ/BACKLOG.md")
if [ "$V" != "deny" ]; then ok "контроль: запись пункта долга отказа не получает"
else bad "контроль обратный не сработал: BACKLOG.md отбит"; fi

# --- Атака 1: восхождение из каталога планов в дерево механизмов ------------------
must_deny a1 "$HOME/.claude/plans/../../hooks/five-whys-gate.sh" \
          "цель «.claude/plans/../../hooks/five-whys-gate.sh» → отказ"

# --- Атака 2: имя механизма, СОДЕРЖАЩЕЕ имя носителя -----------------------------
must_deny a2 "$PROJ/hooks/SESSION.md.bak.sh" \
          "цель «hooks/SESSION.md.bak.sh» → отказ"
must_deny a3 "$PROJ/hooks/global-lessons/state-lock-lib.sh" \
          "цель «hooks/global-lessons/state-lock-lib.sh» → отказ"
must_deny a4 "$PROJ/hooks/BACKLOGGER.md.sh" \
          "цель «hooks/BACKLOGGER.md.sh» → отказ"

# --- Атака 3: восхождение из каталога знаний --------------------------------------
must_deny a5 "$HOME/.claude/global-lessons/../hooks/root-cause-lib.sh" \
          "цель «global-lessons/../hooks/root-cause-lib.sh» → отказ"

# --- Свидетельство: соседнее освобождение ту же уловку знает -----------------------
WT="$REPO/hooks/lib/write-target-lib.sh"
if [ -f "$WT" ]; then
    # shellcheck source=/dev/null
    . "$WT"
    if _wt_outside "/tmp/../$PROJ/hooks/x.sh" "$PROJ"; then
        bad "свидетельство не получено: _wt_outside тоже пускает «..»"
    else
        ok "свидетельство: _wt_outside восхождение «..» отбивает — правило в дереве есть"
    fi
else
    bad "свидетельство не получено: не найден $WT"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
