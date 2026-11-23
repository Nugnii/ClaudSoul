#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh hooks/five-whys-gate.sh scripts/outcome.sh
# probe_D1110 — отношение записи к поводу и её поиск судятся по устройству предмета, а не по формам текста. Красная (1),
# пока: (а) пункт о переработанном файле отвергается, когда отказана правка ДРУГОГО файла (путь токена переработки
# абсолютный, выражение срезает «/», H2); (б) пункт о hooks/lib.sh принимается при отказе на ./lib.sh (подстрока пути,
# M1); (в) номер с точкой на конце («D9912.») не находится (L3); (г) пункт в бэклоге проекта ЦЕЛИ не находится стражем
# (M5); (д) новая цель засчитана по подстроке пути (M1); (е) путь из текста находки не судится предметом. Положительного
# контроля у (б) и (д) нет нужды — он в (а), (в), (г), (е). Рамка не собралась — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
# (а) повод — переработка hooks/x.sh (вход детектора, как его пишет rework-detector); отказ на y.sh
P="$SB/a"; gproj "$P" || exit 2
TA="$SB/ta.jsonl"; mk_tr "$TA" "правлю"
printf '{"ts":"2026-10-26T09:00:00Z","path":"%s","cycles":2}\n' "$P/hooks/x.sh" "$P/hooks/x.sh" > "$ST/rework-fired-s1.jsonl"
[ "$(dec "$(cw s1 "$P/hooks/y.sh" "$TA" "$P")")" = deny ] || exit 2
grep -q "rework:$P/hooks/x.sh:" "$ST/five-whys-s1.seen" 2>/dev/null || exit 2   # токен произвёл страж, путь абсолютный
item "$P/BACKLOG.md" D9912 "hooks/x.sh:4"
no s1 debt rework D9912 "$P" || { echo "(а) пункт о переработанном файле отвергнут при отказе на другом файле" >&2; exit 1; }
# (б) отказ на ./lib.sh, пункт только о hooks/lib.sh — другой файл
P="$SB/b"; gproj "$P" || exit 2; seq 1 20 > "$P/lib.sh"; seq 1 20 > "$P/hooks/lib.sh"
TB="$SB/tb.jsonl"; mk_tr "$TB" "$FINDING"
[ "$(dec "$(cw s2 "$P/lib.sh" "$TB" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9960 "hooks/lib.sh:4"
no s2 debt discovery D9960 "$P" && { echo "(б) пункт о hooks/lib.sh принят при отказе на ./lib.sh" >&2; exit 1; }
# (в) номер с точкой на конце
P="$SB/c"; gproj "$P" || exit 2
TC="$SB/tc.jsonl"; mk_tr "$TC" "$FINDING"
[ "$(dec "$(cw s3 "$P/hooks/x.sh" "$TC" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9913 "hooks/x.sh:4"
no s3 debt discovery "записано в D9913." "$P" || { echo "(в) номер с точкой на конце не найден" >&2; exit 1; }
# (г) сессия в общем родителе P1, правка и пункт — в подпроекте P2 со своим бэклогом, команда исхода из P2
# (родитель, а не соседний каталог: цель в соседнем временном каталоге страж считает песочницей и не отказывает)
P1="$SB/d"; P2="$SB/d/d2"; mkdir -p "$P1" && gproj "$P2" || exit 2
TD="$SB/td.jsonl"; mk_tr "$TD" "$FINDING"
[ "$(dec "$(cw s4 "$P2/hooks/x.sh" "$TD" "$P1")")" = deny ] || exit 2
item "$P2/BACKLOG.md" D9985 "hooks/x.sh:4"
no s4 debt discovery D9985 "$P2" || { echo "(г) пункт в бэклоге проекта цели командой исхода отвергнут" >&2; exit 1; }
[ "$(dec "$(cw s4 "$P2/hooks/x.sh" "$TD" "$P1")")" = deny ] && { echo "(г) пункт в бэклоге проекта цели страж не нашёл" >&2; exit 1; }
# (д) новая цель (файла ещё нет) названа в пункте только подстрокой `subhooks/new.sh` — запись о другом (M1, D1120)
P="$SB/e"; gproj "$P" || exit 2
TE="$SB/te.jsonl"; mk_tr "$TE" "$FINDING"
[ "$(dec "$(cw s5 "$P/hooks/new.sh" "$TE" "$P")")" = deny ] || exit 2
printf '%s\n' '- ☐ **D9986** находка' '  **Повод.** `hooks/y.sh:2`, а чинится `subhooks/new.sh`.' '  **Корень.** R6 — два состояния.' >> "$P/BACKLOG.md"
no s5 debt discovery D9986 "$P" && { echo "(д) новая цель засчитана по подстроке пути" >&2; exit 1; }
# (е) путь из текста находки — предмет повода: пункт о нём принят при первой цели в другом файле (D1120)
P="$SB/f"; gproj "$P" || exit 2
TF="$SB/tf.jsonl"; mk_tr "$TF" "Побочно вылезла дыра: hooks/y.sh теряет последнюю строку, чиню заодно."
[ "$(dec "$(cw s6 "$P/hooks/x.sh" "$TF" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9987 "hooks/y.sh:2"
no s6 debt discovery D9987 "$P" || { echo "(е) пункт о пути из текста находки отвергнут" >&2; exit 1; }
echo "отношение и поиск — по устройству: абсолютный токен, целый путь, номер без точки, проект цели"
exit 0
