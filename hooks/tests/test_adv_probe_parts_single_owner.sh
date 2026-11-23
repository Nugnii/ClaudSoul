#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# АТАКА: доля вселенной заводится правкой ОДНОГО места. Пока перечень долей собран литералом
# у каждого потребителя, добавление доли во владельце не доходит до следа, а добавление в
# след — до суммы; ровно так 24 сентября 2026 четвёртая доля попала в три места из пяти, и
# сумма в рабочем дереве дала 600 при вселенной 601, никого не потревожив.
#
# Вход: песочница с прибором и одним честным свидетелем. Прогон первый — рамка. Затем
# правится РОВНО ОДНА строка — объявление `BCP_PARTS`, — и прогон повторяется.
#
# Ожидание: доля, вписанная только во владельца, обязана появиться У ОБОИХ потребителей —
# в машинной строке `#PARTS` и в строке журнала. Появилась у одного — перечень собран
# литералом, и это тот самый корень R1.
set -uo pipefail

command -v git     >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$REPO/scripts/behavior-condition-probe.sh"
[ -f "$PROBE" ] || { echo "SKIP: нет $PROBE"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
D="$TMP/repo"
mkdir -p "$D/scripts" "$D/hooks/tests" "$D/.claude-docs"
cp "$PROBE" "$D/scripts/"
for f in subject-probe-lib.sh frame-control-lib.sh timeout-lib.sh portable-lib.sh; do
    [ -f "$REPO/hooks/$f" ] && cp "$REPO/hooks/$f" "$D/hooks/"
done
[ -f "$D/hooks/subject-probe-lib.sh" ] || { echo "SKIP: нет hooks/subject-probe-lib.sh"; exit 0; }

printf '#!/usr/bin/env bash\necho MARKER\n' > "$D/hooks/one.sh"
{ printf '#!/usr/bin/env bash\n'
  printf '# СУДИТ: hooks/one.sh\n'
  printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
  printf 'case "$(bash "$R/hooks/one.sh" 2>&1)" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_honest.sh"
printf 'hooks/one.sh\t\t\t\thooks/tests/test_adv_honest.sh\t\n' > "$D/.claude-docs/dep-index.tsv"
chmod +x "$D/hooks/one.sh" "$D/hooks/tests/"*.sh
( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 \
    || { echo "SKIP: git не отработал"; exit 0; }

# --- РАМКА: прибор обязан отработать и назвать доли, иначе атака не о том -----------------
export STATE_DIR="$TMP/state"
OUT1=$( cd "$D" && CLAUDSOUL_REPO="$D" bash scripts/behavior-condition-probe.sh 2>&1 )
# Конвейер в `grep -q` под pipefail даёт 141 на УСПЕХЕ: grep выходит на первом совпадении,
# производитель получает SIGPIPE. Берём подстроку у case — ни трубы, ни кода возврата.
case "$OUT1" in
    *"#PARTS "*) : ;;
    *) echo "РАМКА НЕ СОБРАЛАСЬ: прибор не назвал доли вселенной строкой #PARTS: $OUT1" >&2
       exit 2 ;;
esac
LOG="$STATE_DIR/behavior-condition-probe.jsonl"
[ -s "$LOG" ] || { echo "РАМКА НЕ СОБРАЛАСЬ: прибор не оставил следа" >&2; exit 2; }

# --- ПРАВИТСЯ РОВНО ОДНО МЕСТО: объявление владельца --------------------------------------
python3 - "$D/scripts/behavior-condition-probe.sh" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
mark = 'BCP_PARTS="'
i = s.index(mark) + len(mark)
s = s[:i] + 'vymyshlennaya=0 ' + s[i:]
io.open(p, "w", encoding="utf-8").write(s)
PY
grep -q 'vymyshlennaya' "$D/scripts/behavior-condition-probe.sh" \
    || { echo "РАМКА НЕ СОБРАЛАСЬ: правка владельца не легла в файл" >&2; exit 2; }
CHANGED=$(grep -rl 'vymyshlennaya' "$D" 2>/dev/null | grep -c .)
[ "$CHANGED" = 1 ] || { echo "РАМКА НЕ СОБРАЛАСЬ: правка задела $CHANGED файлов, а не один" >&2; exit 2; }

rm -f "$LOG"
OUT2=$( cd "$D" && CLAUDSOUL_REPO="$D" bash scripts/behavior-condition-probe.sh 2>&1 )

# --- P1: доля дошла до машинной строки ----------------------------------------------------
PARTS2=$(printf '%s\n' "$OUT2" | grep '^#PARTS ' | tail -1)
case "$PARTS2" in
    *vymyshlennaya=0*) ok ;;
    *) bad P1 "доля, вписанная во владельца, не дошла до строки #PARTS: $PARTS2" ;;
esac

# --- P2: та же доля дошла до следа, и это ВТОРОЙ потребитель -------------------------------
if [ -s "$LOG" ] && grep -q '"vymyshlennaya":0' "$LOG"; then ok
else bad P2 "доля не дошла до следа — перечень у следа свой: $(tail -1 "$LOG" 2>/dev/null)"; fi

# --- P3: вселенная по-прежнему сходится (доля нулевая, сумма меняться не должна) -----------
L="$PARTS2"
T=$(printf '%s\n' "$L" | tr ' ' '\n' | sed -n 's/^total=//p')
S=$(printf '%s\n' "$L" | tr ' ' '\n' | grep -v '^total=' \
    | sed -n 's/^[a-z_][a-z_]*=\([0-9][0-9]*\)$/\1/p' | awk '{s+=$1} END{print s+0}')
if [ -n "$T" ] && [ "$S" = "$T" ]; then ok
else bad P3 "доли не складываются во вселенную после правки владельца: $S != $T ($L)"; fi

echo "probe parts single owner: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
