#!/usr/bin/env bash
# СУДИТ: hooks/impact-inject.sh hooks/doc-impact-check.sh scripts/project-graph.py scripts/dep-index.py hooks/lib/project_map.py
# test_project_map_any_project.sh — подсказка перед правкой и хук коммита в ЛЮБОМ проекте с описанием (спецификация
#                       `.claude-docs/specs/2026-10-24-project-map-principle`, шаг 1г, D1089).
# Результат: в проекте с `.claude-docs/project-map.json` подсказка зовёт прибор ClaudSoul с `--repo` и отвечает тремя
#            ответами — «на нём стоят N» (зависимые `.ts` по импорту), «на нём не стоит никто», «карта этого вида не
#            знает»; хук коммита пересобирает учёт прибором ClaudSoul; проект без описания — тишина. Ни хуки, ни приборы
#            не исполняют ничего из проекта: подложенные `scripts/*.py` и программы из настроек git (fsmonitor, внешний
#            diff, textconv, фильтр содержимого) не запускаются. Строки про `run_all.sh` и пересчёт чисел — только в ClaudSoul.
# Проверка результата: bash hooks/tests/test_project_map_any_project.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
REPO_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
unset CLAUDSOUL_REPO CLAUDSOUL_ROOT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
has()   { if grep -qF -- "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в '${1:0:300}'"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$1"; then bad "$3" "не ждали '$2' в '${1:0:300}'"; else ok; fi; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TP="$(cd "$TMP" && pwd -P)"
DG="$REPO_ROOT/scripts/dep-index.py"; PG="$REPO_ROOT/scripts/project-graph.py"
gc() { git -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$TP/lessons" "$TP/evil"
export LESSONS_DIR="$TP/lessons"

# Метки исполнения: каждая подложенная программа пишет файл в каталог, названный ей окружением MARKDIR, — у каждой
# ноги свой каталог, удалять ничего не нужно.
# Фильтр и textconv пропускают содержимое как есть: иначе `git add` самой рамки положил бы в индекс пустой файл.
evil() { printf '#!/bin/sh\n[ -n "$MARKDIR" ] && touch "$MARKDIR/%s"\n%s\n' "$1" "$2" > "$TP/evil/$1.sh"; chmod +x "$TP/evil/$1.sh"; }
evil fsmonitor 'exit 0'; evil ext-diff 'exit 0'; evil textconv 'cat "$1"'; evil clean 'cat'

plant_py() { printf 'import os, pathlib\nd = os.environ.get("MARKDIR")\nd and pathlib.Path(d, "%s").touch()\n' "$2" > "$1"; }

# Проект-образец: TS с псевдонимом `@/`, тест по импорту, лист без зависимых, файл вида, которого описание не знает.
P="$TP/p"; mkdir -p "$P/web/lib" "$P/web/app" "$P/web/tests" "$P/web/styles" "$P/scripts" "$P/.claude-docs"
printf '%s\n' '{"version": 1, "code": [{"glob": "web/**/*.ts", "lang": "tsjs"}], "tests": ["web/tests/**"],' \
    ' "roots": [{"dir": "web", "tsconfig": "web/tsconfig.json"}]}' > "$P/.claude-docs/project-map.json"
printf '%s\n' '{ "compilerOptions": { "paths": { "@/*": ["./*"] } } }' > "$P/web/tsconfig.json"
# Область данных в x.ts: отчёт учёта по правке внутри неё читает `git diff` с содержимым — путь внешнего diff и textconv.
xts() { printf '%s\n' '// dep-index: data-region-start' "export const x = $1;" '// dep-index: data-region-end' > "$P/web/lib/x.ts"; }
xts 1
# Лист — файл БЕЗ экспорта (D1339): экспортированная привязка TS теперь публичное имя, у файла появляется узел функции,
# и о нём карта честно говорит «на нём стоят 1». Прежде лист экспортировал константу и опирался на то, что у TS имён нет.
printf '%s\n' 'const leaf = 2; void leaf;' > "$P/web/lib/leaf.ts"
printf '%s\n' "import { x } from '@/lib/x';" 'export const page = x;' > "$P/web/app/page.ts"
printf '%s\n' "import { x } from '../lib/x';" 'test(x);' > "$P/web/tests/x.test.ts"
printf '%s\n' 'body { margin: 0 }' > "$P/web/styles/a.css"
plant_py "$P/scripts/project-graph.py" planted-graph
plant_py "$P/scripts/dep-index.py" planted-index
plant_py "$P/scripts/defect-class-carriers.py" planted-genera
( cd "$P" && git init -q . && git add -A && gc commit -qm i ) >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: образец не закоммичен" >&2; exit 2; }
# Учёт и карта образца собираются ДО яда; исполнил бы прибор здесь подложенный реестр родов — судит нога S1 ниже.
export MARKDIR="$TP/m-setup"; mkdir -p "$MARKDIR"
python3 "$DG" --repo "$P" --all >/dev/null 2>&1 && ( cd "$P" && git add -A && gc commit -qm idx ) >/dev/null 2>&1 \
    && python3 "$PG" --repo "$P" --refresh >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: учёт или карта образца не собраны" >&2; exit 2; }

# Яд в настройках git образца — после сборки: каждая программа исполняется голым git (контроль K ниже).
git -C "$P" config core.fsmonitor "$TP/evil/fsmonitor.sh"
git -C "$P" config diff.external "$TP/evil/ext-diff.sh"
git -C "$P" config diff.evil.textconv "$TP/evil/textconv.sh"
git -C "$P" config filter.evil.clean "$TP/evil/clean.sh"
printf '*.ts filter=evil diff=evil\n' > "$P/.git/info/attributes"
marks() { ls "$1" 2>/dev/null | tr '\n' ' '; }
fg() { env -u MARKDIR git "$@"; }   # git самой рамки: ставить метки ему нечего, иначе нога судила бы рамку
leg_dir() { export MARKDIR="$TP/m-$1"; mkdir -p "$MARKDIR"; }

# K — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ РАМКИ: голый git в образце исполняет яд, а подложенный прибор исполняется запуском.
# Без него «меток нет» в ногах ниже значило бы и «рамка не умеет их ставить».
xts 3
# Код голого git не читается намеренно: его исход — метки, их читают строки ниже (D1219).
leg_dir K; git -C "$P" diff HEAD -U0 -- web/lib/x.ts >/dev/null 2>&1 || true; git -C "$P" ls-files >/dev/null 2>&1 || true
git -C "$P" diff --no-ext-diff HEAD -U0 -- web/lib/x.ts >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_any_project.sh:$LINENO" >&2; exit 1; }
python3 "$P/scripts/defect-class-carriers.py" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_any_project.sh:$LINENO" >&2; exit 1; }
for m in fsmonitor ext-diff textconv clean planted-genera; do
    [ -f "$MARKDIR/$m" ] || { echo "рамка мертва: контроль не поставил метку $m (есть: $(marks "$MARKDIR"))" >&2; exit 2; }
done
fg -C "$P" checkout -q -- web/lib/x.ts

# S1 — приборы ClaudSoul в чужом дереве не исполняют ни подложенного реестра родов, ни яда git: сборка карты, учёта,
# перечень устаревших строк и отчёт по правке с содержимым (внешний diff и textconv зовёт `git diff` с патчем).
xts 4
leg_dir S1
python3 "$PG" --repo "$P" --refresh >/dev/null 2>&1; r1=$?
python3 "$DG" --repo "$P" --stale-by web/lib/x.ts >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_any_project.sh:$LINENO" >&2; exit 1; }
python3 "$DG" --repo "$P" --impact web/lib/x.ts >/dev/null 2>&1
python3 "$DG" --repo "$P" --changed web/lib/x.ts >/dev/null 2>&1; r2=$?
[ "$r1" = 0 ] && [ "$r2" = 0 ] && ok || bad S1a "приборы не отработали: карта $r1, учёт $r2"
[ -z "$(marks "$MARKDIR")" ] && ok || bad S1 "приборы ClaudSoul исполнили код проекта: $(marks "$MARKDIR")"
fg -C "$P" checkout -q -- web/lib/x.ts .claude-docs/dep-index.tsv 2>/dev/null
python3 "$PG" --repo "$P" --refresh >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_any_project.sh:$LINENO" >&2; exit 1; }

edit() {  # edit <сессия> <путь> [проект] — PreToolUse Edit
    local r="${3:-$P}"
    printf '{"session_id":"t-%s","tool_name":"Edit","hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"file_path":"%s/%s"}}' \
        "$1" "$r" "$r" "$2" \
        | env STATE_DIR="$TP/state-$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" CLAUDSOUL_ROOT="$REPO_ROOT" bash "$HOOK_DIR/impact-inject.sh" 2>/dev/null
}

# H1 — зависимые `.ts` по импорту (псевдоним и относительный путь), команда — прибором ClaudSoul с `--repo`;
# строки про `run_all.sh` в чужом проекте нет — выбора тестов там нет.
leg_dir H
O=$(edit h1 web/lib/x.ts)
has "$O" 'на нём стоят 2' H1; has "$O" 'page.ts' H1b; has "$O" 'x.test.ts' H1c
has "$O" "--repo \\\"$P\\\"" H1d; hasnt "$O" 'run_all.sh --changed' H1e
# H2 — вид знаком, зависимых нет: «никто», а не «0».
O=$(edit h2 web/lib/leaf.ts); has "$O" 'на нём не стоит никто' H2; hasnt "$O" 'стоят 0' H2b
# H3 — вид, которого описание не знает: «не знает», а не «стоят 0».
O=$(edit h3 web/styles/a.css); has "$O" 'карта этого вида не знает' H3; hasnt "$O" 'стоят' H3b
# H4 — маршрут Bash: правка `.ts` командой называется (прежний отбор `*.sh|*.py|*.md` её отсекал).
printf '%s\n' 'const leaf = 5; void leaf;' > "$P/web/lib/leaf.ts"
O=$(printf '{"session_id":"t-h4","tool_name":"Bash","hook_event_name":"PostToolUse","cwd":"%s","tool_input":{"command":"true"}}' "$P" \
    | env STATE_DIR="$TP/state-h4" PATHS_LIB="$HOOK_DIR/paths-lib.sh" CLAUDSOUL_ROOT="$REPO_ROOT" bash "$HOOK_DIR/impact-inject.sh" 2>/dev/null)
has "$O" 'web/lib/leaf.ts — на нём не стоит никто' H4; hasnt "$O" 'run_all.sh' H4b
fg -C "$P" checkout -q -- web/lib/leaf.ts
# H5 — проект без описания: тишина, подложенный прибор не исполняется.
Q="$TP/q"; mkdir -p "$Q/scripts" "$Q/.claude-docs"; plant_py "$Q/scripts/project-graph.py" planted-graph
plant_py "$Q/scripts/dep-index.py" planted-index; printf 'export const q = 1;\n' > "$Q/q.ts"
printf '# path\tsha\tdeps\tdocs\ttests\tnames\n' > "$Q/.claude-docs/dep-index.tsv"
( cd "$Q" && fg init -q . && fg add -A && MARKDIR= gc commit -qm i ) >/dev/null 2>&1
O=$(edit h5 q.ts "$Q"); [ -z "$O" ] && ok || bad H5 "без описания ждали тишину: ${O:0:200}"
[ -z "$(marks "$MARKDIR")" ] && ok || bad H6 "подсказка исполнила код проекта: $(marks "$MARKDIR")"

commit() {  # commit <сессия> <проект> — PreToolUse Bash `git commit`
    printf '{"session_id":"t-%s","tool_name":"Bash","hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$1" "$2" \
        | env STATE_DIR="$TP/state-$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" SCOPE_LIB="$HOOK_DIR/command-scope-lib.sh" \
              CLAUDSOUL_ROOT="$REPO_ROOT" bash "$HOOK_DIR/doc-impact-check.sh" 2>/dev/null
}
# C1 — хук коммита в образце: новый импорт сдвинул строку учёта, учёт пересобран прибором ClaudSoul и лёг в индекс.
leg_dir C
printf '%s\n' "import { x } from '@/lib/x';" 'export const leaf = x;' > "$P/web/lib/leaf.ts"
fg -C "$P" add web/lib/leaf.ts
O=$(commit c1 "$P")
has "$O" 'Учёт пересобран' C1
D=$(fg -C "$P" show :.claude-docs/dep-index.tsv 2>/dev/null | awk -F'\t' '$1 == "web/lib/leaf.ts" { print $3 }')
[ "$D" = "web/lib/x.ts" ] && ok || bad C1b "строка leaf.ts в индексе коммита: deps '$D', ждали web/lib/x.ts"
# C2 — без описания хук коммита молчит и подложенный учётчик не исполняет.
printf 'export const q = 2;\n' > "$Q/q.ts"; fg -C "$Q" add q.ts
O=$(commit c2 "$Q"); [ -z "$O" ] && ok || bad C2 "без описания ждали тишину: ${O:0:200}"
[ -z "$(marks "$MARKDIR")" ] && ok || bad C3 "хук коммита исполнил код проекта: $(marks "$MARKDIR")"

echo "test_project_map_any_project: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
