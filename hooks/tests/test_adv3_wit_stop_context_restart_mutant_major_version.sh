#!/usr/bin/env bash
# test_adv3_wit_stop_context_restart_mutant_major_version.sh — свидетель stop-context-restart зелен на мутанте, сверяющем версию CLI только по мажору: запись о 2.0.0 при живом 2.1.x считается свежей.
#
# Результат: объявленная работа (scripts/stop-context-restart.sh:5-6,25-27) — запись годна для ТОЙ
#            версии CLI, при которой снята; `--check` краснеет при её смене. Мутант, сравнивающий
#            `${ver%%.*}`, печатает те же строки и проходит все ноги test_stop_context_restart.sh:
#            единственная нога о версии (T5) подкладывает «0.0.0», отличную от живой и мажором.
#            На записи «<мажор живой>.0.0» исходник отвечает 1 «УСТАРЕЛО: запись о версии», мутант —
#            0 «вердикт: …», то есть смена харнесса внутри мажора не перемеряется.
#            Ожидание: свидетель на мутанте красен. Без `claude` в PATH сверять не с чем — SKIP.
# Проверка результата: этот тест.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v claude >/dev/null 2>&1 || { echo "SKIP: нет claude — версию сверять не с чем"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

NOW_CLI=$(claude --version 2>/dev/null | awk '{print $1}')
[ -n "$NOW_CLI" ] || { echo "SKIP: claude --version пуст"; exit 0; }
MAJOR="${NOW_CLI%%.*}"
OLD="$MAJOR.0.0"
[ "$OLD" != "$NOW_CLI" ] || OLD="$MAJOR.0.1"

SB=$(mktemp -d)
( cd "$REPO" && git archive HEAD ) | tar -x -C "$SB" || { echo "FAIL: копия дерева не собралась"; exit 1; }
MUT="$SB/scripts/stop-context-restart.sh"
python3 - "$MUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = 'if [ -n "$_now_cli" ] && [ "$_cli" != "$_now_cli" ]; then'
if needle not in s:
    sys.exit("нет места мутации")
s = s.replace(needle, 'if [ -n "$_now_cli" ] && [ "${_cli%%.*}" != "${_now_cli%%.*}" ]; then')
open(p, "w", encoding="utf-8").write(s)
PY
[ $? -eq 0 ] || { echo "FAIL: мутант не собран"; exit 1; }

# --- T1: мутант делает НЕ объявленную работу — запись о другой версии того же мажора свежа --------
S="$SB/state"; mkdir -p "$S"
jq -n --arg d "2026-09-12 10:00" --argjson e "$(date +%s)" --arg c "$OLD" \
      --arg v additionalContext_restarts_systemMessage_does_not \
      '{date:$d, epoch:$e, cli_version:$c, verdict:$v}' > "$S/stop-context-restart.json"
ORIG=$(cd "$REPO" && STATE_DIR="$S" bash scripts/stop-context-restart.sh --check 2>&1); ORC=$?
MUTO=$(cd "$SB"   && STATE_DIR="$S" bash scripts/stop-context-restart.sh --check 2>&1); MRC=$?
{ [ "$ORC" -eq 1 ] && grep -Fq "УСТАРЕЛО: запись о версии $OLD" <<< "$ORIG"; } && ok \
    || bad T1 "исходник на записи о $OLD при живой $NOW_CLI: rc=$ORC — «${ORIG}»"
{ [ "$MRC" -eq 0 ] && grep -Fq 'вердикт: additionalContext_restarts_systemMessage_does_not' <<< "$MUTO"; } && ok \
    || bad T1 "мутант не разошёлся с исходником: rc=$MRC — «${MUTO}»"

# --- T2: свидетель обязан покраснеть на мутанте --------------------------------------------------
OUT=$(cd "$SB" && bash hooks/tests/test_stop_context_restart.sh 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T2 "свидетель зелен на мутанте «версия по мажору»: rc=$RC — $(tail -1 <<< "$OUT")"

echo ""
echo "adv3 stop-context-restart mutant tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
