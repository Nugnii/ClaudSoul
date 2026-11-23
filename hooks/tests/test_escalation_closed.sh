#!/usr/bin/env bash
# СУДИТ: scripts/escalation-age.sh hooks/knowledge-audit-digest.sh
# test_escalation_closed.sh — закрытая заявка на эскалацию не числится открытой (D1007).
#
# Поле закрытия `escalation_mechanism_needed: false` (META §escalation) не читал ни один читатель:
# исполненная 31 августа 2026 заявка 64 дня краснела в escalation-age и висела в дайджесте.
# Ноги: закрытая заявка → escalation-age 0 и названа закрытой; та же заявка открытой → 1 (различение);
# дайджест не выводит закрытую в раздел эскалации, открытую — выводит.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

mk() {  # <каталог> <true|false>
    mkdir -p "$1"
    printf -- '---\nname: x\ntype: pattern\nblocker: true\nconfirmed_count: 15\nescalation_threshold: 12\nescalation_opened: 2026-01-01\nescalation_mechanism_needed: %s\nescalation_hint: "построй страж"\n---\n\nтело\n' "$2" \
        > "$1/pattern-x.md"
}
mk "$T/closed" false
mk "$T/open" true
mk "$T/commented" 'false   # закрыто: страж построен'

OUT=$(LESSONS_DIR="$T/closed" bash "$REPO/scripts/escalation-age.sh" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T1a "закрытая заявка уронила escalation-age (код $RC): $OUT"
grep -q 'закрытых заявок: 1' <<< "$OUT" && ok || bad T1b "закрытая заявка не названа закрытой: $OUT"

OUT=$(LESSONS_DIR="$T/commented" bash "$REPO/scripts/escalation-age.sh" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T1c "закрытие с комментарием в строке не узнано (код $RC): $OUT"

OUT=$(LESSONS_DIR="$T/open" bash "$REPO/scripts/escalation-age.sh" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok || bad T2 "открытая просроченная заявка не уронила escalation-age (код $RC): $OUT"

digest() {  # <каталог базы> → вывод дайджеста; живые ~/.claude не трогаются
    mkdir -p "$1/_audit-history" "$T/state-$2"
    HOME="$T/home-$2" LESSONS_DIR="$1" STATE_DIR="$T/state-$2" CLAUDSOUL_ROOT="$REPO" \
        bash "$REPO/hooks/knowledge-audit-digest.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_escalation_closed.sh:$LINENO" >&2; exit 1; }
    cat "$1"/_audit-history/*.md 2>/dev/null
}
D=$(digest "$T/closed" c)
[ -n "$D" ] || bad T3pre "дайджест не записал отчёт — рамка не поднялась"
grep -q 'Engineering escalation needed' <<< "$D" && bad T3 "закрытая заявка попала в раздел эскалации дайджеста" || ok
D=$(digest "$T/commented" m)
grep -q 'Engineering escalation needed' <<< "$D" && bad T3b "закрытие с комментарием попало в раздел эскалации дайджеста" || ok
D=$(digest "$T/open" o)
grep -q 'Engineering escalation needed' <<< "$D" && ok || bad T4 "открытая заявка не попала в дайджест — нога T3 ничего не различает"

echo "escalation closed: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
