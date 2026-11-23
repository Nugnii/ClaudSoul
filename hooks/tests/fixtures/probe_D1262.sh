#!/usr/bin/env bash
set -u
# СУДИТ: scripts/setup-call-guard.py
# probe_D1262 — признак немых подготовительных вызовов судит ХВОСТ списка `a && <вызов>` как свою команду:
#   (к) песочница: `[ -d x ] && cp a y/ 2>/dev/null` и `( cd x && git status ) >/dev/null` — носители,
#       `cp a y/ 2>/dev/null && echo ok` — нет (код читает связка);
#       группа, чей код читает следующая команда (`…; } && ok || bad`), — не носитель (скептик opus D1262, H1);
#   (ф) `--fix` ставит хвосту стража ВНУТРЬ: при ложном `[ -d x ]` свидетель проходит, страж молчит;
#   (п) в дереве носителей 0: каждый хвост разобран по роли.
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
G="$R/scripts/setup-call-guard.py"
[ -f "$G" ] && command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hooks/tests" && git -C "$T" init -q || exit 2   # `git status` в песочнице обязан проходить
printf '%s\n' '#!/usr/bin/env bash' 'cd "$(dirname "$0")" || exit 2' '[ -d nope ] && cp a y/ 2>/dev/null' \
    '( cd . && git status ) >/dev/null' 'cp a y/ 2>/dev/null && echo ok' \
    '{ [ -d nope ] && ( cd . \' '  && git status ) >/dev/null 2>&1; } && echo ok \' '    || echo bad' \
    'echo end' > "$T/hooks/tests/test_x.sh"
k=$(python3 "$G" --root "$T" --count 2>/dev/null)
[ "$k" = 2 ] || { echo "в песочнице носителей ${k:-?}, а не 2: хвост списка не виден либо голова принята за немую"; exit 1; }
python3 "$G" --root "$T" --fix >/dev/null 2>&1
bash -n "$T/hooks/tests/test_x.sh" 2>/dev/null || { echo "--fix сломал синтаксис свидетеля"; exit 1; }
out=$(bash "$T/hooks/tests/test_x.sh" 2>&1)
case "$out" in *"подготовка мира не удалась"*:3*) echo "страж хвоста поднялся на ложном условии головы"; exit 1 ;; esac
case "$out" in *end*) ;; *) echo "свидетель песочницы не дошёл до конца: ${out:0:200}"; exit 1 ;; esac
n=$(python3 "$G" --root "$R" --count 2>/dev/null)
[ "$n" = 0 ] || { echo "в дереве носителей ${n:-?}: хвосты списков не разобраны"; exit 1; }
echo "хвост списка — носитель, страж ему ставится внутрь; в дереве носителей 0"
exit 0
