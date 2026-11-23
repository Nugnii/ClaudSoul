#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_backlog_cmd_ring.sh hooks/backlog-lib.sh scripts/backlog-archive.sh hooks/completion-gate.sh scripts/backlog-refresh-readings.sh
# test_adv2_cmdring_witness_blind_at_depth.sh — свидетель ограды кольца (D503) задаёт свою рамку, а не наследует глубину вызова: в рамке исполнителя «Проверки» он различает поломку КЛЮЧА, а на исправном механизме зелёный на любой унаследованной глубине.
#
# Атака (противник ограды кольца, раунд 2, 1 октября 2026). test_backlog_cmd_ring.sh объявляет себя
# «Проверкой результата» механизма и снимает только BACKLOG_CHECKS_NESTED; BACKLOG_CMD_RUNNING он
# НАСЛЕДУЕТ — тот самый род D334 («красный от рамки неотличим от красного по делу»), только рамка
# теперь в другой переменной. Ноги R1–R6 судят «команда исполнилась один раз, вложенный прогон сказал
# „кольцо“», а слово «кольцо» печатают обе ограды: исключение по ключу и предел глубины («кольцо не
# исключено»). Отсюда два ложных вердикта одного свидетеля:
#   · глубина 1 — так его исполняет всякий исполнитель «Проверки» (архиватор, гейт кладут ключ пункта
#     в BACKLOG_CMD_RUNNING): вложенный исполнитель каждой ноги упирается в ПРЕДЕЛ раньше ключа, и
#     мутант без исключения по ключу зелёный 12 из 12 — ☑, чья «Проверка» этот свидетель, уезжает в
#     архив с показанием, которое ничего не различило (прямой прогон того же мутанта — 7 красных);
#   · глубина 2 — исправный механизм красный 0 из 12: «команда пункта не исполнилась ни разу — рамка
#     ноги не собралась».
# Девять свидетелей test_adv_cmdring_* рамку задают сами (`unset … BACKLOG_CMD_RUNNING`) — вопреки
# шапке ограды «рамки свидетелей её не касаются»; главный свидетель — нет.
#
# Рамка: копия hooks/ и scripts/ в песочнице; мутант — ключ ограды с одноразовой добавкой ($RANDOM в
# библиотеке, у питоновских исполнителей — через неё же, D1238), так что ключ из
# BACKLOG_CMD_RUNNING не совпадает никогда, а предел глубины цел. Контроль: прямой прогон
# свидетеля мутанта красный.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
export CLAUDSOUL_LOCK_TRIES=5
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX CLAUDSOUL_REPO BACKLOG_FILE BACKLOG_ARCHIVE
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"

M="$T/m"; mkdir -p "$M/hooks/tests" "$M/scripts"
cp "$REPO"/hooks/*.sh "$M/hooks/"
cp -R "$REPO/hooks/lib" "$M/hooks/"
cp "$REPO"/scripts/*.sh "$M/scripts/"
cp "$REPO/hooks/tests/test_backlog_cmd_ring.sh" "$REPO/hooks/tests/test_backlog_green_side.sh" "$REPO/hooks/tests/alerts-read.sh" "$M/hooks/tests/"
# Положительный контроль рамки (D1309): до мутанта свидетель в рамке зелен на ИСПРАВНОМ механизме — иначе «мутант
# красен» (TC ниже) не различает ничего. Так и было с 9310f120 до D1309: соседа alerts-read.sh в рамке не было,
# свидетель краснел ногой R2b на исправном механизме, а TC засчитывал это как красноту мутанта.
POUT=$(bash "$M/hooks/tests/test_backlog_cmd_ring.sh" 2>&1); PRC=$?
[ "$PRC" = 0 ] && ok \
    || bad TC0 "контроль: свидетель красен в рамке на исправном механизме (rc $PRC) — TC ниже ничего не различает: «$(printf '%s' "$POUT" | grep -E '^FAIL|No such' | head -3 | tr '\n' ' ')»"
python3 - "$M" <<'PY'
import io, sys
m = sys.argv[1]
def patch(rel, old, new):
    p = f"{m}/{rel}"
    s = io.open(p, encoding="utf-8").read()
    assert s.count(old) == 1, f"якорь не найден ровно один раз: {rel}: {old}"
    io.open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
patch("hooks/backlog-lib.sh", """printf '%s#%s#%s' "$3" "$2" "$1\"""",
      """printf '%s#%s#%s#%s' "$3" "$2" "$1" "$RANDOM$RANDOM\"""")
# Питоновские исполнители ключа своего не строят с D1238: ограду им решает библиотека (`hooks/lib/backlog_cmd.py`),
# поэтому мутант библиотеки — мутант всех исполнителей.
PY
[ "$?" = 0 ] || { echo "FAIL [T-mut]: мутант не собран"; exit 1; }

# Контроль различения: прямой прогон свидетеля на мутанте (глубина 0) — красный.
DOUT=$(bash "$M/hooks/tests/test_backlog_cmd_ring.sh" 2>&1); DRC=$?
[ "$DRC" != 0 ] && ok \
    || bad TC "контроль: свидетель ограды зелёный на мутанте без ключа даже прямым прогоном (rc $DRC): «$(printf '%s' "$DOUT" | tail -2 | tr '\n' ' ')»"

# Предмет 1 (глубина 1): ☑ D9503, чья «Проверка» — свидетель мутанта. Исполнитель — настоящий
# архиватор дерева, он кладёт ключ пункта в BACKLOG_CMD_RUNNING, как на Stop.
O="$T/o"; mkdir -p "$O"
printf -- '- ☑ **D9503** ограда кольца держит ключ пункта\n  **Результат.** проба\n  **Проверка.** `bash %s/hooks/tests/test_backlog_cmd_ring.sh` → 0\n' "$M" > "$O/BACKLOG.md"
AOUT=$(BACKLOG_FILE="$O/BACKLOG.md" BACKLOG_ARCHIVE="$O/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" run 2>&1); ARC=$?
if grep -q 'Перенесено в архив: 1' <<< "$AOUT" || grep -q 'D9503' "$O/ARCH.md" 2>/dev/null; then
    bad T1 "архиватор унёс ☑ D9503 в архив: его «Проверка» (свидетель ограды) зелёная в рамке исполнителя, хотя ключ ограды у мутанта не работает и прямой прогон того же свидетеля красный (rc $DRC); вывод архиватора (rc $ARC): «$(printf '%s' "$AOUT" | tr '\n' ' ' | cut -c1-200)»"
else
    ok
fi

# Предмет 2 (глубина 2): настоящий свидетель на исправном механизме, унаследованные два ключа чужих
# команд — так он стартует, когда «Проверку» с ним исполняет исполнитель, сам позванный командой.
# shellcheck source=../backlog-lib.sh
. "$REPO/hooks/backlog-lib.sh"
RUN2="${BACKLOG_CMD_SEP}$(backlog_cmd_key check D9601 'bash a.sh')${BACKLOG_CMD_SEP}$(backlog_cmd_key check D9602 'bash b.sh')"
ROUT=$(env BACKLOG_CMD_RUNNING="$RUN2" bash "$REPO/hooks/tests/test_backlog_cmd_ring.sh" 2>&1); RRC=$?
[ "$RRC" = 0 ] && ok \
    || bad T2 "свидетель ограды красный на ИСПРАВНОМ механизме, когда стартует на унаследованной глубине 2 (rc $RRC): «$(printf '%s' "$ROUT" | grep -E '^FAIL|ring:' | head -3 | tr '\n' ' ')»"

echo "adv2 cmdring witness blind at depth: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
