#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_session_collector.sh hooks/tests/test_adv6_archive_second_proverka_ignored.sh hooks/tests/test_adv6_multiline_check_glue.sh hooks/tests/test_backlog_closure_contract.sh hooks/tests/test_mode_arg_guard.sh hooks/tests/test_docs_refresh_claims.sh hooks/tests/test_class_registry_owed.sh hooks/tests/test_disagreement_loop.sh hooks/tests/test_disagreement_snippet.sh hooks/tests/test_adversary_openfind_broken_kills_collector.sh hooks/tests/test_adversary_openfind_poison_line.sh scripts/doc-figures.sh
# (в предмете и сверщик чисел: его чтение двери правил D1179, нога drift_check_pairs = 1 положительная — без него
#  выхолащивание тестов делало свойство «не красны» только вернее, D1222)
# probe_D1179 — тесты, зовущие архиватор, сборщик или сверщик чисел, задают рамку сами (D334):
#   1) внутри «Проверки» — дверь `BACKLOG_CHECKS_NESTED=1` вместе с ключом кольца этого бэклога (вид записи — как у
#      архиватора, `scripts/backlog-archive.sh:501-503`; команда в ключе — имя пробы, не текст «Проверки») — каждый из
#      шести даёт 0, как и без неё; дверь «0» сверщик чисел не читает как «внутри» — ни ключ `tests_*`, ни
#      `drift_check_pairs` (`= "1"`, как у архиватора и гейта; их чтение D1179 не меняет и здесь не судится);
#   2) шесть тестов, зовущих сборщик, в копии дерева с унаследованным корнем зелёные и не уносят ☑ из её BACKLOG.md (M1).
#      Предел рамки: носителя, который снимает `CLAUDSOUL_ROOT` при настоящем HOME, копия не видит — он дошёл бы до
#      живого дерева по указателю (на 29 октября 2026 таких нет: перепись второго скептика, 797 файлов).
# До D1179 все пять первых под дверью — 1; до второго круга — 1 у `test_docs_refresh_claims.sh` под дверью и у шести
# во второй части. Красная (1), пока хоть один красный; 2 — файла нет либо копия дерева не собралась.
# Части идут параллельно: срок «Проверки» у архиватора — 120 с, а под нагрузкой последовательный прогон доходил до 127.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/backlog-lib.sh" ] || exit 2
. "$R/hooks/backlog-lib.sh"
KEY=$(backlog_cmd_env "$R/BACKLOG.md" check D1179 probe_D1179)
# Путь физический: на macOS `/var` — ссылка, и `cpio` не пишет сквозь неё, отвечая при этом 0 — гейт ниже ловит пустую копию.
W=$(mktemp -d) && W=$(cd "$W" && pwd -P) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tree" || exit 2
DOOR=(test_session_collector test_adv6_archive_second_proverka_ignored test_adv6_multiline_check_glue test_backlog_closure_contract test_mode_arg_guard test_docs_refresh_claims)
for t in "${DOOR[@]}"; do [ -f "$R/hooks/tests/$t.sh" ] || exit 2; done
(   b=0
    for t in "${DOOR[@]}"; do
        BACKLOG_CHECKS_NESTED=1 BACKLOG_CMD_RUNNING="$KEY" bash "$R/hooks/tests/$t.sh" >/dev/null 2>&1 || { echo "$t красный под дверью вложенности"; b=1; }
    done
    [ "$(BACKLOG_CHECKS_NESTED=0 bash "$R/scripts/doc-figures.sh" tests_test_disagreement_snippet 2>/dev/null)" != n/a ] \
        || { echo "scripts/doc-figures.sh читает дверь «0» как «внутри»"; b=1; }
    # Второй читатель двери у сверщика — ключ `drift_check_pairs`; drift-check в песочнице — заглушка на одну пару.
    mkdir -p "$W/fig/hooks/tests" && printf '#!/usr/bin/env bash\necho "OK|x"\n' > "$W/fig/hooks/tests/drift-check.sh"
    [ "$(BACKLOG_CHECKS_NESTED=0 CLAUDSOUL_REPO="$W/fig" bash "$R/scripts/doc-figures.sh" drift_check_pairs 2>/dev/null)" = 1 ] \
        || { echo "scripts/doc-figures.sh drift_check_pairs читает дверь «0» как «внутри»"; b=1; }
    exit "$b" ) > "$W/door.out" 2>&1 &
door_pid=$!
# Копия — отслеживаемые файлы в нынешнем состоянии дерева; её BACKLOG.md — один ☑-маркер, архив пуст.
T="$W/tree"
# Код `cpio` не судится: отслеживаемый файл, которого сейчас нет на диске, даёт 1 при годной копии — судит файл-свидетель.
(cd "$R" && git ls-files -z | cpio -0pdm "$T" 2>/dev/null)
[ -f "$T/hooks/session-collector.sh" ] || { echo "копия дерева не собралась"; wait "$door_pid"; exit 2; }
bad=0
for t in test_session_collector test_class_registry_owed test_disagreement_loop test_disagreement_snippet test_adversary_openfind_broken_kills_collector test_adversary_openfind_poison_line; do
    [ -f "$T/hooks/tests/$t.sh" ] || { echo "в копии нет $t.sh"; wait "$door_pid"; exit 2; }
    printf '%s\n' '# BACKLOG' '' '- ☑ **D9001** Маркер.' '  **Результат.** y.' '  **Проверка.** `true` → 0' > "$T/BACKLOG.md"
    printf '%s\n' '# Архив' '' > "$T/BACKLOG-archive.md"
    # Ключ кольца вызывающего остаётся (D503): бэклог копии — другой файл, ограду он не задевает.
    (cd "$T/hooks/tests" && env -u BACKLOG_CHECKS_NESTED -u CLAUDSOUL_BACKLOG \
        CLAUDSOUL_ROOT="$T" CLAUDSOUL_REPO="$T" bash "$T/hooks/tests/$t.sh" >/dev/null 2>&1 </dev/null) \
        || { echo "$t красный в копии дерева"; bad=1; }
    grep -q 'D9001' "$T/BACKLOG.md" || { echo "$t унёс ☑ из BACKLOG.md унаследованного корня"; bad=1; }
done
wait "$door_pid" || bad=1
cat "$W/door.out"
exit "$bad"
