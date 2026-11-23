#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# probe_D478.sh — прибор делит красный живой прогон на «рамка не собралась» и «требует настоящего
# дерева» (маркер `# СУД: только в рабочем дереве`), а не сливает их в один класс.
# Судит САМ ПРИБОР на мини-дереве; живой корпус мерит строка реестра `behavior-condition-probe`
# и пункт D1222.
# Коды: 0 — красный без маркера -> рамка 1, с маркером -> рамка 0 и класс «настоящее дерево» 1, свидетель,
#       требующий `# СУДИТ:` у всех тестов, в снимке с канарейкой прибора не в рамке;
#       1 — нарушено (в stdout слово); 2 — рамка не собралась.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
PROBE="$REPO/scripts/behavior-condition-probe.sh"
[ -f "$PROBE" ] && command -v git >/dev/null 2>&1 || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mk() {  # mk <каталог> <маркер|пусто>
    local R="$1"; mkdir -p "$R/hooks/tests" "$R/.claude-docs" || return 1
    printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$R/hooks/subject.sh"
    { printf '#!/usr/bin/env bash\n'; [ -n "$2" ] && printf '%s\n' "$2"
      printf 'bash "$(dirname "$0")/../subject.sh" >/dev/null 2>&1\nexit 1\n'; } > "$R/hooks/tests/test_adv_red.sh"
    printf '# path\tsha\tdeps\tdocs\ttests\tnames\nhooks/subject.sh\tx\t\t\thooks/tests/test_adv_red.sh\t\n' > "$R/.claude-docs/dep-index.tsv"
    h="$R/hooks"; chmod +x "$h"/*.sh "$h/tests"/*.sh
    ( cd "$R" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1
}
mk "$d/a" "" && mk "$d/b" "# СУД: только в рабочем дереве" || exit 2
mkdir -p "$d/home" "$d/st"
run() { HOME="$d/home" STATE_DIR="$d/st" CLAUDSOUL_REPO="$1" bash "$PROBE" 2>&1; }
A=$(run "$d/a"); B=$(run "$d/b")
case "$A" in *"рамка не собралась: 1"*) ;; *) echo "красный без маркера не зачислен в рамку"; exit 1 ;; esac
case "$B" in *"рамка не собралась: 0"*) ;; *) echo "красный с маркером зачислен в рамку"; exit 1 ;; esac
case "$B" in *"realtree=1"*) ;; *) echo "класс настоящего дерева пуст"; exit 1 ;; esac
# Канарейка прибора объявляет предмет (`# СУДИТ:`): свидетель, требующий объявления у КАЖДОГО теста дерева, в снимке с
# канарейкой обязан остаться зелёным, иначе он уходит в «рамку» (скептик opus по 5b9d761b, M3 — нога T8d свидетеля
# прибора этого не судит). Сам свидетель судит и свой предмет, чтобы на выхолощенном не стать ложно-зелёным.
R="$d/c"; mkdir -p "$R/hooks/tests" "$R/.claude-docs" || exit 2
printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$R/hooks/subject.sh"
printf '#!/usr/bin/env bash\n# СУДИТ: hooks/subject.sh\nt="$(cd "$(dirname "$0")" && pwd)"\ncase "$(bash "$t/../subject.sh" 2>&1)" in *MARKER*) ;; *) exit 1 ;; esac\nfor f in "$t"/test_*.sh; do grep -q "^# СУДИТ:" "$f" || exit 1; done\nexit 0\n' > "$R/hooks/tests/test_adv_decl.sh"
printf '# path\tsha\tdeps\tdocs\ttests\tnames\nhooks/subject.sh\tx\t\t\thooks/tests/test_adv_decl.sh\t\n' > "$R/.claude-docs/dep-index.tsv"
h="$R/hooks"; chmod +x "$h"/*.sh "$h/tests"/*.sh
( cd "$R" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || exit 2
C=$(run "$R")
case "$C" in *"рамка не собралась: 0"*) exit 0 ;; *) echo "канарейка без объявления предмета роняет свидетеля в рамку"; exit 1 ;; esac
