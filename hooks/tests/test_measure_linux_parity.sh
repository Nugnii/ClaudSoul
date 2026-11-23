#!/usr/bin/env bash
# test_measure_linux_parity.sh — «Проверка результата» measure-linux-parity.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/measure-linux-parity.sh отвечает кодом контейнерного прогона
#            и пропускает наружу строку `FAILED:` и хвост сводки; без docker и без демона отвечает
#            2 «не измерено», а не зелёным.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Единственный кандидат в свидетели —
# `test_adv_irm_perl_absent_poisons_snapshot.sh` — упоминает инструмент, а не гоняет его, и зелен
# под заглушкой. Настоящий docker здесь не нужен и не должен быть нужен: в PATH подкладывается
# поддельный `docker`, который отвечает на `info` и `run` так, как велит нога. Команда БЕРЁТСЯ из
# шапки инструмента, как в test_split_provenance_log.sh.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/measure-linux-parity.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *measure-linux-parity.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
# В PATH только то, что нужно самому инструменту: bash, git и tar (дерево едет в контейнер потоком, D1355) и наш
# docker. Поддельный docker вход не читает — tar получает SIGPIPE, и код замера обязан остаться кодом `run`.
ln -s "$(command -v bash)" "$BIN/bash"
ln -s "$(command -v git)" "$BIN/git"
ln -s "$(command -v tar)" "$BIN/tar"

# Поддельный docker: $1 — код `info`, $2 — код `run`, $3 — что печатает `run`. Аргументы `run`
# пишутся в файл: рецепт контейнера живёт только в инструменте, и его маркеры сверяет T5.
mk_docker() {
    printf '#!/usr/bin/env bash\ncase "$1" in\n  info) exit %s ;;\n  run) printf "%%s\\n" "$@" > "%s"; printf "%%s\\n" "%s"; exit %s ;;\nesac\nexit 0\n' "$1" "$TMP/run-args" "$3" "$2" > "$BIN/docker"
    chmod +x "$BIN/docker"
}
run_tool() {
    OUT=$(cd "$REPO" && PATH="$BIN" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: docker нет — «не измерено», код 2 --------------------------------------------------
rm -f "$BIN/docker"; run_tool
[ "$RC" -eq 2 ] && ok || bad T1 "без docker rc=$RC — $OUT"
has T1 'docker недоступен — не измерено'

# --- T2: демон не отвечает — «не измерено», код 2 --------------------------------------------
mk_docker 1 0 ""; run_tool
[ "$RC" -eq 2 ] && ok || bad T2 "без демона rc=$RC — $OUT"
has T2 'демон docker не запущен — не измерено'

# --- T3: красный прогон в контейнере — код прогона и имя теста наружу ----------------------
mk_docker 0 1 'FAILED: test_x.sh
Hook test files: 1/2 passed
1'; run_tool
[ "$RC" -eq 1 ] && ok || bad T3 "красный контейнер rc=$RC — $OUT"
has T3 'FAILED: test_x.sh'
has T3 'Hook test files: 1/2 passed'

# --- T4: зелёный прогон — 0 --------------------------------------------------------------
mk_docker 0 0 'Hook test files: 2/2 passed
0'; run_tool
[ "$RC" -eq 0 ] && ok || bad T4 "зелёный контейнер rc=$RC — $OUT"
has T4 'Hook test files: 2/2 passed'

# --- T5: рамка контейнера — та же, что у раннера: маркеры рецепта в аргументах docker run ---
ARGS=$(cat "$TMP/run-args" 2>/dev/null)
for m in 'python3-yaml' 'procps' 'useradd -m tester' 'su tester' 'LANG=C.UTF-8' 'run_all.sh'; do
    grep -Fq -- "$m" <<< "$ARGS" && ok || bad T5 "в рецепте контейнера нет «${m}»"
done

# --- T6: образ контейнера — та же версия Ubuntu, что `runs-on` каждой задачи workflow (D1316) --------------------------
# Метка `ubuntu-latest` молча сменила образ раннера на 26.04 (uutils), а рецепт стоял на debian с GNU: три теста краснели
# только на CI, и повтор в контейнере их не видел. Плавающая метка отбивается, версия обязана совпасть.
# С 22 ноября 2026 `runs-on` — выражение: закрытый репозиторий идёт на домашний сервер, открытый снимок — на машину
# GitHub `ubuntu-<версия>`. Сверяется метка машины GitHub внутри выражения, а не строка целиком.
WF="$REPO/.github/workflows/tests.yml"
if [ -f "$WF" ]; then
    img=$(grep -oE 'ubuntu:[0-9]+\.[0-9]+' <<< "$ARGS" | head -1)
    runs=$(grep -E '^[[:space:]]*runs-on:' "$WF" | grep -oE 'ubuntu-[0-9a-z.]+' | sort -u)
    if [ -z "$img" ]; then bad T6 "образ рецепта не ubuntu:<версия>: $(grep -oE '[a-z]+:[a-z0-9.-]+ bash -c' <<< "$ARGS" | head -1)"
    elif [ "$runs" != "ubuntu-${img#ubuntu:}" ]; then bad T6 "runs-on workflow «$(tr '\n' ' ' <<< "$runs")» ≠ образ рецепта «${img}»"
    else ok; fi
else
    bad T6 "нет $WF — сверять образ не с чем"
fi

echo ""
echo "measure-linux-parity tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
