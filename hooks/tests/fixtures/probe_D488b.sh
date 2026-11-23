#!/usr/bin/env bash
# СУДИТ: hooks/knowledge-activator.sh
# probe_D488b.sh — разбор шапок базы знаний хуком идёт ОДНИМ проходом (knowledge_frontmatter_batch),
# а не процессами на каждый файл: число вызовов awk/jq/sed/grep/cut/tr/head/md5 не растёт с базой.
# (Имя с «b»: `probe_D488.sh` занят показанием пункта — сверка с хуком до починки, минуты и красна
# от законных правок отбора после 3 октября 2026.) Стенные секунды хука зависят от нагрузки машины и
# здесь не меряются; живое время хука с пределом 5 с — не «Проверка», а замер (строки в реестре нет).
# Судит ХУК в песочных HOME и STATE_DIR на синтетической базе из 30 и 90 файлов; `date` не считается —
# календарный фоллбек (реестра опыта в песочнице нет) зовёт его на файл, в живой установке реестр есть.
# Коды: 0 — держится; 1 — нарушено (в stdout слово); 2 — рамка не собралась.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
HOOK="$REPO/hooks/knowledge-activator.sh"
[ -f "$HOOK" ] || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
calls() {  # calls <N> -> число вызовов считанных утилит за один запуск хука на базе из N файлов
    local N="$1" H t real i; H="$d/h$N"
    mkdir -p "$H/.claude/global-lessons" "$H/st" "$H/bin" || return 1
    : > "$H/calls"
    for t in awk jq sed grep cut tr head md5 md5sum shasum; do
        real=$(command -v "$t") || continue
        printf '#!/bin/sh\necho %s >> "%s/calls"\nexec %s "$@"\n' "$t" "$H" "$real" > "$H/bin/$t"; chmod +x "$H/bin/$t"
    done
    for i in $(seq 1 "$N"); do
        printf -- '---\nname: "Урок %s про деплой сборки"\ndescription: "Проверяй конфиг сборки %s перед деплоем"\ntype: pattern\noutcome: error\nconfidence: 2\nimpact: 4\nintensity: 3\nconfirmed_count: 2\ncontradicted_count: 0\nlast_confirmed: 2026-10-01\nstatus: active\ndomain: [deploy, testing]\ntrigger: "деплой сборка конфиг"\n---\nтело %s\n' \
            "$i" "$i" "$i" > "$H/.claude/global-lessons/pattern-synth-$i.md"
    done
    printf '{"tool_name":"Bash","tool_input":{"command":"deploy build config"},"cwd":"%s","session_id":"p488b"}' "$d" \
      | PATH="$H/bin:$PATH" HOME="$H" STATE_DIR="$H/st" SR_SESSIONS_DIR="$H/st" CLAUDE_CODE_SESSION_ID="p488b-$N" \
        bash "$HOOK" > "$H/out.txt" 2>&1
    grep -q 'additionalContext' "$H/out.txt" || return 1
    wc -l < "$H/calls" | tr -d ' '
}
A=$(calls 30) || exit 2
B=$(calls 90) || exit 2
[ -n "$A" ] && [ -n "$B" ] && [ "$A" -gt 0 ] || exit 2
# 60 лишних файлов; допуск — 6 вызовов на всю прибавку (не на файл): отбор кандидатов может добавить пару
[ $((B - A)) -le 6 ] || { echo "вызовов утилит растёт с базой: $A при 30 файлах, $B при 90"; exit 1; }
exit 0
