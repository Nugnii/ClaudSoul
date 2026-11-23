#!/usr/bin/env bash
# СУД: дороже срока прибора
# (600 настоящих вызовов по секунде на прежнем страже — десятки минут; 80 вызовов шли 521 с при нагрузке 15–24, а меньшая
#  выборка теряет различение; в «Проверку» проба не входит, судит её «Показание» D506 — D1222, 8 ноября 2026)
# probe_D506.sh — ускорение стража blocker-tier (D506) не изменило его решений: страж до
# починки (коммит 21483251) и страж рабочего дерева на одних и тех же настоящих вызовах дают
# байт в байт один и тот же вывод — подсказку, отказ или молчание.
#
# Корпус — вызовы Bash/Edit/Write/MultiEdit из 60 последних расшифровок этой машины:
# выборка вызовов, где упомянуты команды, которые судят сигналы (timeout, sponge, sed -i,
# heredoc, hooks/ …), и случайная выборка остальных; зёрна выборки постоянны. Каждый прогон
# стража — со своим каталогом состояния и своим идентификатором сессии: дроссель стража
# «пара знание:сигнал звучит раз за сессию», и общий каталог глушил бы второй прогон
# (на этом ослепла первая сверка — D508).
#
# Аргументы: <N по ключевым словам> <N случайных> (по умолчанию 300 и 300).
# Код: 0 — все вызовы совпали; 1 — есть расхождение (печатается); 2 — не исполнимо здесь
# (нет истории git с коммитом 21483251, нет базы знаний или расшифровок).
# Цена: прежний страж — около секунды на вызов; при 600 вызовах проба идёт десятки минут.
set -uo pipefail

OLD_REV=21483251
NK="${1:-300}"; NR="${2:-300}"
REPO="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$REPO" ] && [ -f "$REPO/hooks/blocker-tier-check.sh" ] || exit 2
git -C "$REPO" cat-file -e "$OLD_REV^{commit}" 2>/dev/null || exit 2
[ -d "$HOME/.claude/global-lessons" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
ls "$HOME"/.claude/projects/*/*.jsonl >/dev/null 2>&1 || exit 2

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
# Обе стороны — снимки на старте: проба идёт десятки минут, и правка дерева посреди прогона
# не должна смешать редакции.
mkdir -p "$W/old" "$W/new"
git -C "$REPO" archive "$OLD_REV" hooks | tar -x -C "$W/old" || exit 2
( cd "$REPO" && tar -cf - hooks ) | tar -x -C "$W/new" || exit 2

ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -60 | while IFS= read -r f; do
    jq -c 'select(.type == "assistant") | .message.content[]?
           | select(type == "object" and .type == "tool_use"
                    and (.name == "Bash" or .name == "Edit" or .name == "Write" or .name == "MultiEdit"))
           | {tool_name: .name, tool_input: .input}' "$f" 2>/dev/null
done | awk '!seen[$0]++' > "$W/all"
KW='timeout|sponge|realpath|readlink -f|date -j|stat -f|tail -r|compgen|sed -i|grep -P|gtimeout|<<|hooks/'
pick() { awk -v n="$1" -v seed="$2" 'BEGIN { srand(seed) } { a[NR] = $0 }
    END { for (i = 1; i <= NR && i <= n; i++) { j = int(rand() * NR) + 1; if (!(j in u)) { u[j] = 1; print a[j] } } }'; }
{ grep -E "$KW" "$W/all" | pick "$NK" 7; grep -vE "$KW" "$W/all" | pick "$NR" 11; } > "$W/corpus"

run() { # каталог-дерева строка номер → вывод стража
    local st; st=$(mktemp -d "$W/st.XXXXXX")
    printf '%s' "$2" | jq -c --arg s "d506probe-$3" '. + {session_id: $s, cwd: "/tmp"}' \
        | BLOCKER_STATE_DIR="$st" CLAUDE_HOOKS_STATE_DIR="$st" STATE_DIR="$st" \
          bash "$1/hooks/blocker-tier-check.sh" 2>/dev/null
}
N=0; SAME=0; FIRED=0
while IFS= read -r line; do
    N=$((N + 1))
    o=$(run "$W/old" "$line" "$N"); n=$(run "$W/new" "$line" "$N")
    [ -n "$o" ] && FIRED=$((FIRED + 1))
    if [ "$o" = "$n" ]; then SAME=$((SAME + 1))
    else echo "  РАСХОЖДЕНИЕ на вызове $N: $(printf '%s' "$line" | head -c 200)"; fi
done < "$W/corpus"
echo "probe_D506: вызовов $N, совпали $SAME из $N, срабатываний прежнего стража $FIRED"
# Положительный контроль (D1222, скептик opus M2): корпус, на котором прежний страж не сработал ни разу, сравнивает
# молчание с молчанием — выхолощенный страж прошёл бы его так же. Такой прогон — «не измерено», а не зелёный.
[ "$FIRED" -gt 0 ] || { echo "probe_D506: прежний страж не сработал ни разу — различать нечем"; exit 2; }
[ "$N" -gt 0 ] && [ "$SAME" -eq "$N" ]
exit $?
