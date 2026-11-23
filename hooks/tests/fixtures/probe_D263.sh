#!/usr/bin/env bash
# СУДИТ: hooks/completion-gate.sh
# probe_D263.sh — гейт исполняет «Проверку» ОТКРЫТОГО пункта: зелёная у ☐ названа поимённо, красная у ☐
# и зелёная у ☑ молчат, неисполнимая по синтаксису названа «синтаксис», а не уложившаяся в срок — «не хватило бюджета».
# Судит ГЕЙТ на фикстуре-бэклоге в песочных STATE_DIR и HOME. Живой BACKLOG.md и его бюджет
# (нога T7/T7b теста гейта, ~140 с) здесь не мерятся: цену «Проверок» живых пунктов меряет
# нога T7b теста `test_completion_gate_open_items.sh`, состояние — сам BACKLOG.md.
# Коды: 0 — держится; 1 — нарушено (в stdout слово); 2 — рамка не собралась.
set -uo pipefail
. "$(dirname "$0")/../alerts-read.sh"
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
HOOK="$REPO/hooks/completion-gate.sh"
[ -f "$HOOK" ] || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/state" "$d/home" || exit 2
cat > "$d/b.md" <<'MD'
### D901 ☐ зелёная у открытого
**Проверка.** `true` → 0

### D902 ☐ красная у открытого
**Проверка.** `false` → 0

### D903 ☐ медленная у открытого
**Проверка.** `sleep 4; false` → 0

### D905 ☐ неисполнимая по синтаксису у открытого
**Проверка.** `if then fi (` → 0
MD
cat > "$d/c.md" <<'MD'
### D904 ☑ зелёная у закрытого
**Проверка.** `true` → 0
MD
run() {  # run <бэклог> <срок одной команды>
    alerts_clear "$d/state"; rm -f "$d/state"/completion-gate-*.ok "$d/state"/completion-gate-fired-*.jsonl 2>/dev/null
    printf '{"session_id":"p263","cwd":"/"}' \
      | env -u BACKLOG_CHECKS_NESTED HOME="$d/home" CG_BACKLOG="$1" CG_LOCAL_BACKLOG="" CG_TIMEOUT="$2" CG_BUDGET_OPEN=60 \
        STATE_DIR="$d/state" bash "$HOOK" >/dev/null 2>&1
    alerts_of "$d/state"
}
A=$(run "$d/b.md" 1)
case "$A" in *"ОТКРЫТОГО пункта не красная"*D901*|*D901*"ОТКРЫТОГО пункта не красная"*) ;; *) echo "зелёная у открытого не названа"; exit 1 ;; esac
case "$A" in *"не хватило бюджета"*D903*) ;; *) echo "не уложившаяся в срок не названа непроверенной"; exit 1 ;; esac
# Неисполнимая по оболочечному синтаксису — третий дефект «Результата» D263 (нога T3 прежней «Проверки»; скептик opus
# по 5b9d761b, M1): гейт называет её поимённо с пометкой «синтаксис», а не принимает за красную.
case "$A" in *"D905 (синтаксис)"*) ;; *) echo "неисполнимая по синтаксису не названа"; exit 1 ;; esac
# D902 (красная у ☐) — норма и молчит; в канале «зелёная» её быть не может
grep -q D902 <<< "$(awk '/ОТКРЫТОГО пункта не красная/{p=1} p' <<< "$A")" && { echo "красная у открытого названа зелёной"; exit 1; }
C=$(run "$d/c.md" 5)
case "$C" in *"ОТКРЫТОГО пункта не красная"*) echo "зелёная у закрытого названа дефектом открытого"; exit 1 ;; esac
exit 0
