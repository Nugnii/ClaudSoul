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
call() {  # call <sid> <tool> <transcript> [agent_id]
    # `agent_id` кладётся ровно так, как харнесс: поле ЕСТЬ только у субагента, а
    # `transcript_path` при этом остаётся РОДИТЕЛЬСКИМ (замер 17 сентября 2026, D449).
    # Прежде субагент изображался ИМЕНЕМ расшифровки `agent-*.jsonl` — формой, которой
    # харнесс не производит: ноги были зелёными, пока признак не срабатывал ни разу.
    jq -cn --arg s "$1" --arg t "$2" --arg p "$3" --arg a "${4:-}" \
        '{session_id:$s, tool_name:$t, transcript_path:$p, tool_input:{file_path:"/repo/x.sh"}}
         + (if $a == "" then {} else {agent_id:$a, agent_type:"general-purpose"} end)' \
      | STATE_DIR="$STATE_DIR" bash "$HOOK" 2>/dev/null
}
denied()  { grep -q '"permissionDecision":"deny"' <<< "${1:-}"; }
spoke()   { grep -qE "Признак повторяется|Правка не пройдёт" <<< "${1:-}"; }
# Запись без права на отказ МОЛЧИТ (D1151, 31 октября 2026), и тишина судится в паре с журналом: повод ложится строкой
# `turn:…|actor:<суффикс>|<виды>` до выбора вывода — без неё «молчит» неотличимо от «повода не увидел».
noticed() {  # noticed <sid> <суффикс актора ('' у родителя)> [вид:]
    local l; l=$(grep '^turn:' "$STATE_DIR/five-whys-$1.seen" 2>/dev/null)
    grep -qF -- "${3:-|}" <<< "$(grep -F -- "|actor:$2|" <<< "$l")"
}

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
elif [ -z "$OUT" ] && noticed "$SID" "" "event:"; then ok
else bad "event: ожидалась тишина с поводом в журнале (D1151), получено: ${OUT:0:120}"; fi

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
elif [ -z "$OUT" ] && noticed "$SID" "" "breakage:"; then ok
else bad "breakage: ожидалась тишина с поводом в журнале (D1151), получено: ${OUT:0:120}"; fi

# --- субагент: поводы РОДИТЕЛЯ отказа не дают (10 сентября 2026) ---
# Субагент получает session_id родителя, значит читает те же файлы `*-fired-<SID>`. Пойман
# прожаркой: отказ перечислил переработку 16 файлов, которых субагент не касался. Различить
# «мой повод» и «родительский» нечем — у `rework-fired` нет даже даты, — поэтому право на
# отказ снимается целиком; вывода субагенту нет вовсе (D1151).
SID=s_sub
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
OUT=$(call "$SID" Write "$TR" a1b2c3)
if denied "$OUT"; then bad "субагент: отказ по унаследованному поводу, получено: ${OUT:0:120}"
elif [ -z "$OUT" ]; then ok
else bad "субагент: ожидалась тишина (D1151), получено: ${OUT:0:120}"; fi

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
[ -z "$OUT" ] && ok || bad "carry-10e: запись при зачтённой цепочке не молчит (D1151): ${OUT:0:120}"

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

# --- 14. rework по ПРЕДМЕТУ: новый файл возвращает отказ, напоминание живо ---
# КОНТРАКТ ПЕРЕВЁРНУТ 20 сентября 2026 поправкой владельца «трижды это повод для разбора
# причин». Прежде ноги 14a-14b кодировали обратное: токен покрытия был голым родом
# (`chain-ok|rework|`), и первая же цепочка за сессию покрывала все последующие
# переработки — любых файлов, любой глубины. Предел этот держался доводом: ключ
# `rework` есть cksum ВСЕГО журнала и меняется каждым правленным файлом, поэтому цепочка
# по нему не зачлась бы никогда. Довод СНЯТ изменением устройства: ключ теперь несёт
# предмет и ступень глубины (`rework:<файл>:<ступень>`), и цепочка зачитывается.
# Цена прежнего предела измерена на самом агенте: за сессию 16dd77e3 гейт сработал 141
# раз, цепочек зачтено 26, и три промаха ОДНОГО устройства в трёх разных файлах не
# потребовали разбора ни разу — второй и третий были оплачены первым.
SID=c_rework
printf '{"path":"/x/a.sh","cycles":3}\n{"path":"/x/a.sh","cycles":3}\n' > "$STATE_DIR/rework-fired-${SID}.jsonl"
TC4="$TMP/c4.jsonl"; mk_chain_transcript "$TC4"
call "$SID" Write "$TC4" >/dev/null
# Ключ несёт ПОЛНЫЙ ПУТЬ с 20 сентября 2026: базовое имя давало один ключ разным файлам
# (`dir1/x.sh` и `dir2/x.sh`), и цепочка про один покрывала переработку другого — обход
# контракта ноги 14b совпадением имён. В дереве 43 таких файла из 1184.
grep -q '^chain-ok|rework:/x/a\.sh:' <<< "$(seen "$SID")" && ok || bad "carry-14a: rework зачтён не по предмету: $(seen "$SID")"
add_next_turn "$TC4"
printf '{"path":"/x/b.sh","cycles":3}\n{"path":"/x/b.sh","cycles":3}\n' >> "$STATE_DIR/rework-fired-${SID}.jsonl"
OUT=$(call "$SID" Write "$TC4")
if denied "$OUT"; then ok; else bad "carry-14b: цепочка про a.sh покрыла переработку b.sh — покрытие снято с рода"; fi
spoke "$OUT" && ok || bad "carry-14c: напоминание rework исчезло"

# --- 15. субагент: его цепочка зачёта НЕ пишет (общий SID); родитель с тем же поводом отказ получает ---
SID=c_sub
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
TC5="$TMP/c5.jsonl"; mk_chain_transcript "$TC5"
call "$SID" Write "$TC5" ax1 >/dev/null
grep -q '^chain-ok|' <<< "$(seen "$SID")" && bad "carry-15a: цепочка субагента записана как зачтённая" || ok
TC6="$TMP/c6.jsonl"; mk_transcript "$TC6" "Правлю строку."
OUT=$(call "$SID" Write "$TC6")
if denied "$OUT"; then ok; else bad "carry-15b: родитель без цепочки не получил отказа после субагента"; fi

# --- 16. D449: ИМЯ расшифровки субагентом не считается ---
# Положительный контроль к ноге 12: пока признак брался из basename, эта нога была
# зелёной по неверной причине. Харнесс такого пути в payload не кладёт, значит вызов
# принадлежит родителю и отказ обязан состояться.
SID=d449_name
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
TRN="$TMP/agent-looks-like-one.jsonl"; mk_transcript "$TRN" "Правлю строку, сейчас будет зелено."
OUT=$(call "$SID" Write "$TRN")
if denied "$OUT"; then ok; else bad "D449-16a: имя agent-*.jsonl без agent_id снимает отказ"; fi

# --- 17. D449: с полем agent_id отказа нет при том же поводе ---
SID=d449_field
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
OUT=$(call "$SID" Write "$TRN" abc123)
if denied "$OUT"; then bad "D449-17a: субагент получил отказ по поводу родителя"
elif [ -z "$OUT" ]; then ok
else bad "D449-17b: ожидалась тишина без отказа (D1151), получено: ${OUT:0:120}"; fi

# --- 18. D449: текст хода берётся из расшифровки АКТОРА, а не родителя ---
# След выбран ТОТ, КОТОРЫЙ У СУБАГЕНТА ЕСТЬ. Первая редакция ноги судила по отсутствию строки
# `chain-ok|` в журнале, а её запись субагенту подавлена отдельным условием (`:638`) при любом
# резолвере — нога была зелена на мутанте, где резолвер всегда отдаёт родителя (находка
# скептика 18 сентября 2026). Здесь у РОДИТЕЛЯ цепочка произнесена, у субагента в его
# собственной расшифровке — нет: гейт, читающий актора, обязан записать повод в журнал актора; гейт, читающий
# родителя, выйдет по чужой цепочке без записи. Суд — строка журнала, а не вывод (D1151: субагенту вывода нет), и
# полоса лежит и в файле субагента: прежде «напоминание» приходило от события, оставленного ногой `event`.
SID=d449_actor
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
printf '2' > "$STATE_DIR/error_streak_fired_${SID}.agent-deadbeef"
PAR="$TMP/parent-$SID.jsonl"; mk_chain_transcript "$PAR"
mkdir -p "$TMP/$SID/subagents"
AG="$TMP/$SID/subagents/agent-deadbeef.jsonl"; mk_transcript "$AG" "Правлю строку, сейчас будет зелено."
call "$SID" Write "$PAR" deadbeef >/dev/null
if noticed "$SID" .agent-deadbeef "streak:"; then ok
else bad "D449-18a: гейт промолчал субагенту — зачтена цепочка РОДИТЕЛЯ, а не прочитан актор"; fi
# Положительный контроль к ней: с цепочкой в СВОЕЙ расшифровке субагент молчания заслуживает.
SID=d449_actor_ok
printf '2' > "$STATE_DIR/error_streak_fired_${SID}"
printf '2' > "$STATE_DIR/error_streak_fired_${SID}.agent-cafe"
PAR2="$TMP/parent-$SID.jsonl"; mk_transcript "$PAR2" "Правлю строку."
mkdir -p "$TMP/$SID/subagents"
AG2="$TMP/$SID/subagents/agent-cafe.jsonl"; mk_chain_transcript "$AG2"
call "$SID" Write "$PAR2" cafe >/dev/null
if noticed "$SID" .agent-cafe; then bad "D449-18b: цепочка в расшифровке самого субагента не зачтена"; else ok; fi

echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
