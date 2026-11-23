#!/usr/bin/env bash
# СУДИТ: hooks/lib/bounded_run.py hooks/completion-gate.sh scripts/backlog-archive.sh scripts/backlog-refresh-readings.sh scripts/named-limits.py
# Проба D1199: чужая команда, не уложившаяся в срок, снимается вместе с потомками ОДНИМ правилом у всех питонских
# исполнителей со сроком. Ноги a, b, d — как у пробы D1180: completion-gate (открытый пункт, CG_TIMEOUT), backlog-archive
# (закрытый пункт, BACKLOG_CHECK_TIMEOUT), backlog-refresh-readings («Показание», READING_TIMEOUT); нога e —
# `scripts/named-limits.py`, «Проверка снятия» предела в дереве-песочнице (CLAUDSOUL_REPO, NAMED_LIMIT_CHECK_TIMEOUT) —
# четвёртая копия устройства, разошедшаяся с тремя (снимала только `bash -c`). Нога m — правило одно: в копии
# исполнителей общий модуль `hooks/lib/bounded_run.py` порчен (снятие группы убрано), и внук обязан выжить во всех
# четырёх ногах; выжил не везде — тот исполнитель снимает своей копией, а не правилом. Нога s — сигнальная половина
# правила (D1180, H1): SIGTERM группе исполнителя посреди «Проверки» — внук обязан быть снят у всех четырёх.
# Срок 1 с, внук на уровень глубже прямого ребёнка команды (как у D1180, M1). Ноги идут параллельно.
# Код: 0 — внука нет во всех ногах, порча правила видна во всех; 1 — названо; 2 — не измерено.
set -uo pipefail
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING CLAUDSOUL_REPO
REPO="$(cd "$(dirname "$0")/../../.." && pwd -P)"
for f in hooks/completion-gate.sh scripts/backlog-archive.sh scripts/backlog-refresh-readings.sh scripts/named-limits.py; do
    [ -f "$REPO/$f" ] || { echo "нет $f"; exit 2; }
done
command -v git >/dev/null 2>&1 || { echo "нет git"; exit 2; }
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1199.XXXXXX") || exit 2
trap 'for p in "$S"/pid-*; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done; rm -rf "$S"' EXIT
kid() { printf '%s\n' "sh -c 'echo \$\$ > \"$S/pid-$1\"; exec sleep 40'" true > "$S/deep-$1.sh"
        printf '%s' ": > \"$S/ran-$1\"; bash \"$S/deep-$1.sh\" & wait"; }

legs() {  # <корень исполнителей> <метка>
    local R="$1" t="$2"
    mkdir -p "$S/$t-a-state"
    printf '# BACKLOG\n\n### D301 ◐ долгий внук\n**Результат.** нет\n**Проверка.** `%s` → 0\n' "$(kid "${t}a")" > "$S/$t-a.md"
    printf '{"session_id":"probe-d1199-%s","cwd":"/"}' "$t" \
        | env CG_TIMEOUT=1 CG_BACKLOG="$S/$t-a.md" STATE_DIR="$S/$t-a-state" bash "$R/hooks/completion-gate.sh" >/dev/null 2>&1 &
    printf '# BACKLOG\n\n### D302 ☑ долгий внук\n**Результат.** да\n**Проверка.** `%s` → 0\n' "$(kid "${t}b")" > "$S/$t-b.md"
    env CLAUDSOUL_REPO="$R" BACKLOG_CHECK_TIMEOUT=1 BACKLOG_FILE="$S/$t-b.md" BACKLOG_ARCHIVE="$S/$t-b-arch.md" STATE_DIR="$S/$t-b-state" \
        bash "$R/scripts/backlog-archive.sh" run >/dev/null 2>&1 &
    printf -- '- ☐ **D9711** долгий внук\n  **Проверка.** `false` → 0\n  **Показание.** `%s`\n  **Последнее показание (2026-10-01).** 0\n' \
        "$(kid "${t}d")" > "$S/$t-d.md"
    env READING_TIMEOUT=1 BACKLOG_FILE="$S/$t-d.md" STATE_DIR="$S/$t-d-state" \
        bash "$R/scripts/backlog-refresh-readings.sh" --check >/dev/null 2>&1 &
    mkdir -p "$S/$t-e" && git -C "$S/$t-e" init -q 2>/dev/null
    printf 'НАЗВАННЫЙ ПРЕДЕЛ: проба D1199.\nУсловие снятия: никогда.\nПроверка снятия: `%s` → 0\n' "$(kid "${t}e")" > "$S/$t-e/lim.md"
    git -C "$S/$t-e" add lim.md 2>/dev/null
    env CLAUDSOUL_REPO="$S/$t-e" NAMED_LIMIT_CHECK_TIMEOUT=1 python3 "$R/scripts/named-limits.py" --check >/dev/null 2>&1 &
    wait
}

sigs() {  # нога s: SIGTERM группе исполнителя посреди долгой команды, срок 20 с — снимать обязан сигнал, а не срок
    local leg
    mkdir -p "$S/s-a-state" "$S/s-e"
    printf '# BACKLOG\n\n### D301 ◐ долгий внук\n**Результат.** нет\n**Проверка.** `%s` → 0\n' "$(kid sa)" > "$S/s-a.md"
    printf '{"session_id":"probe-d1199-s","cwd":"/"}' > "$S/s-a.json"
    printf '# BACKLOG\n\n### D302 ☑ долгий внук\n**Результат.** да\n**Проверка.** `%s` → 0\n' "$(kid sb)" > "$S/s-b.md"
    printf -- '- ☐ **D9711** долгий внук\n  **Проверка.** `false` → 0\n  **Показание.** `%s`\n  **Последнее показание (2026-10-01).** 0\n' \
        "$(kid sd)" > "$S/s-d.md"
    git -C "$S/s-e" init -q 2>/dev/null
    printf 'НАЗВАННЫЙ ПРЕДЕЛ: проба D1199.\nУсловие снятия: никогда.\nПроверка снятия: `%s` → 0\n' "$(kid se)" > "$S/s-e/lim.md"
    git -C "$S/s-e" add lim.md 2>/dev/null
    set -m   # у каждого исполнителя своя группа: сигнал уходит группе, как от Ctrl-C или от харнесса
    env CG_TIMEOUT=20 CG_BACKLOG="$S/s-a.md" STATE_DIR="$S/s-a-state" bash -c 'bash "$1" < "$2"' _ \
        "$REPO/hooks/completion-gate.sh" "$S/s-a.json" >/dev/null 2>&1 & echo $! > "$S/ex-sa"
    env CLAUDSOUL_REPO="$REPO" BACKLOG_CHECK_TIMEOUT=20 BACKLOG_FILE="$S/s-b.md" BACKLOG_ARCHIVE="$S/s-b-arch.md" \
        STATE_DIR="$S/s-b-state" bash "$REPO/scripts/backlog-archive.sh" run >/dev/null 2>&1 & echo $! > "$S/ex-sb"
    env READING_TIMEOUT=20 BACKLOG_FILE="$S/s-d.md" STATE_DIR="$S/s-d-state" \
        bash "$REPO/scripts/backlog-refresh-readings.sh" --check >/dev/null 2>&1 & echo $! > "$S/ex-sd"
    env CLAUDSOUL_REPO="$S/s-e" NAMED_LIMIT_CHECK_TIMEOUT=20 python3 "$REPO/scripts/named-limits.py" --check \
        >/dev/null 2>&1 & echo $! > "$S/ex-se"
    set +m
    for leg in sa sb sd se; do
        for _ in $(seq 1 100); do [ -s "$S/pid-$leg" ] && break; sleep 0.1; done
        kill -TERM -- -"$(cat "$S/ex-$leg")" 2>/dev/null
    done
    wait
}

# Копия исполнителей с порченым правилом: по сроку снимается только `bash -c` (`p.kill()` вместо снятия группы) —
# устройство до D1180. Порча «снятия нет вовсе» не годится: исполнитель ждал бы внука до конца, и внук умирал бы сам.
# Архиватор берёт библиотеку по CLAUDSOUL_REPO, а не по своему месту, — нога b получает корень копии. Модуля нет —
# судить «одно правило» нечем, и это дефект пункта (правило живёт копиями), а не «не измерено».
M="$S/mut"
h="$REPO/hooks"; mkdir -p "$M/hooks" && cp "$h"/*.sh "$M/hooks/" && cp -R "$REPO/hooks/lib" "$M/hooks/lib" \
    && cp -R "$REPO/scripts" "$M/scripts" || { echo "копия исполнителей не собралась"; exit 2; }
bad=0
if [ -f "$M/hooks/lib/bounded_run.py" ]; then
    python3 - "$M/hooks/lib/bounded_run.py" <<'PY' || { echo "порча правила не легла — проба устарела"; exit 2; }
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
t, n = re.subn(r"os\.killpg\([^)]*\)", "p.kill()", s)
if not n:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(t)
PY
    legs "$REPO" w & legs "$M" m & sigs & wait
else
    echo "общего правила нет: hooks/lib/bounded_run.py — снятие по сроку живёт копиями"; bad=1
    legs "$REPO" w & sigs & wait
fi

for leg in a b d e; do
    [ -e "$S/ran-w$leg" ] && [ -s "$S/pid-w$leg" ] || { echo "нога $leg: исполнитель не дошёл до команды — не измерено"; exit 2; }
    kill -0 "$(cat "$S/pid-w$leg")" 2>/dev/null && { echo "нога $leg: внук «Проверки» жив после выхода исполнителя"; bad=1; }
    [ -f "$M/hooks/lib/bounded_run.py" ] || continue
    [ -e "$S/ran-m$leg" ] && [ -s "$S/pid-m$leg" ] || { echo "нога m$leg: исполнитель копии не дошёл до команды — не измерено"; exit 2; }
    kill -0 "$(cat "$S/pid-m$leg")" 2>/dev/null \
        || { echo "нога m$leg: порча общего правила не видна — исполнитель снимает своей копией"; bad=1; }
done
sleep 0.2
for leg in sa sb sd se; do
    [ -s "$S/pid-$leg" ] || { echo "нога $leg: исполнитель не дошёл до команды — не измерено"; exit 2; }
    kill -0 "$(cat "$S/pid-$leg")" 2>/dev/null && { echo "нога $leg: внук жив после SIGTERM группе исполнителя"; bad=1; }
done
[ "$bad" = 0 ] && echo "все четыре исполнителя снимают «Проверку» по сроку вместе с потомками и при сигнале, правилом hooks/lib/bounded_run.py"
exit "$bad"
