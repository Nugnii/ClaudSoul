#!/usr/bin/env bash
# test_bulk_copy_journal.sh — журнал стража массового копирования читаем и говорит правду.
#
# Повод измерен 4 сентября 2026 на ЖИВОМ журнале, когда разбирали род G (поле без читателя).
# Оказалось, что читателя у полей `source`/`dest` нет по двум причинам сразу, и обе — дефекты,
# а не замысел:
#   · 79 записей из 128 не разбирались как JSON. Строка собиралась `printf`-ом из значений,
#     пришедших с командной строки собеседника, а там кавычки и слэши. Журнал, заведённый ради
#     разбора, разбору не поддавался.
#   · В разобравшихся значения были чужие: `dest: "head"` из `| head`, `dest: "rc=$?"` из
#     `&& echo "rc=$?"`, `source: "|"`. Извлечение брало последние непрефиксные слова ВСЕЙ
#     командной строки, а копирование — лишь её часть.
#
# Оба закрыты: фрагмент своей команды режется по разделителям конвейера, запись строится `jq`.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/../bulk-copy-guard.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/hooks/state"

fire() {   # <команда> → журнал сессии
    printf '{"session_id":"jt","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(jq -Rn --arg c "$1" '$c')" \
      | HOME="$HOME" STATE_DIR="$HOME/.claude/hooks/state" bash "$HOOK" >/dev/null 2>&1
    printf '%s' "$HOME/.claude/hooks/state/bulk-copy-fired-jt.jsonl"
}
field() { jq -r --arg f "$2" 'select(.signature != null) | .[$f]' "$1" 2>/dev/null | tail -1; }

# --- T1: каждая запись разбирается как JSON, даже когда путь несёт кавычки ---
J=$(fire 'cp -R "/tmp/a b" "/tmp/z\"q"')
BADLINES=0
while IFS= read -r l; do printf '%s' "$l" | jq . >/dev/null 2>&1 || BADLINES=$((BADLINES + 1)); done < "$J"
[ "$BADLINES" -eq 0 ] && ok || bad T1 "строк, не разобравшихся как JSON: $BADLINES"

# --- T2: в конвейере берётся СВОЯ команда, а не хвост чужой ---
rm -f "$J"
J=$(fire 'cp -R /tmp/src /tmp/dst | head -3')
[ "$(field "$J" dest)" = "/tmp/dst" ] && ok || bad T2 "dest из конвейера: «$(field "$J" dest)», ожидалось /tmp/dst"
[ "$(field "$J" source)" = "/tmp/src" ] && ok || bad T2b "source из конвейера: «$(field "$J" source)»"

# --- T3: то же для соседа через && ---
rm -f "$J"
J=$(fire 'rsync -a /tmp/a/ /tmp/b/ && echo "rc=$?"')
[ "$(field "$J" dest)" = "/tmp/b/" ] && ok || bad T3 "dest через &&: «$(field "$J" dest)», ожидалось /tmp/b/"

# --- T4: внешние кавычки с пути сняты ---
rm -f "$J"
J=$(fire 'cp -R "/tmp/one" "/tmp/two"')
[ "$(field "$J" source)" = "/tmp/one" ] && ok || bad T4 "кавычки не сняты: «$(field "$J" source)»"

# --- T6: дроссель считает одной работой одну и ту же работу ---
# Замер живого журнала 4 сентября 2026: 125 РАЗНЫХ ключей на 128 записей, в одной сессии
# 114 запросов подтверждения. Ключ строится из (подпись, откуда, куда), а «куда» приходило
# из хвоста чужой команды — значит у одной и той же работы, записанной с разным хвостом,
# ключи разные, и страж спрашивал снова и снова. Прогон пяти записей одной работы: было
# 5 вопросов из 5, стало 1.
rm -f "$HOME/.claude/hooks/state/bulk-copy-fired-jt.jsonl"
ASKS=0
for CMD in \
    'cp -R /tmp/src /tmp/dst' \
    'cp -R /tmp/src /tmp/dst | head -3' \
    'cp -R /tmp/src /tmp/dst && echo done' \
    'cp -R /tmp/src /tmp/dst 2>&1' \
    'cp -R /tmp/src /tmp/dst; rc=$?'
do
    OUT=$(printf '{"session_id":"jt","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":%s}}' \
              "$(jq -Rn --arg c "$CMD" '$c')" \
          | HOME="$HOME" STATE_DIR="$HOME/.claude/hooks/state" bash "$HOOK" 2>/dev/null)
    grep -q '"permissionDecision"' <<< "$OUT" && ASKS=$((ASKS + 1))
done
[ "$ASKS" -eq 1 ] && ok || bad T6 "одна работа в пяти записях дала $ASKS запросов подтверждения, ожидался 1"

# --- T5: отрицательный контроль — команда без копирования журнала не заводит ---
rm -f "$J"
J=$(fire 'ls -la /tmp | head -3')
[ ! -s "$J" ] && ok || bad T5 "страж записал журнал на команде без копирования: $(cat "$J")"

# --- T6: вопрос, показанный ОДНОМУ актору, не гасит его ДРУГОМУ (D457, класс D463) ---
# Подпись дросселя была одним хешем действия, журнал общий, и первый сработавший гасил
# вопрос всем. Воспроизведено прогоном 18 сентября 2026: субагент получал ask, а ВЛАДЕЛЕЦ на
# то же самое копирование молчал. Это страж уровня «спрашивает», цена молчания здесь выше,
# чем у напоминания.
fire_as() { # <команда> <agent_id|пусто> → вывод стража
    jq -cn --arg c "$1" --arg a "$2" \
        'if $a == "" then {session_id:"jt6", cwd:"/tmp", tool_name:"Bash", tool_input:{command:$c}}
         else {session_id:"jt6", cwd:"/tmp", agent_id:$a, tool_name:"Bash", tool_input:{command:$c}} end' \
      | HOME="$HOME" STATE_DIR="$HOME/.claude/hooks/state" bash "$HOOK" 2>/dev/null
}
CMD='cp -r /tmp/aaa /tmp/bbb'
grep -q permissionDecision <<< "$(fire_as "$CMD" sub-1)" \
    && ok || bad T6 "контроль: субагенту вопрос не показан — судить нечем"
grep -q permissionDecision <<< "$(fire_as "$CMD" "")" \
    && ok || bad T6b "ВЛАДЕЛЕЦ молчит после субагента: вопрос погашен чужим актором"
grep -q permissionDecision <<< "$(fire_as "$CMD" "")" \
    && bad T6c "повтор тому же актору не гасится — дроссель снят" || ok

echo "bulk-copy journal: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
exit $?
