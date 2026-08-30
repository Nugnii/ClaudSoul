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

git -C "$R" merge feat >/dev/null 2>&1
grep -q '^<<<<<<<' "$R/.claude-docs/dep-index.tsv" || { echo "SKIP: конфликт в индексе не собрался"; exit 0; }
grep -q 'source hooks/core-lib.sh' "$R/hooks/consumer.sh" || { echo "SKIP: consumer.sh не слился"; exit 0; }

printf '#!/usr/bin/env bash\ncore_fn() { echo new; }\n' > "$R/hooks/core-lib.sh"
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/core-lib.sh 2>&1 )

# --- E1: зависимость есть в дереве, в отчёте её нет ---------------------------------
if grep -q 'hooks/consumer.sh' <<< "$OUT"; then
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
COUNT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 - <<'PY' 2>/dev/null
import importlib.util
spec = importlib.util.spec_from_file_location("di", "scripts/dep-index.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
r = m.load()
print("%d %s" % (len(r), "hooks/consumer.sh" in r))
PY
)
if grep -qiE 'конфликт|не разрешён|unmerged' <<< "$OUT"; then
    ok "E2 про конфликт индекса сказано"
else
    bad "E2 конфликт индекса не назван" "load() разобрал неразрешённый файл без единой жалобы
      и вернул правдоподобный учёт: строк/есть consumer = $COUNT.
      Ни dep-index.py, ни хук не проверяют, что индекс не в конфликте: условие включения
      хука — «файл на месте». В отчёте (rc и текст выше) слова про конфликт нет"
fi

echo ""
echo "adv3 dep merge-conflict: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
