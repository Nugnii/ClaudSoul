#!/usr/bin/env bash
# СУДИТ: hooks/portable-lib.sh
# test_iso_epoch_date_refuses.sh — `iso_epoch` равен пакетному `iso_epoch_lines` и на метке, которую `date` не
# разбирает (D1322).
#
# Результат: на метке с `Z`, которую `date` отвергает, а jq разбирает, `iso_epoch` даёт то же число, что
#            `iso_epoch_lines`, а не 0.
# Проверка результата: этот тест.
#
# Повод (18 ноября 2026, разбор D1316). `date (uutils coreutils) 0.10.0` — coreutils раннера `ubuntu-26.04` — отвечает
# «invalid date '9999-12-31T23:59:59Z'» (замер в контейнере `ubuntu:26.04`); `iso_epoch` после отказа обоих `date`
# отдавал 0, `iso_epoch_lines` (jq) — 253402300799, и нога T1 #21 `test_iso_epoch_lines.sh` краснела только на раннере.
# Здесь `date` — подделка, отвергающая 9999 год, первой в PATH; нога P0 доказывает, что она отвергает и что обычную
# метку пропускает к настоящему `date`.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/portable-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
REAL_DATE=$(command -v date)
cat > "$BIN/date" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in 9999-*) echo "date: invalid date '\$a'" >&2; exit 1 ;; esac; done
exec "$REAL_DATE" "\$@"
EOF
chmod +x "$BIN/date"

one()  { PATH="$BIN:$PATH" bash -c '. "$1"; iso_epoch "$2"' _ "$LIB" "$1"; }
many() { printf '%s\n' "$1" | PATH="$BIN:$PATH" bash -c '. "$1"; iso_epoch_lines' _ "$LIB"; }

# --- P0: подделка отвергает 9999 год и пропускает обычную метку к настоящему `date` ------------------------------------
if ! PATH="$BIN:$PATH" date -u -d '9999-12-31T23:59:59Z' +%s >/dev/null 2>&1 \
   && ! PATH="$BIN:$PATH" date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '9999-12-31T23:59:59Z' +%s >/dev/null 2>&1 \
   && [ -n "$(PATH="$BIN:$PATH" date +%s 2>/dev/null)" ]; then ok
else bad P0 "подделка date не отвергает 9999 год либо ломает обычный вызов — T1 не свидетельство"; fi

# --- T1: метка, которую `date` отвергает, — одно число у обоих разборов, и не ноль ------------------------------------
TS='9999-12-31T23:59:59Z'
a=$(one "$TS"); b=$(many "$TS")
if [ -n "$b" ] && [ "$b" != 0 ] && [ "$a" = "$b" ]; then ok
else bad T1 "метка $TS: iso_epoch=[$a] iso_epoch_lines=[$b]"; fi

# --- T2: положительный контроль — обычная метка, которую `date` разбирает, одна у обоих -------------------------------
TS='2026-11-18T10:00:00Z'
a=$(one "$TS"); b=$(many "$TS")
if [ "$a" = 1794996000 ] && [ "$a" = "$b" ]; then ok
else bad T2 "метка $TS: iso_epoch=[$a] iso_epoch_lines=[$b]"; fi

echo "test_iso_epoch_date_refuses: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
