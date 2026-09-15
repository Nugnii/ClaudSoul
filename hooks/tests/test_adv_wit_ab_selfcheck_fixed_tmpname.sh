#!/usr/bin/env bash
# test_adv_wit_ab_selfcheck_fixed_tmpname.sh — фикстура самопроверки ab-authorization-replay.sh на macOS лежит под ЛИТЕРАЛЬНЫМ именем: чужой или оставшийся файл валит исправный прогон кодом 2.
#
# Результат: `mktemp "$TMPDIR/ab-selfcheck.XXXXXX.jsonl"` на BSD-mktemp (macOS) не заменяет X —
#            суффикс после них запрещает подстановку, и файл создаётся под именем самого шаблона.
#            Имя фиксировано и лежит в ОБЩЕМ TMPDIR вне песочницы теста: вторая копия инструмента
#            (или свидетеля) либо остаток прерванного прогона делают `mktemp` красным («File exists»),
#            `_selfcheck` возвращает 1, и инструмент отвечает «реплей неисправен» кодом 2 на
#            транскрипте с деструктивным ходом. Ожидание: код 0 и «Выборка: 1 транскриптов».
#            Свидетель test_ab_authorization_replay.sh этого не видит: копия у него одна, TMPDIR не
#            трогается, и файл с именем шаблона пишется в системный TMPDIR за пределами его mktemp -d.
#            На GNU mktemp (Linux) X подставляются, и столкновения нет — тест это называет и проходит.
# Проверка результата: этот тест.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/ab-authorization-replay.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
[ -f "$REPO/hooks/lib/backfill-replay-one.sh" ] || { echo "SKIP: нет воркера реплея"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
T="$TMP/tmpdir"; H="$TMP/home"; P="$H/.claude/projects/proj"
mkdir -p "$T" "$P"
PAD=$(printf 'x%.0s' $(seq 1 60000))
{
    jq -cn '{type:"user",timestamp:"2026-01-01T10:00:00Z",message:{role:"user",content:[{type:"text",text:"обсуждаем дизайн"}]}}'
    jq -cn '{type:"assistant",timestamp:"2026-01-01T10:00:05Z",message:{role:"assistant",content:[{type:"text",text:"Поправил."},{type:"tool_use",name:"Edit",id:"x",input:{}}]}}'
    jq -cn '{type:"user",timestamp:"2026-01-01T10:00:30Z",message:{role:"user",content:[{type:"text",text:"спасибо, посмотрю позже обязательно"}]}}'
    jq -cn --arg p "$PAD" '{type:"user",timestamp:"2026-01-01T10:01:00Z",message:{role:"user",content:[{type:"text",text:$p}]}}'
} > "$P/alpha-one.jsonl"
run_tool() { OUT=$(cd "$REPO" && HOME="$H" TMPDIR="$T" bash "$TOOL" 2>&1); RC=$?; }

# --- T1: контроль — чужих файлов в TMPDIR нет, инструмент здоров ----------------------------------
run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "контроль: rc=$RC — ${OUT}"
has T1 'Выборка: 1 транскриптов'

# --- T2: имя фикстуры самопроверки — фиксировано ли оно на этой машине -----------------------------
probe=$(mktemp "$T/ab-selfcheck.XXXXXX.jsonl" 2>&1); prc=$?
case "$prc:$(basename "${probe:-}")" in
    0:ab-selfcheck.XXXXXX.jsonl) echo "mktemp здесь BSD: X не подставлены, имя фикстуры фиксировано — файл шаблона оставлен как «чужой»" ;;
    0:*) echo "mktemp здесь GNU: имя случайно, столкновения на этой машине нет"; rm -f "$probe"; : > "$T/ab-selfcheck.XXXXXX.jsonl" ;;
    *)   echo "mktemp отверг шаблон с суффиксом: ${probe}"; : > "$T/ab-selfcheck.XXXXXX.jsonl" ;;
esac

# --- T3: файл с именем шаблона уже лежит (параллельная копия / остаток прогона) — исправный
#         инструмент на исправном транскрипте обязан отработать кодом 0 ------------------------------
run_tool
[ "$RC" -eq 0 ] && ok || bad T3 "при чужом файле в TMPDIR исправный инструмент ответил rc=$RC — ${OUT}"
has T3 'Выборка: 1 транскриптов'

echo ""
echo "adv ab-selfcheck fixed tmpname: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
