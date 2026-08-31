#!/usr/bin/env bash
# test_adv3_dep_abs_path.sh — абсолютный путь: обе подкоманды не узнают файл и молчат об этом.
#
# Хук заканчивает каждое своё сообщение строкой
#     Пересобрать индекс после правки: python3 scripts/dep-index.py --changed <файлы>
# и не говорит, в какой ФОРМЕ ждёт путь. Форму диктует среда: глобальные правила агента
# требуют абсолютных путей («please only use absolute file paths»), а `Read`/`Edit`
# абсолютного пути и требуют — то есть путь под рукой у исполнителя именно абсолютный.
#
# `impact()` и `build()` сверяют аргумент со строками индекса ТОЧНЫМ равенством строк.
# Ни нормализации, ни отбрасывания префикса репозитория, ни отказа на неизвестной форме.
#
# B1. `--impact /abs/hooks/alpha-hook.sh` — механизм со строкой в учёте, с документом и с
#     НОВЫМ публичным именем объявляется «новым механизмом без строки в учёте»; документ
#     не назван вовсе. Отчёт не пустой, поэтому и хук напечатает именно это.
# B2. `--changed /abs/hooks/alpha-hook.sh` — `wanted` пуст, ни одна строка не пересчитана,
#     файл индекса переписан байт в байт, а на stdout — «индекс собран: механизмов N».
#     Успех отрапортован, работа не сделана: `--check` сразу за этим красный.
# B3. То же для формы `./hooks/...` — её даёт `find`, автодополнение и вставка из вывода.
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
printf '#!/usr/bin/env bash\nalpha_fn() { :; }\n' > "$R/hooks/alpha-hook.sh"
printf '# Справочник\n\nМеханизм alpha-hook описан здесь.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

printf '#!/usr/bin/env bash\nalpha_fn() { echo new; }\nbrand_new_fn() { :; }\n' > "$R/hooks/alpha-hook.sh"
git -C "$R" add -A >/dev/null 2>&1

REL=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/alpha-hook.sh 2>&1 )
ABS=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact "$R/hooks/alpha-hook.sh" 2>&1 )
DOT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact ./hooks/alpha-hook.sh 2>&1 )

grep -q 'docs/manual.md' <<< "$REL" || { echo "SKIP: предпосылка не собралась"; exit 0; }

# --- B1 ---------------------------------------------------------------------------
if grep -q 'docs/manual.md' <<< "$ABS"; then
    ok "B1 --impact с абсолютным путём назвал документ"
else
    bad "B1 --impact с абсолютным путём" "тот же файл, другая форма пути — документ пропал.
      относительный:
$(printf '%s\n' "$REL" | sed 's/^/      /')
      абсолютный:
$(printf '%s\n' "$ABS" | sed 's/^/      /')"
fi

# --- B3 ---------------------------------------------------------------------------
if grep -q 'docs/manual.md' <<< "$DOT"; then
    ok "B3 --impact с ./ назвал документ"
else
    bad "B3 --impact с ./" "форма ./hooks/alpha-hook.sh — тот же файл, отчёт другой:
$(printf '%s\n' "$DOT" | sed 's/^/      /')"
fi

# --- B2 ---------------------------------------------------------------------------
BEFORE=$(cat "$R/.claude-docs/dep-index.tsv")
SAY=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --changed "$R/hooks/alpha-hook.sh" 2>&1 ); RC=$?
AFTER=$(cat "$R/.claude-docs/dep-index.tsv")
CHECK=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check 2>&1 ); CRC=$?
if [ "$RC" -eq 0 ] && [ "$BEFORE" = "$AFTER" ] && [ "$CRC" -ne 0 ]; then
    bad "B2 --changed с абсолютным путём" "rc=$RC, на stdout «${SAY}»,
      файл индекса не изменился ни на байт, ни одна строка не пересчитана,
      а --check сразу за этим (rc=$CRC):
$(printf '%s\n' "$CHECK" | sed 's/^/      /')
      успех отрапортован, работа не сделана и об этом не сказано"
else
    ok "B2 --changed с абсолютным путём не выдал бездействие за успех"
fi

echo ""
echo "adv3 dep abs-path: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
