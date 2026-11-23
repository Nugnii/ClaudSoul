#!/usr/bin/env bash
# СУДИТ: scripts/defect-class-carriers.py
# probe_D1168 — в дереве без git прибор родов не отвечает «носителей: 0» кодом 0: отказ `git ls-files` значит «не
# измерено», а не «чисто». Рамка — копия прибора в каталоге вне репозитория (корень прибор берёт от своего пути).
# Красная (1), пока код 0 или 1 (1 — «носители есть», на пустом перечне невозможен); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/defect-class-carriers.py" ] || exit 2
command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" && cp "$R/scripts/defect-class-carriers.py" "$T/scripts/" || exit 2
git -C "$T" rev-parse --git-dir >/dev/null 2>&1 && exit 2   # рамка: каталог оказался внутри репозитория
for g in G F; do
    python3 "$T/scripts/defect-class-carriers.py" --genus "$g" >/dev/null 2>&1
    case $? in 0|1) echo "род $g без git ответил кодом «чисто»/«носители есть»"; exit 1 ;; esac
done
# Второй круг (скептик M1): копия в неотслеживаемой папке ЧУЖОГО репозитория — git отвечает кодом 0 и пусто.
# Копия `install.sh` рядом (D1170): без неё код 2 давало падение прибора, а не отказ git, и нога не различала дефект.
N="$T/host"; mkdir -p "$N/snap/scripts" && git -C "$N" init -q && cp "$R/scripts/defect-class-carriers.py" "$N/snap/scripts/" \
    && cp "$R/install.sh" "$N/snap/" || exit 2
python3 "$N/snap/scripts/defect-class-carriers.py" --genus G >/dev/null 2>&1
case $? in 0|1) echo "в чужом репозитории ответ кодом «чисто»/«носители есть»"; exit 1 ;; esac
# Положительный контроль (D1170, L1 скептика D1168): на живом дереве прибор МЕРИТ — 0 или 1. Мутант «всегда 2»
# прошёл бы обе ноги выше.
python3 "$R/scripts/defect-class-carriers.py" --genus G >/dev/null 2>&1
case $? in 0|1) ;; *) echo "на живом дереве прибор не измерил — ноги выше ничего не различают"; exit 1 ;; esac
exit 0
