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
PROJ="$TMP/proj"; mkdir -p "$PROJ/scripts"
cp "$REFRESH" "$PROJ/scripts/"

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
        | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

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
if ! grep -q "^\*\*Последнее показание.*VAL-CLOSED-NEW" "$PROJ/BACKLOG.md"; then PASS=$((PASS+1))
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
       | bash "$HOOK" 2>&1); RC6=$?
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
        | STATE_DIR="$S10" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
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
        | STATE_DIR="$S10" bash "$HOOK" 2>/dev/null)
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

echo "backlog reading refresh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
