#!/usr/bin/env bash
# test_project_graph.sh — свидетель карты связей: рёбра по РОЛИ, а не по виду текста.
# Предмет: имя, определённое в нескольких файлах, ребра не даёт; присваивание вызовом не
# считается; настоящий вызов ребро даёт (положительный контроль к обоим); `--scc` отличает
# дерево со спайкой от дерева без неё; ответ берётся из кэша, а устаревший кэш при запрете
# сборки отвечает кодом 3, а не минутной пересборкой.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
TOOL="$REPO_ROOT/scripts/project-graph.py"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

mkrepo() {  # mkrepo <каталог> — дерево-песочница с учётом
    local d="$1"; mkdir -p "$d/scripts" "$d/hooks" "$d/.claude-docs" "$d/mcp-server/visualization"
    ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t )
    cp "$TOOL" "$d/scripts/"
}
run() {  # run <репо> [флаги…]
    ( cd "$1" && shift; LESSONS_DIR="$TMP/lessons" CLAUDSOUL_REPO="$PWD" python3 scripts/project-graph.py "$@" 2>&1 )
}
mkdir -p "$TMP/lessons"

# ── дерево A: одно имя у ДВУХ владельцев, третий файл его зовёт ────────────────
A="$TMP/a"; mkrepo "$A"
printf '#!/usr/bin/env bash\nhelper_common() { echo 1; }\n' > "$A/hooks/one.sh"
printf '#!/usr/bin/env bash\nhelper_common() { echo 2; }\n' > "$A/hooks/two.sh"
printf '#!/usr/bin/env bash\nhelper_common\n' > "$A/hooks/caller.sh"
# и рядом ЧЕСТНОЕ имя с одним владельцем — положительный контроль
printf '#!/usr/bin/env bash\nsolo_helper() { echo 3; }\n' > "$A/hooks/solo.sh"
printf '#!/usr/bin/env bash\nsolo_helper\n' >> "$A/hooks/caller.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/one.sh\ta\t\t\t\thelper_common\n'
  printf 'hooks/two.sh\tb\t\t\t\thelper_common\n'
  printf 'hooks/solo.sh\tc\t\t\t\tsolo_helper\n'
  printf 'hooks/caller.sh\td\t\t\t\t\n'; } > "$A/.claude-docs/dep-index.tsv"
( cd "$A" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )

OUT_A=$(run "$A" --node hooks/caller.sh)
if grep -qF "solo_helper" <<< "$OUT_A"; then ok
else bad T1 "имя с ОДНИМ владельцем не дало ребра — контроль пуст, T2 нечем проверять"; fi
if grep -qF "helper_common" <<< "$OUT_A"; then
  bad T2 "имя с двумя владельцами дало ребро: $(grep -o 'helper_common' <<< "$OUT_A" | head -1)"
else ok; fi
if grep -qF "имён без владельца" <<< "$(run "$A" --check)"; then ok
else bad T3 "отброшенные имена не названы числом — молчаливая потеря"; fi

# ── дерево B: присваивание против вызова ──────────────────────────────────────
B="$TMP/b"; mkrepo "$B"
printf '#!/usr/bin/env bash\nfetch_stats() { echo s; }\n' > "$B/hooks/lib.sh"
printf '#!/usr/bin/env bash\nfetch_stats=$(echo 1)\n' > "$B/hooks/assign.sh"
printf '#!/usr/bin/env bash\nfetch_stats\n'          > "$B/hooks/call.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/lib.sh\ta\t\t\t\tfetch_stats\n'
  printf 'hooks/assign.sh\tb\t\t\t\t\n'
  printf 'hooks/call.sh\tc\t\t\t\t\n'; } > "$B/.claude-docs/dep-index.tsv"
( cd "$B" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )

if grep -qF "fetch_stats" <<< "$(run "$B" --node hooks/call.sh)"; then ok
else bad T4 "настоящий вызов ребра не дал — контроль к T5 пуст"; fi
if grep -qF "fetch_stats" <<< "$(run "$B" --node hooks/assign.sh)"; then
  bad T5 "присваивание засчитано вызовом"
else ok; fi

# ── дерево C: спайка есть и спайки нет ────────────────────────────────────────
C="$TMP/c"; mkrepo "$C"
printf '#!/usr/bin/env bash\nbash hooks/y.sh\n' > "$C/hooks/x.sh"
printf '#!/usr/bin/env bash\nbash hooks/x.sh\n' > "$C/hooks/y.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/x.sh\ta\thooks/y.sh\t\t\t\n'
  printf 'hooks/y.sh\tb\thooks/x.sh\t\t\t\n'; } > "$C/.claude-docs/dep-index.tsv"
( cd "$C" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
run "$C" --scc >/dev/null 2>&1; RC_C=$?
[ "$RC_C" = "1" ] && ok || bad T6 "взаимная пара не признана спайкой (код $RC_C)"

D="$TMP/d"; mkrepo "$D"
printf '#!/usr/bin/env bash\necho one\n' > "$D/hooks/z.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/z.sh\ta\t\t\t\t\n'; } > "$D/.claude-docs/dep-index.tsv"
( cd "$D" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
OUT_D=$(run "$D" --scc); RC_D=$?
if [ "$RC_D" = "0" ] && grep -qF "спаек (кусков, где всё достижимо из всего): 0" <<< "$OUT_D"; then ok
else bad T7 "дерево без взаимных ссылок не даёт «спаек: 0» (код $RC_D)"; fi

# ── кэш: запрет сборки при устаревшем кэше отвечает кодом 3 ───────────────────
touch -t 200001010000 "$A/mcp-server/visualization/project-graph-data.json" 2>/dev/null
( cd "$A" && PROJECT_GRAPH_NO_BUILD=1 LESSONS_DIR="$TMP/lessons" CLAUDSOUL_REPO="$A" \
    python3 scripts/project-graph.py --node hooks/caller.sh >/dev/null 2>&1 ); RC_S=$?
[ "$RC_S" = "3" ] && ok || bad T8 "устаревший кэш при запрете сборки дал код $RC_S вместо 3"

# ── T9-T12: РОЛЬ РЕБРА ЗАВИСИМОСТИ. Учёт знает ЧТО от чего зависит и не знает КАК;
# карте различие нужно, потому что рекурсию даёт только ИСПОЛНЕНИЕ. Замер 14 сентября 2026
# (D406): спайка по сырым «вызовам» — 45 узлов, после разведения четырёх ролей — НОЛЬ.
R="$TMP/roles"; mkrepo "$R"
printf '#!/usr/bin/env bash\necho lib\n' > "$R/hooks/lib.sh"
printf '#!/usr/bin/env bash\nsource hooks/lib.sh\n'                        > "$R/hooks/calls.sh"
printf '#!/usr/bin/env bash\ngrep -c . hooks/lib.sh\n'                     > "$R/hooks/reads.sh"
printf '#!/usr/bin/env bash\nprintf "запусти hooks/lib.sh руками\\n"\n'   > "$R/hooks/says.sh"
printf '#!/usr/bin/env bash\nMSG="смотри hooks/lib.sh за подробностями"\necho "$MSG"\n' > "$R/hooks/const.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'
  printf 'hooks/lib.sh\ta\t\t\t\t\n'
  printf 'hooks/calls.sh\tb\thooks/lib.sh\t\t\t\n'
  printf 'hooks/reads.sh\tc\thooks/lib.sh\t\t\t\n'
  printf 'hooks/says.sh\td\thooks/lib.sh\t\t\t\n'
  printf 'hooks/const.sh\te\thooks/lib.sh\t\t\t\n'; } > "$R/.claude-docs/dep-index.tsv"
( cd "$R" && git add -A >/dev/null 2>&1 && git commit -qm i >/dev/null 2>&1 )
# Роль берётся БЕЗ диапазона букв: GNU grep отвергает `[а-яё]` в локали C.UTF-8
# («Invalid collation character»), и на раннере CI эта нога молча теряла вывод — четыре
# ноги краснели с пустым сообщением (прогон 34872897131, 14 сентября 2026). Класс назван
# в pattern-shell-portability; отрицание `[^-]` диапазона не содержит и переносимо.
role() { run "$R" --node "$1" 2>/dev/null | grep -oE -- '--[^-]+-->' | head -1 | tr -d '>-'; }
[ "$(role hooks/calls.sh)" = "зовёт" ] && ok || bad T9  "source не признан вызовом: $(role hooks/calls.sh)"
[ "$(role hooks/reads.sh)" = "читает" ] && ok || bad T10 "чтение файла признано вызовом: $(role hooks/reads.sh)"
[ "$(role hooks/says.sh)"  = "называет" ] && ok || bad T11 "имя в сообщении признано вызовом: $(role hooks/says.sh)"
[ "$(role hooks/const.sh)" = "называет" ] && ok || bad T12 "имя в строковой константе признано вызовом: $(role hooks/const.sh)"

echo "test_project_graph: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
