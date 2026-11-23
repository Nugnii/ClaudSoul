#!/usr/bin/env bash
# СУДИТ: hooks/backlog-reading-refresh.sh
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
#   · нет скрипта пересчёта — тишина, а не падение;
#   · правка, внесённая за время пересчёта, не затирается: пересчётчик отказывает кодом 3, хук
#     называет отказ вслух, повтор идёт по свежему файлу (T16, D1000).
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HOOKS/.." && pwd)"
HOOK="$HOOKS/backlog-reading-refresh.sh"
REFRESH="$ROOT/scripts/backlog-refresh-readings.sh"
for f in "$HOOK" "$REFRESH"; do [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
# Ноги T1–T16 судят СОДЕРЖАНИЕ прогона, и хук исполняет его в своём вызове; фоновое исполнение по
# умолчанию (D1014) судят ноги T17–T22, снимая переменную у своих вызовов.
export BRR_FOREGROUND=1

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
# 16 ног краснели с «нет hooks/backlog-lib.sh» — зелёными их держала машина автора. То же — у
# правила исполнения «Показания» (`hooks/lib/bounded_run.py`, D1199): его пересчётчик берёт из своего дерева.
cp "$ROOT/hooks/backlog-lib.sh" "$ROOT/hooks/state-lock-lib.sh" "$PROJ/hooks/"
mkdir -p "$PROJ/hooks/lib" && cp "$ROOT/hooks/lib/bounded_run.py" "$ROOT/hooks/lib/backlog_cmd.py" "$PROJ/hooks/lib/"

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
BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" run >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_reading_refresh.sh:$LINENO" >&2; exit 1; }
printf '2\n' > "$PROJ/counter"          # мир изменился; BACKLOG.md — нет
OUT8=$(BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" --check 2>&1); RC8=$?
assert_contains "$OUT8" "D303: в файле «1», в мире «2»" "T8: --check назвал файл и мир"
[ "$RC8" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T8b]: устаревание без правки файла не замечено: $RC8"; }

# --- T9: пересчёт на границе хода СОХРАНЯЕТ mtime — сверщик исхода не примет его за запись агента ---
# Фикстуре ставится старое mtime: без этого запись и проверка укладываются в одну секунду, и
# мутация «убрать os.utime» проходила бы зелёной.
set_mtime "$PROJ/BACKLOG.md" "$T_OLD"
BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" run >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_reading_refresh.sh:$LINENO" >&2; exit 1; }
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
BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$REFRESH" run >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_reading_refresh.sh:$LINENO" >&2; exit 1; }
N11_BEFORE=$(grep -c '' "$J10" 2>/dev/null); N11_BEFORE=${N11_BEFORE:-0}
OUT11=$(printf '{"session_id":"rd10","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$PROJ/BACKLOG.md" \
        | STATE_DIR="$S10" BRR_TRUSTED_ROOT="$PROJ" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT11" "T11: свежее показание — молчание"
_n11=$(grep -c '' "$J10" 2>/dev/null); [ "${_n11:-0}" -eq "$N11_BEFORE" ] && PASS=$((PASS+1)) \
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
READING_TIMEOUT=1 BACKLOG_FILE="$PROJ/BACKLOG.md" CLAUDSOUL_REPO="$PROJ" bash "$PROJ/scripts/backlog-refresh-readings.sh" run >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_reading_refresh.sh:$LINENO" >&2; exit 1; }
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
# Мутант лежит в дереве фикстуры: правило исполнения «Показания» пересчёт берёт из своего дерева (D1199).
MUT="$PROJ/scripts/refresh-mutant.sh"; sed 's/+ line + block\[old.end():\])/+ line)/' "$PROJ/scripts/backlog-refresh-readings.sh" > "$MUT"
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

# --- T16 (D1000, 17 октября 2026): правка, внесённая за время пересчёта, не затирается ---
# Сборщик конца хода идёт фоном, и агент следующего хода правит BACKLOG.md, пока пересчётчик
# держит прочитанную в начале копию и исполняет команды показаний (до 120 с каждая); замок его
# ждёт лишь 2 с, а инструмент Edit замка не берёт. Правку во время пересчёта ведёт детерминированно
# сама команда показания: один раз (отметка `ran`) дописывает в BACKLOG.md новый открытый пункт —
# ровно то, что сделал бы агент. Команда исполняется из корня фикстуры, пути относительные.
# Ноги судят ПОВЕДЕНИЕ: код выхода, что сказано, что в файле. Без параллельной правки — прежнее
# поведение (T1, T15c выше), здесь же контроль повтором.
RACE="$TMP/race"; mkdir -p "$RACE/scripts" "$RACE/hooks"
cp "$REFRESH" "$RACE/scripts/"
cp "$ROOT/hooks/backlog-lib.sh" "$ROOT/hooks/state-lock-lib.sh" "$RACE/hooks/"
mkdir -p "$RACE/hooks/lib" && cp "$ROOT/hooks/lib/bounded_run.py" "$ROOT/hooks/lib/backlog_cmd.py" "$RACE/hooks/lib/"
# Дописанный пункт ищется ЗАГОЛОВКОМ В НАЧАЛЕ СТРОКИ: слово D941 стоит и в тексте самой команды
# показания, и поиск подстроки находил бы его там даже после затирания (мутант без сверки это
# показал: ноги с подстрокой оставались зелёными).
_t16_item_kept() { grep -qE '^- ☐ \*\*D941\*\* ' "$RACE/BACKLOG.md"; }
_t16_fixture() {
    rm -f "$RACE/ran"
    cat > "$RACE/BACKLOG.md" <<'BLR'
# BACKLOG

- ☐ **D940** Пункт, чья команда показания дописывает бэклог (правка во время пересчёта).
  **Показание.** `[ -e ran ] || { : > ran; printf '\n- ☐ **D941** дописан во время пересчёта\n' >> BACKLOG.md; }; echo VAL-NEW`
  **Последнее показание (2020-01-01).** VAL-OLD
BLR
}
_t16_fixture
ERR16=$(BACKLOG_FILE="$RACE/BACKLOG.md" CLAUDSOUL_REPO="$RACE" bash "$RACE/scripts/backlog-refresh-readings.sh" run 2>&1 >/dev/null); RC16=$?
[ "$RC16" -eq 3 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T16a]: пересчёт по устаревшей копии вышел кодом $RC16 вместо 3: $ERR16"; }
assert_contains "$ERR16" "ОТКАЗ: BACKLOG.md изменился за время пересчёта" "T16b: отказ назван"
_t16_item_kept && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T16c]: правка, внесённая во время пересчёта, затёрта — дописанного пункта в файле нет"; }
assert_contains "$(cat "$RACE/BACKLOG.md")" "VAL-OLD" "T16d: показание не записано по устаревшей копии"
if ! grep -qE "^[ \t]*\*\*Последнее показание.*VAL-NEW" "$RACE/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T16e]: после отказа в файле новое показание"; fi
# Повтор идёт по свежему файлу: показание записано, дописанная правка осталась.
BACKLOG_FILE="$RACE/BACKLOG.md" CLAUDSOUL_REPO="$RACE" bash "$RACE/scripts/backlog-refresh-readings.sh" run >/dev/null 2>&1; RC16b=$?
[ "$RC16b" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T16f]: повтор без параллельной правки вышел кодом $RC16b вместо 0"; }
if grep -qE "^[ \t]*\*\*Последнее показание.*VAL-NEW" "$RACE/BACKLOG.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T16g]: повтор не записал показание"; fi
_t16_item_kept && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T16h]: повтор затёр дописанную правку — пункта в файле нет"; }
# --check правку во время прогона не судит: он ничего не пишет, отказывать нечему.
_t16_fixture
BACKLOG_FILE="$RACE/BACKLOG.md" CLAUDSOUL_REPO="$RACE" bash "$RACE/scripts/backlog-refresh-readings.sh" --check >/dev/null 2>&1; RC16c=$?
[ "$RC16c" -eq 1 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T16i]: --check при устаревшем показании вышел кодом $RC16c вместо 1"; }

# --- T16 (хук): код 3 пересчётчика не молчит — агент узнаёт, что показания не пересчитаны ---
# До D1000 код терялся в `| head -5`, а тишина хука читалась как «свежо».
_t16_fixture
S16="$TMP/state16"; mkdir -p "$S16"
OUT16=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$RACE/BACKLOG.md" \
        | STATE_DIR="$S16" BRR_TRUSTED_ROOT="$RACE" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "$OUT16" "Показания НЕ пересчитаны" "T16j: хук назвал отказ пересчёта"
_t16_item_kept && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T16k]: через хук дописанная правка затёрта — пункта в файле нет"; }
if [ ! -s "$S16/backlog-reading-refresh.sum" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T16l]: после отказа поставлена отметка пересчёта — следующая Bash-команда пошла бы в сверку, а не в пересчёт"; fi
# Следующий вызов хука идёт по свежему файлу: пересчёт состоялся, о нём сказано обычным словом.
OUT16b=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$RACE/BACKLOG.md" \
         | STATE_DIR="$S16" BRR_TRUSTED_ROOT="$RACE" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "$OUT16b" "показаний обновлено" "T16m: повторный вызов хука пересчитал показания"

# --- T16n: правка в ОЖИДАНИИ ЗАМКА — отказ кодом 3, а не перезапись (D1000, противник 18 октября 2026) ---
# Снимок без заборов брался до замка, а опора сверки — после него (замок ждёт до 2 с): правка в это
# окно проходила сверку, строки свежего текста размечались по старому снимку, и чужая строка
# затиралась. Подменная библиотека замка дописывает заметку агента ровно в это окно.
R16n="$TMP/t16n"; mkdir -p "$R16n/scripts" "$R16n/hooks" "$R16n/state"
cp "$REFRESH" "$R16n/scripts/"; cp "$ROOT/hooks/backlog-lib.sh" "$ROOT/hooks/state-lock-lib.sh" "$R16n/hooks/"
mkdir -p "$R16n/hooks/lib" && cp "$ROOT/hooks/lib/bounded_run.py" "$ROOT/hooks/lib/backlog_cmd.py" "$R16n/hooks/lib/"
printf '%s\n' 'with_lock() {' '    local target="$1"; shift' \
    '    local t; t=$(awk '"'"'NR == 1 { print; print ""; print "Заметка агента, дописанная во время пересчёта."; next } { print }'"'"' "$target")' \
    '    printf "%s\n" "$t" > "$target"' '    "$@"' '}' > "$R16n/lock_edit.sh"
printf '%s\n' '# Долг' '' '**Легенда статусов:** ☐ todo · ◐ in-progress · ☑ done · ⊘ waived' '' \
    '### D300 ☐ Пункт с командой показания' '' '**Показание.** `printf %s\\n VAL-ALPHA`' \
    '**Последнее показание (2020-01-01).** VAL-STALE' '' '### D301 ☐ Пункт без команды показания' '' \
    '**Последнее показание (2020-01-01).** стало заметно лучше' > "$R16n/BACKLOG.md"
OUT16n=$(cd "$R16n" && STATE_LOCK_LIB="$R16n/lock_edit.sh" STATE_DIR="$R16n/state" BACKLOG_FILE="$R16n/BACKLOG.md" \
    CLAUDSOUL_REPO="$R16n" bash "$R16n/scripts/backlog-refresh-readings.sh" run 2>&1); RC16n=$?
if [ "$RC16n" -eq 3 ] && grep -q 'Заметка агента' "$R16n/BACKLOG.md" \
   && grep -q 'стало заметно лучше' "$R16n/BACKLOG.md" && [ "$(grep -c 'Последнее показание' "$R16n/BACKLOG.md")" -eq 2 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T16n]: правка в ожидании замка — код ${RC16n} (ждали 3), вывод: ${OUT16n:0:160}"
fi

# --- T17–T27 (D1014, 20 октября 2026): без BRR_FOREGROUND сверка и пересчёт идут ФОНОМ ---
# Хук держал ход, пока исполнялись все команды показаний: в живой сессии 67–239 с на одно касание.
# Пересчётчик-заглушка спит STUB_SLEEP секунд (по умолчанию 4) и пишет начало («s») и конец («e»)
# каждого запуска: синхронный хук вернулся бы не раньше чем через 4 с, фоновый ждёт не дольше секунды.
_bg_stub() {  # _bg_stub <дерево> <слово мира> [вывод пересчёта] — дерево с пересчётчиком-заглушкой
    mkdir -p "$1/scripts" "$1/state"
    printf '# Долг\n' > "$1/BACKLOG.md"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "s %s\n" "$1" >> "$CLAUDSOUL_REPO/calls"' 'sleep "${STUB_SLEEP:-4}"' \
        'printf "e %s\n" "$1" >> "$CLAUDSOUL_REPO/calls"' \
        "case \"\$1\" in --check) echo \"D300: в файле VAL-OLD, в мире $2\"; exit 1 ;; run) echo \"${3:-показаний обновлено: 1}\" ;; esac" \
        > "$1/scripts/backlog-refresh-readings.sh"
}
_now() { python3 -c 'import time; print("%.2f" % time.time())'; }
bg_touch() {  # bg_touch <инструмент> <файл вывода> [дерево] — касание фоновым хуком; длительность в BG_SECS
    local d="${3:-$BG}" t0; t0=$(_now)
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"session_id":"bg"}' "$1" "$d/BACKLOG.md" \
        | env -u BRR_FOREGROUND STATE_DIR="$d/state" BRR_TRUSTED_ROOT="$d" bash "$HOOK" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""' > "$2" 2>/dev/null
    BG_SECS=$(python3 -c "print('%.2f' % ($(_now) - $t0))")
}
bg_fast() { python3 -c "import sys; sys.exit(0 if float('$BG_SECS') < 2.5 else 1)"; }
_any() { local f; for f in "$@"; do [ -e "$f" ] && return 0; done; return 1; }   # без nullglob: несовпавший шаблон — сам себе путь
bg_wait() {  # простой — ни замка полосы, ни отметки повтора: между снятием и повтором отметка лежит
    local d="${1:-$BG/state}" p="${2:-}" i
    for i in $(seq 1 150); do
        _any "$d"/*"$p"*.lock "$d"/*"$p"*.again || return 0
        sleep 0.2
    done
    return 1
}
bg_starts() { grep -c "^s $1\$" "${2:-$BG}/calls" 2>/dev/null || true; }
bg_overlap() {  # сколько прогонов полосы шли одновременно в худший момент
    awk -v l="$1" '$2 == l { d += ($1 == "s") ? 1 : -1; if (d > m) m = d } END { print m + 0 }' "${2:-$BG}/calls" 2>/dev/null
}
ok_or() { if [ "$1" = 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: $3"; fi; }

BG="$TMP/bg"; _bg_stub "$BG" VAL-NEW
bg_touch Read "$BG/o1"
bg_fast; ok_or $? T17 "хук ждал сверку ${BG_SECS} с"
assert_empty "$(cat "$BG/o1")" "T17b: долгая сверка — итога в том же вызове нет"
bg_touch Read "$BG/o2"   # сверка первого касания ещё идёт
bg_wait; ok_or $? T18w "фоновый прогон не кончился за 30 с"
[ "$(bg_overlap --check)" = 1 ]; ok_or $? T18 "две сверки шли одновременно: $(bg_overlap --check)"
[ "$(bg_starts --check)" = 2 ]; ok_or $? T18b "касание во время сверки не дало ей повтора: запусков $(bg_starts --check)"
bg_touch Read "$BG/o3"
assert_contains "$(cat "$BG/o3")" "VAL-NEW" "T19: итог прошлого прогона пришёл на следующем касании"
assert_contains "$(cat "$BG/o3")" "фоновый прогон закончен" "T19b: названо, что итог из фона"
bg_touch Read "$BG/o3b"  # сразу: сверка от o3 идёт, а итог прошлой уже забран
assert_empty "$(cat "$BG/o3b")" "T19c: доставленный итог не приходит второй раз"
bg_wait
bg_touch Edit "$BG/o4"
bg_fast; ok_or $? T20 "хук ждал пересчёт ${BG_SECS} с"
bg_wait
bg_touch Read "$BG/o5"
assert_contains "$(cat "$BG/o5")" "показания пересчитаны" "T20b: итог пересчёта по правке пришёл на следующем касании"
bg_wait
# Замок мёртвого владельца — след прерванного прогона: его срывают, а не ждут вечно (живость судит
# библиотека замка по PID владельца).
sh -c 'exit 0' & DEAD=$!; wait "$DEAD" 2>/dev/null
mkdir -p "$BG/state/backlog-reading-refresh-check.lock"
printf '%s мёртвый\n' "$DEAD" > "$BG/state/backlog-reading-refresh-check.lock/owner"
N21=$(bg_starts --check); bg_touch Read "$BG/o6"; bg_wait
[ "$(bg_starts --check)" = $((N21 + 1)) ]; ok_or $? T21 "замок мёртвого владельца не сорван — сверка не пошла"
# Прогон переживает снятие группы процессов хука: так поступает зовущий по сроку, и без своей группы
# (`set -m`) пересчёт умирал бы вместе с хуком, а итог не приходил бы никогда.
if command -v perl >/dev/null 2>&1; then
    mv "$BG/state/backlog-reading-refresh-check.msg" "$BG/state/before22.msg" 2>/dev/null || true  # сообщения прошлой ноги может не быть (D1219)
    printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"session_id":"bg"}' "$BG/BACKLOG.md" \
        | perl -e '$p = fork; unless ($p) { setpgrp(0, 0); exec @ARGV } waitpid $p, 0; kill "KILL", -$p' \
            env -u BRR_FOREGROUND STATE_DIR="$BG/state" BRR_TRUSTED_ROOT="$BG" bash "$HOOK" >/dev/null 2>&1 || true  # код конвейера — код perl-обёртки, он 0 при любом исходе хука; итог читает T22 (D1261, скептик M3)
    bg_wait
    [ -s "$BG/state/backlog-reading-refresh-check.msg" ]; ok_or $? T22 "прогон умер вместе с группой хука — итога нет"
else
    echo "SKIP [T22]: нет perl — выживание прогона при снятии группы хука не проверено"
fi
# Правка во время идущего пересчёта не теряется: она ставит отметку, и пересчёт повторяется после.
N23=$(bg_starts run)
bg_touch Edit "$BG/o7"   # пересчёт пошёл
bg_touch Edit "$BG/o8"   # правка во время пересчёта
bg_wait
[ "$(bg_starts run)" = $((N23 + 2)) ]; ok_or $? T23 "правка во время пересчёта осталась без пересчёта: запусков $(( $(bg_starts run) - N23 ))"
[ "$(bg_overlap run)" = 1 ]; ok_or $? T23b "два пересчёта шли одновременно"
# Отметка — сумма того, что пересчёт обработал: правку, внесённую за время прогона, которому менять
# было нечего, она не накрывает, и следующая команда о бэклоге идёт в пересчёт, а не в сверку.
BG2="$TMP/bg2"; _bg_stub "$BG2" VAL-X "пересчитывать нечего"
bg_touch Edit "$BG2/o1" "$BG2"
printf 'правка во время пересчёта\n' >> "$BG2/BACKLOG.md"
bg_wait "$BG2/state"
N24=$(bg_starts run "$BG2")
printf '{"tool_name":"Bash","tool_input":{"command":"grep x %s/BACKLOG.md"},"session_id":"bg","cwd":"%s"}' "$BG2" "$BG2" \
    | env -u BRR_FOREGROUND STATE_DIR="$BG2/state" BRR_TRUSTED_ROOT="$BG2" bash "$HOOK" >/dev/null 2>&1
bg_wait "$BG2/state"
[ "$(bg_starts run "$BG2")" = $((N24 + 1)) ]; ok_or $? T24 "отметка накрыла правку, которой пересчёт не видел, — команда ушла в сверку"
# Фикстуры под временным корнем с живым каталогом по умолчанию (ветка D1011) полос не делят: имена
# занятости и итога несут ключ пути, как отметка.
FA="$TMP/fa"; FB="$TMP/fb"; _bg_stub "$FA" МИР-A; _bg_stub "$FB" МИР-B
TD=$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || TD=$(cd /tmp && pwd -P)
KA=$(printf '%s' "$FA/BACKLOG.md" | cksum | awk '{print $1}'); KB=$(printf '%s' "$FB/BACKLOG.md" | cksum | awk '{print $1}')
fx_touch() {  # fx_touch <дерево> <файл вывода> — касание при живом каталоге песочного HOME
    printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"session_id":"fx"}' "$1/BACKLOG.md" \
        | env -u BRR_FOREGROUND -u STATE_DIR HOME="$TMP/home" BRR_TRUSTED_ROOT="$1" bash "$HOOK" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""' > "$2" 2>/dev/null
}
fx_touch "$FA" "$TMP/fa.o1"
fx_touch "$FB" "$TMP/fb.o1"   # сверка B обязана пойти своя, а не встать за занятостью A
bg_wait "$TD" "-$KA-"; bg_wait "$TD" "-$KB-"
[ "$(bg_starts --check "$FB")" = 1 ]; ok_or $? T25 "сверка фикстуры B не пошла — полоса занята фикстурой A"
fx_touch "$FB" "$TMP/fb.o2"
assert_contains "$(cat "$TMP/fb.o2")" "МИР-B" "T25b: фикстура B получила свой итог"
if ! grep -q "МИР-A" "$TMP/fb.o2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T25c]: фикстура B получила итог фикстуры A"; fi
bg_wait "$TD" "-$KA-"; bg_wait "$TD" "-$KB-"
# Следы ноги в настоящей временной папке убираются по своим ключам: чужое там не трогается.
rm -f "$TD"/backlog-reading-refresh-"$KA"* "$TD"/backlog-reading-refresh-"$KB"* 2>/dev/null
# Итог старше 30 минут — про мир, которого уже нет: его отбрасывают, а не показывают как свежий.
printf 'СТАРЫЙ ИТОГ\n' > "$BG/state/backlog-reading-refresh-run.msg"
touch -t 202001010000 "$BG/state/backlog-reading-refresh-run.msg"
bg_touch Read "$BG/o9"
if ! grep -q 'СТАРЫЙ ИТОГ' "$BG/o9"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T26]: итог 2020 года показан как свежий"; fi
[ ! -e "$BG/state/backlog-reading-refresh-run.msg" ]; ok_or $? T26b "залежавшийся итог не убран"
bg_wait
# Быстрая сверка отвечает в ТОМ ЖЕ вызове, как до D1014: фон не откладывает то, что готово за секунду.
BG3="$TMP/bg3"; _bg_stub "$BG3" VAL-FAST
export STUB_SLEEP=0
bg_touch Read "$BG3/o1" "$BG3"
unset STUB_SLEEP
assert_contains "$(cat "$BG3/o1")" "VAL-FAST" "T27: быстрая сверка — итог в том же вызове"
bg_wait "$BG3/state"
# Чистая сверка отменяет недоставленное «устарело»: иначе агент получил бы вердикт, опровергнутый миром.
BG6="$TMP/bg6"; _bg_stub "$BG6" VAL-X
sed -i.bak 's/exit 1 ;;/exit 0 ;;/' "$BG6/scripts/backlog-refresh-readings.sh"
printf 'УСТАРЕЛО-ПРЕЖНЕЕ\n' > "$BG6/state/backlog-reading-refresh-check.msg"
export STUB_SLEEP=0
# Чистая сверка — прямым вызовом режима прогона, до конца: забирающее касание идёт ПОСЛЕ неё, и под
# нагрузкой нога не зависит от того, уложилась ли сверка в секунду ожидания.
printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"session_id":"bg"}' "$BG6/BACKLOG.md" \
    | env -u BRR_FOREGROUND BRR_JOB=check STATE_DIR="$BG6/state" BRR_TRUSTED_ROOT="$BG6" bash "$HOOK" >/dev/null 2>&1
bg_touch Read "$BG6/o1" "$BG6"
unset STUB_SLEEP
bg_wait "$BG6/state"
if ! grep -q 'УСТАРЕЛО-ПРЕЖНЕЕ' "$BG6/o1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T28]: чистая сверка не отменила недоставленное «устарело»"; fi
# Файл менялся за время сверки — её вердикт о прошлом тексте не публикуется.
BG7="$TMP/bg7"; _bg_stub "$BG7" VAL-ПРОШЛЫЙ-ТЕКСТ
export STUB_SLEEP=2
bg_touch Read "$BG7/o1" "$BG7"
printf 'правка во время сверки\n' >> "$BG7/BACKLOG.md"
bg_wait "$BG7/state"
bg_touch Read "$BG7/o2" "$BG7"
unset STUB_SLEEP
bg_wait "$BG7/state"
if ! grep -q 'VAL-ПРОШЛЫЙ-ТЕКСТ' "$BG7/o2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T29]: опубликован вердикт сверки о тексте, который за время сверки изменился"; fi
# Bash-чтение во время пересчёта — чтение: оно не ставит повтор пересчёта, а идёт в сверку.
BG8="$TMP/bg8"; _bg_stub "$BG8" VAL-Y
bg_touch Edit "$BG8/o1" "$BG8"
printf '{"tool_name":"Bash","tool_input":{"command":"grep x %s/BACKLOG.md"},"session_id":"bg","cwd":"%s"}' "$BG8" "$BG8" \
    | env -u BRR_FOREGROUND STATE_DIR="$BG8/state" BRR_TRUSTED_ROOT="$BG8" bash "$HOOK" >/dev/null 2>&1
bg_wait "$BG8/state"
[ "$(bg_starts run "$BG8")" = 1 ] && [ "$(bg_starts --check "$BG8")" = 1 ]
ok_or $? T30 "чтение во время пересчёта принято за правку: пересчётов $(bg_starts run "$BG8"), сверок $(bg_starts --check "$BG8")"
# Сумма в замке УБИТОГО пересчёта — не идущий пересчёт: Bash-касание идёт в пересчёт, а не в сверку.
BG9="$TMP/bg9"; _bg_stub "$BG9" VAL-Z
sh -c 'exit 0' & DEAD9=$!; wait "$DEAD9" 2>/dev/null
mkdir -p "$BG9/state/backlog-reading-refresh-run.lock"
printf '%s мёртвый\n' "$DEAD9" > "$BG9/state/backlog-reading-refresh-run.lock/owner"
cksum < "$BG9/BACKLOG.md" | awk '{ printf "%s-%s", $1, $2 }' > "$BG9/state/backlog-reading-refresh-run.lock/sum"
printf '{"tool_name":"Bash","tool_input":{"command":"grep x %s/BACKLOG.md"},"session_id":"bg","cwd":"%s"}' "$BG9" "$BG9" \
    | env -u BRR_FOREGROUND STATE_DIR="$BG9/state" BRR_TRUSTED_ROOT="$BG9" bash "$HOOK" >/dev/null 2>&1
bg_wait "$BG9/state"
[ "$(bg_starts run "$BG9")" = 1 ]; ok_or $? T31 "замок убитого пересчёта с суммой принят за идущий — правка ушла в сверку"
# Отказ пересчёта (код 3) и сломанная сверка (код 2) недоставленное «устарело» не снимают: решает код, а
# не слово «пересчитаны», и сломанный прибор — не «чисто». Прогон — прямым вызовом режима, до конца.
export STUB_SLEEP=0
BG10="$TMP/bg10"; _bg_stub "$BG10" VAL-W
sed -i.bak 's/run) echo "[^"]*" ;;/run) exit 3 ;;/' "$BG10/scripts/backlog-refresh-readings.sh"
printf 'УСТАРЕЛО-ДО-ОТКАЗА\n' > "$BG10/state/backlog-reading-refresh-check.msg"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"session_id":"bg"}' "$BG10/BACKLOG.md" \
    | env -u BRR_FOREGROUND BRR_JOB=run STATE_DIR="$BG10/state" BRR_TRUSTED_ROOT="$BG10" bash "$HOOK" >/dev/null 2>&1
[ -f "$BG10/state/backlog-reading-refresh-check.msg" ]; ok_or $? T32 "отказ пересчёта (код 3) снял недоставленное «устарело»"
BG11="$TMP/bg11"; _bg_stub "$BG11" VAL-V
sed -i.bak 's/exit 1 ;;/exit 2 ;;/' "$BG11/scripts/backlog-refresh-readings.sh"
printf 'УСТАРЕЛО-ДО-ПОЛОМКИ\n' > "$BG11/state/backlog-reading-refresh-check.msg"
printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"session_id":"bg"}' "$BG11/BACKLOG.md" \
    | env -u BRR_FOREGROUND BRR_JOB=check STATE_DIR="$BG11/state" BRR_TRUSTED_ROOT="$BG11" bash "$HOOK" >/dev/null 2>&1
[ -f "$BG11/state/backlog-reading-refresh-check.msg" ]; ok_or $? T33 "сломанная сверка (код 2) сняла недоставленное «устарело» как чистая"
unset STUB_SLEEP
# Режим прогона не уходит в окружение команд показаний: команда, сама зовущая хук, иначе вошла бы в него.
BG12="$TMP/bg12"; _bg_stub "$BG12" VAL-U
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "${BRR_JOB:-none}" >> "$CLAUDSOUL_REPO/jobenv"' 'exit 0' \
    > "$BG12/scripts/backlog-refresh-readings.sh"
printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"session_id":"bg"}' "$BG12/BACKLOG.md" \
    | env -u BRR_FOREGROUND BRR_JOB=check STATE_DIR="$BG12/state" BRR_TRUSTED_ROOT="$BG12" bash "$HOOK" >/dev/null 2>&1
[ "$(cat "$BG12/jobenv" 2>/dev/null)" = none ]; ok_or $? T34 "режим прогона утёк в окружение команды показания: $(cat "$BG12/jobenv" 2>/dev/null)"
# T35 — ВЛАДЕЛЬЦА ПЕРЕЧНЯ КОРНЕЙ НЕ ДОСТАТЬ — ПУТЬ ЖИВОЙ (D1013, вторая редакция по финальному скептику). Хук
# ставится вместе с библиотекой; недостижимый владелец у него — частичный перенос, и «частный» молча увёл бы живую
# отметку во временную папку. Копия хуков без root-cause-lib.sh и песочный HOME без установки: след правки ложится в
# живой каталог песочного HOME. Контроль направления — T35b: тот же источник с владельцем частный, живой пуст.
# Касание — правка, а не чтение: чтение идёт полосой сверки, и отметки она не пишет.
NL="$TMP/nolib"; mkdir -p "$NL"
for f in "$HOOKS"/*.sh; do [ "${f##*/}" = root-cause-lib.sh ] || cp "$f" "$NL/"; done
cp -R "$HOOKS/lib" "$NL/lib" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_reading_refresh.sh:$LINENO" >&2; exit 1; }
FN="$TMP/fn"; _bg_stub "$FN" МИР-N
nl_touch() {  # nl_touch <хук> <HOME>
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"session_id":"nl"}' "$FN/BACKLOG.md" \
        | env -u STATE_DIR -u PATHS_LIB HOME="$2" BRR_TRUSTED_ROOT="$FN" STUB_SLEEP=0 bash "$1" >/dev/null 2>&1
}
nl_touch "$NL/backlog-reading-refresh.sh" "$TMP/home-nl"
grep -q . <<< "$(ls -A "$TMP/home-nl/.claude/hooks/state" 2>/dev/null)"; ok_or $? T35 "владельца нет — следа правки в живом каталоге нет"
nl_touch "$HOOK" "$TMP/home-wl"
! grep -q . <<< "$(ls -A "$TMP/home-wl/.claude/hooks/state" 2>/dev/null)"; ok_or $? T35b "с владельцем фикстура оставила след в живом каталоге"
rm -f "$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)/backlog-reading-refresh-$(printf '%s' "$FN/BACKLOG.md" | cksum | awk '{print $1}')"* 2>/dev/null

echo "backlog reading refresh: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
