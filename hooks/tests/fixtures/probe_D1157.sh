#!/usr/bin/env bash
# СУДИТ: scripts/measurement-due.sh scripts/self-repeat-replay.py scripts/colon-lead-in-count.py scripts/authorization-replay.py scripts/question-survival.py scripts/five-whys-attribution-replay.py scripts/signal-precision-corpus.py
# Проба D1157: сломанный прибор не отвечает кодом находки — ни сам, ни у реестра замеров.
# Нога A — шесть замеров без владельца признака (`hooks/lib`) выходят кодом 2, а не 1: их код читают ещё свод на Stop
# (`--registry-in-text`) и «Проверки» бэклога (скептик D1157, M1).
# Нога B — measurement-due не засчитывает упавший питон-замер находкой: замер печатает строку и падает НЕ ImportError,
# трасса — посреди второй строки (мутанты скептика «ищи ModuleNotFoundError» и «смотри первую строку», M2, и «трасса с
# начала строки» — первая редакция, L2); отметки нет,
# события `measure-found` нет (мутант «событие при любой 1»). Событие ловит подложенный `RC_LIB`.
# Контроль: команда с кодом 1 без трассы — находка с отметкой и событием; без него проба зеленела бы от «всякая 1 — сбой».
# Код: 0 — обе ноги держатся; 1 — нет (названо); 2 — не измерено (нет файла, python3, сценарий не сработал).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../../.." && pwd -P)"
DUE="$REPO/scripts/measurement-due.sh"
[ -f "$DUE" ] || { echo "нет scripts/measurement-due.sh"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "нет python3"; exit 2; }
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1157.XXXXXX") || exit 2
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/repo/scripts" "$S/home" "$S/state" || exit 2
SIX="self-repeat-replay colon-lead-in-count authorization-replay question-survival five-whys-attribution-replay signal-precision-corpus"
: > "$S/m.tsv"
bad=0
for n in $SIX; do
    cp "$REPO/scripts/$n.py" "$S/repo/scripts/" || { echo "нет scripts/$n.py"; exit 2; }
    printf '%s\t1\tpython3 scripts/%s.py\tпроба\n' "$n" "$n" >> "$S/m.tsv"
    ( cd "$S/repo" && HOME="$S/home" python3 "scripts/$n.py" < /dev/null > /dev/null 2>&1 ); rc=$?
    [ "$rc" -eq 2 ] || { echo "$n без владельца признака вышел кодом $rc, а не 2"; bad=1; }
done
printf '%s\n' 'print("начал замер", flush=True)' 'print("частично", end="", flush=True)' 'import json' 'json.loads("{")' \
    > "$S/repo/scripts/crash-late.py"
printf 'crash-late\t1\tpython3 scripts/crash-late.py\tпадение после вывода\n' >> "$S/m.tsv"
printf 'control\t1\techo находка; exit 1\tконтроль\n' >> "$S/m.tsv"
printf '%s\n' 'rc_note_event() { printf "%s\t%s\n" "$2" "$3" >> "$PROBE_EVENTS"; }' > "$S/rc-stub.sh"
env HOME="$S/home" CLAUDSOUL_REPO="$S/repo" MEASUREMENT_REGISTRY="$S/m.tsv" STATE_DIR="$S/state" \
    RC_LIB="$S/rc-stub.sh" PROBE_EVENTS="$S/events" bash "$DUE" run > "$S/out" 2>&1 < /dev/null
R="$S/state/measurement-runs"
[ "$(grep -n 'Traceback (most recent call last):' "$R/crash-late.out" 2>/dev/null | cut -d: -f1 | head -1)" = 2 ] \
    && ! grep -q '^Traceback' "$R/crash-late.out" \
    || { echo "не измерено: crash-late не дал трассы посреди второй строки — сценарий пробы устарел"; exit 2; }
for n in $SIX crash-late; do
    [ -f "$R/$n" ] && { echo "$n: несработавший замер получил отметку прогона"; bad=1; }
done
grep -q 'просрочен: crash-late' <<< "$(grep -B1 'питон упал' "$S/out")" \
    || { echo "упавший после вывода замер не назван «питон упал»"; bad=1; }
grep -q 'выполнен, ЕСТЬ НАХОДКИ' <<< "$(grep -A1 'просрочен: control' "$S/out")" && [ -f "$R/control" ] \
    || { echo "контроль (код 1 без трассы) не прочитан находкой с отметкой"; bad=1; }
grep -q $'^measure-found\tcontrol:' "$S/events" 2>/dev/null || { echo "событие находки контроля не заведено — нога событий слепа"; bad=1; }
grep -vq $'^measure-found\tcontrol:' "$S/events" 2>/dev/null && { echo "событие заведено на несработавший замер: $(grep -v 'control:' "$S/events" | head -1)"; bad=1; }
grep -q 'не удалось: 7' "$S/out" || { echo "итог не называет семь неудач: $(tail -1 "$S/out")"; bad=1; }
[ "$bad" -eq 0 ] && echo "шесть выходят кодом 2; упавший замер не засчитан находкой, настоящая находка — засчитана"
exit "$bad"
