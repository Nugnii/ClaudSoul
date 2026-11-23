#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# test_outcome_observed.sh — исход разбора наблюдается в ДЕЙСТВИЯХ хода, а не в его речи.
#
# Результат: rc_outcome_observed называет исход из закрытого списка rc_resolution_kinds
#            по вызовам инструментов хода; речь на вердикт не влияет, кроме «показалось»
# Проверка результата: bash hooks/tests/test_outcome_observed.sh даёт 0
#
# Повод, 7 сентября 2026 (D323). Замер по 51 расшифровке: из 103 ходов с ПРОИЗНЕСЁННОЙ
# цепочкой (формула rc_chain_spoken) 63 — 61% — не кончились ничем наблюдаемым: ни правкой
# механизма, ни пунктом долга, ни записью знания, ни вердиктом «показалось». Речь была во
# всех ста трёх. До этой функции у системы не было ни одного прибора, отличающего разбор,
# изменивший мир, от разбора, кончившегося абзацем.
#
# Почему признак взят из действий, а не из чисел речи: пять редакций признака «дробь
# добыта прогоном» промерены на том же корпусе и отвергнуты — число в тексте против числа
# в выводе не работает (малые знаменатели неотличимы от шума, а дробь промаха, записанная
# постфактум в BACKLOG, читается как цитата). Числа — см. D323.
#
# КОНТРПРИМЕРЫ, оба проверяются ниже:
#   · правка файла ВНЕ списка носителей исхода (docs/) исходом не считается;
#   · действие ДО последней реплики собеседника принадлежит прошлому ходу и не засчитывается.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS/root-cause-lib.sh"
[ -f "$LIB" ] || { echo "SKIP: нет $LIB"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# T0 — прибор существует. Без этой ноги ноги, ждущие ненулевого кода, зеленеют на 127
# («команда не найдена») — тот же класс ложно-зелёной ноги, что чинился 6 сентября (D342).
if command -v rc_outcome_observed >/dev/null 2>&1; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T0]: rc_outcome_observed не объявлена библиотекой"; fi

# usr <текст> / asst <текст> / act <инструмент> <путь> — строки синтетической расшифровки
usr()  { printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":%s}]}}\n' "$(jq -Rn --arg t "$1" '$t')"; }
asst() { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(jq -Rn --arg t "$1" '$t')"; }
# Вход правки несёт то, что пишет (`new_string`), вход чтения — только путь: по этому устройству правка и узнаётся (D1329).
act()  { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":{"file_path":%s,"new_string":"x"}}]}}\n' \
                "$1" "$(jq -Rn --arg p "$2" '$p')"; }
rd()   { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":%s}}]}}\n' "$(jq -Rn --arg p "$1" '$p')"; }
sh_()  { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' "$(jq -Rn --arg c "$1" '$c')"; }

mk() { f="$TMP/$1.jsonl"; shift; : > "$f"; for l in "$@"; do printf '%s\n' "$l" >> "$f"; done; printf '%s' "$f"; }

CHAIN='Вширь по проявлениям: почему здесь, почему там, почему ещё. Корень найден.'

# T1 — речь есть, действий нет: исхода НЕТ (тот самый 61%)
T1=$(mk t1 "$(usr 'чини')" "$(asst "$CHAIN")")
OUT=$(rc_outcome_observed "$T1"); RC=$?
if [ "$RC" -eq 1 ] && [ -z "$OUT" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: разбор без единого действия сочтён имеющим исход: rc=$RC out='$OUT'"; fi

# T2 — правка механизма
T2=$(mk t2 "$(usr 'чини')" "$(asst "$CHAIN")" "$(act Edit "$HOOKS/five-whys-gate.sh")")
OUT=$(rc_outcome_observed "$T2"); RC=$?
if [ "$RC" -eq 0 ] && grep -q 'механизм' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2]: правка механизма не опознана исходом: rc=$RC out='$OUT'"; fi

# T3 — пункт долга
T3=$(mk t3 "$(usr 'чини')" "$(asst "$CHAIN")" "$(act Edit '/x/ClaudSoul/BACKLOG.md')")
OUT=$(rc_outcome_observed "$T3"); RC=$?
if [ "$RC" -eq 0 ] && grep -q 'долг' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: пункт долга не опознан исходом: rc=$RC out='$OUT'"; fi

# T4 — запись знания
T4=$(mk t4 "$(usr 'чини')" "$(asst "$CHAIN")" "$(act Write '/Users/x/.claude/global-lessons/case-2026-09-07-x.md')")
OUT=$(rc_outcome_observed "$T4"); RC=$?
if [ "$RC" -eq 0 ] && grep -q 'запись знания' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T4]: запись знания не опознана исходом: rc=$RC out='$OUT'"; fi

# T5 — вердикт «показалось»: единственный исход, наблюдаемый в речи
T5=$(mk t5 "$(usr 'чини')" "$(asst 'Проверил по трём местам — признака нет, показалось.')")
OUT=$(rc_outcome_observed "$T5"); RC=$?
if [ "$RC" -eq 0 ] && grep -q 'вердикт' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T5]: вердикт «показалось» не опознан исходом: rc=$RC out='$OUT'"; fi

# T6 — КОНТРПРИМЕР: правка вне носителей исхода
T6=$(mk t6 "$(usr 'чини')" "$(asst "$CHAIN")" "$(act Edit '/x/ClaudSoul/docs/architecture.md')")
OUT=$(rc_outcome_observed "$T6"); RC=$?
if [ "$RC" -eq 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T6]: правка документа сочтена исходом разбора: out='$OUT'"; fi

# T7 — КОНТРПРИМЕР: действие ДО последней реплики собеседника — прошлый ход
T7=$(mk t7 "$(usr 'первое')" "$(act Edit "$HOOKS/five-whys-gate.sh")" "$(usr 'второе')" "$(asst "$CHAIN")")
OUT=$(rc_outcome_observed "$T7"); RC=$?
if [ "$RC" -eq 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T7]: действие прошлого хода зачтено нынешнему: out='$OUT'"; fi

# T9 — КОНТРПРИМЕР: Bash, ЧИТАЮЩИЙ механизм, исходом не является. Без этой ноги признак
# «у Bash осматривается команда» зачёл бы любой grep по хуку за починку.
T9=$(mk t9 "$(usr 'чини')" "$(asst "$CHAIN")" \
     "$(printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"grep -n rc_trace hooks/five-whys-gate.sh"}}]}}')")
OUT=$(rc_outcome_observed "$T9"); RC=$?
if [ "$RC" -eq 1 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T9]: чтение механизма сочтено починкой: out='$OUT'"; fi

# T10 — Bash, ПИШУЩИЙ в механизм, исход даёт (способ работы этой сессии)
T10=$(mk t10 "$(usr 'чини')" "$(asst "$CHAIN")" \
     "$(printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"sed -i.bak s/a/b/ hooks/five-whys-gate.sh"}}]}}')")
OUT=$(rc_outcome_observed "$T10"); RC=$?
if [ "$RC" -eq 0 ] && grep -q 'починка механизма' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T10]: правка через Bash не опознана исходом: rc=$RC out='$OUT'"; fi

# T11–T15 — D1329: чтение и пустое перенаправление исходом не являются, слово вердикта судится по месту в речи.
none() {   # <метка> <что утверждается> <файл>
    OUT=$(rc_outcome_observed "$3"); RC=$?
    if [ "$RC" -eq 1 ] && [ -z "$OUT" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$1]: $2: rc=$RC out='$OUT'"; fi
}
none T11 "чтение хука и бэклога файловым инструментом сочтено исходом" \
    "$(mk t11 "$(usr 'чини')" "$(asst "$CHAIN")" "$(rd "$HOOKS/five-whys-gate.sh")" "$(rd '/x/ClaudSoul/BACKLOG.md')")"
none T12 "чтение с перенаправлением в /dev/null сочтено исходом" \
    "$(mk t12 "$(usr 'чини')" "$(asst "$CHAIN")" "$(sh_ 'grep -n rc_trace hooks/five-whys-gate.sh 2>/dev/null')" \
        "$(sh_ 'grep -c D1 BACKLOG.md >/dev/null')" "$(sh_ 'cat hooks/a.sh >>/dev/null 2>&1')" "$(sh_ 'ls hooks/a.sh &> /dev/null')")"
none T13 "«не показалось» сочтено вердиктом" "$(mk t13 "$(usr 'дефект?')" "$(asst 'Проверил: не показалось, дефект настоящий.')")"
none T14 "пересказ списка исходов и «показалось достаточно» сочтены вердиктом" \
    "$(mk t14 "$(usr 'что с поводом?')" "$(asst "Варианты: $(rc_resolution_kinds). Этой пары показалось достаточно.")")"
# T16 — каждая настоящая форма входа правки даёт исход (скептик D1329, M1 и M2): Write с `content`, Edit с `new_str`
# (так пишет соседний проект), MultiEdit с `edits`; публикация файла (путь и подпись) исходом не является.
wr() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$1" "$2"; }
for inp in '{"file_path":"hooks/a.sh","content":"x"}' '{"file_path":"hooks/a.sh","old_str":"a","new_str":"b"}' '{"file_path":"hooks/a.sh","edits":[]}'; do
    OUT=$(rc_outcome_observed "$(mk t16 "$(usr 'чини')" "$(asst "$CHAIN")" "$(wr Edit "$inp")")"); RC=$?
    if [ "$RC" -eq 0 ] && grep -q 'починка механизма' <<< "$OUT"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [T16]: правка со входом $inp не опознана: rc=$RC out='$OUT'"; fi
done
none T16d "публикация файла сочтена правкой" "$(mk t16d "$(usr 'чини')" "$(asst "$CHAIN")" "$(wr Artifact '{"file_path":"hooks/a.sh","label":"x"}')")"

# T15 — запись в файл рядом с /dev/null остаётся записью
T15=$(mk t15 "$(usr 'чини')" "$(asst "$CHAIN")" "$(sh_ 'printf x 2>/dev/null > hooks/five-whys-gate.sh')")
OUT=$(rc_outcome_observed "$T15"); RC=$?
if [ "$RC" -eq 0 ] && grep -q 'починка механизма' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T15]: запись в хук рядом с /dev/null не опознана: rc=$RC out='$OUT'"; fi

# T8 — нет файла: тихо, без исхода
OUT=$(rc_outcome_observed "$TMP/нет-такого.jsonl" 2>&1); RC=$?
if [ "$RC" -eq 1 ] && [ -z "$OUT" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T8]: отсутствие расшифровки не тихо: rc=$RC out='$OUT'"; fi

echo "outcome-observed: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
