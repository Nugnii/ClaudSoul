#!/usr/bin/env bash
# СУДИТ: scripts/ab-authorization-replay.sh
# test_ab_authorization_replay.sh — «Проверка результата» ab-authorization-replay.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/ab-authorization-replay.sh на подложенных транскриптах печатает
#            таблицу A/B с числом ходов по каждому транскрипту и итогом; выборка ограничена N свежайшими
#            основными транскриптами 50КБ..6МБ; пустая выборка — код 1 «выборка пуста», выборка без
#            деструктивных ходов — код 2 «Не измеряли», и ни то ни другое не код 0.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Три кандидата в свидетели упоминают инструмент и зелены под
# заглушкой. Проба на пустой фикстуре нашла дефект: `printf '%s\n' ""` давал одну строку, пустая
# выборка считалась одним транскриптом, и прогон уходил в «Не измеряли» с кодом 0. Транскрипты
# подкладываются через HOME (инструмент читает `$HOME/.claude/projects`); воркер реплея сам строит
# песочницу. Команда БЕРЁТСЯ из шапки инструмента, как в test_split_provenance_log.sh.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/ab-authorization-replay.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
[ -f "$REPO/hooks/lib/backfill-replay-one.sh" ] || { echo "SKIP: нет воркера реплея"; exit 0; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *ab-authorization-replay.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }
hasnt() { grep -Fq -- "$2" <<< "$OUT" && bad "$1" "лишняя строка «$2»" || ok; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; P="$H/.claude/projects/proj"
PAD=$(printf 'x%.0s' $(seq 1 60000))

# Транскрипт с деструктивным ходом без поручения, добитый до 60 КБ. $2 = 1 — без деструктивного хода.
# Реплика без поручения — ВОПРОС: «обсуждаем дизайн» живой классификатор считает поручением (правило D207), и сцена
# держалась только на том, что в песочнице реплея правило было мертво (D1205, круг скептика, H1).
mk_transcript() {
    {
        jq -cn '{type:"user",timestamp:"2026-01-01T10:00:00Z",message:{role:"user",content:[{type:"text",text:"как лучше устроить дизайн?"}]}}'
        if [ "${2:-0}" -eq 0 ]; then
            jq -cn '{type:"assistant",timestamp:"2026-01-01T10:00:05Z",message:{role:"assistant",content:[{type:"text",text:"Поправил."},{type:"tool_use",name:"Edit",id:"x",input:{}}]}}'
        else
            jq -cn '{type:"assistant",timestamp:"2026-01-01T10:00:05Z",message:{role:"assistant",content:[{type:"text",text:"Обсудим."}]}}'
        fi
        jq -cn '{type:"user",timestamp:"2026-01-01T10:00:30Z",message:{role:"user",content:[{type:"text",text:"спасибо, посмотрю позже обязательно"}]}}'
        jq -cn --arg p "$PAD" '{type:"user",timestamp:"2026-01-01T10:01:00Z",message:{role:"user",content:[{type:"text",text:$p}]}}'
    } > "$1"
}
fresh() { rm -rf "$H"; mkdir -p "$P"; }
run_tool() {   # $@ — аргументы инструмента
    OUT=$(cd "$REPO" && HOME="$H" bash -c "$CMD $*" 2>&1); RC=$?
}

# --- T1: транскриптов нет — «выборка пуста», код 1 --------------------------------------------
fresh; run_tool
[ "$RC" -eq 1 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'выборка пуста'

# --- T2: один транскрипт с деструктивным ходом — таблица, строка транскрипта, итог -------------
fresh; mk_transcript "$P/alpha-one.jsonl"; run_tool
[ "$RC" -eq 0 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 'Выборка: 1 транскриптов'
has T2 '| alpha-on… | 1 | 0 | 1 | 0 |'
has T2 '| **итого** | **1** | **0** | **1** | **0** |'
has T2 'Деструктивных ходов классифицировано: A=1, B=1'

# --- T3: N ограничивает выборку свежайшими; вне размера и в subagents не берутся ----------------
fresh; mk_transcript "$P/old-one.jsonl"; mk_transcript "$P/new-one.jsonl"
touch -t 202601010000 "$P/old-one.jsonl"; touch -t 202602010000 "$P/new-one.jsonl"
printf '{"type":"user"}\n' > "$P/tiny.jsonl"; mkdir -p "$P/subagents"; mk_transcript "$P/subagents/sub-one.jsonl"
run_tool 1
[ "$RC" -eq 0 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'Выборка: 1 транскриптов'
has T3 '| new-one… |'
hasnt T3 '| old-one… |'
hasnt T3 '| sub-one… |'

# --- T4: деструктивных ходов нет — «Не измеряли», код 2, не 0 ------------------------------------
fresh; mk_transcript "$P/calm-one.jsonl" 1; run_tool
[ "$RC" -eq 2 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'Не измеряли'

echo ""
echo "ab-authorization-replay tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
