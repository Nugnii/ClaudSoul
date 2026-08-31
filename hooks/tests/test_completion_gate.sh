#!/usr/bin/env bash
# test_completion_gate.sh — закрытие судит команда пункта, а не отчёт (эскалация
# pattern-completion-by-internal-proxy). Красное ☑ называется, зелёное молчит,
# контракт не вменяется задним числом, кэш по mtime не гоняет неизменное.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/completion-gate.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

mk_backlog() { # $1 файл
    cat > "$1" <<'EOF'
# BACKLOG

### D300 ☑ зелёное закрытие
**Результат.** мир в порядке
**Проверка.** `true` → 0

### D301 ☑ красное закрытие
**Результат.** заявлено, но неправда
**Проверка.** `false` → 0

### D150 ☑ историческое, до контракта
**Проверка.** `false` → 0

### D302 ☐ открытый пункт
**Проверка.** `false` → 0

### D303 ☑ без строки проверки — предмет архиватора
**Результат.** есть только результат
EOF
}

run() { # $1 backlog, $2 cwd
    printf '{"session_id":"cg1","cwd":"%s"}' "${2:-/}" \
      | env CG_BACKLOG="$1" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

# --- T1: красное ☑ названо, зелёное/открытое/историческое/без-строки молчат ---
mk_backlog "$TMP/BACKLOG.md"
OUT=$(run "$TMP/BACKLOG.md")
grep -q 'D301' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1 красное не названо]: $OUT"; }
for id in D300 D150 D302 D303; do
    grep -q "$id" <<< "$OUT" && { FAIL=$((FAIL+1)); echo "FAIL [T1 лишний $id]"; } || PASS=$((PASS+1))
done

# --- T2: вывод — валидный JSON c systemMessage и исполнимой альтернативой ---
printf '%s' "$OUT" | jq -e '.systemMessage | test("верни метке ◐")' >/dev/null 2>&1 \
    && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2 формат/альтернатива]: $OUT"; }

# --- T3: файл только с зелёными ☑ молчит и кэшируется по mtime ---
cat > "$TMP/GREEN.md" <<'EOF'
### D310 ☑ зелёное
**Проверка.** `true` → 0
EOF
OUT=$(run "$TMP/GREEN.md")
[ -z "$OUT" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T3 зелёный молчит]: $OUT"; }
ls "$TMP/state"/completion-gate-*.ok >/dev/null 2>&1 && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T3 кэш не записан]"; }

# --- T4: кэш держит — подмена команды на красную БЕЗ смены mtime не гоняется ---
_OLD_TS=$(date -v-20M '+%Y%m%d%H%M' 2>/dev/null || date -d '20 minutes ago' '+%Y%m%d%H%M' 2>/dev/null)
touch -t "${_OLD_TS}" "$TMP/GREEN.md" 2>/dev/null
OUT=$(run "$TMP/GREEN.md"); MT_BEFORE=$OUT
sed -i.bak 's/`true`/`false`/' "$TMP/GREEN.md" && rm -f "$TMP/GREEN.md.bak"
touch -t "${_OLD_TS}" "$TMP/GREEN.md" 2>/dev/null   # тот же mtime — кэш обязан молчать
OUT=$(run "$TMP/GREEN.md")
[ -z "$OUT" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4 кэш не держит]: $OUT"; }
touch "$TMP/GREEN.md"                                # mtime сменился — красное всплывает
OUT=$(run "$TMP/GREEN.md")
grep -q 'D310' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T4 смена mtime не перечитала]: $OUT"; }

# --- T5: красный файл кэш не получает — каждый Stop напоминает, пока не починено ---
mk_backlog "$TMP/RED2.md"
run "$TMP/RED2.md" >/dev/null
OUT=$(run "$TMP/RED2.md")
grep -q 'D301' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5 красное закэшировалось]"; }

# --- T6: локальный бэклог проекта сессии проверяется тоже ---
mkdir -p "$TMP/proj/.git"
cat > "$TMP/proj/BACKLOG.md" <<'EOF'
### D320 ☑ локальное красное
**Проверка.** `false` → 0
EOF
OUT=$(run "$TMP/BACKLOG.md" "$TMP/proj")
grep -q 'D320' <<< "$OUT" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T6 локальный бэклог]: $OUT"; }

# --- T7: тихая деградация — бэклога нет, пустой stdin ---
OUT=$(run "$TMP/nope.md"); RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7 деградация]"; }
OUT=$(printf '' | env CG_BACKLOG="$TMP/BACKLOG.md" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null); RC=$?
[ "$RC" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7 пустой stdin]"; }

echo "completion-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
