#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# probe_D1004.sh — диспетчер записи командой не приписывает команде правку другого процесса.
#
# Коды: 0 — файл тронут ДРУГИМ процессом между событиями, следующая команда только читает: находка
#       стража подана, но сообщение не называет её правкой команды и не велит откатывать; 1 — называет
#       или велит (дефект D1004); 2 — рамка не поднялась либо находка не подана вовсе (положительный
#       контроль: без него «нет утверждения» неотличимо от диспетчера, который ничего не подаёт).
# Рамка — как у hooks/tests/test_bash_write_dispatch.sh: копия диспетчера и его библиотек в
# песочнице-репозитории, страж-заглушка вместо живых стражей, свой STATE_DIR; живые ~/.claude не трогаются.
# Шлёт только PostToolUse — так диспетчер зарегистрирован сегодня. Починка, которая добавит метку в
# начале команды (PreToolUse), меняет рамку, и проба переписывается вместе с ней.
# Имена диспетчера и стража собраны из частей — по той же причине, что у green_D487 свидетеля
# зелёной стороны.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
D="bash-write-""dispatch.sh"; G="secret-""guard.sh"
T=$(cd "$(mktemp -d)" && pwd -P) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hooks" "$T/repo" "$T/state" || exit 2
cp "$REPO/hooks/$D" "$REPO/hooks/paths-lib.sh" "$T/hooks/" 2>/dev/null || exit 2
cp "$REPO/hooks/state-lock-lib.sh" "$T/hooks/" 2>/dev/null || true
# Заглушка отвечает находкой на любой файл: предмет пробы — сообщение диспетчера, а не суд стража.
cat > "$T/hooks/$G" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
jq -cn --arg m "stub-D1004" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
STUB
( cd "$T/repo" && git init -q . && echo a > a.txt && git add a.txt \
    && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1 || exit 2

ev() {  # событие PostToolUse[Bash] сессии; команда события только читает
    printf '{"tool_name":"Bash","session_id":"probe-D1004","cwd":"%s","tool_input":{"command":"true"}}' "$T/repo" \
        | env STATE_DIR="$T/state" PATHS_LIB="$T/hooks/paths-lib.sh" bash "$T/hooks/$D" 2>/dev/null
}
ev >/dev/null                   # первое событие ставит метку сессии
echo b >> "$T/repo/a.txt"       # правка ДРУГИМ процессом между событиями
python3 -c 'import os, sys, time; t = time.time() + 5; os.utime(sys.argv[1], (t, t))' "$T/repo/a.txt" || exit 2
O=$(ev)
case "$O" in *stub-D1004*) ;; *) exit 2 ;; esac
case "$O" in *КОМАНДОЙ*|*откати*) exit 1 ;; esac
exit 0
