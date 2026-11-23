#!/usr/bin/env bash
# СУДИТ: hooks/completion-gate.sh scripts/backlog-archive.sh hooks/tests/run_all.sh scripts/backlog-refresh-readings.sh scripts/backlog-return-check.sh scripts/backlog-recheck.sh hooks/backlog-open-write-guard.sh scripts/measurement-due.sh
# Проба D1198: исполнители чужих команд не оставляют временных каталогов в TMPDIR — в том числе при сроке.
# Восемь ног — восемь исполнителей: completion-gate («Проверка» открытого пункта), backlog-archive
# («Проверка» закрытого при переносе), run_all (тест набора), backlog-refresh-readings
# («Показание»), backlog-return-check («Проверка возврата»), backlog-recheck --archive
# («Проверки» архива), backlog-open-write-guard («Проверка» нового пункта при записи BACKLOG.md),
# measurement-due (команда реестра замеров). `scripts/named-limits.py` ходит тем же правилом
# `hooks/lib/bounded_run.py`, что гейт, архиватор и пересчёт (одно правило судит проба D1199). Каждой ноге дана
# команда, которая создаёт каталог в TMPDIR и НЕ убирает его — так пишут 62 теста с припиской
# «уберёт система». Система не убирает: 31 октября 2026 в T лежало 41 857 таких каталогов.
# Формы две: шаблонная (`mktemp -d "${TMPDIR:-/tmp}/…"`, читает TMPDIR везде) и голая (`mktemp -d`) — 819 из 883 в
# тестах; на macOS голая TMPDIR не читает и удерживается только подменой `mktemp` исполнителя (`hooks/lib/mktemp-shim.sh`).
# Голая форма — и каталог (`mktemp -d`), и файл (`mktemp`, 64 строки в 27 файлах). Путь голой записывается в файл: где бы каталог ни лёг, после исполнителя его быть не должно.
# Ноги t* — те же команды, ждущие дольше срока: исполнитель снимает их по сроку и обязан убрать и каталог (M2
# скептика D1198). Пять устройств уборки: правило модуля (нога ta, гейт), сверщик, условие возврата, страж записи,
# набор. Идут параллельно — каждая ждёт срок в 1 с.
# Код: 0 — ни у одного исполнителя каталогов не осталось; 1 — остались (названы);
# 2 — не измерено (исполнитель не дошёл до команды, нет файла, нет jq или git).
set -uo pipefail
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING MEASURE_DUE_NESTED
REPO="$(cd "$(dirname "$0")/../../.." && pwd -P)"
for f in hooks/completion-gate.sh scripts/backlog-archive.sh hooks/tests/run_all.sh \
         hooks/timeout-lib.sh hooks/portable-lib.sh \
         scripts/backlog-refresh-readings.sh scripts/backlog-return-check.sh scripts/backlog-recheck.sh \
         hooks/backlog-open-write-guard.sh scripts/measurement-due.sh; do
    [ -f "$REPO/$f" ] || { echo "нет $f"; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "нет jq — нога g не измерена"; exit 2; }
S=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1198.XXXXXX") || exit 2
trap '[ -f "$S/bare-leaks" ] && while IFS= read -r p; do case "$p" in /*) rm -rf "$p" ;; esac; done < "$S/bare-leaks"; rm -rf "$S"' EXIT
LEAK='d=$(mktemp -d "${TMPDIR:-/tmp}/leak-D1198.XXXXXX") && : > "$d/x"; b=$(mktemp -d) && : > "$b/x" && echo "$b" >> "'"$S"'/bare-leaks"; f=$(mktemp) && echo "$f" >> "'"$S"'/bare-leaks"'
bad=0

# Нога A — completion-gate, открытый пункт: красная «Проверка» исполняется, каталог остаётся.
mkdir -p "$S/a-tmp" "$S/a-state"
cat > "$S/a.md" <<EOF
# BACKLOG

### D301 ◐ утечка из Проверки открытого пункта
**Результат.** нет
**Проверка.** \`$LEAK; : > "$S/ran-a"; exit 1\` → 0
EOF
printf '{"session_id":"probe-d1198-a","cwd":"/"}' \
    | env TMPDIR="$S/a-tmp" CG_BACKLOG="$S/a.md" STATE_DIR="$S/a-state" \
          bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1

# Нога B — backlog-archive, закрытый пункт: зелёная «Проверка» исполняется при переносе.
mkdir -p "$S/b-tmp"
cat > "$S/b.md" <<EOF
# BACKLOG

### D302 ☑ утечка из Проверки закрытого пункта
**Результат.** да
**Проверка.** \`$LEAK; : > "$S/ran-b"\` → 0
EOF
env TMPDIR="$S/b-tmp" BACKLOG_FILE="$S/b.md" BACKLOG_ARCHIVE="$S/b-arch.md" STATE_DIR="$S/b-state" \
    bash "$REPO/scripts/backlog-archive.sh" run >/dev/null 2>&1

# Нога C — run_all: копия набора из одного теста, который оставляет каталог.
mkdir -p "$S/c/hooks/tests" "$S/c-tmp" "$S/c-state"
cp "$REPO/hooks/tests/run_all.sh" "$S/c/hooks/tests/"
cp "$REPO/hooks/timeout-lib.sh" "$REPO/hooks/portable-lib.sh" "$S/c/hooks/"
mkdir -p "$S/c/hooks/lib" && cp "$REPO/hooks/lib/mktemp-shim.sh" "$S/c/hooks/lib/" 2>/dev/null
printf '%s\n' '#!/usr/bin/env bash' "$LEAK" ": > \"$S/ran-c\"" 'exit 0' > "$S/c/hooks/tests/test_leak_d1198.sh"
env TMPDIR="$S/c-tmp" STATE_DIR="$S/c-state" SUITE_RUN_LOG="$S/c-suite.tsv" \
    bash "$S/c/hooks/tests/run_all.sh" >/dev/null 2>&1

# Нога D — пересчёт показаний: «Показание» открытого пункта исполняется на каждом Stop.
mkdir -p "$S/d-tmp"
printf -- '- ☐ **D9711** утечка из Показания\n  **Проверка.** `false` → 0\n  **Показание.** `%s; : > "%s/ran-d"; echo 1`\n  **Последнее показание (2026-10-01).** 0\n' \
    "$LEAK" "$S" > "$S/d.md"
env TMPDIR="$S/d-tmp" BACKLOG_FILE="$S/d.md" STATE_DIR="$S/d-state" \
    bash "$REPO/scripts/backlog-refresh-readings.sh" --check >/dev/null 2>&1

# Нога E — условие возврата: «Проверка возврата» исполняется из корня git-дерева пункта.
mkdir -p "$S/e-tmp" "$S/e"
git -C "$S/e" init -q 2>/dev/null || { echo "нет git — нога e не измерена"; exit 2; }
printf -- '- ☐ **D9712** утечка из условия возврата\n  **Проверка.** `false` → 0\n  **Проверка возврата:** `%s; : > "%s/ran-e"; false`\n' \
    "$LEAK" "$S" > "$S/e/BACKLOG.md"
( cd "$S/e" && env TMPDIR="$S/e-tmp" STATE_DIR="$S/e-state" bash "$REPO/scripts/backlog-return-check.sh" ) >/dev/null 2>&1

# Нога F — сверщик закрытых: «Проверки» пунктов архива исполняются режимом --archive.
mkdir -p "$S/f-tmp"
printf -- '- ☑ **D9713** утечка из Проверки архива\n  **Результат.** да\n  **Проверка.** `%s; : > "%s/ran-f"` → 0\n' \
    "$LEAK" "$S" > "$S/f-arch.md"
# Имя архива сверщика — оба написания: `BACKLOG_ARCHIVE` до D1147 круга 2, `BACKLOG_RECHECK_ARCHIVE` после.
# Без своего архива режим исполнил бы все «Проверки» НАСТОЯЩЕГО архива (514, около 25 минут).
env TMPDIR="$S/f-tmp" BACKLOG_ARCHIVE="$S/f-arch.md" BACKLOG_RECHECK_ARCHIVE="$S/f-arch.md" \
    STATE_DIR="$S/f-state" BACKLOG_ARCHIVE_THREADS=1 \
    bash "$REPO/scripts/backlog-recheck.sh" --archive >/dev/null 2>&1

# Нога G — страж записи бэклога: «Проверка» нового открытого пункта исполняется при каждой записи BACKLOG.md.
mkdir -p "$S/g" "$S/g-tmp" "$S/g-state"; printf '# BACKLOG\n' > "$S/g/BACKLOG.md"
_c=$(printf -- '# BACKLOG\n\n- ☐ **D9714** утечка из Проверки при записи\n  **Проверка.** `%s; : > "%s/ran-g"; exit 1` → 0\n' "$LEAK" "$S")
jq -cn --arg f "$S/g/BACKLOG.md" --arg c "$_c" '{session_id:"probe-d1198-g", tool_name:"Write", tool_input:{file_path:$f, content:$c}}' \
    | env TMPDIR="$S/g-tmp" STATE_DIR="$S/g-state" bash "$REPO/hooks/backlog-open-write-guard.sh" >/dev/null 2>&1

# Нога H — бегун замеров: команда реестра исполняется по сроку замера.
mkdir -p "$S/h-tmp" "$S/h-state"
printf 'leak-d1198\t1\t%s; : > "%s/ran-h"\tпроба D1198\n' "$LEAK" "$S" > "$S/h-reg.tsv"
env TMPDIR="$S/h-tmp" STATE_DIR="$S/h-state" MEASUREMENT_REGISTRY="$S/h-reg.tsv" \
    bash "$REPO/scripts/measurement-due.sh" run >/dev/null 2>&1

# Ноги срока.
mkdir -p "$S/ta-tmp" "$S/ta-state" "$S/tc/hooks/tests" "$S/tc-tmp" "$S/tc-state" "$S/te-tmp" "$S/te" "$S/tf-tmp" \
    "$S/tg" "$S/tg-tmp" "$S/tg-state"
printf '# BACKLOG\n\n### D301 ◐ утечка при сроке\n**Результат.** нет\n**Проверка.** `%s; : > "%s/ran-ta"; sleep 30` → 0\n' \
    "$LEAK" "$S" > "$S/ta.md"
( printf '{"session_id":"probe-d1198-ta","cwd":"/"}' | env TMPDIR="$S/ta-tmp" CG_TIMEOUT=1 CG_BACKLOG="$S/ta.md" \
      STATE_DIR="$S/ta-state" bash "$REPO/hooks/completion-gate.sh" >/dev/null 2>&1 ) &
cp "$REPO/hooks/tests/run_all.sh" "$S/tc/hooks/tests/"
cp "$REPO/hooks/timeout-lib.sh" "$REPO/hooks/portable-lib.sh" "$S/tc/hooks/"
mkdir -p "$S/tc/hooks/lib" && cp "$REPO/hooks/lib/mktemp-shim.sh" "$S/tc/hooks/lib/" 2>/dev/null
printf '%s\n' '#!/usr/bin/env bash' "$LEAK" ": > \"$S/ran-tc\"" 'sleep 30' > "$S/tc/hooks/tests/test_leak_d1198.sh"
( env TMPDIR="$S/tc-tmp" STATE_DIR="$S/tc-state" SUITE_RUN_LOG="$S/tc-suite.tsv" TEST_TIMEOUT=1 TEST_TIMEOUT_MIN=1 \
      TEST_RERUN_FACTOR=1 bash "$S/tc/hooks/tests/run_all.sh" >/dev/null 2>&1 ) &
# ponytail: одиночный повтор зависшего (TEST_RERUN_FACTOR, 6× срок) выключен — он идёт той же `run_with_timeout`
# набора, что и первый прогон, а стоил ноге 7 с из 9.
git -C "$S/te" init -q 2>/dev/null || { echo "нет git — нога te не измерена"; exit 2; }
printf -- '- ☐ **D9712** утечка при сроке\n  **Проверка.** `false` → 0\n  **Проверка возврата:** `%s; : > "%s/ran-te"; sleep 30`\n' \
    "$LEAK" "$S" > "$S/te/BACKLOG.md"
( cd "$S/te" && env TMPDIR="$S/te-tmp" STATE_DIR="$S/te-state" RETURN_CHECK_TIMEOUT=1 \
      bash "$REPO/scripts/backlog-return-check.sh" ) >/dev/null 2>&1 &
printf -- '- ☑ **D9713** утечка при сроке\n  **Результат.** да\n  **Проверка.** `%s; : > "%s/ran-tf"; sleep 30` → 0\n' \
    "$LEAK" "$S" > "$S/tf-arch.md"
( env TMPDIR="$S/tf-tmp" BACKLOG_ARCHIVE="$S/tf-arch.md" BACKLOG_RECHECK_ARCHIVE="$S/tf-arch.md" STATE_DIR="$S/tf-state" \
      BACKLOG_ARCHIVE_THREADS=1 BACKLOG_ARCHIVE_CHECK_TIMEOUT=1 bash "$REPO/scripts/backlog-recheck.sh" --archive >/dev/null 2>&1 ) &
printf '# BACKLOG\n' > "$S/tg/BACKLOG.md"
_c=$(printf -- '# BACKLOG\n\n- ☐ **D9715** утечка при сроке\n  **Проверка.** `%s; : > "%s/ran-tg"; sleep 30` → 0\n' "$LEAK" "$S")
( jq -cn --arg f "$S/tg/BACKLOG.md" --arg c "$_c" '{session_id:"probe-d1198-tg", tool_name:"Write", tool_input:{file_path:$f, content:$c}}' \
      | env TMPDIR="$S/tg-tmp" STATE_DIR="$S/tg-state" OPEN_WRITE_TIMEOUT=1 \
            bash "$REPO/hooks/backlog-open-write-guard.sh" >/dev/null 2>&1 ) &
wait

for leg in a b c d e f g h ta tc te tf tg; do
    [ -e "$S/ran-$leg" ] || { echo "нога $leg: исполнитель не дошёл до команды — не измерено"; exit 2; }
    n=$(find "$S/$leg-tmp" -name 'leak-D1198.*' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" != 0 ]; then echo "нога $leg: осталось каталогов $n"; bad=1; fi
done
nb=$(wc -l < "$S/bare-leaks" 2>/dev/null | tr -d ' ')
[ "${nb:-0}" -gt 0 ] || { echo "голая форма не исполнилась ни в одной ноге — не измерено"; exit 2; }
while IFS= read -r p; do
    [ -e "$p" ] && { echo "голая форма mktemp: каталог остался — $p"; bad=1; }
done < "$S/bare-leaks"
[ "$bad" = 0 ] && echo "все восемь исполнителей убрали за командой обеих форм, в том числе при сроке"
exit "$bad"
