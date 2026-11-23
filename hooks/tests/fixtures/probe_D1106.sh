#!/usr/bin/env bash
# СУДИТ: scripts/outcome.sh hooks/root-cause-lib.sh hooks/backlog-lib.sh
# probe_D1106 — исход снимает отказ, только если запись разбора СВЕЖАЯ и ОТНОСИТСЯ к поводу.
# Красная (1), пока давно закоммиченный пункт с корнем и адресом, не тронутый после того, как страж увидел повод,
# принимается командой исхода. Положительный контроль: свежий пункт по цели отказа принимается — без него проба
# позеленела бы и от команды, отвергающей всё. Состояние журнала стража производит сам страж (рамка
# outcome_frame_lib.sh, D1109: прежняя редакция писала контекст отказа функцией, которой больше нет). Рамка — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
P="$SB/p"; gproj "$P" || exit 2
item "$P/BACKLOG.md" D9901 "hooks/x.sh:3"
( cd "$P" && git add -A && GIT_COMMITTER_DATE='2026-01-01T00:00:00' GIT_AUTHOR_DATE='2026-01-01T00:00:00' \
    git -c user.email=t@t -c user.name=t commit -qm old ) || exit 2
touch -t 202601010000 "$P/BACKLOG.md"
TR="$SB/tr.jsonl"; mk_tr "$TR" "$FINDING"
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || exit 2
no s1 debt discovery "D9901" "$P" && { echo "старый пункт, не тронутый после повода, принят исходом" >&2; exit 1; }
item "$P/BACKLOG.md" D9902 "hooks/x.sh:5"
no s1 debt discovery "D9902" "$P" || { echo "свежий пункт по цели отказа не принят — команда отвергает всё" >&2; exit 1; }
echo "несвежая запись отвергнута, свежая по цели принята"
exit 0
