#!/usr/bin/env bash
# СУДИТ: hooks/revert-signal.sh hooks/rework-detector.sh
# probe_D520.sh — сигналы переработки не горят на свидетеле зелёной стороны (D520).
#
# `hooks/tests/test_backlog_green_side.sh` — реестр фикстур: каждый пункт долга дописывает в него
# свою `green_<ID>`, и файл входит в 21 из 60 последних fix-коммитов (замер 6 октября 2026). Повод
# «повторный hotfix» (revert-signal) и «правится N-й раз» (rework-detector) на нём горят по
# устройству — как горели бы на CHANGELOG и BACKLOG, которые оба детектора уже исключают.
#
# Контроли: тот же сценарий на обычном файле `hooks/x.sh` — оба сигнала горят; иначе код 2.
# Код: 0 — на свидетеле сигналы молчат; 1 — горят; 2 — проба не исполнима либо контроль мёртв.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
RS="$REPO/hooks/revert-signal.sh"; RW="$REPO/hooks/rework-detector.sh"
for _f in "$RS" "$RW"; do [ -f "$_f" ] || { echo "проба не исполнима: нет $_f"; exit 2; }; done
for _t in jq git; do command -v "$_t" >/dev/null 2>&1 || { echo "проба не исполнима: нет $_t"; exit 2; }; done

# Песочница с корнем ${HOME}: rework-detector отбрасывает пути `*/tmp/*` (род M). Детекторы зовутся
# без CLAUDSOUL_REPO, CLAUDE_HOME и BACKLOG_FILE: адрес во временном каталоге `rc_env_is_real`
# (root-cause-lib) читает как тест и поводов не пишет, а свидетель зелёной стороны зовёт пробу так.
W=$(mktemp -d "${HOME}/.probeD520.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
N=0

_hotfix() {   # <файл в репозитории> → 0 повод hotfix-repeat заведён, 1 нет, 2 рамка не собралась
    local r st f="$1"; N=$((N+1)); r="$W/r$N"; st="$W/st$N"
    mkdir -p "$r/$(dirname "$f")" "$st" && git -C "$r" init -q \
        && git -C "$r" config user.email t@e && git -C "$r" config user.name t || return 2
    printf 'a\n' > "$r/$f"; { git -C "$r" add -A && git -C "$r" commit -qm 'fix(x): раз'; } >/dev/null 2>&1 || return 2
    printf 'b\n' > "$r/$f"; { git -C "$r" add -A && git -C "$r" commit -qm 'fix(x): два'; } >/dev/null 2>&1 || return 2
    jq -cn --arg d "$r" '{session_id:"d520", tool_name:"Bash", cwd:$d, tool_input:{command:"git commit -m \"fix(x): три\""}}' \
      | ( cd "$r" && env -u CLAUDSOUL_REPO -u CLAUDE_HOME -u BACKLOG_FILE STATE_DIR="$st" bash "$RS" >/dev/null 2>&1 )
    grep -qx 'hotfix-repeat' <<< "$(jq -r '.kind' "$st/pending-events.jsonl" 2>/dev/null)"
}
_rework() {   # <путь файла> → 0 на третьей правке названа «Переработка», 1 нет
    local st out="" sid; N=$((N+1)); st="$W/rw$N"; sid="d520rw$N"
    mkdir -p "$st" || return 2
    for _i in 1 2 3; do
        out=$(jq -cn --arg s "$sid" --arg p "$1" '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$p}}' \
            | env -u CLAUDSOUL_REPO -u CLAUDE_HOME -u BACKLOG_FILE STATE_DIR="$st" bash "$RW" 2>/dev/null)
        jq -cn --arg s "$sid" '{session_id:$s, tool_name:"Bash", tool_input:{command:"bash test.sh"}}' \
            | env -u CLAUDSOUL_REPO -u CLAUDE_HOME -u BACKLOG_FILE STATE_DIR="$st" bash "$RW" >/dev/null 2>&1
    done
    grep -qF 'Переработка' <<< "$out"
}

# контроли: обычный файл — оба сигнала горят
_hotfix hooks/x.sh; rc=$?
[ "$rc" = 0 ] || { echo "контроль мёртв: повторный hotfix обычного файла не заведён (код $rc)"; exit 2; }
_rework "$W/proj/hooks/x.sh"; rc=$?
[ "$rc" = 0 ] || { echo "контроль мёртв: переработка обычного файла не названа (код $rc)"; exit 2; }

BAD=""
_hotfix hooks/tests/test_backlog_green_side.sh; rc=$?
[ "$rc" = 2 ] && { echo "проба не исполнима: рамка hotfix не собралась"; exit 2; }
[ "$rc" = 0 ] && BAD="${BAD}hotfix-repeat "
_rework "$W/proj/hooks/tests/test_backlog_green_side.sh"; rc=$?
[ "$rc" = 2 ] && { echo "проба не исполнима: рамка переработки не собралась"; exit 2; }
[ "$rc" = 0 ] && BAD="${BAD}переработка "
if [ -n "$BAD" ]; then echo "сигнал горит на свидетеле зелёной стороны: ${BAD}"; exit 1; fi
echo "на свидетеле зелёной стороны сигналы молчат: случаев проверено 2"
exit 0
