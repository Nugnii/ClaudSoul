#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh
# probe_D1243 — отказ стража разбора называет повод, который ещё открыт, а не историю вида. Повод в мире (3 и 4 ноября
# 2026, сессия Biznes-sovetnik): у хода было два повода, один снят, второй открыт; отказ перечислял виды и все файлы с
# историей повторов, агент писал исход по снятому, `outcome.sh` отвечал «исход в этом ходе уже принят», и правка стояла.
# Ход пробы: находка 1 → пункт D9901 → исход `debt` снимает её; находка 2 → отказ. Открытый повод — токен из журнала
# стража (`turn:`-строка хода минус память зачёта `chain-ok|`). Красная (1), пока отказ не называет открытый токен или
# называет снятый; 2 — рамка не собралась.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
P="$SB/p"; gproj "$P" || exit 2
TR="$SB/tr.jsonl"; mk_tr "$TR" "Побочно вылезла дыра в разборе ключа в hooks/x.sh, чиню заодно."
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9901 "hooks/x.sh:4"
no s1 debt discovery D9901 "$P" || exit 2
jq -cn --arg t "Побочно вылезла ещё одна дыра: hooks/y.sh теряет последнюю строку при чтении, чиню заодно." \
    '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"
OUT=$(cw s1 "$P/hooks/y.sh" "$TR" "$P")
[ "$(dec "$OUT")" = deny ] || exit 2
SEEN="$ST/five-whys-s1.seen"; [ -f "$SEEN" ] || exit 2
OJ="$ST/outcome-s1.jsonl"; [ -f "$OJ" ] || exit 2
toks=$(grep '^turn:' "$SEEN" | tail -1 | tr '|' '\n' | grep '^discovery:' | sort -u)
# Снятый — повод, названный принятой строкой исхода (то, что `outcome.sh` называет «уже принят»), и память зачёта.
closed=$({ jq -r 'select(.outcome == "debt" and .ref == "D9901") | .toks[]?' "$OJ"
           grep '^chain-ok|' "$SEEN" | tr '|' '\n'; } | grep '^discovery:' | sort -u)
open=$(comm -23 <(printf '%s\n' "$toks") <(printf '%s\n' "$closed") | grep .)
[ "$(printf '%s\n' "$open" | grep -c .)" = 1 ] && [ -n "$closed" ] || { echo "рамка: открытых $(printf '%s\n' "$open" | grep -c .), снятых $(printf '%s\n' "$closed" | grep -c .)" >&2; exit 2; }
msg=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$OUT")
bad=0
grep -qF -- "$open" <<< "$msg" || { echo "отказ не называет открытый повод $open" >&2; bad=1; }
while IFS= read -r c; do
    [ -n "$c" ] && grep -qF -- "$c" <<< "$msg" && { echo "отказ называет снятый повод $c" >&2; bad=1; }
done <<< "$closed"
# Сценарий мира (4 ноября 2026, 01:52): в одном вызове два повода — находка и повтор правки; исход записан по находке,
# и следующий вызов судит оба: снятый здесь стоит среди ожидающих, и сценарий различает «ожидающие минус принятые» и
# «все ожидающие». Повод повтора страж заводит по файлу записи (`rework:<путь>:<ступень>`).
printf '%s\n' "{\"path\":\"$P/hooks/y.sh\",\"cycles\":3}" > "$ST/rework-fired-s2.jsonl"
TR2="$SB/tr2.jsonl"; mk_tr "$TR2" "Побочно вылезла дыра в разборе ключа в hooks/x.sh, чиню заодно."
[ "$(dec "$(cw s2 "$P/hooks/y.sh" "$TR2" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9902 "hooks/x.sh:6"
no s2 debt discovery D9902 "$P" || exit 2
OUT2=$(cw s2 "$P/hooks/y.sh" "$TR2" "$P")
[ "$(dec "$OUT2")" = deny ] || exit 2
x=$(jq -r 'select(.outcome == "debt" and .ref == "D9902") | .toks[]?' "$ST/outcome-s2.jsonl" | grep '^discovery:')
y=$(grep '^turn:' "$ST/five-whys-s2.seen" | tail -1 | tr '|' '\n' | grep '^rework:.*/y\.sh:')
grep -q '^turn:.*'"$x" <<< "$(grep '^turn:' "$ST/five-whys-s2.seen" | tail -1)" || { echo "рамка: снятый ${x} не среди поводов вызова" >&2; exit 2; }
[ -n "$x" ] && [ -n "$y" ] || { echo "рамка: снятый «${x}», открытый «${y}»" >&2; exit 2; }
short() { sed -E 's#^rework:.*/([^/]+):([0-9]+)$#rework:\1:\2#' <<< "$1"; }   # отказ называет путь базовым именем
msg2=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$OUT2")
open2=$(grep -F 'Исхода нет у повода:' <<< "$msg2")
grep -qF -- "$(short "$y")" <<< "$open2" || { echo "отказ не называет открытый повтор $(short "$y")" >&2; bad=1; }
grep -qF -- "$(short "$x")" <<< "$open2" && { echo "отказ называет снятый повтор $(short "$x")" >&2; bad=1; }
# Третий вызов: снятая находка уже в памяти зачёта (её записал второй вызов) и всё ещё среди поводов хода — открыт только
# повтор (скептик opus M2: в мире снятый повод сидел в памяти зачёта с прошлого вызова, 3 ноября 2026).
grep -q "^chain-ok|.*${x}" "$ST/five-whys-s2.seen" || { echo "рамка: в памяти зачёта нет снятой находки" >&2; exit 2; }
OUT2b=$(cw s2 "$P/hooks/y.sh" "$TR2" "$P")
[ "$(dec "$OUT2b")" = deny ] || exit 2
open2b=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$OUT2b" | grep -F 'Исхода нет у повода:')
grep -qF -- "$(short "$x")" <<< "$open2b" && { echo "отказ называет повод из памяти зачёта: $(short "$x")" >&2; bad=1; }
grep -qF -- "$(short "$y")" <<< "$open2b" || { echo "третий вызов не называет открытый повтор" >&2; bad=1; }
# Шаблон команды исхода несёт вид открытого повода, а не все виды хода (вторая половина результата; скептик opus M3).
grep -qF '<вид: rework>' <<< "$msg2" || { echo "шаблон команды не несёт ровно вид открытого повода: $(grep -o '<вид: [^>]*>' <<< "$msg2")" >&2; bad=1; }
# А — ответ команды исхода называет каждый повод своей причиной (скептик opus H1, 4 ноября 2026: «уже принят» о снятом
# склеивался с «запись старше повода» об открытом без имён). Сценарий 1: тот же пункт ещё раз по открытой находке.
err=$( ( cd "$P" && DIS_SESSION=s1 STATE_DIR="$ST" bash "$OUTCMD" debt discovery D9901 2>&1 >/dev/null ) )
grep -qF -- "$open — пункт D9901 записан до того" <<< "$err" || { echo "ответ команды не называет открытый повод с его причиной: $(head -1 <<< "$err")" >&2; bad=1; }
while IFS= read -r c; do
    [ -n "$c" ] && ! grep -qF -- "$c — исход уже принят" <<< "$err" && { echo "ответ команды не называет снятый повод $c" >&2; bad=1; }
done <<< "$closed"
# Б — исход, принятый в конце хода без следующей записи, страж помнит в новом ходе (скептик opus M1).
printf '%s\n' "{\"path\":\"$P/hooks/y.sh\",\"cycles\":3}" > "$ST/rework-fired-s3.jsonl"
TR3="$SB/tr3.jsonl"; mk_tr "$TR3" "Правлю y.sh."
[ "$(dec "$(cw s3 "$P/hooks/y.sh" "$TR3" "$P")")" = deny ] || exit 2
no s3 disproved rework "новая задача, не повтор неудачной правки" "$P" || exit 2
next_turn "$TR3" "дальше" "Продолжаю правку y.sh."
[ "$(dec "$(cw s3 "$P/hooks/y.sh" "$TR3" "$P")")" = allow ] || { echo "исход прошлого хода забыт: новый ход отбит" >&2; bad=1; }
# В — повтор правки носителя исхода (бэклог, база знаний) поводом не считается; повтор файла механизма — считается
# (скептик opus H1: повод повтора на самой записи знания не снимается ничем, кроме «показалось»).
printf '%s\n' "{\"path\":\"$P/BACKLOG.md\",\"cycles\":3}" > "$ST/rework-fired-s4.jsonl"
TR4="$SB/tr4.jsonl"; mk_tr "$TR4" "Уточняю пункт."
[ "$(dec "$(cw s4 "$P/hooks/y.sh" "$TR4" "$P")")" = allow ] || { echo "повтор правки бэклога завёл повод и отказ" >&2; bad=1; }
printf '%s\n' "{\"path\":\"$P/hooks/y.sh\",\"cycles\":3}" "{\"path\":\"$P/BACKLOG.md\",\"cycles\":3}" > "$ST/rework-fired-s5.jsonl"
OUT5=$(cw s5 "$P/hooks/y.sh" "$TR4" "$P")
grep -qF 'rework:y.sh:' <<< "$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$OUT5")" \
    || { echo "повод повтора файла механизма потерян за правкой бэклога: $(dec "$OUT5")" >&2; bad=1; }
[ "$bad" -eq 0 ] && echo "отказ называет открытый повод и его вид, ответ команды — каждый повод с причиной, исход помнится через ход, правка носителя исхода повода не заводит"
exit "$bad"
