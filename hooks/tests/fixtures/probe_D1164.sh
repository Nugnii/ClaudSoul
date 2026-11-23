#!/usr/bin/env bash
# СУДИТ: hooks/fsrs-lib.sh hooks/tests/test_fsrs_lib.sh
# Проба D1164: нога «без реестра — календарный фоллбек» `test_fsrs_lib.sh` зелёная в часы, когда «30 суток назад»
# через переход часов ложится на соседнюю местную дату. Время подменяется только для «сейчас» (`date +%s` и формат без
# отметки) — подменным `date` в PATH; пояс Europe/Warsaw:
#   23:30 CET через неделю после перехода на зимнее (1 ноября 2026) — местная дата отметки на день позже: прежде 29;
#   00:30 CEST через неделю после перехода на летнее (6 апреля 2026) — на день раньше: прежде 31.
# Мутант localdate — ветка мгновений без реестра снята, фоллбек снова идёт через местную дату: тест обязан покраснеть
# хотя бы в одном из двух часов (иначе проба не различает).
# Код: 0 — нынешняя библиотека зелёная в оба часа, мутант красен; 1 — нет (названо); 2 — рамка не собралась.
set -u
R="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -f "$R/hooks/fsrs-lib.sh" ] && [ -f "$R/hooks/tests/test_fsrs_lib.sh" ] && [ -x /bin/date ] || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1164.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" || exit 2
cat > "$W/bin/date" <<'SH'
#!/usr/bin/env bash
# «сейчас» — FAKE_NOW; отметки (-r, -d, -j) идут к настоящему date
if [ "$#" -eq 1 ] && [ "$1" = "+%s" ]; then echo "$FAKE_NOW"; exit 0; fi
if [ "$#" -eq 1 ] && [ "${1#+}" != "$1" ]; then
    /bin/date -r "$FAKE_NOW" "$1" 2>/dev/null || /bin/date -d "@$FAKE_NOW" "$1"; exit; fi
exec /bin/date "$@"
SH
chmod +x "$W/bin/date" || exit 2
mk() {   # mk <имя> [<было> <стало>] — копия библиотек и теста, мутант в fsrs-lib
    mkdir -p "$W/$1/hooks/tests" && cp "$R"/hooks/*.sh "$W/$1/hooks/" \
        && cp "$R/hooks/tests/test_fsrs_lib.sh" "$W/$1/hooks/tests/" || return 1
    [ $# -eq 1 ] && return 0
    python3 - "$W/$1/hooks/fsrs-lib.sh" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
run() { FAKE_NOW="$2" TZ=Europe/Warsaw PATH="$W/bin:$PATH" bash "$W/$1/hooks/tests/test_fsrs_lib.sh" >/dev/null 2>&1; echo $?; }
FALL=1793572200 SPRING=1775428200
[ "$(FAKE_NOW=$FALL "$W/bin/date" +%s)" = "$FALL" ] || { echo "рамка: подменный date не отдаёт «сейчас»"; exit 2; }
mk cur || exit 2
mk localdate '    if [ -z "$_idx" ]; then
        _now=$(date +%s)' '    if false; then
        _now=$(date +%s)' || { echo "мутант localdate не встал"; exit 2; }
bad=0
for t in $FALL $SPRING; do
    rc=$(run cur "$t")
    [ "$rc" = 0 ] || { echo "test_fsrs_lib в $(TZ=Europe/Warsaw /bin/date -r "$t" 2>/dev/null || TZ=Europe/Warsaw /bin/date -d "@$t") — код $rc"; bad=1; }
done
m1=$(run localdate $FALL); m2=$(run localdate $SPRING)
[ "$m1" != 0 ] || [ "$m2" != 0 ] || { echo "мутант localdate зелёный в оба часа — проба не различает"; bad=1; }
[ "$bad" -eq 0 ] && echo "test_fsrs_lib зелёный в 23:30 CET и 00:30 CEST после переходов; мутант по местной дате красен ($m1/$m2)"
exit "$bad"
