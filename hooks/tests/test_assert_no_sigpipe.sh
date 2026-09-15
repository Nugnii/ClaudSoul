#!/usr/bin/env bash
# test_assert_no_sigpipe.sh — утверждение теста не имеет права врать под нагрузкой.
#
# Повод (D59, доказано замером 2026-08-11). Идиом `echo "$haystack" | grep -q "$needle"`
# под `set -o pipefail` возвращает 141: grep выходит по первому совпадению, echo получает
# SIGPIPE, и pipefail отдаёт статус УБИТОГО producer'а, а не нашедшего потребителя.
# Утверждение читает 141 как «не найдено» — при том что строка в выводе есть.
#
# Замер на живой фикстуре (3 КБ, одно совпадение): в тишине 0 ложных «не найдено»
# на 400 прогонов, под нагрузкой 8 на 2000 — и все восемь с кодом 141. При ~47
# утверждениях в файле это даёт около одного ложного падения на шесть прогонов;
# ровно так и выглядели три красных прогона CI, где код метрик никто не трогал.
#
# Класс тот же, что в BACKLOG D50 (`cmd | grep -q` под pipefail). Он ВЫРАЗИМ синтаксисом,
# а не суждением, — поэтому здесь страж, а не строчка в документации: правило «так не
# писать» дважды напомненное и не исполненное есть правило, которого нет.
#
# Лечение: труба заменяется на herestring — `grep -q "$needle" <<< "$haystack"`.
# Статус берётся у grep, producer'а в конвейере больше нет, SIGPIPE неоткуда взяться.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# Producer перед `| grep -…q`. Ищем именно ранний выход потребителя (-q): `grep -c`
# читает вход до конца и SIGPIPE не вызывает. Producer любой, включая внешние команды:
# оценка «опасен только внешний» опровергнута замером — встроенный `echo "$var"` под
# нагрузкой тоже не успевает дописать (8 ложных ответов на 2000 прогонов).
# Признак берётся у владельца — `token_sigpipe_re` в hooks/portable-lib.sh: тот же, что у стража
# момента записи (pipefail-grep-q-notice). До 13 сентября 2026 здесь лежала своя копия строки —
# носитель рода K: правило вынесено в модуль, а копия у потребителя осталась.
. "$DIR/../portable-lib.sh"
SIGPIPE_RE=$(token_sigpipe_re)
[ -n "$SIGPIPE_RE" ] || { echo "FAIL: token_sigpipe_re пуст — владелец признака не отвечает"; exit 1; }

# --- T1: ни тест, ни хук не берут ответ у трубы с ранним выходом ---
# Область — ВСЕ файлы shell дерева (`git ls-files '*.sh'`), а не две стороны закольцовки.
# До 13 сентября 2026 сканер смотрел на тесты (где класс подделывал вердикт) и hooks/*.sh (где
# он тихо инвертирует ответ защиты). Замер suite-linux того дня нашёл носителя в тесте, а обход
# дерева тем же признаком — ещё 15 строк в 13 файлах вне поля зрения: security/scan.sh
# (наличие файлов языка под нагрузкой читалось как «нет»), install.sh и uninstall.sh
# (регистрация MCP), scripts/count-stats.sh (писатель списков deny/ask реестра чисел; труба на
# строке-продолжении), scripts/state-prune.sh (семейство KEEP могло уйти под чистку),
# scripts/sync-drifted.sh (BROKEN сверщика читался как «сравнил»), hooks/tests/run_all.sh (тест
# мог не попасть в выборочный прогон) и другие. Исключены scripts/probes/*.sh: там табличные
# данные с разделителем `|`, третий столбец — команда, и «труба» перед grep -q — разделитель.
# Без git (дерево скопировано без .git) область берётся обходом find — узко, но не пусто.
ROOT="$(cd "$DIR/../.." && pwd)"
FILES=$(cd "$ROOT" && git ls-files '*.sh' 2>/dev/null | grep -v '^scripts/probes/')
[ -n "$FILES" ] || FILES=$(cd "$ROOT" && find . -name '*.sh' -not -path './.git/*' -not -path '*/node_modules/*' -not -path './scripts/probes/*' | sed 's|^\./||')
[ -n "$FILES" ] || bad "T1" "ни git ls-files, ни find не дали ни одного .sh — область пуста"
join_continuations() {  # склеивает строки-продолжения (\): многострочный конвейер судится целиком
    awk '{ line = $0
           while (line ~ /\\$/ && (getline nl) > 0) { sub(/\\$/, "", line); line = line nl }
           print line }' "$1"
}
OFFENDERS=""
for rel in $FILES; do
    f="$ROOT/$rel"
    [ -f "$f" ] || continue
    # Себя пропускаем: в фикстурах T2/T3 дефектный идиом стоит намеренно, как образец.
    [ "${f##*/}" = "test_assert_no_sigpipe.sh" ] && continue
    # Библиотеки проверяются ВСЕГДА, даже без своей строки `pipefail`: они исполняются
    # под опциями вызывающего. `hook-input-lib.sh` своего pipefail не ставит, а
    # `itr-event-detector.sh` и `reformulation-tracker.sh` ставят `set -eo pipefail` —
    # дефект в библиотеке был живым и невидимым для этой проверки (27 августа 2026).
    case "${f##*/}" in
        *-lib.sh) ;;
        *) grep -Eq 'set -[a-z]*o pipefail|set -o pipefail' "$f" || continue ;;
    esac
    # `grep -c` при нуле совпадений печатает 0 И возвращает 1: `|| echo 0` дописал бы
    # второй ноль, и `[` получил бы «0\n0». Гасим статус, а не дублируем вывод.
    # Метка `# sigpipe-ok: <причина>` снимает строку с учёта: дефектный идиом бывает
    # ПРЕДМЕТОМ проверки (отрицательный контроль в test_launchd_freshness), и запрет
    # без исключения заставил бы удалить доказательство вместо дефекта. Причина
    # обязательна — метка без неё не считается.
    # Строки-комментарии отбрасываются до счёта: в шапках хуков этот идиом описан прозой
    # («прежняя форма `find … | grep -q .` возвращает 141»), и считать объяснение
    # нарушением значило бы требовать стереть память о дефекте вместе с дефектом.
    hits=$({ join_continuations "$f" 2>/dev/null | grep -E "$SIGPIPE_RE" || true; } \
        | { grep -Ev '^[[:space:]]*#' || true; } \
        | { grep -Evc '# sigpipe-ok: *[^ ]' || true; } | tr -d '[:space:]')
    [ "${hits:-0}" -gt 0 ] && OFFENDERS="${OFFENDERS}  ${rel}: ${hits}\n"
done
if [ -z "$OFFENDERS" ]; then ok
else
    bad "T1" "утверждения через трубу с grep -q под pipefail (соврут под нагрузкой):"$'\n'"$(printf '%b' "$OFFENDERS")  замена: grep -q \"\$needle\" <<< \"\$haystack\""
fi

# --- T2: отрицательный контроль — сканер видит подложенный идиом ---
FIX=$(mktemp)
printf '#!/usr/bin/env bash\nset -uo pipefail\nif echo "$HAY" | grep -Fq "$N"; then :; fi\n' > "$FIX"
if grep -Eq "$SIGPIPE_RE" "$FIX"; then ok; else bad "T2" "сканер не увидел заведомо дефектный идиом"; fi
rm -f "$FIX"

# --- T3: лечение herestring'ом сканер НЕ считает нарушением ---
FIX=$(mktemp)
printf '#!/usr/bin/env bash\nset -uo pipefail\nif grep -Fq "$N" <<< "$HAY"; then :; fi\n' > "$FIX"
if grep -Eq "$SIGPIPE_RE" "$FIX"; then bad "T3" "herestring помечен нарушением — страж запрещает лечение"; else ok; fi
rm -f "$FIX"

# --- T5: `| head` в строгих хуках не отдаёт статус трубы под set -e ---
# Класс D239, зеркальный T1: там ранний выход у потребителя (grep -q), здесь у head.
# Область — ТОЛЬКО файлы hooks/*.sh с set -e + pipefail: там у продолжения ровно одно
# последствие — 141 производителя убивает хук (реестр 64 мест, 8 носителей — BACKLOG
# D239). В файлах без -e статус подстановки выбрасывается, и отказ был бы ложным;
# в библиотеках последствие зависит от места конвейера в функции — обе зоны остаются
# суждению, не сканеру (case-2026-08-28-enforcement-is-a-property-of-consequence).
# Строки-продолжения (\) склеиваются до счёта: `|| true` на хвосте многострочного
# конвейера — защита (живой образец metrics-collector.sh:224-225).
scan_head_pipes() {
    join_continuations "$1" \
        | { grep -E '\|[[:space:]]*head([[:space:]]|$)' || true; } \
        | { grep -Ev '^[[:space:]]*#' || true; } \
        | { grep -Ev '\|\|[[:space:]]*true' || true; } \
        | { grep -Evc '# sigpipe-ok: *[^ ]' || true; } | tr -d '[:space:]'
}
HEAD_OFFENDERS=""
for f in "$DIR"/../*.sh; do
    case "${f##*/}" in *-lib.sh) continue ;; esac
    grep -Eq 'set -[a-z]*e[a-z]*o pipefail' "$f" || continue
    hits=$(scan_head_pipes "$f")
    [ "${hits:-0}" -gt 0 ] && HEAD_OFFENDERS="${HEAD_OFFENDERS}  ${f##*/}: ${hits}\n"
done
if [ -z "$HEAD_OFFENDERS" ]; then ok
else
    bad "T5" "незащищённый \`| head\` под set -e + pipefail (141 производителя убьёт хук):"$'\n'"$(printf '%b' "$HEAD_OFFENDERS")  лечение: лимит внутри awk (NR<=N), либо \`|| true\` на конвейер, либо \`# sigpipe-ok: <причина>\`"
fi

# --- T6: отрицательный контроль — сканер видит подложенный head-идиом ---
FIX=$(mktemp)
printf '#!/usr/bin/env bash\nset -euo pipefail\nx=$(jq -r .a "$f" | head -1)\n' > "$FIX"
if [ "$(scan_head_pipes "$FIX")" -gt 0 ]; then ok; else bad "T6" "сканер не увидел заведомо дефектный head-идиом"; fi
rm -f "$FIX"

# --- T7: лечение и многострочный || true сканер НЕ считает нарушением ---
FIX=$(mktemp)
printf '#!/usr/bin/env bash\nset -euo pipefail\nx=$(jq -r .a "$f" | head -1 || true)\ny=$(sort "$f" | head -5 | \\\n    awk "{print}" || true)\n' > "$FIX"
if [ "$(scan_head_pipes "$FIX")" -eq 0 ]; then ok; else bad "T7" "защищённые конвейеры помечены нарушением — страж запрещает лечение"; fi
rm -f "$FIX"

# --- T8: труба на строке-продолжении видна сканеру, а построчному grep — нет ---
# Носители scripts/count-stats.sh:59-60 и hooks/tests/test_guards_provable.sh:82-83 (13 сентября
# 2026) держали `| grep -q` второй строкой после `\`; производитель стоял строкой выше, и
# построчный поиск признака их не видел — второй лежал внутри прежней области сканера.
FIX=$(mktemp)
printf '#!/usr/bin/env bash\nset -uo pipefail\ngrep -n x "$f" | grep -v y \\\n    | grep -qE z && echo hit\n' > "$FIX"
if join_continuations "$FIX" | grep -Eq "$SIGPIPE_RE"; then ok; else bad "T8" "труба на строке-продолжении не увидена после склейки"; fi
if grep -Eq "$SIGPIPE_RE" "$FIX"; then bad "T8" "построчный grep увидел продолжение сам — контроль не различает"; else ok; fi
rm -f "$FIX"

# --- T4: механизм воспроизводится, а не взят из рассуждения ---
# Без этого случая страж защищает правило, истинность которого нигде не проверена.
HAY=$(head -c 4000 /dev/zero | tr '\0' 'x'; printf '\nИГЛА\n')
# 141 воспроизводится гонкой и потому утверждать его — значит завести здесь тот же
# непостоянный тест, ради которого всё и затевалось. Утверждается лечение: herestring
# не даёт ложного «не найдено» НИ РАЗУ при заведомо присутствующей игле.
HS_FALSE=0
for _ in $(seq 1 50); do
    grep -Fq "ИГЛА" <<< "$HAY" || HS_FALSE=$((HS_FALSE + 1))
done
[ "$HS_FALSE" -eq 0 ] && ok || bad "T4" "herestring дал $HS_FALSE ложных «не найдено» — лечение не лечит"

echo "test_assert_no_sigpipe: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
