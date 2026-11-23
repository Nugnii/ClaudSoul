#!/usr/bin/env bash
# test_adv3_wit_disagreement_revocation_mutant_match.sh — свидетель disagreement-revocation-check зелен на трёх мутантах сопоставления отзыва: без сессии, без «более ранний», без «ровно один».
#
# Результат: объявленная работа (scripts/disagreement-revocation-check.sh:2-3,68-69) — отзыв имеет
#            РОВНО ОДИН БОЛЕЕ РАННИЙ оригинал той же (knowledge, session). Три мутанта, каждый снимает
#            одно из трёх условий, печатают те же строки и проходят все восемь ног
#            test_disagreement_revocation_check.sh: в фикстуре свидетеля отзыв и оригинал всегда в
#            одной сессии, оригинал всегда раньше, и на один оригинал приходится один отзыв.
#            На журнале «оригинал в другой сессии» / «оригинал позже отзыва» / «два отзыва на один
#            оригинал» исходник отвечает 1 «отзывов без сопоставимого оригинала: 1», мутанты — 0
#            «формат един, отзывы сопоставлены». Ожидание: свидетель на каждом мутанте красен.
# Проверка результата: этот тест.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

SB=$(mktemp -d)
( cd "$REPO" && git archive HEAD ) | tar -x -C "$SB" || { echo "FAIL: копия дерева не собралась"; exit 1; }
MUT="$SB/scripts/disagreement-revocation-check.sh"
cp "$MUT" "$SB/orig-tool.sh"

mutate() {   # $1 — что снять: session | date | once
    cp "$SB/orig-tool.sh" "$MUT"
    python3 - "$MUT" "$1" <<'PY'
import sys
p = sys.argv[1]
what = sys.argv[2]
s = open(p, encoding="utf-8").read()
if what == "session":
    needle = '                and x.get("session") == r.get("session")\n'
    repl = ''
elif what == "date":
    needle = '                and x.get("date", "") < r.get("date", "")):'
    repl = '                ):'
else:
    needle = 'if j in consumed or "supersedes" in x:'
    repl = 'if "supersedes" in x:'
if needle not in s:
    sys.exit("нет места мутации: " + what)
s = s.replace(needle, repl)
open(p, "w", encoding="utf-8").write(s)
PY
}

S="$SB/state"; J="$S/disagreement-outcomes.jsonl"
ORIG_S1='{"date":"2026-09-01","session":"s1","knowledge":"pattern-x","confidence":4,"outcome":"confirmed","case":"c1"}'
ORIG_S1_LATE='{"date":"2026-09-03","session":"s1","knowledge":"pattern-x","confidence":4,"outcome":"confirmed","case":"c1"}'
REVO_S1='{"date":"2026-09-02","session":"s1","knowledge":"pattern-x","confidence":4,"outcome":"revoked","case":"c1","supersedes":"confirmed","note":"n"}'
REVO_S1_B='{"date":"2026-09-03","session":"s1","knowledge":"pattern-x","confidence":4,"outcome":"revoked","case":"c1","supersedes":"confirmed","note":"n"}'
REVO_S2='{"date":"2026-09-02","session":"s2","knowledge":"pattern-x","confidence":4,"outcome":"revoked","case":"c1","supersedes":"confirmed","note":"n"}'

run_orig() { OUT=$(cd "$REPO" && STATE_DIR="$S" bash scripts/disagreement-revocation-check.sh check 2>&1); RC=$?; }
run_mut()  { OUT=$(cd "$SB"   && STATE_DIR="$S" bash scripts/disagreement-revocation-check.sh check 2>&1); RC=$?; }
witness()  { WOUT=$(cd "$SB" && bash hooks/tests/test_disagreement_revocation_check.sh 2>&1); WRC=$?; }

check_pair() {   # $1 метка
    run_orig
    { [ "$RC" -eq 1 ] && grep -Fq 'отзывов без сопоставимого оригинала: 1' <<< "$OUT"; } && ok \
        || bad "$1" "исходник не отверг журнал: rc=$RC — «${OUT}»"
    run_mut
    { [ "$RC" -eq 0 ] && grep -Fq 'формат един, отзывы сопоставлены' <<< "$OUT"; } && ok \
        || bad "$1" "мутант не разошёлся с исходником: rc=$RC — «${OUT}»"
    witness
    [ "$WRC" -ne 0 ] && ok || bad "$1" "свидетель зелен на мутанте: rc=$WRC — $(tail -1 <<< "$WOUT")"
}

# --- T1: сессия снята — отзыв из s2 сопоставлен с оригиналом из s1 -----------------------------
mutate session; mkdir -p "$S"; printf '%s\n%s\n' "$ORIG_S1" "$REVO_S2" > "$J"
check_pair T1

# --- T2: «более ранний» снят — оригинал ПОЗЖЕ отзыва сопоставлен ---------------------------------
mutate date; printf '%s\n%s\n' "$ORIG_S1_LATE" "$REVO_S1" > "$J"
check_pair T2

# --- T3: «ровно один» снят — два отзыва на один оригинал сопоставлены оба ------------------------
mutate once; printf '%s\n%s\n%s\n' "$ORIG_S1" "$REVO_S1" "$REVO_S1_B" > "$J"
check_pair T3

echo ""
echo "adv3 disagreement-revocation mutant tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
