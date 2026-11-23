#!/usr/bin/env bash
# test_undefined_function_remote_exec.sh — клауза «запускается файл, которого нет» не судит
# команду, исполняемую на чужом хосте.
#
# Результат: `bash x.sh` внутри `docker run … bash -c '…'` / `ssh host '…'` не объявляется
#            несуществующим по дереву этой машины; голый `bash x.sh` — объявляется
# Проверка результата: bash hooks/tests/test_undefined_function_remote_exec.sh даёт 0
#
# Повод: 12 сентября 2026 страж дважды назвал несуществующим тест, который жил и запускался
# в контейнере (`docker run -v "$PWD":/repo … bash -c 'cd /work/hooks/tests; bash test_x.sh'`).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/undefined-function-check.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"
say() {  # $1 — команда; печатает additionalContext стража
    jq -cn --arg c "$1" --arg d "$TMP" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
NOPE="nope-$RANDOM$RANDOM.sh"
# T0 — положительный контроль: голый вызов несуществующего файла объявляется
OUT=$(say "bash $NOPE")
case "$OUT" in *"которого нет"*) ok ;; *) bad "T0" "положительный контроль: голый bash $NOPE не назван: [$OUT]" ;; esac
# T1 — внутри docker run … bash -c '…' (многострочно, как в живом вызове)
OUT=$(say "docker run --rm -v \"\$PWD\":/repo:ro -w /repo debian:stable-slim bash -c '
  cd /work/hooks/tests; bash $NOPE 2>&1 | tail -3'")
[ -z "$OUT" ] && ok || bad "T1" "вызов внутри docker run судится по дереву хоста: [$OUT]"
# T2 — внутри ssh
OUT=$(say "ssh host 'cd /srv && bash $NOPE'")
[ -z "$OUT" ] && ok || bad "T2" "вызов внутри ssh судится по дереву хоста: [$OUT]"
# T3 — маркер ПОСЛЕ голого вызова не спасает его: судится текст до маркера
OUT=$(say "bash $NOPE && docker run img true")
case "$OUT" in *"которого нет"*) ok ;; *) bad "T3" "голый вызов перед docker run не назван: [$OUT]" ;; esac
echo "undefined-function remote exec: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
