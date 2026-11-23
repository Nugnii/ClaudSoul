#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_dispatch_cksum_escaped_name.sh — диспетчер записи командой подаёт стражам файл с переводом строки или обратной
# косой в имени и тогда, когда `cksum` печатает имя экранированным (D1321).
#
# Результат: при выводе `cksum` в форме uutils — строка начинается с `\`, в имени `\n` и `\\` — стражам подан файл
#            с настоящим именем, а не потерян и не подменён.
# Проверка результата: этот тест.
#
# Повод (18 ноября 2026, разбор D1316). `cksum (uutils coreutils) 0.10.0` — coreutils раннера `ubuntu-26.04` — печатает
# имя с переводом строки так: `\12738659 1 ./nl\nf1.md` (замер в контейнере `ubuntu:26.04`); GNU и BSD печатают имя как
# есть, в две строки. Разбор отбора в диспетчере ждёт строку, начинающуюся с цифры, и экранированную не опознавал. Здесь
# `cksum` — подделка той же формы первой в PATH; нога P0 доказывает, что подделка экранирует, иначе зелёные T2 и T3
# значили бы только «формы uutils не было».
# Имя диспетчера собрано из частей намеренно — тот же приём, что в test_adv_dispatch_newline_name.sh (признак рода M).
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DISP="bash-write-""dispatch.sh"
[ -f "$HOOK_DIR/$DISP" ] || { echo "FAIL: нет диспетчера"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd) || exit 1
SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"; BIN="$TMP/bin"
mkdir -p "$SB/hooks" "$SR" "$SH" "$BIN"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
STUB='#!/usr/bin/env bash
jq -c ".tool_input.file_path" >> "${ADV_FED:-/dev/null}" 2>/dev/null
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done

# Подделка `cksum` формы uutils: сумма и размер — у настоящего `cksum` (со stdin он печатает только их), имя с переводом
# строки или обратной косой — экранировано (`\\`, `\n`), и строка тогда начинается с `\`.
REAL_CKSUM=$(command -v cksum)
cat > "$BIN/cksum" <<'EOF'
#!/usr/bin/env bash
for f in "$@"; do
    r=$("$REAL_CKSUM" < "$f") || continue
    case "$f" in
        *$'\n'*|*\\*) e=${f//\\/\\\\}; e=${e//$'\n'/\\n}; printf '\\%s %s\n' "$r" "$e" ;;
        *) printf '%s %s\n' "$r" "$f" ;;
    esac
done
EOF
chmod +x "$BIN/cksum"
export REAL_CKSUM

_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > f1.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/f1.md" "$SR/.gitignore"

# --- P0: подделка экранирует так, как замерено у uutils ---------------------------------------------------------------
printf x > "$TMP/nl
x.md"
p0=$(cd "$TMP" && PATH="$BIN:$PATH" cksum "./nl
x.md")
case "$p0" in '\'*' ./nl\nx.md') ok ;; *) bad P0 "подделка не даёт формы uutils: «${p0}»" ;; esac

run() {  # run <сессия> → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"esc-%s","cwd":"%s"}' "$1" "$SR" \
      | env PATH="$BIN:$PATH" HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run n >/dev/null      # начало сессии: метка
sleep 1
echo "запись команды" > "$SR/nl
f1.md"
echo "запись команды" > "$SR/bs\\x.md"
echo "контроль" > "$SR/plain.md"
: > "$FED"
run n >/dev/null

# T0 — положительный контроль: обычная правка того же события подана.
[ "$(grep -c '/plain\.md"$' "$FED")" -ge 1 ] && ok || bad T0 "положительный контроль: plain.md не подан"
# T1 — нетронутый f1.md вместо «nl⏎f1.md» не подан.
[ "$(grep -c '/repo/f1\.md"$' "$FED")" -eq 0 ] && ok || bad T1 "подан НЕТРОНУТЫЙ f1.md"
# T2 — файл с переводом строки в имени подан стражам под настоящим именем (в JSON — `\n`).
[ "$(grep -c '/repo/nl\\nf1\.md"$' "$FED")" -ge 1 ] && ok || bad T2 "файл «nl⏎f1.md» не подан при экранированном cksum: $(tr '\n' ' ' < "$FED")"
# T3 — файл с обратной косой в имени подан под настоящим именем (в JSON — `\\`), а не с удвоенной косой.
[ "$(grep -c '/repo/bs\\\\x\.md"$' "$FED")" -ge 1 ] && ok || bad T3 "файл «bs\\x.md» не подан под своим именем: $(tr '\n' ' ' < "$FED")"

# --- H1: брат — `hash_file` (hooks/hash-lib.sh) берёт первое поле вывода `md5sum <путь>` -----------------------------
# GNU `md5sum` (и uutils) при обратной косой или переводе строки в имени начинает строку с `\` — первое поле
# становилось `\<хеш>`, и обещанная шапкой сравнимость с `hash_value` ломалась (замер 18 ноября 2026: `debian:stable-slim`
# и `ubuntu:26.04`; у macOS `md5sum` имя не экранирует). Подделка той же формы — первой в PATH.
HL="$HOOK_DIR/hash-lib.sh"
if [ -f "$HL" ]; then
    REAL_MD5=$(command -v md5sum || command -v md5)
    cat > "$BIN/md5sum" <<'EOF'
#!/usr/bin/env bash
h() { "$REAL_MD5" | awk '{print $1}'; }
[ $# -eq 0 ] && { printf '%s  -\n' "$(h)"; exit 0; }
for f in "$@"; do
    case "$f" in
        *$'\n'*|*\\*) e=${f//\\/\\\\}; e=${e//$'\n'/\\n}; printf '\\%s  %s\n' "$(h < "$f")" "$e" ;;
        *) printf '%s  %s\n' "$(h < "$f")" "$f" ;;
    esac
done
EOF
    chmod +x "$BIN/md5sum"; export REAL_MD5
    printf abc > "$TMP/b\\s"
    hf=$(PATH="$BIN:$PATH" bash -c '. "$1"; hash_file "$2"' _ "$HL" "$TMP/b\\s")
    hv=$(PATH="$BIN:$PATH" bash -c '. "$1"; hash_value abc' _ "$HL")
    [ -n "$hv" ] && [ "$hf" = "$hv" ] && ok || bad H1 "hash_file пути с обратной косой = [${hf}], hash_value того же содержимого = [${hv}]"
fi

echo "test_dispatch_cksum_escaped_name: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
