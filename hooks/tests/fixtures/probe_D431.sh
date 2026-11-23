#!/usr/bin/env bash
# СУДИТ: scripts/backlog-archive.sh
# probe_D431.sh — проба пункта D431: архиватор переносит закрытие без единой разобранной команды (аудит B1/B2).
# Результат: закрытие от MIN_ID, у которого в строке «Проверка.» нет команды в обратных кавычках либо нет строки «Результат.», остаётся в BACKLOG.md и называется; закрытие с командой и результатом уезжает в архив.
# Проверка результата: bash hooks/tests/fixtures/probe_D431.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён; 2 — рамка не собралась (stderr называет, что).
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой),
# собственный корень — от пути этого файла. Живой ~/.claude не читается: HOME подменён.
# Судится РЕЗУЛЬТАТ архиватора — куда легли пункты и каким кодом он вышел, — а не текст его исходника.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
ARCH="$MECH/scripts/backlog-archive.sh"
[ -f "$ARCH" ] || { echo "probe_D431: нет $ARCH" >&2; exit 2; }
[ -f "$MECH/hooks/backlog-lib.sh" ] || { echo "probe_D431: нет $MECH/hooks/backlog-lib.sh" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D431: нужен python3" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D431: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/state"
cat > "$T/BACKLOG.md" <<'EOF'
# BACKLOG

## Раздел

- ☑ **D901** Закрыт, а в строке «Проверка.» нет команды (B1).
  **Результат.** Есть.
  **Проверка.** пока не определена.

- ☑ **D902** Закрыт зелёной командой, а строки «Результат.» нет (B2).
  **Проверка.** `true` → 0

- ☑ **D903** Закрыт по контракту: и результат, и команда (положительный контроль).
  **Результат.** Есть.
  **Проверка.** `true` → 0
EOF
printf '# BACKLOG — архив\n' > "$T/ARCH.md"
unset BACKLOG_CHECKS_NESTED    # рамку задаёт проба, а не окружение (D334)
OUT=$(cd "$T" && HOME="$T/home" STATE_DIR="$T/state" BACKLOG_FILE="$T/BACKLOG.md" BACKLOG_ARCHIVE="$T/ARCH.md" \
      CLAUDSOUL_REPO="$MECH" bash "$ARCH" run 2>&1); RC=$?

# Положительный контроль: закрытие по контракту уезжает — иначе архиватор не работает и судить нечего.
if ! grep -q 'D903' "$T/ARCH.md" || grep -q 'D903' "$T/BACKLOG.md"; then
    echo "probe_D431: положительный контроль не прошёл — D903 не перенесён (rc=$RC): $OUT" >&2
    exit 2
fi
# Суд: D901 и D902 остались в BACKLOG.md, в архив не попали, и архиватор вышел не нулём (назвал задержанных).
BAD=0
for id in D901 D902; do
    grep -q "$id" "$T/BACKLOG.md" || BAD=1
    grep -q "$id" "$T/ARCH.md" && BAD=1
done
[ "$RC" -ne 0 ] || BAD=1
if [ "$BAD" -ne 0 ]; then
    echo "probe_D431: дефект — закрытие без команды либо без результата уехало в архив (rc=$RC); в BACKLOG.md остались: $(grep -o 'D90[12]' "$T/BACKLOG.md" | tr '\n' ' ')" >&2
    exit 1
fi
exit 0
