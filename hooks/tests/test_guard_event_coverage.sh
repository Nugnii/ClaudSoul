#!/usr/bin/env bash
# СУДИТ: scripts/guard-event-coverage.sh
# test_guard_event_coverage.sh — свидетель прибора «страж видит оба пути правки».
# Предмет: хук, объявивший предметом правку и не видящий Bash, назван и даёт код 1;
# тот же хук с Bash в событии — код 0; шапка, молчащая о предмете, не судится вовсе;
# объявленное исключение снимает вердикт; без install.sh прибор молчит (другой проект).
# live-home-ok: литерал `~/.claude` здесь — СОДЕРЖИМОЕ поддельного install.sh в песочнице
# (строка регистрации хука, которую прибор разбирает), а не чтение живого дома. Проверено
# составом: тест работает только внутри mktemp-каталога и живой ~/.claude не открывает.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
TOOL="$REPO/scripts/guard-event-coverage.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

mk() {  # mk <каталог> <matcher> <шапка> [исключение]
    local d="$1" matcher="$2" head="$3" excl="${4:-}"
    mkdir -p "$d/hooks" "$d/scripts"
    # Страж обязан не только ОБЪЯВИТЬ предмет шапкой, но и ЧИТАТЬ его из входа: прибор
    # с 13 сентября 2026 судит устройство, а не прозу (замер: из девяти, отобранных прозой,
    # путь читают восемь; девятый — `budget-gate`, у него предмет иной).
    { printf '#!/usr/bin/env bash\n# probe.sh — %s\n# en: probe\n#\n' "$head"
      [ -n "$excl" ] && printf '# bash-путь: не нужен — %s\n' "$excl"
      printf 'FILE=$(jq -r ".tool_input.file_path // \\"\\"" 2>/dev/null)\n'; } > "$d/hooks/probe.sh"
    printf '%s\n' '"PreToolUse": {' "  \"matcher\": \"$matcher\"," '  "command": "bash ~/.claude/hooks/probe.sh"' '}' > "$d/install.sh"
}
run() { ( cd "$1" && CLAUDSOUL_REPO="$1" bash "$TOOL" 2>&1 ); }
rc_of() { ( cd "$1" && CLAUDSOUL_REPO="$1" bash "$TOOL" >/dev/null 2>&1 ); }

A="$TMP/blind"; mk "$A" "Edit|Write|MultiEdit" "при правке файла подаёт связи"
OUT=$(run "$A"); rc_of "$A"; RC=$?
[ "$RC" = "1" ] && ok || bad T1 "слепой страж не отмечен кодом 1 (код $RC)"
grep -qF "probe.sh" <<< "$OUT" && ok || bad T1б "слепой страж не назван поимённо"

B="$TMP/sees"; mk "$B" "Bash|Edit|Write" "при правке файла подаёт связи"
rc_of "$B"; RC=$?
[ "$RC" = "0" ] && ok || bad T2 "страж, видящий Bash, отмечен слепым (код $RC)"

C="$TMP/mute"; mk "$C" "Edit|Write" "считает знания базы"
rc_of "$C"; RC=$?
[ "$RC" = "0" ] && ok || bad T3 "шапка молчит о предмете — судить нельзя, а прибор судит (код $RC)"

D="$TMP/excl"; mk "$D" "Edit|Write" "при правке файла подаёт связи" "предмет — намерение до записи"
rc_of "$D"; RC=$?
[ "$RC" = "0" ] && ok || bad T4 "объявленное исключение не снимает вердикт (код $RC)"

E="$TMP/other"; mkdir -p "$E"
rc_of "$E"; RC=$?
[ "$RC" = "0" ] && ok || bad T5 "без install.sh прибор обязан молчать (код $RC)"

# T6 — положительный контроль счёта: прибор называет ЧИСЛО судимых, а не только слепых.
grep -qE "стражей с предметом «правка файла»: [0-9]+" <<< "$OUT" && ok || bad T6 "знаменатель не назван числом"

# T7 — ПРЕДМЕТ ВИДЕН В КОДЕ. Шапка говорит про правку, а из входа страж путь не читает —
# судить его по прозе нельзя. Повод: `budget-gate.sh` числился слепым ложно, его вывод
# побайтово одинаков на чистом и нарушающем файле.
P="$TMP/prose-only"; mkdir -p "$P/hooks" "$P/scripts"
printf '#!/usr/bin/env bash\n# probe.sh — при правке файла говорит о бюджете\n# en: probe\n#\necho ничего\n' > "$P/hooks/probe.sh"
printf '%s\n' '"PreToolUse": {' '  "matcher": "Edit|Write",' '  "command": "bash ~/.claude/hooks/probe.sh"' '}' > "$P/install.sh"
rc_of "$P"; RC=$?
[ "$RC" = "0" ] && ok || bad T7 "страж без чтения предмета осуждён по одной прозе (код $RC)"

echo "test_guard_event_coverage: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
