#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh scripts/backlog-archive.sh hooks/completion-gate.sh hooks/tests/test_backlog_green_side.sh
# test_adv2_cmdring_legit_depth.sh — две цепочки, которые ограда кольца (D503) сама объявляет законными, складываются: «Проверка» ☑ зовёт свидетеля зелёной стороны, а «Проверка» открытого пункта под ним — исполнителя на своей фикстуре; закрытие, зелёное при прямом прогоне свидетеля, исполнитель уровнем выше не объявляет красным.
#
# Атака (противник ограды кольца, раунд 2, 1 октября 2026). Шапка ограды в hooks/backlog-lib.sh
# называет законную вложенность так: «„Проверка“ ☑ → свидетель → „Проверки“ открытых; свидетель →
# исполнитель на фикстуре → её команда» — и ставит предел глубины 2. Цепочки складываются: свидетель,
# позванный «Проверкой» ☑ (форма D499), исполняет «Проверки» открытых уже на глубине 2, и проба
# открытого пункта, гоняющая исполнителя на своей фикстуре (форма probe_D431/D433/D441/D445/D448),
# получает исполнителя, который не исполняет НИЧЕГО: предел исчерпан. Пропуск в глубине поднимается
# наверх не словом «кольцо», а вердиктом: проба красна → свидетель «FAIL» → архиватор «☑, а его же
# «Проверка» красная», гейт — «закрытие расходится со своим же критерием». Кольца нет ни в одной ветке.
#
# Рамка: копия свидетеля и библиотеки в своём дереве с ногой green_D9701 (как R6 test_backlog_cmd_ring.sh);
# открытый D9701 — проба «архиватор переносит закрытое на своей фикстуре»; внешний бэклог — ☑ D9702,
# чья «Проверка» зовёт свидетеля. Контроль: проба и свидетель зелёные прямым прогоном.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
export CLAUDSOUL_LOCK_TRIES=5
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"

S="$T/gs"; mkdir -p "$S/hooks/tests"
cp "$REPO/hooks/backlog-lib.sh" "$S/hooks/"
python3 - "$REPO/hooks/tests/test_backlog_green_side.sh" "$S/hooks/tests/test_backlog_green_side.sh" <<'PY'
import io, sys
s = io.open(sys.argv[1], encoding="utf-8").read()
anchor = "run_check() {"
assert s.count(anchor) == 1, "якорь run_check не найден ровно один раз"
io.open(sys.argv[2], "w", encoding="utf-8").write(s.replace(anchor, 'green_D9701() { echo "LEGIT_PROBE=1"; }\n' + anchor, 1))
PY

# Проба открытого D9701: архиватор на СВОЕЙ фикстуре переносит закрытый D9801 с зелёной «Проверкой».
cat > "$S/probe.sh" <<EOF
d=\$(mktemp -d "$T/fxXXXXXX")
printf -- '- ☑ **D9801** закрытый пункт фикстуры\n  **Результат.** проба\n  **Проверка.** \`true\` → 0\n' > "\$d/BACKLOG.md"
env -u BACKLOG_CHECKS_NESTED BACKLOG_FILE="\$d/BACKLOG.md" BACKLOG_ARCHIVE="\$d/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" run > "\$d/out" 2>&1
rc=\$?
cat "\$d/out" >> "$T/probe.log"
exit "\$rc"
EOF
printf -- '- ☐ **D9701** проба: архиватор на своей фикстуре переносит закрытое\n  **Проверка.** `bash %s/probe.sh` → 0\n' "$S" > "$S/BACKLOG.md"

O="$T/o"; mkdir -p "$O"
printf -- '- ☑ **D9702** закрытие, чья «Проверка» зовёт свидетеля зелёной стороны (форма D499)\n  **Результат.** свидетель зелёный\n  **Проверка.** `bash %s/hooks/tests/test_backlog_green_side.sh` → 0\n' "$S" > "$O/BACKLOG.md"
cp "$O/BACKLOG.md" "$T/o.orig"

# Контроль рамки: проба и свидетель зелёные прямым прогоном (вложенность 1 и 2 — законная).
bash "$S/probe.sh" >/dev/null 2>&1; PRC=$?
[ "$PRC" = 0 ] && ok || bad TC1 "рамка: проба D9701 красна прямым прогоном (rc $PRC): $(cat "$T/probe.log" 2>/dev/null)"
WOUT=$(bash "$S/hooks/tests/test_backlog_green_side.sh" 2>&1); WRC=$?
{ [ "$WRC" = 0 ] && grep -q 'PASS=.* FAIL=0' <<< "$WOUT" && ! grep -q '^FAIL \[' <<< "$WOUT"; } && ok \
    || bad TC2 "рамка: свидетель красен прямым прогоном (rc $WRC): «$(printf '%s' "$WOUT" | tail -3)»"

# Предмет 1: архиватор переносит D9702 — его «Проверка» (свидетель) зелёная.
: > "$T/probe.log"
AOUT=$(BACKLOG_FILE="$O/BACKLOG.md" BACKLOG_ARCHIVE="$O/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" run 2>&1); ARC=$?
{ [ "$ARC" = 0 ] && grep -q 'Перенесено в архив: 1' <<< "$AOUT"; } && ok \
    || bad T1 "законный вызов не сработал: архиватор не перенёс D9702 (rc $ARC); его вывод: «$(printf '%s' "$AOUT" | tr '\n' ' ' | cut -c1-400)»; проба под ним: «$(tr '\n' ' ' < "$T/probe.log" | cut -c1-300)»"
if grep -q 'D9702.*красная' <<< "$AOUT"; then
    bad T2 "пропуск по пределу глубины в глубине дерева поднялся наверх вердиктом «красная» — закрытие, зелёное при прямом прогоне, объявлено расходящимся с критерием: «$(grep 'D9702' <<< "$AOUT" | head -1)»"
else
    ok
fi

# Предмет 2: completion-gate на той же рамке не объявляет закрытие расходящимся с критерием.
cp "$T/o.orig" "$O/BACKLOG.md"; mkdir -p "$T/gst"
printf '{"session_id":"adv2-legit-depth","cwd":"/"}' | CG_BACKLOG="$O/BACKLOG.md" STATE_DIR="$T/gst" \
    bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv2_cmdring_legit_depth.sh:$LINENO" >&2; exit 1; }
. "$REPO/hooks/tests/alerts-read.sh"; AL=$(alerts_of "$T/gst")   # все три канала (D1304, D1309): о главном бэклоге гейт говорит в канал проекта
if grep -q 'расходится' <<< "$AL" && grep -q 'D9702' <<< "$AL"; then
    bad T3 "completion-gate объявил закрытие D9702 расходящимся со своим критерием, хотя свидетель зелёный — красное родил предел глубины: «$(printf '%s' "$AL" | head -3 | tr '\n' ' ')»"
else
    ok
fi

# Предмет 3: пересчёт показаний. «Показание» открытого пункта зовёт свидетеля (форма D464, D499:
# `bash …/test_backlog_green_side.sh | tail -1`). В файле — то, что свидетель говорит прямым прогоном;
# пересчёт на границе хода не вправе переписать его значением, которое родил предел глубины.
WLAST=$(bash "$S/hooks/tests/test_backlog_green_side.sh" 2>/dev/null | tail -1)
R="$T/r"; mkdir -p "$R"
printf -- '- ☐ **D9703** показание зовёт свидетеля зелёной стороны\n  **Проверка.** `false` → 0\n  **Показание.** `bash %s/hooks/tests/test_backlog_green_side.sh | tail -1`\n  **Последнее показание (2026-10-01).** %s\n' "$S" "$WLAST" > "$R/BACKLOG.md"
ROUT=$(BACKLOG_FILE="$R/BACKLOG.md" bash "$REPO/scripts/backlog-refresh-readings.sh" run 2>&1)
RNOW=$(grep -F '**Последнее показание' "$R/BACKLOG.md" | sed 's/.*\*\*Последнее показание[^*]*\*\* *//')
if [ -n "$WLAST" ] && [ "$RNOW" = "$WLAST" ]; then ok; else
    bad T4 "пересчёт переписал показание D9703 значением, которое родил предел глубины: прямой прогон свидетеля «${WLAST}», в файле теперь «${RNOW}»; вывод пересчёта: «$(printf '%s' "$ROUT" | tr '\n' ' ' | cut -c1-300)»"
fi

echo "adv2 cmdring legit depth: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
