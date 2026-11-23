#!/usr/bin/env bash
# test_verdict_through_pipe.sh — свидетель стража hooks/verdict-through-pipe-check.sh.
#
# Результат: страж говорит РОВНО тогда, когда вердикт прибора не наблюдался ни в коде
#            (потерян фильтром), ни в показанном выводе; во всех прочих случаях молчит.
# Проверка результата: bash hooks/tests/test_verdict_through_pipe.sh даёт 0
#
# Ноги построены от КОНТРАКТА, а не от воспроизведения: у утверждения две стороны, и обе
# судятся — «сказал, когда надо» и «смолчал, когда не надо». Урок того же дня
# (case-2026-09-18-witness-built-from-the-repro-not-the-contract): свидетель, писанный по
# следам находки, судит одно направление и проходится мутантом, который ничего не убирает.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
HOOK="${CLAUDSOUL_REPO:-$ROOT}/hooks/verdict-through-pipe-check.sh"
[ -f "$HOOK" ] || { echo "нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "нет jq" >&2; exit 2; }
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

fire() {  # fire <команда> <вывод> → 1 если страж сказал
    jq -cn --arg c "$1" --arg o "${2:-}" \
        '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c},
          tool_response:{stdout:$o,stderr:"",interrupted:false}}' \
      | bash "$HOOK" 2>/dev/null | grep -c 'Вердикт не наблюдался'
}
RUN='… прошло 25, упало 0'

# ── СКАЗАЛ, КОГДА НАДО: ход прогона есть, итога нет ───────────────────────────
# Формы команды НАМЕРЕННО разные: признак о выводе, и ни одна из них роли играть не должна.
# Первая редакция судила команду перечнем форм, и скептик предъявил 13 обходов — каждый из
# пяти ниже был одним из них.
[ "$(fire 'bash hooks/tests/run_all.sh | tail -4' "$RUN")" = 1 ] && ok || bad T1 "обычная форма — молчит"
[ "$(fire 'bash hooks/tests/run_all.sh |
 tail -4' "$RUN")" = 1 ] && ok || bad T2 "перенос строки перед фильтром — молчит"
[ "$(fire 'bash "/Users/s/My Project/ClaudSoul/hooks/tests/run_all.sh" | tail' "$RUN")" = 1 ] \
    && ok || bad T3 "абсолютный путь С ПРОБЕЛОМ — молчит"
[ "$(fire 'bash run_all.sh | tee /tmp/s.log' "$RUN")" = 1 ] && ok || bad T4 "tee вместо tail — молчит"
[ "$(fire 'timeout 900 zsh hooks/tests/run_all.sh | sort' "$RUN")" = 1 ] \
    && ok || bad T5 "интерпретатор и префикс вне перечня — молчит"
[ "$(fire 'git log > /tmp/g.log; bash run_all.sh | tail -3' "$RUN")" = 1 ] \
    && ok || bad T6 "чужой .log в составной команде глушил стража"
[ "$(fire 'bash t.sh | head -3' 'FAIL [T7]: что-то')" = 1 ] && ok || bad T7 "строка FAIL [ — след прогона не опознан"

# T7b — ИСХОДНЫЙ СЛУЧАЙ, ради которого страж построен. `| tail -n 4` показывает ХВОСТ
# набора, и в нём нет ни «прошло», ни «PASS=». Первая редакция признака знала только начало
# вывода и этот случай ПРОПУСКАЛА — проверено прогоном 18 сентября 2026, то есть страж не
# ловил ровно то, ради чего заведён.
[ "$(fire 'bash hooks/tests/run_all.sh --changed 2>&1 | tail -n 4' 'ДОРОЖЕ 20с (12 из 284; сумма по всем 1116 с):
   106 с  test_defect_registry_cache.sh  (CPU 94 с)
журнал прогона (пишется по ходу, переживает обрыв): /path/suite-run.tsv')" = 1 ] \
    && ok || bad T7b "ХВОСТ набора без итога — страж смолчал на собственном поводе"

# ── СМОЛЧАЛ, КОГДА НЕ НАДО: вердикт наблюдался либо прогона не было ───────────
# Перечень итогов взят у ВЛАДЕЛЬЦА (строки итога hooks/tests/run_all.sh — искать по тексту, номера уезжают).
# Первая редакция знала две формы из шести и спорила с фактом на двух настоящих итогах.
[ "$(fire 'bash run_all.sh | tail -14' "$RUN
Hook test files: 531/531 passed")" = 0 ] && ok || bad T8 "итог виден — сказал зря"
[ "$(fire 'bash run_all.sh | tail -3' "$RUN
FAILED: test_x.sh")" = 0 ] && ok || bad T9 "итог FAILED — сказал зря"
[ "$(fire 'bash run_all.sh | tail -3' "$RUN
ЗАВИСЛИ (убиты по своему сроку): test_x.sh(60с)")" = 0 ] && ok || bad T10 "итог ЗАВИСЛИ — сказал зря"
[ "$(fire 'bash run_all.sh | tail -3' "$RUN
НЕ ХВАТИЛО ВРЕМЕНИ под нагрузкой: test_y.sh")" = 0 ] && ok || bad T11 "итог НЕ ХВАТИЛО ВРЕМЕНИ — сказал зря"
[ "$(fire 'bash t.sh | tail -2' 'PASS=13 FAIL=0')" = 0 ] && ok || bad T12 "итог одиночного теста — сказал зря"
[ "$(fire 'bash hooks/tests/run_all.sh --list | head -20' 'test_a.sh
test_b.sh')" = 0 ] && ok || bad T13 "--list: прогона не было, вердикта нет по построению — сказал зря"
[ "$(fire 'bash run_all.sh > /tmp/s.log 2>&1; echo $?' '0')" = 0 ] && ok || bad T14 "код сохранён явно — сказал зря"
[ "$(fire 'git log --oneline | head -3' 'abc правка')" = 0 ] && ok || bad T15 "чужая команда — сказал зря"
[ "$(fire 'echo привет' 'привет')" = 0 ] && ok || bad T16 "обычная команда — сказал зря"

# ── РАМКА: мутанты, каждый УРЕЗАЕТ механизм ──────────────────────────────────
# Блокирующая находка скептика 18 сентября 2026: свидетель проходился ШЕСТЬЮ мутантами, то
# есть различал только «мёртв/жив», а не «полон/урезан». Ноги ниже судят каждый шаг отдельно.
MUT=$(mktemp -d); trap 'rm -rf "$MUT"' EXIT
mutant() {  # mutant <sed-выражение> → путь к урезанной копии
    sed -E "$1" "$HOOK" > "$MUT/m.sh"; printf '%s' "$MUT/m.sh"
}
fire_at() {  # fire_at <страж> <команда> <вывод>
    jq -cn --arg c "$2" --arg o "${3:-}" \
        '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c},
          tool_response:{stdout:$o,stderr:""}}' | bash "$1" 2>/dev/null | grep -c 'Вердикт не наблюдался'
}
# М1: шаг «итог виден» вырезан — страж обязан начать говорить там, где итог есть.
M=$(mutant 's@^for _v in "Hook test files:".*@for _v in "__нет_такой_строки__"; do@')
[ "$(fire_at "$M" 'bash run_all.sh | tail -14' "$RUN
Hook test files: 531/531 passed")" = 1 ] && ok \
    || bad T17 "рамка: мутант без перечня итогов не отличим от целого стража"
# М2: шаг «следы прогона» вырезан — страж обязан заговорить на выводе без прогона.
M=$(mutant 's@^\[ "\$_ran" -eq 1 \] \|\| exit 0@:@')
[ "$(fire_at "$M" 'git log | head -3' 'abc правка')" = 1 ] && ok \
    || bad T18 "рамка: мутант без проверки следов прогона не отличим"
# М3: шаг «код сохранён» вырезан.
M=$(mutant 's@^grep -qE .\(echo\[\[:space:\]\]\+.*PIPESTATUS.*$@:@')
[ "$(fire_at "$M" 'bash run_all.sh | tail -3; echo $?' "$RUN")" = 1 ] && ok \
    || bad T19 "рамка: мутант без проверки сохранённого кода не отличим"
# М4: выпотрошенный страж — «мёртв/жив», прежний контроль рамки.
printf 'exit 0\n' > "$MUT/gut.sh"
[ "$(fire_at "$MUT/gut.sh" 'bash run_all.sh | tail -4' "$RUN")" = 0 ] && ok \
    || bad T20 "рамка: мёртвый страж «сказал» — суд ничего не значит"

echo "verdict through pipe: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
