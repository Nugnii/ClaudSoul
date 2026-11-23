#!/usr/bin/env bash
# test_measure_linux_parity_remote_docker.sh — docker, смотрящий на другую машину, замер measure-linux-parity мерит потоком.
# СУДИТ: scripts/measure-linux-parity.sh
#
# Результат: если docker на этой машине направлен на чужую (контекст с ssh://, как `server` — домашний сервер владельца
#            с 2026-11-22, или DOCKER_HOST=ssh://…), замер зовёт `docker run -i` без `-v` и подаёт дерево потоком на
#            вход: в потоке есть `hooks/tests/run_all.sh` и `.git/HEAD`. Код замера — код контейнера. Локальный docker
#            (unix://) мерится так же. До D1355 (решение владельца 22 ноября 2026 «Дерево потоком») такой docker был
#            «не измерено», код 2: `-v "$PWD":/repo` смонтировал бы на сервере пустую папку с тем же путём.
# Проверка результата: этот тест.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/measure-linux-parity.sh"
[ -f "$TOOL" ] || { echo "FAIL: нет $TOOL"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
# Поддельный docker: адрес контекста — из DOCKER_CTX_HOST, `run` пишет аргументы, сохраняет вход и печатает итог набора.
cat > "$BIN/docker" <<SH
#!/usr/bin/env bash
case "\$1" in
  context) printf '%s\n' "\${DOCKER_CTX_HOST:-unix:///var/run/docker.sock}" ;;
  info) exit 0 ;;
  run) printf '%s\n' "\$@" > "$TMP/run-args"; cat > "$TMP/stream.tar"; echo "Hook test files: 2/2 passed" ;;
esac
SH
chmod +x "$BIN/docker"

run_tool() { rm -f "$TMP/run-args" "$TMP/stream.tar"; OUT="$(env -u DOCKER_HOST PATH="$BIN:$PATH" "$@" bash "$TOOL" 2>&1)"; RC=$?; }
# streamed <нога> — run позван с -i и без -v, в потоке дерево репозитория, код 0
streamed() {
    [ -e "$TMP/run-args" ] || { bad "$1" "docker run не позван (код $RC: $(head -2 <<<"$OUT"))"; return; }
    [ "$RC" -eq 0 ] && ok || bad "$1" "код $RC вместо 0"
    grep -qx -- '-i' "$TMP/run-args" && ok || bad "$1" "docker run без -i — дерево не на входе"
    grep -qx -- '-v' "$TMP/run-args" && bad "$1" "docker run монтирует папку этой машины (-v)" || ok
    local list; list=$(tar -tf "$TMP/stream.tar" 2>/dev/null)
    grep -qE '^(\./)?hooks/tests/run_all\.sh$' <<<"$list" && ok || bad "$1" "в потоке нет hooks/tests/run_all.sh"
    grep -qE '^(\./)?\.git/HEAD$' <<<"$list" && ok || bad "$1" "в потоке нет .git/HEAD"
}

# T1: контекст на другой машине — мерит потоком
run_tool DOCKER_CTX_HOST="ssh://server"
streamed T1

# T2: DOCKER_HOST сильнее контекста — то же
run_tool DOCKER_HOST="ssh://user@203.0.113.1"
streamed T2

# T3: локальный docker — тот же поток, тот же код
run_tool DOCKER_CTX_HOST="unix:///Users/x/.docker/run/docker.sock"
streamed T3

echo "measure-linux-parity remote docker: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
