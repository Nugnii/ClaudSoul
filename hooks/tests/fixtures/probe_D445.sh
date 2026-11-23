#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh scripts/backlog-archive.sh
# probe_D445.sh - проба пункта D445: templates/BACKLOG.md.tmpl не учит контракту закрытого
# пункта (Результат./Проверка., BACKLOG.md:25-32), который scripts/backlog-archive.sh
# требует у закрытого пункта от BACKLOG_CONTRACT_MIN_ID (D431, коммит 444677f; гейты :337-340 и :363-364).
# Результат: шаблон учит обеим строкам контракта с привязкой к порогу D200 (как сам BACKLOG.md).
# Проверка результата: bash hooks/tests/fixtures/probe_D445.sh -> 0
#
# Коды: 0 - шаблон учит контракту; 1 - дефект наблюден (шаблон молчит); 2 - рамка не собралась.
# Механизм под судом (архиватор+библиотека) берется из CLAUDSOUL_REPO, копируется в песочницу;
# судится ПОВЕДЕНИЕ архиватора на синтетическом закрытии, а не слово в исходнике.
# Предел: суд по литералам Результат./Проверка. плюс упоминание порога 200 рядом, а не
# голому наличию двух строк без всякой привязки к контракту.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
TMPL="$MECH/templates/BACKLOG.md.tmpl"
ARCHIVER="$MECH/scripts/backlog-archive.sh"
LIB="$MECH/hooks/backlog-lib.sh"
[ -f "$TMPL" ]     || { echo "probe_D445: нет $TMPL" >&2; exit 2; }
[ -f "$ARCHIVER" ] || { echo "probe_D445: нет $ARCHIVER" >&2; exit 2; }
[ -f "$LIB" ]      || { echo "probe_D445: нет $LIB" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D445: нужен python3" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D445: нет временного каталога" >&2; exit 2; }
trap "rm -rf $T" EXIT
mkdir -p "$T/scripts" "$T/hooks"
cp "$ARCHIVER" "$T/scripts/backlog-archive.sh" || { echo "probe_D445: копия архиватора не удалась" >&2; exit 2; }
cp "$LIB" "$T/hooks/backlog-lib.sh" || { echo "probe_D445: копия библиотеки не удалась" >&2; exit 2; }
# Правило исполнения «Проверки» архиватор берёт из своего дерева (`hooks/lib/bounded_run.py`, D1199).
mkdir -p "$T/hooks/lib" && cp "$MECH/hooks/lib/bounded_run.py" "$MECH/hooks/lib/backlog_cmd.py" "$T/hooks/lib/" \
    || { echo "probe_D445: копия hooks/lib/bounded_run.py не удалась" >&2; exit 2; }
{
  echo "# BACKLOG"
  echo ""
  echo "## Открытые пункты"
  echo ""
  echo "(пусто)"
  echo ""
  echo "## Выполненные"
  echo ""
  echo "- ☑ **D5** старый пункт, контракт не распространяется (порог D200)."
  echo "- ☑ **D999** новый пункт, закрыт ровно тем, чему учит сегодняшний шаблон - без контракта."
} > "$T/BACKLOG.md"
# BACKLOG_CHECKS_NESTED снимается НАМЕРЕННО. Архиватор ставит его в окружение команд
# «Проверки» против размножения процессов, и вложенный прогон выходит сразу, ничего не
# судя, — а предмет ЭТОЙ пробы и есть суждение архиватора. Без снятия проба краснела бы
# кодом 2 («контроль не держится») ровно тогда, когда её зовёт архиватор, то есть у
# закрытого пункта. Размножения тут нет по построению: судится BACKLOG.md ПЕСОЧНИЦЫ,
# и единственная команда «Проверки» в нём — `true`.
OUT=$(env -u BACKLOG_CHECKS_NESTED CLAUDSOUL_REPO="$T" bash "$T/scripts/backlog-archive.sh" check 2>&1)
if ! grep -q "D999" <<< "$OUT"; then
    echo "probe_D445: контроль - D999 без контракта не назван заблокированным, судить нечем: $OUT" >&2
    exit 2
fi
if grep -q "D5:" <<< "$OUT"; then
    echo "probe_D445: контроль - D5 (< порога D200) неожиданно заблокирован, контраст не держится: $OUT" >&2
    exit 2
fi
# СУД - ПОВЕДЕНЧЕСКИЙ, а не по словам в файле. Первая редакция пробы искала в шаблоне два
# литерала и цифру 200; скептик позеленил её одной мусорной строкой
# "xx **Результат.** **Проверка.** 200 xx", дописанной к СТАРОМУ шаблону. Теперь из шаблона
# ИЗВЛЕКАЮТСЯ его собственные строки контракта, из них собирается закрытие, и судит их
# архиватор: шаблон, учащий не тому, даёт заблокированный пункт, а не зелёный.
cat > "$T/extract.py" <<'PYEOF'
import re, sys
# Строки берутся ТОЛЬКО из огороженного блока (```), то есть из ОБРАЗЦА, которым шаблон
# учит, а не откуда угодно в файле. Скептик позеленил прежнюю редакцию, дописав к старому
# шаблону три мусорные строки с нужными префиксами: они стояли в прозе, и суд их принимал.
text = open(sys.argv[1], encoding="utf-8").read()
fenced = re.findall(r"^```.*?^```", text, re.S | re.M)
lines = [l for block in fenced for l in block.split("\n")]
res = [l.strip() for l in lines if l.strip().startswith("**Результат.**")]
chk = [l.strip() for l in lines if l.strip().startswith("**Проверка.**")]
if not res or not chk:
    sys.exit(1)
# Заполнитель команды заменяется исполнимой: шаблон учит ФОРМЕ, команду подставляет автор
# пункта. Подстановка идёт только внутрь кавычек-обратников - если их нет, строка уйдёт
# как есть, архиватор назовёт её неразбираемой, и это верный вердикт о таком шаблоне.
q = chr(96)
check = re.sub(q + "[^" + q + "]*" + q, q + "true" + q, chk[0], count=1)
print("  " + res[0])
print("  " + check)
PYEOF
CONTRACT=$(python3 "$T/extract.py" "$TMPL") || { echo "probe_D445: дефект - в $TMPL нет строк контракта (Результат./Проверка.), извлекать нечего" >&2; exit 1; }

{
  echo "# BACKLOG"
  echo ""
  echo "## Открытые пункты"
  echo ""
  echo "(пусто)"
  echo ""
  echo "## Выполненные"
  echo ""
  echo "- ☑ **D998** закрытие, написанное ПО ШАБЛОНУ."
  echo "$CONTRACT"
} > "$T/BACKLOG.md"
OUT2=$(env -u BACKLOG_CHECKS_NESTED CLAUDSOUL_REPO="$T" bash "$T/scripts/backlog-archive.sh" check 2>&1)
if grep -q "D998" <<< "$OUT2"; then
    echo "probe_D445: дефект - закрытие, написанное ровно по шаблону, архиватор всё равно блокирует: $OUT2" >&2
    exit 1
fi
grep -q "200" "$TMPL" || { echo "probe_D445: дефект - шаблон учит строкам, но молчит о пороге (200)" >&2; exit 1; }
exit 0
