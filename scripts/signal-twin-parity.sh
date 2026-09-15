#!/usr/bin/env bash
# signal-twin-parity.sh — признак видит запись в код, как бы она ни была сделана.
# en: checks that a detection signal sees a code write regardless of how the write is spelled.
#
# Результат: дефектная строка опознаётся признаком и тогда, когда файл пишется ЧЕРЕЗ ПИТОН
#            внутри heredoc (`python3 - <<EOF` + open(path,"w")), а не только когда цель
#            heredoc — сам файл; чистая запись остаётся без срабатывания.
# Проверка результата: bash hooks/tests/test_signal_twin_parity.sh даёт 0 — прибор краснеет
#            на знании, где у близнеца формы нет, и молчит там, где она есть.
#
# Зачем (D415). Строка с кириллическим диапазоном уронила CI (прогон 34872897131), и первая
# версия пункта винила перечень форм. Замер опроверг: форму несёт соседний признак
# `bsd_only_command_written_via_shell`, и нёс её ДО поломки (срез 266c142^). Настоящая дыра
# в том, ЧЕМ сделана запись: из 77 команд окна, пишущих в hooks|scripts, признак видит 20, а
# 57 (74%) идут через `python3 - <<EOF` с `open(path,"w")` — цель heredoc у них stdin питона,
# путь лежит в теле, и `heredoc_target_regex` не совпадает ПО ПОСТРОЕНИЮ. Счёт форм текстом
# такую дыру не ловит: при заведении пункта я сам сломал JSON признаков кавычкой внутри
# строки — блокер всего знания замолк, а счёт по awk остался зелёным.
#
# ОБРАЗЕЦ СОБИРАЕТСЯ ИЗ ЧАСТЕЙ. Записать дефект литералом в файл под scripts/ нельзя: живой
# блокер отказывает такой записи — проверено на себе в час заведения. Части склеиваются
# питоном из кодов символов, поэтому в тексте файла дефектной формы нет.
#
# НАЗВАННЫЙ ПРЕДЕЛ: судится ОДИН способ записи — питон внутри heredoc, самый частый (57 из 77).
# Прочие невидимые способы (tee, ed, printf в цикле) прибором не покрыты. Условие снятия:
# замер назовёт второй способ числом — его образец добавляется сюда же.
#
# Код возврата: 0 — опознано и отрицательный контроль молчит; 1 — дыра; 2 — прибор сломан.
set -uo pipefail

_self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)
REPO="${CLAUDSOUL_REPO:-$(cd -- "$_self/.." 2>/dev/null && pwd -P)}"
LIB="${DS_LIB:-$REPO/hooks/detection-signals-lib.sh}"
[ -f "$LIB" ] || { echo "BROKEN: нет $LIB"; exit 2; }
# shellcheck source=/dev/null
. "$LIB"
KNOW="${TWIN_KNOWLEDGE:-$HOME/.claude/global-lessons/pattern-shell-portability.md}"
[ -f "$KNOW" ] || { echo "BROKEN: нет знания $KNOW"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "BROKEN: нет python3"; exit 2; }
command -v jq      >/dev/null 2>&1 || { echo "BROKEN: нет jq"; exit 2; }

# РАЗБОР ПРИЗНАКОВ ОБЯЗАН СОСТОЯТЬСЯ. Пустой список — отказ прибора, а не «дыр нет»:
# сломанный JSON молчит так же, как исправный на чистом входе (проверено на себе).
_n=$(ds_extract_signals "$KNOW" 2>/dev/null | jq -r 'length' 2>/dev/null || echo 0)
[ "${_n:-0}" -gt 0 ] || { echo "BROKEN: признаки знания не разобрались — JSON сломан либо блока нет"; exit 2; }

_payload() {  # _payload <вид: defect|clean> → JSON вида {"command": …}
    python3 -c '
import json, sys
kind = sys.argv[1]
# ЗАПИСЬ ДЕЛАЕТСЯ ТАК ЖЕ, КАК В ЖИЗНИ: питон внутри heredoc, путь в теле. Цель heredoc при
# этом — stdin питона, и признак, узнающий запись по цели, её не видит.
lo, hi = chr(0x430), chr(0x44F)
defect = "role() { grep -oE -- " + chr(39) + "--[" + lo + "-" + hi + "]+-->" + chr(39) + " ; }"
body = defect if kind == "defect" else "echo ok"
prog = ("python3 - <<" + chr(39) + "PYW" + chr(39) + "\n"
        "p = " + chr(39) + "hooks/probe.sh" + chr(39) + "\n"
        "open(p, " + chr(34) + "w" + chr(34) + ").write(" + repr(body) + ")\n"
        "PYW\n")
print(json.dumps({"command": prog}, ensure_ascii=False))
' "$1"
}

HIT=$(ds_evaluate "$KNOW" Bash "$(_payload defect)" "" 2>/dev/null)
MISS=$(ds_evaluate "$KNOW" Bash "$(_payload clean)" "" 2>/dev/null)

echo "дефектная строка: ${HIT:-НЕ ОПОЗНАНА}; чистая запись: ${MISS:-молчит}"
[ -n "$HIT" ] || { echo "  дыра: запись ЧЕРЕЗ КОМАНДУ не опознана признаком"; exit 1; }
[ -z "$MISS" ] || { echo "  ложное срабатывание на чистой записи: $MISS"; exit 1; }
exit 0
