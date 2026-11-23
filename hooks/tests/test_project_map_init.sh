#!/usr/bin/env bash
# СУДИТ: hooks/lib/project_map.py scripts/project-conformance.sh scripts/dep-index.py scripts/project-graph.py
# test_project_map_init.sh — заведение карты связей в проекте и сверка (спецификация
#                       `.claude-docs/specs/2026-10-24-project-map-principle`, шаг 1д).
# Результат: `project_map.py --propose` предлагает описание по дереву (языки по расширениям, корни TS по tsconfig);
#            `/init-project`-процедура пишет описание, собирает учёт и карту, кладёт карту в .gitignore; сверка
#            `project-conformance.sh` до заведения говорит «карты связей нет», после — описание есть и учёт свеж.
# Проверка результата: bash hooks/tests/test_project_map_init.sh даёт 0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
unset CLAUDSOUL_REPO
export CLAUDSOUL_ROOT="$REPO"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
has()   { if grep -qF -- "$2" <<< "$1"; then ok; else bad "$3" "нет '$2' в '${1:0:300}'"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$1"; then bad "$3" "не ждали '$2'"; else ok; fi; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
gc() { git -c user.email=t@t -c user.name=t "$@"; }

# Проект-образец: TS с tsconfig + shell, минимальный договор для сверки.
P="$TMP/p"; mkdir -p "$P/web/lib" "$P/web/app" "$P/.claude-docs"
printf '{ "compilerOptions": {} }\n' > "$P/web/tsconfig.json"
printf 'export const x = 1;\n' > "$P/web/lib/x.ts"
printf "import { x } from '../lib/x';\nexport const p = x;\n" > "$P/web/app/page.tsx"
printf '#!/usr/bin/env bash\necho hi\n' > "$P/build.sh"
printf '# CLAUDE\n' > "$P/CLAUDE.md"
( cd "$P" && git init -q . && git add -A && gc commit -qm i ) >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: образец не закоммичен" >&2; exit 2; }

# P1 — propose: языки по дереву, корень TS по tsconfig.
PROP=$(python3 "$REPO/hooks/lib/project_map.py" --propose "$P" 2>/dev/null)
has "$PROP" '"lang": "tsjs"' P1; has "$PROP" 'web/**/*.ts' P1b; has "$PROP" '"lang": "shell"' P1c
has "$PROP" '"dir": "web"' P1d; has "$PROP" 'web/tsconfig.json' P1e

# P2 — сверка ДО заведения: «карты связей нет».
OUT=$(bash "$REPO/scripts/project-conformance.sh" "$P" 2>&1)
has "$OUT" 'карты связей нет' P2

# P3 — процедура /init-project: описание → учёт → карта → .gitignore.
python3 "$REPO/hooks/lib/project_map.py" --propose "$P" > "$P/.claude-docs/project-map.json" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_project_map_init.sh:$LINENO" >&2; exit 1; }
env -u CLAUDSOUL_REPO python3 "$REPO/scripts/dep-index.py" --repo "$P" --all >/dev/null 2>&1 && ok || bad P3a "учёт не собрался"
env -u CLAUDSOUL_REPO LESSONS_DIR="$TMP/nl" python3 "$REPO/scripts/project-graph.py" --repo "$P" --refresh >/dev/null 2>&1 && ok || bad P3b "карта не собралась"
printf '.claude-docs/project-graph.json\n' >> "$P/.gitignore"
[ -f "$P/.claude-docs/dep-index.tsv" ] && ok || bad P3c "учёта нет на диске"
[ -f "$P/.claude-docs/project-graph.json" ] && ok || bad P3d "карты нет на диске"
# карта в .gitignore, описание и учёт — под git (решение владельца)
git -C "$P" check-ignore -q .claude-docs/project-graph.json && ok || bad P3e "карта не в .gitignore"
git -C "$P" check-ignore -q .claude-docs/project-map.json && bad P3f "описание попало в .gitignore" || ok
git -C "$P" check-ignore -q .claude-docs/dep-index.tsv && bad P3g "учёт попал в .gitignore" || ok

# P4 — учёт знает импорт TS (связь по описанию работает).
T=$(awk -F'\t' '$1 == "web/app/page.tsx" { print $3 }' "$P/.claude-docs/dep-index.tsv")
grep -q 'web/lib/x.ts' <<< "$T" && ok || bad P4 "импорт @/../lib/x не стал ребром: deps '$T'"

# P5 — сверка ПОСЛЕ заведения: «карты нет» ушло, описание есть, учёт свеж.
( cd "$P" && git add -A && gc commit -qm init-map ) >/dev/null 2>&1
OUT=$(bash "$REPO/scripts/project-conformance.sh" "$P" 2>&1)
hasnt "$OUT" 'карты связей нет' P5
has "$OUT" 'учёт зависимостей свеж' P5b

echo "test_project_map_init: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
