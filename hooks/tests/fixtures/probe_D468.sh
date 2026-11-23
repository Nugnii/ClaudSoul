#!/usr/bin/env bash
# probe_D468.sh — «Проверка» пункта D468: приборы реестра родов судят пробы корней
# (`scripts/probes/*.sh`) как КОД, хотя это такой же фикстурный текст, как `hooks/tests/*`,
# — исключён из универсума только второй.
# Результат: строка таблицы пробы корня, написанная ради ОПИСАНИЯ мира, не становится
#            носителем рода. Проверяется на роде G («объявление без исполнителя»), где
#            дефект наблюдён 19 сентября 2026: `PATH="$PWD/r6shim:$PATH"` прочитано как
#            поле манифеста в тот же час, когда строка была написана.
# Проверка результата: bash hooks/tests/fixtures/probe_D468.sh → 0. Сегодня 1 (дефект
#            наблюдён), 2 — рамка не собралась.
#
# УСТРОЙСТВО. Прибор реестра читает `git ls-files` своего дерева, поэтому судится КОПИЯ
# дерева (`git archive HEAD`), а не подставной каталог: в пустой песочнице прибор падает на
# другом роде, и «носителя нет» вышло бы артефактом падения. В копию подсаживается ОДНА
# строка в `scripts/probes/`, написанная в форме, которую признак рода G заведомо ловит.
# Прибор зовётся ОДИН раз (7 с процессорного времени на род), и оба контроля читаются из
# одного вывода:
#   · СУБЪЕКТ — подсаженные пробы не должны быть названы;
#   · ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ — прибор обязан назвать ХОТЬ КАКОГО-ТО носителя вне
#     `scripts/probes/`, иначе «тихо» означает «прибор не отработал», а не «чисто».
#     Контроль ЧИСЛОВОЙ, а не именной, и это правка по находке скептика 19 сентября 2026:
#     первая редакция требовала поимённо `scripts/ablation/checker.sh`, то есть ПОЧИНКА
#     контрольного файла выключила бы суд навсегда — проба отвечала бы 2 «рамка не
#     собралась», а свидетель зелёных сторон читает любой ненулевой код как «не позеленела».
# Механизм берётся из CLAUDSOUL_REPO: зелёная сторона подставляет копию с починкой.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
TOOL="$MECH/scripts/defect-class-carriers.py"
[ -f "$TOOL" ] || { echo "probe_D468: нет $TOOL" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D468: нет python3 — рамка не собралась" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D468: нет git — рамка не собралась" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D468: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
W="$T/tree"
mkdir -p "$W" || exit 2
( cd "$ROOT" && git archive HEAD ) 2>/dev/null | tar -x -C "$W" 2>/dev/null \
    || { echo "probe_D468: не собралась копия дерева — рамка не собралась" >&2; exit 2; }
cp "$TOOL" "$W/scripts/defect-class-carriers.py" || exit 2

# ДВЕ подсадки, и вторая названа как настоящая проба корня (`R9.sh`): первая редакция
# сажала единственный файл `fixture_D468.sh`, и подделка «исключить имена, начинающиеся с
# fixture_» зеленила пробу, ничего не починив (находка скептика того же дня). Имени,
# отличающего подсадку от настоящих проб, у неё больше нет.
VICTIM="$W/scripts/probes/fixture_D468.sh"
VICTIM2="$W/scripts/probes/R9.sh"
cat > "$VICTIM" <<'FIXTURE'
#!/usr/bin/env bash
# Фикстура пробы D468. Форма взята ИЗ МИРА, а не придумана: это строка таблицы носителей
# `scripts/probes/R6.sh` как она была написана 19 сентября 2026 — подготовка состояния
# печатает снимок карты (`printf '%s' '{...}' > …json`, это и есть объект в универсуме
# признака), а рядом стоит `имя:$PATH`. Первая редакция фикстуры печатала не JSON, и
# признак её не ловил: проба была зелёной, ничего не судя.
_d468_table() {
    cat <<'ROWS'
d468|описание|printf '%s' '{"nodes":[{"id":1}]}' > mcp-server/visualization/project-graph-data.json|mkdir -p d468shim; printf 'exit 1\n' > d468shim/python3; printf '%s' '{"nodes":[{"id":1}]}' > mcp-server/visualization/project-graph-data.json|PATH="$PWD/d468shim:$PATH" true
ROWS
}
FIXTURE
cp "$VICTIM" "$VICTIM2"
chmod +x "$VICTIM" "$VICTIM2"
( cd "$W" && git init -q && git add -A && \
  git -c user.email=p@p -c user.name=p -c commit.gpgsign=false commit -qm fixture ) >/dev/null 2>&1 \
    || { echo "probe_D468: копия дерева не стала репозиторием — рамка не собралась" >&2; exit 2; }

S="$T/state"; mkdir -p "$S"
OUT="$T/out.txt"
( cd "$W" && STATE_DIR="$S" python3 scripts/defect-class-carriers.py --genus G ) > "$OUT" 2>&1
RC=$?
[ "$RC" -le 1 ] || { echo "probe_D468: прибор ответил кодом $RC — рамка не собралась:"; cat "$OUT"; exit 2; } >&2

# Положительный контроль СТРОГО ПЕРЕД судом: молчание прибора не должно читаться как «чисто».
_others=$(grep -c '^  · ' "$OUT" 2>/dev/null | head -1)
_others=$(( ${_others:-0} - $(grep -c '^  · scripts/probes/' "$OUT" 2>/dev/null | head -1) ))
if [ "${_others:-0}" -lt 1 ]; then
    echo "probe_D468: контроль — прибор не назвал НИ ОДНОГО носителя рода G вне scripts/probes/, вывод не о том:" >&2
    cat "$OUT" >&2
    exit 2
fi

if grep -q '^  · scripts/probes/' "$OUT"; then
    echo "probe_D468: дефект — фикстурная строка пробы корня названа носителем рода G:" >&2
    grep '^  · scripts/probes/' "$OUT" >&2
    exit 1
fi
exit 0
