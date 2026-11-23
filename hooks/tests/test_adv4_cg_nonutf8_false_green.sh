#!/usr/bin/env bash
# test_adv4_cg_nonutf8_false_green.sh
# АТАКА: completion-gate.sh читает BACKLOG.md как open(path, encoding="utf-8").read()
# БЕЗ try/except. Один невалидный UTF-8 байт (0xFF) в файле → python падает на .read()
# ДО единого print → stdout пуст (traceback съеден 2>/dev/null) → _out="" → срабатывает
# ветка elif [ -n "$_mt" ] и в OKF пишется mtime = ЗЕЛЁНЫЙ КЭШ. Красное ☑ D200 при этом
# не названо, и файл закэширован как «прошёл» — следующий Stop его пропустит.
#
# Ожидание: красное ☑ D200 (Проверка `false`) названо, зелёный кэш НЕ записан.
# Факт:     вывод пуст, OKF записан — false all-clear + отравленный кэш.
set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
# РАМКА ЗАДАЁТСЯ, А НЕ НАСЛЕДУЕТСЯ (D461, 18 сентября 2026). Гейт прогоняет «Проверку»
# пункта с BACKLOG_CHECKS_NESTED=1 (защита от кольца процессов), а предмет этого теста —
# сам гейт: под маркером он выходит молча, и тест краснел бы В РАМКЕ ЧЬЕГО-ТО ПУНКТА при
# зелёном прямом прогоне. Снимается здесь, а не у каждого вызова: вызовов в файле больше
# одного, и следующий добавленный унаследовал бы маркер молча.
unset BACKLOG_CHECKS_NESTED

HOOK="$(cd "$(dirname "$0")/.." && pwd)/completion-gate.sh"
TMP=$(mktemp -d)
mkdir -p "$TMP/state"
BL="$TMP/BACKLOG.md"

# Валидный UTF-8 каркас + ОДИН байт 0xFF в теле пункта. ☑=\342\230\221, ☐ не нужен.
# «Результат.»=\320\240..., «Проверка.»=\320\237...
printf '# BACKLOG\n\n' > "$BL"
printf '### D200 \342\230\221 red closure\n' >> "$BL"
printf '**\320\240\320\265\320\267\321\203\320\273\321\214\321\202\320\260\321\202.** paste \377 stray byte\n' >> "$BL"
printf '**\320\237\321\200\320\276\320\262\320\265\321\200\320\272\320\260.** `false` \342\206\222 0\n' >> "$BL"

# Канал — очередь pending-alerts (systemMessage снят 12 сентября 2026: в мобильном клиенте
# рендерится построчно); предмет ноги прежний.
printf '{"session_id":"adv4","cwd":"/"}' \
      | env CG_BACKLOG="$BL" STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
OUT=$(alerts_of "$TMP/state")

RC=0
if grep -q 'D200' <<< "$OUT"; then
    echo "PASS: красное ☑ D200 названо — атака не воспроизведена"
else
    echo "RED [ATTACK]: красное ☑ D200 НЕ названо — completion-gate упал на 0xFF и промолчал"
    echo "  вывод стража: [$OUT]"
    if ls "$TMP/state"/completion-gate-*.ok >/dev/null 2>&1; then
        echo "  УСУГУБЛЕНИЕ: OKF записан — файл закэширован как ЗЕЛЁНЫЙ, следующий Stop пропустит:"
        ls -la "$TMP/state"/completion-gate-*.ok
    fi
    RC=1
fi

echo "temp: $TMP (уберёт система)"
exit "$RC"
