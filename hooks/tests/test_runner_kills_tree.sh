#!/usr/bin/env bash
# test_runner_kills_tree.sh — тест, убитый сторожем, не оставляет сирот.
#
# Результат: после срабатывания сторожевого таймаута в системе не остаётся ни одного процесса,
#            запущенного убитым тестом
# Проверка результата: bash hooks/tests/test_runner_kills_tree.sh даёт 0
#
# Повод, 7 сентября 2026, наблюдён владельцем по загрузке машины. Сторож раннера бил
# `kill -9 "$pid"` — только сам тест. Всё, что тест запустил фоном, уходило к pid 1 и
# продолжало крутиться. Накопилось 100 сирот `test_injection_log_rotate_concurrent`
# возрастом до 8 часов, load average 41,6.
#
# ДЕФЕКТ С ПОЛОЖИТЕЛЬНОЙ ОБРАТНОЙ СВЯЗЬЮ, и потому он рос сам: каждый убитый прогон оставлял
# сироту, сироты ели процессор, следующий прогон становился медленнее, умирал по таймауту
# раньше — и оставлял ещё одну. Оттого сто штук за восемь часов, а не две-три.
#
# Проверяются ДВА рубежа по отдельности, потому что они закрывают разные смерти:
#   · `_kill_tree` в раннере — убирает детей при ЛЮБОЙ смерти теста (класс, все тесты);
#   · проверка живости родителя в самом цикле — единственное, что работает, если дерево
#     убить не успели или ребёнок уже осиротел (гигиена, конкретный тест).
# Ни один из двух не делает второй лишним: первый не сработает, если раннера в цепочке нет
# вовсе, второй — если ребёнок не проверяет родителя.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)
# Уборка ЗА СОБОЙ, включая процессы: страж класса «тест оставляет сирот» не имеет права
# оставлять сирот сам. Файлы жертв несут метку каталога, поэтому добиваем по ней.
_cleanup() {
    local _p
    for _p in $(pgrep -f "$TMP/victim-" 2>/dev/null); do kill -9 "$_p" 2>/dev/null || true; done
    rm -rf "$TMP" 2>/dev/null || true
}
trap _cleanup EXIT INT TERM

command -v pgrep >/dev/null 2>&1 || { echo "SKIP: нет pgrep"; exit 0; }

# Фикстура ФОРМЫ ИЗ МИРА: ровно то устройство, что дало сирот — фоновый цикл по файлу-флагу.
# $1 — 1, если ребёнок проверяет живость родителя; $2 — МЕТКА вызова.
# Метка обязательна и уникальна: первая редакция ключевала файлы только видом ($1), и нога T2
# читала pid, записанный ногой T1 — то есть судила о чужом, уже осиротевшем ребёнке.
make_victim() {
    local f="$TMP/victim-$2.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'FLAG="%s/flag-$$"; touch "$FLAG"\n' "$TMP"
        printf 'SELF_PID=$$\n'
        printf 'printf "%%s" "$$" > "%s/victim-pid-%s"\n' "$TMP" "$2"
        if [ "$1" = "1" ]; then
            printf '( while [ -f "$FLAG" ] && kill -0 "$SELF_PID" 2>/dev/null; do sleep 0.2; done; printf x > "%s/child-gone-%s" ) &\n' "$TMP" "$2"
        else
            printf '( while [ -f "$FLAG" ]; do sleep 0.2; done ) &\n'
        fi
        printf 'printf "%%s" "$!" > "%s/child-pid-%s"\n' "$TMP" "$2"
        printf 'sleep 30\n'
    } > "$f"
    chmod +x "$f"
    printf '%s' "$f"
}

# --- T1: ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ — прежнее устройство оставляет сироту ---
# Без этой ноги зелень T2 не значит ничего: может, ребёнок и так умирает сам.
V=$(make_victim 0 t1)
bash "$V" >/dev/null 2>&1 & VP=$! || { echo "подготовка мира не удалась: hooks/tests/test_runner_kills_tree.sh:$LINENO" >&2; exit 1; }
for _ in $(seq 1 40); do [ -s "$TMP/child-pid-t1" ] && break; sleep 0.1; done
CP=$(cat "$TMP/child-pid-t1" 2>/dev/null)
kill -9 "$VP" 2>/dev/null; sleep 1
if [ -n "$CP" ] && kill -0 "$CP" 2>/dev/null; then ok
else bad "T1" "прежнее устройство сироту НЕ оставило — предмет не воспроизводится, остальное про воздух"; fi
# За собой убираем СРАЗУ: нога доказала сироту, оставлять её — плодить ровно то, что чиним.
kill -9 "$CP" 2>/dev/null || true

# --- T2: _kill_tree раннера убирает и ребёнка ---
# Помощник берётся ИЗ раннера, а не переписывается сюда: копия правила у теста разошлась бы
# с оригиналом молча (род K реестра).
# Источник помощника переопределяется РАДИ МУТАЦИИ: зелень ноги не доказывает ничего, пока
# она не покраснела на прежнем устройстве (голый `kill -9 "$pid"`). Образец — test_drift_check.
# С 13 сентября 2026 помощник живёт в hooks/timeout-lib.sh (D369) и берётся оттуда; раннер его
# зовёт, а не определяет. Источник по-прежнему переопределяем ради мутации.
TIMEOUT_LIB_SRC="${TIMEOUT_LIB_SRC:-$TESTS_DIR/../timeout-lib.sh}"
# shellcheck source=/dev/null
[ -f "$TIMEOUT_LIB_SRC" ] && . "$TIMEOUT_LIB_SRC"
if ! command -v kill_tree >/dev/null 2>&1; then
    bad "T2" "kill_tree не найден в $TIMEOUT_LIB_SRC — библиотека его потеряла либо переименовала"
else
    V=$(make_victim 0 t2)
    bash "$V" >/dev/null 2>&1 & VP=$! || { echo "подготовка мира не удалась: hooks/tests/test_runner_kills_tree.sh:$LINENO" >&2; exit 1; }
    for _ in $(seq 1 40); do [ -s "$TMP/child-pid-t2" ] && break; sleep 0.1; done
    CP2=$(cat "$TMP/child-pid-t2" 2>/dev/null)
    kill_tree "$VP"; sleep 1
    if [ -n "$CP2" ] && kill -0 "$CP2" 2>/dev/null; then
        kill -9 "$CP2" 2>/dev/null
        bad "T2" "после kill_tree ребёнок жив (pid $CP2) — сирота остаётся"
    else ok; fi
fi

# --- T3: ребёнок с проверкой родителя умирает САМ, даже без _kill_tree ---
# Второй рубеж: он работает там, где дерево убить не успели.
V=$(make_victim 1 t3)
bash "$V" >/dev/null 2>&1 & VP=$! || { echo "подготовка мира не удалась: hooks/tests/test_runner_kills_tree.sh:$LINENO" >&2; exit 1; }
for _ in $(seq 1 40); do [ -s "$TMP/child-pid-t3" ] && break; sleep 0.1; done
CP3=$(cat "$TMP/child-pid-t3" 2>/dev/null)
kill -9 "$VP" 2>/dev/null
GONE=0
for _ in $(seq 1 40); do kill -0 "$CP3" 2>/dev/null || { GONE=1; break; }; sleep 0.2; done
if [ "$GONE" = "1" ]; then ok
else kill -9 "$CP3" 2>/dev/null; bad "T3" "ребёнок с проверкой родителя пережил его смерть (pid $CP3)"; fi

# --- T4: у теста-виновника оба рубежа стоят ---
# Форма проверяется по ИМЕНАМ, а не по прозе: идентификаторы устойчивее слов.
VICTIM="$TESTS_DIR/test_injection_log_rotate_concurrent.sh"
if [ -f "$VICTIM" ]; then
    grep -q 'kill -0 "$SELF_PID"' "$VICTIM" && ok || bad "T4" "в тесте-виновнике нет проверки живости родителя"
    grep -q '^trap ' "$VICTIM" && ok || bad "T4b" "в тесте-виновнике нет ловушки уборки"
else
    ok; ok
fi

echo "runner kills tree: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
