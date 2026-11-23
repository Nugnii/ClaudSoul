#!/usr/bin/env bash
# СУДИТ: hooks/tool-gate-check.sh
# test_tool_gate_check.sh — прибор ловит вызов инструмента без гейта и печать отказа на Stop.
#
# Результат: оба признака ловят своего носителя и не ловят своих контрпримеров
# Проверка результата: bash hooks/tests/test_tool_gate_check.sh даёт 0
#
# Положительный контроль берётся из ИСТОРИИ, а не из фикстуры: носитель обоих признаков уже
# починен, и в живом дереве его нет. Прибор, не поймавший ни одного носителя, неотличим от
# сломанного, поэтому ноги T2/T3 гоняют редакцию `edc441c^:hooks/carrier-growth-check.sh` —
# ту самую, что дала восемь пустых ходов 7 сентября 2026.
#
# Путь прибора переопределяется РАДИ МУТАЦИИ (образец — test_drift_check.sh): зелень без
# мутационного контроля не доказывает ничего, кроме того, что прибор молчит.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
CHECK="${TOOL_GATE_CHECK:-$ROOT/hooks/tool-gate-check.sh}"
[ -f "$CHECK" ] || { echo "SKIP: нет $CHECK"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# sandbox <имя> — каталог hooks/ с прибором внутри и своим settings.json
sandbox() {
    _s="$TMP/$1"; mkdir -p "$_s/hooks"
    cp "$CHECK" "$_s/hooks/tool-gate-check.sh"
    printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/%s"}]}]}}' \
        "${2:-carrier-growth-check.sh}" > "$_s/settings.json"
    printf '%s' "$_s"
}
# probe <песочница> [файл настроек] — печатает выхлоп, код кладёт в RC
probe() {
    OUTP=$(TOOL_GATE_DIR="$1/hooks" CLAUDE_SETTINGS="${2:-$1/settings.json}" \
           bash "$1/hooks/tool-gate-check.sh" --check 2>&1); RC=$?
    printf '%s' "$OUTP"
}
row() { printf '%s\n' "$OUTP" | awk -F'|' -v n="$1" 'NR==n'; }
# Утверждения о СРАБАТЫВАНИИ названы явной функцией, а не веткой case: мета-тест
# test_guards_provable ищет именно их, и страж, у которого проверяется только тишина,
# прошёл бы и пустым файлом. Заодно текст ноги читается как утверждение, а не как разбор.
assert_contains() { case "$1" in *"$2"*) ok ;; *) bad "$3" "нет «$2» в: ${1:0:160}" ;; esac; }
# Пара к предыдущей: страж, который горит ВСЕГДА, бесполезен ровно так же, как молчащий.
assert_empty()    { if [ -z "$1" ]; then ok; else bad "$2" "ожидалась тишина, получено: ${1:0:160}"; fi; }
fld() { printf '%s\n' "$OUTP" | awk -F'|' -v n="$1" -v f="$2" 'NR==n{print $f}'; }

HIST="$TMP/hist.sh"
git -C "$ROOT" show 'edc441c^:hooks/carrier-growth-check.sh' > "$HIST" 2>/dev/null \
    || { echo "SKIP: историческая редакция недоступна"; exit 0; }

# --- T1: живое дерево — обе строки судят НЕПУСТОЙ знаменатель ---
# Зелень при нуле сравнений это не «чисто», а сломанная проверка (правило drift-check).
S1=$(sandbox live); rm -f "$S1/hooks"/*.sh; cp "$ROOT"/hooks/*.sh "$S1/hooks/"
cp "$HOME/.claude/settings.json" "$S1/settings.json" 2>/dev/null || true
probe "$S1" >/dev/null
[ "$(fld 1 3)" -gt 0 ] 2>/dev/null && ok || bad "T1" "признак 1 судил ноль единиц: $(row 1)"
[ "$(fld 2 3)" -gt 0 ] 2>/dev/null && ok || bad "T1b" "признак 2 судил ноль единиц: $(row 2)"
[ "$RC" = "0" ] && ok || bad "T1c" "живое дерево не чисто (rc=$RC): $OUTP"

# --- T2/T3: ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ на редакции, давшей инцидент ---
S2=$(sandbox hist); cp "$HIST" "$S2/hooks/carrier-growth-check.sh"
probe "$S2" >/dev/null
assert_contains "$(row 1)" "NOGATE" "T2: признак 1 не поймал исторического носителя"
assert_contains "$(row 1)" "carrier-growth-check.sh:" "T2b: носитель не назван адресом"
assert_contains "$(row 2)" "STOPLOOP" "T3: признак 2 не поймал исторического носителя"
assert_contains "$(row 2)" "carrier-growth-check.sh:" "T3c: носитель не назван адресом"
[ "$RC" = "1" ] && ok || bad "T3b" "носители есть, а код $RC (ожидался 1)"

# --- T4: ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ — нынешняя редакция того же файла ---
S4=$(sandbox fixed); cp "$ROOT/hooks/carrier-growth-check.sh" "$S4/hooks/"
probe "$S4" >/dev/null
case "$(row 1)" in OK*) ok ;; *) bad "T4" "починенный файл назван носителем: $(row 1)" ;; esac
case "$(row 2)" in OK*) ok ;; *) bad "T4b" "починенный файл назван носителем: $(row 2)" ;; esac

# --- T5: три механизма отказа признака 2, каждый своей ногой ---
# Тормоз stop_hook_active; печать НЕ из ветки отказа; событие в переменной.
for pair in "timestamp-canary-check.sh:тормоз" "carrier-growth-check.sh:не-отказ" "output-language-check.sh:переменная"; do
    _f="${pair%%:*}"; _why="${pair#*:}"
    S5=$(sandbox "neg-$_f" "$_f"); cp "$ROOT/hooks/$_f" "$S5/hooks/" 2>/dev/null || continue
    probe "$S5" >/dev/null
    case "$(row 2)" in OK*) ok ;; *) bad "T5/$_why" "ложный носитель ($_f): $(row 2)" ;; esac
done

# --- T6: КОНТРПРИМЕР по каналу — настоящая ветка отказа, но не additionalContext ---
# Признак обязан различать КАНАЛ, а не «любой Stop-хук, который что-то печатает при отказе».
S6=$(sandbox chan "install-drift-notice.sh"); cp "$ROOT/hooks/install-drift-notice.sh" "$S6/hooks/"
probe "$S6" >/dev/null
case "$(row 2)" in OK*) ok ;; *) bad "T6" "очередь принята за additionalContext: $(row 2)" ;; esac

# --- T7: нет settings.json — признак 2 BROKEN, а признак 1 всё равно судит ---
# Один ослепший глаз не имеет права ослеплять второй.
S7=$(sandbox nosettings); cp "$HIST" "$S7/hooks/carrier-growth-check.sh"
probe "$S7" "$TMP/нет-такого-файла.json" >/dev/null
case "$(row 2)" in BROKEN*) ok ;; *) bad "T7" "без settings.json признак 2 не BROKEN: $(row 2)" ;; esac
case "$(row 1)" in NOGATE*) ok ;; *) bad "T7b" "признак 1 ослеп заодно: $(row 1)" ;; esac
[ "$RC" = "2" ] && ok || bad "T7c" "BROKEN дал код $RC (ожидался 2)"

# --- T8: МУТАЦИОННЫЙ КОНТРОЛЬ — прибор обязан краснеть на собственной порче ---
# Мутации АДРЕСНЫЕ, по устройству признака, а не сплошные по тексту. Первая редакция ноги
# заменяла слово stop_hook_active во всём файле — вместе с признаком менялась и КАНАРЕЙКА,
# фикстура и правило соглашались друг с другом, и мутант оставался зелёным. Цена того, что
# фикстуры живут в одном файле с правилом (это решение: файл-фикстура способен разойтись с
# прибором молча): проверять его можно только точечной порчей.
for mut in "s|(scripts\|bin\|tools)|(zzz)|:1" "s|if (f in brake) continue|if (0) continue|:2"; do
    _sed="${mut%:*}"; _rown="${mut##*:}"
    M="$TMP/mutant$_rown.sh"; sed "$_sed" "$CHECK" > "$M"; chmod +x "$M"
    S8=$(sandbox "mut$_rown"); cp "$HIST" "$S8/hooks/carrier-growth-check.sh"; cp "$M" "$S8/hooks/tool-gate-check.sh"
    probe "$S8" >/dev/null
    case "$(row "$_rown")" in
        BROKEN*"положительный контроль"*) ok ;;
        *) bad "T8/$_rown" "мутант не покраснел — канарейка не держит: $(row "$_rown")" ;;
    esac
done

# --- T9: ABSENT — дерево без единого вызова инструмента по корню ---
# Ноль ЕДИНИЦ это честное «вопрос не стоит», а не отказ и не «чисто».
# Сканируемый каталог отделён от каталога прибора: иначе прибор судит САМ СЕБЯ — строка его
# канарейки с путём вида корень/scripts/файл есть законная единица его собственного универсума
# (рядом стоит гейт, носителем она не становится), и «дерева без вызовов» с ней не построить.
S9=$(sandbox absent); mkdir -p "$TMP/absent-only"
printf '#!/usr/bin/env bash\necho nothing\n' > "$TMP/absent-only/plain.sh"
OUTP=$(TOOL_GATE_DIR="$TMP/absent-only" CLAUDE_SETTINGS="$S9/settings.json" \
       bash "$CHECK" --check 2>&1); RC=$?
case "$(row 1)" in ABSENT*) ok ;; *) bad "T9" "дерево без вызовов не ABSENT: $(row 1)" ;; esac

# --- T10: неизвестный аргумент — отказ кодом 2, а не молчаливая работа ---
bash "$CHECK" --нет-такого >/dev/null 2>&1; RCA=$?
[ "$RCA" = "2" ] && ok || bad "T10" "неизвестный аргумент дал $RCA (ожидался 2)"

# --- T11: --check не читает stdin и не виснет ---
# Эвристика «есть ли tty» однажды повесила раннер (case-2026-07-25); здесь режим решает аргумент.
( TOOL_GATE_DIR="$S4/hooks" CLAUDE_SETTINGS="$S4/settings.json" bash "$CHECK" --check >/dev/null 2>&1 ) </dev/null &
WPID=$!
for _ in $(seq 1 100); do kill -0 "$WPID" 2>/dev/null || break; sleep 0.05; done
if kill -0 "$WPID" 2>/dev/null; then kill "$WPID" 2>/dev/null; bad "T11" "--check завис на закрытом stdin"; else ok; fi

# --- T12: хук-режим молчит на файле ВНЕ hooks/ ---
OUT12=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo/bar.sh"}}' | bash "$CHECK" 2>&1)
assert_empty "$OUT12" "T12: хук заговорил о файле вне hooks/"

# --- T13: хук-режим на носителе — называет адрес ---
OUT13=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/hooks/carrier-growth-check.sh"}}' "$S2" \
        | CLAUDE_SETTINGS="$S2/settings.json" bash "$CHECK" 2>&1)
assert_contains "$OUT13" "additionalContext" "T13: хук-режим промолчал о носителе"
assert_contains "$OUT13" "carrier-growth-check.sh:" "T13b: хук-режим не назвал адрес"

# --- T14: хук-режим БЕЗ settings.json — ТИШИНА, а не «НЕ ПРОВЕРЕНО» ---
# Нога прямо против дефекта, ради которого прибор и написан: «настроек нет» — состояние
# ПОСТОЯННОЕ, и доклад о нём на каждой правке был бы вечным фоном.
OUT14=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/hooks/carrier-growth-check.sh"}}' "$S4" \
        | CLAUDE_SETTINGS="$TMP/нет.json" bash "$CHECK" 2>&1)
assert_empty "$OUT14" "T14: без настроек хук заговорил о ПОСТОЯННОМ состоянии"

echo "tool gate check: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
