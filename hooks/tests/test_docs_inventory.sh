#!/usr/bin/env bash
# test_docs_inventory.sh — «Проверка результата» docs-inventory.sh меряет объявленный им результат.
#
# Результат: команда из шапки scripts/docs-inventory.sh красна на дереве, где механизм не описан,
#            где описание называет файл, которого нет, где ссылка, имя рычага или адрес строки
#            ведут в никуда, — и каждую находку называет по имени; на согласованном дереве она
#            зелена и печатает ненулевой знаменатель каждой из пяти сторон.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). У инструмента было два кандидата в свидетели и ни одного
# свидетеля: `test_docs_match_tree.sh` исполняет инструмент, но судит по коду 0 — заглушка
# `exit 0` неотличима от прогона; `test_green_verdict_names_denominator.sh` читает исходник и
# инструмент не исполняет. Оба выводят роль из формы (`pattern-marker-matches-form-not-role`).
# Здесь роль устанавливается исполнением на подложенном дереве: фикстура — git-репозиторий с
# одним механизмом, одним документом состояния и одним README; каждая нога портит одну сторону
# и требует, чтобы инструмент назвал именно её. Команда БЕРЁТСЯ из шапки инструмента, как в
# test_split_provenance_log.sh: подменить её на то, что инструмент не запускает, значит
# покраснить этот тест громко.
#
# Названный предел: фикстура крошечная, и знаменатели в ней единицы — тест ловит «сторона
# молчит», а не «сторона считает мимо на большом дереве». Прогон по живому дереву остаётся за
# test_docs_match_tree.sh. Условие снятия: появится дерево-фикстура с известным числом
# механизмов, упоминаний, ссылок, имён и адресов больше единицы — тогда каждая сторона
# сверяется счётом, а не фактом ненулевого знаменателя.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/docs-inventory.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *docs-inventory.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
F="$TMP/f"

# Чистое дерево: механизм foo-mech описан в документе состояния, ссылка на него ведёт к файлу,
# рычаг FOO_MECH_KNOB есть в коде, адрес hooks/foo-mech.sh:2 указывает на непустую строку.
mk_fixture() {
    rm -rf "$F"; mkdir -p "$F/hooks" "$F/docs" "$F/scripts/ablation"
    printf '#!/usr/bin/env bash\nFOO_MECH_KNOB="${FOO_MECH_KNOB:-1}"\nexit 0\n' > "$F/hooks/foo-mech.sh"
    # Второй механизм — в ПОДПАПКЕ scripts/: предмет проверки задан правилом о файле, а не
    # перечнем мест; фикстура из одного hooks/ зеленила мутант `for f in hooks/*.sh`
    # (прожарка 13 сентября 2026, атака 4).
    printf '#!/usr/bin/env bash\nexit 0\n' > "$F/scripts/ablation/deep-mech.sh"
    printf '# Архитектура\n\nМеханизм `foo-mech` описан здесь: [исходник](../hooks/foo-mech.sh), рычаг в hooks/foo-mech.sh:2. Замер `deep-mech` живёт в подпапке.\n' > "$F/docs/architecture.md"
    printf '# README\n\nРычаг `FOO_MECH_KNOB` включает foo-mech.\n' > "$F/README.md"
    ( cd "$F" && git init -q && git add -A ) || { echo "FAIL: фикстура не собралась"; exit 1; }
}
track() { ( cd "$F" && git add -A ); }
# Объявленная проверка из шапки — на фикстуре: инструмент берёт корень из CLAUDSOUL_REPO.
run_tool() {
    OUT=$(cd "$REPO" && CLAUDSOUL_REPO="$F" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: согласованное дерево — зелено, и каждая из пяти сторон называет знаменатель ----------
mk_fixture; run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "чистое дерево: rc=$RC — $OUT"
has T1 'ДОКУМЕНТАЦИЯ ПРОТИВ ДЕРЕВА'
has T1 'все механизмы дерева упомянуты (проверено механизмов: 2)'
has T1 'мёртвых упоминаний нет (проверено упоминаний: 1)'
has T1 'мёртвых ссылок нет (проверено ссылок: 1)'
has T1 'мёртвых имён рычагов нет (проверено имён: 1)'
has T1 'уплывших адресов нет (проверено адресов: 1)'

# --- T2: механизм есть, описания нет — красно, механизм назван --------------------------------
mk_fixture; printf '#!/usr/bin/env bash\nexit 0\n' > "$F/hooks/bar-mech.sh"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T2 "неописанный механизм: rc=$RC"
has T2 'механизм есть, описания нет (1):'
has T2 '· bar-mech.sh'

# --- T2b: неописанный механизм в подпапке scripts/ — назван, как и верхнеуровневый ----------------
mk_fixture; printf '#!/usr/bin/env bash\nexit 0\n' > "$F/scripts/ablation/x.sh"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T2b "неописанный механизм в подпапке: rc=$RC"
has T2b '· x.sh'

# --- T3a: хроника носителем описания не считается — упоминание в CHANGELOG не спасает ----------
mk_fixture; printf '#!/usr/bin/env bash\nexit 0\n' > "$F/hooks/bar-mech.sh"
printf '# Changelog\n\n- заведён bar-mech\n' > "$F/CHANGELOG.md"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T3a "хроника как носитель: rc=$RC"
has T3a '· bar-mech.sh'

# --- T3b: реестр замеров — носитель описания для инструмента-замера --------------------------
mk_fixture; printf '#!/usr/bin/env bash\nexit 0\n' > "$F/hooks/bar-mech.sh"
mkdir -p "$F/scripts"; printf 'bar-mech\t7\thooks/bar-mech.sh\tназначение\n' > "$F/scripts/measurements.tsv"; track; run_tool
[ "$RC" -eq 0 ] && ok || bad T3b "реестр как носитель: rc=$RC — $OUT"
has T3b 'описано в реестре замеров: 1'

# --- T4: описание есть, файла нет — мёртвый участок назван -----------------------------------
mk_fixture; printf 'Смотри gone-tool.sh.\n' >> "$F/README.md"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T4 "мёртвое упоминание: rc=$RC"
has T4 'МЁРТВЫЙ УЧАСТОК — описание есть, файла нет (1):'
has T4 '· gone-tool.sh'

# --- T5: markdown-ссылка в никуда ----------------------------------------------------------
mk_fixture; printf '\nСм. [план](nope.md).\n' >> "$F/docs/architecture.md"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T5 "мёртвая ссылка: rc=$RC"
has T5 'МЁРТВАЯ ССЫЛКА — ведёт в никуда (1):'
has T5 '· nope.md'

# --- T6: имя рычага, которого нет в коде; контрпример — рычаг будущего не судится -------------
mk_fixture; printf 'Рычаг `GONE_KNOB_NAME` тоже.\n' >> "$F/README.md"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T6 "мёртвое имя рычага: rc=$RC"
has T6 'МЁРТВОЕ ИМЯ РЫЧАГА — в документе есть, в коде нет (1):'
has T6 '· GONE_KNOB_NAME'
mk_fixture; printf 'В будущем появится `FUTURE_KNOB_NAME`.\n' >> "$F/README.md"; track; run_tool
[ "$RC" -eq 0 ] && ok || bad T6b "рычаг будущего засчитан мёртвым: rc=$RC — $OUT"

# --- T7: адрес строки за концом файла -------------------------------------------------------
mk_fixture; printf '\nПодробнее: hooks/foo-mech.sh:99.\n' >> "$F/docs/architecture.md"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T7 "уплывший адрес: rc=$RC"
has T7 'УПЛЫВШИЙ АДРЕС — документ указывает мимо (1):'
has T7 'foo-mech.sh:99 (за концом, строк 3)'

# --- T8: НЕПОЛНОЕ ДЕРЕВО — предмета нет, а не «находок нет» ----------------------------------
# В публичном снимке exclude режет документы и дерево независимо, и находки становятся
# следствием изъятия: док про изъятый механизм, механизм без изъятого дока, ссылка на
# неопубликованный файл. Сверка отвечает «неприменима» и кодом 0 — но ОБЯЗАНА сказать это
# вслух: молчаливый ноль неотличим от «сверили и чисто».
# Мутант первым: та же фикстура БЕЗ маркера обязана краснеть, иначе нога ничего не доказывает.
mk_fixture; printf 'Подробнее: hooks/foo-mech.sh:99.\n' >> "$F/docs/architecture.md"; track; run_tool
[ "$RC" -eq 1 ] && ok || bad T8m "без маркера находка не держит код: rc=$RC"
printf 'снимок\n' > "$F/.public-snapshot"; run_tool
[ "$RC" -eq 0 ] && ok || bad T8 "в неполном дереве сверка держит код: rc=$RC — $OUT"
has T8 'неполное дерево (.public-snapshot): сверка документации с деревом неприменима'

echo ""
echo "docs-inventory tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
