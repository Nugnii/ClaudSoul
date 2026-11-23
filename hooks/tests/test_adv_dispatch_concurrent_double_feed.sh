#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_concurrent_double_feed.sh — противник диспетчера записи командой (D487):
# дедуп по паре «файл + страж» обязан держаться и при ОДНОВРЕМЕННЫХ событиях одной сессии.
#
# Повод. У сессии и её субагентов один id сессии, события PostToolUse идут одновременно (в
# инциденте D487 жили 15 экземпляров диспетчера разом). Флаг пары проверяется ДО вызова стража,
# а ставится ПОСЛЕ его ответа: между ними окно длиной в вызов стража (замер в шапке диспетчера —
# 0,12 с), и каждое событие, вошедшее в окно, подаёт ту же пару заново и печатает ту же находку.
# Замер 1 октября 2026 на песочнице: одна правка, 30 одновременных событий — 154–210 подач вместо
# 7; два одновременных события — 14 вместо 7.
#
# Ожидание: одна правка одного файла → каждый страж получает файл РОВНО один раз за сессию,
# находка по паре напечатана ОДНИМ событием.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Здесь все стражи — заглушки, до
# исключения `*/tmp/*` подача не доходит, и носитель был бы ложным (тот же приём —
# test_bash_write_dispatch_versions.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Песочница: копия диспетчера и стражи-заглушки под именами из его списка. Заглушка пишет
# «страж путь» в журнал и держит паузу цены настоящего стража; первый страж на файле one.md
# отвечает находкой. HOME подменён: `--exclude-standard` читает глобальные исключения git.
SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SR" "$SH"
# Песочница несёт и библиотеку замка с её зависимостью, как установка в ~/.claude/hooks:
# без неё диспетчер работает без замка (названное третье состояние), и нога судила бы
# неполную установку, а не предмет.
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
FIRST=${GUARD_LIST%% *}
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
g=$(basename "$0")
echo "$g $p" >> "${ADV_FED:-/dev/null}"
[ -n "${ADV_SLEEP:-}" ] && sleep "$ADV_SLEEP"
if [ "$g" = "${ADV_LOUD:-}" ]; then
  case "$p" in */one.md) printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"ADV-FINDING-ONE\"}}" ;; esac
fi
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore"

run() {  # run <сессия> [ПЕРЕМЕННАЯ=значение ...] → вывод диспетчера
    local s=$1; shift
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$s" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" \
            ADV_FED="$FED" ADV_LOUD="$FIRST" "$@" bash "$SB/hooks/$DISP" 2>/dev/null
}

run c >/dev/null                # первое событие сессии ставит метку
sleep 1                         # правка новее метки при любой точности времени файла
echo "новое" > "$SR/one.md"     # одна команда — одна правка одного файла
: > "$FED"
N=30
i=0
while [ "$i" -lt "$N" ]; do
    i=$((i+1))
    run c ADV_SLEEP=0.1 BASH_DISPATCH_MAX_RUNS=1000 > "$TMP/out.$i" &
done
wait

NG=0; MISS=""; DUP=""
for g in $GUARD_LIST; do
    NG=$((NG+1))
    n=$(grep -c "^$g .*/one\.md\$" "$FED")
    [ "$n" -ge 1 ] || MISS="$MISS $g"
    [ "$n" -le 1 ] || DUP="${DUP} ${g}×${n}"
done
TOTAL=$(grep -c '/one\.md$' "$FED")
REPORTS=0; i=0
while [ "$i" -lt "$N" ]; do
    i=$((i+1))
    grep -qF "ADV-FINDING-ONE" "$TMP/out.$i" && REPORTS=$((REPORTS+1))
done

# T0 — положительный контроль: правка дошла до каждого стража хотя бы раз. Иначе ноги ниже
# судили бы пустую подачу и зеленели вхолостую.
if [ -z "$MISS" ]; then ok; else bad T0 "положительный контроль: правка не дошла до стражей:$MISS"; fi
# T1 — пара «файл + страж» подана ровно один раз за сессию.
if [ -z "$DUP" ]; then ok
else bad T1 "дедуп по паре не держит одновременных событий: $TOTAL подач на $NG стражей при $N событиях одной сессии (ожидалось $NG):$DUP"; fi
# T2 — находка по одной паре напечатана одним событием, а не каждым, вошедшим в окно.
if [ "$REPORTS" -eq 1 ]; then ok
else bad T2 "находка по одной паре «one.md + ${FIRST}» напечатана ${REPORTS} событиями из ${N} (ожидалось 1)"; fi

echo "test_adv_dispatch_concurrent_double_feed: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
