#!/usr/bin/env bash
set -u
# СУДИТ: hooks/command-scope-lib.sh hooks/lib/write_targets.py hooks/five-whys-gate.sh
# probe_D1215 — признак «вызов пишет» (`is_write_command`) узнаёт запись формами, встреченными на двух корпусах
#   расшифровок (`curl -o`/`-O`/`-c`/`-D`, `wget -O` и `wget` без `-O`, `git stash`, `git worktree add|move|remove|prune`,
#   `git apply`, `git checkout -- <пути>`, `git restore`, `chmod`, `find -delete` и со скобками `\( … \)`, `tar -x`, питон
#   `os.remove`/`os.unlink`/`Path.unlink()`/`shutil.rmtree`; `chmod` в команде, которую разбирает запасной разбор), и не принимает за
#   запись их чтения-двойники (`curl -s`, `curl -XPOST`, `-H'…'`, `-b`, `wget -qO-`, `git stash list|show`, `git worktree list`,
#   `git apply --check|--stat`, `find` без `-delete` и со скобками, `tar -t`, `git diff --`, `command -v chmod`).
#   Сквозь стража: полоса упавших команд и `git stash` — отказ, `git stash list` — тишина.
#   0 — все формы судятся верно; 1 — запись названа чтением или чтение записью; 2 — нет библиотеки, разбора или jq,
#   контроль (перенаправление — запись, `cat` — чтение) не прошёл.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
L="$PWD/hooks/command-scope-lib.sh"; H="$PWD/hooks/five-whys-gate.sh"
[ -f "$L" ] && [ -f "$H" ] && command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 2
# shellcheck source=/dev/null
. "$L" || exit 2
command -v is_write_command >/dev/null 2>&1 || exit 2
is_write_command 'echo x > hooks/x.sh' && ! is_write_command 'cat hooks/x.sh' || { echo "рамка: контроль признака не прошёл"; exit 2; }
WRITE=(
    'git stash' 'git stash -u' 'git stash pop' 'git -C sub stash push -m x'
    'curl -o hooks/x https://e.x/a' 'curl -sSLo hooks/x https://e.x/a' 'curl --output hooks/x https://e.x/a'
    'curl -sSLO https://e.x/a' 'curl -c jar.txt https://e.x/a' 'curl -sD hdr.txt https://e.x/a'
    'wget -O hooks/x https://e.x/a' 'wget https://e.x/a.tar.gz'
    'git worktree add ../w main' 'git worktree remove ../w' 'git worktree move ../w ../v' 'git worktree prune'
    'git apply p.diff' 'git apply --index p.diff' 'git checkout -- hooks/x.sh' 'git restore --staged hooks/x.sh'
    'chmod +x hooks/x.sh' 'chmod 755 hooks/x.sh' 'chmod -R u+w hooks'
    'find hooks -name "*.tmp" -delete' 'find . \( -name a -o -name b \) -delete' 'tar -xzf a.tgz' 'tar xf a.tar -C d'
    "python3 -c \"import os; os.remove('hooks/x')\"" "python3 -c \"import os; os.unlink('hooks/x')\""
    "python3 -c \"from pathlib import Path; Path('hooks/x').unlink()\""
    "python3 -c \"import shutil; shutil.rmtree('d')\"" "chmod +x hooks/x.sh; echo \$'x\\'y'"
)
READ=(
    'curl -s https://e.x/a' 'curl -sS https://e.x/a | jq .' 'curl -o /dev/null -w %{http_code} https://e.x/a'
    'curl -XPOST https://e.x/a' "curl -H'Accept: application/json' https://e.x/a" 'curl -b jar.txt https://e.x/a'
    'curl -o - https://e.x/a' 'wget -qO- https://e.x/a' 'wget -O - https://e.x/a' 'wget --spider https://e.x/a'
    'git stash list' 'git stash show -p' 'git worktree list' 'git apply --check p.diff' 'git apply --stat p.diff'
    'find hooks -name x' 'find . \( -name a -o -name b \) -print' 'tar -tzf a.tgz' 'git diff -- hooks/x.sh'
    'command -v chmod' 'grep -rn chmod hooks'
)
bad=0
for c in "${WRITE[@]}"; do is_write_command "$c" || { echo "запись названа чтением: $c"; bad=1; }; done
for c in "${READ[@]}"; do is_write_command "$c" && { echo "чтение названо записью: $c"; bad=1; }; done
# Скобка `\(`/`'('` — граница выражения `find`, а не корень поиска: цель — `hooks`, а не призрачный путь «_».
for c in 'find hooks \( -name a \) -delete' "find hooks '(' -name a ')' -delete"; do
    t=$(executable_change_targets "$c" | tr '\n' ' ')
    [ "$t" = "hooks " ] || { echo "корни find со скобкой — не «hooks»: [$t] у $c"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 1
# Сквозь стража: повод с правом на отказ (полоса) — запись `git stash` отбита, чтение `git stash list` проходит.
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
gate() {  # gate <случай> <команда> — решение стража на Bash-вызов при живой полосе
    mkdir -p "$W/$1" && printf '2' > "$W/$1/error_streak_fired_$1"
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}' \
        '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Правлю."}]}}' > "$W/$1/t.jsonl"
    jq -cn --arg s "$1" --arg p "$W/$1/t.jsonl" --arg d "$PWD" --arg c "$2" \
        '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
        | env -u FWG_STANDING STATE_DIR="$W/$1" bash "$H" 2>/dev/null > "$W/$1.out"
    # Молчание стража — пропуск: пустой stdout `jq` не печатает вовсе, и решение надо подставить, а не читать.
    [ -s "$W/$1.out" ] && jq -r '.hookSpecificOutput.permissionDecision // "allow"' "$W/$1.out" 2>/dev/null || echo allow
}
[ "$(gate ctl 'echo x > hooks/x.sh')" = deny ] || { echo "рамка: страж не отбил перенаправление при полосе"; exit 2; }
[ "$(gate st 'git stash')" = deny ] || { echo "страж пропустил git stash при живом поводе"; exit 1; }
[ "$(gate sl 'git stash list')" = allow ] || { echo "страж отбил git stash list — чтение"; exit 1; }
echo "запись узнаётся формами двух корпусов, чтения-двойники проходят"
exit 0
