#!/usr/bin/env bash
# test_dep_index_unreadable.sh — нечитаемый файл не притворяется пустым (род дефекта B).
#
# Механика. `read()` в scripts/dep-index.py отдавал при OSError пустую строку. Пустая
# строка — законное содержимое файла, маркером «не смог» быть не может: строка индекса
# нечитаемого механизма выходит ровно такой же, как у пустого (deps пусты, публичные
# имена пусты, sha = sha1 пустоты). Хуже того, эта строка СТАБИЛЬНА — sha пустоты не
# меняется, — поэтому записанная однажды, она больше никогда не покраснеет, а `--check`
# при этом печатал «индекс зависимостей совпадает с деревом» и код 0.
#
# Замерено на временном дереве: alpha.sh подключает beta.sh; после chmod 000 alpha
# строка стала `hooks/alpha.sh|da39a3ee5e6b||…` (da39a3ee5e6b — sha1 пустоты), и
# `--impact hooks/beta.sh` переставал называть alpha среди зависимых. Страж «изменил
# механизм — обнови описания» замолкал именно на том файле, который нельзя прочитать.
#
# Починка — не «не гасить» (пустой файл законен), а гасить, НАЗВАВ ЦЕНУ (образец —
# hooks/lib/unread-lib.sh): отказ считается, каждый вердикт его называет, отравленная
# строка в индекс не кладётся.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); R="$TMP/repo"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$R/hooks" "$R/scripts" "$R/.claude-docs/modules"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q
git -C "$R" config user.email t@t.local
git -C "$R" config user.name t
printf '#!/usr/bin/env bash\nsource "$(dirname "$0")/beta.sh"\nalpha_fn() { :; }\n' > "$R/hooks/alpha.sh"
printf '#!/usr/bin/env bash\nbeta_fn() { :; }\n' > "$R/hooks/beta.sh"
printf '# alpha\n\nМеханизм `alpha.sh` описан здесь.\n' > "$R/.claude-docs/modules/alpha.md"
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_dep_index_unreadable.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_dep_index_unreadable.sh:$LINENO" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null 2>&1 )

BEFORE=$(cksum < "$R/.claude-docs/dep-index.tsv")
grep -q 'hooks/beta.sh' "$R/.claude-docs/dep-index.tsv" \
    || bad "фикстура" "в собранном индексе нет связи alpha→beta, проверять нечего"

# Мутация: файл под учётом становится нечитаемым (права, оборванный симлинк, гонка с
# удалением). Содержимое при этом не менялось — меняется только возможность его прочесть.
chmod 000 "$R/hooks/alpha.sh"
if cat "$R/hooks/alpha.sh" >/dev/null 2>&1; then
    echo "SKIP: chmod 000 не закрывает чтение (прогон от root) — мутацию не поставить"
    exit 0
fi

# --- T1: пересборка НЕ кладёт отравленную строку в индекс -------------------------
OUT1=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all 2>&1 ); RC1=$?
AFTER=$(cksum < "$R/.claude-docs/dep-index.tsv")
[ "$RC1" -ne 0 ] && ok "T1a пересборка по нечитаемому файлу вернула не-ноль ($RC1)" \
    || bad "T1a" "пересборка при нечитаемом hooks/alpha.sh вернула 0: [$OUT1]"
grep -qF "не прочитано" <<< "$OUT1" && ok "T1b цена названа" \
    || bad "T1b" "отказ чтения не назван в выводе: [$OUT1] (пусто = ни строки)"
[ "$BEFORE" = "$AFTER" ] && ok "T1c индекс не перезаписан отравленной строкой" \
    || bad "T1c" "индекс перезаписан по нечитаемому файлу — строка пустоты стабильна и больше не покраснеет"

# --- T2: сверка не зеленеет и не врёт «устарел» -----------------------------------
OUT2=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check 2>&1 ); RC2=$?
[ "$RC2" -eq 2 ] && ok "T2a сверка вернула 2 («не смог»), а не 0/1" \
    || bad "T2a" "--check при нечитаемом файле вернул $RC2: [$OUT2]"
grep -qF "не прочитано" <<< "$OUT2" && ok "T2b сверка называет непрочитанное" \
    || bad "T2b" "--check не назвал отказ чтения: [$OUT2] (пусто = ни строки)"

# --- T3: последствие — связь alpha→beta уцелела, страж не онемел -------------------
git -C "$R" add -A >/dev/null 2>&1 || true  # в песочнице лежит нечитаемый файл — это предмет проверки, git add на нём краснеет
OUT3=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/beta.sh 2>&1 )
grep -qF "hooks/alpha.sh" <<< "$OUT3" && ok "T3 alpha назван зависимым от beta" \
    || bad "T3" "после отказа чтения --impact beta не называет alpha: [$OUT3] (пусто = ни строки)"

# --- T4: контроль — права вернули, всё зелено ------------------------------------
chmod 644 "$R/hooks/alpha.sh"
OUT4=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check 2>&1 ); RC4=$?
{ [ "$RC4" -eq 0 ] && grep -qF "совпадает с деревом" <<< "$OUT4"; } \
    && ok "T4 читаемое дерево — сверка зелёная" \
    || bad "T4" "--check на читаемом дереве дал $RC4: [$OUT4]"

# --- T5–T7: запись дерева, не являющаяся файлом, — не сбой; сбой — по-прежнему сбой (D1185, скептик: M2–M4) ----
# Ссылка на каталог отбрасывается при сборке перечня; ссылка на ФАЙЛ остаётся файлом учёта со своими связями;
# битая ссылка и неподготовленное удаление называются «не прочитано». Правило судит путь от корня, а не от каталога вызова.
ln -s alpha.sh "$R/hooks/alpha-link.sh"; ln -s hooks "$R/hl"
printf '#!/usr/bin/env bash\ngone_fn() { :; }\n' > "$R/hooks/gone.sh"
git -C "$R" add -A >/dev/null 2>&1 && git -C "$R" commit -qm links >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: ноги T5–T7" >&2; exit 1; }
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null 2>&1 )
OUT5=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/beta.sh 2>&1 )
{ grep -qF "hooks/alpha-link.sh" <<< "$OUT5" && ! grep -qF "не прочитано" <<< "$OUT5"; } \
    && ok "T5 ссылка на файл — узел со связями, ссылка на каталог — не «не прочитано»" \
    || bad "T5" "--impact beta: [$OUT5] (ждали alpha-link.sh среди зависимых и ни слова «не прочитано»)"
OUT6=$( cd "$R/hooks" && CLAUDSOUL_REPO="$R" python3 ../scripts/dep-index.py --impact hooks/beta.sh 2>&1 )
grep -qF "не прочитано" <<< "$OUT6" && bad "T6" "вызов из hooks/: ссылка на каталог снова «не прочитано»: [$OUT6]" \
    || ok "T6 вызов из подкаталога — правило судит путь от корня"
ln -s nowhere.sh "$R/hooks/dangling.sh"; rm "$R/hooks/gone.sh"
OUT7=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --check 2>&1 ); RC7=$?
{ [ "$RC7" -eq 2 ] && grep -qF "dangling.sh: файла нет" <<< "$OUT7" && grep -qF "gone.sh: файла нет" <<< "$OUT7"; } \
    && ok "T7 битая ссылка и удалённый файл названы «не прочитано», сверка — 2" \
    || bad "T7" "--check при битой ссылке и удалённом файле дал $RC7: [$OUT7]"

echo "test_dep_index_unreadable: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
