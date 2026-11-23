#!/usr/bin/env bash
set -u
# СУДИТ: scripts/stop-context-restart.sh
# probe_D1237 — замер свойства харнесса на пустом журнале пробы показывает улики, а не догадку: подставной `claude`
#   печатает ответ в stdout, выходит с кодом 7 и хука Stop не зовёт — прибор (`--measure`) обязан напечатать этот ответ и
#   этот код по каждой ветке и не назвать причину, которой не видел («авторизация»), с кодом 2 («не выполнен»).
#   Рамка: подставной `claude` первым в PATH, состояние и запись — в песочнице, настоящая сессия не поднимается.
#   0 — вывод и код показаны, догадки нет; 1 — вывод проглочен или названа догадка; 2 — нет прибора или jq.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
S="$PWD/scripts/stop-context-restart.sh"
[ -f "$S" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/st"
printf '#!/usr/bin/env bash\n[ "${1:-}" = "--version" ] && { echo "0.0.0 (подставной)"; exit 0; }\necho "ОТВЕТ-ПОДСТАВНОГО-CLAUDE"\nexit 7\n' > "$W/bin/claude"
chmod +x "$W/bin/claude"
out=$(PATH="$W/bin:$PATH" STATE_DIR="$W/st" bash "$S" --measure 2>&1); rc=$?
bad=0
[ "$rc" = 2 ] || { echo "код прибора $rc вместо 2 (не выполнен)"; bad=1; }
[ "$(grep -c 'ОТВЕТ-ПОДСТАВНОГО-CLAUDE' <<< "$out")" -ge 2 ] || { echo "вывод сессии не показан по обеим веткам"; bad=1; }
[ "$(grep -c 'код сессии 7' <<< "$out")" -ge 2 ] || { echo "код сессии не показан по обеим веткам"; bad=1; }
grep -q 'авторизац' <<< "$out" && { echo "прибор назвал догадку о причине"; bad=1; }
exit "$bad"
