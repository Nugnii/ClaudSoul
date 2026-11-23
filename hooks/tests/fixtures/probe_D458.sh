#!/usr/bin/env bash
# probe_D458.sh — проба пункта D458: цикл переработки замыкается только по совпадению
#                 СЕКУНД. `{"kind":"run"}` пишется лишь при ПУСТОМ перечне целей
#                 (`rework-detector.sh:263`), а `rw_world_targets` объявляет целью всякий
#                 файл, чей mtime отличается от снимка прошлого вызова; `file_mtime` меряет
#                 целыми секундами. Прогон, идущий за правкой в ДРУГУЮ секунду, пишет
#                 `edit` вместо `run`, и цикл не растёт.
# Результат: между правкой и прогоном прошла секунда — цикл всё равно замыкается, и три
#            цикла дают напоминание. Счёт не зависит от числа вызовов оболочки между ними.
# Проверка результата: bash hooks/tests/fixtures/probe_D458.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась.
#
# РОД M ПРОВЕРЕН И НЕ ПОДТВЕРЖДЁН (18 сентября 2026). Признак рода указывает сюда, потому
# что песочница строится голым `mktemp -d`, а в детекторе есть отбрасывание путей `*/tmp/*`
# — на macOS `mktemp` даёт `/var/folders/…`, и класс был бы невидим до раннера. Замер на
# ОБОИХ корнях: с песочницей, принудительно созданной под `/tmp`
# (`mktemp -d /tmp/probeM.XXXXXX`), коды те же, что и с обычной.
# ПОЧЕМУ отбрасывание сюда не достаёт — прочитано у источника, а не выведено из поведения:
# `case … */tmp/*) continue` стоит внутри `rw_write_targets` (`rework-detector.sh:186`), то
# есть применяется к целям, извлечённым из ТЕКСТА КОМАНДЫ. У `rw_world_targets` фильтра по
# пути нет ни одного: он читает `git status --porcelain` ОТНОСИТЕЛЬНО корня репозитория, и
# пути там относительные — `f.sh`, а не `/tmp/…/f.sh`. Песочница целиком лежит внутри
# своего git-репозитория, поэтому её собственный абсолютный путь в сравнение не попадает.
# НАЗВАННЫЙ ПРЕДЕЛ замера: он сделан на macOS с ПОДСТАВЛЕННЫМ корнем песочницы, а не на
# Linux, где `/tmp` — умолчание. Условие снятия: тот же замер в контейнере раннера.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/rework-detector.sh"
[ -f "$HOOK" ] || { echo "probe_D458: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D458: нет jq" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D458: нет git" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || { echo "probe_D458: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
S="$T/state"; mkdir -p "$S" "$T/repo"
( cd "$T/repo" && git init -q . && printf 'x\n' > f.sh && git add -A \
  && git -c user.email=p@p -c user.name=p commit -qm i ) >/dev/null 2>&1 \
  || { echo "probe_D458: репозиторий не собрался" >&2; exit 2; }

SID=d458
call() {  # call <команда|""> <файл|"">
    jq -cn --arg s "$SID" --arg c "$1" --arg f "$2" --arg w "$T/repo" \
        '{session_id:$s, cwd:$w}
         + (if $c == "" then {tool_name:"Edit", tool_input:{file_path:$f}}
            else {tool_name:"Bash", tool_input:{command:$c}} end)' \
      | env STATE_DIR="$S" bash "$HOOK" 2>/dev/null
}
F="$T/repo/f.sh"

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: без задержки, с ДВУМЯ прогонами между правками, цикл замыкается —
# значит механизм жив и судить есть чем. Этот порядок и держит probe_D453.
call "" "$F" >/dev/null
for i in 1 2; do
    printf 'v%s\n' "$i" > "$F"; call "" "$F" >/dev/null
    call "bash t.sh" "" >/dev/null; call "bash t.sh" "" >/dev/null
done
printf 'v9\n' > "$F"
OUT=$(call "" "$F")
grep -q 'Переработка' <<< "$OUT" || {
    echo "probe_D458: контроль — цикл не замкнулся даже в благоприятном порядке, судить нечем" >&2
    exit 2
}

# СУД: ОДИН прогон между правками и СЕКУНДА между правкой и прогоном — так работает живой
# агент. Цикл обязан замкнуться и здесь.
S2="$T/state2"; mkdir -p "$S2"
SID=d458b
call2() {
    jq -cn --arg s "$SID" --arg c "$1" --arg f "$2" --arg w "$T/repo" \
        '{session_id:$s, cwd:$w}
         + (if $c == "" then {tool_name:"Edit", tool_input:{file_path:$f}}
            else {tool_name:"Bash", tool_input:{command:$c}} end)' \
      | env STATE_DIR="$S2" bash "$HOOK" 2>/dev/null
}
# Вывод копится по ВСЕМ вызовам, а не берётся у последнего: троттл выдаёт напоминание один
# раз на пару «файл и число циклов» (`rework-detector.sh:310`), поэтому под ПОЧИНКОЙ цикл
# замыкается раньше и последний вызов уже задушен — проба, смотрящая только на него, сочла
# бы починку дефектом (поймано прогоном зелёной стороны 18 сентября 2026).
OUT=""
OUT="$OUT$(call2 "" "$F")"
for i in 1 2; do
    printf 'w%s\n' "$i" > "$F"; OUT="$OUT$(call2 "" "$F")"
    sleep 1
    OUT="$OUT$(call2 "bash t.sh" "")"
done
printf 'w9\n' > "$F"
OUT="$OUT$(call2 "" "$F")"
if ! grep -q 'Переработка' <<< "$OUT"; then
    RUNS=$(grep -c '"kind":"run"' "$S2/rework-$SID.jsonl" 2>/dev/null || true)
    echo "probe_D458: дефект — цикл не замкнулся: между правкой и прогоном прошла секунда, записей run в журнале ${RUNS:-0}" >&2
    exit 1
fi
exit 0
