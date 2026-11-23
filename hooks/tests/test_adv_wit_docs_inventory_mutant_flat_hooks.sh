#!/usr/bin/env bash
# test_adv_wit_docs_inventory_mutant_flat_hooks.sh — свидетель docs-inventory зелен на мутанте, перечисляющем механизмы как `hooks/*.sh` — том перечне мест, чью замену правилом о файле шапка инструмента называет починкой.
#
# Результат: фикстура свидетеля кладёт механизмы только в hooks/, поэтому мутант, не видящий
#            scripts/ и подпапок (регрессия «13 механизмов замера аблации не проверялись вовсе»
#            из шапки инструмента), проходит все ноги test_docs_inventory.sh. На дереве с
#            неописанным scripts/ablation/x.sh исходный инструмент красен и называет x.sh, мутант
#            зелен с «все механизмы дерева упомянуты». Ожидание: свидетель на мутанте красен.
# Проверка результата: этот тест.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/docs-inventory.sh"; WIT="$REPO/hooks/tests/test_docs_inventory.sh"
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
n=$(python3 - "$SBX/scripts/docs-inventory.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "for f in $(git ls-files --cached --others --exclude-standard '*.sh' '*.py' 2>/dev/null); do"   # форма D1240
new = "for f in hooks/*.sh; do"
print(s.count(old))
open(p, "w").write(s.replace(old, new))
PY
)
[ "${n:-0}" -eq 2 ] || { echo "FAIL: мутант не собрался (вхождений $n)"; exit 1; }

# --- T1: свидетель на мутанте обязан покраснеть ------------------------------------------------
OUT=$(bash "$SBX/hooks/tests/test_docs_inventory.sh" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad T1 "свидетель ЗЕЛЕН на мутанте hooks/*.sh: rc=$RC — $(tail -1 <<< "$OUT")"

# --- T2: доказательство — неописанный механизм в подпапке scripts/: исходный красен, мутант зелен --
F="$TMP/f"; mkdir -p "$F/hooks" "$F/docs" "$F/scripts/ablation"
printf '#!/usr/bin/env bash\nFOO_MECH_KNOB="${FOO_MECH_KNOB:-1}"\nexit 0\n' > "$F/hooks/foo-mech.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$F/scripts/ablation/x.sh"
printf '# Архитектура\n\nМеханизм `foo-mech` описан здесь: [исходник](../hooks/foo-mech.sh), рычаг в hooks/foo-mech.sh:2.\n' > "$F/docs/architecture.md"
printf '# README\n\nРычаг `FOO_MECH_KNOB` включает foo-mech.\n' > "$F/README.md"
( cd "$F" && git init -q && git add -A ) || { echo "FAIL: фикстура не собралась"; exit 1; }
OUT=$(cd "$REPO" && CLAUDSOUL_REPO="$F" bash "$TOOL" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok || bad T2 "исходный инструмент на дереве с неописанным scripts/ablation/x.sh: rc=$RC — ${OUT}"
has T2 '· x.sh'
OUT=$(cd "$SBX" && CLAUDSOUL_REPO="$F" bash "$SBX/scripts/docs-inventory.sh" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T2 "мутант неожиданно красен: rc=$RC — ${OUT}"
has T2 'все механизмы дерева упомянуты (проверено механизмов: 1)'

echo ""
echo "adv docs-inventory mutant flat hooks: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
