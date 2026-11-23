#!/usr/bin/env bash
# СУДИТ: hooks/lib/project_map.py scripts/dep-index.py scripts/project-graph.py
# test_project_map_imports.sh — учёт и карта знают импорты TS/JS и Python (спецификация
#                       `.claude-docs/specs/2026-10-24-project-map-principle`, шаг 1в, D1079).
# Результат: импорт, разрешённый в файл дерева, — ребро «зависит от» (относительный путь, псевдоним из tsconfig, подбор
#            расширения и `index.*`; в Python — относительный импорт от пакета и абсолютный в модуль дерева); пакеты,
#            `import(переменная)` и закомментированный импорт рёбер не дают; тест, импортирующий файл или подменяющий
#            его (`vi.mock`), — его тест (решение владельца 25 октября 2026); инкремент равен сборке.
# Проверка результата: bash hooks/tests/test_project_map_imports.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
unset CLAUDSOUL_REPO CLAUDSOUL_ROOT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TP="$(cd "$TMP" && pwd -P)"
DG="$REPO_ROOT/scripts/dep-index.py"; PG="$REPO_ROOT/scripts/project-graph.py"
gc() { git -c user.email=t@t -c user.name=t "$@"; }
# col <проект> <путь> <номер колонки: 3 deps, 4 docs, 5 tests> — поле строки учёта, как записано
col() { awk -F'\t' -v p="$2" -v c="$3" '$1 == p { print $c }' "$1/.claude-docs/dep-index.tsv"; }

mkts() {
    local d="$1"; mkdir -p "$d/web/lib/util" "$d/web/app/api/a" "$d/web/app/api/b" "$d/web/tests" "$d/.claude-docs"
    printf '%s\n' '{"version": 1, "code": [{"glob": "web/**/*.ts", "lang": "tsjs"}, {"glob": "web/**/*.tsx", "lang": "tsjs"}],' \
        ' "tests": ["**/tests/**", "**/*.test.ts"], "roots": [{"dir": "web", "tsconfig": "web/tsconfig.json"}]}' \
        > "$d/.claude-docs/project-map.json"
    printf '%s\n' '{' '  // псевдоним, как у Next.js' '  "compilerOptions": { "paths": { "@/*": ["./*"] } },' '}' \
        > "$d/web/tsconfig.json"
    printf '%s\n' 'export const x = 1;' > "$d/web/lib/x.ts"
    printf '%s\n' 'export const u = 2;' > "$d/web/lib/util/index.ts"
    printf '%s\n' 'export const w = 3;' > "$d/web/lib/w.tsx"
    printf '%s\n' "import { x } from '@/lib/x';" "import {" "  u," "} from '../../../lib/util';" \
        "import React from 'react';" "export * from '@/lib/w';" "const m = await import(name);" \
        > "$d/web/app/api/a/route.ts"
    printf '%s\n' "const a = require('../a/route');" "const y = import('@/lib/x');" "// import { u } from '@/lib/util';" \
        "/* import { w } from '@/lib/w'; */" > "$d/web/app/api/b/route.ts"
    printf '%s\n' "import { GET } from '@/app/api/a/route';" "vi.mock('@/lib/x');" > "$d/web/tests/a.test.ts"
    ( cd "$d" && git init -q . && git add -A && gc commit -qm i ) >/dev/null 2>&1
}
mkpy() {
    local d="$1"; mkdir -p "$d/pkg" "$d/tools" "$d/tests" "$d/.claude-docs"
    : > "$d/pkg/__init__.py"
    printf '%s\n' 'def f(): return 1' > "$d/pkg/b.py"
    printf '%s\n' 'from .b import f' 'from . import c' > "$d/pkg/a.py"
    printf '%s\n' 'import json' 'X = 1' > "$d/pkg/c.py"
    printf '%s\n' 'import sys' 'import pkg.a' 'from storage import Store' '# import pkg.c' > "$d/tools/run.py"
    printf '%s\n' 'class Store: pass' > "$d/tools/storage.py"
    printf '%s\n' 'import json' > "$d/tools/json.py"
    printf '%s\n' 'import json' > "$d/tools/user.py"
    printf '%s\n' 'from pkg.b import f' > "$d/tests/test_b.py"
    ( cd "$d" && git init -q . && git add -A && gc commit -qm i ) >/dev/null 2>&1
}

# --- TS/JS -------------------------------------------------------------------------------------------------------
T="$TP/ts"; mkts "$T"
( cd "$TP" && python3 "$DG" --repo "$T" --all ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_imports.sh:$LINENO" >&2; exit 1; }
A=web/app/api/a/route.ts; B=web/app/api/b/route.ts
# I1: псевдоним, многострочный импорт в каталог с index, export-from; пакет и import(переменная) — не рёбра.
[ "$(col "$T" $A 3)" = "web/lib/util/index.ts,web/lib/w.tsx,web/lib/x.ts" ] && ok \
    || bad I1 "deps $A: [$(col "$T" $A 3)], ждали web/lib/util/index.ts,web/lib/w.tsx,web/lib/x.ts"
# I2: одноимённый файл — относительный require и import() с литералом; закомментированные импорты — не рёбра.
[ "$(col "$T" $B 3)" = "web/app/api/a/route.ts,web/lib/x.ts" ] && ok \
    || bad I2 "deps $B: [$(col "$T" $B 3)], ждали web/app/api/a/route.ts,web/lib/x.ts"
# I3: тест, импортирующий одноимённый route, — его тест; vi.mock — тест подменённого файла.
{ [ "$(col "$T" $A 5)" = "web/tests/a.test.ts" ] && [ "$(col "$T" web/lib/x.ts 5)" = "web/tests/a.test.ts" ]; } && ok \
    || bad I3 "tests $A: [$(col "$T" $A 5)], tests web/lib/x.ts: [$(col "$T" web/lib/x.ts 5)]"
# I4: инкремент равен сборке — новый импорт, пересборка одной строки, `--check` 0.
printf '%s\n' "import { w } from '@/lib/w';" >> "$T/$B"
( cd "$T" && python3 "$DG" --repo "$T" --changed $B && python3 "$DG" --repo "$T" --check ) >/dev/null 2>&1 \
    && [ "$(col "$T" $B 3)" = "web/app/api/a/route.ts,web/lib/w.tsx,web/lib/x.ts" ] && ok \
    || bad I4 "инкремент: deps $B [$(col "$T" $B 3)], --check не 0 либо ребро не добавлено"
# I5: правка tsconfig — вход учёта: псевдоним сменился, строки TS названы `--stale-by`.
( cd "$T" && gc add -A && gc commit -qm i5 ) >/dev/null 2>&1
printf '%s\n' '{ "compilerOptions": { "paths": { "@/*": ["./lib/*"] } } }' > "$T/web/tsconfig.json"
S5=$( cd "$T" && python3 "$DG" --repo "$T" --stale-by web/tsconfig.json 2>&1 | tr '\n' ' ' )
grep -q "$A" <<< "$S5" && ok || bad I5 "правка tsconfig: --stale-by [${S5}] не назвал $A"
# I6: карта — ребро импорта есть и его роль «зовёт».
( cd "$T" && git checkout -q -- web/tsconfig.json && python3 "$PG" --repo "$T" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_imports.sh:$LINENO" >&2; exit 1; }
E6=$( python3 - "$T/.claude-docs/project-graph.json" "$A" web/lib/x.ts <<'PY'
import json, sys
g = json.load(open(sys.argv[1])); k = {n["id"]: n["key"] for n in g["nodes"]}
print(",".join(sorted(e["type"] for e in g["edges"] if k[e["source"]] == sys.argv[2] and k[e["target"]] == sys.argv[3])))
PY
)
[ "$E6" = "зовёт" ] && ok || bad I6 "ребро карты $A → web/lib/x.ts: [${E6}], ждали «зовёт»"

# --- Python ------------------------------------------------------------------------------------------------------
P="$TP/py"; mkpy "$P"
( cd "$TP" && python3 "$DG" --repo "$P" --all ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_imports.sh:$LINENO" >&2; exit 1; }
# I7: относительные импорты от пакета, `from . import модуль`.
[ "$(col "$P" pkg/a.py 3)" = "pkg/b.py,pkg/c.py" ] && ok || bad I7 "deps pkg/a.py: [$(col "$P" pkg/a.py 3)]"
# I8: абсолютный импорт пакета; модуль соседнего каталога (каталог скрипта — первый в пути поиска); stdlib и
#     закомментированный импорт — не рёбра.
[ "$(col "$P" tools/run.py 3)" = "pkg/a.py,tools/storage.py" ] && ok || bad I8 "deps tools/run.py: [$(col "$P" tools/run.py 3)]"
# I9: одноимённый stdlib-модулю файл дерева — ребро только соседу по каталогу, `import json` из чужого каталога — нет.
{ [ "$(col "$P" tools/user.py 3)" = "tools/json.py" ] && [ -z "$(col "$P" pkg/c.py 3)" ]; } && ok \
    || bad I9 "deps tools/user.py: [$(col "$P" tools/user.py 3)], deps pkg/c.py: [$(col "$P" pkg/c.py 3)]"
# I10: тест, импортирующий модуль, — его тест.
[ "$(col "$P" pkg/b.py 5)" = "tests/test_b.py" ] && ok || bad I10 "tests pkg/b.py: [$(col "$P" pkg/b.py 5)]"

# --- Swift (7 ноября 2026): связь по имени верхнего уровня, а не по импорту файла -------------------------------
mksw() {
    local d="$1"; mkdir -p "$d/Sources/Core" "$d/Sources/App" "$d/Tests/CoreTests" "$d/.claude-docs"
    printf '%s\n' '{"version": 1, "code": [{"glob": "**/*.swift", "lang": "swift"}], "tests": ["**/Tests/**"]}' \
        > "$d/.claude-docs/project-map.json"
    printf '%s\n' 'public final class Engine {' '    func run() { let data = 2; Helper.go() }' '}' > "$d/Sources/Core/Engine.swift"
    mkdir -p "$d/Sources/Tool"; printf '%s\n' 'let data = 1' 'print(data)' > "$d/Sources/Tool/main.swift"
    printf '%s\n' 'enum Helper {' '    static func go() {}' '}' '// Engine в комментарии' 'let label = "Engine"' \
        > "$d/Sources/Core/Helper.swift"
    printf '%s\n' 'struct Twin {}' > "$d/Sources/Core/TwinA.swift"
    printf '%s\n' 'struct Twin {}' > "$d/Sources/App/TwinB.swift"
    printf '%s\n' 'private let secret = 1' 'fileprivate func hidden() {}' > "$d/Sources/Core/Private.swift"
    printf '%s\n' 'import Core' 'let e = Engine()' 'let t = Twin()' 'let secret = 2; hidden()' > "$d/Sources/App/main.swift"
    printf '%s\n' '@testable import Core' 'final class EngineTests {' '    func test() { _ = Engine() }' '}' \
        > "$d/Tests/CoreTests/EngineTests.swift"
    ( cd "$d" && git init -q . && git add -A && gc commit -qm i ) >/dev/null 2>&1
}
S="$TP/sw"; mksw "$S"
( cd "$TP" && python3 "$DG" --repo "$S" --all ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_imports.sh:$LINENO" >&2; exit 1; }
# I11: имя типа другого файла — ребро, в том числе через модуль (`import Core`); имя, объявленное в двух файлах, и
#      `private`/`fileprivate` верхнего уровня чужого файла — нет.
[ "$(col "$S" Sources/App/main.swift 3)" = "Sources/Core/Engine.swift" ] && ok \
    || bad I11 "deps Sources/App/main.swift: [$(col "$S" Sources/App/main.swift 3)]"
# I12: имя в комментарии и в строке ребра не даёт; вызов члена `Helper.go()` — ребро к объявившему `Helper`; глобальная
#      `data` чужого, не импортированного модуля `Tool` — не ребро для локальной `data`.
{ [ "$(col "$S" Sources/Core/Engine.swift 3)" = "Sources/Core/Helper.swift" ] && [ -z "$(col "$S" Sources/Core/Helper.swift 3)" ]; } \
    && ok || bad I12 "deps Engine: [$(col "$S" Sources/Core/Engine.swift 3)], Helper: [$(col "$S" Sources/Core/Helper.swift 3)]"
# I13: тест, называющий тип, — тест файла, где тип объявлен.
[ "$(col "$S" Sources/Core/Engine.swift 5)" = "Tests/CoreTests/EngineTests.swift" ] && ok \
    || bad I13 "tests Sources/Core/Engine.swift: [$(col "$S" Sources/Core/Engine.swift 5)]"
# I14 (скептик opus по 9dc31762, H2): тест Swift Testing, где имя стоит только в строке `#expect(…)`, — тест файла.
printf '%s\n' '@testable import Core' '@Test func helps() {' '    #expect(Helper.ok)' '}' > "$S/Tests/CoreTests/HelperTests.swift"
( cd "$S" && gc add -A && gc commit -qm i14 && python3 "$DG" --repo "$S" --all ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_imports.sh:$LINENO" >&2; exit 1; }
[ "$(col "$S" Sources/Core/Helper.swift 5)" = "Tests/CoreTests/HelperTests.swift" ] && ok \
    || bad I14 "tests Sources/Core/Helper.swift: [$(col "$S" Sources/Core/Helper.swift 5)]"
# I15 (H1): ребро зависит от СОДЕРЖИМОГО цели — переименование типа в Helper.swift делает неверной строку Engine.swift;
#      `--stale-by` её называет, а `--changed` по правленому файлу равен сборке (`--check` 0, ребра больше нет).
( cd "$S" && python3 "$PG" --repo "$S" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_imports.sh:$LINENO" >&2; exit 1; }
sed -i.bak 's/^enum Helper {/enum Aide {/' "$S/Sources/Core/Helper.swift" && rm -f "$S/Sources/Core/Helper.swift.bak"
S15=$( cd "$S" && python3 "$DG" --repo "$S" --stale-by Sources/Core/Helper.swift 2>&1 | tr '\n' ' ' )
{ grep -q "Sources/Core/Engine.swift" <<< "$S15" \
    && ( cd "$S" && python3 "$DG" --repo "$S" --changed Sources/Core/Helper.swift && python3 "$DG" --repo "$S" --check ) >/dev/null 2>&1 \
    && [ -z "$(col "$S" Sources/Core/Engine.swift 3)" ]; } && ok \
    || bad I15 "--stale-by [${S15}], deps Engine после --changed: [$(col "$S" Sources/Core/Engine.swift 3)]"
# I16 (H1): `--touch` правленого файла даёт ту же карту, что полная сборка: ребро Engine → Helper снято.
edges() { python3 - "$1/.claude-docs/project-graph.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1])); k = {n["id"]: n["key"] for n in g["nodes"]}
print("\n".join(sorted(f'{k[e["source"]]} {e["type"]} {k[e["target"]]}' for e in g["edges"])))
PY
}
( cd "$S" && python3 "$PG" --repo "$S" --touch Sources/Core/Helper.swift ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_imports.sh:$LINENO" >&2; exit 1; }; E16t=$(edges "$S")
( cd "$S" && python3 "$PG" --repo "$S" --refresh ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_project_map_imports.sh:$LINENO" >&2; exit 1; }; E16f=$(edges "$S")
{ [ -n "$E16f" ] && [ "$E16t" = "$E16f" ]; } && ok || bad I16 "touch ≠ refresh: $(diff <(printf '%s\n' "$E16t") <(printf '%s\n' "$E16f") | tr '\n' ' ')"
# I17 (M4): `propose` по дереву Swift даёт язык `swift` и тесты `**/Tests/**`.
P17=$(python3 "$REPO_ROOT/hooks/lib/project_map.py" --propose "$S" 2>/dev/null)
{ grep -q '"\*\*/\*\.swift"' <<< "$P17" && grep -q '"swift"' <<< "$P17" && grep -q '"\*\*/Tests/\*\*"' <<< "$P17"; } && ok \
    || bad I17 "propose: $(tr '\n' ' ' <<< "$P17")"

echo "test_project_map_imports: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
