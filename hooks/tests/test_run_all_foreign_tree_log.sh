#!/usr/bin/env bash
# СУДИТ: hooks/tests/run_all.sh
# test_run_all_foreign_tree_log.sh — набор, запущенный в ЧУЖОМ дереве, общего журнала не касается.
#
# Повод (22 сентября 2026). Правило было объявлено в шапке самого раннера: «прогон, идущий НЕ
# в своём репозитории, в общее состояние не пишет». Проверялись же два частных признака —
# маркер от родителя-НАБОРА и отсутствие git-контекста, — и оба промахивались мимо главного
# носителя: прибор ложной зелени гоняет свидетелей в СНИМКЕ, свидетели запускают набор, а
# маркера не ставит никто; git в снимке есть. Замер того дня: в общем журнале осталось шесть
# строк с кодом 137 от чужого прогона, и из этого журнала сторож берёт сроки, а замер цены —
# цену теста. Объявление было шире реализации (корень R5).
#
# Различение: до починки этот же прогон перезаписывал общий журнал целиком.
set -uo pipefail
command -v git >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$REPO/hooks/tests/run_all.sh"
[ -f "$RUNNER" ] || { echo "SKIP: нет $RUNNER"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
D="$TMP/foreign"; mkdir -p "$D/hooks/tests"
cp "$RUNNER" "$D/hooks/tests/"
# Раннер зовёт своих соседей по каталогу hooks — без них он не начнёт прогон и скажет об
# этом вслух (коды 2). Кладём ровно тех, кого он читает: сторож срока и его переносимость.
for _lib in timeout-lib.sh portable-lib.sh paths-lib.sh; do
    [ -f "$REPO/hooks/$_lib" ] && cp "$REPO/hooks/$_lib" "$D/hooks/"
done
printf '#!/usr/bin/env bash\necho "fixture: 1 passed, 0 failed"\nexit 0\n' > "$D/hooks/tests/test_fixture_ok.sh"
chmod +x "$D/hooks/tests/run_all.sh" "$D/hooks/tests/test_fixture_ok.sh"
( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 \
    || { echo "SKIP: git не отработал"; exit 0; }

# Общий журнал — ТОТ, что назван указателем установки; его состояние и охраняем.
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
LOG="$STATE/suite-run.tsv"
BEFORE="$TMP/before"
if [ -f "$LOG" ]; then cp "$LOG" "$BEFORE"; else : > "$BEFORE"; fi

# Переменные корня привязаны к чужому дереву НАМЕРЕННО: ровно так делает прибор, и ровно
# поэтому источником «своего дерева» служит указатель установки, а не они.
( cd "$D" && CLAUDSOUL_REPO="$D" CLAUDSOUL_ROOT="$D" TEST_TIMEOUT=10 \
    bash hooks/tests/run_all.sh ) >"$TMP/out" 2>&1
RC=$?

# T1 — общий журнал не тронут.
AFTER="$TMP/after"
if [ -f "$LOG" ]; then cp "$LOG" "$AFTER"; else : > "$AFTER"; fi
if cmp -s "$BEFORE" "$AFTER"; then ok
else bad T1 "прогон в чужом дереве перезаписал общий журнал $LOG"; fi

# T2 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: прогон вообще состоялся, иначе T1 зелена вхолостую.
if grep -qE 'passed|прошло|ПРОВАЛ|упало' "$TMP/out"; then ok
else bad T2 "набор в чужом дереве не отработал (код $RC), судить нечего: $(head -3 "$TMP/out")"; fi

# T3 — состояние УВЕДЕНО, а не потеряно: раннер называет свой журнал, и путь этот НЕ ведёт
# в общий каталог. Само наличие файла после прогона не судим: свой журнал вложенного прогона
# живёт во временном каталоге раннера (`OUT_DIR=$(mktemp -d)`) и уходит вместе с ним —
# требовать его существования значило бы судить не предмет, а уборку.
SAID=$(grep -F 'журнал прогона' "$TMP/out" | tail -1)
case "$SAID" in
    *"$STATE"*) bad T3 "раннер в чужом дереве назвал ОБЩИЙ журнал: $SAID" ;;
    '')         bad T3 "раннер не назвал журнал прогона — проверить некуда: $(tail -3 "$TMP/out")" ;;
    *)          ok ;;
esac

echo "test_run_all_foreign_tree_log: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
