#!/usr/bin/env bash
# test_meta_contamination_unreadable.sh — нечитаемый сенсор не исчезает молча (род B).
#
# Механика. `_read()` в scripts/meta-contamination.py отдавал при OSError пустую строку.
# Пустая строка идёт дальше как обычный текст: regex не находит массив, `bash_array`
# отдаёт [], `if words:` ложно — и сенсор ПРОПАДАЕТ из таблицы, неотличимо от сенсора,
# которого нет вовсе. Ни маркера, ни счётчика, ни строки в разделе «ни разу не сработали».
#
# Замер на копии дерева: с hooks/reformulation-tracker.sh — «сенсоров: 17», без него —
# «сенсоров: 15», код 0, ни слова о пропаже. Прибор существует ради решения «какие
# словари чинить вырезанием цитат, а какие переписывать» (D88), и это решение
# принималось бы по неполному, но выглядящему полным списку. Общий страж
# `if not docs or not sens` ловит только пропажу ВСЕХ разом.
#
# Починка — не «не гасить», а гасить, НАЗВАВ ЦЕНУ (образец hooks/lib/unread-lib.sh).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/meta-contamination.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); R="$TMP/repo"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$R/scripts" "$R/hooks"
cp "$TOOL" "$R/scripts/meta-contamination.py"

# Словари сенсоров — в той форме, в какой их читает прибор (bash-массив, grep -qiE).
cat > "$R/hooks/reformulation-tracker.sh" << 'EOS'
#!/usr/bin/env bash
CORRECTION_PATTERNS=(
    "не так"
    "неверно"
)
REFORMULATION_PATTERNS=(
    "то есть"
)
EOS
cat > "$R/hooks/itr-event-detector.sh" << 'EOS'
#!/usr/bin/env bash
DECLINE_MARKERS=(
    "stop"
)
CORRECTION_MARKERS=(
    "опять"
)
EOS
printf "#!/usr/bin/env bash\nCORRECTION_REGEX='(снова|опять)'\n" > "$R/hooks/user-correction-guard.sh"
printf "#!/usr/bin/env bash\ngrep -qiE '(статус|что дальше)' <<< \"\$X\"\n" > "$R/hooks/intrusiveness-classify-lib.sh"

# Корпус: HOME уводится в песочницу, чтобы ~/.claude/global-lessons не подмешивал
# машинно-зависимые документы и число сенсоров зависело только от фикстуры.
printf 'Разбор ложных срабатываний детектора: он сказал «не так», а было не так.\nСтатус: опять сработал сенсор, снова мимо.\n' > "$R/SESSION.md"

run() { HOME="$TMP/home" python3 "$R/scripts/meta-contamination.py" 2>"$TMP/err"; }

# --- T0: контроль — всё читается, четыре словаря на месте -------------------------
OUT0=$(run); RC0=$?
ERR0=$(cat "$TMP/err")
N0=$(sed -n 's/.*сенсоров: \([0-9]*\).*/\1/p' <<< "$OUT0" | head -1)
{ [ "$RC0" -eq 0 ] && [ "${N0:-0}" -eq 6 ]; } \
    && ok "T0 читаемое дерево: код 0, сенсоров $N0" \
    || bad "T0" "на читаемом дереве код $RC0, сенсоров [${N0}] (ждали 6): $OUT0 // $ERR0"
grep -qF "не прочитано" <<< "$ERR0$OUT0" \
    && bad "T0б" "цена названа там, где всё прочитано — ложная тревога" \
    || ok "T0б на читаемом дереве о непрочитанном молчит"

# --- Мутация: один файл-сенсор становится нечитаемым ------------------------------
chmod 000 "$R/hooks/reformulation-tracker.sh"
if cat "$R/hooks/reformulation-tracker.sh" >/dev/null 2>&1; then
    echo "SKIP: chmod 000 не закрывает чтение (прогон от root) — мутацию не поставить"
    exit 0
fi

OUT1=$(run); RC1=$?
ERR1=$(cat "$TMP/err")
N1=$(sed -n 's/.*сенсоров: \([0-9]*\).*/\1/p' <<< "$OUT1" | head -1)

[ "$RC1" -ne 0 ] && ok "T1 нечитаемый сенсор — код возврата не 0 ($RC1)" \
    || bad "T1" "прибор отчитался кодом 0, потеряв словари: сенсоров $N1"
grep -qF "не прочитано" <<< "$ERR1" && ok "T2 цена названа" \
    || bad "T2" "об отказе чтения не сказано: [$ERR1] (пусто = ни строки)"
grep -qF "reformulation-tracker.sh" <<< "$ERR1" && ok "T3 назван поимённо тот файл, что не открылся" \
    || bad "T3" "имя нечитаемого файла не названо: [$ERR1] (пусто = ни строки)"
{ [ -n "$N1" ] && [ "$N1" -lt "${N0:-0}" ]; } \
    && ok "T4 предмет замера действительно сузился ($N0 → $N1) — и это сказано" \
    || bad "T4" "число сенсоров не изменилось ($N0 → $N1), фикстура не воспроизводит потерю"

echo "test_meta_contamination_unreadable: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
