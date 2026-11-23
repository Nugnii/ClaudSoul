#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_guards_provable.sh
# test_adv_guards_provable_false_proof.sh — АТАКА на hooks/tests/test_guards_provable.sh.
#
# Мета-страж обязан отличать тест, доказывающий срабатывание и тишину, от теста, который
# «молчал бы и будучи пустым файлом» (его собственные слова). Словарь признаков включает
# ГОЛЫЕ формы `[ -n ` и `[ -z ` (FIRE_PATTERNS / SILENT_PATTERNS, строки 66 и 76). Обе —
# служебные идиомы оболочки, а не утверждения: `[ -n "$line" ] || continue` внутри цикла
# чтения и `[ -z "$x" ] && x=…` подстановка умолчания встречаются в дереве повсеместно.
#
# Итог: файл, не проверяющий НИЧЕГО, объявляется доказательством стража. Признак снят
# с ВИДА строки, а роль у неё другая — тот самый род, который сам этот мета-страж
# объявляет своим предметом.
#
# Фикстура собирается в mktemp: мета-страж считает дерево от собственного расположения
# ($0/..), поэтому его копия кладётся в подложное hooks/tests/.
set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/test_guards_provable.sh"
[ -f "$SRC" ] || { echo "FAIL: нет $SRC"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

TMP=$(mktemp -d) || exit 1
mkdir -p "$TMP/hooks/tests"
cp "$SRC" "$TMP/hooks/tests/test_guards_provable.sh"

# страж-фикстура: говорит наружу, значит мета-страж обязан требовать доказательства
cat > "$TMP/hooks/fakeguard.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
jq -cn --arg m "что-то случилось" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}'
EOF

# ── контроль: теста нет вовсе — мета-страж обязан загореться ──────────────────────
OUT=$(bash "$TMP/hooks/tests/test_guards_provable.sh" 2>&1); RC=$?
if [ "$RC" -ne 0 ] && grep -q 'fakeguard' <<< "$OUT"; then
    ok "контроль: страж без теста назван недоказанным"
else
    bad "контроль: страж без теста назван недоказанным" \
        "код=$RC, вывод: $(printf '%s' "$OUT" | tr '\n' ' ') — фикстура не годится"
fi

# ── АТАКА: «тест», не проверяющий ничего, но с двумя служебными идиомами ──────────
cat > "$TMP/hooks/tests/test_fakeguard.sh" <<'EOF'
#!/usr/bin/env bash
# Проба, которая НИЧЕГО не проверяет: хук даже не запускается.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/fakeguard.sh"
LIST=""
while IFS= read -r line; do
    [ -n "$line" ] || continue
    LIST="$LIST $line"
done <<< "$(printf 'a\nb\n')"
[ -z "$LIST" ] && LIST="умолчание"
echo "проба отработала: $HOOK $LIST"
exit 0
EOF

OUT=$(bash "$TMP/hooks/tests/test_guards_provable.sh" 2>&1); RC=$?
if [ "$RC" -ne 0 ] && grep -q 'fakeguard' <<< "$OUT"; then
    ok "пустая_проба_не_доказательство: мета-страж назвал её"
else
    bad "пустая_проба_не_доказательство: мета-страж назвал её" \
        "код=$RC, вывод: $(printf '%s' "$OUT" | tr '\n' ' ') — хук в пробе даже не запускается, а числится доказанным"
fi

echo "guards-provable-false-proof: $PASS ok, $FAIL FAIL"
exit $(( FAIL != 0 ))
