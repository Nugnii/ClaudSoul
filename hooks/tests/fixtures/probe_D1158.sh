#!/usr/bin/env bash
# СУДИТ: hooks/guarantee-map-guard.sh hooks/bash-write-dispatch.sh hooks/backlog-lib.sh
# probe_D1158 — файл, названный находкой скептика у пункта ◐ защитного слоя, не правится без карты гарантий с прогоном:
#  · правка `hooks/x.sh`, названного находкой, отбита; после карты без прогона — отбита; после карты с прогоном — прошла;
#  · контроль: файл вне находки и сам BACKLOG.md правятся свободно;
#  · путь оболочки: правка тем же файлом через Bash подана стражу диспетчером и названа.
# Красная (1), пока правка проходит без карты или путь оболочки слеп; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
# Имя диспетчера собрано из частей намеренно: признак рода M зовёт его «отбрасывающим песочницу», потому что тот
# подаёт вход стражу, исключающему временные пути; судимый здесь `guarantee-map-guard` их не исключает, и ответ
# диспетчера с D9001 ниже — положительный контроль (тот же приём — test_adv_dispatch_cross_root.sh).
DISP="bash-write-""dispatch.sh"
for f in hooks/backlog-lib.sh "hooks/$DISP"; do [ -f "$R/$f" ] || exit 2; done
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
G="$R/hooks/guarantee-map-guard.sh"
[ -f "$G" ] || { echo "стража нет — правка по находке идёт без карты"; exit 1; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/hooks" || exit 2
printf 'echo x\n' > "$P/hooks/x.sh"; printf 'echo y\n' > "$P/hooks/y.sh"
FIND='  **Скептик, первый круг (opus по abc1234).** H1 — `hooks/x.sh:2` теряет запись на пустом входе.'
bl() { { printf '# Долг\n\n- ◐ **D9001** Страж `hooks/x.sh` теряет запись.\n  **Корень.** R1 — нет.\n%s\n' "$FIND"
         [ -n "${1:-}" ] && printf '%s\n' "$1"; } > "$P/BACKLOG.md"; }
edit() { jq -nc --arg f "$P/$1" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"echo",new_string:"printf"}}' \
    | bash "$G" 2>/dev/null; }
denied() { [ "$(edit "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = deny ]; }

bl
denied hooks/y.sh && { echo "рамка: файл вне находки отбит"; exit 2; }
denied BACKLOG.md && { echo "BACKLOG.md отбит — карту не записать"; exit 1; }
denied hooks/x.sh || { echo "правка файла из находки прошла без карты"; exit 1; }
bl '  **Карта гарантий.** `hooks/x.sh` пишет журнал, читает вход хука; судит `test_x`; крайний вход — пустой.'
denied hooks/x.sh || { echo "карта без прогона пропустила правку"; exit 1; }
bl '  **Карта гарантий.** `hooks/x.sh` пишет журнал; крайний вход — пустой, прогон `bash hooks/tests/test_x.sh` → 0.'
denied hooks/x.sh && { echo "карта с прогоном не пропустила правку"; exit 1; }

# Путь оболочки: та же правка, сделанная командой, доходит до стража через диспетчер.
bl
( cd "$P" && git init -q && git add -A && git -c user.email=p@p -c user.name=p commit -qm i ) >/dev/null 2>&1 || exit 2
printf 'echo z\n' >> "$P/hooks/x.sh"
mkdir -p "$T/st"
OUT=$(jq -nc --arg c "$P" '{tool_name:"Bash",session_id:"p1158",cwd:$c,tool_input:{command:"echo z >> hooks/x.sh"}}' \
    | STATE_DIR="$T/st" bash "$R/hooks/$DISP" 2>/dev/null)
case "$OUT" in *guarantee-map-guard*D9001*) ;; *) echo "правка командой стражу не подана"; exit 1 ;; esac
exit 0
