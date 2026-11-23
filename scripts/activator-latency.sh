#!/usr/bin/env bash
# activator-latency.sh — стенное время хука знаний на одном входе, с пределом, учитывающим нагрузку машины.
#
# Результат: хук знаний (`hooks/knowledge-activator.sh`, синхронный PreToolUse) отвечает в пределе — 5 с, пока нагрузка
#            не выше числа ядер; выше — предел растёт как нагрузка на ядро, но не больше чем вчетверо; превышение —
#            находка с числами, а не тишина
# Проверка результата: bash hooks/tests/test_activator_latency.sh даёт 0
#
# Повод (D1234, 2 ноября 2026): предел 5 с жил только в «Проверке» закрытого D488, и при нагрузке 9–11 три прогона дали
# 6,65, 5,71 и 5,66 с — сказать «дефект или нагрузка» было не по чему, а замера в реестре не было вовсе. Предел
# масштабируется нагрузкой НА ЯДРО (скептик opus по dbf5c8de, M2: деление на 4 без числа ядер на 10 ядрах прощало
# семикратное замедление): замер закрытия D488 — 2,3–2,7 с при нагрузке 3–4,5, то есть 5 с — двойной запас.
# Вход — контекст `commit` пробы D488 (у него самый широкий отбор); состояние и реестр сессий — песочные, семантический
# откат выключен (он внешний). Мера — медиана трёх прогонов: один всплеск нагрузки не решает. Хук, вышедший не с 0 или
# без вывода, — «не измерено», а не «быстро» (M3): упавший хук отвечает мгновенно.
# Коды: 0 — медиана в пределе; 1 — выше предела (числа названы); 2 — не измерено (нет хука, базы знаний, jq или perl,
#       хук упал либо промолчал).
# Переменные: KA_HOOK (хук — для свидетеля), KA_LIMIT (предел на ненагруженной машине, по умолчанию 5), KA_LOAD и KA_NCPU
#             (нагрузка и число ядер — для свидетеля; иначе `uptime` и производительные ядра `sysctl`, затем все/`nproc`).
# НАЗВАННЫЙ ПРЕДЕЛ формулы: поправка выверена по четырём точкам (2,3–2,7 с при 3–4,5; 6,65/5,71/5,66 с при 9–11; 4,72 с
# при 3,2) — замера, который откалибровал бы её под нагрузкой выше 12, нет.
# НАЗВАННЫЙ ПРЕДЕЛ: срока на один прогон нет — зависший хук подвесит замер; нагрузку `uptime` в переведённой локали
# прибор не разберёт и возьмёт 0 (без поправки). Условие снятия: первый такой прогон в журнале замеров.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
H="${KA_HOOK:-$REPO/hooks/knowledge-activator.sh}"
[ -f "$H" ] || { echo "activator-latency: нет хука $H — не измерено"; exit 2; }
# База — та, что читает сам хук (`KNOWLEDGE_DIR` в `hooks/knowledge-activator.sh` — `$HOME/.claude/global-lessons`);
# LESSONS_DIR — подмена только для этой проверки (свидетель), хук её не читает.
KB="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
[ -n "$(ls "$KB" 2>/dev/null | head -1)" ] || { echo "activator-latency: базы знаний нет или она пуста ($KB) — не измерено"; exit 2; }
command -v perl >/dev/null 2>&1 || { echo "activator-latency: нет perl — не измерено"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "activator-latency: нет jq — хук ответил бы мгновенно, не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
IN=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \\"fix(hooks): knowledge activator\\""},"cwd":"%s","session_id":"ka-latency"}' "$REPO")
now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }
T=""
for i in 1 2 3; do
    mkdir -p "$W/st$i/sessions"
    t0=$(now)
    ( cd "$REPO" && printf '%s' "$IN" | STATE_DIR="$W/st$i" SR_SESSIONS_DIR="$W/st$i/sessions" \
        CLAUDE_CODE_SESSION_ID=ka-latency SKIP_MCP_FALLBACK=1 bash "$H" > "$W/out$i" 2>/dev/null )
    rc=$?
    T="$T $(perl -e 'printf "%.2f", $ARGV[1] - $ARGV[0]' "$t0" "$(now)")"
    [ "$rc" = 0 ] && [ -s "$W/out$i" ] || { echo "activator-latency: прогон $i — хук вышел с кодом $rc, вывод $(wc -c < "$W/out$i" | tr -d ' ') байт — время не о работе, не измерено"; exit 2; }
done
LOAD="${KA_LOAD:-$(uptime 2>/dev/null | sed -E 's/.*load averages?: *([0-9]+[.,][0-9]+).*/\1/' | tr , .)}"
case "$LOAD" in ''|*[!0-9.]*) LOAD=0 ;; esac
# Ядра — ПРОИЗВОДИТЕЛЬНЫЕ, где они отличаются (скептик opus по 2f7b9d95, M1): на этой машине 4 из 10, и при нагрузке
# выше четырёх работа уходит на экономичные — замедление в 2,5 раза при нагрузке 9–11 поправка по всем десяти не видела.
NCPU="${KA_NCPU:-$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null)}"
case "$NCPU" in ''|*[!0-9]*|0) NCPU=1 ;; esac
MED=$(printf '%s\n' $T | sort -n | sed -n 2p)
awk -v m="$MED" -v l="$LOAD" -v n="$NCPU" -v b="${KA_LIMIT:-5}" -v runs="$T" 'BEGIN {
    f = l / n; if (f < 1) f = 1; if (f > 4) f = 4
    lim = b * f
    printf "activator-latency: медиана %.2f с (прогоны:%s), нагрузка %.2f на %d ядер, предел %.2f с\n", m, runs, l, n, lim
    exit (m > lim) ? 1 : 0 }'
