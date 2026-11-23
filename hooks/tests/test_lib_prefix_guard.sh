#!/usr/bin/env bash
# СУДИТ: hooks/lib-prefix-guard.sh
# test_lib_prefix_guard.sh — функция библиотеки носит имя из ОБЪЯВЛЕННОГО пространства.
#
# Результат: чужой префикс в `hooks/*-lib.sh` назван, свой и внутренний — пропущены.
# Проверка результата: bash hooks/tests/test_lib_prefix_guard.sh даёт 0
#
# Повод — слово владельца 11 сентября 2026: «должен быть какой-то механизм по неймингу
# функций при создании новой». Замер того дня: правила именования не было ни в одном
# документе, в библиотеках 45 разных префиксов, объявления — ни у одной из 29.
#
# Ноги держат ОБЕ стороны различения и НАЗВАННЫЙ ПРЕДЕЛ: без T2 страж, молчащий всегда,
# был бы зелёным; без T5 предел выглядел бы починенным.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/lib-prefix-guard.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

command -v jq >/dev/null 2>&1 || { echo "нет jq — пропуск"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "нет python3 — пропуск"; exit 0; }

# Форма утверждений взята ИЗ МИРА (`test_ablation_core_inject.sh:25`), а не придумана:
# мета-тест `test_guards_provable.sh` считает доказательством ВЫЗОВЫ признанных форм, и
# «-eq 0» доказательством тишины не является — страж, горящий всегда, прошёл бы мимо.
assert_empty()    { if [ -z "$1" ]; then ok; else bad "$2" "ожидалась тишина, вышло: $1"; fi; }
assert_contains() { case "$1" in *"$2"*) ok ;; *) bad "$3" "не найдено '$2'" ;; esac; }

say() {  # $1 — файл, $2 — тело правки; печатает вывод стража
    python3 -c 'import json,sys;print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"new_string":sys.argv[2]}}))' "$1" "$2" \
        | bash "$HOOK" 2>/dev/null | grep -o 'вне объявленного[^"]*' | head -c 80
}

assert_contains "$(say "$ROOT/hooks/root-cause-lib.sh" 'foo_bar() {
  :
}')" "вне объявленного" "T1: чужой префикс foo_ в rc_-библиотеке не назван"

assert_empty "$(say "$ROOT/hooks/root-cause-lib.sh" 'rc_new_thing() {
  :
}')" "T2: своё имя объявлено чужим — страж говорит на законном"

assert_empty "$(say "$ROOT/hooks/root-cause-lib.sh" '_rc_helper() {
  :
}')" "T3: внутреннее имя с ведущим _ не должно судиться"

assert_contains "$(say "$ROOT/hooks/fsrs-lib.sh" 'itr_compute() {
  :
}')" "вне объявленного" "T4: префикс соседней библиотеки не назван"

# T5 — предел назван в `.claude-docs/modules/lib-prefix-guard.md` (там же условие снятия):
# имя выдумано, но префикс верный — этот страж о нём молчит по построению, и ловит такое
# `undefined-function-check` (существование, а не пространство имён).
assert_empty "$(say "$ROOT/hooks/root-cause-lib.sh" 'rc_trace_counts() {
  :
}')" "T5: предел изменился — страж заговорил о верном префиксе"

# T6 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ПО ДЕРЕВУ: объявления собраны из факта, значит на живых
# библиотеках страж обязан молчать. Заговорит — признак ложен.
_said=0; _n=0
for _f in "$ROOT"/hooks/*-lib.sh; do
    _n=$((_n+1))
    _o=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":open(sys.argv[1],encoding="utf-8").read()}}))' "$_f" \
         | bash "$HOOK" 2>/dev/null | grep -c 'вне объявленного')
    [ "${_o:-0}" -gt 0 ] && _said=$((_said+1))
done
[ "$_said" -eq 0 ] && ok || bad T6 "страж заговорил на $_said живых библиотеках из $_n"

# T7 — у каждой библиотеки есть объявление: без него сверять не с чем и страж нем.
_no=0
for _f in "$ROOT"/hooks/*-lib.sh; do
    grep -q '^# ПРЕФИКСЫ:' "$_f" 2>/dev/null || _no=$((_no+1))
done
[ "$_no" -eq 0 ] && ok || bad T7 "библиотек без объявления: $_no"

echo "lib prefix guard: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
