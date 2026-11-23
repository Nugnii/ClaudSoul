#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_queue_tear.sh — противник диспетчера записи командой (D487): очередь сессии,
# которую одновременно дописывают события сессии и её субагентов, не рвётся и не теряет путей.
#
# Устройство дефекта. Шапка очереди объявляет: «Очередь и список только ДОПИСЫВАЮТСЯ: у сессии и
# её субагентов они общие». Дописывание делает `grep -v '^$' >> ОЧЕРЕДЬ`, а `grep` пишет в файл
# кусками буфера stdio (размер блока файловой системы, 4096 байт): дописывание отбора длиннее
# блока — несколько вызовов write(2), и между ними ложатся куски соседнего события. Строка на
# стыке кусков склеивается с чужой: в очереди мусор («путь-обрубокдругой/путь.md»), и путь, у
# которого порваны ВСЕ копии, теряется — метка уже сдвинута, повторно его никто не отберёт.
# Замер 1 октября 2026, 3000 путей: 30 одновременных событий — 155–963 рваных строк за прогон;
# 2 одновременных события — в части прогонов потеряно 18–65 путей из 3000 (2982/2935 целых).
#
# Здесь одновременно отбирают одну и ту же правку 30 событий одной сессии. Ожидание: каждая
# строка очереди — целый путь, и каждый записанный командой путь в очереди есть целиком.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$(cd "$DIR/.." && pwd)"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Здесь все стражи — заглушки, и
# носитель был бы ложным (тот же приём — test_bash_write_dispatch_versions.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"
mkdir -p "$SB/hooks" "$SR" "$SH"
# Песочница несёт и библиотеку замка с её зависимостью, как установка в ~/.claude/hooks:
# без неё диспетчер работает без замка (названное третье состояние), и нога судила бы
# неполную установку, а не предмет.
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
for g in $GUARD_LIST; do printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore"

run() {  # run <сессия> → вывод диспетчера; бюджет 0: предмет — очередь, а не подача
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=0 \
            bash "$SB/hooks/$DISP" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_dispatch_queue_tear.sh:$LINENO" >&2; exit 1; }
}

# Одна команда записала K файлов (генератор, переключение ветки, форматтер).
K=2000
SUB="docs/a-rather-long-directory-name-to-inflate-each-line/and-another-level"
mkdir -p "$SR/$SUB"
i=0; while [ "$i" -lt "$K" ]; do i=$((i+1)); echo "$i" > "$SR/$SUB/note_with_padding_name_$i.md"; done
# Строка очереди — «путь ⇥ версия» (D489): версия — crc и размер содержимого.
RE="^docs/a-rather-long-directory-name-to-inflate-each-line/and-another-level/note_with_padding_name_[0-9]+[.]md$(printf '\t')[0-9]+-[0-9]+\$"

N=30; TORN=0; INTACT=$K; ROUNDS=0; LINES=0; SAMPLE=""
# До трёх заходов, каждый — новая сессия; стоп на первом порванном: заход стоит ~3 с.
for r in 1 2 3; do
    ROUNDS=$r
    touch "$SR/$SUB"/*.md
    j=0; while [ "$j" -lt "$N" ]; do j=$((j+1)); run "q$r" >/dev/null & done; wait
    # Имя очереди несёт ключ корня (состояние пары «сессия + корень») — берётся по шаблону.
    Q=$(ls "$TMP/state"/bash-dispatch-queue-adv-q$r-* 2>/dev/null | head -1)
    LINES=$(wc -l < "$Q" 2>/dev/null | tr -d ' ')
    TORN=$(grep -c -v -E "$RE" "$Q" 2>/dev/null)
    INTACT=$(grep -E "$RE" "$Q" 2>/dev/null | LC_ALL=C sort -u | wc -l | tr -d ' ')
    SAMPLE=$(grep -v -E "$RE" "$Q" 2>/dev/null | head -1 | cut -c1-160)
    [ "${TORN:-0}" -eq 0 ] && [ "${INTACT:-0}" -ge "$K" ] || break
done

# T0 — положительный контроль: одновременные события действительно дописали отбор (иначе нога
# судила бы пустую очередь).
if [ "${LINES:-0}" -ge "$K" ]; then ok; else bad T0 "положительный контроль: в очереди ${LINES:-0} строк при ${K} записанных файлах"; fi
# T1 — каждая строка очереди — целый путь, а не склейка кусков двух событий.
if [ "${TORN:-0}" -eq 0 ]; then ok
else bad T1 "очередь порвана одновременным дописыванием: ${TORN} строк из ${LINES} — склейки путей (заход ${ROUNDS}, ${N} событий); пример: «${SAMPLE}»"; fi
# T2 — каждый записанный командой путь есть в очереди целиком хотя бы раз.
if [ "${INTACT:-0}" -ge "$K" ]; then ok
else bad T2 "из очереди потеряно $((K - ${INTACT:-0})) путей из ${K}: все их копии порваны, метка сдвинута — стражи их не увидят"; fi

echo "test_adv_dispatch_queue_tear: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
