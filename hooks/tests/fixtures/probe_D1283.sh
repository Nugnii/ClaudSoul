#!/usr/bin/env bash
# СУДИТ: scripts/archive-checks-after-commit.sh scripts/backlog-recheck.sh
# probe_D1283 — сверка архива после коммита выбирает пункты так, как их режет и исполняет исполнитель: граница пункта —
# и заголовок `### D… ☑` старого вида, выбирается только пункт с исполнимой «Проверкой» (корень R1). Повод — 9 ноября
# 2026: после коммитов, задевших `hooks/tests/test_outcome_journal.sh`, напоминание «не измерено: D104» (блок D104 вбирал
# 1854 строки старых пунктов), после 0eaae642 — «не измерено: D447» (выбран по `# СУДИТ:` пробы, а «Проверки» нет).
# Замер 10 ноября 2026 прежним отбором: на этом файле — только D104, а D112, D211, D227 терялись внутри его «блока».
# Красная (1), пока выбор берёт D104 или D447 либо теряет D112; 2 — рамка не собралась (положительный контроль: на
# `scripts/state-prune.sh` выбор называет D1225).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
A="$R/scripts/archive-checks-after-commit.sh"
[ -f "$A" ] && [ -f "$R/BACKLOG-archive.md" ] || exit 2
sel() { ( cd "$R" && bash "$A" --select "$1" 2>/dev/null ); }
has() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }
has "$(sel scripts/state-prune.sh)" D1225 || { echo "рамка: выбор на state-prune.sh не назвал D1225" >&2; exit 2; }
bad=0
o=$(sel hooks/tests/test_outcome_journal.sh)
has "$o" D104 && { echo "D104 выбран по путям чужих пунктов: $o"; bad=1; }
has "$o" D112 || { echo "D112 не выбран, хотя его «Проверка» зовёт test_outcome_journal.sh: $o"; bad=1; }
c=$(sel scripts/defect-class-carriers.py)
has "$c" D447 && { echo "D447 выбран без исполнимой «Проверки»: $c"; bad=1; }
exit "$bad"
