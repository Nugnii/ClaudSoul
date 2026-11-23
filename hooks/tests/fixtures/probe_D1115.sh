#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh hooks/five-whys-gate.sh scripts/outcome.sh
# probe_D1115 — снимок на момент повода различает «бэклога нет», «бэклог не прочитан» и «пункт был» для КАЖДОГО повода.
# Красная (1), пока: (а) второй повод с тем же содержимым снимка получает снимок первого, и бэклог проекта цели в нём —
# состояние до пункта, заведённого для первого повода: старый пункт снимает отказ нового (скептик D1108, H1); (б) у
# проекта цели без бэклога отсутствие не запомнено — пункт в заведённом бэклоге отвергнут «снимка нет» навсегда (M1);
# (в) бэклог, не прочитанный при первом взгляде, ложится пустым снимком — старый пункт «свеж» (L1). Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
# (а) сессия в P1, правка и пункт — в подпроекте Q; ход 1 закрыт исходом, ход 2 — новая находка
P1="$SB/a"; Q="$SB/a/q"; mkdir -p "$P1" && gproj "$Q" || exit 2
TR="$SB/ta.jsonl"; mk_tr "$TR" "$FINDING"
[ "$(dec "$(cw s1 "$Q/hooks/x.sh" "$TR" "$P1")")" = deny ] || exit 2
item "$Q/BACKLOG.md" D9985 "hooks/x.sh:4"
no s1 debt discovery D9985 "$Q" || exit 2
( cd "$Q" && git add -A && git -c user.email=t@t -c user.name=t commit -qm d9985 ) || exit 2
next_turn "$TR" "дальше" "Побочно вылезла ещё дыра: разбор ключа съезжает на пробеле, чиню заодно."
[ "$(dec "$(cw s1 "$Q/hooks/x.sh" "$TR" "$P1")")" = deny ] || exit 2
no s1 debt discovery "D9985 — тот же пункт хода 1" "$Q" && { echo "(а) пункт первого повода снял отказ второго — снимок общий" >&2; exit 1; }
# (б) у проекта цели бэклога нет; заведён ответом на повод
P1="$SB/b"; Q="$SB/b/q"; mkdir -p "$P1" && gproj "$Q" || exit 2
( cd "$Q" && git rm -q BACKLOG.md && git -c user.email=t@t -c user.name=t commit -qm nobl ) || exit 2
TB="$SB/tb.jsonl"; mk_tr "$TB" "$FINDING"
[ "$(dec "$(cw s2 "$Q/hooks/x.sh" "$TB" "$P1")")" = deny ] || exit 2
printf '%s\n' '# BACKLOG' '' > "$Q/BACKLOG.md"; item "$Q/BACKLOG.md" D9986 "hooks/x.sh:4"
no s2 debt discovery D9986 "$Q" || { echo "(б) пункт в бэклоге, заведённом ответом на повод, отвергнут" >&2; exit 1; }
# (в) бэклог не прочитан при первом взгляде
P="$SB/c"; gproj "$P" || exit 2
item "$P/BACKLOG.md" D9950 "hooks/x.sh:3"
( cd "$P" && git add -A && git -c user.email=t@t -c user.name=t commit -qm old ) || exit 2
TC="$SB/tc.jsonl"; mk_tr "$TC" "$FINDING"
chmod 000 "$P/BACKLOG.md"
cw s3 "$P/hooks/x.sh" "$TC" "$P" >/dev/null
chmod 644 "$P/BACKLOG.md"
no s3 debt discovery D9950 "$P" && { echo "(в) нечитаемый при первом взгляде бэклог дал пустой снимок — старый пункт свеж" >&2; exit 1; }
echo "снимок различает поводы, отсутствие и непрочитанное"
exit 0
