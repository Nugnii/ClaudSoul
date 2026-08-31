#!/usr/bin/env bash
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
assert_has()    { if grep -qF "$2" <<< "$1"; then ok; else bad "$3" "нет «$2» в: $1"; fi; }
assert_lacks()  { if grep -qF "$2" <<< "$1"; then bad "$3" "нашлось лишнее «$2»: $1"; else ok; fi; }
assert_silent() { [ -z "$1" ] && ok || bad "$2" "ожидалась тишина: $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/hooks" "$R/docs" "$R/.claude-docs" "$R/scripts"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q
git -C "$R" config user.email t@t.local; git -C "$R" config user.name t

printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\n' > "$R/hooks/alpha.sh"
printf '#!/usr/bin/env bash\npaths_helper() { :; }\n' > "$R/hooks/paths-lib.sh"
printf '# Справочник\n\nМеханизм `alpha` делает то-то.\n' > "$R/docs/manual.md"
git -C "$R" add -A >/dev/null; git -C "$R" commit -qm init
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

run() { # run <sid> [команда]
    jq -cn --arg c "${2:-git commit -m x}" --arg d "$R" --arg s "$1" \
        '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d, session_id:$s}' \
    | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

# --- T1: механизм изменён, его документ не тронут → документ назван -----------------
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\n# правка\n' > "$R/hooks/alpha.sh"
git -C "$R" add hooks/alpha.sh >/dev/null
OUT=$(run s1)
assert_has "$OUT" "docs/manual.md" "T1 документ назван"

# --- T2: документ в том же staged → про него молчит --------------------------------
printf '# Справочник\n\nМеханизм `alpha` делает то-то, поправлено.\n' > "$R/docs/manual.md"
git -C "$R" add docs/manual.md >/dev/null
OUT=$(run s2)
assert_lacks "$OUT" "docs/manual.md" "T2 тронутый документ не поминается"

# --- T3: новое публичное имя в существующем модуле → сказано отдельно ---------------
printf '#!/usr/bin/env bash\nsource paths-lib.sh\nfoo_one() { :; }\nfoo_two() { :; }\n' > "$R/hooks/alpha.sh"
git -C "$R" add -A >/dev/null
OUT=$(run s3)
assert_has "$OUT" "foo_two" "T3 новое публичное имя"

# --- T4: новый механизм без строки в учёте → сказано отдельно ----------------------
printf '#!/usr/bin/env bash\nbar() { :; }\n' > "$R/hooks/beta.sh"
git -C "$R" add hooks/beta.sh >/dev/null
OUT=$(run s4)
assert_has "$OUT" "hooks/beta.sh" "T4 новый механизм"
assert_has "$OUT" "без строки в учёте" "T4b формулировка учёта"

# --- T5: зависимый назван именем, а не своим документом ---------------------------
printf '#!/usr/bin/env bash\npaths_helper() { :; }\n# правка\n' > "$R/hooks/paths-lib.sh"
git -C "$R" reset -q; git -C "$R" add hooks/paths-lib.sh >/dev/null
OUT=$(run s5)
assert_has "$OUT" "hooks/alpha.sh" "T5 зависимый назван"

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
git -C "$R" add -A >/dev/null; git -C "$R" commit -qm gamma
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

printf '#!/usr/bin/env bash\n# dep-index: data-region-start\nDATA="один два"\n# dep-index: data-region-end\ngamma_fn() { :; }\n' > "$R/hooks/gamma.sh"
git -C "$R" add hooks/gamma.sh >/dev/null
OUT=$(run s10)
assert_lacks "$OUT" "docs/gamma-doc.md" "T10 данные не поднимают документы"
assert_has   "$OUT" "области данных" "T10b сказано, что это данные"

printf '#!/usr/bin/env bash\n# dep-index: data-region-start\nDATA="один два"\n# dep-index: data-region-end\ngamma_fn() { :; }\n# правка поведения\n' > "$R/hooks/gamma.sh"
git -C "$R" add hooks/gamma.sh >/dev/null
OUT=$(run s11)
assert_has "$OUT" "docs/gamma-doc.md" "T11 правка вне области данных поднимает документ"

# --- T14/T15: как документ называет механизм — правило о форме ИМЕНИ ---------------
# Составное имя (дефис/подчёркивание) обычным словом быть не может, поэтому засчитывается
# и голым. Односложное — может: замер 28 августа 2026 показал, что голое «inject» ловит
# «silent inject» в PLAN.md, «phase» — поле JSON, «cli» — псевдоним домена. Для таких
# нужна форма, помечающая имя: расширение, путь или обратные кавычки.
git -C "$R" reset -q
printf '#!/usr/bin/env bash\nphase_fn() { :; }\n' > "$R/hooks/phase.sh"
printf '#!/usr/bin/env bash\nlong_fn() { :; }\n' > "$R/hooks/long-name-thing.sh"
printf '# Док\n\nЗдесь слово phase встречается как обычное слово.\nА `long-name-thing` назван голым составным именем.\n' > "$R/docs/naming.md"
git -C "$R" add -A >/dev/null; git -C "$R" commit -qm naming
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )

printf '#!/usr/bin/env bash\nphase_fn() { :; }\n# правка\n' > "$R/hooks/phase.sh"
git -C "$R" add hooks/phase.sh >/dev/null
OUT=$(run s14)
assert_lacks "$OUT" "docs/naming.md" "T14 голое односложное слово связью не считается"

printf '#!/usr/bin/env bash\nlong_fn() { :; }\n# правка\n' > "$R/hooks/long-name-thing.sh"
git -C "$R" reset -q; git -C "$R" add hooks/long-name-thing.sh >/dev/null
OUT=$(run s15)
assert_has "$OUT" "docs/naming.md" "T15 голое составное имя связью считается"

printf '# Док\n\nА тут `phase` в обратных кавычках — это имя.\n' > "$R/docs/naming2.md"
git -C "$R" add docs/naming2.md >/dev/null; git -C "$R" commit -qm n2 >/dev/null
( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py --all >/dev/null )
printf '#!/usr/bin/env bash\nphase_fn() { :; }\n# ещё правка\n' > "$R/hooks/phase.sh"
git -C "$R" add hooks/phase.sh >/dev/null
OUT=$(run s16)
assert_has "$OUT" "docs/naming2.md" "T16 имя в обратных кавычках связью считается"

echo ""
echo "doc-impact-check tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
