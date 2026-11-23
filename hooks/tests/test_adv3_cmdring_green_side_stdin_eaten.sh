#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_backlog_green_side.sh hooks/backlog-lib.sh
# test_adv3_cmdring_green_side_stdin_eaten.sh — свидетель зелёной стороны (исполнитель «Проверок» открытых пунктов) не теряет пункты молча, когда «Проверка» предыдущего пункта читает stdin.
#
# Атака (противник ограды кольца, раунд 3, 1 октября 2026). Цикл свидетеля читает перечень открытых
# пунктов СО STDIN (`while IFS= read -r ROW; do … done <<EOF $(backlog_open_items …) EOF`), а
# `run_check` исполняет «Проверку» в подоболочке без `</dev/null`: команда наследует stdin цикла.
# «Проверка», читающая stdin (`cat`, `jq` без файла, `read`, `python3 -` без перенаправления),
# выедает остаток перечня — следующие пункты не судятся И НЕ НАЗЫВАЮТСЯ: свидетель печатает
# «открытых 1» при двух и выходит 0. Пропуск молчит и читается «проверено, чисто» (обещание (3)
# ограды) — уже без всякого кольца. Тот же род у соседей починен давно и записан словами:
# `scripts/measurement-due.sh` («stdin закрыт: замер, читающий его, выедал остаток реестра из трубы
# цикла, и следующие замеры не запускались И НЕ НАЗЫВАЛИСЬ»), страж возврата и страж записи
# закрывают stdin команды (`</dev/null`); свидетель — нет.
#
# Рамка: копия свидетеля и библиотеки в песочнице (правка копии — одна строка `green_D9811() { … }`
# перед якорем `run_check() {`, встречающимся ровно один раз); у D9811 фикстура есть и «Проверка» под ней
# зелёная, у D9812 фикстуры НЕТ — свидетель обязан назвать его «FAIL». Контроль: «Проверка» D9811
# без чтения stdin — D9812 назван. Предмет: «Проверка» D9811 читает stdin.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"

# leg <каталог> <команда «Проверки» D9811> → вывод свидетеля; код — код свидетеля
leg() {
    local S="$1" chk="$2"
    mkdir -p "$S/hooks/tests"
    cp "$REPO/hooks/backlog-lib.sh" "$S/hooks/"
    python3 - "$REPO/hooks/tests/test_backlog_green_side.sh" "$S/hooks/tests/test_backlog_green_side.sh" <<'PY'
import io, sys
s = io.open(sys.argv[1], encoding="utf-8").read()
anchor = "run_check() {"
assert s.count(anchor) == 1, "якорь run_check не найден ровно один раз"
io.open(sys.argv[2], "w", encoding="utf-8").write(s.replace(anchor, 'green_D9811() { echo "STDIN_PROBE=1"; }\n' + anchor, 1))
PY
    printf -- '- ☐ **D9811** пункт с зелёной стороной\n  **Проверка.** `%s` → 0\n\n- ☐ **D9812** пункт БЕЗ зелёной стороны\n  **Проверка.** `false` → 0\n' "$chk" > "$S/BACKLOG.md"
    bash "$S/hooks/tests/test_backlog_green_side.sh" 2>&1 </dev/null
}

# Контроль: «Проверка» D9811 stdin не читает — пункт без зелёной стороны назван, свидетель красный.
C_OUT=$(leg "$T/c" "true"); C_RC=$?
{ [ "$C_RC" = 1 ] && grep -q 'FAIL \[D9812\]' <<< "$C_OUT"; } && ok \
    || bad TC "контроль: свидетель не назвал D9812 без зелёной стороны (rc $C_RC): «$(printf '%s' "$C_OUT" | tail -3 | tr '\n' ' ')»"

# Предмет: «Проверка» D9811 зелёная под фикстурой и читает stdin.
S_OUT=$(leg "$T/s" "cat >/dev/null; true"); S_RC=$?
grep -q 'FAIL \[D9812\]' <<< "$S_OUT" && ok \
    || bad T1 "свидетель не судил D9812 вовсе: «Проверка» D9811 выела перечень пунктов со stdin цикла — пункт без зелёной стороны не назван, итог: «$(printf '%s' "$S_OUT" | tail -1)»"
[ "$S_RC" != 0 ] && ok \
    || bad T2 "свидетель вышел 0 при открытом пункте без зелёной стороны — пропуск молчит и читается «проверено, чисто»"

echo "adv3 cmdring green side stdin eaten: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
