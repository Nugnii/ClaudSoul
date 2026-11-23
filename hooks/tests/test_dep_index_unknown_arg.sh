#!/usr/bin/env bash
# test_dep_index_unknown_arg.sh — аргумент вне перечня режимов индекса отбивается кодом 2
# и мира не меняет; известные режимы работают как прежде (D288).
#
# Механика. `main()` спрашивал у аргументов три раза «есть ли тут --impact / --check /
# --changed» и всё, что не совпало, роняло в остаток `rows = build(); save(rows)` — то есть
# в ЗАПИСЬ файла. Поймано дважды 6 сентября 2026: `--help` напечатал «индекс собран» и
# переписал `.claude-docs/dep-index.tsv`, исполнитель соседнего пункта побочно перестроил
# 101 строку чужого индекса. Тот же класс, что закрывали 1 сентября 2026 у measurement-due.sh:
# признак снят с ПРИСУТСТВИЯ известного флага, а не с ПРИНАДЛЕЖНОСТИ входа перечню, и
# неизвестное сваливается в умолчание — самое разрушительное действие прибора.
#
# У проверки есть ПОТОЛОК (R1-R3: неизвестное не пишет) и ПОЛ (R4-R8: известное работает).
# Без пола проходит переснятие «отказывать всегда», которое убивает прибор целиком.
#
# КОНТРПРИМЕР: путь файла, начинающийся с дефиса, признан аргументом и отбит. Таких путей
# в дереве ноль, и это известно.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INDEXER="$REPO/scripts/dep-index.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS [$1]"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; R="$TMP/repo"
mkdir -p "$R/hooks" "$R/.claude-docs" "$R/scripts" "$R/docs"
cp "$INDEXER" "$R/scripts/dep-index.py"
git -C "$R" init -q; git -C "$R" config user.email t@t.local; git -C "$R" config user.name t
for m in alpha beta; do
    printf '#!/usr/bin/env bash\n%s_one() { :; }\n' "$m" > "$R/hooks/$m.sh"
done
printf '# Хук alpha.sh\n\nописание.\n' > "$R/docs/alpha.md"
git -C "$R" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_dep_index_unknown_arg.sh:$LINENO" >&2; exit 1; }
git -C "$R" commit -qm init >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_dep_index_unknown_arg.sh:$LINENO" >&2; exit 1; }
IDX="$R/.claude-docs/dep-index.tsv"
run() { ( cd "$R" && CLAUDSOUL_REPO="$R" python3 scripts/dep-index.py "$@" ) ; }

run --all >/dev/null 2>&1 || { echo "FAIL: базовая сборка не прошла"; exit 1; }
# Механизм изменён ПОСЛЕ сборки: теперь всякая пересборка обязана изменить файл, и
# «не тронул» отличимо от «переписал тем же».
printf '#!/usr/bin/env bash\nalpha_one() { :; }\nalpha_two() { :; }\n' > "$R/hooks/alpha.sh"
BEFORE=$(cat "$IDX")

# --- ПОТОЛОК: вход вне перечня отбивается и не пишет ------------------------------------
for arg in --нет-такого-флага --help -h; do
    run "$arg" >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 2 ] && [ "$(cat "$IDX")" = "$BEFORE" ]; then
        ok "R1 [$arg] код 2, индекс не тронут"
    else
        bad "R1 [$arg]" "код $rc, индекс изменён: $([ "$(cat "$IDX")" = "$BEFORE" ] && echo нет || echo да)"
    fi
done
run hooks/alpha.sh >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ] && [ "$(cat "$IDX")" = "$BEFORE" ]; then
    ok "R2 голый путь без режима — код 2, индекс не тронут"
else
    bad "R2" "код $rc, индекс изменён: $([ "$(cat "$IDX")" = "$BEFORE" ] && echo нет || echo да)"
fi
run --changed hooks/alpha.sh --лишний-флаг >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ] && [ "$(cat "$IDX")" = "$BEFORE" ]; then
    ok "R3 неизвестный флаг среди путей — код 2, индекс не тронут"
else
    bad "R3" "код $rc, индекс изменён: $([ "$(cat "$IDX")" = "$BEFORE" ] && echo нет || echo да)"
fi

# --- ПОЛ: известные режимы работают -----------------------------------------------------
OUT=$(run --check 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -q "устарел" <<< "$OUT"; then
    ok "R4 --check видит расхождение (код 1)"
else
    bad "R4" "код $rc, вывод: $OUT"
fi
OUT=$(run --impact hooks/alpha.sh 2>&1); rc=$?
if grep -q "docs/alpha.md" <<< "$OUT"; then
    ok "R5 --impact называет описывающий документ"
else
    bad "R5" "вывод: $OUT"
fi
BETA_BEFORE=$(grep '^hooks/beta\.sh	' "$IDX")
run --changed hooks/alpha.sh >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(grep '^hooks/beta\.sh	' "$IDX")" = "$BETA_BEFORE" ] \
   && grep -q '^hooks/alpha\.sh	.*alpha_two' "$IDX"; then
    ok "R6 адресный режим переписал свою строку и не тронул чужую"
else
    bad "R6" "код $rc, строка beta изменена: $([ "$(grep '^hooks/beta\.sh	' "$IDX")" = "$BETA_BEFORE" ] && echo нет || echo да)"
fi
printf '#!/usr/bin/env bash\nbeta_one() { :; }\nbeta_two() { :; }\n' > "$R/hooks/beta.sh"
run >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^hooks/beta\.sh	.*beta_two' "$IDX"; then
    ok "R7 без аргументов — полная пересборка, как было"
else
    bad "R7" "код $rc"
fi
OUT=$(run --check 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q "совпадает" <<< "$OUT"; then
    ok "R8 --check зелен после пересборки"
else
    bad "R8" "код $rc, вывод: $OUT"
fi

echo ""
echo "dep-index unknown-arg: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
