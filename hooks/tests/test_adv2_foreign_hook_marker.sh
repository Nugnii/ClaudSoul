#!/usr/bin/env bash
# test_adv2_foreign_hook_marker.sh — обратный дрейф в session-start.sh: маркер
# `claudsoul-foreign-hook` ищется как подстрока где угодно в файле.
#
# Атака 1 (доверие). Признак принадлежности чужому проекту — `grep -q
# 'claudsoul-foreign-hook' "$DRIFT_HOOKS_DIR/$name"`. Совпадение засчитывается в любой
# строке файла, включая комментарий, который маркер ЦИТИРУЕТ. Хук ClaudSoul, чья шапка
# объясняет соглашение («чужие помечаются маркером claudsoul-foreign-hook, этот — наш»),
# сам себя выводит из-под проверки: работает, зарегистрирован, копии в репозитории нет —
# и на другой машине его не будет, а сигнал молчит. Ровно тот отказ, ради которого блок
# и писали. В дереве проекта такая цитата уже есть — в session-start.sh и в
# hooks/tests/test_install_drift.sh.
#
# Атака 2 (состояние). Весь Signal 6 — и обратный блок вместе с ним — не доживает до
# исполнения, если в `~/.claude/hooks/` нет ни одного `*.sh`. Строка
#     DRIFT_INSTALLED=$(ls "$DRIFT_HOOKS_DIR"/*.sh 2>/dev/null | xargs -n1 basename | sort -u)
# при непопавшем глобе даёт `ls` с кодом 1, `pipefail` тянет код в присваивание, а
# `set -euo pipefail` из шапки файла роняет ХУК: exit 1, stderr пуст, ни одного сигнала
# дрейфа. Каталог без `.sh` — это ровно состояние «install.sh ещё не отработал», то самое,
# ради которого сигнал и заводили (case-2026-04-24-install-drift-silent-safeguards).
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-start.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# setup <зарегистрированные> <установленные с телом-по-умолчанию> <лежащие в репозитории>
setup() {
    rm -rf "$TMP/home" "$TMP/repo" "$TMP/state"
    mkdir -p "$TMP/home/.claude/hooks" "$TMP/state" "$TMP/repo/hooks"
    local reg=() n
    for n in $1; do reg+=("$(jq -cn --arg c "bash ~/.claude/hooks/$n" '{type:"command",command:$c}')"); done
    jq -n --argjson hooks "$(printf '%s\n' "${reg[@]}" | jq -s .)" \
        '{hooks:{PreToolUse:[{matcher:"Bash",hooks:$hooks}]}}' > "$TMP/home/.claude/settings.json"
    for n in $2; do printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/home/.claude/hooks/$n"; done
    for n in $3; do printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/repo/hooks/$n"; done
}

install_with_quote() {   # хук ClaudSoul, чья ШАПКА цитирует маркер
    cat > "$TMP/home/.claude/hooks/$1" <<'BODY'
#!/usr/bin/env bash
# our-hook.sh — SessionStart: наш хук, дом в репозитории ClaudSoul.
#
# Соглашение: хук чужого проекта помечают строкой claudsoul-foreign-hook,
# и тогда обратный дрейф его не считает. Этот хук — НАШ, маркера не несёт.
exit 0
BODY
}

run() {
    rm -f "$TMP/state"/startup-signals-*.txt
    printf '{"session_id":"adv2-drift","source":"startup","cwd":"%s"}' "$TMP/repo" | \
        env HOME="$TMP/home" STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$TMP/repo" \
            bash "$HOOK" >/dev/null 2>"$TMP/run-err" || echo "$?" >> "$TMP/run-rc"
    cat "$TMP/state"/startup-signals-*.txt 2>/dev/null || true
}
# run() зовётся через $(…) — счётчики внутри не выживают, смерть хука копится флаг-файлом
# и предъявляется один раз перед итогом (D220: смерть продюсера — не «пустой вывод»).

reverse_line() { grep -F 'Install drift (обратный)' <<< "$1" || true; }

check_named() {   # check_named <label> <вывод> <имя>
    if grep -qF "$3" <<< "$(reverse_line "$2")"; then
        PASS=$((PASS + 1)); echo "PASS [$1]"
    else
        FAIL=$((FAIL + 1)); echo "FAIL [$1]: '$3' не назван в обратном сигнале"
        echo "       сигналы: ${2:-<пусто>}"
    fi
}
check_not_named() {   # check_not_named <label> <вывод> <имя>
    if grep -qF "$3" <<< "$(reverse_line "$2")"; then
        FAIL=$((FAIL + 1)); echo "FAIL [$1]: '$3' назван в обратном сигнале"
        echo "       сигналы: ${2:-<пусто>}"
    else
        PASS=$((PASS + 1)); echo "PASS [$1]"
    fi
}

# ── контроль: наш хук без всяких упоминаний маркера — сигнал есть ─────────────
setup "our-hook.sh" "our-hook.sh" ""
check_named "контроль: хук без маркера, копии в репозитории нет" "$(run)" "our-hook.sh"

# ── атака 1: тот же хук, шапка цитирует маркер ────────────────────────────────
setup "our-hook.sh" "" ""
install_with_quote "our-hook.sh"
check_named "атака 1: маркер лишь процитирован в комментарии — сигнал обязан остаться" \
    "$(run)" "our-hook.sh"

# ── атака 2: каталог хуков без единого *.sh — хук падает, сигналов нет ────────
setup "ghost.sh" "" "ghost.sh"
printf 'print("guard")\n' > "$TMP/home/.claude/hooks/guard.py"   # каталог не пуст, но .sh нет
rm -f "$TMP/state"/startup-signals-*.txt
printf '{"session_id":"adv2-drift","source":"startup","cwd":"%s"}' "$TMP/repo" | \
    env HOME="$TMP/home" STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$TMP/repo" \
        bash "$HOOK" >/dev/null 2>"$TMP/err"
RC=$?
OUT=$(cat "$TMP/state"/startup-signals-*.txt 2>/dev/null || true)
if [ "$RC" -eq 0 ]; then
    PASS=$((PASS + 1)); echo "PASS [атака 2a: хук завершился кодом 0]"
else
    FAIL=$((FAIL + 1))
    echo "FAIL [атака 2a: каталог ~/.claude/hooks без *.sh]: хук упал, exit=$RC, stderr='$(cat "$TMP/err")'"
fi
if grep -qF 'Install drift' <<< "$OUT"; then
    PASS=$((PASS + 1)); echo "PASS [атака 2b: сигнал дрейфа выдан]"
else
    FAIL=$((FAIL + 1))
    echo "FAIL [атака 2b: ghost.sh зарегистрирован и не установлен — сигнал дрейфа обязан быть]"
    echo "       сигналы: ${OUT:-<пусто>}"
fi

if [ -f "$TMP/run-rc" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL [run: хук падал, rc: $(tr '\n' ' ' < "$TMP/run-rc"), stderr: $(tail -c 200 "$TMP/run-err" 2>/dev/null)]"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
