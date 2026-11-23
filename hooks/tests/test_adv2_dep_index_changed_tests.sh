#!/usr/bin/env bash
# test_adv2_dep_index_changed_tests.sh — предписание хука («--changed <файлы>») оставляет
# индекс несогласованным, когда среди файлов есть ТЕСТ, и рапортует об успехе.
#
# Механика. Полная пересборка внутри `--changed` включается двумя признаками:
#     if any(p not in rows for p in paths if p in mech_set) or any(p.endswith(".md") ...)
# то есть «новый механизм» и «любой документ». Тест — ни то, ни другое: он .sh/.py, но
# отсеян MECH_SKIP как `tests/`, значит `p in mech_set` ложно и первый признак его не
# видит. При этом текст теста ВХОДИТ в корпус `tests()` и меняет колонку tests у каждого
# механизма, которого называет. Строки соседей остаются старыми.
#
# Ровно тот класс, что уже был закрыт для документов и новых механизмов
# (test_adv_dep_index_changed_partial.sh, A6a) — для тестов не закрыт.
#
# Почему это дорого, а не косметика: `dep-index --check` стоит в scripts/measurements.tsv
# с периодом 7 дней. Красным его увидит другой ход через неделю, без контекста правки, —
# и «пересобрать: --all» будет единственной подсказкой на 154 строки.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

seed() {  # seed <dir>
    mkdir -p "$1/hooks/tests" "$1/docs" "$1/.claude-docs" "$1/scripts"
    cp "$INDEXER" "$1/scripts/dep-index.py"
    git -C "$1" init -q; git -C "$1" config user.email t@t.local; git -C "$1" config user.name t
    printf '#!/usr/bin/env bash\nfoo_one() { :; }\n' > "$1/hooks/alpha.sh"
    printf '#!/usr/bin/env bash\nbar_one() { :; }\n' > "$1/hooks/beta.sh"
    printf '# Док\n\nМеханизм alpha описан.\n' > "$1/docs/manual.md"
    git -C "$1" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dep_index_changed_tests.sh:$LINENO" >&2; exit 1; }
    git -C "$1" commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dep_index_changed_tests.sh:$LINENO" >&2; exit 1; }
    ( cd "$1" && CLAUDSOUL_REPO="$1" python3 scripts/dep-index.py --all >/dev/null )
    # КОНТРОЛЬ РАБОТЫ (D342, 20 сентября 2026): собранный индекс обязан быть непуст.
    #
    # Замер того дня: свидетель зелен И на живом индексаторе, И на выхолощенном до `pass`.
    # Устройство здесь СВОЁ, не то, что у соседей по очереди: оба вердикта (C1 и C2) —
    # это код `dep-index.py --check`, то есть ВЕРДИКТ ВЫНОСИТ САМ ПОДСУДИМЫЙ. Выхолощенный
    # предмет отвечает нулём на любой вопрос, включая вопрос о собственной согласованности.
    # Ни «отсутствие» (как у свидетелей абсолютного пути), ни SKIP тут ни при чём.
    #
    # Контроль поэтому обязан быть НЕЗАВИСИМ от предмета: файл индекса читается напрямую.
    # Он стоит В СТРОИТЕЛЕ, а не в ветвях вердиктов, — вчерашняя правка ставила его туда и
    # была откачена: у этого свидетеля индекс собирается дважды, по разным спискам, и в
    # ветви контроль судил бы полупостроенный мир.
    # ОТКАЗ ЧТЕНИЯ СЧИТАЕТСЯ И НАЗЫВАЕТСЯ (24 сентября 2026, род B). Прежняя редакция брала
    # число как `$(grep -cv ... || true)`: на ВЫПОТРОШЕННОМ индексаторе файла индекса нет
    # вовсе, `grep` печатает пусто и выходит кодом 2, `|| true` подменяет код, но не вывод,
    # и `[ "" -eq 0 ]` завершается ОШИБКОЙ, а не истиной — ветвь контроля не берётся. Свидетель
    # проходил обе проверки на мёртвом предмете и числился единственным ложно-зелёным дерева.
    _idx_n=$(grep -cv '^#' "$1/.claude-docs/dep-index.tsv" 2>/dev/null) || _idx_n=""
    case "$_idx_n" in ''|*[!0-9]*) _idx_n=0 ;; esac
    if [ "$_idx_n" -eq 0 ]; then
        echo "FAIL [рамка не собралась]: индекс в песочнице пуст — индексатор не отработал," >&2
        echo "     и его же вердикт --check о согласованности ничего не стоит." >&2
        exit 1
    fi
}

TMP=$(mktemp -d)

# --- C1: коммит только с тестом ------------------------------------------------------
A="$TMP/a"; seed "$A"
printf '#!/usr/bin/env bash\n# проверяет alpha\ntrue\n' > "$A/hooks/tests/test_alpha.sh"
git -C "$A" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dep_index_changed_tests.sh:$LINENO" >&2; exit 1; }
SAY1=$( cd "$A" && CLAUDSOUL_REPO="$A" python3 scripts/dep-index.py --changed hooks/tests/test_alpha.sh 2>&1 )
CHK1=$( cd "$A" && CLAUDSOUL_REPO="$A" python3 scripts/dep-index.py --check 2>&1 ); RC1=$?
if [ "$RC1" -eq 0 ]; then
    ok "C1 после предписанной пересборки по тесту --check зелёный"
else
    bad "C1" "исполнено дословно: --changed hooks/tests/test_alpha.sh → «${SAY1}»,
      сразу за ним --check (rc=$RC1):
$(printf '%s\n' "$CHK1" | sed 's/^/      /')"
fi

# --- C2: коммит «механизм + его тест», тест называет и соседа ------------------------
B="$TMP/b"; seed "$B"
printf '#!/usr/bin/env bash\nfoo_one() { echo ИНОЕ; }\n' > "$B/hooks/alpha.sh"
printf '#!/usr/bin/env bash\n# проверяет alpha, заодно трогает beta\ntrue\n' > "$B/hooks/tests/test_alpha.sh"
git -C "$B" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dep_index_changed_tests.sh:$LINENO" >&2; exit 1; }
SAY2=$( cd "$B" && CLAUDSOUL_REPO="$B" python3 scripts/dep-index.py --changed hooks/alpha.sh hooks/tests/test_alpha.sh 2>&1 )
CHK2=$( cd "$B" && CLAUDSOUL_REPO="$B" python3 scripts/dep-index.py --check 2>&1 ); RC2=$?
if [ "$RC2" -eq 0 ]; then
    ok "C2 пересборка по всему списку staged оставила индекс согласованным"
else
    bad "C2" "исполнено дословно: --changed hooks/alpha.sh hooks/tests/test_alpha.sh → «${SAY2}»,
      сразу за ним --check (rc=$RC2):
$(printf '%s\n' "$CHK2" | sed 's/^/      /')
      строка соседа не перестроена, хотя новый тест называет его:
      $(grep '^hooks/beta\.sh	' "$B/.claude-docs/dep-index.tsv" | tr '\t' '|')"
fi

echo ""
echo "adv2 changed-tests: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
