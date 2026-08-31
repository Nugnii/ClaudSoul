#!/usr/bin/env bash
# test_adv3_dep_tsv_escaping.sh — у формата индекса нет экранирования, и путь этим ломается.
#
# Формат объявлен в шапке dep-index.py: поля через табуляцию, внутри поля список через
# запятую. Ни один из двух разделителей в путях не запрещён и не экранируется:
#   save()  — `"\t".join(rows[path])`, поля собраны `",".join(...)`
#   load()  — `line.split("\t")`, дальше `r[3].split(",")`, `r[2].split(",")`
#
# C1. Запятая в пути ДОКУМЕНТА. `docs/a,b.md` кладётся в поле docs как есть, читается
#     как ДВА документа — «docs/a» и «b.md». Обоих на диске нет. Хук печатает их как
#     «описывают изменённое, но не тронуты», то есть требует обновить несуществующие файлы.
#     Хуже: правило «тронутый документ не поминается» (`d not in staged`) сверяет строку
#     целиком, а обломки с ней не совпадают — реальный документ ЗАСТЕЙДЖЕН, а хук всё
#     равно требует его обновить, только под двумя выдуманными именами.
#
# C2. Табуляция в пути МЕХАНИЗМА. `save()` пишет строку с седьмым полем, `load()` берёт
#     только `len(parts) == 6` и молча выбрасывает её целиком. Итог: `--check` красный
#     СРАЗУ после успешного `--all`, и предписанное им же лекарство («пересобрать:
#     --all») не лечит — расхождение вечное. Механизм при этом выпадает из учёта весь.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)

# --- C1: запятая в имени документа --------------------------------------------------
R="$TMP/comma"; mkdir -p "$R/hooks" "$R/scripts" "$R/docs" "$R/.claude-docs"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
printf '#!/usr/bin/env bash\nalpha_fn() { :; }\n' > "$R/hooks/alpha-hook.sh"
printf '# Заметка\n\nМеханизм alpha-hook описан здесь.\n' > "$R/docs/a,b.md"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

# правим механизм И его документ — оба уходят в коммит
printf '#!/usr/bin/env bash\nalpha_fn() { echo new; }\n' > "$R/hooks/alpha-hook.sh"
printf '# Заметка\n\nМеханизм alpha-hook описан здесь. Обновлено.\n' > "$R/docs/a,b.md"
git -C "$R" add -A >/dev/null 2>&1
OUT=$( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --impact hooks/alpha-hook.sh 'docs/a,b.md' 2>&1 )

GHOSTS=$(grep -cE '^  . (docs/a|b\.md) ' <<< "$OUT" || true)
if [ "$GHOSTS" -eq 0 ]; then
    ok "C1 запятая в пути документа не породила выдуманных имён"
else
    bad "C1 запятая в пути документа" "в коммите оба файла — hooks/alpha-hook.sh и docs/a,b.md.
      Документ ТРОНУТ, поминать его нельзя. Отчёт:
$(printf '%s\n' "$OUT" | sed 's/^/      /')
      названо несуществующих документов: $GHOSTS (docs/a и b.md на диске нет:
      $(ls "$R/docs" | tr '\n' ' '))"
fi

# --- C2: табуляция в имени механизма ------------------------------------------------
R2="$TMP/tabname"; mkdir -p "$R2/hooks" "$R2/scripts" "$R2/.claude-docs"
cp "$INDEXER" "$R2/scripts/dep-index.py"
git -C "$R2" init -q; git -C "$R2" config user.email t@t.local; git -C "$R2" config user.name t
printf '#!/usr/bin/env bash\nbeta_fn() { :; }\n' > "$R2/hooks/beta-hook.sh"
TABNAME="$R2/hooks/$(printf 'ta\tb')-hook.sh"
printf '#!/usr/bin/env bash\ntabbed_fn() { :; }\n' > "$TABNAME" 2>/dev/null \
    || { echo "SKIP: файловая система не приняла таб в имени"; }
if [ -f "$TABNAME" ]; then
    git -C "$R2" add -A >/dev/null 2>&1; git -C "$R2" commit -qm init >/dev/null 2>&1
    ALL=$( cd "$R2" && CLAUDSOUL_REPO="$R2" python3 scripts/dep-index.py --all 2>&1 ); ARC=$?
    CHK=$( cd "$R2" && CLAUDSOUL_REPO="$R2" python3 scripts/dep-index.py --check 2>&1 ); CRC=$?
    ALL2=$( cd "$R2" && CLAUDSOUL_REPO="$R2" python3 scripts/dep-index.py --all 2>&1 )
    CHK2=$( cd "$R2" && CLAUDSOUL_REPO="$R2" python3 scripts/dep-index.py --check 2>&1 ); CRC2=$?
    if [ "$CRC" -eq 0 ]; then
        ok "C2 --check зелёный сразу после --all"
    else
        bad "C2 табуляция в пути механизма" "--all (rc=$ARC): «${ALL}»
      --check сразу за ним (rc=$CRC):
$(printf '%s\n' "$CHK" | sed 's/^/      /')
      повторное лечение по его же рецепту («${ALL2}») не помогает, --check снова rc=$CRC2:
$(printf '%s\n' "$CHK2" | sed 's/^/      /')
      строка выброшена в load() по len(parts)==6 — механизм выпал из учёта навсегда"
    fi
else
    echo "SKIP C2: таб в имени файла не создался"
fi

echo ""
echo "adv3 dep tsv-escaping: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
