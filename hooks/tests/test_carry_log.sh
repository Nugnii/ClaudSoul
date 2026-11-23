#!/usr/bin/env bash
# СУДИТ: install.sh lib/carry-log.sh
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

# --- T11 (D1099): install.sh кладёт knowledge/META.md ЧЕРЕЗ журнал — дорог две, писать обязаны обе ---
# Строка `cp` мимо журнала оставляла sync-drifted и сверщику D27 старый хеш: следующий коммит в META
# выглядел «правкой в рабочей базе» (ложный «✗ D27») и отказом переноса (rc=3). Исполняется строка
# установщика, вырезанная по приёмнику, — тот же код, что идёт в шаге 2.
META_LINE=$(grep -E '"\$GLOBAL_LESSONS/META\.md"' "$ROOT/install.sh" | grep -v '^[[:space:]]*#' | head -1)
if [ -n "$META_LINE" ] && [ -n "$CARRY_FN" ]; then
    H11="$TMP/home11"; mkdir -p "$H11/global-lessons"
    bash -c '
        set -euo pipefail
        CLAUDE_HOME="$1"; CLAUDSOUL_DIR="$2"; GLOBAL_LESSONS="$1/global-lessons"; . "$2/lib/carry-log.sh"
        warn() { :; }; info() { :; }; CARRY_REFUSED=0
        eval "$3"
        eval "$4"' _ "$H11" "$ROOT" "$CARRY_FN" "$META_LINE" >/dev/null 2>&1
    cmp -s "$ROOT/knowledge/META.md" "$H11/global-lessons/META.md" && ok || bad "T11" "строка установщика не положила META: $META_LINE"
    [ -n "$(CLAUDE_HOME="$H11" carry_last_hash "$H11/global-lessons/META.md")" ] && ok \
        || bad "T11b" "META положена мимо журнала переносов: $META_LINE"
else
    bad "T11" "в install.sh нет строки с приёмником \$GLOBAL_LESSONS/META.md"
fi

# --- T12 (D1166): carry_ordered — библиотеки первыми, потребитель отбитой библиотеки не переносится, под set -e ---
S12="$TMP/s12"; mkdir -p "$S12/hooks/lib"
printf 'echo\n' > "$S12/hooks/a-hook.sh"
printf '. "$D/x-lib.sh"\n' > "$S12/hooks/b-uses-x.sh"
printf 'python3 "$D/lib/tw.py"\n' > "$S12/hooks/c-uses-tw.sh"
: > "$S12/hooks/x-lib.sh"; : > "$S12/hooks/lib/tw.py"
T12_OUT=$(bash -c '
    set -euo pipefail
    . "$1/lib/carry-log.sh"
    CARRY_SRC_HOOKS="$2/hooks"; REFUSE="$3"
    put()  { printf "carry %s\n" "$1"; [ "$1" != "$REFUSE" ] || return 3; }
    skip() { printf "skip %s %s\n" "$1" "$2"; }
    carry_ordered put skip a-hook.sh b-uses-x.sh c-uses-tw.sh x-lib.sh lib/tw.py
    echo "end"' _ "$ROOT" "$S12" "x-lib.sh" 2>&1)
T12_EXP=$(printf 'carry x-lib.sh\ncarry lib/tw.py\ncarry a-hook.sh\nskip b-uses-x.sh x-lib.sh\ncarry c-uses-tw.sh\nend')
[ "$T12_OUT" = "$T12_EXP" ] && ok || bad "T12" "порядок или пропуск не те, либо set -e оборвал: ${T12_OUT//$'\n'/ | }"
T12b=$(bash -c '. "$1/lib/carry-log.sh"; CARRY_SRC_HOOKS="$2/hooks"
    put() { printf "carry %s\n" "$1"; [ "$1" != lib/tw.py ] || return 1; }; skip() { printf "skip %s %s\n" "$1" "$2"; }
    carry_ordered put skip c-uses-tw.sh lib/tw.py' _ "$ROOT" "$S12" 2>&1)
[ "$T12b" = "$(printf 'carry lib/tw.py\nskip c-uses-tw.sh tw.py')" ] && ok || bad "T12b" "сбой переноса библиотеки (код 1) не остановил потребителя: ${T12b//$'\n'/ | }"
T12c=$(bash -c '. "$1/lib/carry-log.sh"; CARRY_SRC_HOOKS="$2/hooks"
    put() { printf "carry %s\n" "$1"; }; skip() { printf "skip %s\n" "$1"; }
    carry_ordered put skip b-uses-x.sh x-lib.sh' _ "$ROOT" "$S12" 2>&1)
[ "$T12c" = "$(printf 'carry x-lib.sh\ncarry b-uses-x.sh')" ] && ok || bad "T12c" "без отказа потребитель не перенесён: ${T12c//$'\n'/ | }"

# --- T13 (D1166, второй круг): отказ, известный заранее (`carry_diverged`), замыкается по КОДУ библиотек: цепочка
# «библиотека → библиотека → хук» не переносится; упоминание в комментарии отказ не несёт; новый файл (приёмника нет)
# ставится, даже если зависит от отбитой.
S13="$TMP/s13"; mkdir -p "$S13/src/hooks/lib" "$S13/home/hooks/lib"
printf 'x\n' > "$S13/src/hooks/x-lib.sh"
printf '. "$D/x-lib.sh"\n' > "$S13/src/hooks/y-lib.sh"
printf '# x-lib упомянут лишь в комментарии\necho\n' > "$S13/src/hooks/z-lib.sh"
printf '. "$D/y-lib.sh"\n' > "$S13/src/hooks/h-uses-y.sh"
printf '. "$D/z-lib.sh"\n' > "$S13/src/hooks/h-uses-z.sh"
printf '. "$D/x-lib.sh"\n' > "$S13/src/hooks/new-uses-x.sh"
for f in x-lib.sh y-lib.sh z-lib.sh h-uses-y.sh h-uses-z.sh; do printf 'old\n' > "$S13/home/hooks/$f"; done
T13_OUT=$(bash -c '
    set -euo pipefail
    CLAUDE_HOME="$2/home"; . "$1/lib/carry-log.sh"
    carry_record t13 "$2/src/hooks/x-lib.sh" "$2/home/hooks/x-lib.sh"   # журнал знает приёмник
    printf "правлен\n" >> "$2/home/hooks/x-lib.sh"                       # и его правят в установке
    CARRY_SRC_HOOKS="$2/src/hooks"; CARRY_DST_HOOKS="$2/home/hooks"; CARRY_REFUSED_LIBS=""
    put()  { local rc=0; carry_file t13 "$CARRY_SRC_HOOKS/$1" "$CARRY_DST_HOOKS/$1" || rc=$?; printf "put %s %s\n" "$1" "$rc"; return "$rc"; }
    skip() { printf "skip %s %s\n" "$1" "$2"; }
    carry_ordered put skip h-uses-y.sh h-uses-z.sh new-uses-x.sh x-lib.sh y-lib.sh z-lib.sh
    echo end' _ "$ROOT" "$S13" 2>&1)
T13_EXP=$(printf 'put x-lib.sh 3\nskip y-lib.sh x-lib.sh\nput z-lib.sh 0\nskip h-uses-y.sh y-lib.sh\nput h-uses-z.sh 0\nput new-uses-x.sh 0\nend')
[ "$T13_OUT" = "$T13_EXP" ] && ok || bad "T13" "цепочка, комментарий или новый файл решены не так: ${T13_OUT//$'\n'/ | }"
grep -q '^old$' "$S13/home/hooks/y-lib.sh" && grep -q '^old$' "$S13/home/hooks/h-uses-y.sh" && [ -f "$S13/home/hooks/new-uses-x.sh" ] \
    && ok || bad "T13b" "приёмники не те: цепочка перенесена либо новый файл не поставлен"

# --- T14 (D1166, третий круг): подключение, а не упоминание. Реестр-данные (.tsv), докстрока Python и подстрока
# основания (`stats_unread` ⊃ `unread`) отказ не несут; импорт Python во вставке внутри оболочки — несёт.
S14="$TMP/s14"; mkdir -p "$S14/hooks/lib"
: > "$S14/hooks/lib/unread.py"; : > "$S14/hooks/lib/tw.py"
printf 'файл\tчитатель\nlib/unread.py\tданные\n' > "$S14/hooks/lib/reg.tsv"
printf '"""\nДокстрока: зовёт unread.py.\n"""\nx = 1\n' > "$S14/hooks/lib/doc.py"
printf 'stats_unread=1\n' > "$S14/hooks/sub-unread.sh"
printf "python3 - <<'PY'\nimport tw\nPY\n" > "$S14/hooks/emb-tw.sh"
T14=$(bash -c '. "$1/lib/carry-log.sh"; CARRY_SRC_HOOKS="$2/hooks"; CARRY_REFUSED_LIBS="unread.py tw.py"
    put() { printf "carry %s\n" "$1"; }; skip() { printf "skip %s %s\n" "$1" "$2"; }
    carry_ordered put skip lib/reg.tsv lib/doc.py sub-unread.sh emb-tw.sh' _ "$ROOT" "$S14" 2>&1)
[ "$T14" = "$(printf 'carry lib/reg.tsv\ncarry lib/doc.py\ncarry sub-unread.sh\nskip emb-tw.sh tw.py')" ] && ok \
    || bad "T14" "данные, докстрока или подстрока несут отказ либо импорт во вставке не несёт: ${T14//$'\n'/ | }"

echo "carry-log: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
