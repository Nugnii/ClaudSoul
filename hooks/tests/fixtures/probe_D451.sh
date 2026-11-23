#!/usr/bin/env bash
# probe_D451.sh — проба пункта D451: снимок мира у `hooks/rework-detector.sh` не отделялся по
#                 АКТОРУ, потому что ветка суффикса стояла на ИМЕНИ расшифровки (`agent-*` в
#                 basename `transcript_path`), а харнесс кладёт туда путь родителя всегда.
# Результат: вызов субагента пишет свой снимок `rework-world-<SID>.agent-<id>.txt`, вызов
#            родителя — свой `rework-world-<SID>.txt`; ИМЯ расшифровки актором не считается.
# Проверка результата: bash hooks/tests/fixtures/probe_D451.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась.
#
# ЛОЖНЫЙ НОСИТЕЛЬ РОДА M, замерено 18 сентября 2026. Страж прироста назвал эту пробу
# носителем («песочница голым mktemp -d, корня ${HOME} рядом нет»): у судимого механизма
# есть фильтр `*/tmp/*` (rework-detector.sh:180). Фильтр относится к ЦЕЛЯМ ПРАВКИ,
# извлечённым из текста команды, а в песочнице пробы лежит только STATE_DIR со снимками —
# под фильтр он не попадает. Проверено поведением, а не рассуждением: против дореформенной
# ревизии 5792b0a проба даёт 1 и на macOS (/var/folders), и под TMPDIR=/tmp (как на Linux).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/rework-detector.sh"
[ -f "$HOOK" ] || { echo "probe_D451: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D451: нет jq" >&2; exit 2; }
T=$(cd "$(mktemp -d)" && pwd -P) || { echo "probe_D451: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
S="$T/state"; mkdir -p "$S"
# Мир вызова — свой чистый репозиторий, поле `cwd` у каждого вызова оболочки (D1287, скептик opus M2): без поля детектор
# судил каталог процесса, и вне git контроль ниже отвечал 2 при исправном механизме.
G="$T/w"; mkdir -p "$G"
( cd "$G" && git init -q && printf 'a\n' > f.sh && git add f.sh && git -c user.name=p -c user.email=p@p commit -qm 0 ) \
    || { echo "probe_D451: репозиторий мира не собран" >&2; exit 2; }

# Журнал сессии обязателен: без него ветка Bash выходит до снимка мира.
jq -cn '{session_id:"p451", tool_name:"Edit", tool_input:{file_path:"/repo/x.sh"}}' \
  | STATE_DIR="$S" bash "$HOOK" >/dev/null 2>&1
[ -f "$S/rework-p451.jsonl" ] || { echo "probe_D451: журнал сессии не создан — рамка не собралась" >&2; exit 2; }

run_as() {  # run_as <agent_id|пусто> [transcript_path]
    jq -cn --arg a "${1:-}" --arg t "${2:-}" --arg d "$G" \
        '{session_id:"p451", tool_name:"Bash", cwd:$d, tool_input:{command:"bash t.sh"}}
         + (if $a == "" then {} else {agent_id:$a, agent_type:"general-purpose"} end)
         + (if $t == "" then {} else {transcript_path:$t} end)' \
      | STATE_DIR="$S" bash "$HOOK" >/dev/null 2>&1
}

# Положительный контроль: вызов родителя обязан дать снимок. Иначе судить нечем — механизм
# мог быть выпотрошен, и «нет файла субагента» ничего не значило бы.
run_as ""
[ -f "$S/rework-world-p451.txt" ] || { echo "probe_D451: контроль — снимок родителя не создан" >&2; exit 2; }

# ЖУРНАЛ АКТОРА ГОТОВИТСЯ ОТДЕЛЬНО (23 сентября 2026). Ветка Bash выходит до снимка, если у
# АКТОРА нет своего журнала правок, — ровно как у родителя выше. Прежде проба готовила журнал
# только родителю и ждала снимок субагента: рамка требовала невозможного, и проба краснела на
# ИСПРАВНОМ механизме. Проверено прямым прогоном: субагент со своим журналом получает
# `rework-world-<SID>.agent-<id>.txt`, то есть закрытие пункта держится.
jq -cn '{session_id:"p451", tool_name:"Edit", tool_input:{file_path:"/repo/y.sh"},
         agent_id:"abc123", agent_type:"general-purpose"}' \
  | STATE_DIR="$S" bash "$HOOK" >/dev/null 2>&1
# Неспособность завести журнал АКТОРА — это и есть отсутствие отделения, то есть предмет
# пункта, а не срыв рамки: на дореформенной ревизии 5792b0a механизм ведёт один журнал
# на всех, и проба обязана сказать «дефект», а не «судить нечем» (проверено прогоном
# на той ревизии: до уточнения кода она отвечала 2).
[ -f "$S/rework-p451.agent-abc123.jsonl" ] || { echo "probe_D451: дефект — журнал субагента не заведён, правки акторов в одном журнале" >&2; exit 1; }

# Суд 1: вызов субагента пишет ОТДЕЛЬНЫЙ снимок.
run_as abc123
if [ ! -f "$S/rework-world-p451.agent-abc123.txt" ]; then
    echo "probe_D451: дефект — снимок субагента не отделён, правки акторов в одном файле" >&2
    exit 1
fi

# Суд 2: ИМЯ расшифровки актором не считается — форма, которой харнесс не производит.
rm -f "$S/rework-world-p451.txt"
run_as "" "/x/agent-looks-like-one.jsonl"
if [ ! -f "$S/rework-world-p451.txt" ]; then
    echo "probe_D451: дефект — имя agent-*.jsonl без поля увело снимок родителя в чужой файл" >&2
    exit 1
fi
exit 0
