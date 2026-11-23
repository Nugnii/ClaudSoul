#!/usr/bin/env bash
# test_adv_wit_measure_linux_parity_mount_root.sh — в среде свидетеля measure-linux-parity инструмент монтирует в контейнер `/`, а не репозиторий, и свидетель зелен.
#
# Результат: PATH свидетеля несёт только bash и docker; `dirname` в нём нет, подстановка REPO
#            вырождается в `cd -- "/.."` → `/` (ошибка `dirname: command not found` уходит в OUT и
#            никем не судится), и `docker run -v "$PWD":/repo:ro` получает корень диска. Нога T5
#            свидетеля сверяет маркеры рецепта, но не источник монтирования — мутант с любым
#            каталогом проходит, а сам инструмент под свидетелем проверяет не то дерево.
#            Ожидание до D1355: аргумент `-v` равен «<репозиторий>:/repo:ro». С D1355 (22 ноября 2026, решение
#            владельца «Дерево потоком») дерево едет в контейнер потоком на вход `docker run -i`, монтирования нет, и
#            предмет тот же другими средствами: в потоке дерево репозитория (его `hooks/tests/run_all.sh` и
#            `.git/HEAD`), а не корня диска, и `-v` нет вовсе.
# Проверка результата: этот тест.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/measure-linux-parity.sh"; WIT="$REPO/hooks/tests/test_measure_linux_parity.sh"
[ -f "$TOOL" ] && [ -f "$WIT" ] || { echo "FAIL: нет инструмента или свидетеля"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
ln -s "$(command -v bash)" "$BIN/bash"
ln -s "$(command -v git)" "$BIN/git"
ln -s "$(command -v tar)" "$BIN/tar"
ln -s "$(command -v cat)" "$BIN/cat"
# Тот же поддельный docker, что у свидетеля: аргументы `run` — в файл; вход (поток дерева) — в файл.
printf '#!/usr/bin/env bash\ncase "$1" in\n  info) exit 0 ;;\n  run) printf "%%s\\n" "$@" > "%s"; cat > "%s"; printf "%%s\\n" "Hook test files: 2/2 passed"; exit 0 ;;\nesac\nexit 0\n' "$TMP/run-args" "$TMP/stream.tar" > "$BIN/docker"
chmod +x "$BIN/docker"

# --- T1: свидетель в своей среде зелен (контроль: он не замечает того, что ниже) ------------------
OUT=$(bash "$WIT" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T1 "свидетель сам красен: rc=$RC — $(tail -1 <<< "$OUT")"

# --- T2: та же среда, тот же вызов, что у run_tool свидетеля — какое дерево ушло в контейнер ------
OUT=$(cd "$REPO" && PATH="$BIN" bash -c "bash scripts/measure-linux-parity.sh" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T2 "инструмент rc=$RC — ${OUT}"
ARGS=$(cat "$TMP/run-args" 2>/dev/null)
grep -qx -- '-v' <<< "$ARGS" && bad T2 "в контейнер монтируется папка этой машины: $(awk 'prev == "-v" { print; exit } { prev = $0 }' <<< "$ARGS")" || ok
LIST=$(tar -tf "$TMP/stream.tar" 2>/dev/null)
grep -qE '^(\./)?hooks/tests/run_all\.sh$' <<< "$LIST" && grep -qE '^(\./)?\.git/HEAD$' <<< "$LIST" && ok \
    || bad T2 "в потоке не дерево репозитория: $(head -3 <<< "$LIST" | tr '\n' ' ')"

echo ""
echo "adv measure-linux-parity mount root: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
