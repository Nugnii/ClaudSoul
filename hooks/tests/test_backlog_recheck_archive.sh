#!/usr/bin/env bash
# СУДИТ: scripts/backlog-recheck.sh
# test_backlog_recheck_archive.sh — «Проверки» закрытых пунктов архива исполняются, и откат отличим от гнилой пробы.
#
# Результат: режим `--archive` называет `✗ <ID>` закрытый пункт, чья «Проверка» расходится с объявленным кодом,
#            а «не измерено» (код 2, 126/127, срок, кольцо, нестабильность) — значком `?`; обычный прогон
#            пересказывает итог замера `archive-checks` по пункту на строку.
# Проверка результата: bash hooks/tests/test_backlog_recheck_archive.sh даёт 0
#
# Повод (D1147, 31 октября 2026). После переноса в архив «Проверку» закрытого пункта не исполнял никто: проба
# закрытого D439 краснела с 25 октября и нашлась случайно. Замер того же дня: 53 закрытых пункта красны в самом
# репозитории. Ноги держат обе стороны: откат назван (T1) И держащийся не назван (T2) — без T2 зеленел бы режим,
# называющий всё подряд; не измеренное не выдаётся за откат (T3, T4, T7, T13) И не исчезает молча.
set -uo pipefail
unset BACKLOG_CHECKS_NESTED
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
command -v python3 >/dev/null 2>&1 || { echo "нет python3 — пропуск"; exit 0; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
F="$T/repo"; ST="$T/state"
mkdir -p "$F/scripts" "$F/hooks" "$ST/measurement-runs"
cp "$REPO/scripts/backlog-recheck.sh" "$F/scripts/" && cp "$REPO/hooks/backlog-lib.sh" "$F/hooks/" \
    || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck_archive.sh:$LINENO" >&2; exit 1; }
: > "$F/BACKLOG.md"
cat > "$F/BACKLOG-archive.md" <<A
# Архив

- ☑ **D9** откат
  **Проверка.** \`bash -c 'echo "дефект: вернулся"; exit 1'\` → 0
- ☑ **D8** держится
  **Проверка.** \`true\` → 0
  **Проверка.** \`bash -c 'exit 0'\` → 0
- ☑ **D7** рамка не собралась
  **Проверка.** \`exit 2\` → 0
- ☑ **D6** проба удалена
  **Проверка.** \`bash hooks/tests/fixtures/нет_пробы_d6.sh\` → 0
- ⊘ **D5** снят
  **Проверка.** \`touch "$T/RAN5"; false\` → 0
- ☑ **D4** команда в заборе кода
\`\`\`
  **Проверка.** \`touch "$T/RAN4"; false\` → 0
\`\`\`
- ☑ **D3** висит
  **Проверка.** \`sleep 20\` → 0
- ☑ **D2** прозой
  **Проверка.** \`touch "$T/RAN2"; false\` печатает что-то
- ☑ **D11** нестабильна
  **Проверка.** \`bash -c '[ -f "$T/flaky" ] && exit 0; touch "$T/flaky"; exit 1'\` → 0
A
run_archive() {  # <архив> → вывод режима в $T/out, код в $T/rc
    ( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$1" BACKLOG_ARCHIVE_CHECK_TIMEOUT=2 \
        bash scripts/backlog-recheck.sh --archive > "$T/out" 2>&1 < /dev/null ); echo $? > "$T/rc"
}
run_archive "$F/BACKLOG-archive.md"
OUT=$(cat "$T/out"); RC=$(cat "$T/rc")

# T1: откат назван по имени и со словами самой пробы
grep -q '^  ✗ D9 .*вывод: дефект: вернулся' <<< "$OUT" && ok || bad T1 "откат D9 не назван или без вывода пробы: $OUT"
# T2: положительный контроль — держащийся пункт не назван ни откатом, ни «не измерено»
grep -qE '^  (✗|\?) D8 ' <<< "$OUT" && bad T2 "держащийся D8 назван: $OUT" || ok
# T3: код 2 — «не измерено», а не откат
grep -q '^  ? D7 ' <<< "$OUT" && ! grep -q '^  ✗ D7 ' <<< "$OUT" && ok || bad T3 "код 2 у D7 не «?»: $OUT"
# T4: удалённая проба (127) — гнилая, «не измерено»
grep -q '^  ? D6 .*гнилая' <<< "$OUT" && ok || bad T4 "удалённая проба D6 не названа гнилой: $OUT"
# T5–T6, T8: снятый ⊘, команда в заборе кода и строка без объявленного кода не исполняются
[ -e "$T/RAN5" ] && bad T5 "исполнена «Проверка» снятого (⊘) D5" || ok
[ -e "$T/RAN4" ] && bad T6 "исполнена команда из забора кода (D4)" || ok
[ -e "$T/RAN2" ] && bad T8 "исполнена строка без объявленного кода (D2)" || ok
# T7: срок — «не измерено»
grep -q '^  ? D3 .*не ответила за 2 с' <<< "$OUT" && ok || bad T7 "зависшая D3 не названа сроком: $OUT"
# T13: красное в потоке, зелёное в одиночку — «нестабильна», не откат
grep -q '^  ? D11 .*нестабильна' <<< "$OUT" && ok || bad T13 "нестабильная D11 не названа: $OUT"
# T9: код режима — 1 при откате
[ "$RC" = 1 ] && ok || bad T9 "код режима при откате $RC, ждали 1"
grep -q '^Исполнено «Проверок»: ' <<< "$OUT" && ok || bad T9b "нет строки итога: $OUT"

# T10: без отката — код 0, «не измерено» кода не красит
printf -- '- ☑ **D1** держится\n  **Проверка.** `true` → 0\n- ☑ **D2** рамка\n  **Проверка.** `exit 2` → 0\n' > "$T/a2.md"
run_archive "$T/a2.md"
[ "$(cat "$T/rc")" = 0 ] && ok || bad T10 "без отката код $(cat "$T/rc"): $(cat "$T/out")"

# T11: под маркером вложенности — «не исполнялось» (2), ни одной команды
printf -- '- ☑ **D1** метка\n  **Проверка.** `touch "%s/RAN11"` → 0\n' "$T" > "$T/a3.md"
( cd "$F" && BACKLOG_CHECKS_NESTED=1 CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a3.md" \
    bash scripts/backlog-recheck.sh --archive > /dev/null 2>&1 < /dev/null ); r=$?
[ "$r" = 2 ] && [ ! -e "$T/RAN11" ] && ok || bad T11 "под маркером вложенности код $r, исполнено: $([ -e "$T/RAN11" ] && echo да || echo нет)"

# T12: кольцо — «Проверка», зовущая режим со снятым маркером, исполняется ОДИН раз: ключ библиотеки отбивает уже
# первый повторный вход той же команды, и внутренний прогон называет его «?», а не молчит. Счёт исполнений и
# вывод внутреннего прогона, а не внешний текст: внешний отказ изнутри не печатает.
# Своё дерево: путь архива «Проверке» не наследуется, и кольцо замыкается только через архив по умолчанию.
F4="$T/repo4"; mkdir -p "$F4/scripts" "$F4/hooks" && cp "$F/scripts/backlog-recheck.sh" "$F4/scripts/" && cp "$F/hooks/backlog-lib.sh" "$F4/hooks/"
: > "$F4/BACKLOG.md"
printf -- '- ☑ **D10** кольцо\n  **Проверка.** `echo x >> "%s/ring.cnt"; env -u BACKLOG_CHECKS_NESTED bash scripts/backlog-recheck.sh --archive > "%s/inner.out" 2>&1` → 0\n' "$T" "$T" > "$F4/BACKLOG-archive.md"
( cd "$F4" && CLAUDSOUL_REPO="$F4" STATE_DIR="$ST" BACKLOG_ARCHIVE_CHECK_TIMEOUT=30 \
    bash scripts/backlog-recheck.sh --archive > "$T/out4" 2>&1 < /dev/null ); r=$?
n=$(grep -c x "$T/ring.cnt" 2>/dev/null)
[ "${n:-0}" = 1 ] && [ "$r" = 0 ] && grep -q '^  ? D10 .*кольцо' "$T/inner.out" 2>/dev/null && ok \
    || bad T12 "кольцо: исполнений ${n:-0}, ждали 1 (код $r); изнутри: $(cat "$T/inner.out" 2>/dev/null)"

# T14: пересказ в обычном прогоне — каждый пункт своей строкой, тем же значком
run_archive "$F/BACKLOG-archive.md"; cp "$T/out" "$ST/measurement-runs/archive-checks.out"
DEF=$(cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" LESSONS_DIR="$T/none" bash scripts/backlog-recheck.sh 2>&1)
grep -q '^  ✗ D9 .*архив, прогон' <<< "$DEF" && grep -q '^  ? D7 .*архив, прогон' <<< "$DEF" && ok \
    || bad T14 "пересказ не назвал D9/D7: $DEF"
grep -qE '^  (✗|\?) D8 ' <<< "$DEF" && bad T14b "пересказ назвал держащийся D8" || ok
# T15: итога нет либо он неполон — «не проверено», а не «держится»
: > "$ST/measurement-runs/archive-checks.out"
DEF=$(cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" LESSONS_DIR="$T/none" bash scripts/backlog-recheck.sh 2>&1)
grep -q '^  ? D1147 .*не исполнялись' <<< "$DEF" && ok || bad T15 "пустой итог не назван: $DEF"
printf '«Проверки» закрытых пунктов архива\n  ✗ D9    красна\n' > "$ST/measurement-runs/archive-checks.out"
DEF=$(cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" LESSONS_DIR="$T/none" bash scripts/backlog-recheck.sh 2>&1)
grep -q '^  ? D1147 .*неполон' <<< "$DEF" && ok || bad T15b "неполный итог не назван: $DEF"

# --- Круг 2 (скептик D1147, круг 1) ---
# T16 (H1): многострочная «Проверка» исполняется и называется; T17 (H2): молчащая на красном проба сказана вслух;
# T24 (L4): закрытый пункт без «Проверки» посчитан.
printf -- '- ☑ **D20** многострочная\n  **Проверка.** `bash -c '"'"'echo откат\nexit 1'"'"'` → 0\n- ☑ **D21** молчит\n  **Проверка.** `false` → 0\n- ☑ **D22** без проверки\n  **Результат.** держится.\n' > "$T/a5.md"
run_archive "$T/a5.md"; O5=$(cat "$T/out")
grep -q '^  ✗ D20 .*вывод: откат' <<< "$O5" && ok || bad T16 "многострочная красная D20 не названа: $O5"
grep -qE '^  ✗ D21 +\[без слов пробы\] «Проверка» красна' <<< "$O5" && ok || bad T17 "молчащая красная D21 не сказана вслух: $O5"
grep -q 'закрытых пунктов без «Проверки»: 1' <<< "$O5" && ok || bad T24 "пункт без «Проверки» не посчитан: $O5"

# T18 (H3): унаследованный `BACKLOG_ARCHIVE` (так зовёт архиватор сборщик) путь архива не меняет.
printf -- '- ☑ **D7** приманка\n  **Проверка.** `false` → 0\n' > "$T/decoy.md"
( cd "$F" && BACKLOG_ARCHIVE="$T/decoy.md" CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_ARCHIVE_CHECK_TIMEOUT=2 \
    bash scripts/backlog-recheck.sh --archive > "$T/out18" 2>&1 < /dev/null )
grep -q 'приманка\|decoy' "$T/out18" && bad T18 "режим читает архив из BACKLOG_ARCHIVE: $(cat "$T/out18")" || ok
grep -q '^  ✗ D9 ' "$T/out18" && ok || bad T18b "свой архив не исполнен при чужом BACKLOG_ARCHIVE: $(cat "$T/out18")"

# T19 (M1): общий срок исчерпан — нестабильная всё равно повторяется в одиночку и не выдаётся за откат.
printf -- '- ☑ **D1** нестабильна\n  **Проверка.** `bash -c '"'"'[ -f "%s/fl19" ] && exit 0; touch "%s/fl19"; exit 1'"'"'` → 0\n- ☑ **D2** долгая\n  **Проверка.** `sleep 2` → 0\n- ☑ **D3** после срока\n  **Проверка.** `true` → 0\n' "$T" "$T" > "$T/a6.md"
( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a6.md" BACKLOG_ARCHIVE_THREADS=1 BACKLOG_ARCHIVE_TOTAL=1 \
    bash scripts/backlog-recheck.sh --archive > "$T/out19" 2>&1 < /dev/null ); r=$?
grep -q '^  ? D1 .*нестабильна' "$T/out19" && [ "$r" = 0 ] && ok || bad T19 "после общего срока нестабильная D1 — не «нестабильна» (код $r): $(cat "$T/out19")"

# T20 (M2): потомок, вышедший из группы и держащий трубу, срок не обходит.
printf -- '- ☑ **D1** держит трубу\n  **Проверка.** `bash -c '"'"'set -m; sleep 40 & sleep 60'"'"'` → 0\n' > "$T/a7.md"
s0=$(date +%s)
( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a7.md" BACKLOG_ARCHIVE_CHECK_TIMEOUT=2 \
    bash scripts/backlog-recheck.sh --archive > "$T/out20" 2>&1 < /dev/null )
dt=$(( $(date +%s) - s0 ))
[ "$dt" -lt 25 ] && grep -q '^  ? D1 .*не ответила за 2 с' "$T/out20" && ok || bad T20 "срок 2 с, а прогон шёл $dt с: $(cat "$T/out20")"

# T21 (L2): копии одного пункта исполняются раз; разные пункты с одним номером не сливаются.
printf -- '- ☑ **D30** копия\n  **Проверка.** `echo x >> "%s/cnt21"; false` → 0\n## раздел\n- ☑ **D30** копия\n  **Проверка.** `echo x >> "%s/cnt21"; false` → 0\n- ☑ **D31** первый\n  **Проверка.** `false` → 0\n- ☑ **D31** второй\n  **Проверка.** `true` → 0\n' "$T" "$T" > "$T/a8.md"
run_archive "$T/a8.md"; O8=$(cat "$T/out")
n=$(grep -c x "$T/cnt21" 2>/dev/null)
# Исполнений три, а не шесть: в потоке, повтор в одиночку и повтор с трассой промолчавшей (D1201) — у одной копии.
[ "${n:-0}" = 3 ] && [ "$(grep -c '^  ✗ D30 ' <<< "$O8")" = 1 ] && ok || bad T21 "копии D30: исполнений ${n:-0} (повтор в одиночку — второе, с трассой — третье), строк: $(grep -c '^  ✗ D30 ' <<< "$O8"): $O8"
grep -q '^  ✗ D31 (стр. 6) ' <<< "$O8" && ! grep -q 'D31 (стр. 8)' <<< "$O8" && ok || bad T21b "пункты D31 слились: $O8"

# T22 (L1): кодировка вывода окружения не роняет печать.
( cd "$F" && PYTHONIOENCODING=ascii CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a2.md" \
    bash scripts/backlog-recheck.sh --archive > "$T/out22" 2>&1 < /dev/null ); r=$?
[ "$r" = 0 ] && grep -q '^Исполнено «Проверок»' "$T/out22" && ok || bad T22 "печать упала в кодировке ascii (код $r): $(cat "$T/out22")"

# T23 (M3): внутри «Проверки» пересказ чужих закрытий не судится.
run_archive "$F/BACKLOG-archive.md"; cp "$T/out" "$ST/measurement-runs/archive-checks.out"
DEF=$(cd "$F" && BACKLOG_CHECKS_NESTED=1 CLAUDSOUL_REPO="$F" STATE_DIR="$ST" LESSONS_DIR="$T/none" bash scripts/backlog-recheck.sh 2>&1)
! grep -q '^  ✗ D9 ' <<< "$DEF" && grep -q '^  … D1147 .*внутри «Проверки»' <<< "$DEF" && ok || bad T23 "пересказ внутри «Проверки» судит чужие закрытия: $DEF"
DEF=$(cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" LESSONS_DIR="$T/none" bash scripts/backlog-recheck.sh 2>&1)
grep -q '^  … D1147 .*Исполнено «Проверок»: ' <<< "$DEF" && ok || bad T24b "пересказ не назвал счёт исполненного: $DEF"

# --- Круг 3 (скептик D1147, круг 2) ---
# T31 (M2): сирота (`set -m` в подоболочке, родитель вышел) и рождающий цикл после срока не живут. Метки — дробные
# сроки сна, по ним и ищутся выжившие.
printf -- '- ☑ **D1** сирота\n  **Проверка.** `bash -c '"'"'( set -m; sleep 41.7 & ); sleep 60'"'"'` → 0\n- ☑ **D2** рождает\n  **Проверка.** `bash -c '"'"'set -m; while :; do sleep 42.3 & sleep 0.02; done'"'"'` → 0\n' > "$T/a9.md"
( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a9.md" BACKLOG_ARCHIVE_CHECK_TIMEOUT=2 \
    bash scripts/backlog-recheck.sh --archive > "$T/out31" 2>&1 < /dev/null )
left=$(pgrep -f 'sleep 4(1\.7|2\.3)' | grep -c . || true)
[ "${left:-0}" = 0 ] && ok || { bad T31 "после срока живы $left процессов команды: $(cat "$T/out31")"; pkill -f 'sleep 4(1\.7|2\.3)' 2>/dev/null; }
# T32 (L4 круга 2): команда вышла с объявленным кодом, трубу держит фоновый потомок — держится, а не «срок»; потомок снят.
printf -- '- ☑ **D3** держит трубу\n  **Проверка.** `bash -c '"'"'( sleep 43.1 & ); exit 0'"'"'` → 0\n' > "$T/a10.md"
( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a10.md" BACKLOG_ARCHIVE_CHECK_TIMEOUT=2 \
    bash scripts/backlog-recheck.sh --archive > "$T/out32" 2>&1 < /dev/null )
! grep -qE '^  (✗|\?) D3 ' "$T/out32" && ! pgrep -f 'sleep 43\.1' >/dev/null && ok \
    || { bad T32 "вышедшая с 0 команда не держится или потомок жив: $(cat "$T/out32")"; pkill -f 'sleep 43\.1' 2>/dev/null; }
# T33 (M1 круга 2): строка `# …` с нулевой колонки внутри многострочной команды — комментарий, а не граница пункта.
printf -- '- ☑ **D40** с комментарием\n  **Проверка.** `bash -c '"'"'\n# откат вернулся\necho откат; exit 1'"'"'` → 0\n' > "$T/a11.md"
run_archive "$T/a11.md"
grep -q '^  ✗ D40 .*вывод: откат' "$T/out" && ok || bad T33 "команда с # в нулевой колонке потеряна: $(cat "$T/out")"
# T34 (L1 круга 2): повтор в одиночку сверх своего бюджета — «не подтверждено», а не откат.
printf -- '- ☑ **D1** долгий красный\n  **Проверка.** `bash -c '"'"'sleep 2; exit 1'"'"'` → 0\n- ☑ **D2** красный\n  **Проверка.** `false` → 0\n' > "$T/a12.md"
( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a12.md" BACKLOG_ARCHIVE_THREADS=1 \
    BACKLOG_ARCHIVE_RECHECK_TOTAL=1 bash scripts/backlog-recheck.sh --archive > "$T/out34" 2>&1 < /dev/null )
grep -q '^  ? D2 .*не подтверждено' "$T/out34" && ok || bad T34 "повтор сверх бюджета не назван: $(cat "$T/out34")"
# T35 (L1–L2 круга 2): «Проверке» не наследуются путь архива прогона и кодировка вывода режима.
printf -- '- ☑ **D50** окружение\n  **Проверка.** `bash -c '"'"'[ -z "${BACKLOG_RECHECK_ARCHIVE:-}" ] && [ -z "${PYTHONIOENCODING+x}" ]'"'"'` → 0\n' > "$T/a13.md"
( cd "$F" && env -u PYTHONIOENCODING CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a13.md" \
    bash scripts/backlog-recheck.sh --archive > "$T/out35" 2>&1 < /dev/null )
! grep -qE '^  (✗|\?) D50 ' "$T/out35" && grep -q '^Исполнено «Проверок»: 1 из 1 ' "$T/out35" && ok \
    || bad T35 "«Проверка» унаследовала окружение режима: $(cat "$T/out35")"
# T36 (L5 круга 2): пустая команда не исполняется и держащейся не объявляется.
printf -- '- ☑ **D61** пусто\n  **Проверка.** ` ` → 0\n' > "$T/a14.md"
( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a14.md" BACKLOG_RECHECK_VERBOSE=1 \
    bash scripts/backlog-recheck.sh --archive > "$T/out36" 2>&1 < /dev/null )
! grep -q '✓ D61' "$T/out36" && grep -q 'Исполнено «Проверок»: 0 из 0 ' "$T/out36" && ok || bad T36 "пустая команда объявлена держащейся: $(cat "$T/out36")"

# --- Круг 4 (скептик D1147, круг 3) ---
command -v pgrep >/dev/null 2>&1 || echo "нет pgrep — ноги T31, T32, T39, T41 о выживших процессах не судят"
# T37 (M1): у пункта с двумя красными слова говорящей не прячутся за молчащей; T38 (L6): говорящий — без метки.
printf -- '- ☑ **D8** две красные\n  **Проверка.** `bash -c '"'"'exit 1'"'"'` → 0\n  **Проверка.** `bash -c '"'"'echo "дефект вернулся: 3 строки"; exit 1'"'"'` → 0\n' > "$T/a15.md"
run_archive "$T/a15.md"
grep -qE '^  ✗ D8 +«Проверка» .*вывод: дефект вернулся' "$T/out" && ok || bad T37 "говорящая красная спрятана за молчащей: $(cat "$T/out")"
run_archive "$F/BACKLOG-archive.md"
! grep -qE '^  ✗ D9 +\[без слов пробы\]' "$T/out" && grep -qE '^  ✗ D9 +«Проверка»' "$T/out" && ok || bad T38 "говорящий D9 помечен молчащим: $(cat "$T/out")"
# T39 (L4): после штатного выхода фоновый потомок снят.
printf -- '- ☑ **D9** фон\n  **Проверка.** `bash -c '"'"'sleep 44.9 >/dev/null 2>&1 & exit 0'"'"'` → 0\n' > "$T/a16.md"
run_archive "$T/a16.md"
! pgrep -f 'sleep 44\.9' >/dev/null && ok || { bad T39 "фоновый потомок пережил штатный выход"; pkill -f 'sleep 44\.9' 2>/dev/null; }
# T40 (L5): «Проверке» возвращается кодировка вызвавшего, а не режима.
printf -- '- ☑ **D50** кодировка\n  **Проверка.** `bash -c '"'"'[ "${PYTHONIOENCODING:-}" = latin-1 ]'"'"'` → 0\n' > "$T/a17.md"
( cd "$F" && PYTHONIOENCODING=latin-1 CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a17.md" \
    bash scripts/backlog-recheck.sh --archive > "$T/out40" 2>&1 < /dev/null )
! grep -qE '^  (✗|\?) D50 ' "$T/out40" && ok || bad T40 "кодировка вызвавшего не вернулась «Проверке»: $(cat "$T/out40")"
# T41 (L2): вывод не дочитан (трубу держит потомок, ушедший из сессии) — «не измерено», а не «без слов пробы».
printf -- '- ☑ **D80** держит трубу вне сессии\n  **Проверка.** `bash -c '"'"'echo "дефект: вернулся"; python3 -c "import os,time; os.setsid(); time.sleep(31.3)" & exit 1'"'"'` → 0\n' > "$T/a18.md"
run_archive "$T/a18.md"
grep -q '^  ? D80 .*не дочитан' "$T/out" && ok || bad T41 "недочитанный вывод не назван: $(cat "$T/out")"
pkill -f 'time.sleep\(31\.3\)' 2>/dev/null
# T42 (M2): пересказ ведёт молчащее красное своим состоянием: метка за номером, своя строка подвала, не «перестали
# держаться».
printf '%s\n' '«Проверки» закрытых пунктов архива (x)' '  ✗ D21   [без слов пробы] «Проверка» красна (код 1, объявлен 0) — откат от гнилой пробы по её выводу не отличить: `false`' 'Исполнено «Проверок»: 1 из 1 у 1 закрытых пунктов за 0 с; откатилось пунктов: 0, красны без слов пробы: 1.' > "$ST/measurement-runs/archive-checks.out"
DEF=$(cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" LESSONS_DIR="$T/none" bash scripts/backlog-recheck.sh 2>&1)
grep -qE '^  ✗ D21 +\[без слов пробы\] архив, прогон' <<< "$DEF" && grep -q '^Красны без слов пробы: 1 ' <<< "$DEF" && ok \
    || bad T42 "пересказ не ведёт молчащее отдельно: $DEF"
# T43 (H1 круга 3): итог старого формата — «не проверено», без пересказа строк.
printf '%s\n' '  ✗ D9    «Проверка» красна (код 1, объявлен 0): `x`' 'Исполнено «Проверок»: 3 у 2 закрытых пунктов за 1 с; откатилось пунктов: 1, не измерено: 0.' > "$ST/measurement-runs/archive-checks.out"
DEF=$(cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" LESSONS_DIR="$T/none" bash scripts/backlog-recheck.sh 2>&1)
grep -q '^  ? D1147 .*старого формата' <<< "$DEF" && ! grep -q '^  ✗ D9 ' <<< "$DEF" && ok || bad T43 "итог старого формата пересказан: $DEF"
# T44 (L7): пустая команда подписана пустой, счёт свой.
( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a14.md" BACKLOG_RECHECK_VERBOSE=1 \
    bash scripts/backlog-recheck.sh --archive > "$T/out44" 2>&1 < /dev/null )
grep -q '^  … D61 .*пуста' "$T/out44" && grep -q 'строк без объявленного кода: 0, пустых: 1' "$T/out44" && ok || bad T44 "пустая команда подписана неверно: $(cat "$T/out44")"

# --- Круг 5 (скептик D1147, круг 4, L7): коды выхода и подвал при одних молчащих, «(стр. N)» в пересказе ---
printf -- '- ☑ **D21** молчит\n  **Проверка.** `false` → 0\n' > "$T/a19.md"
run_archive "$T/a19.md"
[ "$(cat "$T/rc")" = 1 ] && ok || bad T45 "--archive при одних молчащих отдал код $(cat "$T/rc")"
# Чистое дерево: инварианты D7–D13 не красны, и подвал судит только молчащие.
F6="$T/repo6"; mkdir -p "$F6/scripts" "$F6/hooks" "$F6/knowledge" "$T/less6"
cp "$F/scripts/backlog-recheck.sh" "$F6/scripts/" && cp "$F/hooks/backlog-lib.sh" "$F6/hooks/" \
    && cp "$REPO/knowledge/META.md" "$F6/knowledge/" && cp "$REPO/knowledge/META.md" "$T/less6/" && : > "$F6/BACKLOG.md" && : > "$F6/BACKLOG-archive.md"
mkdir -p "$T/st6/measurement-runs"
printf '%s\n' '  ✗ D21   [без слов пробы] «Проверка» красна (код 1, объявлен 0) — откат от гнилой пробы по её выводу не отличить: `false`' \
    '  ✗ D31 (стр. 6) [без слов пробы] «Проверка» красна (код 1, объявлен 0) — x: `false`' \
    'Исполнено «Проверок»: 2 из 2 у 2 закрытых пунктов за 0 с; откатилось пунктов: 0, красны без слов пробы: 2, не измерено: 0.' > "$T/st6/measurement-runs/archive-checks.out"
DEF6=$(cd "$F6" && CLAUDSOUL_REPO="$F6" STATE_DIR="$T/st6" LESSONS_DIR="$T/less6" bash scripts/backlog-recheck.sh 2>&1); r6=$?
[ "$r6" = 1 ] && ok || bad T46 "обычный прогон при одних молчащих отдал код $r6: $DEF6"
grep -q 'откатов со словами пробы нет' <<< "$DEF6" && ! grep -q 'все держатся' <<< "$DEF6" && ! grep -q 'ПЕРЕСТАЛИ' <<< "$DEF6" && ok \
    || bad T47 "подвал при одних молчащих неверен: $DEF6"
grep -qE '^  ✗ D31 +\[без слов пробы\] \(стр\. 6\) архив' <<< "$DEF6" && ok || bad T48 "молчащая копия повторного номера не пересказана молчащей: $DEF6"

# --- D1201: промолчавшая красная получает подсказку повтора без глушения, с трассой; метка остаётся ---
# Метку «без слов пробы» снимают только слова первого прогона: трасса у команды с кавычками и подстановками всегда
# «нова», и как вердикт она переводила шум в «откатилось» (скептик opus D1201, H1).
# T49: значения из трассы (`n=1` → `'[' 1 -eq 0 ']'`) — в подсказке, метка на месте;
# T50: проба под полным глушением названа файлом и строкой; T51: обе остаются «без слов пробы», откатов 0.
mkdir -p "$F/hooks/tests/fixtures"
printf '#!/usr/bin/env bash\ngrep -q nothing-here /dev/null\n' > "$F/hooks/tests/fixtures/probe_t50.sh"
printf -- '- ☑ **D49** значения\n  **Проверка.** `bash -c '"'"'n=1; [ "$n" -eq 0 ]'"'"'` → 0\n- ☑ **D50** проба молчит\n  **Проверка.** `bash hooks/tests/fixtures/probe_t50.sh >/dev/null 2>&1` → 0\n' > "$T/a49.md"
run_archive "$T/a49.md"; O49=$(cat "$T/out")
grep -qE "^  ✗ D49 +\[без слов пробы\] .*подсказка повтора без глушения, с трассой: .*n=1 .*1 -eq 0" <<< "$O49" && ok || bad T49 "значения трассы не в подсказке либо снята метка: $O49"
grep -qE '^  ✗ D50 +\[без слов пробы\] .*подсказка повтора.*⟪probe_t50\.sh:2⟫ grep -q nothing-here' <<< "$O49" && ok || bad T50 "проба под глушением не названа файлом и строкой: $O49"
grep -q 'откатилось пунктов: 0, красны без слов пробы: 2' <<< "$O49" && ok || bad T51 "подсказка трассы сменила исход: $O49"

# T52 (H1): кавычки и подстановка — в трассе всегда «новое» (раскрытый путь), а метка всё равно остаётся;
# T53: проба без глушения говорит сама — её слова первыми в подсказке; T54 (L3): ловушка EXIT не вытесняет
# значения из хвоста; T55 (M3): строки-продолжения многострочного значения трассы не выдаются за слова пробы.
printf '#!/usr/bin/env bash\necho "носитель остался: x.sh"\nexit 1\n' > "$F/hooks/tests/fixtures/probe_t53.sh"
printf '#!/usr/bin/env bash\ntrap "rm -f /dev/null/none 2>/dev/null; true" EXIT\nn=9\n[ "$n" -eq 0 ] || exit 1\n' > "$F/hooks/tests/fixtures/probe_t54.sh"
printf '#!/usr/bin/env bash\nv=$(printf "a\\nПРОДОЛЖЕНИЕ")\n[ -z "$v" ]\n' > "$F/hooks/tests/fixtures/probe_t55.sh"
printf -- '- ☑ **D52** кавычки\n  **Проверка.** `bash -c '"'"'cd "$HOME" && grep -q "x" /dev/null'"'"'` → 0\n- ☑ **D53** говорит без глушения\n  **Проверка.** `bash hooks/tests/fixtures/probe_t53.sh >/dev/null 2>&1` → 0\n- ☑ **D54** ловушка\n  **Проверка.** `bash hooks/tests/fixtures/probe_t54.sh >/dev/null 2>&1` → 0\n- ☑ **D55** продолжение\n  **Проверка.** `bash hooks/tests/fixtures/probe_t55.sh >/dev/null 2>&1` → 0\n' > "$T/a52.md"
run_archive "$T/a52.md"; O52=$(cat "$T/out")
grep -qE '^  ✗ D52 +\[без слов пробы\] .*подсказка повтора.*grep -q x /dev/null' <<< "$O52" && ok || bad T52 "шум трассы снял метку либо подсказки нет: $O52"
grep -qE '^  ✗ D53 +\[без слов пробы\] .*подсказка повтора без глушения, с трассой: носитель остался: x\.sh; трасса: ' <<< "$O52" && ok || bad T53 "слова пробы без глушения не в подсказке: $O52"
grep -qE '^  ✗ D54 +.*подсказка повтора.*n=9 .*9 -eq 0 .*exit 1$' <<< "$O52" && ok || bad T54 "ловушка EXIT вытеснила значения из хвоста: $O52"
grep -qE '^  ✗ D55 +.*подсказка повтора без глушения, с трассой: ⟪' <<< "$O52" && ! grep -q 'с трассой: ПРОДОЛЖЕНИЕ' <<< "$O52" && ok || bad T55 "продолжение трассы выдано за слова пробы: $O52"

# T57: нулевой выход вложенного помощника не обрезает подсказку — место падения после него остаётся (живой D474).
printf '#!/usr/bin/env bash\nexit 0\n' > "$F/hooks/tests/fixtures/helper_t57.sh"
printf -- '- ☑ **D57** помощник\n  **Проверка.** `bash -c '"'"'bash hooks/tests/fixtures/helper_t57.sh; m=7; [ "$m" -eq 0 ]'"'"'` → 0\n' > "$T/a57.md"
run_archive "$T/a57.md"; O57=$(cat "$T/out")
grep -qE '^  ✗ D57 +.*подсказка повтора.*m=7 .*7 -eq 0' <<< "$O57" && ok || bad T57 "нулевой выход помощника обрезал подсказку: $O57"

# T56 (M2): повторы с трассой идут после всех подтверждений и в остатке бюджета — подтверждение важнее подсказки.
printf -- '- ☑ **D61** долгая\n  **Проверка.** `sleep 2; false` → 0\n- ☑ **D62** долгая\n  **Проверка.** `sleep 2; false` → 0\n- ☑ **D63** долгая\n  **Проверка.** `sleep 2; false` → 0\n' > "$T/a61.md"
( cd "$F" && CLAUDSOUL_REPO="$F" STATE_DIR="$ST" BACKLOG_RECHECK_ARCHIVE="$T/a61.md" BACKLOG_ARCHIVE_CHECK_TIMEOUT=10 \
    BACKLOG_ARCHIVE_RECHECK_TOTAL=3 bash scripts/backlog-recheck.sh --archive > "$T/out61" 2>&1 < /dev/null )
O61=$(cat "$T/out61")
grep -qE '^  ✗ D61 ' <<< "$O61" && grep -qE '^  ✗ D62 ' <<< "$O61" && ! grep -q 'подсказка повтора' <<< "$O61" && ok \
    || bad T56 "повтор с трассой съел бюджет подтверждений: $O61"

echo "backlog recheck archive: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
