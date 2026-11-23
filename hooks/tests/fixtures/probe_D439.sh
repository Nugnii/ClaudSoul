#!/usr/bin/env bash
# СУДИТ: hooks/impact-inject.sh
# probe_D439.sh — «Проверка» пункта D439 (и D1114): на коде 3 прибора карты (`project-graph.py` — «кэш стар»)
# `hooks/impact-inject.sh` не подделывает свежесть кэша: не говорит «в карте его не было, внесён» про узел, который
# в карте есть, и не освежает mtime кэша без пересборки (`--touch`). С D1009 хук сам запускает пересборку фоном, и
# честная пересборка законно переписывает кэш — поэтому подделка от пересборки отличается по СОДЕРЖИМОМУ: новое
# ребро учёта честная пересборка вносит в кэш, `--touch` — нет.
# Результат: код 3 называет устаревшую карту (молчание неотличимо от «зависимостей нет»), синхронная часть хука на
# обоих маршрутах (Bash и Edit) mtime кэша не трогает, а фон оставляет кэш либо нетронутым, либо пересобранным с
# новым ребром; на ДЕЙСТВИТЕЛЬНО новом узле при свежей карте сообщение о новизне законно (положительный контроль).
# Проверка результата: bash hooks/tests/fixtures/probe_D439.sh → 0; 1 — подделка свежести или ложное «не было»;
# 2 — рамка не собралась (в том числе фон не пересобрал кэш, и нога фона не судила).
#
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставит копию с
# починкой). Хук сам вычисляет ROOT по `cwd` из входного JSON (git-корень песочницы), а не
# по месту, где лежит его файл, — поэтому файл хука зовётся ПРЯМО из MECH, а
# project-graph.py копируется В песочницу (там его ищет хук по своему ROOT).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/impact-inject.sh"
[ -f "$HOOK" ] || { echo "probe_D439: нет $HOOK" >&2; exit 2; }
[ -f "$MECH/scripts/project-graph.py" ] || { echo "probe_D439: нет $MECH/scripts/project-graph.py" >&2; exit 2; }
[ -f "$MECH/hooks/paths-lib.sh" ] || { echo "probe_D439: нет $MECH/hooks/paths-lib.sh" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D439: нет git" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "probe_D439: нет jq" >&2; exit 2; }

T=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/scripts" "$P/hooks" "$P/.claude-docs" "$P/mcp-server/visualization"
cp "$MECH/scripts/project-graph.py" "$P/scripts/" || exit 2
STATE_DIR="$T/state"; mkdir -p "$STATE_DIR" "$T/home" "$T/lessons"
# `project-graph.py` читает CLAUDSOUL_REPO КАК СВОЙ КОРЕНЬ, если он задан в окружении
# (scripts/project-graph.py:51) — здесь он ОБЯЗАН указывать на песочницу ($P), а не на MECH,
# иначе сборка кэша и вызовы прибора внутри хука уйдут в чужое дерево.
export HOME="$T/home" LESSONS_DIR="$T/lessons" PYTHONDONTWRITEBYTECODE=1 CLAUDSOUL_REPO="$P"

printf '#!/usr/bin/env bash\necho one\n' > "$P/hooks/alpha.sh"
printf '#!/usr/bin/env bash\nsource hooks/alpha.sh\n' > "$P/hooks/beta.sh"
printf '# path\tsha\tdeps\tdocs\ttests\tnames\nhooks/alpha.sh\ta\t\t\t\t\nhooks/beta.sh\tb\thooks/alpha.sh\t\t\t\n' \
    > "$P/.claude-docs/dep-index.tsv"
( cd "$P" && git init -q . && git add -A && git -c user.email=p@p -c user.name=p commit -qm i ) >/dev/null 2>&1 \
    || { echo "probe_D439: git-песочница не поднялась" >&2; exit 2; }

# Свежий кэш — alpha.sh в карте ЕСТЬ (у него зависимый beta.sh).
( cd "$P" && python3 scripts/project-graph.py >/dev/null 2>&1 ) \
    || { echo "probe_D439: сборка кэша не удалась" >&2; exit 2; }
CACHE="$P/mcp-server/visualization/project-graph-data.json"
[ -s "$CACHE" ] || { echo "probe_D439: кэш не записан — рамка не собралась" >&2; exit 2; }

run_bash() {  # run_bash <session>
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s"}' "$1" "$P" \
        | env STATE_DIR="$STATE_DIR" PATHS_LIB="$MECH/hooks/paths-lib.sh" LESSONS_DIR="$T/lessons" \
              bash "$HOOK" 2>/dev/null
}

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: карта СВЕЖА, узел ДЕЙСТВИТЕЛЬНО новый — сообщение о новизне законно.
printf '#!/usr/bin/env bash\necho fresh-new\n' > "$P/hooks/fresh.sh"
OC=$(run_bash pc)
case "$OC" in
    *"hooks/fresh.sh — в карте его не было"*) : ;;
    *) echo "probe_D439: положительный контроль пуст — новый узел на свежей карте не назван новым (вывод: ${OC:0:200})" >&2
       exit 2 ;;
esac
rm -f "$P/hooks/fresh.sh"

# ДЕФЕКТ: учёт становится НОВЕЕ уже записанного кэша (код 3, «кэш стар»); alpha.sh — узел, который в карте ЕСТЬ (у
# него зависимый beta.sh), и правится ОН. В учёт входит НОВОЕ ребро — gamma.sh зависит от alpha.sh: честная
# пересборка внесёт его в кэш, подделка свежести (`--touch`) — нет.
sleep 1   # разрешение mtime секундное — учёт должен стать новее уже записанного кэша
printf '#!/usr/bin/env bash\nsource hooks/alpha.sh\n' > "$P/hooks/gamma.sh"
( cd "$P" && git add hooks/gamma.sh && git -c user.email=p@p -c user.name=p commit -qm g ) >/dev/null 2>&1 \
    || { echo "probe_D439: gamma.sh не закоммичен" >&2; exit 2; }
printf '# path\tsha\tdeps\tdocs\ttests\tnames\nhooks/alpha.sh\ta\t\t\t\t\nhooks/beta.sh\tb\thooks/alpha.sh\t\t\t\nhooks/gamma.sh\tg\thooks/alpha.sh\t\t\t\n' \
    > "$P/.claude-docs/dep-index.tsv"
grep -q 'hooks/gamma.sh' "$CACHE" && { echo "probe_D439: gamma.sh уже в кэше — рамка не различит пересборку" >&2; exit 2; }
mtime() { python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$CACHE"; }
CACHE_MT=$(mtime)
printf '#!/usr/bin/env bash\necho one\n# правка\n' > "$P/hooks/alpha.sh"
run_edit() {  # run_edit <session> — маршрут Edit на alpha.sh
    printf '{"session_id":"%s","tool_name":"Edit","hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"file_path":"%s"}}' \
        "$1" "$P" "$P/hooks/alpha.sh" \
        | env STATE_DIR="$STATE_DIR" PATHS_LIB="$MECH/hooks/paths-lib.sh" LESSONS_DIR="$T/lessons" bash "$HOOK" 2>/dev/null
}
# ФОН ЖДЁТСЯ ДО КОНЦА, А НЕ ГОНКОЙ (D1114, скептик M2). Прежде проба читала mtime сразу после хука и зеленела, пока
# успевала раньше фона: «зелёная до f1f7a524» была выигранной гонкой. Ждём, пока держится чужой замок пересборки, и не
# меньше 2 с — фон стартует за миллисекунды; потолок 30 с.
wait_bg() {  # wait_bg [свой замок — его не ждать]
    local i=0 l busy
    while [ "$i" -lt 120 ]; do
        sleep 0.25; i=$((i + 1)); busy=0
        for l in "$STATE_DIR"/impact-inject-refresh-*.lock; do
            [ -d "$l" ] && [ "$l" != "${1:-}" ] && busy=1
        done
        [ "$busy" -eq 0 ] && [ "$i" -ge 8 ] && return 0
    done
}
said_stale() {  # said_stale <маршрут> <вывод> — ложное «не было» и молчание отбиваются
    case "$2" in *"hooks/alpha.sh — в карте его не было"*)
        echo "probe_D439: код 3 (кэш стар), маршрут $1: ложное «в карте его не было» про hooks/alpha.sh — узел в карте ЕСТЬ; вывод: ${2:0:300}" >&2
        exit 1 ;;
    esac
    # Молчание тоже не принимается: оно неотличимо от настоящего «зависимостей нет» (корень R6).
    case "$2" in *устаре*) : ;; *)
        echo "probe_D439: код 3 (кэш стар), маршрут $1: устаревшая карта не названа — вывод пуст или про другое; вывод: ${2:0:300}" >&2
        exit 1 ;;
    esac
}
# НОГА 1 — СИНХРОННАЯ ЧАСТЬ ХУКА, оба маршрута. Замок пересборки держит проба (ключ тот же, что `_II_KEY` хука, живой
# PID — свой): фон уходит ни с чем, и сдвинуть mtime кэша может только сам хук. Ключ хука сменится — замок не удержит,
# фон пересоберёт кэш, и после ожидания mtime сдвинут: красно, а не молча.
_K="$STATE_DIR/impact-inject-refresh-$(printf '%s' "$P" | cksum | awk '{print $1}')"
mkdir -p "$_K.lock" && printf '%s probe\n' "$$" > "$_K.lock/owner" || { echo "probe_D439: замок пересборки не взят" >&2; exit 2; }
OD=$(run_bash defect); OE=$(run_edit defect-edit)
wait_bg "$_K.lock"
said_stale Bash "$OD"; said_stale Edit "$OE"
if [ "$(mtime)" != "$CACHE_MT" ]; then
    echo "probe_D439: mtime кэша сдвинут за время хука при замке пересборки у пробы (--touch либо пересборка мимо замка)" >&2
    exit 1
fi
# НОГА 2 — ФОН. Замок снят, хук запускает пересборку фоном; после её конца кэш либо пересобран честно (новое ребро в
# нём), либо подделан: свежий mtime при старом содержимом (`--touch` вместо `--refresh` в фоне — скептик D1114, M1).
rm -f "$_K.lock/owner"; rmdir "$_K.lock" 2>/dev/null
run_bash defect-bg >/dev/null
wait_bg
if [ "$(mtime)" = "$CACHE_MT" ]; then
    echo "probe_D439: фон не тронул кэш — нога фона не судила (пересборка не запущена либо упала)" >&2
    exit 2
fi
grep -q 'hooks/gamma.sh' "$CACHE" || {
    echo "probe_D439: кэш освежён фоном, а нового ребра в нём нет — подделка свежести" >&2
    exit 1; }
exit 0
