#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh hooks/completion-gate.sh hooks/tests/test_backlog_green_side.sh
# test_adv3_cmdring_key_unicode_edge.sh — ключ ограды кольца (D503) у одной и той же команды пункта один у питоновского и у оболочечного исполнителя: «Проверка» с неразрывным пробелом на краю не исполняется внутри своего же исполнения через пару «гейт → свидетель зелёной стороны».
#
# Атака (противник ограды кольца, раунд 3, 1 октября 2026). Правило ключа — «текст команды (края
# без пробелов)#ID#вид», и у него две реализации, которые расходятся в том, ЧТО есть пробел:
#   · питон (`_bc_blocked`: `cmd.strip()`, и гейт ещё до того исполняет `.strip()`) снимает любой
#     юникодный пробел: U+00A0, U+2003, U+3000, U+0085, а заодно \x1c–\x1f;
#   · оболочка (`backlog_cmd_key`: `[[:space:]]`) снимает только пробелы ТЕКУЩЕЙ локали: в C/POSIX
#     (CI-контейнер debian без LANG, launchd) это ASCII, в C.UTF-8 не снимается U+0085.
# Одна команда получает два ключа. Гейт исполняет «Проверку» открытого пункта и кладёт ключ без
# NBSP; «Проверка» зовёт свидетеля, свидетель строит ключ с NBSP, совпадения нет — и команда
# исполняется ВНУТРИ СВОЕГО ЖЕ исполнения (обещание (1) ограды). Остановил второй вход лишь
# предел глубины файла; через копию бэклога не остановил бы и он.
# Тот же род вторым входом, без всякой локали: ТАБУЛЯЦИЯ внутри команды. Гейт (питон) берёт команду
# целиком, свидетель — седьмое поле TSV `backlog_open_items` (`awk -F'\t' '{print $7}'`), то есть
# кусок до табуляции: ключи снова разные, и тот же кусок исполняется внутри целого.
#
# Рамка: копия свидетеля и библиотеки в песочнице с ногой green_D9801 (как R6 test_backlog_cmd_ring.sh):
# правка копии — одна строка `green_D9801() { … }`, вставленная перед якорем `run_check() {`, который
# встречается в свидетеле ровно один раз; поведение свидетеля не меняется, продукт не трогается.
# Нога N — локаль C, «Проверка» `bash again.sh #<NBSP>`: решётка делает NBSP комментарием, команда
# одна и та же для обоих исполнителей. Нога T — локаль окружения, «Проверка» `bash again.sh<TAB>#x`.
# Наблюдатель — счётчик запусков с предохранителем «четыре». Контроль: та же рамка без NBSP и
# табуляции — команда исполняется один раз, свидетель называет кольцо.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX
T=$(mktemp -d)   # временное уберёт система
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"
NBSP=$(printf '\302\240')

# leg <каталог> <хвост команды> [локаль] → число запусков «Проверки» D9801
leg() {
    local S="$1" tail="$2" loc="${3:-C}"
    mkdir -p "$S/hooks/tests" "$S/s"
    cp "$REPO/hooks/backlog-lib.sh" "$S/hooks/"
    python3 - "$REPO/hooks/tests/test_backlog_green_side.sh" "$S/hooks/tests/test_backlog_green_side.sh" <<'PY'
import io, sys
s = io.open(sys.argv[1], encoding="utf-8").read()
anchor = "run_check() {"
assert s.count(anchor) == 1, "якорь run_check не найден ровно один раз"
io.open(sys.argv[2], "w", encoding="utf-8").write(s.replace(anchor, 'green_D9801() { echo "RING_PROBE=1"; }\n' + anchor, 1))
PY
    cat > "$S/again.sh" <<EOF
echo x >> "$S/cnt"
[ "\$(wc -l < "$S/cnt")" -ge 4 ] && exit 1
bash "$S/hooks/tests/test_backlog_green_side.sh" >> "$S/inner.out" 2>&1
exit 1
EOF
    printf -- '- ☐ **D9801** проба ключа\n  **Проверка.** `bash %s/again.sh%s` → 0\n' "$S" "$tail" > "$S/BACKLOG.md"
    if [ "$loc" = C ]; then
        printf '{"session_id":"adv3-key-edge","cwd":"/"}' | env LC_ALL=C CG_BACKLOG="$S/BACKLOG.md" STATE_DIR="$S/s" \
            bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv3_cmdring_key_unicode_edge.sh:$LINENO" >&2; exit 1; }
    else
        printf '{"session_id":"adv3-key-edge","cwd":"/"}' | env CG_BACKLOG="$S/BACKLOG.md" STATE_DIR="$S/s" \
            bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv3_cmdring_key_unicode_edge.sh:$LINENO" >&2; exit 1; }
    fi
    if [ -f "$S/cnt" ]; then wc -l < "$S/cnt" | tr -d ' '; else echo 0; fi
}

# Контроль: без NBSP и табуляции ключи совпадают — свидетель называет кольцо, команда исполнена один раз.
NC=$(leg "$T/c" " #")
[ "$NC" = 1 ] && ok || bad TC "контроль: без NBSP «Проверка» D9801 исполнилась $NC раз (ожидалось 1) — рамка не собралась либо ограда не держит и без NBSP"
grep -q 'SKIP \[D9801\]' "$T/c/inner.out" 2>/dev/null && ok || bad TC2 "контроль: свидетель без NBSP не назвал пропуск D9801 по кольцу: «$(tr '\n' ' ' < "$T/c/inner.out" 2>/dev/null | cut -c1-300)»"

# Нога N: NBSP на краю команды внутри обратных кавычек, локаль C.
N=$(leg "$T/n" " #${NBSP}")
[ "$N" -ge 1 ] && ok || bad N0 "рамка: гейт не исполнил «Проверку» D9801 с NBSP ни разу"
[ "$N" = 1 ] && ok \
    || bad N1 "«Проверка» D9801 с NBSP на краю исполнилась $N раз: гейт (питон, strip снимает NBSP) и свидетель (оболочка, [[:space:]] локали C — нет) построили РАЗНЫЕ ключи одной команды, и она исполнилась внутри своего же исполнения"

# Нога T: табуляция внутри команды, локаль окружения.
TB=$(leg "$T/t" "$(printf '\t')#x" env)
[ "$TB" -ge 1 ] && ok || bad T0 "рамка: гейт не исполнил «Проверку» D9801 с табуляцией ни разу"
[ "$TB" = 1 ] && ok \
    || bad T1 "«Проверка» D9801 с табуляцией внутри исполнилась $TB раз: гейт взял команду целиком, свидетель — поле TSV до табуляции; ключи разные, и команда исполнилась внутри своего же исполнения"

echo "adv3 cmdring key unicode edge: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
