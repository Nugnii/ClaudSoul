#!/usr/bin/env bash
# СУДИТ: scripts/witness-subject-propose.sh
# test_witness_subject_propose.sh — свидетель объявлятеля предмета (D474).
# Предмет: объявлятель находит предмет ПРОГОНОМ, а не догадкой, отличает несобравшуюся
# рамку от слепого свидетеля и умеет отвечать «да» (положительный контроль).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# ПЕСОЧНИЦА ОЧИЩАЕТ ЧУЖОЙ КОРЕНЬ (23 сентября 2026, находка замера instrument-result-measured).
# Тест строит СВОЁ дерево и зовёт в нём объявлятель, а тот зовёт прибор. Если в окружении
# осталась переменная корня от зовущего (а приборы её ставят — так делает и сам
# instrument-result-measured), вложенный прибор уходит судить ЧУЖОЕ дерево, возвращает пустой
# перечень, и объявлятель честно отвечает «объявлять нечего». Контраст прямой: с переменной
# 9 ног красных, без неё 9 из 9 зелёных.
unset CLAUDSOUL_REPO CLAUDSOUL_ROOT

TOOL="$REPO/scripts/witness-subject-propose.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

command -v git >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
[ -f "$TOOL" ] || { echo "FAIL: нет $TOOL"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
D="$TMP/repo"
mkdir -p "$D/scripts" "$D/hooks/tests" "$D/.claude-docs"
cp "$TOOL" "$D/scripts/"
cp "$REPO/scripts/behavior-condition-probe.sh" "$D/scripts/"
# СОСЕДИ СВЕРЕНЫ С ТЕМ, ЧТО БИБЛИОТЕКА ЗОВЁТ (23 сентября 2026, находка замера suite-linux).
# Здесь копировались не все: `timeout-lib.sh` забыли, а библиотека выхолащивания без него
# отвечает «BROKEN: свидетелю не поставить срока». На машине автора это маскировал фоллбек на
# установленную копию в ~/.claude; в чистом контейнере копии нет, и тест падал целиком.
for _lib in subject-probe-lib.sh frame-control-lib.sh state-lock-lib.sh timeout-lib.sh; do
    cp "$REPO/hooks/$_lib" "$D/hooks/$_lib" || { echo "SKIP: нет hooks/$_lib"; exit 0; }
done
[ -f "$REPO/hooks/portable-lib.sh" ] && cp "$REPO/hooks/portable-lib.sh" "$D/hooks/"

printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$D/hooks/one.sh"
printf '#!/usr/bin/env bash\necho SECOND\nexit 0\n' > "$D/hooks/two.sh"

# честный: краснеет от потери ОДНОГО звена
{
    printf '#!/usr/bin/env bash\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'case "$(bash "$R/hooks/one.sh" 2>&1)" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_one.sh"
# честный: краснеет от потери ЛЮБОГО из двух — предмет список
{
    printf '#!/usr/bin/env bash\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'case "$(bash "$R/hooks/one.sh" 2>&1)" in *MARKER*) : ;; *) exit 1 ;; esac\n'
    printf 'case "$(bash "$R/hooks/two.sh" 2>&1)" in *SECOND*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_both.sh"
# слепой: зовёт звено, но вердикт от него не зависит
{
    printf '#!/usr/bin/env bash\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'bash "$R/hooks/one.sh" >/dev/null 2>&1\nexit 0\n'
} > "$D/hooks/tests/test_adv_blind.sh"
# красный и так: рамка не собирается независимо от предмета
printf '#!/usr/bin/env bash\nexit 3\n' > "$D/hooks/tests/test_adv_broken.sh"

# У КАЖДОГО СВИДЕТЕЛЯ ПО ДВА КАНДИДАТА — иначе прибор зовёт предмет ОДНОЗНАЧНЫМ, и такой
# свидетель в перечень `--unresolved` не попадает вовсе: объявлятель его не увидит, а нога
# будет судить пустоту. Краснеет при этом по-прежнему одно звено — в том и приём.
{
    printf 'hooks/one.sh\t\t\t\ttest_adv_one.sh,test_adv_both.sh,test_adv_blind.sh,test_adv_broken.sh\n'
    printf 'hooks/two.sh\t\t\t\ttest_adv_one.sh,test_adv_both.sh,test_adv_blind.sh,test_adv_broken.sh\n'
} | sed 's|test_adv|hooks/tests/test_adv|g' > "$D/.claude-docs/dep-index.tsv"

( cd "$D" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) \
    || { echo "SKIP: git не отработал"; exit 0; }

# ЗАПАСНОЙ ИСТОЧНИК КАНДИДАТОВ (22 сентября 2026): свидетель, которого индекс не знает
# вовсе, но который сам называет свой механизм в тексте. Замер: таких 9 из 15 в остатке.
printf '#!/usr/bin/env bash\necho THIRD\nexit 0\n' > "$D/hooks/three.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf '# зовёт hooks/three.sh, и в индексе этой связи нет\n'
    printf 'case "$(bash "$R/hooks/three.sh" 2>&1)" in *THIRD*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_offindex.sh"

OUT=$(cd "$D" && bash scripts/witness-subject-propose.sh 2>&1); RC=$?

# T1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: рамка обязана уметь отвечать «да». Без него зелёный прогон
# означал бы лишь, что объявлятель ничего не нашёл, — и молчание было бы неотличимо от работы.
grep -q '^# СУДИТ: hooks/one.sh	hooks/tests/test_adv_one.sh$' <<< "$OUT" \
    && ok || bad T1 "предмет честного свидетеля не предложен: $OUT"
# T2 — ПРЕДМЕТ-СПИСОК: краснеют оба звена, названы оба.
grep -q '^# СУДИТ: hooks/one.sh hooks/two.sh	hooks/tests/test_adv_both.sh$' <<< "$OUT" \
    && ok || bad T2 "два краснящих звена не собрались в список: $OUT"
# T3 — СЛЕПОЙ не получает объявления: от потери звена он не краснеет.
grep -q 'ни один кандидат не краснит: hooks/tests/test_adv_blind.sh' <<< "$OUT" \
    && ok || bad T3 "слепой свидетель не назван: $OUT"
grep -q '^# СУДИТ: .*test_adv_blind' <<< "$OUT" && bad T3b "слепому предложен предмет" || ok
# T4 — КРАСНЫЙ И ТАК отделён от слепого: другой класс, другое имя.
grep -q 'рамка не собралась: hooks/tests/test_adv_broken.sh' <<< "$OUT" \
    && ok || bad T4 "красный-и-так не отнесён к несобравшейся рамке: $OUT"
# T4b — ЗАПАСНОЙ ИСТОЧНИК: предмет найден по тексту теста, хотя индекс о нём не знает.
grep -q '^# СУДИТ: hooks/three.sh	hooks/tests/test_adv_offindex.sh$' <<< "$OUT" \
    && ok || bad T4b "предмет не найден по тексту теста, когда индекс пуст: $OUT"

# T5 — код возврата: работа сделана.
[ "$RC" = 0 ] && ok || bad T5 "объявлятель дал код $RC, ожидался 0"

# T6 — --apply ВПИСЫВАЕТ строку под shebang, и прибор её потом читает.
(cd "$D" && bash scripts/witness-subject-propose.sh --apply >/dev/null 2>&1)
L2=$(sed -n '2p' "$D/hooks/tests/test_adv_one.sh")
grep -q '^# СУДИТ: hooks/one.sh$' <<< "$L2" \
    && ok || bad T6 "строка не встала второй: $(sed -n '1,3p' "$D/hooks/tests/test_adv_one.sh")"
# T7 — повторный --apply НЕ ДУБЛИРУЕТ: объявление уже есть, второе было бы мусором.
(cd "$D" && bash scripts/witness-subject-propose.sh --apply >/dev/null 2>&1)
N=$(grep -c '^# СУДИТ:' "$D/hooks/tests/test_adv_one.sh")
[ "$N" = 1 ] && ok || bad T7 "объявлений после двух прогонов: $N"

echo "test_witness_subject_propose: passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ] || exit 1
exit 0
