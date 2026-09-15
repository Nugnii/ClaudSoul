#!/usr/bin/env bash
# test_backlog_reading_refresh.sh — показание пересчитывается при изменении бэклога.
#
# Результат: после записи в BACKLOG.md показание открытого пункта равно выводу его команды;
#            закрытые пункты и пункты без команды не трогаются
# Проверка результата: bash hooks/tests/test_backlog_reading_refresh.sh даёт 0
#
# Повод — поправка владельца 30 августа 2026: «накопления должны обновляться у пунктов
# бэклога каждый раз, когда туда что-то добавляется или удаляется». Замер того же часа:
# D206 говорил «накоплено 13», фактически 19, и условие возврата ссылалось именно на это
# число — решение о закрытии принималось бы по устаревшей величине.
#
# КОНТРПРИМЕРЫ, все проверяются ниже:
#   · пункт БЕЗ строки `**Показание.**` не трогается (показание-суждение — законная форма);
#   · ЗАКРЫТЫЙ пункт не трогается: его показание — свидетельство на момент закрытия;
#   · запись в другой файл хук не будит;
#   · нет скрипта пересчёта — тишина, а не падение.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HOOKS/.." && pwd)"
HOOK="$HOOKS/backlog-reading-refresh.sh"
REFRESH="$ROOT/scripts/backlog-refresh-readings.sh"
for f in "$HOOK" "$REFRESH"; do [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 250)"; fi
}
assert_empty() {
    if [ -z "${1//[[:space:]]/}" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина: $(printf '%s' "$1" | head -c 200)"; fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"; mkdir -p "$PROJ/scripts" "$PROJ/hooks"
cp "$REFRESH" "$PROJ/scripts/"
# Фикстура несёт библиотеки, а не один скрипт: без `hooks/` пересчётчик молча уходил в
# установленную копию `~/.claude/hooks`, и на машине без установки (CI, 12 сентября 2026)
# 16 ног краснели с «нет hooks/backlog-lib.sh» — зелёными их держала машина автора.
cp "$ROOT/hooks/backlog-lib.sh" "$ROOT/hooks/state-lock-lib.sh" "$PROJ/hooks/"

cat > "$PROJ/BACKLOG.md" <<'BL'
# Долг

**Легенда статусов:** ☐ todo · ◐ in-progress · ☑ done · ⊘ waived

### D300 ☐ Пункт с командой показания

**Дефект.** Что-то накапливается.
**Показание.** `printf %s\\n VAL-ALPHA`
**Последнее показание (2020-01-01).** VAL-STALE

### D301 ☐ Пункт без команды показания

**Дефект.** Тут показание — суждение.
**Последнее показание (2020-01-01).** стало заметно лучше

### D302 ☑ Закрытый пункт с командой

**Показание.** `printf %s\\n VAL-CLOSED-NEW`
**Последнее показание (2020-01-01).** VAL-CLOSED-OLD
BL

run() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "${1:-$PROJ/BACKLOG.md}" \
        | BRR_TRUSTED_ROOT="$PROJ" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# --- T1: показание открытого пункта пересчитано ---
OUT=$(run)
assert_contains "$OUT" "показаний обновлено" "T1: хук сообщил о пересчёте"
assert_contains "$(cat "$PROJ/BACKLOG.md")" "VAL-ALPHA" "T1b: новое значение в файле"
if ! grep -q "VAL-STALE" "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1c]: старое значение осталось"; fi

# --- T2: КОНТРПРИМЕР — пункт без команды не тронут ---
assert_contains "$(cat "$PROJ/BACKLOG.md")" "стало заметно лучше" "T2: показание-суждение сохранено"

# --- T3: КОНТРПРИМЕР — закрытый пункт не тронут (свидетельство на момент закрытия) ---
assert_contains "$(cat "$PROJ/BACKLOG.md")" "VAL-CLOSED-OLD" "T3: закрытый пункт сохранил показание"
# Ищем значение в строке ПОКАЗАНИЯ, а не где угодно: имя значения встречается и в тексте
# команды, и проверка «нет такой подстроки» находила бы её там.
if ! grep -qE "^[ \t]*\*\*Последнее показание.*VAL-CLOSED-NEW" "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3b]: закрытый пункт пересчитан"; fi

# --- T4: повтор без изменений — тишина (иначе хук станет фоном) ---
OUT4=$(run)
assert_empty "$OUT4" "T4: показания свежие — молчание"

# --- T5: КОНТРПРИМЕР — другой файл хук не будит ---
printf 'x\n' > "$PROJ/OTHER.md"
OUT5=$(run "$PROJ/OTHER.md")
assert_empty "$OUT5" "T5: чужой файл не будит"

# --- T6: КОНТРПРИМЕР — нет скрипта пересчёта → тишина, не падение ---
BARE="$TMP/bare"; mkdir -p "$BARE"
cp "$PROJ/BACKLOG.md" "$BARE/BACKLOG.md"
OUT6=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$BARE/BACKLOG.md" \
       | BRR_TRUSTED_ROOT="$PROJ" bash "$HOOK" 2>&1); RC6=$?
assert_empty "$OUT6" "T6: без скрипта пересчёта — тишина"
[ "$RC6" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6b]: ненулевой код: $RC6"; }

# --- T7: режим --check называет расхождение, не правя файл ---
python3 - "$PROJ/BACKLOG.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
p.write_text(s.replace("**Последнее показание (%s).** VAL-ALPHA" % __import__("datetime").date.today().isoformat(), "**Последнее показание (2020-01-01).** VAL-DRIFTED"))
PY
OUT7=$(BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" --check 2>&1); RC7=$?
assert_contains "$OUT7" "разошлись" "T7: --check назвал расхождение"
[ "$RC7" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7b]: --check не сообщил кодом: $RC7"; }
if grep -q "VAL-DRIFTED" "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7c]: --check изменил файл — режим проверки обязан только смотреть"; fi

# ── D210: показание живёт по границе хода, а не по правке файла ─────────────────
# Повод — вопрос владельца 30 августа 2026, 01:14: «как было 19, так и осталось?». Показание
# устарело через 50 минут после введения пересчёта по правке: мир (журнал исходов) менялся
# каждым ходом, файл — нет. Прежняя фикстура (`printf VAL-ALPHA`) устареть не могла и
# закрепила дефект как норму (case-2026-08-29-fixture-easier-than-world-hides-the-defect).
set_mtime() { python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"; }
get_mtime() { python3 -c "import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))" "$1"; }
T_OLD=$(( $(date -u +%s) - 7200 ))

# --- T8: КОНТРПРИМЕР условия возврата — команда меняет вывод САМА, файл не трогают ---
printf '1\n' > "$PROJ/counter"
python3 - "$PROJ/BACKLOG.md" "$PROJ/counter" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s += "\n### D303 ☐ Пункт, чей мир движется\n\n**Показание.** `cat %s`\n" % sys.argv[2]
p.write_text(s)
PY
BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" run >/dev/null 2>&1
printf '2\n' > "$PROJ/counter"          # мир изменился; BACKLOG.md — нет
OUT8=$(BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" --check 2>&1); RC8=$?
assert_contains "$OUT8" "D303: в файле «1», в мире «2»" "T8: --check назвал файл и мир"
[ "$RC8" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8b]: устаревание без правки файла не замечено: $RC8"; }

# --- T9: пересчёт на границе хода СОХРАНЯЕТ mtime — сверщик исхода не примет его за запись агента ---
# Фикстуре ставится старое mtime: без этого запись и проверка укладываются в одну секунду, и
# мутация «убрать os.utime» проходила бы зелёной.
set_mtime "$PROJ/BACKLOG.md" "$T_OLD"
BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" run >/dev/null 2>&1
assert_contains "$(grep -A3 'D303' "$PROJ/BACKLOG.md")" "Последнее показание" "T9: показание записано"
assert_contains "$(grep -A3 'D303' "$PROJ/BACKLOG.md" | grep 'Последнее показание')" "** 2" "T9b: значение — из мира"
[ "$(get_mtime "$PROJ/BACKLOG.md")" -eq "$T_OLD" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T9c]: пересчёт сдвинул mtime — сверщик исхода счёл бы это записью агента"; }

# --- T9d: сравнение по ЗНАЧЕНИЮ — перенос даты через полночь не делает показание устаревшим ---
python3 - "$PROJ/BACKLOG.md" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = re.sub(r'\*\*Последнее показание \([0-9-]+\)\.\*\* 2', '**Последнее показание (2020-01-01).** 2', s)
p.write_text(s)
PY
OUT9=$(BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" --check 2>&1 | grep 'D303' || true)
assert_empty "$OUT9" "T9d: та же величина под старой датой — не расхождение"

# --- T10: чтение устаревшего показания — посчитано и названо, файл не тронут ---
printf '3\n' > "$PROJ/counter"
S10="$TMP/state10"; mkdir -p "$S10"
BEFORE10=$(cat "$PROJ/BACKLOG.md")
OUT10=$(printf '{"session_id":"rd10","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$PROJ/BACKLOG.md" \
        | STATE_DIR="$S10" BRR_TRUSTED_ROOT="$PROJ" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
assert_contains "$OUT10" "в мире «3»" "T10: при чтении названо значение мира"
J10="$S10/backlog-stale-read-rd10.jsonl"
if [ -f "$J10" ] && [ "$(jq -r 'select(.item=="D303") | .world' "$J10" 2>/dev/null | tail -1)" = "3" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T10b]: устаревшее чтение не легло в журнал: $(cat "$J10" 2>/dev/null)"; fi
[ "$(cat "$PROJ/BACKLOG.md")" = "$BEFORE10" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T10c]: чтение изменило файл — сверка обязана только смотреть"; }

# --- T11: КОНТРПРИМЕР — свежее показание при чтении: тишина, журнал не растёт ---
BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" run >/dev/null 2>&1
N11_BEFORE=$(grep -c '' "$J10" 2>/dev/null || printf 0)
OUT11=$(printf '{"session_id":"rd10","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$PROJ/BACKLOG.md" \
        | STATE_DIR="$S10" BRR_TRUSTED_ROOT="$PROJ" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT11" "T11: свежее показание — молчание"
[ "$(grep -c '' "$J10" 2>/dev/null || printf 0)" -eq "$N11_BEFORE" ] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T11b]: журнал устаревших чтений вырос на свежем показании"; }

# --- T12: замер stale-reads называет число и сообщает находку кодом ---
STALE="$ROOT/scripts/backlog-stale-reads.sh"
[ -f "$STALE" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T12]: нет $STALE"; }
OUT12=$(STATE_DIR="$S10" bash "$STALE" 2>&1); RC12=$?
assert_contains "$OUT12" "устаревших чтений: 1" "T12b: замер посчитал одно чтение"
[ "$RC12" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T12c]: находка не сообщена кодом: $RC12"; }
EMPTY12="$TMP/empty12"; mkdir -p "$EMPTY12"
OUT12b=$(STATE_DIR="$EMPTY12" bash "$STALE" 2>&1); RC12b=$?
assert_contains "$OUT12b" "устаревших чтений: 0" "T12d: пустое состояние — ноль"
[ "$RC12b" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T12e]: ноль сообщён как находка"; }
grep -q '^stale-reads	' "$ROOT/scripts/measurements.tsv" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T12f]: замера stale-reads нет в реестре — число держится на памяти"; }

# --- T13: граница хода — пересчёт стоит в session-collector ПОСЛЕ архиватора ---
# Два писателя одного файла на одном событии без порядка — гонка; порядок держится тем, что
# оба вызова живут в одном хуке, и этот тест ловит вынос пересчёта в отдельную регистрацию.
SC="$HOOKS/session-collector.sh"
L_ARCH=$(grep -n 'bash "\$BACKLOG_ARCHIVER" run' "$SC" | head -1 | cut -d: -f1)
L_REFR=$(grep -n '_bl_refresh_readings "\$BACKLOG_FILE"' "$SC" | head -1 | cut -d: -f1)
if [ -n "$L_ARCH" ] && [ -n "$L_REFR" ] && [ "$L_REFR" -gt "$L_ARCH" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T13]: пересчёт показаний на Stop не стоит после архиватора (arch=$L_ARCH refresh=$L_REFR)"; fi

# --- T13 (D244): корень не объявлен доверенным — хук молчит и ничего не исполняет ---
# Без этой проверки граница доверия держалась бы на слове: все остальные случаи ставят
# BRR_TRUSTED_ROOT и потому не отличили бы работающий страж от снятого.
MARK="$TMP/T13-EXECUTED"
cat >> "$PROJ/BACKLOG.md" <<BL

- ☐ **D998** Пункт с исполнимым показанием.
**Показание.** \`touch $MARK; printf %s\\n VAL-T13\`
**Последнее показание (2020-01-01).** VAL-OLD
BL
OUT13=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$PROJ/BACKLOG.md" \
        | bash "$HOOK" 2>/dev/null)
if [ -f "$MARK" ]; then FAIL=$((FAIL+1)); echo "FAIL [T13]: команда недоверенного корня исполнилась"
else PASS=$((PASS+1)); fi
if [ -z "$OUT13" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T13b]: недоверенный корень дал вывод: $OUT13"; fi

# --- T6: текст ошибки не выдаётся за показание ---
# `r.stdout or r.stderr` брал stderr, когда stdout пуст, и строка «Последнее показание»
# получала вид настоящего замера. Признак составной: ненулевой код И пустой stdout —
# сам по себе ненулевой код поводом не является, команда показания законно возвращает 1,
# когда находит (`injection-outcome.sh` при доле выше порога).
cat > "$PROJ/BACKLOG.md" <<'BLX'
# BACKLOG

- ◐ **D910** Падающая команда показания.
  **Показание.** `bash -c 'echo "ошибка чтения" >&2; exit 3'`

- ◐ **D911** Законный ненулевой код с выводом.
  **Показание.** `bash -c 'echo "доля 52%"; exit 1'`
BLX
run >/dev/null 2>&1
if grep -q 'Последнее показание.*команда упала (rc=3)' "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6-stderr]: текст ошибки выдан за показание"; fi
if grep -q 'Последнее показание.*доля 52%' "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6-rc1]: законный ненулевой код с выводом потерян"; fi

# --- T7-T9: РОД J — предмет есть правка файла, а не имя инструмента ---
# Замер по корпусу 209 расшифровок: правок BACKLOG.md 233, через оболочку 50 (21,5%).
# На них хук не вызывался, и молчание было неотличимо от «пересчитывать нечего».
# Признак правки — МИР (файл новее отметки), а не перечень форм записи в команде.
run_bash() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" \
        | STATE_DIR="$STATE_J" BRR_TRUSTED_ROOT="$PROJ" bash "$HOOK" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
STATE_J="$TMP/state-j"; mkdir -p "$STATE_J"

# T7: команда БЕЗ упоминания бэклога — дешёвый выход, ни stat, ни пересчёта.
assert_empty "$(run_bash 'ls -la')" "T7: команда не о бэклоге — тишина"

# T8: команда ПРАВИТ бэклог через оболочку — пересчёт обязан состояться.
printf '\n### D399 ☐ Пункт, дописанный оболочкой\n\n**Показание.** `printf %%s VAL-SHELL`\n**Последнее показание (2020-01-01).** VAL-OLD-SHELL\n' >> "$PROJ/BACKLOG.md"
OUT8=$(run_bash 'cat >> BACKLOG.md <<EOF ... EOF')
assert_contains "$OUT8" "показаний обновлено" "T8: правка оболочкой разбудила пересчёт"
assert_contains "$(cat "$PROJ/BACKLOG.md")" "VAL-SHELL" "T8b: показание пересчитано по миру"

# T9: КОНТРПРИМЕР — команда лишь УПОМИНАЕТ бэклог, файл не менялся: пересчётчик НЕ ЗВАН.
# Первая редакция этой ноги проверяла тишину вывода и была ложно-зелёной: при снятом
# признаке правки хук всё равно молчал — пересчёт просто не находил, что обновлять, и
# выходил на проверке текста. Мутация «признак снят» проходила её насквозь (39/39).
# Предмет здесь — ФАКТ ОБРАЩЕНИЯ к пересчётчику, и ловится он шпионом, а не выводом.
# Предмет ноги — РЕЖИМ вызова, а не факт вызова. Признак чтения инвертирован: команда,
# упомянувшая бэклог и не изменившая его, читала его — значит обязана идти в СВЕРКУ
# (`--check`, без записи), а не в ПЕРЕСЧЁТ (`run`). Первая редакция требовала, чтобы
# пересчётчик не звался вовсе, и стала неверной, когда чтение из оболочки было покрыто:
# 89,4% чтений бэклога идут мимо инструмента Read (565 чтений корпуса, Read лишь 60).
SPY_LOG="$TMP/refresh-mode.log"
cp "$PROJ/scripts/backlog-refresh-readings.sh" "$TMP/refresh-real.sh"
cat > "$PROJ/scripts/backlog-refresh-readings.sh" <<SPY
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SPY_LOG"
exec bash "$TMP/refresh-real.sh" "\$@"
SPY
: > "$SPY_LOG"
OUT9=$(run_bash 'grep -n D399 BACKLOG.md')
if grep -q -- '--check' "$SPY_LOG" && ! grep -qx 'run' "$SPY_LOG"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T9]: упоминание без правки обязано идти в сверку, а не в пересчёт; режимы: $(tr '\n' ' ' < "$SPY_LOG")"
fi

# T10: правка через оболочку обязана идти в ПЕРЕСЧЁТ — вторая половина того же признака.
: > "$SPY_LOG"
printf '\n### D398 ☐ Второй пункт оболочкой\n\n**Показание.** `printf %%s VAL-SHELL2`\n**Последнее показание (2020-01-01).** VAL-OLD-2\n' >> "$PROJ/BACKLOG.md"
OUT10=$(run_bash 'python3 - <<PY ... BACKLOG.md ... PY')
if grep -qx 'run' "$SPY_LOG"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T10]: правка оболочкой не разбудила пересчёт; режимы: $(tr '\n' ' ' < "$SPY_LOG")"; fi
assert_contains "$(cat "$PROJ/BACKLOG.md")" "VAL-SHELL2" "T10b: показание второго пункта пересчитано"

# T11: сессия в ЧУЖОМ проекте — носитель берётся у НЕГО, бэклог ClaudSoul не трогается.
# Повод — проверка вызовом 11 сентября 2026 (шаг «братья корня» к D395): у Bash-ветки цели
# правки в payload нет, и адрес стоял константой ClaudSoul. Сессия в чужом проекте правила
# СВОЙ BACKLOG.md, а хук пересчитывал показания ClaudSoul (то есть ПИСАЛ в файл, которого
# сессия не касалась) и объявлял ходу «бэклог изменился», хотя тот не менялся. У соседа
# того же предмета класс был закрыт (`session-collector.sh:533-540`), сюда правка не дошла.
# Нога держит ФАКТ ОБРАЩЕНИЯ шпионом: тишина вывода тут ложно-зелёная — пересчёт мог просто
# не найти, что обновлять. Отдельного «а не пуст ли шпион вообще» не нужно: T8/T10 выше
# уже показали его непустым на том же прогоне.
FOREIGN="$TMP/foreign"; mkdir -p "$FOREIGN"
printf '# BACKLOG\n\n### P1 \u2610 Пункт чужого проекта\n\n**Показание.** `printf %%s VAL-FOREIGN`\n**Последнее показание (2020-01-01).** VAL-OLD-F\n' > "$FOREIGN/BACKLOG.md"
: > "$SPY_LOG"
printf '{"tool_name":"Bash","tool_input":{"command":"sed -i BACKLOG.md"},"cwd":"%s"}' "$FOREIGN" \
    | STATE_DIR="$STATE_J" BRR_TRUSTED_ROOT="$PROJ" CLAUDSOUL_ROOT="$PROJ" bash "$HOOK" >/dev/null 2>&1
if [ ! -s "$SPY_LOG" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T11]: сессия в чужом проекте разбудила пересчётчик ClaudSoul; режимы: $(tr '\n' ' ' < "$SPY_LOG")"; fi

cp "$TMP/refresh-real.sh" "$PROJ/scripts/backlog-refresh-readings.sh"

# --- T14 (D355): команда, не уложившаяся в срок, пишется маркером, а не текстом исключения ---
cat > "$PROJ/BACKLOG.md" <<'BLT'
# BACKLOG

- ◐ **D920** Медленная команда показания.
  **Показание.** `sleep 3; echo late`
BLT
READING_TIMEOUT=1 BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$PROJ/scripts/backlog-refresh-readings.sh" run >/dev/null 2>&1
if grep -q 'Последнее показание.*НЕ ИЗМЕРЕНО: команда не уложилась в срок 1 с' "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T14]: срок не назван маркером: $(grep 'Последнее показание' "$PROJ/BACKLOG.md")"; fi
if grep -q "Command '\[" "$PROJ/BACKLOG.md"; then FAIL=$((FAIL+1)); echo "FAIL [T14b]: текст исключения попал в файл"; else PASS=$((PASS+1)); fi

# --- T15 (D355): пересчёт не может удалить ни строки вне показаний — мутант, глотающий хвост блока,
# получает отказ и файл остаётся байт в байт; контроль — настоящий писатель тот же хвост сохраняет ---
cat > "$PROJ/BACKLOG.md" <<'BLM'
# BACKLOG

- ◐ **D930** Пункт с хвостом после показания.
  **Показание.** `printf %s\\n NEW`
  **Последнее показание (2020-01-01).** OLD
  **Проверка возврата:** строка после показания — та, что съедалась.

- ◐ **D931** Сосед, который однажды пропал.
  **Дефект.** целиком внутри хвоста.
BLM
cp "$PROJ/BACKLOG.md" "$TMP/before.md"
MUT="$TMP/mutant.sh"; sed 's/+ line + block\[old.end():\])/+ line)/' "$PROJ/scripts/backlog-refresh-readings.sh" > "$MUT"
grep -q '+ line)' "$MUT" || { FAIL=$((FAIL+1)); echo "FAIL [T15-mut]: мутант не собрался — якорь замены не найден"; }
ERR15=$(BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$MUT" run 2>&1 >/dev/null); RC15=$?
if [ "$RC15" -eq 2 ] && grep -q 'ОТКАЗ: пересчёт изменил бы строки вне показаний' <<< "$ERR15"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T15a]: мутант с проглоченным хвостом не получил отказа (rc $RC15): $ERR15"; fi
if cmp -s "$TMP/before.md" "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T15b]: после отказа файл изменён"; fi
BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$PROJ/scripts/backlog-refresh-readings.sh" run >/dev/null 2>&1; RC15c=$?
if [ "$RC15c" -eq 0 ] && grep -q 'Последнее показание.*NEW' "$PROJ/BACKLOG.md" \
   && grep -q 'строка после показания — та, что съедалась' "$PROJ/BACKLOG.md" && grep -q 'D931' "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T15c]: контроль — настоящий писатель (rc $RC15c) не сохранил хвост или соседа"; fi

echo "backlog reading refresh: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
