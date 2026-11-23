#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh
# test_contract_header_once_under_race.sh — строка-шапка исполнителя архивирования вставляется в BACKLOG.md проекта не
# больше одного раза при любом числе одновременных вызовов договора инициации (D1308, корень R6, род H).
#
# Устройство дефекта: `backlog_contract_parts_ensure` решал «шапки нет» чтением ВНЕ замка, а под замком сверял только
# сумму между взятием и записью — второй вызов, дождавшийся замка, видел уже вставленную шапку как «файл не менялся
# с моего взятия» и вставлял её ещё раз. Вызывателей два — старт сессии и каждая граница хода, у параллельных сессий
# одного проекта они сходятся.
#
# H0 — положительный контроль: один вызов дописывает шапку (одна строка) и называет это;
# H1 — 20 пар одновременных вызовов: в каждой паре шапка одна, «дописана» сказано одним, «не вышло» — никем;
# H2 — замок держит третий писатель (архиватор, пересчёт показаний): два вызова ждут его — шапка одна.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/backlog-lib.sh"; PL="$HOOKS_DIR/paths-lib.sh"; SL="$HOOKS_DIR/state-lock-lib.sh"
[ -f "$LIB" ] && [ -f "$PL" ] && [ -f "$SL" ] || { echo "FAIL: нет библиотек в дереве"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
TPL="$HOOKS_DIR/../templates"
[ -f "$TPL/BACKLOG.md.tmpl" ] && [ -f "$TPL/ROOTS.md.tmpl" ] || { echo "FAIL: нет шаблонов частей в дереве"; exit 1; }
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd) || exit 1
mkdir -p "$TMP/home/.claude/templates" "$TMP/out"
cp "$TPL/BACKLOG.md.tmpl" "$TPL/ROOTS.md.tmpl" "$TMP/home/.claude/templates/"
P="$TMP/proj"; mkdir -p "$P"
( cd "$P" && git init -q && printf '# Session Log\n' > SESSION.md && cp "$TPL/ROOTS.md.tmpl" ROOTS.md ) \
    || { echo "подготовка мира не удалась: hooks/tests/test_contract_header_once_under_race.sh:$LINENO" >&2; exit 1; }

_reset() { printf '# BACKLOG\n\n- ☐ **X1** пункт руками\n' > "$P/BACKLOG.md"; rm -rf "$P/BACKLOG.md.lock"; }
_call() {   # <файл вывода> — один вызов договора в своём процессе
    HOME="$TMP/home" CLAUDSOUL_ROOT="$HOOKS_DIR/.." bash -c '. "$1"; . "$2"; backlog_contract_parts_ensure "$3"' _ "$PL" "$LIB" "$P" \
        > "$1" 2>/dev/null
}
_heads() { grep -c 'backlog-archive\.sh' "$P/BACKLOG.md" 2>/dev/null; }

# H0. Один вызов.
_reset; _call "$TMP/out/h0"
[ "$(_heads)" = 1 ] && ok || bad H0a "один вызов не дописал шапку ровно один раз: $(_heads)"
grep -q 'дописана из шаблона' "$TMP/out/h0" && ok || bad H0b "дописанное не названо: $(head -c 200 "$TMP/out/h0")"

# H1. Пары одновременных вызовов.
dup=0; said_bad=0
for i in $(seq 1 20); do
    _reset
    _call "$TMP/out/a$i" & _call "$TMP/out/b$i" & wait
    [ "$(_heads)" = 1 ] || dup=$((dup + 1))
    n=$(cat "$TMP/out/a$i" "$TMP/out/b$i" | grep -c 'дописана из шаблона')
    m=$(cat "$TMP/out/a$i" "$TMP/out/b$i" | grep -c 'дописать не вышло')
    [ "$n" = 1 ] && [ "$m" = 0 ] || said_bad=$((said_bad + 1))
done
[ "$dup" = 0 ] && ok || bad H1a "шапка удвоена в $dup парах из 20"
[ "$said_bad" = 0 ] && ok || bad H1b "в $said_bad парах из 20 сказано не «дописана» одним и молчание другим"

# H2. Замок держит третий писатель секунду; оба вызова ждут его.
_reset
HOME="$TMP/home" bash -c '. "$1"; lock_acquire "$2" || exit 3; sleep 1; lock_release "$2"' _ "$SL" "$P/BACKLOG.md" &
held=$!
sleep 0.2
_call "$TMP/out/c1" & _call "$TMP/out/c2" & wait
wait "$held" 2>/dev/null
[ "$(_heads)" = 1 ] && ok || bad H2 "при удержанном третьим замке шапка вставлена $(_heads) раз(а)"

echo "test_contract_header_once_under_race: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
