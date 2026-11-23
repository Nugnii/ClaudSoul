#!/usr/bin/env bash
# test_rework_rerun_streak.sh — серия прогонов ОДНОГО файла без правок между ними названа (D418).
#
# Результат: N прогонов подряд одного проверочного файла при неизменном мире дают сигнал
#            повтора; правка между прогонами серию обрывает
# Проверка результата: bash hooks/tests/test_rework_rerun_streak.sh даёт 0
#
# Повод (ProjectA_NEW, 9 сентября 2026): один ассерт отлаживался ПЯТЬЮ полными прогонами спеки
# вместо отладочного режима. Не видел этого никто: `error-tracker` считает провалы КОМАНД, а
# команды завершались успешно; `rework-detector` ловит «правка → прогон → правка», то есть
# требует правку МЕЖДУ прогонами, а здесь её нет вовсе. Предметы противоположны.
#
# Замер до стройки по 74 расшифровкам: серий «один файл подряд без правки» 809, длиной >= 5 —
# 53 (около 0,7 на сессию). Точность на выборке 14 длинных серий: 12 настоящих, 2 со скрытой
# правкой (86%) — уровень ПОДСКАЗКИ, не отказа.
#
# ДОСТИЖИМОСТЬ ТОЧКИ ВЫЗОВА — отдельный предмет, и он куплен шестью заходами. Две редакции
# подряд молчали шесть раз из шести: первая считала серию по журналу правок, который серия
# прогонов не создаёт никогда; вторая перенесла состояние на своё, но вызов остался ниже
# раннего выхода по отсутствию того же журнала. Оба раза фикстура говорила «молчит», и оба
# раза причина объяснялась состоянием, а не достижимостью. Нога T1 проверяет именно её.
set -uo pipefail
unset BACKLOG_CHECKS_NESTED

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/rework-detector.sh"
[ -f "$HOOK" ] || { echo "SKIP: нет $HOOK"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

PASS=0; FAIL=0; SPOKE=0
# ПЕСОЧНИЦА ЦЕЛЕЙ — во временном каталоге (D1268): детектор судит временный путь по каталогу сессии (`cwd` = $REPO
# ниже), а не по форме пути, поэтому песочница под домашним каталогом не нужна — и снятый по сроку прогон её там не
# оставляет. Прежде она жила в HOME «ближе к боевым условиям» и по образцу соседнего test_rework_detector.sh.
TMP=$(mktemp -d); trap 'rm -rf "$TMP" "$SANDBOX"' EXIT
SANDBOX=$(mktemp -d)   # D1268: детектор судит временный каталог по корню сессии (`cwd` = $REPO), HOME не нужен
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

REPO="$SANDBOX/repo"; mkdir -p "$REPO"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t \
  && echo x > a.txt && git add -A && git commit -qm init )

call() { # call <sid> <команда> [tool] → вывод хука
    local sid="$1" cmd="$2" tool="${3:-Bash}"
    mkdir -p "$TMP/state"
    if [ "$tool" = "Bash" ]; then
        printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' \
            "$sid" "$cmd" "$REPO"
    else
        printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
            "$sid" "$REPO/$cmd" "$REPO"
    fi | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
said() { grep -q 'прогон подряд одного файла' <<< "$1"; }

# --- T1: пятый прогон подряд назван, до него тихо ------------------------------------
QUIET_BEFORE=1
for i in 1 2 3 4; do
    said "$(call s1 'bash hooks/tests/test_x.sh')" && QUIET_BEFORE=0
done
[ "$QUIET_BEFORE" = 1 ] && ok || bad T1a "страж заговорил раньше порога — шум на обычной работе"
OUT5=$(call s1 'bash hooks/tests/test_x.sh')
if said "$OUT5"; then ok; SPOKE=$((SPOKE + 1)); else
    bad T1b "пятый прогон подряд не назван — проверь ДОСТИЖИМОСТЬ точки вызова: две редакции молчали именно здесь"; fi

# --- T2: правка между прогонами ОБРЫВАЕТ серию ---------------------------------------
for i in 1 2 3 4; do call s2 'bash hooks/tests/test_y.sh' >/dev/null; done
call s2 'a.txt' Write >/dev/null           # мир изменился
OUT=$(call s2 'bash hooks/tests/test_y.sh')
said "$OUT" && bad T2 "серия не оборвана правкой — повтор при изменившемся мире повтором не является" || ok

# --- T3: прогон ДРУГОГО файла обрывает серию -----------------------------------------
for i in 1 2 3 4; do call s3 'bash hooks/tests/test_a.sh' >/dev/null; done
call s3 'bash hooks/tests/test_b.sh' >/dev/null
OUT=$(call s3 'bash hooks/tests/test_a.sh')
said "$OUT" && bad T3 "серия пережила прогон другого файла — счёт идёт не по предмету" || ok

# --- T4: не-прогон серию не трогает ---------------------------------------------------
# Осмотр между прогонами (`git status`, `ls`) мир не меняет, и повтор от него повтором
# быть не перестаёт: иначе счётчик обнулялся бы любой посторонней командой.
for i in 1 2 3 4; do call s4 'bash hooks/tests/test_c.sh' >/dev/null; done
call s4 'git status --short' >/dev/null
OUT=$(call s4 'bash hooks/tests/test_c.sh')
if said "$OUT"; then ok; SPOKE=$((SPOKE + 1)); else
    bad T4 "осмотр между прогонами обнулил серию — счётчик рвётся не на правке"; fi

# --- T6 (D1330): предмет серии — ЗАПУСК теста, а не строка о нём ----------------------
# Образец по всему тексту команды читал прогоном поиск строки запуска, рецепт в теле heredoc и остаток имени файла
# (`gate.sh hooks/tests/x.sh` — «sh» из конца имени): пять таких команд давали «5-й прогон подряд» теста, который не
# запускался ни разу. Слова команд даёт владелец разбора. Контроль молчания — T1b и T6d: настоящий запуск назван.
callj() { # callj <sid> <команда> → вывод хука; команда — любым текстом (кавычки, переводы строк)
    jq -cn --arg s "$1" --arg c "$2" --arg d "$REPO" '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
NOTE=$(printf "cat > notes.txt <<'N'\nпроверка: bash hooks/tests/test_x.sh\nN")
for pair in "s6a|grep -rn 'bash hooks/tests/test_x.sh' docs" "s6b|$NOTE" "s6c|git add hooks/gate.sh hooks/tests/test_gate.sh" \
            "s6e|git commit -q -m 'зелёный прогон bash hooks/tests/test_x.sh'"; do
    sid="${pair%%|*}"; cmd="${pair#*|}"; Q=1
    for i in 1 2 3 4 5 6; do said "$(callj "$sid" "$cmd")" && Q=0; done
    [ "$Q" = 1 ] && ok || bad "T6 $sid" "текст о запуске засчитан прогоном теста: $(printf '%s' "$cmd" | head -1)"
done
RUNQ='timeout 60 bash "/Users/x/My Project/hooks/tests/test_q.sh" 2>&1 | tail -3'
for i in 1 2 3 4; do callj s6d "$RUNQ" >/dev/null; done
if said "$(callj s6d "$RUNQ")"; then ok; SPOKE=$((SPOKE + 1)); else
    bad T6d "запуск через обёртку и по пути с пробелом не назван прогоном — предмет серии потерян"; fi

# --- T6e, T6f (скептик D1330, L1): цикл по тестам и `bash -c` внутри чужой программы — настоящие прогоны.
LOOP='for t in hooks/tests/test_a.sh hooks/tests/test_b.sh; do bash "$t"; done'
for i in 1 2 3 4; do callj s6l "$LOOP" >/dev/null; done
if said "$(callj s6l "$LOOP")"; then ok; SPOKE=$((SPOKE + 1)); else bad T6e "пятый прогон цикла по тестам не назван — предмет серии потерян"; fi
DOCK="docker run img bash -c 'bash hooks/tests/test_d.sh'"
for i in 1 2 3 4; do callj s6k "$DOCK" >/dev/null; done
if said "$(callj s6k "$DOCK")"; then ok; SPOKE=$((SPOKE + 1)); else bad T6f "пятый прогон через docker … bash -c не назван — предмет серии потерян"; fi

# --- T7 (D1330): отметка «сказано» лежит в состоянии серии, а не в журнале повода -----
# Строки `rework-fired-*` страж разбора считает поводами с правом на отказ, сборщик метрик — срабатываниями
# переработки; подсказка о серии туда не пишется. Серия s1 (T1) дошла до порога и говорила.
if ls "$TMP/state"/rework-fired-s1*.jsonl >/dev/null 2>&1; then
    bad T7a "серия прогонов записала повод в журнал переработки: $(head -1 "$TMP/state"/rework-fired-s1*.jsonl)"; else ok; fi
grep -q '"reruns":5' "$TMP/state/rework-rerun-told-s1.jsonl" 2>/dev/null && ok \
    || bad T7b "отметки «сказано» нет в состоянии серии: $(ls "$TMP/state" | grep s1 | tr '\n' ' ')"

# --- T5: ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ — страж вообще говорил --------------------------------
# Без него T2 и T3 зеленеют на вырезанном блоке: у них ожидаемый исход И ЕСТЬ молчание.
[ "$SPOKE" -ge 2 ] && ok || bad T5 "страж заговорил $SPOKE раз(а) — ноги молчания зеленеют от неработающего блока"

echo "rework rerun streak: $PASS passed, $FAIL failed (сказал $SPOKE раз)"
exit $(( FAIL != 0 ))
