#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_bash_write_dispatch.sh — свидетель диспетчера: правка КОМАНДОЙ доходит до стражей записи.
# live-home-ok: живой ~/.claude не читается — STATE_DIR и корень подменены песочницей.
# Предмет: нарушение, записанное командой, названо задним числом; чистый файл молчит;
# повтор по той же паре «файл + страж» молчит (дедуп); не-Bash событие не трогается;
# отсутствие стража в каталоге не роняет диспетчер.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
HOOK="$HOOK_DIR/bash-write-dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

REPO="$TMP/repo"; mkdir -p "$REPO/hooks/tests"
# Страж явного выхода зовёт соседа-сверщика из ТОГО ЖЕ дерева и без него молча выходит —
# песочница обязана нести его, иначе нога зеленеет вхолостую (проверено: без файла вывод пуст).
cp "$DIR/test_tests_exit_explicit.sh" "$REPO/hooks/tests/" 2>/dev/null || true
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  echo base > keep.txt && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_bash_write_dispatch.sh:$LINENO" >&2; exit 1; }

run() {  # run <state>
    printf '{"tool_name":"%s","session_id":"t-%s","cwd":"%s"}' "${2:-Bash}" "$1" "$REPO" \
        | env STATE_DIR="$TMP/state-$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null
}

# T1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: тест без явного выхода, записанный командой.
printf '#!/usr/bin/env bash\necho "нет выхода"\n' > "$REPO/hooks/tests/test_silent.sh"
O=$(run s1)
grep -qF "test-exit-explicit-guard" <<< "$O" && ok || bad T1 "нарушение не названо: ${O:0:160}"
grep -qF '"hookEventName":"PostToolUse"' <<< "$O" && ok || bad T1б "подача не протоколом"
grep -qF "Отказать уже нельзя" <<< "$O" && ok || bad T1в "цена события ПОСЛЕ записи не названа"

# T2 — дедуп: та же пара «файл + страж» второй раз молчит.
[ -z "$(run s1)" ] && ok || bad T2 "повтор по той же паре не заглушён"

# T3 — чистый файл: тишина, а не шум.
rm -f "$REPO/hooks/tests/test_silent.sh"
printf '#!/usr/bin/env bash\necho ок\nexit 0\n' > "$REPO/hooks/tests/test_clean.sh"
[ -z "$(run s3)" ] && ok || bad T3 "чистый файл дал находку"

# T4 — не Bash: диспетчер не наш путь не трогает.
printf '#!/usr/bin/env bash\necho "нет выхода"\n' > "$REPO/hooks/tests/test_silent2.sh"
[ -z "$(run s4 Edit)" ] && ok || bad T4 "событие Edit обработано диспетчером"

# T5 — стража нет в каталоге: не падаем, выходим тихо.
O5=$(printf '{"tool_name":"Bash","session_id":"t-s5","cwd":"%s"}' "$REPO" \
     | env STATE_DIR="$TMP/state-s5" PATHS_LIB="$HOOK_DIR/paths-lib.sh" HOME="$TMP" bash "$HOOK" 2>&1)
[ $? -eq 0 ] && ok || bad T5 "диспетчер упал"

# T6 — ПОТОЛОК ОТКЛАДЫВАЕТ, А НЕ ГАСИТ. Дедуп гасит показанное, потолок переносит показ:
# первая редакция ставила флаг дедупа ДО потолка, и отложенная находка пропадала навсегда,
# хотя текст обещал «ждут следующего хода». Дробь класса — 1 из 4 мест дерева, где дедуп и
# потолок стоят рядом.
rm -f "$REPO/hooks/tests/test_silent.sh" "$REPO/hooks/tests/test_silent2.sh"
printf '#!/usr/bin/env bash\necho "нет выхода"\n' > "$REPO/hooks/tests/test_a.sh"
printf '#!/usr/bin/env bash\necho "тоже нет"\n'   > "$REPO/hooks/tests/test_b.sh"
# Бюджет вызовов поднят намеренно: предмет ноги — потолок ПЕЧАТИ, и он обязан упереться
# первым. Иначе нога судила бы длину списка стражей, а не своё свойство.
O6=$(printf '{"tool_name":"Bash","session_id":"t-s6","cwd":"%s"}' "$REPO" \
     | env STATE_DIR="$TMP/state-s6" PATHS_LIB="$HOOK_DIR/paths-lib.sh" BASH_DISPATCH_MAX_SHOW=1 BASH_DISPATCH_MAX_RUNS=200 bash "$HOOK" 2>/dev/null)
grep -qF "и ещё 1" <<< "$O6" && ok || bad T6 "остаток не назван числом: ${O6:0:200}"
O6b=$(printf '{"tool_name":"Bash","session_id":"t-s6","cwd":"%s"}' "$REPO" \
      | env STATE_DIR="$TMP/state-s6" PATHS_LIB="$HOOK_DIR/paths-lib.sh" BASH_DISPATCH_MAX_SHOW=1 BASH_DISPATCH_MAX_RUNS=200 bash "$HOOK" 2>/dev/null)
if grep -qE "test_(a|b)\.sh" <<< "$O6b"; then ok
else bad T6б "отложенная находка не пришла следующим вызовом — потолок гасит вместо переноса"; fi
rm -f "$REPO/hooks/tests/test_a.sh" "$REPO/hooks/tests/test_b.sh"

# T7 — БЮДЖЕТ ВЫЗОВОВ тоже откладывает, а не гасит. Замер цены: 0,12 с на вызов стража,
# при восьми стражах и десятке файлов ход платил бы ~9 с. Бюджет режет число ВЫЗОВОВ за
# событие; пары, до которых очередь не дошла, флага не получают.
printf '#!/usr/bin/env bash\necho "нет выхода"\n' > "$REPO/hooks/tests/test_c.sh"
printf '#!/usr/bin/env bash\necho "нет выхода два"\n' > "$REPO/hooks/tests/test_d.sh"
run_budget() {
    printf '{"tool_name":"Bash","session_id":"t-s7","cwd":"%s"}' "$REPO" \
      | env STATE_DIR="$TMP/state-s7" PATHS_LIB="$HOOK_DIR/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=1 bash "$HOOK" 2>/dev/null
}
# Предмет ноги — «ни одна пара не потеряна», а НЕ «первый же вызов что-то скажет»:
# бюджет тратится на первую пару очереди, а она бывает молчащей (чистый файл), и это
# верное поведение. Проверяем накоплением по ходам.
# Число ходов в ноге НЕ ЗАШИТО: очередь пар растёт с каждым стражем в списке диспетчера,
# и порог «восемь» покраснел бы от добавления четвёртого стража — то есть судил бы длину
# списка, а не предмет. Крутим до тишины с названным потолком.
# Ранний выход «по трём молчаниям подряд» тоже оказался хрупким: молчащих стражей в
# списке несколько, и три подряд пустых вызова случаются ДО того, как очередь дойдёт до
# нарушения. Гоняем фиксированный запас — он покрывает пары «файл × страж» с избытком.
ALL=""
# Выход — по УСПЕХУ, а не по тишине (D1275): обе находки пришли — предмет доказан; потерянная пара по-прежнему крутит
# все 60 ходов и краснит ногу. Очередь пустела к 20-му ходу из 60 — 40 вызовов хука были лишними (13 с из 43 CPU).
for _i in $(seq 1 60); do
    ALL="${ALL}$(run_budget)"
    grep -qF "test_c.sh" <<< "$ALL" && grep -qF "test_d.sh" <<< "$ALL" && break
done
if grep -qF "test_c.sh" <<< "$ALL" && grep -qF "test_d.sh" <<< "$ALL"; then ok
else bad T7 "до тишины пришли не все находки: $(grep -oE 'test_[cd]\.sh' <<< "$ALL" | sort -u | tr '\n' ' ')"; fi
rm -f "$REPO/hooks/tests/test_c.sh" "$REPO/hooks/tests/test_d.sh"

# T8 — ПОДАЁТСЯ ТРОНУТОЕ, А НЕ ВСЁ ГРЯЗНОЕ. Повод измерен скептиком с положительным
# контролем: задне-числовая подача по всему грязному списку ГАСИЛА срабатывание стража на
# пути ДО записи (у него свой дроссель на сессию, журнал общий), и шум был на каждом третьем
# тронутом файле. Здесь: давно правленный грязный файл в подачу попасть не должен.
rm -f "$REPO/hooks/tests/test_a.sh" "$REPO/hooks/tests/test_b.sh" "$REPO/hooks/tests/test_c.sh" "$REPO/hooks/tests/test_d.sh"
printf '#!/usr/bin/env bash\necho "древнее нарушение"\n' > "$REPO/hooks/tests/test_old.sh"
touch -t 202001010000 "$REPO/hooks/tests/test_old.sh"
# Бюджет снят: предмет ноги — ВЫБОР подаваемых файлов, а не число вызовов за событие.
O8=$(printf '{"tool_name":"Bash","session_id":"t-s8","cwd":"%s"}' "$REPO" \
     | env STATE_DIR="$TMP/state-s8" PATHS_LIB="$HOOK_DIR/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=200 bash "$HOOK" 2>/dev/null)
if grep -qF "test_old.sh" <<< "$O8"; then bad T8 "давний грязный файл подан — слот дросселя крадётся у рабочего пути"; else ok; fi
# Положительный контроль к T8: свежая правка ТОГО ЖЕ файла подаётся.
printf '#!/usr/bin/env bash\necho "свежее нарушение"\n' > "$REPO/hooks/tests/test_old.sh"
O8b=$(printf '{"tool_name":"Bash","session_id":"t-s8b","cwd":"%s"}' "$REPO" \
      | env STATE_DIR="$TMP/state-s8b" PATHS_LIB="$HOOK_DIR/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=200 bash "$HOOK" 2>/dev/null)
grep -qF "test_old.sh" <<< "$O8b" && ok || bad T8б "свежая правка не подана — T8 зелена вхолостую"
rm -f "$REPO/hooks/tests/test_old.sh"

# T9 — СООБЩЕНИЕ НЕ РЕЖЕТСЯ ТАМ, ГДЕ ПОЛЕЗНО. Измерено на живом страже: у
# `backlog-touch-check` сообщение 564 знака, и ТРЕТИЙ исход — «пункт уже решён, а метка
# осталась» — стоит в самом хвосте. Прежний потолок 400 отрезал ровно его, а после записи
# файла этот исход вероятнее прочих. Признак ноги взят из мира: не длина числом, а наличие
# хвостовой фразы.
# Песочница — во временном каталоге исполнителя (D1224): судимый путь идёт стражу `backlog-touch-check.sh`, а
# тот судит правку во временном каталоге по корню бэклога, а не по форме пути, — на Linux (`/tmp`) путь внутри
# корня песочницы судится, как на macOS. Прежде фикстура лежала в HOME, и снятый по сроку тест её там оставлял.
# Второй trap ПЕРЕОПРЕДЕЛЯЕТ первый (строка 12), поэтому убирает оба каталога.
T9ROOT=$(mktemp -d); trap 'rm -rf "$TMP" "$T9ROOT"' EXIT
LONG="$T9ROOT/repo-long"; mkdir -p "$LONG/hooks"
# ПОСТРОЙКА ПЕСОЧНИЦЫ ГОВОРИТ, ЕСЛИ НЕ УДАЛАСЬ (род B, 14 сентября 2026). Прежняя редакция
# глушила вывод git целиком, и на раннере CI нога падала с ПУСТЫМ сообщением: «сломалась
# установка» было неотличимо от «страж промолчал». Локально дефект невоспроизводим — здесь
# git настроен; на чистой машине отсутствие имени автора роняет коммит.
_S9ERR=$( ( cd "$LONG" && git init -q . \
    && echo base > keep.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 )
_S9RC=$?
cp "$HOOK_DIR/backlog-lib.sh" "$HOOK_DIR/paths-lib.sh" "$LONG/hooks/" 2>/dev/null || true
printf '#!/usr/bin/env bash\necho x\n' > "$LONG/hooks/probe-target.sh"
printf -- '- ☐ **D999** Проба длины сообщения.\n  **Дефект.** Страж `probe-target.sh` молчит на пустом входе.\n  **Проверка.** `false` → 0\n' > "$LONG/BACKLOG.md"
O9=$(printf '{"tool_name":"Bash","session_id":"t-s9","cwd":"%s"}' "$LONG" \
     | env STATE_DIR="$TMP/state-s9" PATHS_LIB="$HOOK_DIR/paths-lib.sh" CLAUDSOUL_ROOT="$LONG" \
           BASH_DISPATCH_MAX_RUNS=200 bash "$HOOK" 2>/dev/null)
if [ "${_S9RC:-0}" -ne 0 ]; then
    bad T9 "песочница не собралась (git rc=${_S9RC}): ${_S9ERR:0:200} — это отказ установки, а не молчание стража"
elif grep -qF "закрой его с показанием" <<< "$O9"; then ok
else bad T9 "хвост сообщения отрезан — теряется третий исход. Вывод стража: «${O9:0:200}»; песочница: $(ls "$LONG" 2>&1 | tr '\n' ' ' | cut -c1-80)"; fi

echo "test_bash_write_dispatch: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
