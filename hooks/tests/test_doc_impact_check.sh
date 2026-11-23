#!/usr/bin/env bash
# СУДИТ: hooks/doc-impact-check.sh scripts/dep-index.py
# test_doc_impact_check.sh — doc-impact-check.sh: изменил механизм → назови его документы.
#
# Закрепляется (обе стороны, guards-provable):
#   - изменён механизм, его документ НЕ в staged → назван поимённо;
#   - документ в том же staged → про него молчит;
#   - новый механизм без строки в учёте → сказано отдельно;
#   - новое публичное имя в существующем модуле → сказано отдельно;
#   - нет индекса (чужой проект без документации) → полная тишина;
#   - не git-commit → тишина;
#   - троттл: тот же набор второй раз за сессию → тишина.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/doc-impact-check.sh"
INDEXER="$REPO/scripts/dep-index.py"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
assert_contains() { if grep -qF "$2" <<< "$1"; then ok; else bad "$3" "нет «$2» в: $1"; fi; }
assert_lacks()    { if grep -qF "$2" <<< "$1"; then bad "$3" "нашлось лишнее «$2»: $1"; else ok; fi; }
assert_silent()   { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина: $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/hooks" "$R/docs" "$R/.claude-docs" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q
git -C "$R" config user.email t@t.local; git -C "$R" config user.name t

printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\n' > "$R/hooks/alpha.sh"
printf '#!/usr/bin/env bash\npaths_helper() { :; }\n' > "$R/hooks/paths-lib.sh"
printf '# Справочник\n\nМеханизм `alpha` делает то-то.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm init || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

run() { # run <sid> [команда]
    jq -cn --arg c "${2:-git commit -m x}" --arg d "$R" --arg s "$1" \
        '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d, session_id:$s}' \
    | STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$R" bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
# tree_check <ревизия|:index> — учёт совпадает с деревом коммита либо индекса: выгрузка в git-песочницу и своя сверка
# (D1083: вопрос хука — о дереве коммита, а не о рабочей копии).
tree_check() { local C; C=$(mktemp -d "$TMP/tc.XXXX")
    if [ "$1" = :index ]; then git -C "$R" checkout-index -a --prefix="$C/"; else git -C "$R" archive "$1" | tar -x -C "$C"; fi
    git -C "$C" init -q && git -C "$C" add -A >/dev/null 2>&1 \
      && ( cd "$C" && CLAUDSOUL_REPO="$C" python3 scripts/dep-index.py --check >/dev/null 2>&1 ); }

# --- T1: механизм изменён, его документ не тронут → документ назван -----------------
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\n# правка\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s1)
assert_contains "$OUT" "docs/manual.md" "T1 документ назван"

# --- T2: документ в том же staged → про него молчит --------------------------------
printf '# Справочник\n\nМеханизм `alpha` делает то-то, поправлено.\n' > "$R/docs/manual.md"
git -C "$R" add docs/manual.md >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s2)
assert_lacks "$OUT" "docs/manual.md" "T2 тронутый документ не поминается"

# --- T3: новое публичное имя в существующем модуле → сказано отдельно ---------------
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_two() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add -A >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s3)
assert_contains "$OUT" "foo_two" "T3 новое публичное имя"

# --- T4: новый механизм без строки в учёте → сказано отдельно ----------------------
printf '#!/usr/bin/env bash\nbar() { :; }\n' > "$R/hooks/beta.sh"
git -C "$R" add hooks/beta.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s4)
assert_contains "$OUT" "hooks/beta.sh" "T4 новый механизм"
assert_contains "$OUT" "без строки в учёте" "T4b формулировка учёта"

# --- T5: зависимый назван именем, а не своим документом ---------------------------
printf '#!/usr/bin/env bash\npaths_helper() { :; }\n# правка\n' > "$R/hooks/paths-lib.sh"
git -C "$R" reset -q || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
# Зависимый, правленый в рабочей копии, сам «в коммите» и из зависимых выпадает: без возврата alpha.sh нога проходила
# по строке «частично застейджены hooks/alpha.sh», а не по списку зависимых (D1082 это вскрыл).
git -C "$R" checkout -q -- hooks/alpha.sh docs/manual.md
git -C "$R" add hooks/paths-lib.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s5)
assert_contains "$OUT" "hooks/alpha.sh" "T5 зависимый назван"
assert_contains "$OUT" "зависят от изменённого" "T5б назван строкой зависимых, а не другой"

# --- T6: троттл — тот же набор второй раз за сессию → тишина -----------------------
OUT=$(run s5)
assert_silent "$OUT" "T6 троттл"

# --- T7: не commit-команда → тишина ------------------------------------------------
OUT=$(run s7 "git status")
assert_silent "$OUT" "T7 не commit"

# --- T8: нет индекса (чужой проект без документации) → полная тишина ---------------
mv "$R/.claude-docs/dep-index.tsv" "$TMP/idx.bak"
OUT=$(run s8)
assert_silent "$OUT" "T8 без индекса молчит"
mv "$TMP/idx.bak" "$R/.claude-docs/dep-index.tsv"

# --- T9: индекс знает своё устаревание --------------------------------------------
printf '#!/usr/bin/env bash\nfoo_one() { :; }\n# ещё правка\n' > "$R/hooks/alpha.sh"
if ( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check >/dev/null 2>&1 ); then
    bad "T9 --check" "индекс устарел, а проверка это не заметила"
else ok; fi

# --- T10/T11: правка внутри объявленной области данных ≠ правка поведения ----------
# Порог «много документов = узловой файл» пробовали и он провалил приёмку: механизм с
# девятью документами замолчал вместе со справочником. Различие берётся из разметки файла.
git -C "$R" reset -q
printf '#!/usr/bin/env bash\n# dep-index: data-region-start\nDATA="один"\n# dep-index: data-region-end\ngamma_fn() { :; }\n' > "$R/hooks/gamma.sh"
printf '# Про gamma\n\nМеханизм `gamma` описан тут.\n' > "$R/docs/gamma-doc.md"
git -C "$R" add -A >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm gamma || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null && git add .claude-docs/dep-index.tsv \
  && git commit -qm idx >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }  # учёт — в коммите: хук судит дерево коммита (D1083)

printf '#!/usr/bin/env bash\n# dep-index: data-region-start\nDATA="один два"\n# dep-index: data-region-end\ngamma_fn() { :; }\n' > "$R/hooks/gamma.sh"
git -C "$R" add hooks/gamma.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s10)
assert_lacks "$OUT" "docs/gamma-doc.md" "T10 данные не поднимают документы"
assert_contains "$OUT" "области данных" "T10b сказано, что это данные"

printf '#!/usr/bin/env bash\n# dep-index: data-region-start\nDATA="один два"\n# dep-index: data-region-end\ngamma_fn() { :; }\n# правка поведения\n' > "$R/hooks/gamma.sh"
git -C "$R" add hooks/gamma.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s11)
assert_contains "$OUT" "docs/gamma-doc.md" "T11 правка вне области данных поднимает документ"

# --- T14/T15: как документ называет механизм — правило о форме ИМЕНИ ---------------
# Составное имя (дефис/подчёркивание) обычным словом быть не может, поэтому засчитывается
# и голым. Односложное — может: замер 28 августа 2026 показал, что голое «inject» ловит
# «silent inject» в PLAN.md, «phase» — поле JSON, «cli» — псевдоним домена. Для таких
# нужна форма, помечающая имя: расширение, путь или обратные кавычки.
git -C "$R" reset -q
printf '#!/usr/bin/env bash\nphase_fn() { :; }\n' > "$R/hooks/phase.sh"
printf '#!/usr/bin/env bash\nlong_fn() { :; }\n' > "$R/hooks/long-name-thing.sh"
printf '# Док\n\nЗдесь слово phase встречается как обычное слово.\nА `long-name-thing` назван голым составным именем.\n' > "$R/docs/naming.md"
git -C "$R" add -A >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm naming || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null && git add .claude-docs/dep-index.tsv \
  && git commit -qm idx >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }  # учёт — в коммите: хук судит дерево коммита (D1083)

printf '#!/usr/bin/env bash\nphase_fn() { :; }\n# правка\n' > "$R/hooks/phase.sh"
git -C "$R" add hooks/phase.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s14)
assert_lacks "$OUT" "docs/naming.md" "T14 голое односложное слово связью не считается"

printf '#!/usr/bin/env bash\nlong_fn() { :; }\n# правка\n' > "$R/hooks/long-name-thing.sh"
git -C "$R" reset -q || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
git -C "$R" add hooks/long-name-thing.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s15)
assert_contains "$OUT" "docs/naming.md" "T15 голое составное имя связью считается"

printf '# Док\n\nА тут `phase` в обратных кавычках — это имя.\n' > "$R/docs/naming2.md"
git -C "$R" add docs/naming2.md >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm n2 >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null && git add .claude-docs/dep-index.tsv \
  && git commit -qm idx >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }  # учёт — в коммите: хук судит дерево коммита (D1083)
printf '#!/usr/bin/env bash\nphase_fn() { :; }\n# ещё правка\n' > "$R/hooks/phase.sh"
git -C "$R" add hooks/phase.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s16)
assert_contains "$OUT" "docs/naming2.md" "T16 имя в обратных кавычках связью считается"

# --- T17-T19: УЧЁТ ПЕРЕСОБИРАЕТСЯ САМ ------------------------------------------------
# Сообщение хука везёт два смысла с разными последствиями. Суждение о документах остаётся
# инжектом — его уровень измерен. Производный факт («новые публичные имена», «строки учёта
# устарели») решения не требует: индекс либо совпадает с деревом, либо нет. Цена прежнего
# устройства измерена 14 сентября 2026: за 30 дней 50 коммитов чинили ТОЛЬКО индекс.
git -C "$R" reset -q
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered17 >/dev/null 2>&1 )
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm idx17 >/dev/null 2>&1 )

# T17 — новое публичное имя, механизм застейджен ЦЕЛИКОМ: учёт пересобран и добавлен сам.
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_sam() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s17)
assert_contains "$OUT" "Учёт пересобран САМ" "T17 пересборка состоялась"
STAGED_IDX=$(git -C "$R" diff --cached --name-only 2>/dev/null)
if grep -qxF ".claude-docs/dep-index.tsv" <<< "$STAGED_IDX"; then ok
else bad "T17б индекс в коммите" "учёт пересобран, но в коммит не добавлен: $STAGED_IDX"; fi

# T18 — механизм застейджен ЧАСТИЧНО. В коммит уходит индекс git, и учёт пересобирается по ВЫГРУЗКЕ индекса (D1083):
# строка описывает застейдженный текст, хвост рабочей копии её не трогает. Прежде пересборка читала рабочее дерево, и
# частичный файл приходилось отказывать с причиной — зазор, найденный противником в этом же хуке.
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered18 >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_chastich() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_chastich() { :; }\n# хвост вне индекса\n' > "$R/hooks/alpha.sh"
OUT=$(run s18)
assert_contains "$OUT" "Учёт пересобран САМ" "T18 частичная постановка — учёт пересобран по индексу коммита"
tree_check :index && ok || bad "T18б" "частичная постановка: учёт в индексе расходится с деревом индекса"
grep -q 'хвост вне индекса' "$R/hooks/alpha.sh" && ok || bad "T18в" "рабочая копия частичного файла тронута"

# T19 — ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ К ОБЛАСТИ: учёт УЖЕ СВЕЖ, и хук не приписывает себе работы,
# которой не делал. Первая редакция ноги проверяла «правку только тела» — и мерила
# недостижимое: строка учёта устаревает от ЛЮБОЙ правки тела, поэтому отчёт без производных
# фактов при изменённом механизме не встречается. Достижимое состояние одно: строка
# пересобрана ДО коммита, и в отчёте остаётся лишь суждение о документах.
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered19 >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_chastich() { :; }\n# правка тела\n' > "$R/hooks/alpha.sh"
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --changed hooks/alpha.sh >/dev/null 2>&1 )
git -C "$R" add -A >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s19)
assert_contains "$OUT" "docs/manual.md" "T19 суждение о документах на месте"
assert_lacks "$OUT" "Учёт пересобран САМ" "T19б свежий учёт заново не пересобирается"
assert_lacks "$OUT" "Пересобрать индекс после правки" "T19в свежий учёт не поручается пересобрать (D1082, А2)"

# --- T20: КОМАНДА САМА ДОБАВЛЯЕТ ФАЙЛЫ — пересборка не отказывает -------------------
# Хук стоит ДО команды, поэтому при `git add -A && git commit` в одной строке файлы на
# момент проверки ещё не в индексе. Первая редакция звала их частично застейдженными и
# отказывала в пересборке — то есть механизм не работал бы у того, кто ставит и коммитит
# одной командой. Поймано на самом себе: коммит 978fb82 получил такой отказ на двух файлах,
# поставленных той же командой. Признак взят оттуда же, откуда его берёт отбор файлов, —
# из ТЕКСТА команды.
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered20 >/dev/null 2>&1 )
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null 2>&1 )
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm idx20 >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_dvadcat() { :; }\n' > "$R/hooks/alpha.sh"
# НИЧЕГО НЕ СТЕЙДЖИМ НАМЕРЕННО: добавит сама команда, как в живой работе.
OUT=$(run s20 "git add -A && git commit -m x")
assert_contains "$OUT" "Учёт пересобран САМ" "T20 команда добавляет сама — пересборка идёт"
assert_lacks "$OUT" "частично застейджены" "T20б отказа по частичности нет"

# T21 — ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ К T20: та же грязь, но команда НИЧЕГО не добавляет. Правленый файл в коммит не войдёт:
# учёт в индексе обязан описывать индекс, а не рабочую копию (D1083).
OUT=$(run s21 "git commit -m x")
tree_check :index && ok || bad "T21" "без добавления: учёт в индексе расходится с деревом индекса"

# --- T22: ПОЯВИЛСЯ ФАЙЛ-ДОГОВОР — учёт пересобран в том же коммите (шаг 1б.3, урок F2 D1067) ---------
# Читатель `hooks/rd22.sh` называет `$REPO/data/reg22.tsv`, которого ещё нет: ребра нет. Затем файл добавлен и
# застейджен ОДИН, без механизмов: прежний фильтр хука `*.sh|*.py` пересборки не давал, учёт оставался устаревшим.
# Модуль описания кладётся в песочницу и коммитится заранее: на CI указателя на живую копию нет, а незакоммиченный
# модуль сам дал бы «новый механизм» — нога прошла бы по чужой причине.
( cd "$R" && git checkout -q -- . 2>/dev/null; git add -A >/dev/null 2>&1 && git commit --allow-empty -qm pered22 >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
mkdir -p "$R/hooks/lib" "$R/data"; cp "$REPO/hooks/lib/project_map.py" "$R/hooks/lib/"
printf '#!/usr/bin/env bash\ncat "$REPO/data/reg22.tsv"\n' > "$R/hooks/rd22.sh"
( cd "$R" && git add -A >/dev/null 2>&1 && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null 2>&1 \
  && git add -A >/dev/null 2>&1 && git commit -qm rd22 >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
printf 'a\tb\n' > "$R/data/reg22.tsv"; git -C "$R" add data/reg22.tsv >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s22)
assert_contains "$OUT" "Учёт пересобран САМ" "T22 договор появился — учёт пересобран"
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check >/dev/null 2>&1 ) && ok \
    || bad "T22б" "после пересборки учёт не совпадает с деревом"
awk -F'\t' '$1 == "hooks/rd22.sh" && $3 ~ /data\/reg22\.tsv/ { f = 1 } END { exit !f }' "$R/.claude-docs/dep-index.tsv" \
    && ok || bad "T22в" "у читателя нет ребра к появившемуся договору"

# --- T23: ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ К T22 — правка СОДЕРЖИМОГО договора рёбер не меняет, пересборки нет ----------
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered23 >/dev/null 2>&1 )
printf 'a\tb\nc\td\n' > "$R/data/reg22.tsv"; git -C "$R" add data/reg22.tsv >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s23)
assert_lacks "$OUT" "Учёт пересобран САМ" "T23 правка содержимого договора — без пересборки"
assert_lacks "$OUT" "строки учёта устарели" "T23б правка содержимого договора учёт не старит"

# --- T24: УЧЁТ СТАРОЙ РЕДАКЦИИ не знает `--stale-by` (код 2) — хук возвращается к отбору по расширению -------------
# Рабочая копия на прежнем коммите и проект со своей копией прибора встретят новый хук именно так; без запасной ветки
# пересборка молча пропадала (нога D2 `test_commit_trap.sh` поймала это на копии HEAD).
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered24 >/dev/null 2>&1 )
printf '%s\n' 'import os, runpy, sys' \
    'if sys.argv[1:2] == ["--stale-by"]: sys.stderr.write("неизвестный аргумент\n"); sys.exit(2)' \
    'runpy.run_path(os.environ["REAL_DG"], run_name="__main__")' > "$TMP/old-dg.py"
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_star() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(jq -cn --arg c "git commit -m x" --arg d "$R" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d, session_id:"s24"}' \
    | STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$R" DEP_INDEX_TOOL="$TMP/old-dg.py" REAL_DG="$R/scripts/dep-index.py" \
      bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
assert_contains "$OUT" "Учёт пересобран САМ" "T24 учёт без --stale-by — пересборка по расширению идёт"

# --- T25: МЕХАНИЗМ + ТЕСТ, тест начал называть третий механизм — учёт сведён с деревом (скептик 72d00022, F1) -------
# `--stale-by` отдавал только механизмы и строки договоров: колонка `tests` третьего механизма оставалась прежней.
( cd "$R" && git add -A >/dev/null 2>&1 && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null 2>&1 \
  && git add -A >/dev/null 2>&1 && git commit -qm pered25 >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
mkdir -p "$R/hooks/tests"
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_star() { :; }\n# правка 25\n' > "$R/hooks/alpha.sh"
printf '#!/usr/bin/env bash\nbash hooks/alpha.sh\nbash hooks/rd22.sh\n' > "$R/hooks/tests/test_t25.sh"
git -C "$R" add hooks/alpha.sh hooks/tests/test_t25.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s25)
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check >/dev/null 2>&1 ) && ok \
    || bad "T25" "механизм + тест: учёт после коммита не совпадает с деревом"
# --- T26: коммит ОДНОГО теста, начавшего называть механизм — учёт тоже сведён (давний пробел того же устройства) ----
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered26 >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\nbash hooks/alpha.sh\nbash hooks/rd22.sh\nbash hooks/paths-lib.sh\n' > "$R/hooks/tests/test_t25.sh"
git -C "$R" add hooks/tests/test_t25.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$(run s26)
assert_contains "$OUT" "Учёт пересобран САМ" "T26 коммит одного теста — учёт пересобран"
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check >/dev/null 2>&1 ) && ok \
    || bad "T26б" "коммит одного теста: учёт не совпадает с деревом"
# --- T27: переименованный документ — до владельца перечня доходят оба пути (D1076, скептик b4c40167, А3) -----------
# С распознаванием переименований git отдаёт только новый путь: прежний остаётся в колонке docs строки, которую больше
# никто не называет. Документ длинный, чтобы git узнал в правке переименование.
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered27 >/dev/null 2>&1 )
P27=$(printf 'Строка общего текста номер %s.\\n' 1 2 3 4 5 6 7 8 9 10 11 12)
printf "# Проба\\n\\n${P27}Механизмы \`alpha\` и \`rd22\`.\\n" > "$R/docs/p27.md"
( cd "$R" && git add -A >/dev/null 2>&1 && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null 2>&1 \
  && git add -A >/dev/null 2>&1 && git commit -qm p27 >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
git -C "$R" mv docs/p27.md docs/q27.md >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
printf "# Проба\\n\\n${P27}Механизм \`alpha\`.\\n" > "$R/docs/q27.md"
git -C "$R" add docs/q27.md >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
grep -q '^R' <<< "$(git -C "$R" diff --cached --name-status)" || bad "T27-рамка" "git не узнал переименования — нога ничего не судит"
OUT=$(run s27)
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check >/dev/null 2>&1 ) && ok \
    || bad "T27" "переименованный документ: учёт после коммита не совпадает с деревом"
# --- T28: правка документа, не сдвинувшая ни одной строки учёта, — поручения пересобрать нет (D1077) ----------------
# Строка «изменено документов … пересобери учёт» звучала на каждый коммит документа, хотя владелец свежести знает
# сдвинутые строки точно: при свежем учёте агент получал поручение, исполнять которое нечего.
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm pered28 >/dev/null 2>&1 )
printf '# Справочник\n\nМеханизм `alpha` делает то-то, поправлено в T28.\n' > "$R/docs/manual.md"
git -C "$R" add docs/manual.md >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check >/dev/null 2>&1 ) \
    || bad "T28-рамка" "учёт расходится с деревом и без правки — нога ничего не судит"
OUT=$(run s28)
assert_lacks "$OUT" "пересобери учёт" "T28 правка документа без сдвига строк не поручает пересборку"

# --- T29–T32 (D1082, скептик sk3): ответ «нужна ли пересборка» — у `--stale-by`, частичность — по входам пересборки ---
# Хук зовётся так, как его зовут ловушки git (D1022): `--pre-commit` пересобирает учёт в индекс коммита, `--commit-msg`
# отчитывается. Прежде пересборку решали фразы отчёта `--impact`, а частичность — строки перечня.
trap_run() { # trap_run pre|msg
    if [ "$1" = msg ]; then printf 'x\n' > "$TMP/msg"; set -- --commit-msg "$TMP/msg"; else set -- --pre-commit; fi
    ( cd "$R" && STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$R" bash "$HOOK" "$@" </dev/null 2>&1 )
}
fresh_base() { ( cd "$R" && git checkout -q -- . 2>/dev/null; git add -A >/dev/null 2>&1 \
    && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
    && git commit --allow-empty -qm "$1" >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }; }
idx_check() { ( cd "${1:-$R}" && CLAUDSOUL_REPO="${1:-$R}" python3 scripts/dep-index.py --check >/dev/null 2>&1 ); }
# T29 (А2): pre-commit пересобрал учёт — commit-msg не поручает пересборку свежего учёта.
fresh_base pered29
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_star() { :; }\n# правка 29\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
PRE=$(trap_run pre)
assert_contains "$PRE" "пересобран и добавлен" "T29-рамка pre-commit пересобрал учёт"
idx_check || bad "T29-рамка" "учёт после pre-commit не свеж — нога ничего не судит"
OUT=$(trap_run msg)
assert_lacks "$OUT" "Пересобрать индекс после правки" "T29 commit-msg при свежем учёте не поручает пересборку"
# T30 (А3): правка внутри объявленной области данных — строка устарела (sha), её называют отчёт и перечень, pre-commit
# её пересобирает. Отчёт выкидывал механизм из «изменённых», фраз-поводов не было, и строка уходила в коммит прежней.
fresh_base pered30
printf '#!/usr/bin/env bash\n# dep-index: data-region-start\nDATA="один два три"\n# dep-index: data-region-end\ngamma_fn() { :; }\n# правка поведения\n' > "$R/hooks/gamma.sh"
git -C "$R" add hooks/gamma.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
I30=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/gamma.sh 2>&1 )
assert_contains "$I30" "области данных" "T30-рамка правка признана данными"
assert_contains "$I30" "строки учёта устарели" "T30б отчёт называет устаревшую строку правки данных"
trap_run pre >/dev/null
idx_check && ok || bad "T30" "правка области данных: учёт после pre-commit расходится с деревом"
# T31 (А4): механизм ВНЕ коммита (правлен в рабочей копии, не застейджен), чью строку сдвигает документ коммита. Учёт
# считается по выгрузке индекса: строка механизма описывает его закоммиченный текст и новый документ (D1083).
fresh_base pered31
printf '# Заметка\n\nМеханизм `alpha` упомянут и тут.\n' > "$R/docs/zz31.md"
printf '# wip\n' >> "$R/hooks/alpha.sh"
git -C "$R" add docs/zz31.md >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
PRE=$(trap_run pre)
assert_lacks "$PRE" "частично застейджены" "T31 механизм вне коммита не назван частично застейдженным"
assert_contains "$PRE" "пересобран и добавлен" "T31б строка, сдвинутая документом коммита, пересобрана"
git -C "$R" commit -qm c31 >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
tree_check HEAD && ok || bad "T31в" "механизм вне коммита: учёт в коммите расходится с деревом коммита"
# T32 (А5): частично застейджен ДОКУМЕНТ — по рабочей копии в коммит ушла бы строка, которой его дерево не даёт.
# Судится результат: учёт в коммите совпадает с деревом коммита.
( cd "$R" && git checkout -q -- . && rm -f docs/zz31.md ); fresh_base pered32
printf '# Заметка\n\nОбщий текст.\n' > "$R/docs/zz32.md"; git -C "$R" add docs/zz32.md >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
printf '# Заметка\n\nОбщий текст. Механизм `alpha` тоже.\n' > "$R/docs/zz32.md"
PRE=$(trap_run pre)
assert_lacks "$PRE" "пересобран и добавлен" "T32 частичный документ строк коммита не сдвигает — пересборки нет"
git -C "$R" commit -qm partial32 >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
tree_check HEAD && ok || bad "T32б" "частичный документ: учёт в коммите расходится с деревом коммита"
# --- T33–T36 (D1083, скептик по b2beb37f): файл ВНЕ коммита ответа о коммите не меняет --------------------------------
# T33 (А1): неотслеживаемый новый механизм, чьё имя есть в коде нетронутого zeta33.sh, не отменяет пересборку alpha.sh.
( cd "$R" && git checkout -q -- . ); fresh_base pered33
printf '#!/usr/bin/env bash\nbash "$(dirname "$0")/beta33.sh"\n' > "$R/hooks/zeta33.sh"; fresh_base zeta33
printf '#!/usr/bin/env bash\nbeta_fn() { :; }\n' > "$R/hooks/beta33.sh"
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t33() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
PRE=$(trap_run pre)
assert_contains "$PRE" "пересобран и добавлен" "T33 неотслеживаемый механизм не отменяет пересборку"
git -C "$R" commit -qm c33 >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
tree_check HEAD && ok || bad "T33б" "неотслеживаемый механизм: учёт в коммите расходится с деревом коммита"
# T34 (А2): при том же неотслеживаемом механизме коммит документа слышит «Пересобрать» только при несвежем учёте.
fresh_base pered34
printf '#!/usr/bin/env bash\nbash "$(dirname "$0")/beta34.sh"\n' > "$R/hooks/zeta34.sh"; fresh_base zeta34
printf '#!/usr/bin/env bash\nbeta_fn() { :; }\n' > "$R/hooks/beta34.sh"
printf '# Справочник\n\nМеханизм `alpha` делает то-то, T34.\n' > "$R/docs/manual.md"; git -C "$R" add docs/manual.md >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
trap_run pre >/dev/null; OUT=$(trap_run msg)
tree_check :index || bad "T34-рамка" "учёт индекса не свеж — нога ничего не судит"
assert_lacks "$OUT" "Пересобрать индекс после правки" "T34 файл вне коммита не поручает пересобрать свежий учёт"
# T35 (А3): неотслеживаемый однофамилец не отменяет пересборку и не включает полную сборку на коммите.
fresh_base pered35
printf '#!/usr/bin/env bash\necho копия\n' > "$R/scripts/alpha.sh"
printf '#!/usr/bin/env bash\npaths_helper() { :; }\npaths_t35() { :; }\n' > "$R/hooks/paths-lib.sh"
git -C "$R" add hooks/paths-lib.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
PRE=$(trap_run pre)
assert_contains "$PRE" "пересобран и добавлен" "T35 однофамилец вне коммита не отменяет пересборку"
git -C "$R" commit -qm c35 >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
tree_check HEAD && ok || bad "T35б" "однофамилец вне коммита: учёт в коммите расходится с деревом коммита"
rm -f "$R/scripts/alpha.sh"
# T36 (А6): учёт пересобран в рабочей копии без `git add` — в коммит идёт учёт, описывающий дерево коммита.
fresh_base pered36
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t36() { :; }\n' > "$R/hooks/alpha.sh"
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --changed hooks/alpha.sh >/dev/null 2>&1 )
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
trap_run pre >/dev/null
git -C "$R" commit -qm c36 >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
tree_check HEAD && ok || bad "T36" "незастейдженный пересобранный учёт: в коммит ушёл прежний"
# --- T37–T41 (D1084, скептик по b64111fa): рабочая копия после коммита, формы «добавить всё», отчёт, служебный diff ---
# T37 (А3): учёт правлен в рабочей копии отдельно от индекса — после коммита там лежит учёт коммита, и следующий коммит
# всего правленого (`add -u`, как `commit -a`) не уносит в HEAD откат строки, пересобранной первым коммитом.
fresh_base pered37
printf '#!/usr/bin/env bash\npaths_helper() { :; }\npaths_t37() { :; }\n' > "$R/hooks/paths-lib.sh"
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --changed hooks/paths-lib.sh >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t37() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
trap_run pre >/dev/null
git -C "$R" commit -qm c37 >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
tree_check HEAD || bad "T37-рамка" "первый коммит уже расходится с деревом — нога ничего не судит"
git -C "$R" add -u >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
trap_run pre >/dev/null
git -C "$R" commit -qm c37b >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
tree_check HEAD && ok || bad "T37" "правленый в рабочей копии учёт: второй коммит унёс в HEAD откат строки"
# T41 (А2): запись учёта, положенная хуком, несёт stat — служебный diff сразу после коммита чист, а не только `git status`.
# Коммит отдельный, где пересборку делает сам хук: после `add -u` запись пришла бы с stat по чужой причине.
fresh_base pered41
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t41() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }; PRE=$(trap_run pre)
assert_contains "$PRE" "пересобран и добавлен" "T41-рамка учёт положил хук"
# Сверка — сразу после хука: в настоящей ловушке git индекс после неё не освежает, а `git commit` здесь освежил бы.
git -C "$R" diff-files --quiet -- .claude-docs/dep-index.tsv && ok \
    || bad "T41" "после хука diff-files называет учёт изменённым: запись в индексе без stat"
git -C "$R" commit -qm c41 >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
# T38: правило учёта — дерева коммита: прибор, правленый в рабочей копии и не застейдженный, строки коммита не строит.
fresh_base pered38
cp "$R/scripts/dep-index.py" "$TMP/dg38.bak"
sed -i.bak 's/hexdigest()\[:12\]/hexdigest()[:10]/' "$R/scripts/dep-index.py"; rm -f "$R/scripts/dep-index.py.bak"
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t38() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
trap_run pre >/dev/null
git -C "$R" commit -qm c38 >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
cp "$TMP/dg38.bak" "$R/scripts/dep-index.py"
tree_check HEAD && ok || bad "T38" "прибор рабочей копии построил строки коммита по чужому правилу"
# T39 (А10): формы «добавить всё» в режиме PreToolUse — `--all`, кластер `-qam`, `-a` после сообщения.
_i=0
for _form in "git commit --all -m x" "git commit -qam x" "git commit -m x -a"; do
    _i=$((_i+1)); fresh_base "pered39$_i"
    printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t39n%s() { :; }\n' "$_i" > "$R/hooks/alpha.sh"
    OUT=$(run "s39$_i" "$_form")
    assert_contains "$OUT" "Учёт пересобран САМ" "T39 «${_form}» добавляет всё — пересборка по рабочей копии"
done
# T40 (А1): отчёт commit-msg судит дерево коммита — имя, которое есть только в рабочей копии, не называется.
( cd "$R" && git checkout -q -- . ); fresh_base pered40
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t40() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t40() { :; }\nfoo_wip40() { :; }\n' > "$R/hooks/alpha.sh"
trap_run pre >/dev/null; OUT=$(trap_run msg)
assert_lacks "$OUT" "foo_wip40" "T40 отчёт не называет публичное имя, которого в коммите нет"
assert_lacks "$OUT" "строки учёта устарели" "T40б после пересборки отчёт не зовёт учёт устаревшим"
( cd "$R" && git checkout -q -- . )
# --- T42–T45 (D1085, скептик по 6435140d): режим PreToolUse судит ИСПОЛНЯЕМУЮ часть команды -----------------------------
# row_of <ревизия|""> — строка учёта hooks/paths-lib.sh в коммите либо в индексе (пустая ревизия: `:путь`)
row_of() { git -C "$R" show "$1:.claude-docs/dep-index.tsv" 2>/dev/null | awk -F'\t' '$1 == "hooks/paths-lib.sh"'; }
# T42 (А1) и T43 (А8): `-a`/`--all` в тексте сообщения и `git add ./путь` — не «добавить всё»: незастейдженная правка
# paths-lib.sh в учёт индекса не протекает.
_i=0
for _form in 'git commit -m "fix -a bug"' 'git commit -m "add --all option"' 'git add ./hooks/alpha.sh && git commit -m x' \
             'git add .claude-docs/dep-index.tsv && git commit -m x'; do
    _i=$((_i+1)); ( cd "$R" && git checkout -q -- . ); fresh_base "pered42$_i"
    printf '#!/usr/bin/env bash\npaths_helper() { :; }\npaths_t42n%s() { :; }\n' "$_i" > "$R/hooks/paths-lib.sh"
    printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t42n%s() { :; }\n' "$_i" > "$R/hooks/alpha.sh"
    git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
    run "s42$_i" "$_form" >/dev/null
    _ri=$(row_of ""); [ -n "$_ri" ] && [ "$_ri" = "$(row_of HEAD)" ] && ok \
        || bad "T42 «${_form}»" "текст команды принят за «добавить всё»: правка вне индекса протекла в учёт индекса"
done
# T44 (А5): `-a` после сообщения с `;` и после переноса строки — «добавить всё» узнаётся.
_i=0
for _form in "git commit -m 'a; b' -a" "$(printf 'git commit \\\n  -a -m x')"; do
    _i=$((_i+1)); ( cd "$R" && git checkout -q -- . ); fresh_base "pered44$_i"
    printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t44n%s() { :; }\n' "$_i" > "$R/hooks/alpha.sh"
    OUT=$(run "s44$_i" "$_form")
    assert_contains "$OUT" "Учёт пересобран САМ" "T44 форма ${_i}: «добавить всё» после кавычек с «;» и переноса строки"
done
# T46 (D1086, Д1): «добавить всё» с разделителем вплотную, в кластере флагов, `-u` и `-a` перед `;` — узнаётся.
_i=0
for _form in 'git add -A; git commit -m x' 'git add -A&&git commit -m x' 'git add -Av && git commit -m x' \
             'git add --all;git commit -m x' 'git add -u && git commit -m x' 'git commit -qm x -a;'; do
    _i=$((_i+1)); ( cd "$R" && git checkout -q -- . ); fresh_base "pered46$_i"
    printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t46n%s() { :; }\n' "$_i" > "$R/hooks/alpha.sh"
    OUT=$(run "s46$_i" "$_form")
    assert_contains "$OUT" "Учёт пересобран САМ" "T46 «${_form}» — добавить всё"
done
# T47 (D1086, Д2): флаг другой программы внутри `$( )` в сообщении — не флаг `commit`.
( cd "$R" && git checkout -q -- . ); fresh_base pered47
printf '#!/usr/bin/env bash\npaths_helper() { :; }\npaths_t47() { :; }\n' > "$R/hooks/paths-lib.sh"
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t47() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
run s47 'git commit -qm "on $(uname -a)"' >/dev/null
_ri=$(row_of ""); [ -n "$_ri" ] && [ "$_ri" = "$(row_of HEAD)" ] && ok \
    || bad "T47" "флаг внутри \$( ) в сообщении принят за -a: правка вне индекса протекла в учёт индекса"
# T48 (D1086, Д4): библиотека разбора есть, но без функций — ловушка не печатает «command not found».
( cd "$R" && git checkout -q -- . ); fresh_base pered48
: > "$TMP/empty-scope.sh"
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t48() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
OUT=$( cd "$R" && SCOPE_LIB="$TMP/empty-scope.sh" STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$R" bash "$HOOK" --pre-commit </dev/null 2>&1 )
assert_lacks "$OUT" "command not found" "T48 пустая библиотека разбора — без шума в выводе коммита"
# T45 (А2): в режиме PreToolUse коммита ещё нет — отчёт судит рабочую копию: файл, который добавит сама команда, назван.
( cd "$R" && git checkout -q -- . ); fresh_base pered45
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_t45() { :; }\n' > "$R/hooks/alpha.sh"
OUT=$(run s45 'git add hooks/alpha.sh && git commit -m x')
assert_contains "$OUT" "foo_t45" "T45 отчёт PreToolUse называет новое имя файла, который добавит команда"
( cd "$R" && git checkout -q -- . )

# --- T46 (D1093): решение принимает ЛЮБОЙ staged документ состояния, а не первый по списку ---
# PLAN.md стоит в STATE_DOCS раньше CLAUDE.md: до починки PENDING успевал набрать PLAN.md, и «не тронут»
# выходило при staged CLAUDE.md. Положительный контроль: без staged документа состояния сообщение есть.
S="$TMP/d1093"; mkdir -p "$S/hooks" "$S/.claude-docs"
( cd "$S" && git init -q . && git config user.email t@t && git config user.name t \
  && printf '#!/usr/bin/env bash\necho a\n' > hooks/m.sh && printf '# PLAN\n' > PLAN.md && printf '# CLAUDE\n' > CLAUDE.md \
  && printf '# path\tsha\tdeps\tdocs\ttests\tnames\n' > .claude-docs/dep-index.tsv && git add -A && git commit -qm init ) >/dev/null 2>&1 \
  || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:T46" >&2; exit 1; }
printf 'print("описывают изменённое, но не тронуты (1):")\nprint("  . PLAN.md — про hooks/m.sh")\n' > "$TMP/stub46.py"
run46() { jq -cn --arg d "$S" --arg s "$1" '{tool_name:"Bash", tool_input:{command:"git commit -m x"}, cwd:$d, session_id:$s}' \
    | STATE_DIR="$TMP/state46" CLAUDSOUL_ROOT="$S" DEP_INDEX_TOOL="$TMP/stub46.py" bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
printf '#!/usr/bin/env bash\necho b\n' > "$S/hooks/m.sh"; git -C "$S" add hooks/m.sh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
assert_contains "$(run46 s46a)" "документ СОСТОЯНИЯ" "T46a без staged документа состояния решение требуется (положительный контроль)"
printf '# CLAUDE v2\n' > "$S/CLAUDE.md"; git -C "$S" add CLAUDE.md >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_doc_impact_check.sh:$LINENO" >&2; exit 1; }
assert_lacks "$(run46 s46b)" "документ СОСТОЯНИЯ" "T46b staged CLAUDE.md — решение принято, PLAN.md не требуется"

echo ""
echo "doc-impact-check tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
