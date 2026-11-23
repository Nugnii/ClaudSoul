#!/usr/bin/env bash
# СУДИТ: hooks/tests/run_all.sh
# test_run_all_changed.sh — выборочный прогон берёт реестр «всегда» и связанных с правкой, а без правок не пустеет.
# en: selective run takes the always-list plus tests tied to edits, and never degrades to an empty set.
#
# Результат: `run_all.sh --changed` гонит меньше полного набора, но никогда не меньше реестра
#            `always-run.tsv`; без изменённых файлов он не вырождается в пустоту.
# Проверка результата: bash hooks/tests/test_run_all_changed.sh даёт 0
#
# Повод (11 сентября 2026, D392). Полный набор прогнан за сессию 18 раз по 4 минуты, а
# типичная правка трогала 0-1 механизм. Выборка по ОДНОМУ имени опасна и это измерено:
# добавление одного хука сломало семь тестов, ни один из которых с ним по имени не связан.
#
# Ноги держат обе стороны: без T2 тест зеленел бы у выборки, которая гонит вообще всё; без
# T1 и T3 — у выборки, которая пропускает сквозные тесты и оттого не ловит регресс.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
assert_contains() { if grep -Fq "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в: ${1}"; fi; }

ALWAYS="$DIR/always-run.tsv"
[ -f "$ALWAYS" ] || { echo "FAIL: нет реестра $ALWAYS"; exit 1; }

# --- T1: каждый тест реестра «всегда» существует на диске ---
# Реестр, назвавший несуществующий тест, молча сокращает выборку — и регресс проходит.
MISSING=""
while IFS=$'\t' read -r name _; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -f "$DIR/$name" ] || MISSING="$MISSING $name"
done < "$ALWAYS"
[ -z "$MISSING" ] && ok || bad T1 "в реестре «всегда» названы несуществующие тесты:$MISSING"

# --- T2: у каждой строки реестра есть ПРИЧИНА с датой наблюдения ---
# Список измерен поведением, и без причины строка неотличима от догадки.
NOREASON=""
while IFS=$'\t' read -r name why; do
    case "$name" in ''|'#'*) continue ;; esac
    case "$why" in *20[0-9][0-9]*) ;; *) NOREASON="$NOREASON $name" ;; esac
done < "$ALWAYS"
[ -z "$NOREASON" ] && ok || bad T2 "строки реестра без причины с датой:$NOREASON"

# --- T3: выборка НЕ МЕНЬШЕ реестра «всегда» ---
# Главная нога: выборочный прогон, потерявший сквозные тесты, бесполезен — он зелен на
# регрессе, который полный набор ловит.
N_ALWAYS=$(grep -vc '^#' "$ALWAYS" | tr -d ' ')
# `--list` печатает СОСТАВ выборки и выходит, ничего не прогоняя. Предмет этой ноги —
# размер выборки, а не результат тестов; первая редакция звала настоящий прогон и стоила
# 226 с, а в наборе уходила в таймаут 120 с. Тот же класс, что чинился этим днём в четырёх
# других тестах: тест зовёт прибор целиком ради одной его стороны.
OUT=$( (cd "$DIR" && bash run_all.sh --list 2>&1 | head -1) 2>&1 )
NUM=$(printf '%s' "$OUT" | grep -oE '[0-9]+ тест' | head -1 | grep -oE '[0-9]+')
if [ -n "$NUM" ] && [ "$NUM" -ge "$N_ALWAYS" ]; then ok
else bad T3 "выборка ($NUM) меньше реестра «всегда» ($N_ALWAYS) либо строка не напечатана: ${OUT}"; fi

# --- T4: выборка МЕНЬШЕ полного набора (иначе режим бессмыслен) ---
TOTAL=$(ls "$DIR"/test_*.sh | grep -c .)
if [ -n "$NUM" ] && [ "$NUM" -lt "$TOTAL" ]; then ok
else bad T4 "выборка ($NUM) не меньше полного набора ($TOTAL) — режим ничего не экономит"; fi

# --- T5: строка отчёта называет ОБА числа, иначе владелец не увидит, что прогон неполный ---
assert_contains "$OUT" "из $TOTAL" "T5: строка выборки не называет размер полного набора"

# --- T6-T8: ВТОРОЙ ШАГ выбора (13 сентября 2026) -----------------------------------------
# Повод измерен в тот день тремя покраснениями полного набора подряд, ни одного — в
# выборочном. Выбор по ОДНОМУ имени не видит теста, который зависит от механизма через
# посредника, а таких два вида, и оба проверяются ниже:
#   · через другой механизм: test_recheck_unproven_is_not_broken зовёт scripts/backlog-recheck.sh,
#     а сломала его правка hooks/lib/link_symmetry.py — имени библиотеки в тесте нет;
#   · через ТЕКСТ КОМАНДЫ пункта долга: test_backlog_green_side исполняет «Проверку» D358,
#     а та зовёт scripts/outcome-share.sh — имени скрипта в тесте тоже нет.
# `CHANGED_FILES` — шов для замера: подменяет список правок, не трогая рабочее дерево.
LIST_LS=$( (cd "$DIR" && CHANGED_FILES="hooks/lib/link_symmetry.py" bash run_all.sh --list 2>&1) )
assert_contains "$LIST_LS" "test_recheck_unproven_is_not_broken.sh" \
    "T6: зависимость через посредника-механизм не попала в выборку"

# Цель ноги — ИМЕННО путь «через номер пункта», а не реестр «всегда». Первая редакция
# спрашивала про test_backlog_green_side и была ПУСТОЙ: тот стоит в реестре и попадает в
# выборку всегда, поэтому зеленел бы и на снятом втором шаге — проверено мутантом.
# ПАРА ВЫВОДИТСЯ ИЗ ЖИВОГО БЭКЛОГА, а не вписана (14 сентября 2026). Прежняя редакция брала
# `outcome-share.sh` → `test_daily_signal_queued.sh`, и пара жила ровно до закрытия пункта
# D358: команда уехала в архив, нога покраснела на ЗАКРЫТИИ, а не на дефекте. Берём любой
# открытый пункт, чья «Проверка» называет тест ВНЕ реестра «всегда» и механизм из scripts/.
_PAIR=$(python3 - <<'PYPAIR' 2>/dev/null
import re, os
root = os.environ.get("CLAUDSOUL_REPO") or "."
always = set()
try:
    for line in open(os.path.join(root, "hooks/tests/always-run.tsv"), encoding="utf-8"):
        if line.strip() and not line.startswith("#"):
            always.add(line.split("\t")[0].strip())
except OSError:
    pass
try:
    text = open(os.path.join(root, "BACKLOG.md"), encoding="utf-8").read()
except OSError:
    raise SystemExit
for it in re.split(r"\n(?=- (?:\u2610|\u25d0) \*\*D)", text):
    if not re.match(r"- (\u2610|\u25d0) \*\*D", it):
        continue
    # ТОЛЬКО строка «Проверка»: выборка идёт по ней, а не по любому упоминанию в теле пункта.
    # Широкая редакция дала пару из разных абзацев D307 — связи между ними нет, и нога
    # краснела на несуществующей зависимости (14 сентября 2026).
    line = next((l for l in it.split("\n") if "**Проверка.**" in l), "")
    if not line:
        continue
    tests = sorted(set(re.findall(r"hooks/tests/(test_[a-z0-9_]+\.sh)", line)) - always)
    mechs = sorted(set(re.findall(r"\b(scripts/[a-z0-9-]+\.sh)", line)))
    if tests and mechs:
        print(mechs[0] + "\t" + tests[0])
        break
PYPAIR
)
if [ -z "$_PAIR" ]; then
    # Третье состояние: пары в бэклоге нет — это не «нога зелена», а «нечем проверить».
    echo "  … T7 пропущена: среди открытых пунктов нет пары «механизм + тест вне реестра»"
else
    _mech=${_PAIR%%	*}; _test=${_PAIR##*	}
    LIST_OS=$( (cd "$DIR" && CHANGED_FILES="$_mech" bash run_all.sh --list 2>&1) )
    assert_contains "$LIST_OS" "$_test" \
        "T7: зависимость через команду пункта долга не попала в выборку ($_mech → $_test)"
fi

# T8: КОНТРПРИМЕР — второй шаг не превращает выборку в полный набор.
# Без этой ноги оба требования выше зеленели бы у селектора, который просто гонит всё.
N_LS=$(printf '%s' "$LIST_LS" | grep -oE '[0-9]+ тест' | head -1 | grep -oE '[0-9]+')
TOTAL8=$(ls "$DIR"/test_*.sh | grep -c .)
if [ -n "$N_LS" ] && [ "$N_LS" -lt "$TOTAL8" ]; then ok
else bad T8 "выборка со вторым шагом ($N_LS) не меньше полного набора ($TOTAL8)"; fi

# T9: в выборку попадают ТОЛЬКО test_*.sh — та же популяция, что у полного прогона.
# Повод (13 сентября 2026): правка install.sh притащила из колонки `tests` учёта три
# файла каталога, тестами не являющихся, — `_decl_hooks.py` (помощник, исполнился как
# bash и высыпал разбор python), `drift-check.sh` (сверщик установки) и сам `run_all.sh`.
# Набор доложил три падения, ни одно из которых не дефект дерева. Знаменатель строки
# «из N» при этом считался по test_*.sh: гонялось то, чего в популяции нет.
LIST_NT=$( (cd "$DIR" && CHANGED_FILES="install.sh" bash run_all.sh --list 2>/dev/null) | tail -n +2 )
NON_TEST=$(printf '%s\n' "$LIST_NT" | grep -vcE '^test_.*\.sh$' || true)
if [ "${NON_TEST:-0}" -eq 0 ]; then ok
else bad T9 "в выборке не-тесты: $(printf '%s\n' "$LIST_NT" | grep -vE '^test_.*\.sh$' | tr '\n' ' ')"; fi
# Положительный контроль к T9: выборка по install.sh не пуста, иначе нога пройдёт вхолостую.
if [ "$(printf '%s\n' "$LIST_NT" | grep -c .)" -gt 5 ]; then ok
else bad T9б "выборка по install.sh пуста — T9 зелена вхолостую"; fi

# T10: реестр выбирает тест, называющий его в коде; документ и учёт — только реестр «всегда» (D1203). До D1203 ветка
# выбора знала лишь `*.sh|*.py`, и правка `hooks/lib/reply-readers.tsv` не выбирала ни одного своего теста.
_sel() { (cd "$DIR" && CHANGED_FILES="$1" bash run_all.sh --list 2>/dev/null) | tail -n +2 | sort; }
ALW10=$(_sel "none-$$.txt")   # имя собрано при прогоне: литерал в коде теста выбрал бы сам тест
grep -qx 'test_reply_readers_registry.sh' <<< "$(_sel hooks/lib/reply-readers.tsv)" && ok \
    || bad T10 "правка реестра читателей реплики не выбрала test_reply_readers_registry.sh"
[ "$(_sel BACKLOG.md)" = "$ALW10" ] && ok || bad T10б "правка документа выбрала тесты сверх реестра «всегда»"
[ "$(_sel .claude-docs/dep-index.tsv)" = "$ALW10" ] && ok || bad T10в "правка учёта выбрала тесты сверх реестра «всегда»"
# T10г–T10е — скептик opus по af02bfce (M2, M3, M1): живы были мутанты «данные по имени без расширения» (у `.gitignore`
# оно пустое, и `grep -F ""` выбирал весь набор) и «данные — только .tsv»; неотслеживаемый замок писателя входил в выбор.
[ "$(_sel .gitignore | grep -c .)" -lt "$(ls "$DIR"/test_*.sh | grep -c .)" ] && ok \
    || bad T10г "правка .gitignore выбрала весь набор — данные искались по пустому имени без расширения"
grep -qx 'test_env_pin.sh' <<< "$(_sel lib/env-pin.jq)" && ok || bad T10д "правка lib/env-pin.jq не выбрала test_env_pin.sh"
git -C "$DIR/../.." check-ignore -q BACKLOG.md.lock/owner && ok \
    || bad T10е "замок писателя не под .gitignore — неотслеживаемым он входит в выбор данными «owner»"

echo "run_all --changed: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
