#!/usr/bin/env bash
# test_authorization_replay.sh — «Проверка результата» authorization-replay.py меряет объявленный результат.
#
# Результат: команда из шапки scripts/authorization-replay.py на подложенном корпусе печатает число
#            реплик собеседника, число признанных поручением, долю и число нераспознанных реплик,
#            после которых агент правил файлы, с примерами; системные вставки репликами не считаются;
#            пустой корпус даёт нули, а не молчание.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Кандидатов в свидетели у инструмента не было ни одного. Корпус
# подкладывается через HOME (инструмент читает `~/.claude/projects`); классификатор — настоящий,
# из hooks/authorization-lib.sh. Команда БЕРЁТСЯ из шапки инструмента; хвост «печатает…» —
# пояснение, отсекается вместе с «даёт 0».
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/authorization-replay.py"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—|печатает).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *authorization-replay.py*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; P="$H/.claude/projects/proj"
run_tool() {
    OUT=$(cd "$REPO" && HOME="$H" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: две реплики, одно поручение, одна нераспознанная с правкой следом ----------------------
rm -rf "$H"; mkdir -p "$P"
{
    printf '{"type":"user","message":{"role":"user","content":"сделай вот это"}}\n'
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":"ок"}]}}\n'
    printf '{"type":"user","message":{"role":"user","content":"а почему так вышло?"}}\n'
    printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","id":"1","input":{}}]}}\n'
    printf '{"type":"user","message":{"role":"user","content":"[SYSTEM NOTIFICATION] служебное"}}\n'
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<task-notification>x</task-notification>"}]}}\n'
} > "$P/s1.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'реплик собеседника в корпусе: 2'
has T1 'признано поручением: 1'
has T1 'доля признанных: 50%'
has T1 'НЕ признано, но агент следом правил файлы: 1'
has T1 '· а почему так вышло?'

# --- T2: пустой корпус — нули напечатаны -----------------------------------------------------
rm -rf "$H"; mkdir -p "$H/.claude/projects"; run_tool
[ "$RC" -eq 0 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 'реплик собеседника в корпусе: 0'
has T2 'НЕ признано, но агент следом правил файлы: 0'

# --- T3: реплика длиннее 600 символов репликой не считается (порог инструмента) -----------------
rm -rf "$H"; mkdir -p "$P"
long=$(printf 'сделай %.0s' $(seq 1 120))
printf '{"type":"user","message":{"role":"user","content":"%s"}}\n{"type":"user","message":{"role":"user","content":"сделай вот это"}}\n' "$long" > "$P/s1.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'реплик собеседника в корпусе: 1'

# --- T4: чтение файла после нераспознанной реплики — не правка (условие EDIT_TOOLS) -----------------
rm -rf "$H"; mkdir -p "$P"
printf '{"type":"user","message":{"role":"user","content":"а почему так вышло?"}}\n{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","id":"1","input":{}}]}}\n' > "$P/s1.jsonl"
run_tool
[ "$RC" -eq 0 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'НЕ признано, но агент следом правил файлы: 0'

echo ""
echo "authorization-replay tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
