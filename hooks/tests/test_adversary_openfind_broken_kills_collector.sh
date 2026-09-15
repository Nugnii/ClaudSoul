#!/usr/bin/env bash
# test_adversary_openfind_broken_kills_collector.sh — АТАКА 1.
#
# Утверждение библиотеки: «источник видов недоступен — это ПОЛОМКА, и она называется словом
# BROKEN» (hooks/lib/open-findings-lib.sh:34-36), код возврата 2.
#
# Проверяется НЕ библиотека, а её единственный потребитель. `session-collector.sh` идёт под
# `set -euo pipefail` (строка 15), а строка 578 — простое присваивание из подстановки:
#     _of_line=$(of_open_counts "$STATE_DIR" 2>/dev/null)
# Статус присваивания равен статусу подстановки, значит возврат 2 УБИВАЕТ весь хук Stop:
# ни свода, ни очереди pending-alerts, ни чистки состояния, ни строки systemMessage.
# Слово BROKEN не доходит никуда: `awk '{print $1 + 0}'` от «BROKEN» даёт 0.
#
# Ожидание: хук на Stop обязан отработать и НАЗВАТЬ поломку прибора.
# Факт: пустой вывод и код 2 — молчание там, где обязан быть крик.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
COLLECTOR="$REPO/hooks/session-collector.sh"
[ -f "$COLLECTOR" ] || { echo "FAIL: нет $COLLECTOR"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)   # ничего не удаляем: каталог остаётся для разбора
S="$TMP/state"; mkdir -p "$S" "$TMP/home/.claude/hooks" "$TMP/hooks"

# Песочница дерева хуков: копия, из которой можно убрать источник видов, не трогая репозиторий.
cp "$REPO"/hooks/*.sh "$TMP/hooks/" 2>/dev/null
# Библиотеки лежат в hooks/lib/, и глоб `hooks/*.sh` их не берёт: песочница расходилась
# бы с миром, а проверка в расходящейся рамке доказывает не то, о чём утверждает.
mkdir -p "$TMP/hooks/lib" && cp "$REPO"/hooks/lib/*.sh "$TMP/hooks/lib/" 2>/dev/null
cp -R "$REPO/hooks/lib" "$TMP/hooks/lib" 2>/dev/null

cat > "$S/outcome-adv1.jsonl" <<'J'
{"ts":"2026-09-01T10:00:00Z","key":"k1","signal":"discovery","outcome":"deferred","ref":""}
J

run_collector() {
    printf '{"session_id":"%s","transcript_path":"","cwd":"%s"}' "$1" "$TMP" \
        | env HOME="$TMP/home" STATE_DIR="$S" CLAUDE_CODE_SESSION_ID="$1" \
              bash "$TMP/hooks/session-collector.sh" 2>&1
}

# 0. ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: с доступным источником свод звучит. Без этого плеча падение
#    ниже не отличить от «песочница нерабочая».
CTRL=$(run_collector advctl); CTRL_RC=$?
if grep -qF "🔎" <<< "$CTRL"; then ok; else
    echo "SKIP: песочница не даёт свода даже при исправном приборе (rc=$CTRL_RC, вывод «${CTRL}»)"; exit 0
fi

# Убираем источник видов — тот самый вход, ради которого написана ветка BROKEN.
mv "$TMP/hooks/root-cause-lib.sh" "$TMP/rc-lib.moved"

OUT=$(run_collector advbroken); RC=$?

# 1. Хук обязан завершиться нормально: код Stop-хука читает харнесс.
[ "$RC" -eq 0 ] && ok || bad A1a "session-collector умер с кодом $RC — set -e на присваивании из of_open_counts"

# 2. Хук обязан вообще что-то сказать: в нём висят все алерты хода, очередь и чистка.
[ -n "$OUT" ] && ok || bad A1b "вывод пуст: свод, очередь pending-alerts и чистка состояния не выполнены вовсе"

# 3. Поломка прибора обязана быть НАЗВАНА, а не съедена арифметикой awk.
if grep -qE "BROKEN|сломан|поломк" <<< "$OUT"; then ok
else bad A1c "поломка не названа: «${OUT}» — «BROKEN» + 0 = 0, и потребитель молчит"
fi

# 4. ТОТ ЖЕ КОРЕНЬ ПРИ ЖИВОМ ИСТОЧНИКЕ ВИДОВ: интерпретатор ЕСТЬ, но падает.
#    `command -v python3` (open-findings-lib.sh:49) проверяет НАЛИЧИЕ имени, а не работу.
#    Шим pyenv с удалённой версией — ровно такой вход: имя есть, код 1. Возврат уходит
#    в присваивание под `set -e`, и Stop-хук снова умирает целиком.
mv "$TMP/rc-lib.moved" "$TMP/hooks/root-cause-lib.sh"
mkdir -p "$TMP/bin"
{
    echo '#!/bin/sh'
    echo 'echo "pyenv: version 3.12.0 is not installed" >&2'
    echo 'exit 1'
} > "$TMP/bin/python3"
chmod +x "$TMP/bin/python3"
OUT2=$(printf '{"session_id":"advpy","transcript_path":"","cwd":"%s"}' "$TMP" \
    | env PATH="$TMP/bin:$PATH" HOME="$TMP/home" STATE_DIR="$S" CLAUDE_CODE_SESSION_ID=advpy \
          bash "$TMP/hooks/session-collector.sh" 2>&1); RC2=$?
[ "$RC2" -eq 0 ] && [ -n "$OUT2" ] \
    && ok || bad A1d "python3 есть, но падает — Stop-хук умер целиком (код $RC2, вывод «${OUT2}»)"

echo "adversary openfind broken-kills-collector: $PASS passed, $FAIL failed (песочница: $TMP)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
