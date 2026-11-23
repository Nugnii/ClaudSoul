#!/usr/bin/env bash
# СУДИТ: scripts/setup-call-guard.py
# test_setup_messages_locate_themselves.sh — сообщение подготовки называет свою строку вычислением, а не числом (D1306).
#
# Повод: адрес «подготовка мира не удалась: <файл>:<строка>» был вписан числом в тот же файл, который он описывает, —
# 710 сообщений в 190 файлах; каждая нога, вставленная выше, сдвигала их, и правка шла вручную (шесть раз за одну
# сессию, D1251 называл), а поправка по смещению хранила и ложные соответствия.
# L1 — в дереве нет сообщения подготовки с вписанным номером строки (*.sh, *.py под git);
# L2 — генератор починок (`setup-call-guard.py --fix`) ставит вычисляемый адрес, и упавшая подготовка печатает строку,
#      на которой стоит её вызов, — после вставки строк выше тоже.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="$REPO/scripts/setup-call-guard.py"
[ -f "$GEN" ] || { echo "FAIL: нет $GEN"; exit 1; }
command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || { echo "SKIP: нет python3 или git"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

LIT=$(git -C "$REPO" grep -nE 'подготовка мира не удалась: [^ :"]+:[0-9]+' -- '*.sh' '*.py' 2>/dev/null)
N=$(printf '%s' "$LIT" | awk 'NF { n++ } END { print n + 0 }')
[ "$N" = 0 ] && ok || bad L1 "сообщений подготовки с вписанным номером строки: $N, первые: $(printf '%s\n' "$LIT" | head -3 | cut -c1-160 | tr '\n' ' ')"

TMP=$(mktemp -d)   # временное уберёт система (D360)
mkdir -p "$TMP/hooks/tests"
F="$TMP/hooks/tests/test_fixture_mute.sh"
printf '%s\n' '#!/usr/bin/env bash' 'D="$1"' 'cp "$D/нет-такого" "$D/куда" 2>/dev/null' 'echo дошёл' > "$F"
( cd "$TMP" && python3 "$GEN" --root "$TMP" --fix >/dev/null 2>&1 ) || { echo "подготовка мира не удалась: генератор починок упал на фикстуре" >&2; exit 1; }
grep -q 'подготовка мира не удалась' "$F" && ok || bad L2a "генератор не поставил стража немой подготовке: $(cat "$F")"
# Вставка двух строк выше: адрес обязан ехать вместе с вызовом, без правки.
python3 - "$F" <<'PY' || { echo "подготовка мира не удалась: вставка строк в фикстуру" >&2; exit 1; }
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read().split("\n")
s[1:1] = ["# вставка 1", "# вставка 2"]
open(p, "w", encoding="utf-8").write("\n".join(s))
PY
want=$(grep -n 'нет-такого' "$F" | cut -d: -f1)
got=$(bash "$F" "$TMP" 2>&1 >/dev/null | sed -n 's/.*подготовка мира не удалась: [^ ]*:\([0-9][0-9]*\).*/\1/p')
[ -n "$want" ] && [ "$got" = "$want" ] && ok || bad L2b "упавшая подготовка назвала строку «${got}», вызов стоит на «${want}»"

echo "адреса подготовки: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
