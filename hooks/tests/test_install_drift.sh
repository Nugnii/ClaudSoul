#!/usr/bin/env bash
# test_install_drift.sh — Signal 6 в session-start.sh: детект расхождения между
# репозиторием, установкой и регистрацией хуков.
#
# Зачем. `case-2026-04-24-install-drift-silent-safeguards`: 8 релизов подряд
# safeguard-хуки лежали в репозитории и в install.sh, но не попадали в
# `~/.claude/hooks/` — молча неактивны. Тогда закрыли направление «зарегистрирован →
# файла нет». Шапка Signal 6 с тех пор обещала и обратную сторону, но код её не
# делал, и за следующие релизы накопилось 9 хуков, которые работают локально и
# которых нет в репозитории — на другой машине их просто не будет.
# Оба направления теперь проверяются здесь, потому что отказ обоих — тихий:
# ничего не падает, просто защита отсутствует.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-start.sh"
REPO_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_contains() {
    if printf '%s' "$1" | grep -qF "$2"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2'"; fi
}
assert_not_contains() {
    if printf '%s' "$1" | grep -qF "$2"; then FAIL=$((FAIL + 1)); echo "FAIL [$3]: неожиданно найдено '$2'"
    else PASS=$((PASS + 1)); fi
}

# Три независимые плоскости: что зарегистрировано, что установлено, что в репозитории.
# $1 — список зарегистрированных, $2 — установленных, $3 — лежащих в репозитории.
setup() {
    rm -rf "$TMP/home" "$TMP/repo"
    mkdir -p "$TMP/home/.claude/hooks" "$TMP/state" "$TMP/repo/hooks"
    local reg=() n
    for n in $1; do reg+=("$(jq -cn --arg c "bash ~/.claude/hooks/$n" '{type:"command",command:$c}')"); done
    jq -n --argjson hooks "$(printf '%s\n' "${reg[@]}" | jq -s .)" \
        '{hooks:{PreToolUse:[{matcher:"Bash",hooks:$hooks}]}}' > "$TMP/home/.claude/settings.json"
    for n in $2; do printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/home/.claude/hooks/$n"; done
    for n in $3; do printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/repo/hooks/$n"; done
}

run() {
    rm -f "$TMP/state"/startup-signals-*.txt
    printf '{"session_id":"drift-test","source":"startup","cwd":"%s"}' "$TMP/repo" | \
        env HOME="$TMP/home" STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$TMP/repo" \
            bash "$HOOK" >/dev/null 2>&1
    cat "$TMP/state"/startup-signals-*.txt 2>/dev/null || true
}

# === T1: всё согласовано → о дрейфе молчим ===
setup "a.sh b.sh" "a.sh b.sh" "a.sh b.sh"
OUT=$(run)
assert_not_contains "$OUT" "Install drift" "T1: согласованное состояние — тишина"

# === T2: зарегистрирован, но не установлен (направление v1.6.1) ===
setup "a.sh b.sh" "a.sh" "a.sh b.sh"
OUT=$(run)
assert_contains "$OUT" "зарегистрированы, но не установлены" "T2a: прямой дрейф пойман"
assert_contains "$OUT" "b.sh" "T2b: назван конкретный хук"

# === T3: работает и зарегистрирован, но копии в репозитории нет (направление v1.11) ===
setup "a.sh b.sh" "a.sh b.sh" "a.sh"
OUT=$(run)
assert_contains "$OUT" "обратный" "T3a: обратный дрейф пойман"
assert_contains "$OUT" "b.sh" "T3b: назван конкретный хук"
assert_not_contains "$OUT" "зарегистрированы, но не установлены" "T3c: не путается с прямым"

# === T4: оба направления сразу — оба сигнала ===
setup "a.sh b.sh c.sh" "a.sh b.sh" "a.sh c.sh"
OUT=$(run)
assert_contains "$OUT" "зарегистрированы, но не установлены" "T4a: прямой (c.sh не установлен)"
assert_contains "$OUT" "обратный" "T4b: обратный (b.sh не в репозитории)"

# === T5: нет каталога репозитория → обратная проверка молчит, не падает ===
setup "a.sh" "a.sh" "a.sh"
rm -rf "$TMP/repo/hooks"
OUT=$(run)
assert_not_contains "$OUT" "обратный" "T5: без каталога репозитория обратный дрейф не сообщается"

# === T6: живая система — projecta-security-gate заведомо вне репозитория ===
# Регрессия на реальный случай: хук проектный, в ClaudSoul ему не место,
# но он обязан быть виден как untracked, а не молча существовать.
LIVE_UNTRACKED=0
for f in ~/.claude/hooks/*.sh; do
    b=$(basename "$f")
    [ -f "$REPO_ROOT/hooks/$b" ] || LIVE_UNTRACKED=$((LIVE_UNTRACKED + 1))
done
if [ "$LIVE_UNTRACKED" -le 1 ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T6]: в установке $LIVE_UNTRACKED хуков без копии в репозитории (ожидалось ≤1 — только проектный)"; fi

echo ""
echo "install-drift tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
