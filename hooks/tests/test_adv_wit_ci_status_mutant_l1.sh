#!/usr/bin/env bash
# test_adv_wit_ci_status_mutant_l1.sh — свидетель ci-status зелен на мутанте с `gh run list -L 1` — том самом дефекте, ради которого инструмент написан.
#
# Результат: поддельный gh свидетеля печатает все строки независимо от `-L`, поэтому мутант,
#            спрашивающий только самый свежий прогон, проходит все шесть ног test_ci_status.sh.
#            С gh, чтущим `-L`, тот же мутант на сцене T1 (свежий чужой зелёный, свой красный)
#            отвечает «прогон … не найден» кодом 2 вместо «failure» кодом 1 — то есть не делает
#            объявленной работы «исход прогона ИМЕННО ЭТОГО sha». Ожидание: свидетель на мутанте красен.
# Проверка результата: этот тест.
set -uo pipefail
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/ci-status.sh"; WIT="$REPO/hooks/tests/test_ci_status.sh"
[ -f "$TOOL" ] && [ -f "$WIT" ] || { echo "FAIL: нет инструмента или свидетеля"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Песочница — из mktemp: имя цели записи рождается там, писатель у него один по построению
# (род H реестра судит по происхождению имени; `SBX="$TMP/sbx"` резолва до mktemp не давало).
SBX=$(mktemp -d "$TMP/sbx.XXXXXX"); mkdir -p "$SBX/scripts" "$SBX/hooks/tests"
cp "$TOOL" "$SBX/scripts/"; cp "$WIT" "$SBX/hooks/tests/"
( cd "$SBX" && git init -q && : > seed && git add seed && git -c user.name=t -c user.email=t@e commit -q -m seed ) \
    || { echo "FAIL: песочница не собралась"; exit 1; }
# Мутант: единственная правка — окно опроса.
n=$(python3 - "$SBX/scripts/ci-status.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "gh run list -L 20 "
new = "gh run list -L 1 "
print(s.count(old))
open(p, "w").write(s.replace(old, new))
PY
)
[ "${n:-0}" -eq 1 ] || { echo "FAIL: мутант не собрался (вхождений $n)"; exit 1; }

# --- T1: свидетель на мутанте обязан покраснеть ------------------------------------------------
OUT=$(bash "$SBX/hooks/tests/test_ci_status.sh" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T1 "свидетель ЗЕЛЕН на мутанте -L 1: rc=$RC — $(tail -1 <<< "$OUT")"

# --- T2: доказательство, что мутант считает мимо — gh, чтущий -L, сцена T1 свидетеля -----------
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/state"
for t in bash git awk sed grep sleep cat head; do p=$(command -v "$t") && ln -s "$p" "$BIN/$t"; done
MINE=$(cd "$SBX" && git rev-parse HEAD)
OTHER=$(printf '%s' "$MINE" | tr '0-9a-f' 'f0123456789abcde')
{
    printf '#!/usr/bin/env bash\nn=20; while [ $# -gt 0 ]; do case "$1" in -L) n="$2"; shift ;; esac; shift; done\n'
    printf 'head -n "$n" <<LINES\n2 %s completed success\n1 %s completed failure\nLINES\n' "$OTHER" "$MINE"
} > "$BIN/gh"; chmod +x "$BIN/gh"
run_in() {   # $1 — каталог с scripts/ci-status.sh
    OUT=$(cd "$SBX" && PATH="$BIN" STATE_DIR="$TMP/state" CI_WAIT=0 CI_POLL_INTERVAL=0 CI_MAX_TRIES=2 bash "$1/scripts/ci-status.sh" "$MINE" 2>&1); RC=$?
}
run_in "$REPO"
[ "$RC" -eq 1 ] && ok || bad T2 "исходный инструмент с честным gh: rc=$RC — ${OUT}"
has T2 "прогон 1 для ${MINE:0:7}: failure"
run_in "$SBX"
[ "$RC" -eq 2 ] && ok || bad T2 "мутант с честным gh ответил rc=$RC — ${OUT}"
has T2 "прогон для ${MINE:0:7} не найден"

echo ""
echo "adv ci-status mutant -L 1: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
