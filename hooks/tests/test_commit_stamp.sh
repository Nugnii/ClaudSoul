#!/usr/bin/env bash
# СУДИТ: scripts/commit-stamp.sh hooks/commit-trap.sh
# test_commit_stamp.sh — коммит агента получает отметку «чем проверен», коммит владельца — нет.
#
# Результат: (1) самопроверка прибора отметки зелёная (окно по времени, три состояния, запрос «ничем»);
#            (2) насквозь через ловушку git: коммит агента с прогоном теста в окне расшифровки получает строку
#            журнала «тесты», коммит владельца в терминале (без CLAUDECODE/AI_AGENT) строки не получает.
# Проверка результата: bash hooks/tests/test_commit_stamp.sh даёт 0
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TRAP="$REPO/hooks/commit-trap.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"
export HOME="$TMP/home" GIT_CONFIG_GLOBAL="$TMP/gitconfig" STATE_DIR="$TMP/state" CLAUDSOUL_ROOT="$REPO"
export COMMIT_STAMP_JOURNAL="$TMP/stamps.tsv"
git config --global user.name t; git config --global user.email t@l; git config --global init.defaultBranch main

# (1) самопроверка прибора
OUT=$(bash "$REPO/scripts/commit-stamp.sh" --self-test 2>&1) && ok || bad S1 "самопроверка прибора красная: ${OUT:0:300}"

# (2) насквозь через ловушку
R="$TMP/r"; git init -q "$R" && git -C "$R" commit -q --allow-empty -m "chore: начало" \
    && bash "$TRAP" --install "$R" >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: hooks/tests/test_commit_stamp.sh:$LINENO" >&2; exit 1; }
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"type":"assistant","timestamp":"%s","cwd":"%s","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bash hooks/tests/test_x.sh"}}]}}\n' \
    "$NOW" "$R" > "$TMP/s.jsonl"   # cwd — репозиторий коммита: прогон в другом репозитории не засчитывается
export COMMIT_STAMP_TRANSCRIPT="$TMP/s.jsonl"

stamp_of() {   # <коммит> → отметка; ждёт отсоединённую запись до 15 с
    local i=0 v=""
    while [ $i -lt 30 ]; do
        v=$(awk -F'\t' -v s="$1" '$1 == s { print $7 }' "$COMMIT_STAMP_JOURNAL" 2>/dev/null)
        [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
        sleep 0.5; i=$((i + 1))
    done
}
CLAUDECODE=1 git -C "$R" commit -q --allow-empty -m "chore: коммит агента" >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: hooks/tests/test_commit_stamp.sh:$LINENO" >&2; exit 1; }
A=$(git -C "$R" rev-parse HEAD)
V=$(stamp_of "$A")
[ "$V" = "тесты" ] && ok || bad E1 "коммит агента с прогоном теста в окне получил «${V:-нет строки}», ждали «тесты»"

env -u CLAUDECODE -u AI_AGENT git -C "$R" commit -q --allow-empty -m "chore: коммит владельца" >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: hooks/tests/test_commit_stamp.sh:$LINENO" >&2; exit 1; }
O=$(git -C "$R" rev-parse HEAD)
sleep 3
grep -q "^$O" "$COMMIT_STAMP_JOURNAL" 2>/dev/null && bad E2 "коммит владельца в терминале получил отметку" || ok
L=$(cd "$R" && bash "$REPO/scripts/commit-stamp.sh" --list "$R" 5)
grep -q "^${O:0:8}  не отмечен" <<< "$L" && ok || bad E3 "запрос не назвал коммит владельца «не отмечен»: $L"

# E4: отметка идёт отсоединённым процессом — медленный прибор коммит не задерживает (скептик opus, M3/M4).
FK="$TMP/fake root"; mkdir -p "$FK/scripts"; printf '#!/usr/bin/env bash\nsleep 8\n' > "$FK/scripts/commit-stamp.sh"
T0=$(date +%s)
CLAUDSOUL_ROOT="$FK" CLAUDECODE=1 git -C "$R" commit -q --allow-empty -m "chore: медленная отметка" >/dev/null 2>&1 \
    || { echo "подготовка мира не удалась: hooks/tests/test_commit_stamp.sh:$LINENO" >&2; exit 1; }
[ $(( $(date +%s) - T0 )) -lt 5 ] && ok || bad E4 "коммит ждал отметку $(( $(date +%s) - T0 )) с — вызов не отсоединён"

echo "commit stamp: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
