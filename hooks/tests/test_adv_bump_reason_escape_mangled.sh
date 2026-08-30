#!/usr/bin/env bash
# test_adv_bump_reason_escape_mangled.sh — два хранилища одного события обязаны совпасть.
#
# Результат: причина в знании и причина в журнале — одна строка, оба носителя валидны.
# Проверка результата: bash hooks/tests/test_adv_bump_reason_escape_mangled.sh даёт 0
#
# История файла. Заведён противником 29 августа 2026 как АТАКА «причина записывается не
# той, какой передана»: она уезжала в awk через `-v reason="$REASON"`, а присваивание `-v`
# разбирает escape в ЗНАЧЕНИИ (`\t` → табуляция, `\\` → одна косая). Текст мутировал молча,
# и — главное — расходился с durable-журналом, куда шёл через printf, минуя awk. Два
# хранилища противоречили друг другу на одном событии.
#
# Расхождение устранено: санитайзер причины приведён к ПРАВИЛУ носителей. Причина едет в
# три носителя с разными правилами экранирования — YAML-скаляр в двойных кавычках, строка
# JSON и значение `awk -v`, — поэтому остаётся только то, что безопасно во всех трёх:
# снимаются кавычка, обратная косая и управляющие символы.
#
# Потеря обратной косой — РЕШЕНИЕ, а не недосмотр, и тест закрепляет именно его. Довод:
# полное экранирование под три носителя требует учетверения косых на входе в awk (одно
# снятие в `-v`, второе — при печати в YAML-скаляр), то есть кода, чья правильность
# проверяется только такими же тестами; цена — реальная, выигрыш — дословность прозы в
# поле журнала. Причина остаётся читаемой: `C:\temp` становится `C:temp`.
#
# КОНТРПРИМЕР: `:` и `#` НЕ снимаются — внутри двойных кавычек YAML они безвредны.
# Если снимутся, тест покраснеет: это была бы порча осмысленного текста ради формы.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons" STATE_DIR="$T/state"
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR" "$STATE_DIR"
rc=0

cat > "$LESSONS_DIR/pattern-probe.md" <<'KN'
---
name: проба
confidence: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-01-01
source_cases: []
provenance_log: []
---
тело
KN

REASON=$(printf 'регулярка \\d+ не матчила путь C:\\temp; итог: 2 из 5 # хвост')
bash "$SCRIPT" pattern-probe confirmed "$REASON" case-x.md >/dev/null 2>&1

IN_KNOWLEDGE=$(python3 - "$LESSONS_DIR/pattern-probe.md" <<'PY'
import sys, yaml
fm = open(sys.argv[1], encoding="utf-8").read().split("---")[1]
d = yaml.safe_load(fm)
print(d["provenance_log"][-1]["reason"])
PY
) || { echo "FAIL: frontmatter знания не разобрался после записи"; rc=1; }

IN_JOURNAL=$(python3 - "$STATE_DIR/disagreement-outcomes.jsonl" <<'PY'
import sys, json
line = [l for l in open(sys.argv[1], encoding="utf-8") if l.strip()][-1]
print(json.loads(line)["case"])
PY
) || { echo "FAIL: строка durable-журнала не разобралась как JSON"; rc=1; }

echo "в знании: [$IN_KNOWLEDGE]"
echo "в журнале: [$IN_JOURNAL]"

# T1 — главное: два хранилища одного события не расходятся.
if [ "$IN_KNOWLEDGE" != "$IN_JOURNAL" ]; then
    echo "FAIL [T1]: хранилища расходятся на одном событии"; rc=1
fi

# T2 — опасное во всех трёх носителях снято.
case "$IN_KNOWLEDGE" in
    *\\*) echo "FAIL [T2]: обратная косая дошла до носителя"; rc=1 ;;
    *\"*) echo "FAIL [T2]: кавычка дошла до носителя"; rc=1 ;;
esac
printf '%s' "$IN_KNOWLEDGE" | LC_ALL=C grep -q '[[:cntrl:]]' && { echo "FAIL [T2]: управляющий символ дошёл до носителя"; rc=1; }

# T3 — КОНТРПРИМЕР: безвредное НЕ снимается, иначе санитайзер portит смысл.
case "$IN_KNOWLEDGE" in
    *"итог: 2 из 5"*) ;;
    *) echo "FAIL [T3]: двоеточие снято — санитайзер портит осмысленный текст"; rc=1 ;;
esac
case "$IN_KNOWLEDGE" in
    *"# хвост"*) ;;
    *) echo "FAIL [T3]: решётка снята — санитайзер портит осмысленный текст"; rc=1 ;;
esac

[ "$rc" -eq 0 ] && echo "adv bump reason-escape: passed" || echo "adv bump reason-escape: КРАСНЫЙ"
exit "$rc"
