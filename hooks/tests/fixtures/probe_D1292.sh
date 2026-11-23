#!/usr/bin/env bash
# СУДИТ: scripts/outcome.sh hooks/root-cause-lib.sh hooks/five-whys-gate.sh
# probe_D1292 — исход по поводу хода не ложится на повод, закрытый исходом в ПРОШЛОМ ходе. Повод в мире (ProjectA,
# 10 ноября 2026, сессия e9651ead): поправка A закрыта исходом `knowledge` в ходе 1, в ходе 2 пришла поправка B, а
# `disproved` по B лёг с поводами A и B — настоящая поправка посчитана ложной тревогой. Страж разбора считает A
# закрытой (память зачёта `chain-ok|` либо принятая строка от якоря первого хода, где повод жив — D1243), а команда
# исхода искала принятую строку только после якоря ТЕКУЩЕГО хода (D1139). Две ноги: (а) A в памяти зачёта — её пишет
# запись хода 2 до прихода B; (б) памяти нет — A только жива в ходе 2 (читающий вызов). Красная (1), пока строка
# «показалось» о B несёт A; контроль — строка несёт B. Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
P="$SB/p"; gproj "$P" || exit 2
corr() { jq -cn --arg h "$2" --arg s "$3" '{date:"2026-11-10T14:00:00Z", hash:$h, snippet:$s}' >> "$ST/correction-fired-$1.jsonl"; }
bad=0
for leg in a b; do
    s="s_$leg"; TR="$SB/tr_$leg.jsonl"; mk_tr "$TR" "Смотрю настройку почты."
    tk=$(STATE_DIR="$ST" bash -c '. "$1/hooks/root-cause-lib.sh"; rc_turn_key "$2"' _ "$R" "$TR")
    corr "$s" "$tk" "не так настроил ящик"
    [ "$(dec "$(cw "$s" "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || { echo "рамка $leg: поправка A не отбита" >&2; exit 2; }
    item "$P/BACKLOG.md" "D99${leg}1" "hooks/x.sh:4"
    no "$s" debt correction "D99${leg}1" "$P" || { echo "рамка $leg: исход по A не принят" >&2; exit 2; }
    A=$(jq -r "select(.ref == \"D99${leg}1\") | .toks[]?" "$ST/outcome-$s.jsonl")
    [ -n "$A" ] || exit 2
    next_turn "$TR" "пришло во входящие" "Проверяю доставку."
    if [ "$leg" = a ]; then
        [ "$(dec "$(cw "$s" "$P/hooks/x.sh" "$TR" "$P")")" = allow ] || { echo "рамка a: A не закрыта в ходе 2" >&2; exit 2; }
        grep -q "^chain-ok|.*${A}|" "$ST/five-whys-$s.seen" || { echo "рамка a: A нет в памяти зачёта" >&2; exit 2; }
    else
        cr "$s" "$TR" "$P"
        grep -q "^chain-ok|.*${A}|" "$ST/five-whys-$s.seen" && { echo "рамка b: A в памяти зачёта" >&2; exit 2; }
    fi
    tk2=$(STATE_DIR="$ST" bash -c '. "$1/hooks/root-cause-lib.sh"; rc_turn_key "$2"' _ "$R" "$TR")
    grep -q "^live|turn:${tk2}|${A}|" "$ST/five-whys-$s.seen" || { echo "рамка $leg: A не жива в ходе 2" >&2; exit 2; }
    corr "$s" "$tk2" "пришло во входящие"
    [ "$(dec "$(cw "$s" "$P/hooks/y.sh" "$TR" "$P")")" = deny ] || { echo "рамка $leg: поправка B не отбита" >&2; exit 2; }
    no "$s" disproved correction "реплика — подтверждение доставки, не поправка" "$P" || { echo "рамка $leg: «показалось» по B не принято" >&2; exit 2; }
    disp=$(jq -r 'select(.outcome == "disproved") | .toks[]?' "$ST/outcome-$s.jsonl")
    grep -vqxF -- "$A" <<< "$disp" || { echo "рамка $leg: в строке «показалось» нет повода B" >&2; exit 2; }
    grep -qxF -- "$A" <<< "$disp" && { echo "нога $leg: «показалось» о B легло на A, закрытую в прошлом ходе" >&2; bad=1; }
done
# (в) A закрыта ПРОИЗНЕСЁННОЙ цепочкой — память зачёта без строки исхода. В ходе 2 A жива рядом с поводом другого вида
# (повтор правки z.sh, его память не покрывает), как в мире рядом с A стояла полоса.
s=s_c; TR="$SB/tr_c.jsonl"
mk_tr "$TR" "Почему ящик не принимает письма (hooks/x.sh:4)? Потому что пароль приложения не создан. Почему не создан? Потому что двухэтапная проверка выключена. Почему выключена? Потому что ящик новый."
tk=$(STATE_DIR="$ST" bash -c '. "$1/hooks/root-cause-lib.sh"; rc_turn_key "$2"' _ "$R" "$TR")
corr "$s" "$tk" "не так настроил ящик"
[ "$(dec "$(cw "$s" "$P/hooks/x.sh" "$TR" "$P")")" = allow ] || { echo "рамка c: цепочка не сняла A" >&2; exit 2; }
A=$(grep '^chain-ok|' "$ST/five-whys-$s.seen" | tr '|' '\n' | grep '^correction:' | sort -u)
[ "$(grep -c . <<< "$A")" = 1 ] || { echo "рамка c: A нет в памяти зачёта" >&2; exit 2; }
next_turn "$TR" "пришло во входящие" "Правлю z.sh."
printf '%s\n' "{\"path\":\"$P/hooks/z.sh\",\"cycles\":3}" > "$ST/rework-fired-$s.jsonl"
cr "$s" "$TR" "$P"
tk2=$(STATE_DIR="$ST" bash -c '. "$1/hooks/root-cause-lib.sh"; rc_turn_key "$2"' _ "$R" "$TR")
grep -q "^live|turn:${tk2}|${A}|" "$ST/five-whys-$s.seen" || { echo "рамка c: A не жива в ходе 2" >&2; exit 2; }
corr "$s" "$tk2" "пришло во входящие"
[ "$(dec "$(cw "$s" "$P/hooks/y.sh" "$TR" "$P")")" = deny ] || { echo "рамка c: поправка B не отбита" >&2; exit 2; }
no "$s" disproved correction "реплика — подтверждение доставки, не поправка" "$P" || { echo "рамка c: «показалось» по B не принято" >&2; exit 2; }
disp=$(jq -r 'select(.outcome == "disproved") | .toks[]?' "$ST/outcome-$s.jsonl")
grep -vqxF -- "$A" <<< "$disp" || { echo "рамка c: в строке «показалось» нет повода B" >&2; exit 2; }
grep -qxF -- "$A" <<< "$disp" && { echo "нога c: «показалось» о B легло на A, закрытую цепочкой в прошлом ходе" >&2; bad=1; }
[ "$bad" = 0 ] && echo "исход ложится только на поводы без исхода, и прошлый ход в счёт"
exit "$bad"
