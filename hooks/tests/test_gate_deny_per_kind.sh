#!/usr/bin/env bash
# test_gate_deny_per_kind.sh — право на отказ есть свойство СРОДА, а не расположения кода.
#
# Результат: отказ даёт любой повод, возникший в ходе; стоячий `event` не даёт
# Проверка результата: bash hooks/tests/test_gate_deny_per_kind.sh даёт 0
#
# Повод, 9 сентября 2026. `EVENT=1` стоял ровно в одном месте — внутри блока `discovery`, —
# и отказ был привилегией находки. Для `event` решение «отказа не бывает» принято
# сознательно (сигнал стоячий, приходит извне хода). Для остальных семи сродов решение НЕ
# ПРИНИМАЛОСЬ: они добавлялись по одному, каждый своим блоком, и ни один не тронул
# переменную. Дробь — сродов 9, право давал 1. Цена (D323): за сессию 219 срабатываний,
# отказов 8 (3,6%); в журналах `deferred` 243 из 1035, из них 82 у `discovery` против
# 5 у `event` и 1 у `streak`.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/five-whys-gate.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL — $1"; }

mk_transcript() {
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' >> "$1"
    jq -cn --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"
}
call() {  # call <sid> <tool> <transcript>
    jq -cn --arg s "$1" --arg t "$2" --arg p "$3" \
        '{session_id:$s, tool_name:$t, transcript_path:$p, tool_input:{file_path:"/repo/x.sh"}}' \
      | STATE_DIR="$STATE_DIR" bash "$HOOK" 2>/dev/null
}
denied()  { grep -q '"permissionDecision":"deny"' <<< "${1:-}"; }
spoke()   { grep -qE "Признак повторяется|Правка не пройдёт" <<< "${1:-}"; }

TR="$TMP/t.jsonl"; mk_transcript "$TR" "Правлю строку, сейчас будет зелено."

# --- streak: повод возник В ЭТОМ ходе, право на отказ обязано быть ---
SID=s_streak
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
OUT=$(call "$SID" Write "$TR")
if denied "$OUT"; then ok; else bad "streak: ожидался отказ (повод хода), получено: ${OUT:0:120}"; fi

# --- event: сигнал СТОЯЧИЙ, приходит извне хода — отказа быть не должно ---
SID=s_event
printf '{"ts":"2026-09-09T00:00:00Z","kind":"ci-red","detail":"прогон 1 для abc: failure","project":"","status":"open"}\n' \
    > "$STATE_DIR/pending-events.jsonl"
OUT=$(call "$SID" Write "$TR")
if denied "$OUT"; then bad "event: стоячий сигнал не должен отказывать, получено отказ"
elif spoke "$OUT"; then ok
else bad "event: ожидалось напоминание без отказа, получено: ${OUT:0:120}"; fi

# --- перечень стоячих задаётся снаружи: правило, а не зашитая константа ---
SID=s_cfg
printf '3' > "$STATE_DIR/error_streak_fired_${SID}"
OUT=$(FWG_STANDING="event streak" call "$SID" Write "$TR")
if denied "$OUT"; then bad "streak объявлен стоячим — отказа быть не должно"; else ok; fi


# --- ВЫХОД: запись исхода не блокируется, даже когда повод есть ---
SID=s_exit
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
# Перечень носителей — у владельца (`RC_OUTCOME_CARRIERS` в root-cause-lib). До 9 сентября
# 2026 он жил копиями у трёх потребителей, и ни одна не знала ни плана, ни журнала
# сессии: оба всплыли отказом гейта на записи РАЗБОРА.
for tgt in /repo/BACKLOG.md "$HOME/.claude/global-lessons/case-x.md" "$HOME/.claude/plans/p.md" /repo/SESSION.md; do
    OUT=$(jq -cn --arg s "$SID" --arg p "$TR" --arg f "$tgt" \
        '{session_id:$s, tool_name:"Write", transcript_path:$p, tool_input:{file_path:$f}}' \
      | STATE_DIR="$STATE_DIR" bash "$HOOK" 2>/dev/null)
    if denied "$OUT"; then bad "выход закрыт: отказ на записи исхода ($tgt)"; else ok; fi
done

# --- обычная правка при том же поводе отбивается, и дедуп хода этого не гасит ---
# Прежде выход по дедупу стоял выше отказа, и первый же вызов хода снимал отказ до конца.
OUT=$(call "$SID" Write "$TR")
if denied "$OUT"; then ok; else bad "обычная правка при поводе должна отбиваться"; fi


# --- breakage: жалоба на поломку СТОЯЧАЯ (точность 4 из 12) — напоминает, не отказывает ---
SID=s_brk
printf '{"date":"2026-09-09T00:00:00Z","hash":"777","snippet":"опять не работает выгрузка"}\n' \
    > "$STATE_DIR/breakage-fired-${SID}.jsonl"
OUT=$(call "$SID" Write "$TR")
if denied "$OUT"; then bad "breakage: признак с точностью 33% не должен отказывать"
elif spoke "$OUT"; then ok
else bad "breakage: ожидалось напоминание, получено: ${OUT:0:120}"; fi

# --- субагент: поводы РОДИТЕЛЯ отказа не дают (10 сентября 2026) ---
# Субагент получает session_id родителя, значит читает те же файлы `*-fired-<SID>`. Пойман
# прожаркой: отказ перечислил переработку 16 файлов, которых субагент не касался. Различить
# «мой повод» и «родительский» нечем — у `rework-fired` нет даже даты, — поэтому право на
# отказ снимается целиком, а напоминание остаётся.
SID=s_sub
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
TR_SUB="$TMP/agent-a1b2c3.jsonl"; mk_transcript "$TR_SUB" "Правлю строку, сейчас будет зелено."
OUT=$(call "$SID" Write "$TR_SUB")
if denied "$OUT"; then bad "субагент: отказ по унаследованному поводу, получено: ${OUT:0:120}"
elif spoke "$OUT"; then ok
else bad "субагент: ожидалось напоминание без отказа, получено: ${OUT:0:120}"; fi

# --- положительный контроль к нему: ТОТ ЖЕ повод у родителя отказ даёт ---
# Без этой ноги «нет отказа» неотличимо от «гейт онемел совсем».
SID=s_sub_ctl
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
OUT=$(call "$SID" Write "$TR")
if denied "$OUT"; then ok; else bad "родитель: отказ обязан остаться, получено: ${OUT:0:120}"; fi

# ═══ ПАМЯТЬ ЗАЧТЁННОЙ ЦЕПОЧКИ ПОПЕРЁК ХОДОВ (12 сентября 2026, ADR-020) ═══════════════
# Повод измерен по сессии 84af614f: 11 эпизодов отказа по репликам владельца, в 10 из них
# цепочка была зачтена в ПРЕДЫДУЩЕМ ходе при неизменном составе сродов с правом — реплика
# («делай», «что дальше», уведомление задачи) обнуляла окно текста, и разобранный повод
# требовал разбора заново. Единица зачёта теперь — состав поводов, записанный в `.seen`.
CHAIN='Почему упало? → hooks/x.sh:12 читает пустой файл. Почему файл пуст? → писатель молчит при отказе. Почему молчит? → код возврата глотается. Корень назван.'
mk_chain_transcript() {  # $1 файл — ход с цепочкой
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' >> "$1"
    jq -cn --arg t "$CHAIN" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"
}
add_next_turn() {  # $1 файл — реплика владельца и ход без цепочки
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"делай"}]}}\n' >> "$1"
    jq -cn --arg t "Правлю дальше." '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"
}
seen() { cat "$STATE_DIR/five-whys-${1}.seen" 2>/dev/null; }

# --- 10. положительный контроль: цепочка → зачёт записан; реплика владельца → пропуск со следом ---
SID=c_carry
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
TC="$TMP/c1.jsonl"; mk_chain_transcript "$TC"
OUT=$(call "$SID" Write "$TC")
if denied "$OUT"; then bad "carry-10a: цепочка в ходе, а отказ есть: ${OUT:0:120}"; else ok; fi
grep -q '^chain-ok|streak:' <<< "$(seen "$SID")" && ok || bad "carry-10b: зачёт не записан в .seen: $(seen "$SID")"
add_next_turn "$TC"
OUT=$(call "$SID" Write "$TC")
if denied "$OUT"; then bad "carry-10c: после реплики владельца тот же повод отказал снова"; else ok; fi
grep -q '^carried|' <<< "$(seen "$SID")" && ok || bad "carry-10d: след снятого отказа не записан: $(seen "$SID")"
spoke "$OUT" && ok || bad "carry-10e: напоминание при зачтённой цепочке исчезло: ${OUT:0:120}"

# --- 11. новый ЭКЗЕМПЛЯР того же срода → отказ возвращается ---
printf '3' > "$STATE_DIR/error_streak_fired_${SID}"   # новая полоса — новый отпечаток
OUT=$(call "$SID" Write "$TC")
if denied "$OUT"; then ok; else bad "carry-11: новый экземпляр полосы не дал отказа"; fi

# --- 12. новый СРОД с правом при покрытом старом → отказ ---
SID=c_newkind
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
TC2="$TMP/c2.jsonl"; mk_chain_transcript "$TC2"
call "$SID" Write "$TC2" >/dev/null
add_next_turn "$TC2"
printf '{"date":"2026-09-12T10:00:00Z","kind":"behavior","hash":"1"}\n' > "$STATE_DIR/correction-fired-${SID}.jsonl"
OUT=$(call "$SID" Write "$TC2")
if denied "$OUT"; then ok; else bad "carry-12: новая поправка не дала отказа при покрытой полосе"; fi

# --- 13. КОНТРПРИМЕР: цепочки не было → отказ как прежде, зачёта нет ---
SID=c_none
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
TC3="$TMP/c3.jsonl"; mk_transcript "$TC3" "Правлю строку."
add_next_turn "$TC3"
OUT=$(call "$SID" Write "$TC3")
if denied "$OUT"; then ok; else bad "carry-13a: без цепочки отказ пропал"; fi
grep -q '^chain-ok|' <<< "$(seen "$SID")" && bad "carry-13b: зачёт записан без цепочки" || ok

# --- 14. rework по СРОДУ: новый файл в журнале отказа не возвращает, напоминание живо ---
SID=c_rework
printf '{"path":"/x/a.sh","cycles":3}\n' > "$STATE_DIR/rework-fired-${SID}.jsonl"
TC4="$TMP/c4.jsonl"; mk_chain_transcript "$TC4"
call "$SID" Write "$TC4" >/dev/null
grep -q '^chain-ok|rework|' <<< "$(seen "$SID")" && ok || bad "carry-14a: rework зачтён не по сроду: $(seen "$SID")"
add_next_turn "$TC4"
printf '{"path":"/x/b.sh","cycles":3}\n' >> "$STATE_DIR/rework-fired-${SID}.jsonl"
OUT=$(call "$SID" Write "$TC4")
if denied "$OUT"; then bad "carry-14b: rework с новым файлом отказал при зачтённой цепочке"; else ok; fi
spoke "$OUT" && ok || bad "carry-14c: напоминание rework исчезло"

# --- 15. субагент: его цепочка зачёта НЕ пишет (общий SID); родитель с тем же поводом отказ получает ---
SID=c_sub
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
TC5="$TMP/agent-x.jsonl"; mk_chain_transcript "$TC5"
call "$SID" Write "$TC5" >/dev/null
grep -q '^chain-ok|' <<< "$(seen "$SID")" && bad "carry-15a: цепочка субагента записана как зачтённая" || ok
TC6="$TMP/c6.jsonl"; mk_transcript "$TC6" "Правлю строку."
OUT=$(call "$SID" Write "$TC6")
if denied "$OUT"; then ok; else bad "carry-15b: родитель без цепочки не получил отказа после субагента"; fi

echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
