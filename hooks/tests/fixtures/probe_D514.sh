#!/usr/bin/env bash
# СУДИТ: hooks/session-collector.sh hooks/completion-gate.sh
# probe_D514.sh — код из папки сессии на Stop не исполняется (D514, брат D244).
#
# D244 закрыл один путь: completion-gate не исполняет «Проверку» из бэклога, найденного по cwd.
# Скептик правки D512 (4 октября 2026) воспроизвёл два оставшихся:
#   A. `hooks/session-collector.sh` исполняет `scripts/backlog-refresh-readings.sh` проекта,
#      найденного подъёмом от папки сессии, — достаточно открыть чужой склонированный каталог;
#   B. `hooks/completion-gate.sh` принимает ОТНОСИТЕЛЬНЫЙ `CG_LOCAL_BACKLOG` и читает его от
#      папки, где запущен хук, то есть снова от сессии.
# Скептик починки (тот же день) добавил ещё два:
#   A2. признак назван, но указывает на ДРУГОЙ проект — скрипт проекта сессии исполняться
#       не должен и тогда (возврат дефекта A в форме «признак где-то есть»);
#   C. `git log` в папке сессии исполняет программу из настроек чужого репозитория
#      (`log.showSignature` + `gpg.program`) — `hooks/activity-flush-lib.sh`.
#
# Судит дерево `CLAUDSOUL_REPO` (по умолчанию — то, где лежит проба), в песочнице.
# Код: 0 — ни один путь не исполнил чужой код; 1 — исполнил (носители названы);
#      2 — проба здесь не исполнима либо контроль мёртв (хук не дошёл до предмета).
set -uo pipefail
# Пробу зовёт «Проверка» пункта, то есть гейт и архиватор: их ограда вложенного прогона
# заглушила бы гейт в песочнице. Кольца песочница не даёт — её команды суть `touch`.
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX CG_LOCAL_BACKLOG

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
COLLECTOR="$REPO/hooks/session-collector.sh"
GATE="$REPO/hooks/completion-gate.sh"
[ -f "$COLLECTOR" ] && [ -f "$GATE" ] || { echo "проба не исполнима: нет хуков в $REPO"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "проба не исполнима: нет jq"; exit 2; }
# Что сказал хук, читается по всем трём каналам (D1304, D1309): о долге проекта сборщик говорит в канал проекта.
. "$REPO/hooks/tests/alerts-read.sh" 2>/dev/null || { echo "проба не исполнима: нет hooks/tests/alerts-read.sh в $REPO"; exit 2; }

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
BAD=""

# --- A: скрипт проекта, найденного по папке сессии ---
mkdir -p "$W/a/st" "$W/a/clone/.git" "$W/a/clone/scripts"
printf '%s\n' '# BACKLOG' '' '- ☐ **L1** открытый пункт' > "$W/a/clone/BACKLOG.md"
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/a/ran\"" > "$W/a/clone/scripts/backlog-refresh-readings.sh"
( cd "$W/a/clone" && jq -cn --arg c "$W/a/clone" '{session_id:"d514a", cwd:$c}' \
    | STATE_DIR="$W/a/st" CLAUDSOUL_BACKLOG="$W/none.md" CLAUDSOUL_MEASURE_DUE="$W/no.sh" \
      BACKLOG_READINGS_EVERY_TURNS=1 bash "$COLLECTOR" >/dev/null 2>&1 )
# контроль: хук дошёл до бэклога проекта — назвал его открытый пункт
grep -q 'открытых пункт' <<< "$(alerts_of "$W/a/st")" \
    || { echo "контроль A мёртв: Stop-хук не назвал долг проекта"; exit 2; }
[ -e "$W/a/ran" ] && BAD="${BAD}A (скрипт пересчёта показаний проекта из папки сессии) "

# --- A2: признак указывает на другой проект — скрипт проекта сессии молчит ---
mkdir -p "$W/a2/st" "$W/a2/clone/.git" "$W/a2/clone/scripts" "$W/a2/other"
printf '%s\n' '# BACKLOG' '' '- ☐ **L1** открытый пункт' > "$W/a2/clone/BACKLOG.md"
printf '%s\n' '# BACKLOG' '' '- ☐ **M1** пункт названного проекта' > "$W/a2/other/BACKLOG.md"
printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/a2/ran\"" > "$W/a2/clone/scripts/backlog-refresh-readings.sh"
( cd "$W/a2/clone" && jq -cn --arg c "$W/a2/clone" '{session_id:"d514a2", cwd:$c}' \
    | STATE_DIR="$W/a2/st" CLAUDSOUL_BACKLOG="$W/none.md" CLAUDSOUL_MEASURE_DUE="$W/no.sh" \
      CG_LOCAL_BACKLOG="$W/a2/other/BACKLOG.md" BACKLOG_READINGS_EVERY_TURNS=1 bash "$COLLECTOR" >/dev/null 2>&1 )
grep -q 'открытых пункт' <<< "$(alerts_of "$W/a2/st")" \
    || { echo "контроль A2 мёртв: Stop-хук не назвал долг названного проекта"; exit 2; }
[ -e "$W/a2/ran" ] && BAD="${BAD}A2 (скрипт проекта сессии при признаке, названном для другого проекта) "

# --- C: git в папке сессии и программа из настроек чужого репозитория ---
if command -v git >/dev/null 2>&1; then
    mkdir -p "$W/c/st" "$W/c/home" "$W/c/sessions" "$W/c/evil"
    printf '%s\n' '#!/usr/bin/env bash' "touch \"$W/c/ran\"" 'exit 1' > "$W/c/fakegpg.sh"; chmod +x "$W/c/fakegpg.sh"
    (
        cd "$W/c/evil" && HOME="$W/c/home" git init -q . >/dev/null 2>&1 || exit 2
        git config log.showSignature true && git config gpg.program "$W/c/fakegpg.sh" || exit 2
        _tree=$(git hash-object -t tree -w /dev/null) || exit 2
        # подписанный коммит собран руками (заголовок gpgsig), дата — 2100 год: автор ставит её
        # сам, и окно «за 4 часа» она проходит всегда
        printf 'tree %s\nauthor A <a@example.com> 4102444800 +0000\ncommitter A <a@example.com> 4102444800 +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n ZmFrZQ==\n -----END PGP SIGNATURE-----\n\nsigned\n' "$_tree" > "$W/c/commit.txt"
        _c=$(git hash-object -t commit -w "$W/c/commit.txt") && git update-ref HEAD "$_c"
    ) || { echo "проба не исполнима: git не собрал песочный репозиторий"; exit 2; }
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"}}' \
        '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}' > "$W/c/tr.jsonl"
    ( cd "$W/c/evil" && jq -cn --arg c "$W/c/evil" --arg t "$W/c/tr.jsonl" '{session_id:"d514c", cwd:$c, transcript_path:$t}' \
        | HOME="$W/c/home" SR_SESSIONS_DIR="$W/c/sessions" STATE_DIR="$W/c/st" CLAUDSOUL_ROOT="$REPO" \
          CLAUDSOUL_BACKLOG="$W/none.md" CLAUDSOUL_MEASURE_DUE="$W/no.sh" bash "$COLLECTOR" >/dev/null 2>&1 )
    # контроль: запись активности хода дошла до расшифровки — счёт её вызовов лежит в состоянии
    ls "$W/c/st"/transcript-fold-activity-stats-* >/dev/null 2>&1 \
        || { echo "контроль C мёртв: Stop-хук не дошёл до записи активности хода"; exit 2; }
    [ -e "$W/c/ran" ] && BAD="${BAD}C (программа из настроек git чужого репозитория) "
fi

# --- B: относительный путь в признаке согласия у гейта ---
_gate() {   # <dir> <значение CG_LOCAL_BACKLOG> — один Stop гейта из папки проекта
    mkdir -p "$1/st" "$1/proj/.git"
    printf '%s\n' '# BACKLOG' '' '## Раздел' '' '- ☑ **L2** закрытый' '  **Результат.** Есть.' \
        "  **Проверка.** \`touch $1/ran; true\` → 0" > "$1/proj/BACKLOG.md"
    ( cd "$1/proj" && jq -cn --arg c "$1/proj" '{session_id:"d514b", cwd:$c}' \
        | STATE_DIR="$1/st" CG_BACKLOG="$W/none.md" CG_LOCAL_BACKLOG="$2" bash "$GATE" >/dev/null 2>&1 )
}
# контроль: по АБСОЛЮТНОМУ пути (акт владельца) гейт «Проверку» исполняет — рамка пробы жива
_gate "$W/bc" "$W/bc/proj/BACKLOG.md"
[ -e "$W/bc/ran" ] || { echo "контроль B мёртв: гейт не исполнил «Проверку» по абсолютному пути"; exit 2; }
_gate "$W/b" "BACKLOG.md"
[ -e "$W/b/ran" ] && BAD="${BAD}B (относительный CG_LOCAL_BACKLOG у completion-gate) "

if [ -n "$BAD" ]; then echo "код из папки сессии исполнен: ${BAD}"; exit 1; fi
echo "код из папки сессии не исполнен: путей проверено 4"
exit 0
