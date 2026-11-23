#!/usr/bin/env bash
# СУДИТ: hooks/lib/project_map.py scripts/dep-index.py scripts/project-graph.py
# test_project_map.sh — учёт и карта судят указанный проект по ЕГО описанию устройства (спецификация
#                       `.claude-docs/specs/2026-10-24-project-map-principle`, шаг 1б.1, D1067).
# Результат: `--repo <путь>` судит указанный проект из любого каталога; без описания действуют прежние правила
#            ClaudSoul, а карта проекта без каталога дашборда ложится в его `.claude-docs/`; описание сужает код до
#            объявленного; сломанное описание — отказ с кодом 2 и названной причиной, учёт не пишется.
# Проверка результата: bash hooks/tests/test_project_map.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
python3 "$REPO_ROOT/hooks/lib/project_map.py" "$TMP" >/dev/null 2>&1 && ok || bad M0 "самопроверка модуля не прошла"

mkproj() {  # mkproj <каталог> — чужой проект: без каталога дашборда, без копий инструментов
    local d="$1"; mkdir -p "$d/lib" "$d/tools" "$d/tests" "$d/.claude-docs"
    printf '#!/usr/bin/env bash\nsource tools/b.sh\n' > "$d/tools/a.sh"
    printf '#!/usr/bin/env bash\necho b\n'           > "$d/tools/b.sh"
    printf 'def f():\n    return 1\n'                > "$d/lib/m.py"
    printf '#!/usr/bin/env bash\nbash tools/a.sh\n'  > "$d/tests/test_a.sh"
    ( cd "$d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1
}
idx_paths() { grep -v '^#' "$1/.claude-docs/dep-index.tsv" 2>/dev/null | cut -f1 | tr '\n' ' '; }

# P1: без описания — прежние правила (код .sh/.py вне тестов), вызов из чужого каталога с `--repo`.
A="$TMP/a"; mkproj "$A"
( cd "$TMP" && python3 "$REPO_ROOT/scripts/dep-index.py" --repo "$A" --all >/dev/null 2>&1 )
GOT=$(idx_paths "$A")
[ "$GOT" = "lib/m.py tools/a.sh tools/b.sh " ] && ok || bad P1 "без описания учёт проекта: [${GOT}], ждали lib/m.py tools/a.sh tools/b.sh"
grep -q $'^tools/a.sh\t[^\t]*\ttools/b.sh' "$A/.claude-docs/dep-index.tsv" && ok \
    || bad P1b "зависимость tools/a.sh → tools/b.sh в учёте чужого проекта не записана"

# P2: карта проекта без каталога дашборда — в его .claude-docs/, вызов из чужого каталога.
( cd "$TMP" && python3 "$REPO_ROOT/scripts/project-graph.py" --repo "$A" --refresh >/dev/null 2>&1 )
[ -f "$A/.claude-docs/project-graph.json" ] && [ ! -e "$A/mcp-server" ] && ok \
    || bad P2 "карта чужого проекта не легла в .claude-docs/project-graph.json"
OUT=$( cd "$TMP" && PROJECT_GRAPH_NO_BUILD=1 python3 "$REPO_ROOT/scripts/project-graph.py" --repo "$A" --node tools/b.sh 2>&1 )
grep -q "tools/a.sh" <<< "$OUT" && ok || bad P2b "карта чужого проекта не знает, что tools/a.sh стоит на tools/b.sh: ${OUT:0:160}"

# P3: описание сужает код до объявленного.
B="$TMP/b"; mkproj "$B"
printf '{"code": [{"glob": "lib/**/*.py", "lang": "python"}]}\n' > "$B/.claude-docs/project-map.json"
( cd "$TMP" && python3 "$REPO_ROOT/scripts/dep-index.py" --repo "$B" --all >/dev/null 2>&1 )
GOT=$(idx_paths "$B")
[ "$GOT" = "lib/m.py " ] && ok || bad P3 "описание объявило код только lib/**/*.py, учёт взял [${GOT}]"

# P4: сломанное описание — отказ с кодом 2 и причиной, учёт не пишется.
C="$TMP/c"; mkproj "$C"
printf '{"code": [\n' > "$C/.claude-docs/project-map.json"
ERR=$( cd "$TMP" && python3 "$REPO_ROOT/scripts/dep-index.py" --repo "$C" --all 2>&1 ); RC=$?
WROTE=нет; [ -f "$C/.claude-docs/dep-index.tsv" ] && WROTE=записан
{ [ "$RC" -eq 2 ] && grep -qF "project-map.json" <<< "$ERR" && [ "$WROTE" = нет ]; } && ok \
    || bad P4 "сломанное описание: код ${RC}, вывод [${ERR:0:120}], учёт ${WROTE}"
# Код 2 сам по себе не различает: прежний прибор отвечал им же, но по иной причине — нога требует названную.
ERR=$( cd "$TMP" && python3 "$REPO_ROOT/scripts/project-graph.py" --repo "$C" --refresh 2>&1 ); RC=$?
{ [ "$RC" -eq 2 ] && grep -qF "project-map.json" <<< "$ERR"; } && ok \
    || bad P4b "карта на сломанном описании: код ${RC}, вывод [${ERR:0:120}] — ждали отказ 2 с именем описания"

# P5: `--repo` без пути — отказ с этой причиной, а не молча прежний корень.
ERR=$( python3 "$REPO_ROOT/scripts/dep-index.py" --repo 2>&1 ); RC=$?
{ [ "$RC" -eq 2 ] && grep -qF -- "--repo без пути" <<< "$ERR"; } && ok || bad P5 "«--repo» без пути: код ${RC}, вывод [${ERR:0:100}]"

# P6: запасной путь без модуля (песочницы копируют только учёт, на CI нет указателя и установки) даёт тот же учёт,
# что путь через модуль. Копия учёта лежит ВНЕ проекта, HOME подменён, CLAUDSOUL_ROOT снят — модуль недостижим.
# Сравниваются СТРОКИ учёта: отметка редакции правила в шапке (D1339) у двух путей разная по устройству — она хеш кода
# прибора вместе с модулем описания, а у запасного пути модуля нет.
same_rows() { cmp -s <(grep -v '^# правило ' "$1") <(grep -v '^# правило ' "$2"); }
E="$TMP/e"; mkproj "$E"; mkdir -p "$TMP/tool/scripts" "$TMP/fakehome"
( cd "$TMP" && python3 "$REPO_ROOT/scripts/dep-index.py" --repo "$E" --all >/dev/null 2>&1 )
cp "$E/.claude-docs/dep-index.tsv" "$TMP/via-module.tsv" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
cp "$REPO_ROOT/scripts/dep-index.py" "$TMP/tool/scripts/"
( cd "$E" && env -u CLAUDSOUL_ROOT HOME="$TMP/fakehome" CLAUDSOUL_REPO="$E" python3 "$TMP/tool/scripts/dep-index.py" --all >/dev/null 2>&1 ); RC=$?
if [ "$RC" -eq 0 ] && [ -s "$TMP/via-module.tsv" ] && same_rows "$TMP/via-module.tsv" "$E/.claude-docs/dep-index.tsv"; then ok
else bad P6 "запасной путь без модуля: код ${RC}, учёт $(same_rows "$TMP/via-module.tsv" "$E/.claude-docs/dep-index.tsv" && echo совпал || echo РАЗОШЁЛСЯ) с путём через модуль"; fi
printf '{}\n' > "$E/.claude-docs/project-map.json"
ERR=$( cd "$E" && env -u CLAUDSOUL_ROOT HOME="$TMP/fakehome" CLAUDSOUL_REPO="$E" python3 "$TMP/tool/scripts/dep-index.py" --all 2>&1 ); RC=$?
{ [ "$RC" -eq 2 ] && grep -qF "project_map.py не найден" <<< "$ERR"; } && ok \
    || bad P6b "описание есть, модуля нет: код ${RC}, вывод [${ERR:0:120}] — ждали громкий отказ, а не прежние правила молча"

# ── D1068: договор входной поверхности ─────────────────────────────────────────────────────────────────────
DG="$REPO_ROOT/scripts/dep-index.py"; PG="$REPO_ROOT/scripts/project-graph.py"
# F1: выходы инструментов не носители и не узлы карты.
F="$TMP/f1"; mkproj "$F"
( cd "$TMP" && python3 "$PG" --repo "$F" --refresh && python3 "$DG" --repo "$F" --all ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
OUT=$( cd "$TMP" && python3 "$DG" --repo "$F" --impact tools/b.sh 2>&1 )
NODE=$( cd "$TMP" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$F" --node .claude-docs/project-graph.json 2>&1 )
{ ! grep -q "project-graph.json" <<< "$OUT" && ! grep -q "^=== .claude-docs/project-graph.json" <<< "$NODE"; } && ok \
    || bad F1 "кэш карты — носитель или узел: impact [${OUT:0:120}], node [${NODE:0:80}]"
# F2: graph_out вне проекта, абсолютный, поверх отслеживаемого — отказ 2, ничего не записано.
for g in "../escaped.json" "$TMP/abs.json" "tools/a.sh"; do
    G="$TMP/f2$RANDOM"; mkproj "$G"; cp "$G/tools/a.sh" "$TMP/a.before"
    printf '{"graph_out": "%s"}\n' "$g" > "$G/.claude-docs/project-map.json"
    ( cd "$TMP" && python3 "$PG" --repo "$G" --refresh ) >/dev/null 2>&1; RC=$?
    { [ "$RC" -eq 2 ] && [ ! -e "$(dirname "$G")/escaped.json" ] && [ ! -e "$TMP/abs.json" ] && cmp -s "$TMP/a.before" "$G/tools/a.sh"; } \
        && ok || bad F2 "graph_out [${g}]: код ${RC}, запись вне проекта или поверх исходника"
done
# F3: проект без .claude-docs/ и без учёта — карта строится и читается (без учёта кэш несвеж, D1070 F4: чтение
# пересобирает, поэтому без PROJECT_GRAPH_NO_BUILD; прежняя редакция ноги держала «кэш годен всегда» — регрессию).
H="$TMP/f3"; mkdir -p "$H/x"; printf '#!/usr/bin/env bash\necho h\n' > "$H/x/h.sh"
( cd "$H" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1
( cd "$TMP" && python3 "$PG" --repo "$H" --refresh ) >/dev/null 2>&1; RC=$?
OUT=$( cd "$TMP" && python3 "$PG" --repo "$H" --node x/h.sh 2>&1 )
{ [ "$RC" -eq 0 ] && grep -q "^=== x/h.sh" <<< "$OUT"; } && ok || bad F3 "свежий проект: код ${RC}, ответ [${OUT:0:100}]"
# F4: `--repo=X` судит X; повтор флага — отказ 2 у обоих инструментов.
( cd "$TMP" && python3 "$PG" "--repo=$H" --refresh ) >/dev/null 2>&1; RC1=$?
( cd "$TMP" && python3 "$PG" --repo "$H" --repo "$F" --refresh ) >/dev/null 2>&1; RC2=$?
( cd "$TMP" && python3 "$DG" --repo "$H" --repo "$F" --all ) >/dev/null 2>&1; RC3=$?
{ [ "$RC1" -eq 0 ] && [ "$RC2" -eq 2 ] && [ "$RC3" -eq 2 ]; } && ok || bad F4 "--repo=X код ${RC1} (ждали 0), повтор: карта ${RC2}, учёт ${RC3} (ждали 2)"
# F5: поле не того типа, неизвестный ключ, неизвестный язык, пустой код — отказ 2 с причиной.
for js in '{"code":"**/*.sh"}' '{"code":["**/*.sh"]}' '{"ignore":null}' '{"tests":"tests/**"}' '{"test":["x/**"]}' \
          '{"code":[{"glob":"**/*.sh","lang":"bash"}]}' '{"code":[]}'; do
    K="$TMP/f5$RANDOM"; mkproj "$K"; printf '%s\n' "$js" > "$K/.claude-docs/project-map.json"
    ERR=$( cd "$TMP" && python3 "$DG" --repo "$K" --all 2>&1 ); RC=$?
    { [ "$RC" -eq 2 ] && grep -qF "project-map.json" <<< "$ERR"; } && ok || bad F5 "описание ${js}: код ${RC}, вывод [${ERR:0:100}]"
done
# F6: --repo на несуществующее, не-git, подкаталог — отказ 2, ничего не создано.
mkdir -p "$TMP/nongit"
for r in "$TMP/nope" "$TMP/nongit" "$A/lib"; do
    ( cd "$TMP" && python3 "$DG" --repo "$r" --all ) >/dev/null 2>&1; RC=$?
    { [ "$RC" -eq 2 ] && [ ! -e "$r/.claude-docs" ]; } && ok || bad F6 "--repo [${r}]: код ${RC} или создан .claude-docs"
done
# F7: правило «что тест» у карты — владельца: описанный тест spec/** — узел вида test.
S="$TMP/f7"; mkproj "$S"; mkdir -p "$S/spec"; printf '#!/usr/bin/env bash\nbash tools/a.sh\n' > "$S/spec/check.sh"
printf '{"tests": ["spec/**", "tests/**"]}\n' > "$S/.claude-docs/project-map.json"
( cd "$S" && git add -A && git -c user.email=t@t -c user.name=t commit -qm s ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
( cd "$TMP" && python3 "$DG" --repo "$S" --all && python3 "$PG" --repo "$S" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
OUT=$( cd "$TMP" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$S" --node spec/check.sh 2>&1 )
grep -q "^=== spec/check.sh (test)" <<< "$OUT" && ok || bad F7 "описанный тест spec/check.sh в карте не test: [${OUT:0:80}]"

# ── D1070: путь записи не выбирает описание, писатели не идут по ссылкам наружу ─────────────────────────────
TP="$(cd "$TMP" && pwd -P)"
# Брат корня: `.claude-docs` проекта — отслеживаемая ссылка наружу; учёт и карта не пишут туда.
mkdir -p "$TP/outside"; L="$TP/l1"; mkdir -p "$L/x"; printf '#!/usr/bin/env bash\necho l\n' > "$L/x/l.sh"; ln -s "$TP/outside" "$L/.claude-docs"
( cd "$L" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1
( cd "$TP" && python3 "$DG" --repo "$L" --all ) >/dev/null 2>&1; RC1=$?
( cd "$TP" && python3 "$PG" --repo "$L" --refresh ) >/dev/null 2>&1; RC2=$?
{ [ "$RC1" -eq 2 ] && [ "$RC2" -eq 2 ] && [ -z "$(ls -A "$TP/outside")" ]; } && ok \
    || bad L1 "ссылка .claude-docs наружу: учёт ${RC1}, карта ${RC2} (ждали 2), снаружи: [$(ls -A "$TP/outside" | tr '\n' ' ')]"
# F3: `--repo` через ссылку; абсолютные пути файлов той же формы — зависимый назван, строка пересчитана.
V="$TP/v1"; mkproj "$V"; ln -s "$V" "$TP/vlink"
( cd "$TP" && python3 "$DG" --repo "$TP/vlink" --all ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
printf '\necho changed\n' >> "$V/tools/b.sh"
OUT=$( cd "$TP" && python3 "$DG" --repo "$TP/vlink" --impact "$TP/vlink/tools/b.sh" 2>&1 )
( cd "$TP" && python3 "$DG" --repo "$TP/vlink" --changed "$TP/vlink/tools/b.sh" && python3 "$DG" --repo "$TP/vlink" --check ) >/dev/null 2>&1; RC=$?
{ grep -q "tools/a.sh" <<< "$OUT" && [ "$RC" -eq 0 ]; } && ok || bad F3 "--repo через ссылку: impact [${OUT:0:120}], --changed+--check код ${RC}"
# F4: без учёта кэш несвеж — новый файл виден после повторного вызова без --refresh.
W="$TP/w1"; mkdir -p "$W/x"; printf '#!/usr/bin/env bash\necho w\n' > "$W/x/w.sh"
( cd "$W" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
( cd "$TP" && python3 "$PG" --repo "$W" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
printf '#!/usr/bin/env bash\necho n\n' > "$W/x/n.sh"; ( cd "$W" && git add -A ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
OUT=$( cd "$TP" && python3 "$PG" --repo "$W" --node x/n.sh 2>&1 )
grep -q "^=== x/n.sh" <<< "$OUT" && ok || bad F4 "без учёта кэш не обновился: [${OUT:0:100}]"
# F6: --touch не вносит кэш карты (D1070); файл, которого ещё нет, вносит — хук зовёт --touch ДО создания (D1071, F1:
# прежняя редакция этой ноги закрепляла «призрак не заводится», и новые файлы перестали попадать в карту).
OUT1=$( cd "$W" && python3 "$PG" --repo "$W" --touch .claude-docs/project-graph.json 2>&1 )
OUT2=$( cd "$W" && python3 "$PG" --repo "$W" --touch x/future.sh 2>&1 )
GH=$(python3 -c 'import json,sys; g=json.load(open(sys.argv[1])); k={n["key"] for n in g["nodes"]}; print(int(".claude-docs/project-graph.json" in k), int("x/future.sh" in k))' "$W/.claude-docs/project-graph.json" 2>/dev/null)
{ [ "$GH" = "0 1" ] && grep -q "не тронута" <<< "$OUT1" && grep -q "в карте" <<< "$OUT2"; } && ok \
    || bad F6 "--touch: кэш/будущий файл в карте [${GH:-?}] (ждали 0 1); [${OUT1:0:60}] [${OUT2:0:60}]"
# F9: версия описания — только 1.
Y="$TP/y1"; mkproj "$Y"; printf '{"version": 2}\n' > "$Y/.claude-docs/project-map.json"
( cd "$TP" && python3 "$DG" --repo "$Y" --all ) >/dev/null 2>&1; [ $? -eq 2 ] && ok || bad F9 "описание version 2 не отбито"
# F10: описание объявило только tsjs, а файлов .ts нет — ноль механизмов назван причиной. С шага 1в tsjs разбирается, и
# причина — «образцы не нашли файлов», а не «язык вне разбора» (та ветка ждёт языка, известного и не разбираемого).
Z="$TP/z1"; mkproj "$Z"; printf '{"code": [{"glob": "**/*.ts", "lang": "tsjs"}]}\n' > "$Z/.claude-docs/project-map.json"
ERR=$( cd "$TP" && python3 "$DG" --repo "$Z" --all 2>&1 )
grep -q "образцы не нашли файлов" <<< "$ERR" && ok || bad F10 "ноль механизмов по описанию без причины: [${ERR:0:120}]"

# ── D1071 ───────────────────────────────────────────────────────────────────────────────────────────────────
# F2: путь через ссылку — относительная, реальная и ссылочная формы равно годны карте и учёту.
X="$TP/x1"; mkproj "$X"; ln -s "$X" "$TP/xlink"
( cd "$X" && python3 "$DG" --repo "$TP/xlink" --all && python3 "$PG" --repo "$TP/xlink" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
F2OK=1
for pth in tools/a.sh "$X/tools/a.sh" "$TP/xlink/tools/a.sh"; do
    O=$( cd "$X" && python3 "$PG" --repo "$TP/xlink" --touch "$pth" 2>&1 ); grep -q "в карте" <<< "$O" || { F2OK=0; bad F2 "--touch [${pth}] через --repo-ссылку: [${O:0:80}]"; }
    O=$( cd "$X" && python3 "$DG" --repo "$TP/xlink" --impact "$pth" 2>&1 ); grep -q "новые механизмы" <<< "$O" && { F2OK=0; bad F2b "--impact [${pth}]: путь не узнан"; }
done
[ "$F2OK" = 1 ] && ok
# F3/F4/F6: замок-ссылка, временный файл-ссылка, висячая ссылка .claude-docs — отказ 2, снаружи ничего.
mkdir -p "$TP/out3" "$TP/out4"; touch -t 202001010000 "$TP/out3"
Q="$TP/q3"; mkproj "$Q"; ln -s "$TP/out3" "$Q/.claude-docs/dep-index.tsv.lock"
( cd "$TP" && python3 "$DG" --repo "$Q" --all ) >/dev/null 2>&1; RC=$?
{ [ "$RC" -eq 2 ] && [ ! -e "$TP/out3/.break" ]; } && ok || bad F3 "замок-ссылка: код ${RC}, снаружи [$(ls -A "$TP/out3" | tr '\n' ' ')]"
# F4: временный файл учёта `<учёт>.tmp.<pid>` — ссылка наружу под точным именем (`exec` сохраняет PID оболочки).
Q4="$TP/q4"; mkproj "$Q4"
( cd "$TP" && bash -c 'ln -s "$1/x" "$2/.claude-docs/dep-index.tsv.tmp.$$"; exec python3 "$3" --repo "$2" --all' _ "$TP/out4" "$Q4" "$DG" ) >/dev/null 2>&1; RC=$?
{ [ "$RC" -eq 2 ] && [ ! -e "$TP/out4/x" ]; } && ok || bad F4 "временный файл-ссылка: код ${RC}, снаружи [$(ls -A "$TP/out4" | tr '\n' ' ')]"
U="$TP/u6"; mkdir -p "$U/x"; printf '#!/usr/bin/env bash\necho u\n' > "$U/x/u.sh"; ln -s "$TP/nowhere" "$U/.claude-docs"
( cd "$U" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1
ERR=$( cd "$TP" && python3 "$DG" --repo "$U" --all 2>&1 ); RC=$?
{ [ "$RC" -eq 2 ] && grep -q "висячая ссылка" <<< "$ERR"; } && ok || bad F6b "висячая .claude-docs: код ${RC}, [${ERR:0:100}]"
# F7: без учёта — ответ из кэша сразу после сборки; после git add нового файла кэш несвеж.
N7="$TP/n7"; mkdir -p "$N7/x"; printf '#!/usr/bin/env bash\necho n\n' > "$N7/x/n.sh"
( cd "$N7" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
( cd "$TP" && python3 "$PG" --repo "$N7" --refresh ) >/dev/null 2>&1
( cd "$TP" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$N7" --node x/n.sh ) >/dev/null 2>&1; RC1=$?
sleep 1; printf '#!/usr/bin/env bash\necho m\n' > "$N7/x/m.sh"; ( cd "$N7" && git add -A ) >/dev/null 2>&1
( cd "$TP" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$N7" --node x/m.sh ) >/dev/null 2>&1; RC2=$?
{ [ "$RC1" -eq 0 ] && [ "$RC2" -ne 0 ]; } && ok || bad F7 "без учёта: свежий кэш код ${RC1} (ждали 0), после git add ${RC2} (ждали «несвеж»)"
# F9: version 1.0 — отказ. F10: --touch каталога и .git/ — отказ, `..odd.sh` — в дереве.
Y2="$TP/y2"; mkproj "$Y2"; printf '{"version": 1.0}\n' > "$Y2/.claude-docs/project-map.json"
( cd "$TP" && python3 "$DG" --repo "$Y2" --all ) >/dev/null 2>&1; [ $? -eq 2 ] && ok || bad F9 "version 1.0 принят"
printf '#!/usr/bin/env bash\necho o\n' > "$N7/..odd.sh"
O1=$( cd "$N7" && python3 "$PG" --repo "$N7" --touch x 2>&1 ); O2=$( cd "$N7" && python3 "$PG" --repo "$N7" --touch .git/config 2>&1 )
O3=$( cd "$N7" && python3 "$PG" --repo "$N7" --touch ..odd.sh 2>&1 )
{ grep -q "не тронута" <<< "$O1" && grep -q "не тронута" <<< "$O2" && grep -q "в карте" <<< "$O3"; } && ok \
    || bad F10 "--touch: каталог [${O1:0:50}] .git [${O2:0:50}] ..odd.sh [${O3:0:50}]"

# ── Шаг 1б.2/1б.3 (D1067): рёбра к файлам-договорам по РАЗРЕШЁННОМУ пути, роль ребра, свежесть учёта ──────────────
# C1: каждая форма и роль своим файлом; отрицательные — голое имя, чужая переменная, хвост чужого пути, `.bak` (F1/F3/F8).
K="$TP/k"; mkdir -p "$K/hooks" "$K/data" "$K/we:ird" "$K/.claude-docs"
printf '{"version": 1, "repo_vars": ["REPO"], "contracts": ["BACKLOG.md", "data/*.tsv", "we:ird/*.json"]}\n' \
    > "$K/.claude-docs/project-map.json"
printf -- '- x\n' > "$K/BACKLOG.md"; printf 'a\n' > "$K/data/log.tsv"; printf 'a\n' > "$K/data/conf.tsv"
printf '{}\n' > "$K/we:ird/c.json"
printf '#!/usr/bin/env bash\ncat "$REPO/BACKLOG.md"\n'                                > "$K/hooks/rd.sh"
printf '#!/usr/bin/env bash\necho x >> "$REPO/data/log.tsv"\n'                         > "$K/hooks/wr.sh"
printf '#!/usr/bin/env bash\necho "правь $REPO/BACKLOG.md руками"\n'                    > "$K/hooks/say.sh"
printf '#!/usr/bin/env bash\ncase "$f" in data/log.tsv) exit 0 ;; esac\n'               > "$K/hooks/cs.sh"
printf '#!/usr/bin/env bash\ncat BACKLOG.md "$dir/BACKLOG.md" data/log.tsv.bak x/data/log.tsv\n' > "$K/hooks/no.sh"
printf 'import os\nREPO = "."\nopen(os.path.join(REPO, "data/conf.tsv")).read()\n'     > "$K/hooks/py.py"
printf '#!/usr/bin/env bash\nsource data/conf.tsv\n'                                   > "$K/hooks/src.sh"
printf '#!/usr/bin/env bash\ncat we:ird/c.json\n'                                      > "$K/hooks/colon.sh"
( cd "$K" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
( cd "$TP" && python3 "$DG" --repo "$K" --all && python3 "$PG" --repo "$K" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
csnap() { python3 - "$K/.claude-docs/project-graph.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1])); k = {n['id']: n['key'] for n in g['nodes']}
c = ('BACKLOG.md', 'data/log.tsv', 'data/conf.tsv', 'we:ird/c.json', 'data/new.tsv')
print('\n'.join(sorted(f"{k[e['source']]} {e['type']} {k[e['target']]}" for e in g['edges'] if k[e['target']] in c)))
PY
}
C1WANT=$'hooks/colon.sh читает we:ird/c.json\nhooks/cs.sh называет data/log.tsv\nhooks/py.py читает data/conf.tsv\nhooks/rd.sh читает BACKLOG.md\nhooks/say.sh называет BACKLOG.md\nhooks/src.sh читает data/conf.tsv\nhooks/wr.sh записывает data/log.tsv'
C1GOT=$(csnap)
[ "$C1GOT" = "$C1WANT" ] && ok || bad C1 "рёбра к договорам: [$(tr '\n' ';' <<< "$C1GOT")], ждали [$(tr '\n' ';' <<< "$C1WANT")]"
# C2: инкремент равен сборке — `--touch` каждого механизма оставляет рёбра к договорам теми же (D430, F7 двоеточие).
for f in rd wr say cs no src colon; do ( cd "$K" && python3 "$PG" --repo "$K" --touch "hooks/$f.sh" ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }; done
( cd "$K" && python3 "$PG" --repo "$K" --touch hooks/py.py ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
[ "$(csnap)" = "$C1WANT" ] && ok || bad C2 "после --touch рёбра к договорам разошлись со сборкой: [$(csnap | tr '\n' ';')]"
# C3: правка СОДЕРЖИМОГО договора рёбер не меняет — пересобирать нечего; описание изменилось — все строки.
printf -- '- y\n' >> "$K/BACKLOG.md"
S3=$( cd "$K" && python3 "$DG" --repo "$K" --stale-by BACKLOG.md 2>&1 )
[ -z "$S3" ] && ok || bad C3 "правка содержимого договора просит пересборки: [${S3}]"
# C3b: перечень — строки, которые правка РАЗВЕЛА с учётом (D1082), а не все: описание названо без правки — пусто; из
# договоров убран BACKLOG.md — его читатели.
S3b0=$( cd "$K" && python3 "$DG" --repo "$K" --stale-by .claude-docs/project-map.json 2>&1 )
cp "$K/.claude-docs/project-map.json" "$TP/k-desc.bak"
printf '{"version": 1, "repo_vars": ["REPO"], "contracts": ["data/*.tsv", "we:ird/*.json"]}\n' > "$K/.claude-docs/project-map.json"
S3b=$( cd "$K" && python3 "$DG" --repo "$K" --stale-by .claude-docs/project-map.json 2>&1 | tr '\n' ' ' )
cp "$TP/k-desc.bak" "$K/.claude-docs/project-map.json"
{ [ -z "$S3b0" ] && [ "$S3b" = "hooks/rd.sh hooks/say.sh " ]; } && ok \
    || bad C3b "правка описания: без правки [${S3b0}] (ждали пусто), договор снят [${S3b}] (ждали hooks/rd.sh hooks/say.sh)"
I3c=$( cd "$K" && python3 "$DG" --repo "$K" --impact .claude-docs/project-map.json 2>&1 )
{ grep -q "описание проекта изменено" <<< "$I3c" && ! grep -q "строки учёта устарели" <<< "$I3c"; } && ok \
    || bad C3c "правка описания названа устареванием всех строк, а не своим смыслом: [${I3c:0:120}]"
# C4: появился договор — его читатель назван владельцем (`--stale-by`, `--impact`), `--changed` сводит учёт с деревом.
printf '#!/usr/bin/env bash\ncat "$REPO/data/new.tsv"\n' > "$K/hooks/nw.sh"
( cd "$K" && git add -A && git -c user.email=t@t -c user.name=t commit -qm nw && python3 "$DG" --repo "$K" --all ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
printf 'n\n' > "$K/data/new.tsv"; ( cd "$K" && git add data/new.tsv ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
S4=$( cd "$K" && python3 "$DG" --repo "$K" --stale-by data/new.tsv 2>&1 )
I4=$( cd "$K" && python3 "$DG" --repo "$K" --impact data/new.tsv 2>&1 )
( cd "$K" && python3 "$DG" --repo "$K" --changed data/new.tsv && python3 "$DG" --repo "$K" --check ) >/dev/null 2>&1; R4=$?
{ [ "$S4" = hooks/nw.sh ] && grep -q "строки учёта устарели" <<< "$I4" && [ "$R4" -eq 0 ]; } && ok \
    || bad C4 "появился договор: --stale-by [${S4}], --impact [${I4:0:80}], --changed+--check код ${R4}"
# C5: удалён договор, учёт ещё не пересобран — узла-призрака в карте нет (F2); `--stale-by` называет читателей.
( cd "$K" && git rm -q data/conf.tsv && python3 "$PG" --repo "$K" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
S5=$( cd "$K" && python3 "$DG" --repo "$K" --stale-by data/conf.tsv 2>&1 | tr '\n' ' ' )
{ ! grep -q 'data/conf.tsv' <<< "$(csnap)" && [ "$S5" = "hooks/py.py hooks/src.sh " ]; } && ok \
    || bad C5 "удалён договор: рёбра [$(csnap | grep conf | tr '\n' ';')], --stale-by [${S5}]"
# C7: данные в каталоге тестов — договор (скептик 72d00022, F2); тестовый код — нет.
Y7="$TP/y7"; mkproj "$Y7"; printf 'a\tb\n' > "$Y7/tests/reg.tsv"
printf '#!/usr/bin/env bash\ncut -f1 "$REPO/tests/reg.tsv"\n' > "$Y7/tools/c.sh"
( cd "$Y7" && git add -A && git -c user.email=t@t -c user.name=t commit -qm c7 && python3 "$DG" --repo "$Y7" --all ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
grep -q $'^tools/c.sh\t[^\t]*\ttests/reg.tsv' "$Y7/.claude-docs/dep-index.tsv" && ok \
    || bad C7 "читатель реестра в каталоге тестов без ребра"
# C8: правка ТЕСТА сдвигает колонку `tests` другой строки — `--stale-by` её называет, `--impact` — устаревшей (F1).
printf '#!/usr/bin/env bash\nbash tools/a.sh\nbash tools/b.sh\n' > "$Y7/tests/test_a.sh"
S8=$( cd "$Y7" && python3 "$DG" --repo "$Y7" --stale-by tests/test_a.sh 2>&1 )
I8=$( cd "$Y7" && python3 "$DG" --repo "$Y7" --impact tests/test_a.sh 2>&1 )
{ [ "$S8" = tools/b.sh ] && grep -q "строки учёта устарели" <<< "$I8"; } && ok \
    || bad C8 "правка теста: --stale-by [${S8}], --impact [${I8:0:80}]"
# C9–C12 (D1076, скептик b4c40167): перечень `--stale-by` знает все входы строки учёта.
# C9: документ в каталоге тестов — документ (колонка docs): корпус судит его владелец, а не «лежит в tests/».
printf '## Связь с tools/b.sh\n' > "$Y7/tests/README.md"
S9=$( cd "$Y7" && python3 "$DG" --repo "$Y7" --stale-by tests/README.md 2>&1 )
[ "$S9" = tools/b.sh ] && ok || bad C9 "документ в каталоге тестов: --stale-by [${S9}], ждали tools/b.sh"
# C10: данные в каталоге тестов не входят ни в корпус тестов, ни в корпус документов — строк не сдвигают.
printf 'a\ttools/b.sh\n' > "$Y7/tests/reg.tsv"
S10=$( cd "$Y7" && python3 "$DG" --repo "$Y7" --stale-by tests/reg.tsv 2>&1 )
[ -z "$S10" ] && ok || bad C10 "правка реестра в каталоге тестов: --stale-by [${S10}], ждали пусто"
# C11: удалён механизм, у которого есть вызывающий, — строка вызывающего названа, учёт после пересборки свеж.
Y11="$TP/y11"; mkproj "$Y11"
( cd "$Y11" && python3 "$DG" --repo "$Y11" --all && git add -A && git -c user.email=t@t -c user.name=t commit -qm c11 \
  && git rm -q tools/b.sh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
S11=$( cd "$Y11" && python3 "$DG" --repo "$Y11" --stale-by tools/b.sh 2>&1 | tr '\n' ' ' )
# shellcheck disable=SC2086
{ [ "$S11" = "tools/a.sh tools/b.sh " ] && ( cd "$Y11" && python3 "$DG" --repo "$Y11" --changed $S11 \
  && python3 "$DG" --repo "$Y11" --check ) >/dev/null 2>&1; } && ok \
    || bad C11 "удалён механизм с вызывающим: --stale-by [${S11}], ждали tools/a.sh tools/b.sh и свежий учёт"
# C12: удалён двойник имени — голое `source b.sh` снова разрешается, строка сдвигается.
Y12="$TP/y12"; mkproj "$Y12"
printf '#!/usr/bin/env bash\nsource b.sh\n' > "$Y12/tools/c.sh"; printf '#!/usr/bin/env bash\n:\n' > "$Y12/lib/b.sh"
( cd "$Y12" && git add -A && python3 "$DG" --repo "$Y12" --all && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm c12 && git rm -q lib/b.sh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
S12=$( cd "$Y12" && python3 "$DG" --repo "$Y12" --stale-by lib/b.sh 2>&1 | tr '\n' ' ' )
# shellcheck disable=SC2086
( cd "$Y12" && python3 "$DG" --repo "$Y12" --changed $S12 && python3 "$DG" --repo "$Y12" --check ) >/dev/null 2>&1 \
    && ok || bad C12 "удалён двойник имени: --stale-by [${S12}], учёт после пересборки названных расходится с деревом"
# C13 (D1082, скептик sk3, А1): удалён один из ТРЁХ двойников — набор неоднозначных имён тот же, а состав другой: голое
# имя у оставшегося двойника снова разрешается в единственного соседа, и его строка сдвигается.
Y13="$TP/y13"; mkproj "$Y13"; mkdir -p "$Y13/t1" "$Y13/t2" "$Y13/t3"
printf '#!/usr/bin/env bash\necho "usage: x9.sh"\n' > "$Y13/t1/x9.sh"
printf '#!/usr/bin/env bash\necho 2\n' > "$Y13/t2/x9.sh"; printf '#!/usr/bin/env bash\necho 3\n' > "$Y13/t3/x9.sh"
( cd "$Y13" && git add -A && python3 "$DG" --repo "$Y13" --all && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm c13 && git rm -q t3/x9.sh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
S13=$( cd "$Y13" && python3 "$DG" --repo "$Y13" --stale-by t3/x9.sh 2>&1 | tr '\n' ' ' )
# shellcheck disable=SC2086
{ grep -q 't1/x9.sh' <<< "$S13" && ( cd "$Y13" && python3 "$DG" --repo "$Y13" --changed $S13 \
  && python3 "$DG" --repo "$Y13" --check ) >/dev/null 2>&1; } && ok \
    || bad C13 "удалён один из трёх двойников: --stale-by [${S13}], ждали t1/x9.sh и свежий учёт после пересборки"
# C14 (D1080): правка кода САМОГО правила в судимом дереве — вход каждой строки. Проект со своей копией прибора и модуля;
# правило меняет длину sha, то есть сдвигает все строки, — перечень называет и строки механизмов, а не только прибор.
Y14="$TP/y14"; mkproj "$Y14"; mkdir -p "$Y14/scripts" "$Y14/hooks/lib"
cp "$DG" "$Y14/scripts/dep-index.py"; cp "$REPO_ROOT/hooks/lib/project_map.py" "$Y14/hooks/lib/"
( cd "$Y14" && env -u CLAUDSOUL_REPO python3 scripts/dep-index.py --all && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm c14 ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
sed -i.bak 's/hexdigest()\[:12\]/hexdigest()[:10]/' "$Y14/scripts/dep-index.py"; rm -f "$Y14/scripts/dep-index.py.bak"
S14=$( cd "$Y14" && env -u CLAUDSOUL_REPO python3 scripts/dep-index.py --stale-by scripts/dep-index.py 2>&1 | tr '\n' ' ' )
# shellcheck disable=SC2086
{ grep -q 'tools/a.sh' <<< "$S14" && ( cd "$Y14" && env -u CLAUDSOUL_REPO python3 scripts/dep-index.py --changed $S14 \
  && env -u CLAUDSOUL_REPO python3 scripts/dep-index.py --check ) >/dev/null 2>&1; } && ok \
    || bad C14 "правка кода правила: --stale-by [${S14}], ждали и строки механизмов, и свежий учёт после пересборки"
# C6: `repo_vars` — голые имена; `$REPO` в описании — отказ 2 с причиной.
Y6="$TP/y6"; mkproj "$Y6"; printf '{"version": 1, "repo_vars": ["$REPO"]}\n' > "$Y6/.claude-docs/project-map.json"
E6=$( cd "$TP" && python3 "$DG" --repo "$Y6" --all 2>&1 ); R6=$?
{ [ "$R6" -eq 2 ] && grep -q "голые имена" <<< "$E6"; } && ok || bad C6 "repo_vars с \$: код ${R6}, [${E6:0:80}]"

# ── D1073: путь от корня — одно правило у учёта и карты, по файловой системе, а не по тексту ─────────────────────
# T1: относительный путь — от корня из любого каталога, у карты и учёта одинаково (прежде карта брала его от каталога
# вызова и из tools/ вносила призрак tools/tools/b.sh); на b.sh стоит tools/a.sh — учёт, узнавший путь, его называет.
V="$TP/v73"; mkproj "$V"
( cd "$V" && python3 "$DG" --repo "$V" --all && python3 "$PG" --repo "$V" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
O1=$( cd "$V/tools" && python3 "$PG" --repo "$V" --touch tools/b.sh 2>&1 ); I1=$( cd "$V/tools" && python3 "$DG" --repo "$V" --impact tools/b.sh 2>&1 )
{ grep -q "в карте: tools/b.sh " <<< "$O1" && grep -q "tools/a.sh" <<< "$I1"; } && ok \
    || bad T1 "из tools/ путь tools/b.sh: карта [${O1:0:60}], учёт [${I1:0:80}]"
# T4: нечувствительная к регистру система — `.GIT/`, кэш карты в ином регистре и `TOOLS/b.sh` те же файлы, что и
# в нижнем регистре. На чувствительной системе этих имён на диске нет — нога пропускается (предмета нет).
if [ -e "$V/.GIT" ]; then
    O4a=$( cd "$V" && python3 "$PG" --repo "$V" --touch .GIT/config 2>&1 )
    O4b=$( cd "$V" && python3 "$PG" --repo "$V" --touch .claude-docs/Project-Graph.json 2>&1 )
    O4c=$( cd "$V" && python3 "$PG" --repo "$V" --touch TOOLS/b.sh 2>&1 ); I4=$( cd "$V" && python3 "$DG" --repo "$V" --impact TOOLS/b.sh 2>&1 )
    { grep -q "не тронута" <<< "$O4a" && grep -q "не тронута" <<< "$O4b" && grep -q "в карте: tools/b.sh " <<< "$O4c" \
      && grep -q "tools/a.sh" <<< "$I4"; } && ok \
        || bad T4 "регистр: .GIT [${O4a:0:50}] Project-Graph [${O4b:0:50}] TOOLS/b.sh [${O4c:0:50}] учёт [${I4:0:60}]"
fi
# T2: `ссылка/..` решает файловая система — `lnk/..` это родитель цели ссылки, вне проекта. Ссылка заводится ПОСЛЕ ног
# учёта: до D1185 учёт читал ссылку на каталог как файл и звал отчёт неполным; порядок шагов остался.
mkdir -p "$TP/o73/x"; printf '#!/usr/bin/env bash\necho z\n' > "$TP/o73/x/z.sh"; ln -s "$TP/o73" "$V/lnk"
O2=$( cd "$V" && python3 "$PG" --repo "$V" --touch lnk/../x/z.sh 2>&1 )
grep -q "вне дерева" <<< "$O2" && ok || bad T2 "lnk/../x/z.sh: [${O2:0:80}] (ждали «вне дерева»)"
# T3: каталог, которого ещё нет, узлом не ложится.
O3=$( cd "$V" && python3 "$PG" --repo "$V" --touch newdir/ 2>&1 )
GK=$(python3 -c 'import json,sys; print(int("newdir" in {n["key"] for n in json.load(open(sys.argv[1]))["nodes"]}))' "$V/.claude-docs/project-graph.json" 2>/dev/null)
{ grep -q "не тронута" <<< "$O3" && [ "$GK" = 0 ]; } && ok || bad T3 "newdir/: [${O3:0:60}], узел newdir в карте: ${GK:-?}"
# Второй круг D1073 (финальный скептик 4ff7a114): имя, которое владелец ключей знает, — как есть; по диску — только
# незнакомое. T5: механизм в NFD на диске, git отдаёт NFC — учёт узнаёт имя git, карта не заводит второго узла (нога —
# только там, где git отдаёт NFC-имя).
V5="$TP/v5"; mkproj "$V5"; NFD=$(printf 'r\xc3\xa9sume\xcc\x81'); NFC=$(printf 'r\xc3\xa9sum\xc3\xa9')
printf '#!/usr/bin/env bash\necho r\n' > "$V5/tools/$NFD.sh"
( cd "$V5" && git add -A && git -c user.email=t@t -c user.name=t commit -qm n5 && python3 "$DG" --repo "$V5" --all \
  && python3 "$PG" --repo "$V5" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
if [ -n "$(git -C "$V5" ls-files "tools/$NFC.sh")" ]; then
    printf '#!/usr/bin/env bash\necho r2\n' > "$V5/tools/$NFD.sh"
    S5=$( cd "$V5" && python3 "$DG" --repo "$V5" --stale-by "tools/$NFC.sh" 2>&1 )
    ( cd "$V5" && python3 "$PG" --repo "$V5" --touch "tools/$NFC.sh" ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
    N5=$(python3 -c 'import json,sys; print(sum(n["key"].startswith("tools/r") for n in json.load(open(sys.argv[1]))["nodes"]))' "$V5/.claude-docs/project-graph.json" 2>/dev/null)
    { [ "$S5" = "tools/$NFC.sh" ] && [ "$N5" = 1 ]; } && ok || bad T5 "NFD на диске: --stale-by [${S5:0:60}], узлов tools/r*: ${N5:-?}"
    # T11 (четвёртый круг): NFD на диске × вход в NFD и в NFC × формы — ключ учёта всегда имя git (NFC); NFC-форму
    # входа сверяет `_known` (мутация без неё молчала у прежнего свидетеля).
    for f in "tools/$NFD.sh" "./tools/$NFD.sh" "$V5/tools/$NFD.sh" ".claude-docs/../tools/$NFD.sh" "./tools/$NFC.sh" "$V5/tools/$NFC.sh"; do
        S11=$( cd "$V5" && python3 "$DG" --repo "$V5" --stale-by "$f" 2>&1 )
        [ "$S11" = "tools/$NFC.sh" ] && ok || bad T11 "NFD на диске, вход [${f#"$TP"/}]: --stale-by [${S11:0:60}]"
    done
fi
# T6: переименование регистра `tools/b.sh` → `tools/B.sh` — перечень git называет оба имени, и удалённое учёт держит
# своим ключом: устаревшие строки и зависимые не теряются (прежде оба имени сводились к `tools/B.sh`).
V6="$TP/v6"; mkproj "$V6"; ( cd "$V6" && python3 "$DG" --repo "$V6" --all && git mv tools/b.sh tools/B.sh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
S6=$( cd "$V6" && python3 "$DG" --repo "$V6" --stale-by tools/B.sh tools/b.sh 2>&1 ); I6=$( cd "$V6" && python3 "$DG" --repo "$V6" --impact tools/b.sh 2>&1 )
{ grep -q "^tools/b.sh$" <<< "$S6" && grep -q "tools/a.sh" <<< "$I6"; } && ok \
    || bad T6 "переименование регистра: --stale-by [$(tr '\n' ' ' <<< "$S6")], --impact [${I6:0:80}]"
# T7–T9: `--node` знает путь в ином регистре (третий потребитель «путь → ключ»); `newdir/.` — каталог; замок кэша в ином
# регистре — не узел. T7 — только на нечувствительной к регистру системе.
if [ -e "$V/TOOLS" ]; then
    N7=$( cd "$V" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$V" --node TOOLS/b.sh --brief 2>&1 )
    grep -q "стоят" <<< "$N7" && ok || bad T7 "--node TOOLS/b.sh: [${N7:0:80}] (ждали карточку tools/b.sh)"
fi
O8=$( cd "$V" && python3 "$PG" --repo "$V" --touch newdir8/. 2>&1 ); O9=$( cd "$V" && python3 "$PG" --repo "$V" --touch .claude-docs/Project-Graph.json.LOCK 2>&1 )
{ grep -q "не тронута" <<< "$O8" && grep -q "не тронута" <<< "$O9"; } && ok \
    || bad T8 "newdir8/. [${O8:0:60}], замок в ином регистре [${O9:0:60}]"
# Третий круг D1073 (скептик adac200f): знакомое имя — в ЛЮБОЙ форме входа. T9 — произведение «класс × форма» у учёта и
# `--node`: класс — имя, удалённое переименованием регистра, и каталог, переехавший за ссылку совместимости `tools ->
# bin`; форма — относительная, `./`, абсолютная, абсолютная через иной псевдоним корня (`/var` ↔ `/private/var`, где
# он есть). Ждём имя git: `--stale-by` его называет, `--impact` — его зависимого, `--node` — его карточку. NFD × формы
# держит «Проверка» D1073 (там, где git отдаёт NFC-имя).
# Четвёртый круг (скептик 2f892efb): класс «удалён `git rm`» (`--node` переводит и путь, которого на диске нет) и форма
# `подкаталог/..` (звено `..` решает файловая система только до последнего `..`, хвост — текстом: L1).
for cls in case compat gone; do
    W="$TP/w9$cls"; mkproj "$W"
    ( cd "$W" && python3 "$DG" --repo "$W" --all && git add -A && git -c user.email=t@t -c user.name=t commit -qm idx \
      && python3 "$PG" --repo "$W" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
    case "$cls" in
        case) ( cd "$W" && git mv tools/b.sh tools/B.sh ) >/dev/null 2>&1 ;;
        compat) ( cd "$W" && git mv tools bin && ln -s bin tools && git add tools ) >/dev/null 2>&1 ;;
        gone) ( cd "$W" && git rm -q tools/b.sh ) >/dev/null 2>&1 ;;
    esac
    forms=("tools/b.sh" "./tools/b.sh" "$W/tools/b.sh" ".claude-docs/../tools/b.sh" "$W/lib/../tools/b.sh")
    [ "${W#/private}" != "$W" ] && forms+=("${W#/private}/tools/b.sh")
    for f in "${forms[@]}"; do
        S9=$( cd "$W" && python3 "$DG" --repo "$W" --stale-by "$f" 2>&1 ); I9=$( cd "$W" && python3 "$DG" --repo "$W" --impact "$f" 2>&1 )
        N9=$( cd "$W" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$W" --node "$f" --brief 2>&1 )
        { grep -q "^tools/b.sh$" <<< "$S9" && grep -q "tools/a.sh" <<< "$I9" && ! grep -q "новые механизмы" <<< "$I9" \
          && grep -q "стоят" <<< "$N9"; } && ok \
            || bad T9 "$cls × [${f#"$TP"/}]: --stale-by [$(tr '\n' ' ' <<< "$S9")], --impact [${I9:0:60}], --node [${N9:0:40}]"
    done
done
# T10: знакомый узел, чей каталог заменён ссылкой наружу, — не тот файл: `--touch` отказывает «вне дерева» (L-C).
W="$TP/w10"; mkproj "$W"; ( cd "$W" && python3 "$DG" --repo "$W" --all && python3 "$PG" --repo "$W" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
mkdir -p "$TP/o10"; printf '#!/usr/bin/env bash\nsource lib/m.py\n' > "$TP/o10/b.sh"; mv "$W/tools" "$TP/o10old"; ln -s "$TP/o10" "$W/tools"
O10=$( cd "$W" && python3 "$PG" --repo "$W" --touch tools/b.sh 2>&1 )
grep -q "вне дерева" <<< "$O10" && ok || bad T10 "каталог узла — ссылка наружу: [${O10:0:80}] (ждали «вне дерева»)"

# ── D1075: роль пути, присвоенного переменной, и читатели, чей путь правило не разрешает ──────────────────────────────
# Клетки — перечень из «Карты гарантий» пункта, каждая своим файлом; исполняются циклом на сборке и на `--touch` (R×, R0),
# читатели — на `--brief` и `--node` (U1–U7).
V="$TP/v1075"; mkdir -p "$V/hooks" "$V/data" "$V/tests" "$V/.claude-docs"
printf '{"version": 1, "repo_vars": ["REPO"], "contracts": ["BACKLOG.md", "data/*.tsv"]}\n' > "$V/.claude-docs/project-map.json"
printf -- '- x\n' > "$V/BACKLOG.md"; for t in w log quiet; do printf 'a\n' > "$V/data/$t.tsv"; done
vf() { local f="$1"; shift; printf '%s\n' "$@" > "$V/$f"; }
SH='#!/usr/bin/env bash'
vf hooks/r1.sh "$SH" 'N="$REPO/data/w.tsv"' 'echo x > "$N"' 'cat "$N"'   # запись не последней строкой
vf hooks/r7.sh "$SH" '[ -z "$E" ] && N="$REPO/data/w.tsv"' 'echo x > "$N"'
vf hooks/r2.sh "$SH" 'N="${E:-$REPO/data/w.tsv}"' 'printf x >> "$N"'
vf hooks/r3.sh "$SH" 'if [ -n "$E" ]; then N="$E"; else N="$REPO/data/w.tsv"; fi' 'echo x | tee "$N"'
vf hooks/r4.sh "$SH" 'f() {' '    local N="$REPO/data/w.tsv"' '    sed e "$N" > "$t" && mv "$t" "$N"' '}'
vf hooks/r5.sh "$SH" 'export N=$REPO/data/w.tsv' 'cp "$t" "$N"'
vf hooks/p1.py 'import os' 'REPO = "."' 'N = os.path.join(REPO, "data/w.tsv")' "open(N, 'w').write('x')"
vf hooks/p2.py 'import pathlib' 'REPO = pathlib.Path(".")' 'N = REPO / "data/w.tsv"' 'N.write_text("x")'
vf hooks/p3.py 'import os' 'REPO = "."' 'N = f"{REPO}/data/w.tsv"' 'os.replace("t", N)'
vf hooks/r6.sh "$SH" 'N="$REPO/data/w.tsv"' 'if true; then mv "$t" "$N"; fi'
vf hooks/p4.py 'import os' 'REPO = "."' 'N = os.path.join(REPO, "data/w.tsv")' 'print(f"правь {N}")' 'cfg.N.write_text("x")'
vf hooks/n1.sh "$SH" 'N="$REPO/data/w.tsv"' 'cat "$N"'
vf hooks/n2.sh "$SH" 'N="$REPO/data/w.tsv"' 'echo "правь $N руками"'
vf hooks/n3.sh "$SH" 'N="$REPO/data/w.tsv"' 'python3 tool.py "$N"'
vf hooks/n4.sh "$SH" 'N="$REPO/data/w.tsv"' 'echo x > "${N%/*}/other.tsv"'
vf hooks/n5.sh "$SH" 'N="$REPO/data/w.tsv"' 'echo x > "$NX"'
vf hooks/n6.py "REG = {'data/w.tsv': 'метка'}" 'print(len(REG))'
vf hooks/s1.py 'import os' 'REPO = "."' "t = open(os.path.join(REPO, 'data', 'w.tsv')).read()"
vf hooks/s2.py 'import pathlib' "REPO = pathlib.Path('.')" "t = (REPO / 'data' / 'w.tsv').read_text()"
# Второй круг D1075 (скептик 04481f5a): H1 — источник `cp`/`install`/`shutil.copy` с флагом — чтение; M1 — производный
# путь (`$N.lock`, `N + ".lock"`) — не использование; M2 — `path = INDEX` в Python — не сравнение; M3 — именованный
# аргумент на строке продолжения вызова — не присваивание; L3 — присваивание в ветке `case`, в `{ …; }`, `${N:=…}`,
# `${N:?}`, `abspath(`/`str(`, `.open("w")`, `sed -i` — запись; `info=` — не сообщение.
vf hooks/h1.sh "$SH" 'N="$REPO/data/w.tsv"' 'S=$(mktemp)' 'cp -f "$N" "$S"' 'wc -l < "$S"'
vf hooks/h2.sh "$SH" 'N="$REPO/data/w.tsv"' 'install -m 644 "$N" "$DEST/w.tsv"'
vf hooks/h3.sh "$SH" '[ -d "$S" ] && cp -f "$REPO/data/w.tsv" "$S/"'
vf hooks/h4.sh "$SH" 'N="$REPO/data/w.tsv"' 'cp -- "$N" "$OUT"'
vf hooks/h5.py 'import os, shutil' 'REPO = "."' 'N = os.path.join(REPO, "data/w.tsv")' 'shutil.copy(N, "/tmp/snap")'
vf hooks/d1.sh "$SH" 'N="$REPO/data/w.tsv"' 'cp "$N" "$N.bak"'
vf hooks/d2.sh "$SH" 'N="$REPO/data/w.tsv"' 'exec 9>"$N.lock"' 'cat "$N"'
vf hooks/d3.sh "$SH" 'N="$REPO/data/w.tsv"' 'sort "$N" > "$N.sorted"' 'diff "$N" "$N.sorted"'
vf hooks/d4.py 'import os' 'REPO = "."' 'N = os.path.join(REPO, "data/w.tsv")' 'lock = open(N + ".lock", "w")' 'data = open(N).read()'
vf hooks/k1.py 'import os' 'REPO = "."' 'x = load(' '    path=os.path.join(REPO, "data/w.tsv"))' 'path = "/tmp/out"' 'open(path, "w").write("x")'
vf hooks/k2.py 'import os' 'REPO = "."' 'INDEX = os.path.join(REPO, "data/w.tsv")' 'path = INDEX' 'rows = open(path).read().split()'
vf hooks/k3.py 'import os' 'REPO = "."' 'INDEX = os.path.join(REPO, "data/w.tsv")' 'def load(path: str = INDEX):' '    return open(path).read()'
vf hooks/w1.sh "$SH" 'case "$1" in' '  --x) N="$REPO/data/w.tsv" ;;' 'esac' 'echo x > "$N"'
vf hooks/w2.sh "$SH" '[ -n "$E" ] || { N="$REPO/data/w.tsv"; }' 'echo x > "$N"'
vf hooks/w3.sh "$SH" ': "${N:=$REPO/data/w.tsv}"' 'echo x > "$N"'
vf hooks/w4.sh "$SH" 'N="$REPO/data/w.tsv"' 'echo x > "${N:?}"'
vf hooks/w5.py 'import os' 'REPO = "."' 'N = os.path.abspath(os.path.join(REPO, "data/w.tsv"))' 'open(N, "w").write("x")'
vf hooks/w6.py 'import os' 'REPO = "."' 'N = str(os.path.join(REPO, "data/w.tsv"))' 'open(N, "w").write("x")'
vf hooks/w7.py 'import pathlib' 'REPO = pathlib.Path(".")' 'N = REPO / "data/w.tsv"' 'with N.open("w") as f:' '    f.write("x")'
vf hooks/w8.sh "$SH" 'N="$REPO/data/w.tsv"' 'sed -i.bak "s/a/b/" "$N"'
vf hooks/q1.sh "$SH" 'N="$REPO/data/w.tsv"' 'info=$(stat "$N")'
vf hooks/q2.py 'import os, shutil' 'REPO = "."' 'N = os.path.join(REPO, "data/w.tsv")' 'shutil.copy("a", "b"); rows = open(N).read()'
vf hooks/q3.py 'import os' 'REPO = "."' 'x = "("' 'N = os.path.join(REPO, "data/w.tsv")' 'open(N, "w").write("x")'
vf hooks/q4.sh "$SH" 'N="$REPO/data/w.tsv"' 'cp "$t" "$N" 2>/dev/null'
# Клетки мутантов скептика 04481f5a (L2), свидетель до них их не ловил: разделитель перед `cat`, `(` перед `cp`,
# `local -r`, `readonly`, `${E-` без двоеточия, аннотация Python, «все места — имя», `"…"::`, `||` перед
# присваиванием, `else mv`.
vf hooks/g1.sh "$SH" 'N="$REPO/data/w.tsv"' 'cp "$t" "$S"; cat "$N"'
vf hooks/g2.sh "$SH" 'N="$REPO/data/w.tsv"' '( cp "$t" "$N" )'
vf hooks/g3.sh "$SH" 'f() {' '    local -r N="$REPO/data/w.tsv"' '    echo x > "$N"' '}'
vf hooks/g4.sh "$SH" 'readonly N="$REPO/data/w.tsv"' 'echo x > "$N"'
vf hooks/g5.sh "$SH" 'N="${E-$REPO/data/w.tsv}"' 'echo x > "$N"'
vf hooks/g6.py 'import os' 'REPO = "."' 'N: str = os.path.join(REPO, "data/w.tsv")' 'open(N, "w").write("x")'
vf hooks/g7.sh "$SH" 'N="$REPO/data/w.tsv"' 'echo "правь $N руками"' 'cat "$N"'
vf hooks/g8.sh "$SH" 'rsync -a "$REPO/data/w.tsv"::backup'
vf hooks/g9.sh "$SH" '[ -n "$E" ] || N="$REPO/data/w.tsv"' 'echo x > "$N"'
vf hooks/ga.sh "$SH" 'N="$REPO/data/w.tsv"' 'if false; then :; else mv "$t" "$N"; fi'
# Оговорка карточки (L2): докстринг `.py` — не читатель; ровно три читателя без пути — без многоточия; имя файла не в
# ASCII — читатель назван.
vf hooks/u7.py '"""Reads BACKLOG.md of the project."""' 'import sys' 'print(1)'
printf 'a\n' > "$V/data/three.tsv"
vf hooks/y1.sh "$SH" 'cat "$X/data/three.tsv"'
vf hooks/y2.sh "$SH" 'cat "$X/data/three.tsv"'
vf "hooks/я3.sh" "$SH" 'cat "$X/data/three.tsv"'
vf hooks/u1.sh "$SH" 'f="$1"' 'cat "${f%/*}/BACKLOG.md"'
vf hooks/u2.sh "$SH" 'cat "$OTHER/BACKLOG.md"'
vf hooks/u3.sh "$SH" 'for x in BACKLOG.md README.md; do :; done'
vf hooks/u4.py 'import os, sys' 'p = sys.argv[1]' 'open(os.path.join(os.path.dirname(p), "BACKLOG.md"))'
vf hooks/u5.sh "$SH" 'cat "$CWD/data/log.tsv"'
vf hooks/x1.sh "$SH" '# BACKLOG.md — только в комментарии' 'true'
vf hooks/x2.sh "$SH" 'cat BACKLOG.md.bak XBACKLOG.md'
vf hooks/e1.sh "$SH" 'cat "$REPO/BACKLOG.md"' 'echo BACKLOG.md'
vf tests/test_x.sh "$SH" 'cat "$OTHER/BACKLOG.md"'
mkdir -p "$V/tools"; vf tools/r1.sh "$SH" 'true'; vf hooks/x3.sh "$SH" 'bash r1.sh'   # имя двух механизмов — ребра нет
( cd "$V" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
( cd "$TP" && python3 "$DG" --repo "$V" --all && python3 "$PG" --repo "$V" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }
vsnap() { python3 - "$V/.claude-docs/project-graph.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1])); k = {n['id']: n['key'] for n in g['nodes']}
print('\n'.join(sorted(f"{k[e['source']]} {e['type']}" for e in g['edges'] if k[e['target']] == 'data/w.tsv')))
PY
}
CELLS=("r1.sh записывает" "r2.sh записывает" "r3.sh записывает" "r4.sh записывает" "r5.sh записывает" "r6.sh записывает" "r7.sh записывает" "p4.py называет"
       "p1.py записывает" "p2.py записывает" "p3.py записывает" "n1.sh читает" "n2.sh называет" "n3.sh читает"
       "n4.sh читает" "n5.sh читает" "n6.py называет" "s1.py читает" "s2.py читает"
       "h1.sh читает" "h2.sh читает" "h3.sh читает" "h4.sh читает" "h5.py читает" "d1.sh читает" "d2.sh читает"
       "d3.sh читает" "d4.py читает" "k1.py читает" "k2.py читает" "k3.py читает" "w1.sh записывает" "w2.sh записывает"
       "w3.sh записывает" "w4.sh записывает" "w5.py записывает" "w6.py записывает" "w7.py записывает"
       "w8.sh записывает" "q1.sh читает" "q2.py читает" "q3.py записывает" "q4.sh записывает"
       "g1.sh читает" "g2.sh записывает" "g3.sh записывает" "g4.sh записывает" "g5.sh записывает" "g6.py записывает"
       "g7.sh читает" "g8.sh читает" "g9.sh записывает" "ga.sh записывает")
for when in сборка touch; do
    if [ "$when" = touch ]; then
        for c in "${CELLS[@]}"; do ( cd "$V" && python3 "$PG" --repo "$V" --touch "hooks/${c%% *}" ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map.sh:$LINENO" >&2; exit 1; }; done
    fi
    VS=$(vsnap)
    for c in "${CELLS[@]}"; do
        grep -qx "hooks/$c" <<< "$VS" && ok || bad "R×$when" "клетка [$c]: рёбра к data/w.tsv [$(tr '\n' ';' <<< "$VS")]"
    done
    [ "$(grep -c . <<< "$VS")" = "${#CELLS[@]}" ] && ok || bad "R0×$when" "лишние рёбра к data/w.tsv: [$(tr '\n' ';' <<< "$VS")]"
done
BR=$( cd "$V" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$V" --node BACKLOG.md --brief 2>&1 )
ND=$( cd "$V" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$V" --node BACKLOG.md 2>&1 )
grep -q "имя называют ещё 4 без пути" <<< "$BR" && grep -q "u1.sh, u2.sh, u3.sh…" <<< "$BR" && grep -q "на нём стоят 1:" <<< "$BR" && ok \
    || bad U1 "карточка BACKLOG.md не называет 4 читателя без разрешённого пути: [${BR}]"
SEC=$(sed -n '/^ИМЯ НАЗЫВАЮТ/,/^ОН СТОИТ/p' <<< "$ND")
for f in u1.sh u2.sh u3.sh u4.py; do
    grep -qx "  hooks/$f" <<< "$SEC" && ok || bad "U2×$f" "полная карточка не называет $f: [${ND}]"
done
for f in hooks/x1.sh hooks/x2.sh tests/test_x.sh hooks/e1.sh hooks/u7.py; do
    grep -q "$f" <<< "$SEC" && bad "U3×$f" "оговорка называет $f (комментарий, хвост, тест, ребро): [${ND}]" || ok
done
BL=$( cd "$V" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$V" --node data/log.tsv --brief 2>&1 )
grep -q "на нём не стоит никто по разрешённому пути | сам стоит на 0 | имя называют ещё 1 без пути.*u5.sh" <<< "$BL" && ok \
    || bad U4 "договор только с неразрешёнными читателями назван «не стоит никто» без оговорки: [${BL}]"
BQ=$( cd "$V" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$V" --node data/quiet.tsv --brief 2>&1 )
[ "$BQ" = "на нём не стоит никто | сам стоит на 0" ] && ok || bad U5 "карточка договора, чьё имя никто не называет, изменилась: [${BQ}]"
B3=$( cd "$V" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$V" --node data/three.tsv --brief 2>&1 )
grep -q "имя называют ещё 3 без пути" <<< "$B3" && grep -q "я3.sh" <<< "$B3" && ! grep -q "…" <<< "$B3" && ok \
    || bad U8 "ровно три читателя без пути (один с именем не в ASCII) названы не все или с многоточием: [${B3}]"
B7=$( cd "$V" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$V" --node hooks/r1.sh --brief 2>&1 )
grep -q "имя называют" <<< "$B7" && bad U7 "оговорка у карточки механизма, а не договора: [${B7}]" || ok
vf hooks/u6.sh "$SH" 'cat "$OTHER/BACKLOG.md"'   # не под учётом git — карта его тоже знает (`tracked_files`)
N6=$( cd "$V" && PROJECT_GRAPH_NO_BUILD=1 python3 "$PG" --repo "$V" --node BACKLOG.md 2>&1 )
SEC6=$(sed -n '/^ИМЯ НАЗЫВАЮТ/,/^ОН СТОИТ/p' <<< "$N6")
grep -qx "  hooks/u6.sh" <<< "$SEC6" && ok || bad U6 "неотслеживаемый читатель не назван: [${N6}]"

echo "test_project_map: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
