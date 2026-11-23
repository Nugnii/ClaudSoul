#!/usr/bin/env bash
# СУДИТ: lib/env-pin.jq install.sh uninstall.sh
# test_env_pin.sh — закрепление локали в env настроек ставится и снимается, не трогая чужого.
#
# Результат: `set` кладёт LC_NUMERIC=C и LC_COLLATE=C, сохраняя прочие ключи; запись хранит только
#            ЧУЖИЕ значения и обновляется каждой установкой; `unset` трогает только наше значение;
#            шаг установщика закрепляет во всех трёх ветках; цепочка «установка → снятие» на мире
#            владельца (закрепление без записи) закрепление снимает
# Проверка результата: bash hooks/tests/test_env_pin.sh даёт 0
#
# Повод — D1176: под ru_RU awk читает «1.5» как 1 и равняет «☐» и «◐». Установщик целиком в
# песочнице не прогнать (агенты launchd), поэтому шаг настроек ВЫРЕЗАЕТСЯ из живого install.sh —
# от подключения библиотеки замка до «--- 7. MCP-сервер» — и исполняется на поддельном доме с
# поддельным HOME. Вырезка без конечной метки не исполняется вовсе: `sed` напечатал бы файл до
# конца, и тест запустил бы разделы MCP и launchd (M2 второго круга скептика).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
J="$REPO/lib/env-pin.jq"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
[ -f "$J" ] || { echo "FAIL: нет $J"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
run() { jq -c --arg mode "$1" -f "$J"; }
rec() { jq -c --arg mode record --argjson prev "$2" -f "$J" <<< "$1"; }
uns() { jq -c --arg mode unset --argjson prev "$2" -f "$J" <<< "$1"; }

out=$(echo '{"model":"opus"}' | run set)
[ "$out" = '{"model":"opus","env":{"LC_NUMERIC":"C","LC_COLLATE":"C"}}' ] && ok || bad T1 "set без env: $out"
out=$(echo '{"env":{"A":"1","LC_NUMERIC":"ru_RU.UTF-8"}}' | run set)
[ "$out" = '{"env":{"A":"1","LC_NUMERIC":"C","LC_COLLATE":"C"}}' ] && ok || bad T2 "set поверх чужого значения: $out"
out=$(echo '{"env":{"A":"1","LC_NUMERIC":"C","LC_COLLATE":"ru_RU.UTF-8"}}' | run unset)
[ "$out" = '{"env":{"A":"1","LC_COLLATE":"ru_RU.UTF-8"}}' ] && ok || bad T3 "unset снял чужое значение или оставил своё: $out"
out=$(echo '{"model":"opus"}' | run set | run unset)
[ "$out" = '{"model":"opus"}' ] && ok || bad T4 "set → unset не вернул настройки без env: $out"
out=$(echo '{"env":"строка"}' | run unset)
[ "$out" = '{"env":"строка"}' ] && ok || bad T5 "unset над env не-объектом: $out"
if echo '{}' | run bogus >/dev/null 2>&1; then bad T6 "неизвестный режим принят кодом 0"; else ok; fi
if echo '{"env":[1]}' | run set >/dev/null 2>&1; then bad T8 "set над env-массивом прошёл"; else ok; fi
out=$(echo '{"env":{}}' | run unset)
[ "$out" = '{"env":{}}' ] && ok || bad T9 "unset удалил пустой env пользователя: $out"
out=$(echo '{"env":{"LC_COLLATE":"ru_RU.UTF-8","LC_NUMERIC":"C"}}' | jq -r --arg mode replaced -f "$J")
[ "$out" = 'LC_COLLATE=ru_RU.UTF-8' ] && ok || bad T11 "replaced: $out"

# Запись (второй круг): только чужие значения; своё «C» не записывается (H1); свежее чужое вытесняет старое (M1а).
out=$(rec '{"env":{"LC_NUMERIC":"C","LC_COLLATE":"C"}}' '{}')
[ "$out" = '{"values":{},"had_env":true}' ] && ok || bad R1 "закрепление без записи записано как прежнее: $out"
out=$(rec '{"env":{"LC_NUMERIC":"en_US.UTF-8","LC_COLLATE":"C"}}' '{"values":{"LC_NUMERIC":"ru_RU.UTF-8"},"had_env":true}')
[ "$out" = '{"values":{"LC_NUMERIC":"en_US.UTF-8"},"had_env":true}' ] && ok || bad R2 "свежее чужое не вытеснило старое: $out"
out=$(rec '{"env":"s"}' '{}')
[ "$out" = '{"values":{},"had_env":false}' ] && ok || bad R3 "env-строка: $out"
# Снятие: только наше значение; правка пользователя после установки остаётся (M1б); had_env решает судьбу пустого env (L4).
out=$(uns '{"env":{"LC_NUMERIC":"en_US.UTF-8","LC_COLLATE":"C"}}' '{"values":{"LC_NUMERIC":"ru_RU.UTF-8","LC_COLLATE":"ru_RU.UTF-8"},"had_env":true}')
[ "$out" = '{"env":{"LC_NUMERIC":"en_US.UTF-8","LC_COLLATE":"ru_RU.UTF-8"}}' ] && ok || bad U1 "правка пользователя затёрта либо чужое не вернулось: $out"
out=$(uns '{"env":{"LC_NUMERIC":"C","LC_COLLATE":"C"}}' '{"values":{},"had_env":true}')
[ "$out" = '{"env":{}}' ] && ok || bad U2 "пустой env пользователя удалён кругом установка→снятие: $out"
out=$(uns '{"env":{"LC_NUMERIC":"C","LC_COLLATE":"C"}}' '{"values":{},"had_env":false}')
[ "$out" = '{}' ] && ok || bad U3 "env, которого не было, остался: $out"

# Шаг установщика — вырезка из живого файла, только при обеих метках.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
STEP="$T/step.sh"
CUT=$(sed -n '/^STATE_LOCK_LIB="\$CLAUDSOUL_DIR\/hooks\/state-lock-lib.sh"$/,/^# --- 7\. MCP-сервер ---$/p' "$REPO/install.sh")
if [ "$(tail -n 1 <<< "$CUT")" != "# --- 7. MCP-сервер ---" ] || ! grep -q 'env-pin.jq' <<< "$CUT"; then
    bad T7 "вырезка шага настроек не ограничена метками или без шага закрепления — не исполняю"
    echo "env-pin tests: PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok
{
    printf 'set -euo pipefail\n'
    printf 'CLAUDSOUL_DIR=%q\nCLAUDE_HOME="$1"\nSETTINGS="$CLAUDE_HOME/settings.json"\n' "$REPO"
    printf 'info(){ echo "INFO $*"; }\nwarn(){ echo "WARN $*"; }\n'
    printf '%s\n' "HOOKS_CONFIG='{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"bash ~/.claude/hooks/x.sh\"}]}]}}'"
    printf '%s\n' "$CUT"
    printf 'echo STEP-END\n'
} > "$STEP"
step()   { local h="$T/$1"; mkdir -p "$h"; [ -n "${2:-}" ] && printf '%s\n' "$2" > "$h/settings.json"; HOME="$T/fakehome" bash "$STEP" "$h" 2>&1; }
pinned() { jq -e '.env.LC_NUMERIC == "C" and .env.LC_COLLATE == "C"' "$T/$1/settings.json" >/dev/null 2>&1; }
baks()   { find "$T/$1" -maxdepth 1 -name 'settings.json.bak.*' | wc -l | tr -d ' '; }
recf()   { jq -c . "$T/$1/claudsoul-env-prev.json" 2>/dev/null; }
said_ok() { grep -q 'INFO Локаль чисел и сравнений закреплена' <<< "$1" && ! grep -q 'не закреплена' <<< "$1"; }

o=$(step i1 '{"hooks":{"Stop":[]},"env":{"LC_NUMERIC":"ru_RU.UTF-8","A":"1"}}')
{ pinned i1 && said_ok "$o" && [ "$(jq -c '.env.A' "$T/i1/settings.json")" = '"1"' ] && [ "$(baks i1)" -ge 1 ] \
  && [ "$(recf i1)" = '{"values":{"LC_NUMERIC":"ru_RU.UTF-8"},"had_env":true}' ] \
  && grep -q 'WARN env: LC_NUMERIC=ru_RU.UTF-8 заменено' <<< "$o" && grep -q STEP-END <<< "$o"; } \
    && ok || bad I1 "ветка слияния: закрепление, слово, копия, запись чужого, слово о замене — $o"
o=$(step i2 '{"model":"opus"}')
{ pinned i2 && said_ok "$o" && [ "$(baks i2)" -ge 1 ] && [ "$(recf i2)" = '{"values":{},"had_env":false}' ]; } \
    && ok || bad I2 "ветка без .hooks: закрепление, слово, копия, запись — $o"
o=$(step i3 '')
{ pinned i3 && said_ok "$o" && jq -e '.hooks.Stop' "$T/i3/settings.json" >/dev/null 2>&1; } \
    && ok || bad I3 "ветка без файла: создан с хуками и закреплением — $o"
o=$(step i4 '{"hooks":{"Stop":[]},"env":"строка"}')
{ grep -q STEP-END <<< "$o" && grep -q 'WARN локаль чисел и сравнений не закреплена' <<< "$o" && [ "$(jq -c '.env' "$T/i4/settings.json")" = '"строка"' ]; } \
    && ok || bad I4 "env не объект: установщик обязан сказать и идти дальше — $o"
o=$(step i5 '{"hooks":{"Stop":[]},"env":{"LC_ALL":"ru_RU.UTF-8"}}')
grep -q 'WARN env: LC_ALL' <<< "$o" && ok || bad I5 "LC_ALL в env не назван — $o"
# I6 (M1а): повторная установка после правки пользователя — свежее чужое значение в записи.
jq '.env.LC_NUMERIC = "en_US.UTF-8"' "$T/i1/settings.json" > "$T/i1/s.tmp" && mv "$T/i1/s.tmp" "$T/i1/settings.json"
HOME="$T/fakehome" bash "$STEP" "$T/i1" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }
[ "$(recf i1)" = '{"values":{"LC_NUMERIC":"en_US.UTF-8"},"had_env":true}' ] \
    && ok || bad I6 "повторная установка не записала свежее чужое значение: $(recf i1)"

# I7 (H1): мир владельца — закрепление первого круга без записи; повторная установка, затем снятие.
STUB="$T/stub"; mkdir -p "$STUB"; printf '#!/bin/sh\nexit 0\n' > "$STUB/claude"; chmod +x "$STUB/claude"
H="$T/owner"; mkdir -p "$H/.claude"
printf '%s\n' '{"hooks":{"Stop":[]},"env":{"LC_NUMERIC":"C","LC_COLLATE":"C","MY":"1"}}' > "$H/.claude/settings.json"
HOME="$T/fakehome" bash "$STEP" "$H/.claude" >/dev/null 2>&1
o=$(HOME="$H" PATH="$STUB:$PATH" bash "$REPO/uninstall.sh" --apply 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(jq -c '.env' "$H/.claude/settings.json")" = '{"MY":"1"}' ] && [ ! -e "$H/.claude/claudsoul-env-prev.json" ]; } \
    && ok || bad I7 "мир владельца: закрепление пережило снятие — env $(jq -c '.env' "$H/.claude/settings.json"), код $rc"

# Третий круг скептика. I8 (M3): вторая установка без правок переносит чужое значение из прежней записи —
# сейчас на его месте наше «C», и без чтения записи оно бы пропало; снятие его возвращает.
H="$T/carry"; mkdir -p "$H/.claude"
printf '%s\n' '{"hooks":{"Stop":[]},"env":{"LC_NUMERIC":"ru_RU.UTF-8","MY":"1"}}' > "$H/.claude/settings.json"
HOME="$T/fakehome" bash "$STEP" "$H/.claude" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }; HOME="$T/fakehome" bash "$STEP" "$H/.claude" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }
HOME="$H" PATH="$STUB:$PATH" bash "$REPO/uninstall.sh" --apply >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }
[ "$(jq -c '.env' "$H/.claude/settings.json")" = '{"LC_NUMERIC":"ru_RU.UTF-8","MY":"1"}' ] \
    && ok || bad I8 "чужое значение не пережило вторую установку: env $(jq -c '.env' "$H/.claude/settings.json")"
# I9 (M3): env не было — две установки и снятие env не оставляют (had_env из прежней записи).
H="$T/noenv"; mkdir -p "$H/.claude"; printf '%s\n' '{"hooks":{"Stop":[]}}' > "$H/.claude/settings.json"
HOME="$T/fakehome" bash "$STEP" "$H/.claude" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }; HOME="$T/fakehome" bash "$STEP" "$H/.claude" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }
HOME="$H" PATH="$STUB:$PATH" bash "$REPO/uninstall.sh" --apply >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }
jq -e 'has("env") | not' "$H/.claude/settings.json" >/dev/null 2>&1 && ok || bad I9 "env, которого не было, остался после двух установок: $(jq -c '.env' "$H/.claude/settings.json")"
# I10 (M1, M2, L1): негодная запись (битая, прежнего вида) не перетирается, названа, возврат обещан только из .bak.
for bad_rec in '{"values":{"LC_NUMERIC":"ru_RU.UTF-8"},"had_env":tr' '{"LC_NUMERIC":"ru_RU.UTF-8"}'; do
    H="$T/badrec$RANDOM"; mkdir -p "$H"
    printf '%s\n' '{"hooks":{"Stop":[]},"env":{"LC_COLLATE":"ru_RU.UTF-8"}}' > "$H/settings.json"
    printf '%s\n' "$bad_rec" > "$H/claudsoul-env-prev.json"
    o=$(HOME="$T/fakehome" bash "$STEP" "$H" 2>&1)
    { [ "$(cat "$H/claudsoul-env-prev.json")" = "$bad_rec" ] && grep -q 'не читается — оставлена как есть' <<< "$o" \
      && grep -q 'только в копии settings.json.bak' <<< "$o" && pinned "${H#$T/}"; } \
        && ok || bad I10 "негодная запись «${bad_rec}» перетёрта или не названа — $o"
done
# D1 (L5): сухой прогон установщика называет запись чужих значений.
mkdir -p "$T/dryhome/.claude"   # установщик без ~/.claude выходит до списка
o=$(HOME="$T/dryhome" bash "$REPO/install.sh" --dry-run 2>&1)
grep -q 'claudsoul-env-prev.json' <<< "$o" && ok || bad D1 "сухой прогон не называет запись чужих значений"
# V (M2 третьего, M4 и L1 четвёртого круга): судья формы записи — у программы, вход — файл целиком (-s).
for good in '{"values":{"LC_NUMERIC":"ru_RU.UTF-8"},"had_env":true}' '{"values":{},"had_env":false}'; do
    jq -e -s --arg mode valid -f "$J" <<< "$good" >/dev/null 2>&1 && ok || bad V1 "годная запись отвергнута: $good"
done
for nogood in '{"LC_NUMERIC":"ru_RU.UTF-8"}' '{"values":[1],"had_env":true}' '{"values":{"A":1},"had_env":true}' \
              '{"values":{},"had_env":"да"}' '[]' '{}' '{"values":{}}' '{"x":1}
{"values":{},"had_env":true}'; do
    jq -e -s --arg mode valid -f "$J" <<< "$nogood" >/dev/null 2>&1 && bad V2 "негодная запись принята: $nogood" || ok
done
# K (M3 четвёртого круга): имена ключей программы — против независимого ожидания теста, а не против неё самой.
[ "$(echo null | jq -r --arg mode keys -f "$J" | sort | tr '\n' ' ')" = "LC_COLLATE LC_NUMERIC " ] \
    && ok || bad K1 "режим keys назвал не LC_COLLATE и LC_NUMERIC"
# I11 (M1): не-строковое значение нашего ключа не попадает в запись, названо, запись остаётся годной.
H="$T/nonstr"; mkdir -p "$H"
printf '%s\n' '{"hooks":{"Stop":[]},"env":{"LC_NUMERIC":1,"MY":"1"}}' > "$H/settings.json"
o=$(HOME="$T/fakehome" bash "$STEP" "$H" 2>&1); o2=$(HOME="$T/fakehome" bash "$STEP" "$H" 2>&1)
{ grep -q 'LC_NUMERIC=1 — не строка' <<< "$o" && grep -q 'только в копии settings.json.bak' <<< "$o" \
  && ! grep -q 'не читается' <<< "$o2" && jq -e -s --arg mode valid -f "$J" "$H/claudsoul-env-prev.json" >/dev/null 2>&1; } \
    && ok || bad I11 "не-строка: $o | $o2"
# I12 (M2, L2): ключ, удалённый пользователем, и env, удалённый целиком, снятием не воскресают.
for edit in 'del(.env.LC_NUMERIC)' 'del(.env)'; do
    H="$T/gone$RANDOM"; mkdir -p "$H/.claude"
    printf '%s\n' '{"hooks":{"Stop":[]},"env":{"LC_NUMERIC":"ru_RU.UTF-8","MY":"1"}}' > "$H/.claude/settings.json"
    HOME="$T/fakehome" bash "$STEP" "$H/.claude" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }
    jq "$edit" "$H/.claude/settings.json" > "$H/s" && mv "$H/s" "$H/.claude/settings.json"
    HOME="$T/fakehome" bash "$STEP" "$H/.claude" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }
    HOME="$H" PATH="$STUB:$PATH" bash "$REPO/uninstall.sh" --apply >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_env_pin.sh:$LINENO" >&2; exit 1; }
    jq -e '(.env // {}) | has("LC_NUMERIC") | not' "$H/.claude/settings.json" >/dev/null 2>&1 \
        && ok || bad I12 "после «${edit}» снятие воскресило LC_NUMERIC: $(jq -c '.env' "$H/.claude/settings.json")"
done
# I13 (L4): сбой записи (jq, отказывающий только режиму record) назван, возврат обещан только из .bak.
FJ="$T/fakejq"; mkdir -p "$FJ"; REALJQ=$(command -v jq)
printf '#!/bin/sh\ncase "$*" in *"mode record"*) exit 5 ;; esac\nexec %s "$@"\n' "$REALJQ" > "$FJ/jq"; chmod +x "$FJ/jq"
H="$T/wfail"; mkdir -p "$H"; printf '%s\n' '{"hooks":{"Stop":[]},"env":{"LC_COLLATE":"ru_RU.UTF-8"}}' > "$H/settings.json"
o=$(HOME="$T/fakehome" PATH="$FJ:$PATH" bash "$STEP" "$H" 2>&1)
{ grep -q 'запись чужих значений env не обновлена' <<< "$o" && grep -q 'только в копии settings.json.bak' <<< "$o" && pinned wfail; } \
    && ok || bad I13 "сбой записи не назван или возврат обещан ложно — $o"

echo "env-pin tests: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
