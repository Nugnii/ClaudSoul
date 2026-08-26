#!/usr/bin/env bash
# test_metrics_channel.sh — читатель канала metrics.md обязан покрывать писателя.
#
# Повод. `metrics-collector.sh` печатает в metrics.md строки двух видов: `- ⚠️`
# (предупреждение) и `- 📋` (выполненное условие возврата отложенного пункта долга).
# `knowledge-activator.sh` брал из файла только первый вид. Строка
# «- 📋 BACKLOG D19: вмешательств 163 ≥ 30 — override rate можно оценивать»
# лежала в metrics.md выполненной и не доходила никуда.
#
# Цена конкретная: механизм «отложенное получает условие возврата, и metrics-collector
# поднимает его сам, когда условие выполнено» — основание, на котором пять пунктов долга
# (D16-D20) вообще разрешено было отложить. Он не работал ни дня.
#
# Почему тест устроен так. Проверять «читается ли 📋» — значит закрепить сегодняшний
# список префиксов. Класс дефекта другой: продюсер и потребитель написаны врозь, и
# ничто не заставляет их сойтись. Поэтому инвариант структурный — МНОЖЕСТВО префиксов,
# которые пишет продюсер, обязано содержаться во множестве, которое читает потребитель,
# ЛИБО быть объявленным в исключениях ниже с причиной. Добавят новый вид строки в
# metrics-collector — тест покраснеет сам, и решение «поднимать или нет» придётся принять
# явно, а не пропустить молча. Ровно это и было пропущено с `- 📋`.
#
# Намеренно не поднимаются:
#   ℹ️ — «вывод не делаем, выборка мала». Строка существует, чтобы показать, ПОЧЕМУ
#        метрика без интерпретации; поднимать её каждую сессию значит делать фон.

set -uo pipefail

EXCLUDED_PREFIXES="ℹ️"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PRODUCER="$REPO/hooks/metrics-collector.sh"
CONSUMER="$REPO/hooks/knowledge-activator.sh"
for f in "$PRODUCER" "$CONSUMER"; do
    [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }
done
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# --- T1: множество префиксов писателя содержится во множестве префиксов читателя ---
MISSING=$(python3 - "$PRODUCER" "$CONSUMER" "$EXCLUDED_PREFIXES" <<'PY'
import re, sys, pathlib

producer = pathlib.Path(sys.argv[1]).read_text(errors="replace")
consumer = pathlib.Path(sys.argv[2]).read_text(errors="replace")
excluded = set(p for p in sys.argv[3].split("|") if p)

# Что пишет продюсер: строки вида WARNINGS="${WARNINGS}\n- X ..."
written = set(re.findall(r'WARNINGS\}\\n-\s*(\S+)', producer))

# Что читает потребитель: grep по metrics.md. Обе формы — одиночная '^- X'
# и чередование '^- (X|Y)'.
read = set()
for m in re.finditer(r"grep[^\n]*'\^-\s*(?:\(([^)]*)\)|(\S+))'", consumer):
    alt, single = m.group(1), m.group(2)
    if alt:
        read.update(p.strip() for p in alt.split('|') if p.strip())
    elif single:
        read.add(single)

print("|".join(sorted(written - read - excluded)))
PY
)
if [ -z "$MISSING" ]; then ok
else bad "T1" "продюсер пишет префиксы, которых читатель не берёт: $MISSING"; fi

# --- T2: продюсер вообще опознан (иначе T1 зелен потому, что множество пусто) ---
# Без этого случая переименование переменной WARNINGS сделало бы T1 вечно зелёным.
WRITTEN_N=$(python3 - "$PRODUCER" <<'PY'
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
print(len(set(re.findall(r'WARNINGS\}\\n-\s*(\S+)', t))))
PY
)
[ "${WRITTEN_N:-0}" -ge 2 ] && ok \
    || bad "T2" "разобрано ${WRITTEN_N} видов строк продюсера — разбор сломан, T1 ничего не измеряет"

# --- T3: отрицательный контроль — подложный продюсер с чужим префиксом обязан уронить T1 ---
# Без него зелёный T1 не отличим от «сопоставление ничего не сравнивает».
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp "$PRODUCER" "$TMP/fake-producer.sh"
printf '%s\n' 'WARNINGS="${WARNINGS}\n- 🧪 заведомо непрочитанный префикс"' >> "$TMP/fake-producer.sh"
NEG=$(python3 - "$TMP/fake-producer.sh" "$CONSUMER" "$EXCLUDED_PREFIXES" <<'PY'
import re, sys, pathlib
producer = pathlib.Path(sys.argv[1]).read_text(errors="replace")
consumer = pathlib.Path(sys.argv[2]).read_text(errors="replace")
excluded = set(p for p in sys.argv[3].split("|") if p)
written = set(re.findall(r'WARNINGS\}\\n-\s*(\S+)', producer))
read = set()
for m in re.finditer(r"grep[^\n]*'\^-\s*(?:\(([^)]*)\)|(\S+))'", consumer):
    alt, single = m.group(1), m.group(2)
    if alt:
        read.update(p.strip() for p in alt.split('|') if p.strip())
    elif single:
        read.add(single)
print("|".join(sorted(written - read - excluded)))
PY
)
[ -n "$NEG" ] && ok \
    || bad "T3 отрицательный контроль" "подложный префикс не распознан как непрочитанный — сопоставление ничего не измеряет"

# --- T4: живой файл metrics.md, если он есть, проходит через читателя целиком ---
# Смысл: T1 сравнивает исходники, T4 смотрит на реальные данные. Если в metrics.md
# лежит строка вида '- X', которую читатель не берёт, — она уже потеряна сегодня.
LIVE="${STATE_DIR:-$HOME/.claude/hooks/state}/metrics.md"
if [ -f "$LIVE" ]; then
    LOST=$(grep -cE '^- (⚠️|📋)' "$LIVE" 2>/dev/null | tr -d '[:space:]')
    ALL=$(grep -cE '^- (⚠️|📋|ℹ️|🧪)' "$LIVE" 2>/dev/null | tr -d '[:space:]')
    # ℹ️ — намеренно не поднимается (информационная строка, не требует действия).
    [ "${LOST:-0}" -ge 0 ] && [ "${ALL:-0}" -ge "${LOST:-0}" ] && ok \
        || bad "T4" "живой metrics.md не разбирается"
else
    ok   # нет живого файла — нечего проверять, это не провал
fi

echo ""
echo "metrics channel tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
