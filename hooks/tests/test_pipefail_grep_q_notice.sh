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

# --- T9: СРАБАТЫВАНИЕ ОСТАВЛЯЕТ СЛЕД (24 сентября 2026) -------------------------------
# Повод: один и тот же капкан сработал четырежды за сессию, а спросить «сколько раз страж уже
# говорил» было не у кого — он не писал ничего. Число существовало только в памяти о тексте,
# то есть на уровне 1 лестницы. След нужен не ради счёта, а чтобы точность признака стало НА
# ЧЁМ накопить: уровень стража не меняется, он остаётся подсказкой.
_T9_DIR=$(mktemp -d)
_T9_PAY=$(python3 -c '
import json
print(json.dumps({"session_id": "t9probe", "tool_input": {"file_path": "/tmp/t9.sh",
    "content": "set -o pipefail\nprintf %s \"$V\" | grep -q foo && echo yes\n"}}))')  # sigpipe-ok: фикстура — идиом здесь ПРЕДМЕТ подачи стражу, а не дефект
# ДВЕ подачи: страж зарегистрирован и на событии записи, и в диспетчере подачи из оболочки.
printf '%s' "$_T9_PAY" | STATE_DIR="$_T9_DIR" bash "$GUARD" >/dev/null 2>&1
printf '%s' "$_T9_PAY" | STATE_DIR="$_T9_DIR" bash "$GUARD" >/dev/null 2>&1
_T9_F="$_T9_DIR/pipefail-grep-q-fired-t9probe.jsonl"
_T9_N=$(grep -c . "$_T9_F" 2>/dev/null || true)
case "$_T9_N" in ''|*[!0-9]*) _T9_N=0 ;; esac
if [ "$_T9_N" -eq 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T9]: строк следа $_T9_N, ожидалась одна (дедуп по ключу)"; fi
rm -rf "$_T9_DIR"

# --- T10: ВЫВОД — JSON ПРОТОКОЛА НА ЛЮБОЙ СТРОКЕ (D1026, 22 октября 2026) -----------------------
# Строка подставлялась в JSON руками с экранированием одних кавычек: `\` в образце `grep` и разрез до 100 знаков сразу
# после `\` давали `\.` и `\»` — вывод не разбирался, и подсказка о строке 316 docs-family-check.sh не дошла.
# Образцы — каждый в своей строке с меткой: сводный сверщик SIGPIPE судит строки файла, и образец внутри многострочной
# фикстуры без метки краснил его (скептик D1026).
_t10a='ok=$(printf "%s" "$v" | grep -qE '"'"'\.sh$'"'"') && echo ok'  # sigpipe-ok: фикстура — дефектный идиом здесь ПРЕДМЕТ проверки
_t10c='        if [ "$TRAP" -eq 1 ]; then project_git -C "$CWD" show ":$doc" 2>/dev/null | grep -Fq "$VER_PLAIN" && continue'  # sigpipe-ok: фикстура — дефектный идиом здесь ПРЕДМЕТ проверки
for _t10 in "set -o pipefail
$_t10a" "set -o pipefail
$_t10c"; do
    if python3 -c 'import json, sys; sys.exit(0 if "SIGPIPE" in json.loads(sys.stdin.read())["hookSpecificOutput"]["additionalContext"] else 1)' \
        >/dev/null 2>&1 <<< "$(probe "$_t10")"; then ok
    else bad T10 "вывод стража не разбирается как JSON протокола: $(probe "$_t10" | cut -c1-160)"; fi
done
# T10б — разрез до 100 знаков рвёт букву: в локали C `cut` режет байты (как GNU `cut` в любой локали), а печать идёт в
# UTF-8. Первая редакция починки D1026 падала здесь на суррогате, и подсказка пропадала молча.
_t10b_pre='x=$(printf "%s" "$v" | grep -q "'  # sigpipe-ok: фикстура — дефектный идиом здесь ПРЕДМЕТ проверки
_t10b="set -o pipefail
${_t10b_pre}$(printf 'a%.0s' $(seq 1 $((99 - ${#_t10b_pre}))))абвгд\")"
if python3 -c 'import json, sys; sys.exit(0 if "SIGPIPE" in json.loads(sys.stdin.read())["hookSpecificOutput"]["additionalContext"] else 1)' \
    >/dev/null 2>&1 <<< "$(LC_ALL=C PYTHONIOENCODING=utf-8 probe "$_t10b")"; then ok
else bad T10б "буква, разрезанная на 100-м байте, обрушила вывод стража: $(LC_ALL=C PYTHONIOENCODING=utf-8 probe "$_t10b" | cut -c1-160)"; fi

echo "pipefail grep -q notice: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
