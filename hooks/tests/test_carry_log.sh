#!/usr/bin/env bash
# test_carry_log.sh — журнал переносов различает своё и чужое состояние приёмника (ADR-019, D350).
# Результат: перенос записан с хешем приёмника и именем дороги; повтор без изменений записи не
#            плодит; приёмник, правленный после нашего переноса, не перезаписывается и назван
#            кодом 3; приёмник без записи переносится как прежде (названный предел библиотеки).
# Проверка результата: bash hooks/tests/test_carry_log.sh даёт 0
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/lib/carry-log.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
# Песочница не убирается самим тестом: временное уберёт система, а раннер бьёт SIGKILL (D360).
TMP=$(mktemp -d)
. "$LIB"
CLAUDE_HOME="$TMP/home"
REPO_FX="$TMP/repo"; mkdir -p "$REPO_FX"
LOG=$(carry_log_path)
lines() { if [ -f "$LOG" ]; then grep -c . "$LOG"; else echo 0; fi; }
field() { awk -F'\t' -v n="$1" -v f="$2" 'NR == n { print $f }' "$LOG"; }
SRC="$REPO_FX/x.sh"; DST="$CLAUDE_HOME/hooks/x.sh"
printf 'v1\n' > "$SRC"

# --- T1: первый перенос — файл положен, запись одна, шесть полей, хеш приёмника с именем алгоритма ---
carry_file test "$SRC" "$DST"; RC=$?
if [ "$RC" = 0 ] && cmp -s "$SRC" "$DST"; then ok; else bad "T1" "первый перенос: rc=$RC"; fi
[ "$(lines)" = 1 ] && ok || bad "T1b" "записей после первого переноса: $(lines), ожидалась 1"
[ "$(awk -F'\t' 'NR == 1 { print NF }' "$LOG")" = 6 ] && ok || bad "T1c" "полей в записи: $(awk -F'\t' 'NR == 1 { print NF }' "$LOG"), ожидалось 6"
[ "$(field 1 5)" = "$(carry_hash "$DST")" ] && ok || bad "T1d" "хеш записи не равен хешу приёмника"
[ "$(field 1 2)" = "test" ] && ok || bad "T1e" "поле «чем» не записано: «$(field 1 2)»"
[ "$(field 1 4)" = "$DST" ] && ok || bad "T1f" "поле «куда» не равно приёмнику"
case "$(field 1 5)" in sha256:*|cksum:*) ok ;; *) bad "T1g" "у хеша нет имени алгоритма: $(field 1 5)" ;; esac

# --- T2: повтор без изменений — записи не плодит ---
carry_file test "$SRC" "$DST"; RC=$?
if [ "$RC" = 0 ] && [ "$(lines)" = 1 ]; then ok; else bad "T2" "повтор: rc=$RC, записей $(lines) (ожидалась 1)"; fi

# --- T3: источник изменился — перенос и вторая запись ---
printf 'v2\n' > "$SRC"
carry_file test "$SRC" "$DST"; RC=$?
if [ "$RC" = 0 ] && cmp -s "$SRC" "$DST" && [ "$(lines)" = 2 ]; then ok; else bad "T3" "обновление: rc=$RC, записей $(lines)"; fi

# --- T4: приёмник правлен ПОСЛЕ нашего переноса, источник ушёл дальше — третий исход ---
printf 'mine\n' >> "$DST"; BEFORE=$(cksum < "$DST")
printf 'v3\n' > "$SRC"
carry_diverged "$SRC" "$DST" && ok || bad "T4" "carry_diverged не видит правку приёмника"
carry_file test "$SRC" "$DST"; RC=$?
[ "$RC" = 3 ] && ok || bad "T4b" "разошлось в обе стороны: rc=$RC, ожидался 3"
[ "$(cksum < "$DST")" = "$BEFORE" ] && ok || bad "T4c" "приёмник перезаписан при третьем исходе"
[ "$(lines)" = 2 ] && ok || bad "T4d" "отказ записан как перенос: записей $(lines)"

# --- T5: репозиторий догнал правку приёмника — исход 0 без копии, запись обновляет базу сравнения ---
cp "$DST" "$SRC"
carry_file test "$SRC" "$DST"; RC=$?
if [ "$RC" = 0 ] && [ "$(lines)" = 3 ]; then ok; else bad "T5" "репозиторий догнал: rc=$RC, записей $(lines) (ожидалось 3)"; fi
if carry_diverged "$SRC" "$DST"; then bad "T5b" "после сближения всё ещё «разошлось»"; else ok; fi

# --- T6: приёмник без записи и отличающийся — переносится, получает первую запись (предел) ---
SRC2="$REPO_FX/y.sh"; DST2="$CLAUDE_HOME/hooks/y.sh"
printf 'repo\n' > "$SRC2"; printf 'old\n' > "$DST2"
if carry_diverged "$SRC2" "$DST2"; then bad "T6" "приёмник без записи объявлен разошедшимся"; else ok; fi
carry_file test "$SRC2" "$DST2"; RC=$?
if [ "$RC" = 0 ] && cmp -s "$SRC2" "$DST2" && [ "$(carry_last_hash "$DST2")" = "$(carry_hash "$DST2")" ]; then ok
else bad "T6b" "перенос без записи: rc=$RC"; fi

# --- T7: источника нет — 1, приёмник и журнал не тронуты ---
N=$(lines)
carry_file test "$REPO_FX/none.sh" "$CLAUDE_HOME/hooks/none.sh"; RC=$?
if [ "$RC" = 1 ] && [ ! -e "$CLAUDE_HOME/hooks/none.sh" ] && [ "$(lines)" = "$N" ]; then ok; else bad "T7" "нет источника: rc=$RC, записей $(lines) при $N"; fi

# --- T8: последний хеш ищется по ПРИЁМНИКУ — запись соседа этот файл не судит ---
printf 'z\n' > "$REPO_FX/z.sh"; carry_file test "$REPO_FX/z.sh" "$CLAUDE_HOME/hooks/z.sh"
[ "$(carry_last_hash "$CLAUDE_HOME/hooks/z.sh")" = "$(carry_hash "$CLAUDE_HOME/hooks/z.sh")" ] && ok || bad "T8" "последний хеш взят не у своего приёмника"
[ "$(carry_last_hash "$DST2")" = "$(carry_hash "$DST2")" ] && ok || bad "T8b" "запись z затёрла последний хеш y"

# --- T9: CARRY_LOG переопределяет путь журнала ---
CARRY_LOG="$TMP/alt.tsv" carry_record test "$SRC" "$DST"
[ -s "$TMP/alt.tsv" ] && ok || bad "T9" "CARRY_LOG не переопределил путь журнала"

# --- T10: обёртка install.sh `carry` — под set -e отвечает 0, отказ считает и называет файл ---
# Установщик целиком в тесте не гоняется (launchd, регистрация MCP — это машина владельца),
# поэтому исполняется его функция, вырезанная из файла: тот же код, что зовут циклы установки.
CARRY_FN=$(sed -n '/^carry() {/,/^}/p' "$ROOT/install.sh")
if [ -n "$CARRY_FN" ]; then
    OUT10=$(bash -c '
        set -euo pipefail
        CLAUDE_HOME="$1"; CLAUDSOUL_DIR="$2"; . "$2/lib/carry-log.sh"
        warn() { printf "%s\n" "$1"; }
        CARRY_REFUSED=0
        eval "$3"
        carry "$4" "$5"
        printf "rc=%s refused=%s\n" "$?" "$CARRY_REFUSED"' _ "$CLAUDE_HOME" "$ROOT" "$CARRY_FN" "$REPO_FX/x.sh" "$DST" 2>&1); RC=$?
    # приёмник $DST после T5 совпадает с источником; подложим расхождение в обе стороны заново
    printf 'v4\n' > "$REPO_FX/x.sh"; printf 'owner\n' >> "$DST"; B10=$(cksum < "$DST")
    OUT10=$(bash -c '
        set -euo pipefail
        CLAUDE_HOME="$1"; CLAUDSOUL_DIR="$2"; . "$2/lib/carry-log.sh"
        warn() { printf "%s\n" "$1"; }
        CARRY_REFUSED=0
        eval "$3"
        carry "$4" "$5"
        printf "rc=%s refused=%s\n" "$?" "$CARRY_REFUSED"' _ "$CLAUDE_HOME" "$ROOT" "$CARRY_FN" "$REPO_FX/x.sh" "$DST" 2>&1); RC=$?
    [ "$RC" = 0 ] && ok || bad "T10" "обёртка под set -e уронила вызывающего: rc=$RC, $OUT10"
    case "$OUT10" in *"rc=0 refused=1"*) ok ;; *) bad "T10b" "отказ не посчитан: $OUT10" ;; esac
    case "$OUT10" in *"hooks/x.sh"*"НЕ перезаписан"*) ok ;; *) bad "T10c" "отказ не назвал файл: $OUT10" ;; esac
    [ "$(cksum < "$DST")" = "$B10" ] && ok || bad "T10d" "обёртка перезаписала правку владельца"
else
    bad "T10" "в install.sh нет функции carry()"
fi

echo "carry-log: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
