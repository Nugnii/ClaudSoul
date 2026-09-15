#!/usr/bin/env bash
# test_dep_index_input_role.sh — индекс зависимостей отказывает на входе, которого нет, и
# судит путь по РОЛИ строки, а не по вхождению подстроки (D304, пять голов прожарки).
#
# Механика — два корня.
#  А. Признак снят с ФОРМЫ текста, а не с роли: `is_snapshot()` считала снимком всякое имя,
#     где встретилось «-archive» (живой документ про архивирование молча выпадал из корпуса,
#     и doc-impact-check переставал о нём говорить); `mentions()` засчитывала форму `/имя`
#     при любом соседе слева, то есть слэш в ПРОЗЕ делал тест одного модуля тестом другого;
#     `load()` считала комментарием всякую строку с `#` в начале, и механизм, чей путь
#     начинается с `#`, краснил `--check` сразу после успешной сборки.
#  Б. Непригодный вход не отбивается: `--changed <несуществующий путь>` рапортовал успех и
#     оставлял учёт несогласованным; неразрешённый конфликт в индексе ронял `--check` и
#     `--changed` трейсбеком, хотя класс `IndexConflict` заведён.
#
# У проверки ПОЛ и ПОТОЛОК: потолок ловит лишнее (прозаический слэш, ложный снимок),
# пол — потерянное (настоящий путь, настоящий архив, живые режимы).
#
# КОНТРПРИМЕР: документ, честно названный `*-archive.md` и при этом живой, снимком считаться
# продолжит — имя тут конвенция, а объявление роли одно: маркер `doc-kind: snapshot`.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; R="$TMP/repo"
mkdir -p "$R/hooks/tests" "$R/.claude-docs" "$R/scripts" "$R/docs"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
for m in alpha beta gamma; do
    printf '#!/usr/bin/env bash\n%s_one() { :; }\n' "$m" > "$R/hooks/$m.sh"
done
printf '#!/usr/bin/env bash\ndelta_one() { :; }\n' > "$R/hooks/delta.sh"
# Односложное имя: голое упоминание не считается, форма «путь/имя» — считается.
printf 'def run():\n    return 1\n' > "$R/scripts/parse.py"
# Живой документ, у которого в имени есть «-archive», но который описывает НЫНЕШНЕЕ.
printf '# Как архивировать сессии\n\nСмотри hooks/alpha.sh.\n' > "$R/docs/how-to-archive-sessions.md"
# Настоящий архив по конвенции проекта: `<имя>-archive[-d<номер>].md`.
printf '# Перенос из notes.md (D7)\n\nхроника про hooks/beta.sh.\n' > "$R/docs/notes-archive-d7.md"
# Слэш в ПРОЗЕ перед односложным именем — путём не является.
printf '#!/usr/bin/env bash\necho "режим чтение/parse включён"\n' > "$R/hooks/tests/test_prose.sh"
# Настоящий путь без расширения — является.
printf '#!/usr/bin/env bash\nbash "$R/scripts/parse.py"\n' > "$R/hooks/tests/test_path.sh"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm init >/dev/null 2>&1
IDX="$R/.claude-docs/dep-index.tsv"
run() { ( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py "$@" ) ; }
col()  { grep "^$1	" "$IDX" | cut -f"$2"; }

run --all >/dev/null 2>&1 || { echo "FAIL: базовая сборка не прошла"; exit 1; }

# --- А1: снимок по РОЛИ, а не по подстроке в имени -------------------------------------
if [ "$(col hooks/alpha.sh 4)" = "docs/how-to-archive-sessions.md" ]; then
    ok "A1 живой документ со словом archive в имени остался в корпусе"
else
    bad "A1" "docs/how-to-archive-sessions.md называет alpha.sh, колонка docs: [$(col hooks/alpha.sh 4)]"
fi
if [ -z "$(col hooks/beta.sh 4)" ]; then
    ok "A2 архив по конвенции <имя>-archive-dN.md снимком остался"
else
    bad "A2" "notes-archive-d7.md — архив, колонка docs beta: [$(col hooks/beta.sh 4)]"
fi

# --- А3: слэш в прозе путём не считается ------------------------------------------------
PT=$(col scripts/parse.py 5)
if ! grep -q "test_prose" <<< "$PT"; then
    ok "A3 слэш в прозе (чтение/parse) связью не считается"
else
    bad "A3" "колонка tests parse.py: [$PT]"
fi
if grep -q "test_path" <<< "$PT"; then
    ok "A4 настоящий путь scripts/parse связью остаётся"
else
    bad "A4" "колонка tests parse.py: [$PT]"
fi

# --- А5: путь механизма, начинающийся с # (строка индекса неотличима от комментария) ------
printf '#!/usr/bin/env bash\nhash_one() { :; }\n' > "$R/#hash.sh"
git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm hash >/dev/null 2>&1
run --all >/dev/null 2>&1
OUT=$(run --check 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
    ok "A5 --check зелен сразу после сборки при пути с # в начале"
else
    bad "A5" "код $rc: $OUT"
fi
git -C "$R" rm -q "#hash.sh" >/dev/null 2>&1
git -C "$R" commit -qm rmhash >/dev/null 2>&1; run --all >/dev/null 2>&1

# --- Б1: вход, которого нет, отбивается и не пишет ---------------------------------------
BEFORE=$(cat "$IDX")
OUT=$(run --changed scripts/нет-такого-файла.py 2>&1); rc=$?
if [ "$rc" -ne 0 ] && [ "$(cat "$IDX")" = "$BEFORE" ]; then
    ok "Б1 --changed на несуществующий путь: код $rc, индекс не тронут"
else
    bad "Б1" "код $rc, индекс изменён: $([ "$(cat "$IDX")" = "$BEFORE" ] && echo нет || echo да)"
fi
# Пол: удалённый этим коммитом механизм — законный вход, его строка обязана уйти.
git -C "$R" rm -q hooks/delta.sh >/dev/null 2>&1
git -C "$R" commit -qm rm >/dev/null 2>&1
OUT=$(run --changed hooks/delta.sh 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^hooks/delta\.sh	' "$IDX"; then
    ok "Б2 удалённый механизм — законный вход, строка убрана"
else
    bad "Б2" "код $rc, строка delta осталась: $(grep -c '^hooks/delta\.sh	' "$IDX")"
fi
OUT=$(run --changed hooks/alpha.sh 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then ok "Б3 живой механизм — законный вход"; else bad "Б3" "код $rc: $OUT"; fi

# --- Б4: конфликт слияния — вердикт, а не трейсбек ---------------------------------------
cp "$IDX" "$TMP/keep.tsv"
{ echo "<<<<<<< HEAD"; cat "$TMP/keep.tsv"; echo "======="; echo ">>>>>>> other"; } > "$IDX"
OUT=$(run --check 2>&1); rc=$?
if [ "$rc" -eq 2 ] && grep -q "конфликт" <<< "$OUT" && ! grep -q "Traceback" <<< "$OUT"; then
    ok "Б4 --check при конфликте: код 2 и вердикт словами"
else
    bad "Б4" "код $rc: $(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi
OUT=$(run --changed hooks/alpha.sh 2>&1); rc=$?
if [ "$rc" -eq 2 ] && grep -q "конфликт" <<< "$OUT" && ! grep -q "Traceback" <<< "$OUT"; then
    ok "Б5 --changed при конфликте: код 2 и вердикт словами"
else
    bad "Б5" "код $rc: $(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi
if [ "$(cat "$IDX" | head -1)" = "<<<<<<< HEAD" ]; then
    ok "Б6 конфликтный индекс не перезаписан"
else
    bad "Б6" "индекс переписан поверх конфликта"
fi

echo ""
echo "dep-index input-role: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
