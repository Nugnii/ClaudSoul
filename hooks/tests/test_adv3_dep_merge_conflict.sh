#!/usr/bin/env bash
# test_adv3_dep_merge_conflict.sh — индекс в конфликте слияния читается как исправный,
# и вместе с проигравшей стороной молча пропадает настоящая зависимость.
#
# `.claude-docs/dep-index.tsv` под учётом git, пересобирается почти каждым коммитом,
# сортирован по пути и не имеет ни merge-драйвера, ни записи в .gitattributes. Две ветки,
# тронувшие один механизм, дают конфликт в нём с вероятностью, близкой к единице.
#
# `load()` берёт строки так: пропускает начинающиеся с `#`, берёт те, где ровно 6 полей
# через таб. Маркеры `<<<<<<<`, `=======`, `>>>>>>>` под это не подходят и молча
# выбрасываются, а строки ОБЕИХ сторон остаются — и складываются в один dict, где
# побеждает последняя, то есть «их» сторона. Никакой проверки, что файл не в конфликте,
# нет ни в dep-index.py, ни в хуке (его условие включения — `[ -f ... ]`, «файл на месте»).
#
# Цена конкретная: `dependents` собираются ТОЛЬКО из сохранённых строк (rev по полю deps)
# и, в отличие от `docs`, не пересчитываются. Ребро, записанное на проигравшей стороне,
# исчезает. В дереве после слияния зависимость есть, в отчёте её нет, о конфликте не
# сказано ни слова.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
# Тело именованной секции отчёта: строки после заголовка до следующей строки с 0-й позиции.
# Отчёт `--impact` — плоский список секций, тело каждой идёт с отступа.
sect() { awk -v h="$1" 'substr($0,1,length(h))==h{f=1;next} /^[^[:space:]]/{f=0} f'; }
# Несобранная фикстура — ПРОВАЛ, а не пропуск: см. комментарий у блока фикстуры.
die() { bad "$1" "$2"; echo ""; echo "adv3 dep merge-conflict: $PASS/$((PASS+FAIL)) passed"; exit 1; }

TMP=$(mktemp -d); R="$TMP/repo"
mkdir -p "$R/hooks" "$R/scripts" "$R/docs" "$R/.claude-docs"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
git -C "$R" symbolic-ref HEAD refs/heads/main

rebuild() { ( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null ); }

printf '#!/usr/bin/env bash\ncore_fn() { :; }\n' > "$R/hooks/core-lib.sh"
{ printf '#!/usr/bin/env bash\n'; printf '# заголовок\n'; printf 'c_one() { :; }\n'; printf '# хвост\n'; } > "$R/hooks/consumer.sh"
printf '# Справочник\n\nМеханизм core-lib описан здесь.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null 2>&1; rebuild; git -C "$R" add -A >/dev/null 2>&1
git -C "$R" commit -qm init >/dev/null 2>&1

git -C "$R" checkout -qb feat
{ printf '#!/usr/bin/env bash\n'; printf '# заголовок\n'; printf 'c_one() { :; }\n'; printf 'c_two() { :; }\n'; } > "$R/hooks/consumer.sh"
rebuild; git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm feat >/dev/null 2>&1

git -C "$R" checkout -q main
{ printf '#!/usr/bin/env bash\n'; printf 'source hooks/core-lib.sh\n'; printf 'c_one() { :; }\n'; printf '# хвост\n'; } > "$R/hooks/consumer.sh"
rebuild; git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm main2 >/dev/null 2>&1

# --- фикстура: состояние УСТАНАВЛИВАЕТСЯ, а не предполагается ------------------------
# Предполагалось: слияние даст конфликт в индексе, а consumer.sh сольётся чисто.
# Ложно: код возврата `merge` гасился, а несобравшийся сценарий уходил в SKIP с кодом
# УСПЕХА. Проверено мутацией `read()` в scripts/dep-index.py (все чтения падают): индекс
# не собирался вовсе, конфликта не возникало, тест был ЗЕЛЁН, не посмотрев на предмет.
# Держит: каждая предпосылка — отдельный вердикт с ненулевым кодом.
git -C "$R" merge feat >/dev/null 2>&1 \
  && die "фикстура" "слияние прошло БЕЗ конфликта — сценарий не собран, проверять нечего"
UNMERGED=$(git -C "$R" diff --name-only --diff-filter=U)
grep -qxF '.claude-docs/dep-index.tsv' <<< "$UNMERGED" \
  || die "фикстура" "индекс не помечен неразрешённым; unmerged: ${UNMERGED:-<пусто>}"
grep -q '^<<<<<<<' "$R/.claude-docs/dep-index.tsv" \
  || die "фикстура" "маркеров конфликта в индексе нет — читать нечему"
grep -q 'source hooks/core-lib.sh' "$R/hooks/consumer.sh" \
  || die "фикстура" "consumer.sh не слился: зависимости в дереве нет, терять нечего"

printf '#!/usr/bin/env bash\ncore_fn() { echo new; }\n' > "$R/hooks/core-lib.sh"
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/core-lib.sh 2>&1 )

# --- E1: зависимость есть в дереве, в отчёте её нет ---------------------------------
# Предполагалось: имя `hooks/consumer.sh` где угодно в отчёте = зависимый назван.
# Ложно: тем же именем отчёт называет НЕПРОЧИТАННОЕ («не прочитано: 4 — …,
# hooks/consumer.sh: файла нет»). При мутации `read()` зависимые не считались вообще,
# а нога была зелёной.
# Держит: счёт в заголовке секции зависимых обязан быть ≥ 1, а адрес ищется точным
# совпадением в ЕЁ теле, не по всему отчёту.
DEP_N=$(sed -n 's/^зависят от изменённого (\([0-9]*\)).*/\1/p' <<< "$OUT")
DEP_LIST=$(sect 'зависят от изменённого (' <<< "$OUT" | tr ',' '\n' | sed 's/^ *//;s/ *$//')
if [ "${DEP_N:-0}" -ge 1 ] && grep -qxF 'hooks/consumer.sh' <<< "$DEP_LIST"; then
    ok "E1 зависимый назван"
else
    bad "E1 зависимость потеряна вместе с проигравшей стороной конфликта" \
"после слияния hooks/consumer.sh содержит «source hooks/core-lib.sh» — зависимость реальна.
      Индекс в конфликте:
$(sed -n '3,8p' "$R/.claude-docs/dep-index.tsv" | sed 's/^/      /')
      побеждает нижняя строка («их»), в ней поле deps пустое. Отчёт про правку core-lib:
$(printf '%s\n' "$OUT" | sed 's/^/      /')
      dependents берутся только из сохранённых строк и не пересчитываются"
fi

# --- E2: о самом конфликте не сказано ничего ----------------------------------------
# Предполагалось: слово «конфликт» в отчёте = конфликт замечен. Ложно: слово — весь
# вердикт, а осмотрен ли неразрешённый файл, нога не спрашивала; результат зонда COUNT
# в неё не входил вовсе и печатался только в тексте провала.
# Держит: сперва ВЕЛИЧИНА — `load()` обязан ОТКАЗАТЬСЯ читать неразрешённый файл
# (IndexConflict), а не вернуть правдоподобный словарь строк обеих сторон.
# ПРЕДЕЛ: второе условие — про формулировку в отчёте, то есть о тексте; величины,
# отличающей «сказал» от «промолчал», у печати нет.
PROBE=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 - <<'PY' 2>&1
import importlib.util
spec = importlib.util.spec_from_file_location("di", "scripts/dep-index.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try:
    r = m.load()
except m.IndexConflict:
    print("CONFLICT")
else:
    print("ROWS %d consumer=%s" % (len(r), "hooks/consumer.sh" in r))
PY
)
if [ "$PROBE" = "CONFLICT" ] && grep -qiE 'конфликт|не разрешён|unmerged' <<< "$OUT"; then
    ok "E2 про конфликт индекса сказано"
else
    bad "E2 конфликт индекса не назван" "load() на неразрешённом файле дал: $PROBE
      (ожидалось CONFLICT — отказ читать. «ROWS n» значит, что строки ОБЕИХ сторон
      сложились в один учёт: побеждает нижняя, потерянные связи выглядят отсутствующими)
      отчёт --impact:
$(printf '%s\n' "$OUT" | sed 's/^/      /')"
fi

echo ""
echo "adv3 dep merge-conflict: $PASS/$((PASS+FAIL)) passed"
exit $(( FAIL != 0 ))
