#!/usr/bin/env bash
# СУДИТ: scripts/dep-index.py scripts/project-graph.py
# test_project_graph_gaps_characterized.sh — характеризующий свидетель ПРЕДЕЛОВ карты связей
#   (аудит docs/project-relations-audit.ru.md §3.2, пробы E1–E13; этап R0 плана §7).
# Результат: у каждого названного аудитом пробела есть воспроизводимый вход, и нога закрепляет
#            НЫНЕШНЕЕ поведение карты. Каждая нога — ПРЕДЕЛ, а не контракт: в комментарии назван
#            этап плана (R2/R3/R4/R5), который его снимает, и тогда нога переворачивается.
#            Положительный контроль (настоящий `bash hooks/b.sh` даёт «зовёт») не пускает дерево,
#            где рёбра сняты вовсе.
# Проверка результата: bash hooks/tests/test_project_graph_gaps_characterized.sh даёт 0
#
# Зачем закреплять дефект. Аудит 17 сентября 2026 показал тринадцать пробелов на изолированных
# пробах; четыре из них взяты пунктами долга (D427–D430) и получили свои пробы в
# hooks/tests/fixtures/probe_D*.sh. Остальные семь остаются пределами, и без свидетеля они
# неотличимы от регресса: когда этап плана их снимет, эта нога покраснеет первой — и это
# сигнал перевернуть её, а не починить обратно.
#
# Рамка: копии обоих механизмов исполняются в песочнице-репозитории; живой ~/.claude не
# читается (HOME и LESSONS_DIR — в песочницу), живой учёт и кэш карты не трогаются.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
# Физический путь: на macOS mktemp даёт /var/…, а /var — ссылка на /private/var; relpath карты
# от cwd тогда уводит файл «вне дерева».
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"
mkdir -p "$P/scripts" "$P/hooks" "$P/pkg" "$P/ts" "$P/.github/workflows" "$P/.claude-docs" \
         "$P/mcp-server/visualization" "$TMP/home" "$TMP/lessons"
cp "$REPO_ROOT/scripts/project-graph.py" "$REPO_ROOT/scripts/dep-index.py" "$P/scripts/"
export HOME="$TMP/home" LESSONS_DIR="$TMP/lessons" PYTHONDONTWRITEBYTECODE=1 CLAUDSOUL_REPO="$P"
STATE_DIR="$TMP/state"; export STATE_DIR; mkdir -p "$STATE_DIR"
CACHE="$P/mcp-server/visualization/project-graph-data.json"

# ── дерево аудита (§3.2): цепочка a→b→c, alias-импорт, короткое имя и метод, TS, CI ─────────
printf '#!/usr/bin/env bash\nbash hooks/b.sh\n' > "$P/hooks/a.sh"
printf '#!/usr/bin/env bash\nbash hooks/c.sh\n' > "$P/hooks/b.sh"
printf '#!/usr/bin/env bash\necho c\n'          > "$P/hooks/c.sh"
printf 'def calculate_total(x):\n    return x * 2\n\n\ndef compute_action():\n    return "act"\n' > "$P/pkg/worker.py"
printf 'from pkg.worker import calculate_total as calc\nresult = calc(3)\n' > "$P/pkg/consumer.py"
printf 'from pkg.worker import compute_action\ncompute_action()\n'          > "$P/pkg/caller.py"
printf 'def run():\n    return 1\n\n\nclass Handler:\n    def process(self):\n        return 2\n' > "$P/pkg/short.py"
printf 'import {render} from "./library";\nrender();\n' > "$P/ts/app.ts"
printf 'export function render() { return 1; }\n'      > "$P/ts/library.ts"
printf 'name: ci\non: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: python pkg/worker.py\n' > "$P/.github/workflows/ci.yml"
( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 \
    || { echo "рамка: git-песочница не поднялась"; exit 1; }
( cd "$P" && python3 scripts/dep-index.py --all >/dev/null 2>&1 ) || { echo "рамка: учёт не собрался"; exit 1; }
( cd "$P" && python3 scripts/project-graph.py --refresh >/dev/null 2>&1 ) || { echo "рамка: карта не собралась"; exit 1; }
[ -f "$CACHE" ] || { echo "рамка: кэш карты не записан"; exit 1; }

pg()   { ( cd "$P" && python3 scripts/project-graph.py "$@" 2>/dev/null ); }
# q <вопрос> <ключ> — ответы из кэша: out → «тип<TAB>цель» по исходящим, in → число входящих,
# type → вид узла, has → yes/no
q() {
    python3 - "$CACHE" "$1" "$2" <<'PY'
import json, sys
g = json.load(open(sys.argv[1])); what, key = sys.argv[2], sys.argv[3]
byid = {n['id']: n for n in g['nodes']}
node = next((n for n in g['nodes'] if n['key'] == key), None)
if what == 'has':
    print('yes' if node else 'no')
elif what == 'type':
    print(node['type'] if node else '')
elif what == 'out':
    for e in g['edges']:
        if node and e['source'] == node['id']:
            print(e['type'] + '\t' + byid[e['target']]['key'])
elif what == 'in':
    print(sum(1 for e in g['edges'] if node and e['target'] == node['id']))
PY
}
deps_of() { awk -F'\t' -v p="$1" '$1 == p { print $3 }' "$P/.claude-docs/dep-index.tsv"; }

# ── T0 положительный контроль: настоящий `bash hooks/b.sh` даёт «зовёт» a.sh → b.sh ─────────
# Без него ноги «ребра нет» проходили бы и на карте, где рёбер не осталось вовсе.
if grep -qF "$(printf 'зовёт\thooks/b.sh')" <<< "$(q out hooks/a.sh)"; then ok
else bad T0 "настоящий вызов bash hooks/b.sh ребра «зовёт» не дал — контроль пуст: $(q out hooks/a.sh | tr '\n' ' ')"; fi
[ "$(q has pkg/worker.py)" = yes ] && [ "$(q has 'функция:compute_action')" = yes ] && ok \
    || bad T0b "рамка: узла pkg/worker.py или функция:compute_action нет — ноги ниже судят о пустоте"

# ── E1 (ПРЕДЕЛ, снимает R3 — identity, symbols): alias-импорт `from pkg.worker import … as calc`
#    ребра consumer→worker не даёт ни в учёте (deps пусты), ни в карте. Когда R3 научит учёт
#    разбирать Python-импорт, эта нога перевернётся: ребро появится.
if [ -z "$(deps_of pkg/consumer.py)" ]; then ok
else bad E1a "учёт увидел зависимость consumer.py → «$(deps_of pkg/consumer.py)» — предел E1 снят, переверни ногу"; fi
if grep -qF 'pkg/worker.py' <<< "$(q out pkg/consumer.py)"; then
    bad E1b "карта дала ребро consumer.py → worker.py по alias-импорту — предел E1 снят, переверни ногу"
else ok; fi

# ── E3 (ПРЕДЕЛ, снимает R5 — другой стек): .ts есть в узлах видом «data», рёбер import/call нет.
#    Когда R5 заведёт поставщика для TS/JS, узел получит вид кода и ребро app.ts → library.ts.
[ "$(q has ts/app.ts)" = yes ] && [ "$(q has ts/library.ts)" = yes ] && ok \
    || bad E3a "узлов .ts в карте нет — «вид есть у каждого файла дерева» нарушен"
[ "$(q type ts/app.ts)" = data ] && ok \
    || bad E3b "ts/app.ts получил вид «$(q type ts/app.ts)», а не data — предел E3 снят, переверни ногу"
[ -z "$(q out ts/app.ts)" ] && ok \
    || bad E3c "у ts/app.ts появились исходящие рёбра: $(q out ts/app.ts | tr '\n' ' ') — предел E3 снят, переверни ногу"

# ── E4 (ПРЕДЕЛ, снимает R3): у короткого имени `run` (< 4 букв) узла-функции нет; метод
#    `Handler.process` в публичные имена не попадает и узла не имеет. Класс Handler узел имеет.
[ "$(q has 'функция:run')" = no ] && ok \
    || bad E4a "узел функция:run появился — предел E4 (короткие имена) снят, переверни ногу"
[ "$(q has 'функция:process')" = no ] && ok \
    || bad E4b "узел функция:process появился — предел E4 (методы) снят, переверни ногу"
[ "$(q has 'функция:Handler')" = yes ] && ok \
    || bad E4c "класс Handler узла не получил — контроль к E4 пуст"

# ── E11 (ПРЕДЕЛ, снимает R3 — direct vs transitive query): path_of(a.sh) показывает только
#    соседей — b.sh есть, c.sh нет. Когда запрос станет транзитивным, c.sh появится.
OUT_A=$(pg --node hooks/a.sh)
grep -qF 'hooks/b.sh' <<< "$OUT_A" && ok || bad E11a "path_of(a.sh) не показал даже соседа b.sh — контроль пуст"
if grep -qF 'hooks/c.sh' <<< "$OUT_A"; then
    bad E11b "path_of(a.sh) показал c.sh — путь стал транзитивным, предел E11 снят, переверни ногу"
else ok; fi

# ── E12 (ПРЕДЕЛ, снимает R3): ребро «использует compute_action» идёт caller.py → worker.py
#    (в ФАЙЛ владельца), а у узла функция:compute_action входящих нет. Когда ребро вызова
#    будет направлено в узел функции, счётчик входящих станет ненулевым.
grep -qF "$(printf 'использует compute_action\tpkg/worker.py')" <<< "$(q out pkg/caller.py)" && ok \
    || bad E12a "настоящий вызов compute_action() ребра в worker.py не дал — контроль пуст"
[ "$(q in 'функция:compute_action')" = 0 ] && ok \
    || bad E12b "у узла функция:compute_action появились входящие ($(q in 'функция:compute_action')) — предел E12 снят, переверни ногу"

# ── E13 (ПРЕДЕЛ, снимает R4 — CI/task bindings): узел CI-рецепта есть (data), а `run: python
#    pkg/worker.py` ребра-вызова не даёт. Когда R4 заведёт разбор привязок CI, ребро появится.
[ "$(q type .github/workflows/ci.yml)" = data ] && ok \
    || bad E13a "узла .github/workflows/ci.yml вида data нет: «$(q type .github/workflows/ci.yml)»"
[ -z "$(q out .github/workflows/ci.yml)" ] && ok \
    || bad E13b "у ci.yml появились исходящие рёбра: $(q out .github/workflows/ci.yml | tr '\n' ' ') — предел E13 снят, переверни ногу"

# ── E7 (ПРЕДЕЛ, снимает R2 — единое обновление; назван в докстринге load()): правка tracked
#    исходника без правки учёта кэш не старит — load() отдаёт прежнюю карту без нового ребра,
#    а свежая сборка ребро видит. Когда у кэша появится сторож по mtime источников, первая
#    половина перевернётся. Идёт последней: меняет исходник песочницы.
printf 'compute_action()\n' >> "$P/pkg/consumer.py"
if grep -qF 'использует compute_action' <<< "$(pg --node pkg/consumer.py)"; then
    bad E7a "load() увидел правку исходника без правки учёта — предел E7 снят, переверни ногу"
else ok; fi
if grep -qF 'использует compute_action' <<< "$(pg --refresh --node pkg/consumer.py)"; then ok
else bad E7b "свежая сборка не увидела новый вызов в consumer.py — контроль пуст"; fi

echo "test_project_graph_gaps_characterized: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
