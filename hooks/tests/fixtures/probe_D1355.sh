#!/usr/bin/env bash
# СУДИТ: scripts/measure-linux-parity.sh
# probe_D1355.sh — замер `suite-linux` мерит, когда docker этой машины направлен на другую (домашний сервер владельца):
#   `docker run` позван без монтирования папки этой машины и получил дерево потоком на вход.
#
# Повод (22 ноября 2026, D1355). Docker на Mac направлен на сервер (`docker context use server`, адрес `ssh://server`).
# Замер монтировал папку этой машины (`-v "$PWD":/repo`) и на сервере смонтировал бы пустой каталог с тем же путём,
# поэтому такой docker был «не измерено», код 2 — и стоял гейт публикации. Решение владельца того же дня — «Дерево
# потоком»: файлы репозитория и `.git` идут в контейнер через вход `docker run -i`.
# Заглушка docker отвечает адресом `ssh://server` (так отвечает `docker context inspect` на машине владельца), пишет
# аргументы `run` и сохраняет поток со входа; итог набора печатает, как печатает его контейнер.
# Проверка результата: bash hooks/tests/fixtures/probe_D1355.sh → 0 — замер позвал `docker run -i` без `-v`, в потоке
#   есть `hooks/tests/run_all.sh` и `.git/HEAD`, код замера — код «контейнера»; 1 — не мерит или мерит не потоком;
#   2 — не измерено (нет замера, git или tar; заглушка не узнаёт поток, собранный вручную).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
T="$REPO/scripts/measure-linux-parity.sh"
[ -f "$T" ] && command -v git >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 \
    || { echo "нет замера, git или tar — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/bin/docker" <<SH
#!/usr/bin/env bash
case "\$1" in
  context) printf '%s\n' "ssh://server" ;;
  info) exit 0 ;;
  run) printf '%s\n' "\$@" > "$W/args"; cat > "$W/stream.tar"; echo "Hook test files: 2/2 passed"; exit 0 ;;
esac
exit 0
SH
chmod +x "$W/bin/docker"

# Контроль «рамка умеет сказать да»: поток, собранный вручную, заглушка сохраняет, и tar его читает.
mkdir -p "$W/ctl/hooks/tests" && : > "$W/ctl/hooks/tests/run_all.sh"
tar -cf - -C "$W/ctl" hooks | PATH="$W/bin:$PATH" docker run -i x >/dev/null 2>&1
grep -qx 'hooks/tests/run_all.sh' <<< "$(tar -tf "$W/stream.tar" 2>/dev/null)" \
    || { echo "заглушка не узнаёт поток, собранный вручную — не измерено"; exit 2; }
rm -f "$W/stream.tar" "$W/args"

out=$(cd "$REPO" && env -u DOCKER_HOST PATH="$W/bin:$PATH" bash "$T" 2>&1); rc=$?
if [ ! -f "$W/args" ]; then
    echo "docker на другой машине — замер не позвал docker run (код $rc): $(head -1 <<< "$out")"; exit 1
fi
bad=""
grep -qx -- '-i' "$W/args" || bad="${bad}; нет -i"
grep -qx -- '-v' "$W/args" && bad="${bad}; монтирует папку этой машины (-v)"
list=$(tar -tf "$W/stream.tar" 2>/dev/null)
grep -qE '^(\./)?hooks/tests/run_all\.sh$' <<< "$list" || bad="${bad}; в потоке нет hooks/tests/run_all.sh"
grep -qE '^(\./)?\.git/HEAD$' <<< "$list" || bad="${bad}; в потоке нет .git/HEAD"
[ "$rc" -eq 0 ] || bad="${bad}; код замера $rc при зелёном контейнере"
if [ -n "$bad" ]; then echo "замер при docker на другой машине — не потоком${bad}"; exit 1; fi
echo "docker на другой машине: дерево ушло потоком ($(grep -c . <<< "$list") записей), без монтирования, код 0"
exit 0
