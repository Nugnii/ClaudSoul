#!/usr/bin/env bash
# СУДИТ: hooks/tests/run_all.sh
# test_run_all_changed_selects_frames.sh — правка свидетеля выбирает в `run_all.sh --changed` и РАМКИ: тесты, чей код
# называет его имя (копируют его, исполняют его, ставят заглушку под его именем) — D1310, корень R3.
#
# Повод (16 ноября 2026, D1309): правка `test_completion_gate_open_items.sh` выбрала только сам тест; рамки, копирующие
# его, в выборку не вошли и краснели до архивного свода. Ветка `hooks/tests/test_*.sh` выборщика отдавала одно имя:
# роль файла решалась формой пути — «тест», хотя для рамки свидетель есть механизм.
#
# F1 — рамка, чей КОД называет изменённый тест, выбрана вместе с ним;
# F2 — тест, назвавший его только в комментарии, не выбран (комментарий — не зависимость);
# F3 — тест с длинным именем, начинающимся с того же (`test_target_more.sh`), выбора рамок изменённого не меняет:
#      рамка ДЛИННОГО имени не выбрана правкой короткого;
# F4 — посторонний тест не выбран.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/run_all.sh" ] || { echo "FAIL: нет run_all.sh рядом"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
SB=$(mktemp -d) || { echo "BROKEN: нет временного каталога"; exit 2; }
trap 'rm -rf "$SB"' EXIT
T="$SB/hooks/tests"; mkdir -p "$T" "$SB/.claude-docs"
cp "$DIR/run_all.sh" "$T/" && cp "$DIR/../timeout-lib.sh" "$SB/hooks/" || { echo "подготовка мира не удалась: hooks/tests/test_run_all_changed_selects_frames.sh:$LINENO" >&2; exit 2; }
git -C "$SB" init -q . 2>/dev/null \
    || { echo "подготовка мира не удалась: hooks/tests/test_run_all_changed_selects_frames.sh:$LINENO (git init)" >&2; exit 2; }
_t() { printf '#!/usr/bin/env bash\n%s\nexit 0\n' "$2" > "$T/$1"; }
_t test_target.sh 'echo цель'
_t test_target_more.sh 'echo другая цель'
_t test_frame.sh 'cp "$DIR/test_target.sh" "$W/" && bash "$W/test_target.sh"'
_t test_more_frame.sh 'bash "$DIR/test_target_more.sh"'
_t test_mention.sh '# смотри test_target.sh — только упоминание в комментарии'
_t test_other.sh 'echo посторонний'
_t test_mention_indent.sh '    # с отступом: test_target.sh — упоминание, не зависимость'

OUT=$(cd "$T" && CHANGED_FILES="hooks/tests/test_target.sh" bash run_all.sh --list 2>&1); RC=$?
[ "$RC" -eq 0 ] || { echo "BROKEN: run_all.sh --list вернул $RC: $(printf '%s' "$OUT" | head -c 300)"; exit 2; }
grep -qx 'test_target.sh' <<< "$OUT" && ok || bad F0 "изменённый тест не выбран — рамка не отвечает: $OUT"
grep -qx 'test_frame.sh' <<< "$OUT" && ok || bad F1 "рамка, чей код называет изменённый тест, не выбрана"
grep -qx 'test_mention.sh' <<< "$OUT" && bad F2 "выбран тест, назвавший изменённый только в комментарии" || ok
grep -qx 'test_more_frame.sh' <<< "$OUT" && bad F3 "правка короткого имени выбрала рамку длинного (совпадение приставки)" || ok
grep -qx 'test_other.sh' <<< "$OUT" && bad F4 "выбран посторонний тест" || ok
grep -qx 'test_mention_indent.sh' <<< "$OUT" && bad F2b "выбран тест, назвавший изменённый в комментарии с отступом" || ok
# F5 — два изменённых теста сразу: выбраны рамки ОБОИХ (скептик opus по 5377782d, M1: мутант «рамки только последнего
# изменённого» проходил свидетеля, а 163 коммита из 962 с 23 октября трогают два теста и больше).
OUT=$(cd "$T" && CHANGED_FILES="hooks/tests/test_target.sh hooks/tests/test_target_more.sh" bash run_all.sh --list 2>&1)
grep -qx 'test_frame.sh' <<< "$OUT" && grep -qx 'test_more_frame.sh' <<< "$OUT" && ok \
    || bad F5 "при двух изменённых тестах выбраны не рамки обоих: $(printf '%s' "$OUT" | tr '\n' ' ')"

echo "test_run_all_changed_selects_frames: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
