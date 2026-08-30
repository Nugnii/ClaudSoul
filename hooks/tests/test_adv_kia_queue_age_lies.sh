#!/usr/bin/env bash
# test_adv_kia_queue_age_lies.sh — АТАКА на столбец «В очереди»: показанный возраст не
# обязан быть настоящим, а порог не обязан когда-нибудь сработать.
#
# Отчёт объявляет: «Срок стояния — N дн. Просроченный пункт роняет замер: очередь без срока
# это не очередь, а список (D106)» (knowledge-instrument-audit.sh:238-239). Проверяем, что
# число в столбце «В очереди» действительно измерено и что порог применим к каждому пункту.
#
# Три способа, которыми число оказывается неправдой:
#
# D1. Дата разбора вида `2026-13-45`. Проверка входа — регулярное выражение `\d{4}-\d{2}-\d{2}`
#     (строка 180), а не разбор даты. Мусор проходит фильтр, записывается В РЕЕСТР (строка 183)
#     и остаётся там навсегда: `queue_age` ловит ValueError и возвращает 0 (строки 187-191).
#     Пункт вечно «0 дн.» — НИКАКОЙ порог его не догонит, включая ноль дней.
#
# D2. Дата разбора в будущем. Отчёт печатает отрицательный срок стояния.
#
# D3. Даты разбора нет вовсе. Комментарий кода (строки 170-172) обещает: «Нет записанной даты
#     — считаем с сегодня и НЕ ВЫДАЁМ ЭТО ЗА ИЗМЕРЕННЫЙ ВОЗРАСТ». Вывод обещание не держит:
#     пункт с неизвестной датой входа и пункт, вошедший сегодня, дают в таблице дословно
#     одну и ту же ячейку «0 дн.».
#
# Достижимость D3 — боевая база, сегодня: `pattern-subject-of-measurement-mismatch` носит
# `instrument_verdict: candidate` c 29 июля 2026 (об этом же пишет шапка скрипта, строки
# 149-151) и НЕ имеет поля `instrument_assessed`. Прогон по копии базы показывает ему «0 дн.»
# — как и остальным пяти пунктам очереди.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$REPO/scripts/knowledge-instrument-audit.sh"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

T=$(mktemp -d); L="$T/l"; S="$T/s"; mkdir -p "$L" "$S"
mk() {  # mk <имя> <доп. строки frontmatter>
    cat > "$L/$1.md" <<KN
---
type: pattern
confirmed_count: 9
outcome: error
status: active
${2:-}
description: "проба"
---
# Тело
KN
}
row() { grep "\`$1\`" "$S/knowledge-instrument.md" | head -1; }
age_cell() { row "$1" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}'; }

mk pattern-broken 'instrument_verdict: candidate
instrument_assessed: 2026-13-45'
mk pattern-future 'instrument_verdict: candidate
instrument_assessed: 2099-01-01'
mk pattern-nodate 'instrument_verdict: candidate'
mk pattern-today

OUT=$(LESSONS_DIR="$L" STATE_DIR="$S" KIA_QUEUE_MAX_DAYS=0 bash "$AUDIT" 2>&1); RC=$?
echo "прогон при пороге 0 дн.: rc=$RC"
echo "$OUT" | sed 's/^/    /'
echo "--- реестр входа ---"; cat "$S/knowledge-instrument-queue.json"; echo
echo "--- строки таблицы ---"
for n in pattern-broken pattern-future pattern-nodate pattern-today; do echo "    $(row "$n")"; done

# --- D1: мусорная дата даёт вечный ноль и попадает в реестр ---
LEDGER_OK=$(python3 - "$S/knowledge-instrument-queue.json" <<'PY'
import json, sys, datetime, pathlib
d = json.loads(pathlib.Path(sys.argv[1]).read_text())
# Существо проверки — «неразбираемая дата не попадает в реестр», а не форма хранения.
# С 29 августа 2026 значение хранит ещё и происхождение даты (`{"since":…,"source":…}`),
# потому что провенанс, живший в памяти прогона, не переживал его: предположенная дата
# на втором прогоне читалась как измеренный возраст.
bad = []
for k, v in d.items():
    since = v.get("since") if isinstance(v, dict) else v
    try:
        datetime.date.fromisoformat(since)
    except Exception:
        bad.append(f"{k}={v!r}")
print(";".join(bad))
PY
)
if [ -z "$LEDGER_OK" ]; then ok D1a; else bad D1a "в реестр входа записана неразбираемая дата: $LEDGER_OK — возраст такого пункта навсегда 0"; fi

if grep -q "pattern-broken" <<< "$OUT"; then
    ok D1b
else
    bad D1b "при пороге 0 дн. пункт с датой 2026-13-45 не просрочен (ячейка «$(age_cell pattern-broken)») — ни один порог его не догонит"
fi

# --- D2: будущая дата даёт отрицательный срок стояния ---
case "$(age_cell pattern-future)" in
    -*) bad D2 "отчёт показывает отрицательный срок стояния: «$(age_cell pattern-future)»" ;;
    *)  ok D2 ;;
esac

# --- D3: неизвестный возраст напечатан так же, как измеренный ---
if [ "$(age_cell pattern-nodate)" = "$(age_cell pattern-today)" ]; then
    bad D3 "пункт с НЕИЗВЕСТНОЙ датой входа и пункт, вошедший сегодня, дают одну ячейку «$(age_cell pattern-nodate)» — обещание «не выдаём за измеренный возраст» не выполнено"
else
    ok D3
fi

# --- достижимость D3: боевая база, только чтение, состояние во временный каталог ---
LIVE="$HOME/.claude/global-lessons"
if [ -f "$LIVE/pattern-subject-of-measurement-mismatch.md" ]; then
    T2=$(mktemp -d); mkdir -p "$T2/l" "$T2/s"
    cp "$LIVE"/*.md "$T2/l/" 2>/dev/null
    LESSONS_DIR="$T2/l" STATE_DIR="$T2/s" bash "$AUDIT" >/dev/null 2>"$T2/err"
    RC=$?
    # rc=1 у аудита законен («отработал и нашёл»); смерть (>=2) или отсутствие артефакта
    # раньше опустошали блок улик молча, и тест проходил по FAIL=0 (D220).
    if [ "$RC" -ge 2 ] || [ ! -f "$T2/s/knowledge-instrument.md" ]; then
        bad D3live "прогон по копии боевой базы умер: rc=$RC, stderr: $(tail -c 200 "$T2/err" 2>/dev/null)"
    else
        ok D3live
    fi
    echo "--- боевая база (копия), флагманский пункт D106 ---"
    grep -n 'instrument_verdict\|instrument_assessed' "$LIVE/pattern-subject-of-measurement-mismatch.md" | sed 's/^/    /'
    grep 'pattern-subject-of-measurement-mismatch' "$T2/s/knowledge-instrument.md" | sed 's/^/    /'
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
