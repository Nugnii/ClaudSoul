#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh scripts/backlog-archive.sh hooks/completion-gate.sh scripts/backlog-return-check.sh scripts/backlog-refresh-readings.sh hooks/backlog-open-write-guard.sh hooks/tests/test_backlog_green_side.sh
# test_backlog_cmd_ring.sh — команда пункта бэклога не исполняется внутри своего же исполнения, какой бы исполнитель её ни звал и кто бы ни снял маркер вложенности (D503).
#
# Результат: у каждого из шести исполнителей команд бэклога команда пункта, позвавшая того же
#            исполнителя на том же бэклоге со снятым BACKLOG_CHECKS_NESTED, исполняется ровно
#            один раз, а вложенный исполнитель называет пропуск словом «кольцо»
# Проверка результата: bash hooks/tests/test_backlog_cmd_ring.sh даёт 0
#
# Повод (1 октября 2026, D502). Кольцо «архиватор → «Проверка» D499 → свидетель формы →
# архиватор» прошло мимо двери `BACKLOG_CHECKS_NESTED`: её снимают свидетели, задающие свою
# рамку (D334, D461). D502 закрыл одно ребро; ограда по ключу пункта (`hooks/backlog-lib.sh`,
# BACKLOG_CMD_RUNNING) закрывает кольцо у любого исполнителя.
#
# Устройство ноги. Команда пункта дописывает строку в счётчик и, пока строк меньше четырёх,
# зовёт исполнителя снова так, как это делает свидетель со своей рамкой, — `env -u
# BACKLOG_CHECKS_NESTED`. Предохранитель «четыре» держит кольцо конечным на непочиненном
# дереве. Строк 1 — ограда сработала; больше — кольцо. Положительный контроль у каждой ноги —
# сама первая строка: команда пункта исполнилась, то есть исполнитель до неё дошёл.
set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
# Вложенный исполнитель на том же файле ждёт замок держателя; пять проб вместо ста — уровень
# кольца за 0,1 с, а не за 2 с.
export CLAUDSOUL_LOCK_TRIES=5
unset BACKLOG_CHECKS_NESTED
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# Состояние исполнителей — в песочнице (противник D503, атака 5): архиватор пишет отказы в журнал
# каталога состояния, и прогон свидетеля пополнял боевой корпус отказов поддельным D9001.
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"
cnt() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
# judge <нога> <каталог> <исполнитель>: счётчик ровно 1 и пропуск назван
judge() {
    local n; n=$(cnt "$2/cnt")
    if [ "$n" = 0 ]; then bad "$1" "$3: команда пункта не исполнилась ни разу — рамка ноги не собралась"; return; fi
    [ "$n" = 1 ] && ok || bad "$1" "$3: команда пункта исполнилась $n раз — кольцо не остановлено"
    grep -q 'кольцо' "$2/inner.out" 2>/dev/null && ok || bad "$1b" "$3: вложенный прогон не назвал пропуск — молчаливый пропуск неотличим от «проверено»"
}

# R1 — архиватор: ☑-пункт, чья «Проверка» зовёт архиватор на том же бэклоге.
A="$T/a"; mkdir -p "$A"
cat > "$A/again.sh" <<EOF
echo x >> "$A/cnt"
[ "\$(wc -l < "$A/cnt")" -ge 4 ] && exit 0
env -u BACKLOG_CHECKS_NESTED BACKLOG_FILE="$A/BACKLOG.md" BACKLOG_ARCHIVE="$A/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" check > "$A/inner.out" 2>&1
exit 0
EOF
printf -- '- ☑ **D9001** проба кольца\n  **Результат.** проба\n  **Проверка.** `bash %s/again.sh` → 0\n' "$A" > "$A/BACKLOG.md"
env BACKLOG_FILE="$A/BACKLOG.md" BACKLOG_ARCHIVE="$A/ARCH.md" bash "$REPO/scripts/backlog-archive.sh" check >/dev/null 2>&1 || true  # архиватор `check` отвечает не-нулём на кольцо — предмет ноги: глубину читает строка ниже (D1261)
judge R1 "$A" "архиватор"

# R2 — completion-gate: ☑-пункт, чья «Проверка» зовёт гейт на том же бэклоге (своё состояние).
G="$T/g"; mkdir -p "$G/s"
cat > "$G/again.sh" <<EOF
echo x >> "$G/cnt"
[ "\$(wc -l < "$G/cnt")" -ge 4 ] && exit 0
s=\$(mktemp -d)
printf '{"session_id":"ring","cwd":"/"}' | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$G/BACKLOG.md" STATE_DIR="\$s" bash "$REPO/hooks/completion-gate.sh" > "$G/inner.out" 2>&1
. "$REPO/hooks/tests/alerts-read.sh"
alerts_of "\$s" >> "$G/inner.out" 2>/dev/null
rm -rf "\$s"
exit 0
EOF
printf -- '- ☑ **D9002** проба кольца\n  **Результат.** проба\n  **Проверка.** `bash %s/again.sh` → 0\n' "$G" > "$G/BACKLOG.md"
printf '{"session_id":"ring","cwd":"/"}' | env CG_BACKLOG="$G/BACKLOG.md" STATE_DIR="$G/s" bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1
judge R2 "$G" "completion-gate"

# R3 — страж возврата: условие возврата открытого пункта зовёт стража на том же бэклоге.
# Бэклог страж берёт у корня git каталога вызова, поэтому каталог ноги — репозиторий.
R="$T/r"; mkdir -p "$R"; git -C "$R" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_cmd_ring.sh:$LINENO" >&2; exit 1; }
cat > "$R/again.sh" <<EOF
echo x >> "$R/cnt"
[ "\$(wc -l < "$R/cnt")" -ge 4 ] && exit 1
cd "$R" && bash "$REPO/scripts/backlog-return-check.sh" > "$R/inner.out" 2>&1
exit 1
EOF
printf -- '- ☐ **D9003** проба кольца\n  **Проверка.** `false` → 0\n  **Проверка возврата:** `bash %s/again.sh`\n' "$R" > "$R/BACKLOG.md"
( cd "$R" && bash "$REPO/scripts/backlog-return-check.sh" ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_cmd_ring.sh:$LINENO" >&2; exit 1; }
judge R3 "$R" "страж возврата"

# R4 — пересчёт показаний: «Показание» зовёт пересчёт через посредника — запрет по тексту
# команды («backlog-refresh-readings» в строке) посредника не видит.
F="$T/f"; mkdir -p "$F"
cat > "$F/again.sh" <<EOF
echo x >> "$F/cnt"
[ "\$(wc -l < "$F/cnt")" -ge 4 ] && { echo 1; exit 0; }
BACKLOG_FILE="$F/BACKLOG.md" bash "$REPO/scripts/backlog-refresh-readings.sh" --check > "$F/inner.out" 2>&1
echo 1
EOF
printf -- '- ☐ **D9004** проба кольца\n  **Проверка.** `false` → 0\n  **Показание.** `bash %s/again.sh`\n' "$F" > "$F/BACKLOG.md"
BACKLOG_FILE="$F/BACKLOG.md" bash "$REPO/scripts/backlog-refresh-readings.sh" --check >/dev/null 2>&1 || true  # `--check` отвечает не-нулём на кольцо — предмет: число прогонов читает judge ниже (D1261)
judge R4 "$F" "пересчёт показаний"

# R5 — страж записи открытого пункта: «Проверка» записываемого пункта подаёт стражу тот же вызов.
W="$T/w"; mkdir -p "$W/s"; : > "$W/BACKLOG.md"
jq -cn --arg f "$W/BACKLOG.md" --arg c "$(printf -- '- ☐ **D9005** проба кольца\n  **Проверка.** `bash %s/again.sh` → 0\n' "$W")" \
    '{tool_name:"Write", session_id:"ring", tool_input:{file_path:$f, content:$c}}' > "$W/payload.json"
cat > "$W/again.sh" <<EOF
echo x >> "$W/cnt"
[ "\$(wc -l < "$W/cnt")" -ge 4 ] && exit 1
env -u BACKLOG_CHECKS_NESTED STATE_DIR="$W/s" bash "$REPO/hooks/backlog-open-write-guard.sh" < "$W/payload.json" > "$W/inner.out" 2>&1
exit 1
EOF
STATE_DIR="$W/s" bash "$REPO/hooks/backlog-open-write-guard.sh" < "$W/payload.json" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_cmd_ring.sh:$LINENO" >&2; exit 1; }
judge R5 "$W" "страж записи открытого пункта"

# R6 — свидетель зелёной стороны: «Проверка» открытого пункта зовёт свидетеля. Копия свидетеля и
# библиотеки в своём дереве, ему дописана нога green_D9006 — иначе пункт он не исполняет.
S6="$T/gs"; mkdir -p "$S6/hooks/tests"
cp "$REPO/hooks/backlog-lib.sh" "$S6/hooks/"
python3 - "$REPO/hooks/tests/test_backlog_green_side.sh" "$S6/hooks/tests/test_backlog_green_side.sh" <<'PY'
import io, sys
s = io.open(sys.argv[1], encoding="utf-8").read()
anchor = "run_check() {"
assert s.count(anchor) == 1, "якорь run_check не найден ровно один раз"
io.open(sys.argv[2], "w", encoding="utf-8").write(s.replace(anchor, 'green_D9006() { echo "RING_PROBE=1"; }\n' + anchor, 1))
PY
cat > "$S6/again.sh" <<EOF
echo x >> "$S6/cnt"
[ "\$(wc -l < "$S6/cnt")" -ge 4 ] && exit 0
bash "$S6/hooks/tests/test_backlog_green_side.sh" > "$S6/inner.out" 2>&1
exit 0
EOF
printf -- '- ☐ **D9006** проба кольца\n  **Проверка.** `bash %s/again.sh` → 0\n' "$S6" > "$S6/BACKLOG.md"
bash "$S6/hooks/tests/test_backlog_green_side.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_cmd_ring.sh:$LINENO" >&2; exit 1; }
judge R6 "$S6" "свидетель зелёной стороны"

echo "backlog cmd ring: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
