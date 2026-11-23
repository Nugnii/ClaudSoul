#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh hooks/lib/transcript_window.py
# test_adv_fold3_turn_fallback_all_turns.sh — противник свёртки, раунд 3 (D498): шаг свёртки ХОДА, сбрасывающийся на реплике владельца (договор), даёт одно и то же с помощником и без него.
#
# Договор `transcript_fold <путь> <имя> turn <шаг...>` (hook-input-lib.sh, модуль
# transcript-window): «turn начинается с реплики владельца, и новая реплика начинает свёртку
# заново, поэтому шаг не обязан сам сбрасываться на ней». Свидетель договора — нога F4 в
# test_transcript_fold.sh (шаг-счётчик, ход после новой реплики = 2), но только с помощником.
# Запасной путь (`_transcript_fold_whole`): «шаг по всему окну хода» — `transcript_turn_window`,
# а оно без помощника (нет python3, нет lib/transcript_window.py, помощник отказал) отдаёт
# ФАЙЛ ЦЕЛИКОМ. Шаг хода получает все ходы сессии. rc_* этого не видят только потому, что
# RC_TURN_STEP сбрасывается сам; договор API обещал обратное.
#
# Исход атаки — СУЖЕНИЕ ДОГОВОРА, а не третья копия определения «реплики владельца» на jq ради
# редкого пути без python3 (корень R1): шаг свёртки хода ОБЯЗАН сам сбрасываться на реплике
# владельца — помощник начинает свёртку с неё ради цены, запасной путь отдаёт весь файл. Нога
# S1 закрепляет договор: соблюдающий его шаг (счётчик со сбросом на записи user с текстом) даёт
# одно и то же на обоих путях. Шаг, не сбрасывающийся сам, договору не отвечает (атака: «5» вместо «2»).
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3 (нужен для эталона)"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
F="$T/t.jsonl"; NOLIB="$T/nolib"; mkdir -p "$NOLIB" "$T/st1" "$T/st2"
case "$F|$NOLIB|$TMPDIR" in "$T"/*"|$T"/*"|$T"/*) ;; *) echo "FAIL [K0]: путь записи вне каталога теста"; exit 1 ;; esac
cp "$HOOKS/hook-input-lib.sh" "$NOLIB/"                 # библиотека без lib/ — помощника нет

# Шаг по договору: сброс на записи user с непустым текстом (её граница не уже реплики владельца).
CNT='reduce inputs as $r (($a[0] // 0); if $r.type == "user" and ((($r.message.content // [])[0].text // "") != "") then 0 else . + (if $r.x then 1 else 0 end) end)'
u() { printf '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
# Два хода: первый — три записи шага, второй (текущий) — две.
{ u "раз"; printf '%s\n' '{"x":true}' '{"x":true}' '{"x":true}'; u "два"; printf '%s\n' '{"x":true}' '{"x":true}'; } > "$F"

fold() {  # fold <каталог библиотеки> <каталог состояния>
    STATE_DIR="$2" bash -c '. "$1/hook-input-lib.sh"; transcript_fold "$2" cnt turn jq -cn "$3" --slurpfile a' _ "$1" "$F" "$CNT"
}
WITH=$(fold "$HOOKS" "$T/st1")
[ "$WITH" = 2 ] && ok || bad K1 "с помощником свёртка хода дала «${WITH}», ожидалось 2 — тест не о том"

# Предмет: без помощника шаг по договору считает тот же текущий ход, что и с помощником.
WITHOUT=$(fold "$NOLIB" "$T/st2")
[ "$WITHOUT" = "$WITH" ] && ok \
    || bad S1 "без помощника шаг по договору дал «${WITHOUT}» вместо «${WITH}»: запасной путь расходится с помощником"

echo "test_adv_fold3_turn_fallback_all_turns: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
