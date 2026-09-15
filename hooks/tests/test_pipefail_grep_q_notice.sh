#!/usr/bin/env bash
# test_pipefail_grep_q_notice.sh — страж формы SIGPIPE говорит о пайпе в grep -q и молчит обо всём прочем.
#
# Результат: три формы, ловившие автора 11 сентября 2026, названы; безопасные — пропущены.
# Проверка результата: bash hooks/tests/test_pipefail_grep_q_notice.sh даёт 0
#
# Ноги держат ОБЕ стороны различения: без T4-T7 тест зеленел бы у стража, который горит на
# всё подряд, а без T1-T3 — у того, который молчит всегда.
#
# Хелперы взяты у соседа (test_budget_gate.sh), а не изобретены: прувер
# `test_guards_provable.sh` распознаёт доказательство тишины ПО СИГНАТУРЕ, ручной `[ -z ]`
# доказательством не считает. Правило — `docs/development.md`, раздел «Обязательные шаги».
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/pipefail-grep-q-notice.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
assert_silent()   { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина, получено: ${1}"; }
assert_contains() { if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в: ${1}"; fi; }
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "нет python3 — пропуск"; exit 0; }

probe() { # $1 — записываемый текст
    python3 -c '
import json, sys
print(json.dumps({"tool_input": {"file_path": "/tmp/probe.sh", "content": sys.argv[1]}}))' "$1" \
    | bash "$GUARD" 2>&1
}

# --- T1-T3: три формы, ловившие автора в один день, — обязаны быть названы ---
OUT=$(probe 'set -uo pipefail
check | grep -qi "формализ" && ok || bad T2 "нет"')  # sigpipe-ok: фикстура — дефектный идиом здесь ПРЕДМЕТ проверки, а не дефект
assert_contains "$OUT" "SIGPIPE" "T1: функция слева от пайпа не названа"

OUT=$(probe 'set -uo pipefail
if (cd "$T" && bash suite.sh 2>&1 | grep -q "Hook test"); then ok; fi')  # sigpipe-ok: фикстура — дефектный идиом здесь ПРЕДМЕТ проверки, а не дефект
assert_contains "$OUT" "SIGPIPE" "T2: вызов скрипта слева от пайпа не назван"

OUT=$(probe 'set -uo pipefail
if printf "%s" "$BODY" | grep -q "ПРЕФИКСЫ"; then echo да; fi')  # sigpipe-ok: фикстура — дефектный идиом здесь ПРЕДМЕТ проверки, а не дефект
assert_contains "$OUT" "SIGPIPE" "T3: printf с переменной слева не назван"

# --- T4: here-string — пайпа нет, SIGPIPE невозможен ---
assert_silent "$(probe 'set -uo pipefail
grep -q "a" <<<"$OUT" && ok')" "T4: страж заговорил о here-string"

# --- T5: без pipefail статус берётся у grep — дефекта нет ---
assert_silent "$(probe 'set -u
if bash x.sh | grep -q "a"; then ok; fi')" "T5: страж заговорил при отсутствии pipefail"  # sigpipe-ok: фикстура — дефектный идиом здесь ПРЕДМЕТ проверки, а не дефект

# --- T6: статус пайпа не проверяется (идёт в подстановку) — безопасно ---
assert_silent "$(probe 'set -uo pipefail
N=$(bash x.sh | grep -c "a")')" "T6: страж заговорил там, где статус не проверяется"

# --- T7: форма внутри комментария — не код ---
assert_silent "$(probe 'set -uo pipefail
# было: check | grep -q "x" && ok')" "T7: страж принял комментарий за код"

# --- T8: не shell-файл — не предмет стража ---
OUT=$(python3 -c '
import json, sys
print(json.dumps({"tool_input": {"file_path": "/tmp/readme.md", "content": sys.argv[1]}}))' \
      'set -uo pipefail
check | grep -q "x" && ok' | bash "$GUARD" 2>&1)  # sigpipe-ok: фикстура — дефектный идиом здесь ПРЕДМЕТ проверки, а не дефект
assert_silent "$OUT" "T8: страж заговорил о файле, который не скрипт"

echo "pipefail grep -q notice: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
