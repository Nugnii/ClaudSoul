#!/usr/bin/env bash
# СУДИТ: hooks/backlog-open-write-guard.sh
# test_backlog_open_write_guard.sh — страж записи открытого пункта с зелёной или отсутствующей «Проверкой» (D264).
# Результат: новый или изменённый открытый пункт с зелёной «Проверкой» отбивается с именем; без строки
#            «Проверка» — тоже; красный проходит; закрытый пункт, неизменённые пункты, чужие файлы,
#            битый payload — тишина; срыв бюджета — не отказ, а контекст и журнал; отказ пишет журнал.
#            Неисполнимая «Проверка» отделена от красной (D432): не разбираемая оболочкой отбивается и не
#            исполняется; незапустившаяся (код 126/127) — НЕ отказ, а контекст с именем пункта и кодом плюс
#            журнал `unrunnable`, без ссылки на чужой замер точности; честный ненулевой код и объявленное
#            отсутствие скрипта проходят молча.
# Проверка результата: bash hooks/tests/test_backlog_open_write_guard.sh даёт 0
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/backlog-open-write-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система (D360)
PROJ="$TMP/proj"; mkdir -p "$PROJ"; STATE="$TMP/state"
BL="$PROJ/BACKLOG.md"
cat > "$BL" <<'EOF'
# BACKLOG

- ☐ **D10** красный открытый пункт, не меняется
  **Проверка.** `false` → 0
- ☐ **D11** открытый пункт с зелёной проверкой уже на диске (не наш предмет, пока не меняется)
  **Проверка.** `true` → 0
- ☑ **D12** закрытый
  **Проверка.** `true` → 0
EOF
edit() {  # edit <old> <new> [sid] → вывод хука
    jq -cn --arg f "$BL" --arg o "$1" --arg n "$2" --arg s "${3:-s1}" \
        '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' \
    | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null
}
write() { # write <content> [sid]
    jq -cn --arg f "$BL" --arg c "$1" --arg s "${2:-s1}" \
        '{session_id:$s, tool_name:"Write", tool_input:{file_path:$f, content:$c}}' \
    | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null
}
denied() { grep -q '"permissionDecision":"deny"' <<< "${1:-}"; }
# Тишина — своим утверждением, а не `[ -z ]`: прувер стражей (test_guards_provable) требует у теста
# отказывающего хука и проверку срабатывания, и проверку тишины в узнаваемой форме.
assert_silent() { if [ -z "${1:-}" ]; then ok; else bad "$2" "ожидалась тишина, получено: $1"; fi; }
# --- T1: новый открытый пункт с зелёной проверкой — отказ с именем ---
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D13** новый зелёный\n  **Проверка.** `true` → 0\n- ☑ **D12** закрытый')
denied "$OUT" && ok || bad "T1" "новый открытый пункт с зелёной проверкой прошёл: $OUT"
grep -q "D13" <<< "$OUT" && ok || bad "T1b" "пункт не назван в отказе: $OUT"
grep -q "зелёная" <<< "$OUT" && ok || bad "T1c" "вид не назван: $OUT"
# --- T2: новый открытый пункт с красной проверкой — проходит ---
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D14** новый красный\n  **Проверка.** `false` → 0\n- ☑ **D12** закрытый')
assert_silent "$OUT" "T2 красный открытый пункт отбит"
# --- T3: новый открытый пункт без строки «Проверка» — отказ ---
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D15** без критерия\n  **Род.** нет\n- ☑ **D12** закрытый')
denied "$OUT" && grep -q "D15" <<< "$OUT" && grep -q "нет строки" <<< "$OUT" && ok || bad "T3" "пункт без «Проверки» прошёл или не назван: $OUT"
# --- T4: правка закрытого пункта с зелёной проверкой — проходит (открытых не касается) ---
OUT=$(edit "- ☑ **D12** закрытый" "- ☑ **D12** закрытый, переименован")
assert_silent "$OUT" "T4 правка закрытого пункта отбита"
# --- T5: неизменённый открытый пункт с зелёной проверкой на диске не судится при чужой правке ---
OUT=$(edit "# BACKLOG" "# BACKLOG проекта")
assert_silent "$OUT" "T5 неизменённый пункт D11 отбит при правке заголовка"
# --- T6: Write целиком — судятся только изменённые: команда D10 стала зелёной → отказ; D11 не бежит ---
# Первая замена — через python, не `sed 0,/re/`: адрес 0 знает только GNU sed (pattern-shell-portability).
NEWC=$(python3 -c 'import sys; s = open(sys.argv[1], encoding="utf-8").read(); s = s.replace("**D10** красный открытый пункт, не меняется", "**D10** стал зелёным", 1).replace("`false` → 0", "`true` → 0", 1); sys.stdout.write(s)' "$BL")
T0=$(date +%s); OUT=$(write "$NEWC"); T1=$(( $(date +%s) - T0 ))
denied "$OUT" && grep -q "D10" <<< "$OUT" && ok || bad "T6" "изменённая на зелёную проверка не отбита при Write: $OUT"
grep -q "D11" <<< "$OUT" && bad "T6b" "неизменённый D11 попал в отказ при Write" || ok
# --- T7: закрытие пункта в той же правке (☐ → ☑) с зелёной проверкой — проходит ---
OUT=$(edit "- ☐ **D10** красный открытый пункт, не меняется" "- ☑ **D10** закрыт с показанием")
assert_silent "$OUT" "T7 закрытие пункта в правке отбито"
# --- T8: срыв бюджета — не отказ, а контекст; журнал видом timeout ---
OUT=$(OPEN_WRITE_TIMEOUT=1 STATE_DIR="$STATE" bash -c 'jq -cn --arg f "'"$BL"'" '"'"'{session_id:"s8", tool_name:"Edit", tool_input:{file_path:$f, old_string:"- ☑ **D12** закрытый", new_string:"- ☐ **D16** долгий\n  **Проверка.** `sleep 5` → 0\n- ☑ **D12** закрытый"}}'"'"' | bash "'"$HOOK"'" 2>/dev/null')
denied "$OUT" && bad "T8" "срыв бюджета выдан за зелёную: $OUT" || ok
grep -q "не уложилась" <<< "$OUT" && ok || bad "T8b" "срыв бюджета не назван контекстом: $OUT"
grep -q '"kind":"timeout"' "$STATE"/backlog-open-write-fired-s8.jsonl 2>/dev/null && ok || bad "T8c" "срыв не записан в журнал"
# --- T9: журнал отказа — семейство *-fired-*, вид green, имя пункта ---
grep -q '"kind":"green"' "$STATE"/backlog-open-write-fired-s1.jsonl 2>/dev/null && grep -q '"item":"D13"' "$STATE"/backlog-open-write-fired-s1.jsonl && ok || bad "T9" "отказ не записан в журнал семейства fired"
# --- T10: MultiEdit — правка, вносящая зелёный открытый пункт, отбита ---
OUT=$(jq -cn --arg f "$BL" '{session_id:"s10", tool_name:"MultiEdit", tool_input:{file_path:$f, edits:[{old_string:"# BACKLOG", new_string:"# BACKLOG"}, {old_string:"- ☑ **D12** закрытый", new_string:"- ☐ **D17** зелёный через MultiEdit\n  **Проверка.** `true` → 0\n- ☑ **D12** закрытый"}]}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
denied "$OUT" && grep -q "D17" <<< "$OUT" && ok || bad "T10" "MultiEdit с зелёным открытым пунктом прошёл: $OUT"
# --- T11: чужой файл и битый payload — тишина ---
OUT=$(jq -cn --arg f "$PROJ/README.md" '{session_id:"s11", tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
assert_silent "$OUT" "T11 чужой файл вызвал вывод"
OUT=$(printf 'не json' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null); assert_silent "$OUT" "T11b битый payload вызвал вывод"
# --- T13-T18: неисполнимая «Проверка» — не красная (D432, 17 сентября 2026) ---
# До правки всё, что не 0 и не 124, проходило красным: «команда сказала „нет“» и «команду не
# удалось запустить» шли одним кодом возврата, и пункт с ни разу не исполненным критерием
# ложился в долг молча. Уровень у двух видов разный (довод и замер — в шапке стража): синтаксис —
# отказ, коды 126/127 — контекст и журнал, запись проходит. Судится ДИНАМИЧЕСКАЯ часть текста —
# «<пункт> (неисполнима: <что>)»: слова «неисполнима» и «синтаксис» стоят и в статической части
# отказа, и нога, читающая только слово, зеленела бы на любом отказе (замечание скептика: мутант
# «126|127 → отказ с другим словом» такую ногу проходил). Контрпримеры держат вторую сторону:
# честный ненулевой код (в том числе не 1) и объявленное отсутствие скрипта проходят МОЛЧА —
# без них признак ширился бы до «всякий код, кроме 1».
named() { grep -q '"additionalContext"' <<< "${1:-}"; }
NEW18=$'- ☐ **D18** команды нет\n  **Проверка.** `claudsoul_missing_cmd_t13_5931` → 0\n- ☑ **D12** закрытый'
OUT=$(edit "- ☑ **D12** закрытый" "$NEW18" s13)
named "$OUT" && grep -qF "D18 (неисполнима: rc=127)" <<< "$OUT" && ok || bad "T13" "команда, которой нет (rc 127), прошла красной молча: $OUT"
denied "$OUT" && bad "T13a" "вид unrunnable отбит отказом — у него нет замера точности (ADR-015): $OUT" || ok
grep -q '"kind":"unrunnable"' "$STATE"/backlog-open-write-fired-s13.jsonl 2>/dev/null && ok || bad "T13b" "неисполнимая не записана в журнал видом unrunnable"
# T13c: контекст не предъявляет замер, в котором вида не было («23 срабатывания, ложных 0» — про иные виды)
grep -q "ложных 0" <<< "$OUT" && bad "T13c" "контекст unrunnable ссылается на замер точности чужих видов: $OUT" || ok
# T14: «скрипт ещё не написан» — голый вызов НАЗВАН, объявленное отсутствие (честный код 1) проходит молча
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D19** скрипт не написан\n  **Проверка.** `bash ./nope-not-written-t14.sh` → 0\n- ☑ **D12** закрытый')
named "$OUT" && grep -qF "D19 (неисполнима: rc=127)" <<< "$OUT" && ok || bad "T14" "вызов ненаписанного скрипта (rc 127) прошёл красным молча: $OUT"
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D19** скрипт не написан, отсутствие объявлено\n  **Проверка.** `test -f ./nope-not-written-t14.sh || exit 1; bash ./nope-not-written-t14.sh` → 0\n- ☑ **D12** закрытый')
assert_silent "$OUT" "T14b объявленное отсутствие скрипта (честный код 1) названо"
# T15: файл есть, но не запускается (rc 126)
printf '#!/bin/sh\nexit 1\n' > "$PROJ/noexec-t15.sh"; chmod -x "$PROJ/noexec-t15.sh"
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D20** не запускается\n  **Проверка.** `./noexec-t15.sh` → 0\n- ☑ **D12** закрытый')
named "$OUT" && grep -qF "D20 (неисполнима: rc=126)" <<< "$OUT" && ok || bad "T15" "незапускаемый файл (rc 126) прошёл красным молча: $OUT"
# T16: синтаксис оболочки — отбит ДО запуска (брат-здоровяк: completion-gate, вид syntax)
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D21** синтаксис\n  **Проверка.** `touch ran-t16; if [` → 0\n- ☑ **D12** закрытый' s16)
denied "$OUT" && grep -qF "D21 (неисполнима: синтаксис оболочки)" <<< "$OUT" && ok || bad "T16" "команда с ошибкой синтаксиса прошла красной: $OUT"
# T16b — нога СВОЙСТВА, а не починки: зелёная и на прежнем страже, потому что bash разбирает всю
# строку `-c` до исполнения. Держит обещание «судя, не исполняю», свидетели починки — T16 и T16c.
[ ! -e "$PROJ/ran-t16" ] && ok || bad "T16b" "неисполнимая по синтаксису команда ИСПОЛНИЛАСЬ"
grep -q '"kind":"syntax"' "$STATE"/backlog-open-write-fired-s16.jsonl 2>/dev/null && ok || bad "T16c" "синтаксис не записан в журнал видом syntax"
# T17: контрпример — честный ненулевой код, отличный от 1, остаётся красным и проходит
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D22** красная кодом 2\n  **Проверка.** `exit 2` → 0\n- ☑ **D12** закрытый')
assert_silent "$OUT" "T17 честная красная с кодом 2 отбита"
# T18: зелёный и незапустившийся в одной правке — отказ по зелёному, незапустившийся назван там же
# (вызов не выполнен, второго канала у него не будет)
OUT=$(edit "- ☑ **D12** закрытый" $'- ☐ **D23** зелёный\n  **Проверка.** `true` → 0\n- ☐ **D24** команды нет\n  **Проверка.** `claudsoul_missing_cmd_t18_5931` → 0\n- ☑ **D12** закрытый')
denied "$OUT" && grep -qF "D23 (зелёная)" <<< "$OUT" && grep -qF "D24 (неисполнима: rc=127)" <<< "$OUT" && ok || bad "T18" "отказ по зелёному потерял незапустившийся пункт: $OUT"
# --- T19–T24: новый пункт рядом с картой корней рождается с корнем (решение владельца 9 октября 2026) ---
# Различающая способность: одна и та же правка отбивается или проходит по ОДНОМУ свойству —
# есть ли строка «Корень», есть ли рядом ROOTS.md, нов ли пункт.
RP="$TMP/rootproj"; mkdir -p "$RP"; printf '# ROOTS\n\n## R1 — тестовый корень\n' > "$RP/ROOTS.md"; RBL="$RP/BACKLOG.md"
printf '# BACKLOG\n\n### B1 ☐ [P2] старый, без корня\n**Проверка.** `false` → 0\n' > "$RBL"
redit() {  # redit <old> <new> → вывод хука на правке $RBL
    jq -cn --arg f "$RBL" --arg o "$1" --arg n "$2" \
        '{session_id:"sr", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' \
    | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null
}
OLD1=$'**Проверка.** `false` → 0\n'
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] новый без корня\n**Проверка.** `false` → 0\n')
denied "$OUT" && grep -q "B2" <<< "$OUT" && grep -q "Корень" <<< "$OUT" && ok || bad "T19" "новый пункт без корня рядом с ROOTS.md прошёл: $OUT"
grep -q '"kind":"rootless"' "$STATE"/backlog-open-write-fired-sr.jsonl 2>/dev/null && ok || bad "T19b" "отказ не записан в журнал видом rootless"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] новый с корнем\n**Корень.** R1\n**Проверка.** `false` → 0\n')
assert_silent "$OUT" "T20 новый пункт с корнем отбит"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] задача\n**Корень.** не дефект — новая возможность\n**Проверка.** `false` → 0\n')
assert_silent "$OUT" "T21 «не дефект» отбит"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] разбор\n**Корень.** Не в критерии, а в его входе\n**Проверка.** `false` → 0\n')
denied "$OUT" && grep -qF "B2 («Не — …» — не корень)" <<< "$OUT" && ok || bad "T21d" "«Не …» с заглавной (отрицание в разборе) принят за «не дефект»: $OUT"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] без разбора\n**Корень.** не разобран — позже\n**Проверка.** `false` → 0\n')
denied "$OUT" && grep -qF "B2 («не — …» — не корень)" <<< "$OUT" && ok || bad "T21e" "«не разобран — …» принят за «не дефект»: $OUT"
# Карточка — по форме владельца карты (root-map.py, `HEAD`): «##  R7 — …» — карточка, «## R8 - …» — нет.
printf '\n##  R7 — два пробела\n**Признак.** —\n\n## R8 - дефис\n**Признак.** —\n' >> "$RP/ROOTS.md"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] корень R7\n**Корень.** R7\n**Проверка.** `false` → 0\n')
assert_silent "$OUT" "T20c «##  R7 — …» отбит, хотя владелец карты видит карточку"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] корень R8\n**Корень.** R8\n**Проверка.** `false` → 0\n')
denied "$OUT" && grep -qF "корня R8 нет в ROOTS.md" <<< "$OUT" && ok || bad "T20d" "«## R8 - …» принят карточкой, хотя владелец карты её не видит: $OUT"
# D1020: судится ЗНАЧЕНИЕ корня, а не наличие строки. Пары к T20 и T21 — одно свойство меняется.
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] новый, корень вне карты\n**Корень.** R9\n**Проверка.** `false` → 0\n')
denied "$OUT" && grep -qF "B2 (корня R9 нет в ROOTS.md)" <<< "$OUT" && ok || bad "T20b" "корень вне карты принят: $OUT"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] новый без разбора\n**Корень.** нет — разбор не проводился\n**Проверка.** `false` → 0\n')
denied "$OUT" && grep -qF "B2 («нет — …» — не корень)" <<< "$OUT" && ok || bad "T21b" "«нет — разбор не проводился» принят корнем: $OUT"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] новый с догадкой\n**Корень.** гипотеза — может быть, R3\n**Проверка.** `false` → 0\n')
denied "$OUT" && grep -qF "B2 («гипотеза — …» — не корень)" <<< "$OUT" && ok || bad "T21c" "«гипотеза» принята корнем: $OUT"
OUT=$(redit "старый, без корня" "старый, переименован")
assert_silent "$OUT" "T22 правка СТАРОГО пункта без корня отбита — страж судит только новые"
mv "$RP/ROOTS.md" "$RP/ROOTS.off"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] новый без корня\n**Проверка.** `false` → 0\n')
assert_silent "$OUT" "T23 без карты корней пункт без корня отбит"
mv "$RP/ROOTS.off" "$RP/ROOTS.md"
# T24: путь подачи задним числом (`bash-write-dispatch.sh`, D492) — файл уже записан командой,
# прежняя редакция — закоммиченная; отказать нельзя, называется.
git -C "$RP" init -q && git -C "$RP" add -A && git -C "$RP" -c user.name=t -c user.email=t@t commit -qm init
printf '\n### B3 ☐ [P2] записан командой без корня\n**Проверка.** `false` → 0\n' >> "$RBL"
OUT=$(jq -cn --arg f "$RBL" --rawfile c "$RBL" \
        '{hook_event_name:"PostToolUse", session_id:"sd", tool_name:"Write", cwd:"", tool_input:{file_path:$f, content:$c}}' \
      | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
grep -q "Записано командой" <<< "$OUT" && grep -q "B3" <<< "$OUT" && ok || bad "T24" "подача задним числом не назвала пункт без корня: $OUT"
# Имя диспетчера собрано из частей: T24b его ЧИТАЕТ, а не исполняет. Буквальное имя реестр родов
# (род M) принимал за путь, которым песочница теста доходит до механизма с исключением `*/tmp/*`.
_disp="bash-write""-dispatch.sh"
grep -q "backlog-open-write-guard.sh" "$HOOKS_DIR/$_disp" && ok || bad "T24b" "страж выпал из списка диспетчера записи командой"
# --- T25–T32: закрытие защитного слоя — после скептика (D1137, решение владельца 26 октября 2026) ---
# Одна и та же правка ◐ → ☑ отбивается или проходит по ОДНОМУ свойству: строка «Скептик.» с opus, путь в `hooks/`
# (не `hooks/tests/`), каталог `hooks/` в корне бэклога, метка (☑, а не ⊘), закрытие именно этой правкой.
SP="$TMP/skepproj"; mkdir -p "$SP/hooks"; SBL="$SP/BACKLOG.md"
SK_RET='  **Проверка возврата:** решение — пункт описывает наличный дефект, возврат наступает, когда за него берутся.'
sitem() {  # sitem <метка> <id> <адрес> [строка-скептика] — блок пункта; закрытый несёт показание
    printf '%s\n' "- $1 **$2** дефект" "  **Повод.** $3 пропускает запись." '  **Корень.** R5 — объявление без проверки.' '  **Проверка.** `true` → 0'
    case "$1" in ☑|⊘) printf '%s\n' '  **Показание.** «Проверка» 0 (до — 1).'; [ -n "${4:-}" ] && printf '%s\n' "$4" ;; *) printf '%s\n' "$SK_RET" ;; esac
}
sclose() {  # sclose <каталог> <id> <адрес> <метка> [строка-скептика] → вывод хука на правке ◐ → <метка>
    local bl="$1/BACKLOG.md"; { printf '%s\n\n' '# BACKLOG'; sitem ◐ "$2" "$3"; } > "$bl"
    jq -cn --arg f "$bl" --arg o "$(sitem ◐ "$2" "$3")" --arg n "$(sitem "$4" "$2" "$3" "${5:-}")" \
        '{session_id:"sk", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' \
    | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null
}
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑)
denied "$OUT" && grep -q "до финального скептика: S1" <<< "$OUT" && ok || bad "T25" "закрытие пункта с адресом в hooks/ без «Скептик.» прошло: $OUT"
grep -q '"item":"S1","kind":"noskeptic"' "$STATE"/backlog-open-write-fired-sk.jsonl 2>/dev/null && ok || bad "T25a" "отказ не записан в журнал видом noskeptic"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик.** opus, a1b2c3..d4e5f6, находки H/M — нет.')
assert_silent "$OUT" "T25b закрытие со строкой «Скептик.» opus отбито"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик.** нет — не запускался.')
denied "$OUT" && grep -q "S1" <<< "$OUT" && ok || bad "T25c" "«Скептик. нет» принят скептиком (значение, а не наличие — урок D1020): $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик.** sonnet, промежуточный.')
denied "$OUT" && ok || bad "T25d" "скептик не opus принят финальным: $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  Скептик. opus — без жирной метки, в прозе.')
denied "$OUT" && ok || bad "T25e" "упоминание скептика в прозе принято строкой «Скептик.»: $OUT"
OUT=$(sclose "$SP" S2 '`hooks/tests/fixtures/probe_D1.sh:3`' ☑)
assert_silent "$OUT" "T26 пункт только с адресом в hooks/tests/ отбит"
OUT=$(sclose "$SP" S2 '`scripts/report.sh:5`' ☑)
assert_silent "$OUT" "T26b пункт с адресом в scripts/ отбит"
OUT=$(sclose "$SP" S2 '`web/src/hooks/usePay.ts:9` и `~/.claude/hooks/state/x.jsonl`' ☑)
assert_silent "$OUT" "T26c src/hooks/ (React) и ~/.claude/hooks/state/ приняты защитным слоем"
NP="$TMP/nohooks"; mkdir -p "$NP"
OUT=$(sclose "$NP" S3 '`hooks/usePayouts.ts:193`' ☑)
assert_silent "$OUT" "T27 закрытие в дереве без каталога hooks/ в корне отбито"
OUT=$(sclose "$SP" S4 '`hooks/x-guard.sh:10`' ⊘)
assert_silent "$OUT" "T29 ⊘ (снят — не починка) отбит"
# T28: пункт, рождённый закрытым, — тоже закрытие этой правкой.
printf '%s\n\n' '# BACKLOG' > "$SBL"
OUT=$(jq -cn --arg f "$SBL" --arg c "$(printf '%s\n\n' '# BACKLOG'; sitem ☑ S5 '`hooks/lib/y.py:1`')" \
        '{session_id:"sk", tool_name:"Write", tool_input:{file_path:$f, content:$c}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
denied "$OUT" && grep -q "S5" <<< "$OUT" && ok || bad "T28" "пункт, рождённый закрытым без «Скептик.», прошёл: $OUT"
# T30: пункт, уже закрытый в прежней редакции, не судится при правке.
{ printf '%s\n\n' '# BACKLOG'; sitem ☑ S6 '`hooks/x-guard.sh:10`'; } > "$SBL"
OUT=$(jq -cn --arg f "$SBL" --arg o "**S6** дефект" --arg n "**S6** дефект, переименован" \
        '{session_id:"sk", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
assert_silent "$OUT" "T30 правка пункта, закрытого до неё, отбита"
# T31: большой блок (вывод путей больше буфера канала). Конвейер в `grep -q` под pipefail давал бы 141 и пропуск.
BIG=$(awk 'BEGIN { for (i = 0; i < 6000; i++) printf "`hooks/a%d.sh:1` ", i }')
OUT=$(sclose "$SP" S7 "$BIG" ☑)
denied "$OUT" && grep -q "S7" <<< "$OUT" && ok || bad "T31" "закрытие пункта с большим блоком без «Скептик.» прошло (141 под pipefail?)"
# T32: подача задним числом (`bash-write-dispatch.sh`, D492) — прежняя редакция закоммиченная; называется.
{ printf '%s\n\n' '# BACKLOG'; sitem ◐ S8 '`hooks/x-guard.sh:10`'; } > "$SBL"
git -C "$SP" init -q && git -C "$SP" add -A && git -C "$SP" -c user.name=t -c user.email=t@t commit -qm init
{ printf '%s\n\n' '# BACKLOG'; sitem ☑ S8 '`hooks/x-guard.sh:10`'; } > "$SBL"
OUT=$(jq -cn --arg f "$SBL" --rawfile c "$SBL" \
        '{hook_event_name:"PostToolUse", session_id:"sk", tool_name:"Write", cwd:"", tool_input:{file_path:$f, content:$c}}' \
      | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
grep -q "Записано командой" <<< "$OUT" && grep -q "S8" <<< "$OUT" && ok || bad "T32" "закрытие командой без «Скептик.» не названо: $OUT"
# T33–T42: находки финального скептика D1137 (M1, L1, выжившие мутации M01, M06, M09, M14, M15, M24, M25).
: > "$SP/hooks/real-guard.sh"
OUT=$(sclose "$SP" S9 '`real-guard.sh:5`' ☑)
denied "$OUT" && grep -q "S9" <<< "$OUT" && ok || bad "T33" "голое имя файла из hooks/ не названо защитным слоем (M1): $OUT"
OUT=$(sclose "$SP" S9 '`./hooks/real-guard.sh:5`' ☑)
denied "$OUT" && ok || bad "T33b" "./hooks/… не названо защитным слоем (M1): $OUT"
OUT=$(sclose "$SP" S9 '`ghost-guard.sh:5`' ☑)
assert_silent "$OUT" "T33c имя без файла в hooks/ принято защитным слоем"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик.** нет — opus не запускался.')
denied "$OUT" && ok || bad "T34" "«Скептик. нет — opus не запускался» принят (L1): $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10` (opus назвал его сам)' ☑ '  **Скептик.** sonnet, промежуточный.')
denied "$OUT" && ok || bad "T35" "opus в другой строке блока засчитан строке скептика (M14): $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  Итог: **Скептик.** opus, посреди строки.')
denied "$OUT" && ok || bad "T36" "«Скептик.» посреди строки засчитан (M01): $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик** opus, без точки.')
denied "$OUT" && ok || bad "T37" "«Скептик» без точки засчитан (M24): $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ $'  Итог: **Скептик.** упомянут в прозе.\n  **Скептик.** opus, коммиты a1..b2, находки H/M — нет.')
assert_silent "$OUT" "T36b строка «Скептик.» за упоминанием в прозе не засчитана (якорь строки выбрал не ту, M01)"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ $'  **Скептик** без точки — черновик.\n  **Скептик.** opus, коммиты a1..b2, находки H/M — нет.')
assert_silent "$OUT" "T37b строка «Скептик.» за черновиком без точки не засчитана (M24)"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик.** Opus (26 октября), коммиты a1..b2, находки H/M — нет.')
assert_silent "$OUT" "T42 «Скептик. Opus …» с заглавной отбит"
{ printf '%s\n\n' '# BACKLOG'; sitem ⊘ S10 '`hooks/x-guard.sh:10`'; } > "$SBL"
OUT=$(jq -cn --arg f "$SBL" --arg o "- ⊘ **S10**" --arg n "- ☑ **S10**" \
        '{session_id:"sk", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
denied "$OUT" && grep -q "S10" <<< "$OUT" && ok || bad "T38" "переход ⊘ → ☑ без «Скептик.» прошёл (M06): $OUT"
{ printf '%s\n\n' '# BACKLOG'; sitem ☑ S110 '`hooks/x-guard.sh:10`'; printf '\n'; sitem ◐ S11 '`hooks/x-guard.sh:10`'; } > "$SBL"
OUT=$(jq -cn --arg f "$SBL" --arg o "- ◐ **S11**" --arg n "- ☑ **S11**" \
        '{session_id:"sk", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
denied "$OUT" && grep -q "скептика: S11" <<< "$OUT" && ok || bad "T39" "закрытие S11 принято за прежнее, потому что S110 уже ☑ (M15): $OUT"
OUT=$(sclose "$SP" S12 '`hooks/tests-helper.sh:1`' ☑)
denied "$OUT" && ok || bad "T40" "hooks/tests-helper.sh принят за hooks/tests/ (M09): $OUT"
OUT=$(sclose "$SP" S12 '`hooks/tests/fixtures/p.sh:1` и `hooks/x-guard.sh:10`' ☑)
denied "$OUT" && ok || bad "T41" "второй путь блока не судится, когда первый — hooks/tests/ (M25): $OUT"
# T43 (L6): диспетчер записи командой показывает первые 700 знаков причины — имена всех видов обязаны уложиться в них,
# даже когда впереди длинное пояснение вида «зелёная».
{ printf '%s\n\n' '# BACKLOG'; sitem ◐ S13 '`hooks/x-guard.sh:10`'; printf '\n%s\n%s\n%s\n' '- ☐ **S14** открытый' '  **Проверка.** `false` → 0' "$SK_RET"; } > "$SBL"
git -C "$SP" add -A && git -C "$SP" -c user.name=t -c user.email=t@t commit -qm s13
{ printf '%s\n\n' '# BACKLOG'; sitem ☑ S13 '`hooks/x-guard.sh:10`'; printf '\n%s\n%s\n%s\n' '- ☐ **S14** открытый' '  **Проверка.** `true` → 0' "$SK_RET"; } > "$SBL"
OUT=$(jq -cn --arg f "$SBL" --rawfile c "$SBL" \
        '{hook_event_name:"PostToolUse", session_id:"sk", tool_name:"Write", cwd:"", tool_input:{file_path:$f, content:$c}}' \
      | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
_cut=$(python3 -c 'import sys; print(sys.argv[1][:700])' "$OUT")
grep -q "S14" <<< "$_cut" && grep -q "до скептика: S13" <<< "$_cut" && ok || bad "T43" "имена пунктов не уложились в первые 700 знаков причины (L6): ${_cut:0:300}"
# T44–T54: второй круг скептика D1137 — выжившие мутации (Ma, Mb, Mc, Md, Mu, Mv, Me–Mg), L3 и L4.
mkdir -p "$SP/hooks/lib"; : > "$SP/hooks/lib/real-lib.sh"; : > "$SP/hooks/lib/real_tool.py"
OUT=$(sclose "$SP" S15 '`real-lib.sh:3`' ☑)
denied "$OUT" && ok || bad "T44" "голое имя файла из hooks/lib/ не названо защитным слоем (Ma): $OUT"
OUT=$(sclose "$SP" S15 '`real_tool.py:1`' ☑)
denied "$OUT" && ok || bad "T45" "имя .py из hooks/lib/ не названо защитным слоем (Mb): $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик.** opusfoo, не модель.')
denied "$OUT" && ok || bad "T46" "«opusfoo» засчитан за opus (Mc): $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик.** opus')
assert_silent "$OUT" "T47 голое «opus» в конце строки отбито (Md)"
OUT=$(sclose "$SP" S15 '`aaa-ghost.sh` и `real-guard.sh:5`' ☑)
denied "$OUT" && ok || bad "T48" "судится только первое по алфавиту имя (Mu): $OUT"
{ printf '%s\n\n' '# BACKLOG'; sitem ◐ S20 '`hooks/x-guard.sh:10`'; printf '\n'; sitem ◐ S21 '`hooks/x-guard.sh:10`'; } > "$SBL"
OUT=$(jq -cn --arg f "$SBL" --arg c "$(printf '%s\n\n' '# BACKLOG'; sitem ☑ S20 '`hooks/x-guard.sh:10`'; printf '\n'; sitem ☑ S21 '`hooks/x-guard.sh:10`')" \
        '{session_id:"sk", tool_name:"Write", tool_input:{file_path:$f, content:$c}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
grep -q "до скептика: S20 S21\." <<< "$OUT" && ok || bad "T49" "из двух закрытий одной правкой назван не каждый (Mv): $OUT"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] новый без корня\n**Проверка.** `false` → 0\n')
grep -q "Пункты: без корня: B2\." <<< "$OUT" && ok || bad "T50" "строка «Пункты:» без имени без корня (Me): $OUT"
OUT=$(redit "$OLD1" $'**Проверка.** `false` → 0\n\n### B2 ☐ [P2] корень вне карты\n**Корень.** R9\n**Проверка.** `false` → 0\n')
grep -q "Пункты: корень не из карты: B2 " <<< "$OUT" && ok || bad "T50b" "строка «Пункты:» без имени корня не из карты (Mf): $OUT"
XP="$TMP/splitproj"; mkdir -p "$XP"
printf '%s\n' '# BACKLOG' '' '- ☐ **X1** первый' '  **Проверка.** `false` → 0' '  **Показание.** строка только у X1' > "$XP/BACKLOG.md"
OUT=$(jq -cn --arg f "$XP/BACKLOG.md" --arg o $'  **Проверка.** `false` → 0\n  **Показание.** строка только у X1' \
        --arg n $'  **Проверка.** `false` → 0\n- ☐ **X2** вписан внутрь\n  **Проверка.** `false` → 0\n  **Показание.** строка только у X1' \
        '{session_id:"sk", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
grep -q "Пункты: раскол: X2\." <<< "$OUT" && ok || bad "T50c" "строка «Пункты:» без имени раскола (Mg): $OUT"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ $'  **Скептик.** sonnet, промежуточный.\n  **Скептик.** opus, коммиты a1..b2, находки H/M — нет.')
assert_silent "$OUT" "T51 промежуточная строка перед финальной отбила закрытие (L3)"
OUT=$(sclose "$SP" S1 '`hooks/x-guard.sh:10`' ☑ '  **Скептик.** opus4, коммиты a1..b2.')
assert_silent "$OUT" "T52 «opus4» отбит (L3)"
OUT=$(sclose "$SP" S15 '`hooks/tests/real-lib.sh:2`' ☑)
assert_silent "$OUT" "T53 hooks/tests/<имя из hooks/lib> принят защитным слоем (L4)"
OUT=$(sclose "$SP" S15 'все `hooks/*.sh`' ☑)
denied "$OUT" && ok || bad "T54 " "упоминание hooks/*.sh не названо защитным слоем (L4): $OUT"
# T55–T55d (D1141): бэклог узнаётся ФАЙЛОМ, а не формой имени. `backlog.md` — тот же файл (macOS — одно имя, Linux —
# жёсткая ссылка), `plan.md` — жёсткая ссылка под иным именем; другой файл с иным именем не судится.
CP="$TMP/caseproj"; mkdir -p "$CP"
printf '%s\n' '# BACKLOG' '' '- ☐ **C1** старый' '  **Проверка.** `false` → 0' > "$CP/BACKLOG.md"
[ "$CP/backlog.md" -ef "$CP/BACKLOG.md" ] || ln "$CP/BACKLOG.md" "$CP/backlog.md"; ln "$CP/BACKLOG.md" "$CP/plan.md"
printf '%s\n' '# ЗАМЕТКИ' '' '- ☐ **C1** старый' '  **Проверка.** `false` → 0' > "$CP/notes.md"
cedit() {  # cedit <имя файла> → вывод хука на вписывании нового открытого пункта с зелёной «Проверкой»
    jq -cn --arg f "$CP/$1" --arg o '- ☐ **C1** старый' --arg n "$(printf '%s\n' '- ☐ **C2** новый' '  **Проверка.** `true` → 0' '- ☐ **C1** старый')" \
        '{session_id:"sc", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null
}
OUT=$(cedit backlog.md); denied "$OUT" && grep -q "C2" <<< "$OUT" && ok || bad "T55" "правка бэклога по пути в другом регистре прошла (D1141): $OUT"
OUT=$(cedit plan.md); denied "$OUT" && ok || bad "T55b" "правка бэклога по жёсткой ссылке под иным именем прошла (D1141): $OUT"
OUT=$(cedit notes.md); assert_silent "$OUT" "T55c другой файл с иным именем судится как бэклог"
# T55d: подача задним числом по другому имени берёт прежнюю редакцию по КАНОНИЧЕСКОМУ имени: `git show HEAD:./backlog.md`
# в дереве git не найдётся, прежняя редакция опустеет, и неизменный зелёный пункт C3 судился бы как новый.
printf '%s\n' '- ☐ **C3** зелёный, давний' '  **Проверка.** `true` → 0' >> "$CP/BACKLOG.md"
git -C "$CP" init -q && git -C "$CP" add BACKLOG.md && git -C "$CP" -c user.name=t -c user.email=t@t commit -qm c
printf '%s\n' '- ☐ **C4** новый красный' '  **Проверка.** `false` → 0' >> "$CP/BACKLOG.md"
OUT=$(jq -cn --arg f "$CP/backlog.md" --rawfile c "$CP/BACKLOG.md" \
        '{hook_event_name:"PostToolUse", session_id:"sc", tool_name:"Write", cwd:"", tool_input:{file_path:$f, content:$c}}' \
      | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
assert_silent "$OUT" "T55d подача задним числом по другому имени судит давний пункт как новый"
# T55e (скептик D1141, L1): положительная сторона T55d — новый зелёный пункт, поданный задним числом по `backlog.md`,
# назван; без неё T55d молчала и на страже, вовсе не судящем подачу.
printf '%s\n' '- ☐ **C5** новый зелёный' '  **Проверка.** `true` → 0' >> "$CP/BACKLOG.md"
OUT=$(jq -cn --arg f "$CP/backlog.md" --rawfile c "$CP/BACKLOG.md" \
        '{hook_event_name:"PostToolUse", session_id:"sc", tool_name:"Write", cwd:"", tool_input:{file_path:$f, content:$c}}' \
      | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
grep -q "Записано командой" <<< "$OUT" && grep -q "C5" <<< "$OUT" && ! grep -q "C3" <<< "$OUT" && ok \
    || bad "T55e" "подача задним числом по backlog.md не назвала новый зелёный C5 либо назвала давний C3: $OUT"
# T55f (L2): бэклог записан в git под строчным именем — прежняя редакция находится и под ним, давний пункт не судится.
# На ФС с различием регистра `backlog.md` без BACKLOG.md рядом — другой файл, и нога молчит по иной причине.
LP="$TMP/lowerproj"; mkdir -p "$LP"
printf '%s\n' '# BACKLOG' '' '- ☐ **L1** зелёный, давний' '  **Проверка.** `true` → 0' > "$LP/backlog.md"
git -C "$LP" init -q && git -C "$LP" add backlog.md && git -C "$LP" -c user.name=t -c user.email=t@t commit -qm l
printf '%s\n' '- ☐ **L2** новый красный' '  **Проверка.** `false` → 0' >> "$LP/backlog.md"
OUT=$(jq -cn --arg f "$LP/backlog.md" --rawfile c "$LP/backlog.md" \
        '{hook_event_name:"PostToolUse", session_id:"sc", tool_name:"Write", cwd:"", tool_input:{file_path:$f, content:$c}}' \
      | STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
assert_silent "$OUT" "T55f бэклог в git под строчным именем — давний пункт судится как новый (L2)"
# --- T12: диск не тронут ни одним вызовом (страж только судит) ---
grep -q '^- ☐ \*\*D10\*\* красный открытый пункт, не меняется$' "$BL" && ok || bad "T12" "страж изменил файл на диске"
echo "backlog open write guard: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
