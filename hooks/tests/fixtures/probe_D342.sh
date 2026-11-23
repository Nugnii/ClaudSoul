#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# probe_D342.sh — прибор журнала свидетелей называет ЛОЖНО-ЗЕЛЁНОГО поимённо и молчит на честном.
# Судит САМ ПРИБОР на мини-дереве (предмет, честный свидетель, ложно-зелёный), а не живой
# корпус: состояние корпуса мерит строка реестра `behavior-condition-probe` и пункт D1222.
# Коды: 0 — ложно-зелёный назван, честный нет, код прибора 1, а без ложно-зелёного — 0;
#       1 — нарушено (в stdout слово); 2 — рамка не собралась.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
PROBE="$REPO/scripts/behavior-condition-probe.sh"
[ -f "$PROBE" ] && command -v git >/dev/null 2>&1 || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
R="$d/r"; mkdir -p "$R/hooks/tests" "$R/.claude-docs" "$d/home" "$d/st" || exit 2
printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$R/hooks/subject.sh"
printf '#!/usr/bin/env bash\nREPO="$(cd "$(dirname "$0")/../.." && pwd)"\nout=$(bash "$REPO/hooks/subject.sh" 2>&1)\ncase "$out" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n' > "$R/hooks/tests/test_adv_honest.sh"
printf '#!/usr/bin/env bash\nREPO="$(cd "$(dirname "$0")/../.." && pwd)"\nbash "$REPO/hooks/subject.sh" >/dev/null 2>&1\nexit 0\n' > "$R/hooks/tests/test_adv_vacuous.sh"
# Вторая пара ПОДКЛЮЧАЕТ свой предмет (`.`): у прибора на подключение своя ветка выхолащивания (скептик opus по
# 5b9d761b, M2 — её заглушка `exit 0` проходила пробу с одними исполняющими свидетелями).
printf '#!/usr/bin/env bash\nsubj_fn() { echo MARKER; }\n' > "$R/hooks/subject_src.sh"
printf '#!/usr/bin/env bash\nREPO="$(cd "$(dirname "$0")/../.." && pwd)"\n. "$REPO/hooks/subject_src.sh"\nout=$(subj_fn 2>&1)\ncase "$out" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n' > "$R/hooks/tests/test_adv_honest_src.sh"
printf '#!/usr/bin/env bash\nREPO="$(cd "$(dirname "$0")/../.." && pwd)"\n. "$REPO/hooks/subject_src.sh"\nexit 0\n' > "$R/hooks/tests/test_adv_vacuous_src.sh"
printf '# path\tsha\tdeps\tdocs\ttests\tnames\nhooks/subject.sh\tx\t\t\thooks/tests/test_adv_honest.sh,hooks/tests/test_adv_vacuous.sh\t\nhooks/subject_src.sh\tx\t\t\thooks/tests/test_adv_honest_src.sh,hooks/tests/test_adv_vacuous_src.sh\t\n' > "$R/.claude-docs/dep-index.tsv"
h="$R/hooks"; chmod +x "$h"/*.sh "$h/tests"/*.sh
( cd "$R" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || exit 2
run() { HOME="$d/home" STATE_DIR="$d/st" CLAUDSOUL_REPO="$R" bash "$PROBE" 2>&1; }
OUT=$(run); RC=$?
case "$OUT" in *"ложно-зелёных: 2"*) ;; *) echo "ложно-зелёных не два (исполняющий и подключающий)"; exit 1 ;; esac
case "$OUT" in *"ложно-зелёные: "*"test_adv_vacuous.sh"*) ;; *) echo "исполняющий носитель не назван поимённо"; exit 1 ;; esac
case "$OUT" in *"ложно-зелёные: "*"test_adv_vacuous_src.sh"*) ;; *) echo "подключающий носитель не назван поимённо"; exit 1 ;; esac
case "$OUT" in *"ложно-зелёные: "*"test_adv_honest"*) echo "честный свидетель назван ложно-зелёным"; exit 1 ;; esac
[ "$RC" = 1 ] || { echo "код при находке $RC, ожидался 1"; exit 1; }
rm -f "$R/hooks/tests/test_adv_vacuous.sh" "$R/hooks/tests/test_adv_vacuous_src.sh"
( cd "$R" && git add -A && git -c user.email=t@t -c user.name=t commit -qm drop ) >/dev/null 2>&1 || exit 2
OUT=$(run); RC=$?
[ "$RC" = 0 ] || { echo "без ложно-зелёного код $RC, ожидался 0"; exit 1; }
case "$OUT" in *"ложно-зелёных: 0"*) exit 0 ;; *) echo "счёт без ложно-зелёного не ноль"; exit 1 ;; esac
