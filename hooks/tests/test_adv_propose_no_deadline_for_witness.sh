#!/usr/bin/env bash
# СУДИТ: scripts/witness-subject-propose.sh
# АТАКА: свидетелю не поставлено срока — один зависший свидетель вешает объявлятеля навсегда.
#
# Вход: песочница, где свидетель не возвращается (`sleep 30`). Объявлятель запускает его
# без срока: контроль рамки — witness-subject-propose.sh:83-84, прогоны выхолащивания —
# hooks/subject-probe-lib.sh:52,69,107. Ни одного вызова `timeout` ни в объявлятеле, ни в
# приборе, ни в библиотеке (замер: `grep -c timeout` даёт 0, 0 и 2 — оба в комментариях).
#
# Ожидание: то же, что у набора дерева, — «Зависание — тоже провал и должно называться
# провалом» (hooks/tests/run_all.sh:10, сторож живёт в hooks/timeout-lib.sh). Свидетель
# снимается по сроку и НАЗЫВАЕТСЯ, работа продолжается.
# Факт: объявлятель ждёт столько, сколько живёт свидетель. Сам он зовётся реестром замеров
# (scripts/measurements.tsv:117), а тот исполняет команду через `eval` без срока
# (scripts/measurement-due.sh:267) — зависание уходит наверх целиком.
#
# ДОСТИЖИМОСТЬ ЧАСТИЧНАЯ И НАЗВАНА ЧЕСТНО: цепочка вызова без срока проверена (адреса выше),
# зависающий свидетель на нынешнем дереве НЕ предъявлен. Известно лишь, что сроком себя
# ограничивают 10 свидетелей из 544 — остальные полагаются на сторожа набора, которого у
# объявлятеля нет.
set -uo pipefail

command -v git     >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# ПЕСОЧНИЦА ОЧИЩАЕТ ЧУЖОЙ КОРЕНЬ (23 сентября 2026, находка замера instrument-result-measured).
# Тест строит СВОЁ дерево и зовёт в нём объявлятель, а тот зовёт прибор. Если в окружении
# осталась переменная корня от зовущего (а приборы её ставят — так делает и сам
# instrument-result-measured), вложенный прибор уходит судить ЧУЖОЕ дерево, возвращает пустой
# перечень, и объявлятель честно отвечает «объявлять нечего». Контраст прямой: с переменной
# 9 ног красных, без неё 9 из 9 зелёных.
unset CLAUDSOUL_REPO CLAUDSOUL_ROOT

TOOL="$REPO/scripts/witness-subject-propose.sh"
[ -f "$TOOL" ] || { echo "SKIP: нет $TOOL"; exit 0; }

BUDGET="${ADV_PROPOSE_BUDGET_S:-12}"   # сколько ждём объявлятеля
HANG="${ADV_PROPOSE_HANG_S:-30}"       # сколько «висит» свидетель

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"

D="$TMP/repo"
mkdir -p "$D/scripts" "$D/hooks/tests" "$D/.claude-docs"
cp "$TOOL" "$REPO/scripts/behavior-condition-probe.sh" "$D/scripts/"
# Сторож срока — сосед библиотеки выхолащивания, и без него она отвечает BROKEN. Забыли его
# 22 сентября 2026; на машине автора это маскировал фоллбек на ~/.claude, а замер suite-linux
# в чистом контейнере показал настоящее (23 сентября 2026).
cp "$REPO/hooks/subject-probe-lib.sh" "$REPO/hooks/frame-control-lib.sh" \
   "$REPO/hooks/state-lock-lib.sh" "$REPO/hooks/timeout-lib.sh" "$D/hooks/"
[ -f "$REPO/hooks/portable-lib.sh" ] && cp "$REPO/hooks/portable-lib.sh" "$D/hooks/"

printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$D/hooks/one.sh"
printf '#!/usr/bin/env bash\necho SECOND\nexit 0\n' > "$D/hooks/two.sh"
printf '#!/usr/bin/env bash\nsleep %s\nexit 0\n' "$HANG" > "$D/hooks/tests/test_adv_hangs.sh"
{
    printf 'hooks/one.sh\t\t\t\thooks/tests/test_adv_hangs.sh\n'
    printf 'hooks/two.sh\t\t\t\thooks/tests/test_adv_hangs.sh\n'
} > "$D/.claude-docs/dep-index.tsv"

( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }

# Срок задан ЯВНО, и нога судит его ДЕЙСТВЕННОСТЬ, а не умолчание (уточнено 22 сентября
# 2026 при починке). Атака доказала ОТСУТСТВИЕ срока — тогда объявлятель не возвращался ни
# при каком значении. Умолчание же взято у базиса (30 с при 90-м процентиле 7 с) и с
# бюджетом ноги в 12 с не сравнимо: сравнивать их значило бы судить выбор числа, а не
# механизм. Без срока эта нога красна при ЛЮБОМ SP_WITNESS_TIMEOUT — различение сохранено.
SP_WITNESS_TIMEOUT="${SP_WITNESS_TIMEOUT:-3}"; export SP_WITNESS_TIMEOUT
# Сторож свой: `timeout(1)` на macOS нет по умолчанию (повод hooks/timeout-lib.sh).
( cd "$D" && bash scripts/witness-subject-propose.sh > "$TMP/out" 2>&1 ) &
PID=$!
WAITED=0
while kill -0 "$PID" 2>/dev/null && [ "$WAITED" -lt "$BUDGET" ]; do
    sleep 1
    WAITED=$((WAITED + 1))
done

if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null || true
    bad D1 "объявлятель не вернулся за ${BUDGET} с: свидетель висит ${HANG} с, срока ему не поставлено"
else
    wait "$PID" 2>/dev/null || true
    ok
    OUT=$(cat "$TMP/out" 2>/dev/null || true)
    if grep -q 'test_adv_hangs' <<< "$OUT"; then ok
    else bad D2 "зависший свидетель не назван в отчёте: $OUT"; fi
fi

echo "test_adv_propose_no_deadline_for_witness: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
