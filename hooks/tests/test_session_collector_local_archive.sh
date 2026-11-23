#!/usr/bin/env bash
# СУДИТ: hooks/session-collector.sh
# test_session_collector_local_archive.sh — уборка закрытых пунктов в бэклоге проекта (D512).
#
# Повод (4 октября 2026, слово владельца, сессия ProjectA): «странно что архиватор работает в
# ручном режиме, в клаудсоул он автоматический». Проект вёл бэклог по контракту ClaudSoul и
# включил гейт признаком `CG_LOCAL_BACKLOG`: «Проверки» его пунктов исполнялись на каждом
# Stop, а закрытые пункты копились — 37 закрытых против 56 открытых — до ручной команды.
#
# Признак согласия один, и он же граница доверия: архиватор ИСПОЛНЯЕТ команду «Проверки»
# закрытого пункта, поэтому убирается только файл, названный владельцем в `CG_LOCAL_BACKLOG`,
# а не найденный по папке сессии (D244: путь из cwd — вход извне).
#
# Ноги: T1 — проект с признаком: закрытый пункт переехал, открытый остался, проект назван;
#       T2 — проект без признака: файл не изменён, архива нет (сессия идёт В ЭТОМ проекте);
#       T3 — признак указывает на главный бэклог: «Проверка» исполнена один раз, отказ один;
#       T4 — закрытый пункт с красной «Проверкой» не уезжает, отказ назван с проектом;
#       T5 — закрытые пункты в ОБОИХ бэклогах за один Stop: уезжают оба, сообщений два;
#       T6 — признак называет несуществующий файл: хук жив и молчит;
#       T7 — относительный путь в признаке не исполняется (он читался бы от папки сессии);
#       T8 — архиватор ответил неизвестным исходом: тревога названа с проектом;
#       T9 — отказ на сотни пунктов (вывод за 100 КБ) не убивает хук, сообщение доходит;
#       T10 — пункт проекта с номером ниже порога ClaudSoul (D12) и красной «Проверкой» остаётся;
#       T11 — тот же отказ на втором Stop той же сессии не повторяется, другой отказ звучит (D514);
#       T12 — счёт открытых пунктов берёт названный бэклог, а не найденный по папке сессии;
#       T13 — скрипт пересчёта показаний проекта исполняется только у названного бэклога,
#             в том числе когда признак назван для ДРУГОГО проекта (T13d);
#       T15 — у главного бэклога и бэклога проекта свои счётчики ходов пересчёта;
#       T16 — архиватор отложил перенос (бэклог изменился за время прогона «Проверок», D1000):
#             сборщик молчит, правка цела, следующий Stop переносит.
# Различение показано мутациями хука (4 октября 2026, скептик): без сравнения с главным
# бэклогом краснеет T3, затёртая очередь сообщений — T5c, снятая проверка файла — T6,
# подъём от папки сессии — T2, относительный путь — T7.

set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"
# Свидетеля зовёт «Проверка» пункта D512, то есть архиватор и гейт: в их окружении стоит ограда
# вложенного прогона, и архиватор внутри хука отвечал бы «Вложенный прогон», ничего не унося.
# Песочница кольца не даёт — команды её пунктов суть `true` и `false`; идиома соседей по ограде.
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-collector.sh"
ARCHIVER="$HOOKS_DIR/../scripts/backlog-archive.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
[ -f "$ARCHIVER" ] || { echo "FAIL: $ARCHIVER not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

_project() {   # <name> <check command> — проект с одним открытым и одним закрытым пунктом
    local dir="$TMP/$1" check="$2"
    mkdir -p "$dir"
    {
        printf '%s\n' '# BACKLOG' '' '## Раздел' ''
        printf '%s\n' '- ☐ **L1** открытый пункт проекта'
        printf '%s\n' '- ☑ **L2** закрытый пункт проекта' '  **Результат.** Есть.'
        printf '  **Проверка.** `%s`\n' "$check"
    } > "$dir/BACKLOG.md"
}

_stop() {   # <cwd> <main backlog> [CG_LOCAL_BACKLOG] — один Stop, очередь сообщений на выход
    # SID=<имя> — тот же идентификатор сессии и НЕсброшенный дроссель: второй ход той же сессии
    alerts_clear "$TMP/state"
    [ -n "${SID:-}" ] || rm -f "$TMP/state"/*session-persist* 2>/dev/null || true
    jq -cn --arg s "${SID:-la$RANDOM}" --arg c "$1" '{session_id:$s, cwd:$c}' \
        | STATE_DIR="$TMP/state" \
          CLAUDSOUL_BACKLOG="$2" \
          CLAUDSOUL_BACKLOG_ARCHIVER="${ARCH:-$ARCHIVER}" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" \
          CG_LOCAL_BACKLOG="${3:-}" \
          BACKLOG_READINGS_EVERY_TURNS="${EVERY:-20}" \
          bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: Stop-хук вернул не 0" >&2; exit 1; }
    alerts_of "$TMP/state"
}

# === T1: проект с признаком — закрытый пункт переехал ===
_project with 'true'
OUT=$(_stop "$TMP/with" "$TMP/none.md" "$TMP/with/BACKLOG.md")
if grep -q 'L2' "$TMP/with/BACKLOG.md"; then bad T1a "закрытый пункт остался в BACKLOG.md проекта"; else ok; fi
if grep -q 'L2' "$TMP/with/BACKLOG-archive.md" 2>/dev/null; then ok; else bad T1b "закрытого пункта нет в BACKLOG-archive.md проекта"; fi
if grep -q 'L1' "$TMP/with/BACKLOG.md"; then ok; else bad T1c "открытый пункт пропал из BACKLOG.md проекта"; fi
if grep -qF 'проекта with' <<< "$OUT" && grep -qF 'унесено' <<< "$OUT"; then ok
else bad T1d "перенос не назван с именем проекта: $(printf '%s' "$OUT" | head -c 200)"; fi

# === T2: проект без признака — хук его не трогает, хотя сессия идёт в нём ===
_project without 'true'
SUM_BEFORE=$(cksum < "$TMP/without/BACKLOG.md")
OUT=$(_stop "$TMP/without" "$TMP/none.md" "")
if [ "$(cksum < "$TMP/without/BACKLOG.md")" = "$SUM_BEFORE" ]; then ok; else bad T2a "BACKLOG.md проекта без признака изменён"; fi
if [ -e "$TMP/without/BACKLOG-archive.md" ]; then bad T2b "у проекта без признака появился архив"; else ok; fi

# === T3: признак указывает на главный бэклог — один проход ===
# «Проверка» красная и оставляет след: второй проход исполнил бы её ещё раз и дал второй отказ.
_project main "sh -c \"echo x >> $TMP/main.cnt; false\""
OUT=$(_stop "$TMP/main" "$TMP/main/BACKLOG.md" "$TMP/main/BACKLOG.md")
N=$(grep -c x "$TMP/main.cnt" 2>/dev/null || true)
if [ "${N}" = "1" ]; then ok; else bad T3a "«Проверка» исполнена ${N:-0} раз вместо 1"; fi
N=$(grep -oF 'ОТКАЗАЛСЯ' <<< "$OUT" | grep -c . || true)
if [ "${N}" = "1" ]; then ok; else bad T3b "сообщений об отказе: ${N} вместо 1"; fi
if grep -qF 'этого проекта (main)' <<< "$OUT"; then bad T3c "главный бэклог посчитан второй раз как бэклог проекта"; else ok; fi

# === T4: красная «Проверка» — пункт не уезжает, отказ назван с проектом ===
_project red 'false'
OUT=$(_stop "$TMP/red" "$TMP/none.md" "$TMP/red/BACKLOG.md")
if grep -q 'L2' "$TMP/red/BACKLOG.md"; then ok; else bad T4a "пункт с красной «Проверкой» уехал из BACKLOG.md"; fi
if grep -qF 'ОТКАЗАЛСЯ' <<< "$OUT" && grep -qF 'проекта red' <<< "$OUT"; then ok
else bad T4b "отказ не назван с именем проекта: $(printf '%s' "$OUT" | head -c 200)"; fi

# === T5: закрытые пункты и в главном бэклоге, и в бэклоге проекта — уезжают оба ===
_project both-main 'true'
_project both-local 'true'
OUT=$(_stop "$TMP/both-local" "$TMP/both-main/BACKLOG.md" "$TMP/both-local/BACKLOG.md")
if grep -q 'L2' "$TMP/both-main/BACKLOG-archive.md" 2>/dev/null; then ok; else bad T5a "главный бэклог не убран"; fi
if grep -q 'L2' "$TMP/both-local/BACKLOG-archive.md" 2>/dev/null; then ok; else bad T5b "бэклог проекта не убран после главного"; fi
N=$(grep -oF 'унесено' <<< "$OUT" | grep -c . || true)
if [ "${N}" = "2" ]; then ok; else bad T5c "сообщений о переносе: ${N} вместо 2 — одно затёрто другим"; fi

# === T6: признак называет файл, которого нет — хук жив и про архиватор молчит ===
OUT=$(_stop "$TMP/with" "$TMP/none.md" "$TMP/with/NOPE.md")
if grep -qF 'Архиватор' <<< "$OUT"; then bad T6 "несуществующий файл дал сообщение архиватора: $(printf '%s' "$OUT" | head -c 200)"; else ok; fi
if grep -qF 'файл, которого нет' <<< "$OUT"; then ok; else bad T6b "сломанный признак промолчал: $(printf '%s' "$OUT" | head -c 200)"; fi

# === T7: относительный путь в признаке — файл в папке сессии не трогается ===
_project rel 'true'
SUM_BEFORE=$(cksum < "$TMP/rel/BACKLOG.md")
OUT=$(cd "$TMP/rel" && _stop "$TMP/rel" "$TMP/none.md" "BACKLOG.md")
if [ "$(cksum < "$TMP/rel/BACKLOG.md")" = "$SUM_BEFORE" ]; then ok; else bad T7 "бэклог по относительному пути изменён"; fi
if grep -qF 'относительным путём' <<< "$OUT"; then ok; else bad T7b "относительный признак промолчал: $(printf '%s' "$OUT" | head -c 200)"; fi
OUT=$(cd "$TMP/rel" && SID=rel-sid _stop "$TMP/rel" "$TMP/none.md" "BACKLOG.md")
OUT=$(cd "$TMP/rel" && SID=rel-sid _stop "$TMP/rel" "$TMP/none.md" "BACKLOG.md")
if grep -qF 'относительным путём' <<< "$OUT"; then bad T7c "сломанный признак повторён на втором ходу той же сессии"; else ok; fi

# === T8: архиватор ответил неизвестным исходом — тревога названа с проектом ===
_project mute 'true'
printf '%s\n' '#!/usr/bin/env bash' 'echo "неизвестный исход"' > "$TMP/fake-archiver.sh"
OUT=$(ARCH="$TMP/fake-archiver.sh" _stop "$TMP/mute" "$TMP/none.md" "$TMP/mute/BACKLOG.md")
if grep -qF 'проекта mute НЕ ОТВЕТИЛ' <<< "$OUT"; then ok
else bad T8 "немой архиватор не назван с проектом: $(printf '%s' "$OUT" | head -c 200)"; fi

# === T9: отказ на сотни пунктов — хук жив (в _stop код проверяется), сообщение дошло ===
mkdir -p "$TMP/big"
{
    printf '%s\n' '# BACKLOG' '' '## Раздел' ''
    i=1
    while [ "$i" -le 1600 ]; do   # строка отказа ~90 байт на пункт; обрыв начинался за 100 КБ вывода
        printf -- '- ☑ **L%s** закрытый пункт без показания, длинный заголовок для объёма вывода архиватора %s\n' "$i" "$i"
        printf '  **Результат.** Есть, и описан достаточно длинно, чтобы строка отказа занимала место.\n'
        i=$((i + 1))
    done
} > "$TMP/big/BACKLOG.md"
OUT=$(_stop "$TMP/big" "$TMP/none.md" "$TMP/big/BACKLOG.md")
if grep -qF 'ОТКАЗАЛСЯ' <<< "$OUT" && grep -qF 'проекта big' <<< "$OUT"; then ok
else bad T9 "большой отказ не дошёл до очереди: $(printf '%s' "$OUT" | head -c 200)"; fi

# === T10: порог возраста пунктов ClaudSoul к бэклогу проекта не применяется ===
mkdir -p "$TMP/lowid"
printf '%s\n' '# BACKLOG' '' '## Раздел' '' '- ☑ **D12** закрытый пункт с номером ниже порога' \
    '  **Результат.** Есть.' '  **Проверка.** `false`' > "$TMP/lowid/BACKLOG.md"
OUT=$(_stop "$TMP/lowid" "$TMP/none.md" "$TMP/lowid/BACKLOG.md")
if grep -q 'D12' "$TMP/lowid/BACKLOG.md"; then ok; else bad T10 "пункт D12 с красной «Проверкой» уехал из бэклога проекта"; fi

# === T11: тот же отказ на втором ходу той же сессии молчит, другой отказ звучит ===
_project thr 'false'
OUT=$(SID=thr-sid _stop "$TMP/thr" "$TMP/none.md" "$TMP/thr/BACKLOG.md")
if grep -qF 'ОТКАЗАЛСЯ' <<< "$OUT"; then ok; else bad T11a "первый отказ не назван"; fi
OUT=$(SID=thr-sid _stop "$TMP/thr" "$TMP/none.md" "$TMP/thr/BACKLOG.md")
if grep -qF 'ОТКАЗАЛСЯ' <<< "$OUT"; then bad T11b "тот же отказ повторён на втором ходу той же сессии"; else ok; fi
printf '%s\n' '- ☑ **L0** ещё один закрытый пункт' '  **Результат.** Есть.' '  **Проверка.** `false`' > "$TMP/thr/head.md"
{ printf '%s\n' '# BACKLOG' '' '## Раздел' ''; cat "$TMP/thr/head.md"; sed -n '5,$p' "$TMP/thr/BACKLOG.md"; } > "$TMP/thr/new.md"
mv "$TMP/thr/new.md" "$TMP/thr/BACKLOG.md"; rm -f "$TMP/thr/head.md"
OUT=$(SID=thr-sid _stop "$TMP/thr" "$TMP/none.md" "$TMP/thr/BACKLOG.md")
if grep -qF 'ОТКАЗАЛСЯ' <<< "$OUT"; then ok; else bad T11c "другой отказ (новый первый пункт) не назван"; fi
printf '%s\n' '- ☑ **L9** закрытый пункт НИЖЕ уже отказанных' '  **Результат.** Есть.' '  **Проверка.** `false`' >> "$TMP/thr/BACKLOG.md"
OUT=$(SID=thr-sid _stop "$TMP/thr" "$TMP/none.md" "$TMP/thr/BACKLOG.md")
if grep -qF 'ОТКАЗАЛСЯ' <<< "$OUT"; then ok; else bad T11d "новый отказ, стоящий в файле ниже прежних, не назван"; fi

# === T12: сессия в подпапке со своим CLAUDE.md — счёт берёт названный бэклог ===
_project sub 'false'
mkdir -p "$TMP/sub/web"; : > "$TMP/sub/web/CLAUDE.md"
OUT=$(_stop "$TMP/sub/web" "$TMP/none.md" "$TMP/sub/BACKLOG.md")
if grep -qF 'этого проекта (sub)' <<< "$OUT"; then ok
else bad T12 "открытые пункты названного бэклога не посчитаны из подпапки: $(printf '%s' "$OUT" | head -c 200)"; fi
mkdir -p "$TMP/named"
printf '%s\n' '# DEBT' '' '- ☐ **N1** открытый пункт в файле с другим именем' > "$TMP/named/DEBT.md"
printf '%s\n' '# BACKLOG' '' '- ☐ **X1** раз' '- ☐ **X2** два' > "$TMP/named/BACKLOG.md"
OUT=$(_stop "$TMP/named" "$TMP/none.md" "$TMP/named/DEBT.md")
if grep -qF '1 открытых пункт' <<< "$OUT"; then ok
else bad T12b "счёт взят не из названного файла DEBT.md: $(printf '%s' "$OUT" | head -c 200)"; fi

# === T13: скрипт пересчёта показаний проекта — только у названного бэклога ===
_project rr 'true'
mkdir -p "$TMP/rr/.git" "$TMP/rr/scripts"
printf '%s\n' '#!/usr/bin/env bash' "echo x >> \"$TMP/rr.ran\"" > "$TMP/rr/scripts/backlog-refresh-readings.sh"
OUT=$(EVERY=1 _stop "$TMP/rr" "$TMP/none.md" "")
if [ -e "$TMP/rr.ran" ]; then bad T13a "скрипт проекта, найденного по папке сессии, исполнен"; else ok; fi
OUT=$(EVERY=1 _stop "$TMP/rr" "$TMP/none.md" "$TMP/rr/BACKLOG.md")
if [ -e "$TMP/rr.ran" ]; then ok; else bad T13b "скрипт названного проекта не исполнен — показания проекта не пересчитываются"; fi
rm -f "$TMP/rr.ran" "$TMP/state"/backlog-readings-turns*
OUT=$(EVERY=1 _stop "$TMP/rr" "$TMP/rr/BACKLOG.md" "$TMP/rr/BACKLOG.md")
N=$(grep -c x "$TMP/rr.ran" 2>/dev/null || true)
if [ "${N}" = "1" ]; then ok; else bad T13c "признак называет главный бэклог: пересчёт исполнен ${N:-0} раз вместо 1"; fi
rm -f "$TMP/rr.ran"
_project other 'true'
OUT=$(EVERY=1 _stop "$TMP/rr" "$TMP/none.md" "$TMP/other/BACKLOG.md")
if [ -e "$TMP/rr.ran" ]; then bad T13d "признак назван для другого проекта, а скрипт проекта сессии исполнен"; else ok; fi

# === T15: свой счётчик ходов у каждого бэклога — пересчёт главного не голодает ===
_project cmain 'true'; _project cproj 'true'
mkdir -p "$TMP/cmain/scripts" "$TMP/cproj/scripts"
printf '%s\n' '#!/usr/bin/env bash' "echo x >> \"$TMP/cmain.ran\"" > "$TMP/cmain/scripts/backlog-refresh-readings.sh"
printf '%s\n' '#!/usr/bin/env bash' "echo x >> \"$TMP/cproj.ran\"" > "$TMP/cproj/scripts/backlog-refresh-readings.sh"
rm -f "$TMP/state"/backlog-readings-turns*
OUT=$(EVERY=2 _stop "$TMP/cproj" "$TMP/cmain/BACKLOG.md" "$TMP/cproj/BACKLOG.md")
OUT=$(EVERY=2 _stop "$TMP/cproj" "$TMP/cmain/BACKLOG.md" "$TMP/cproj/BACKLOG.md")
if [ -e "$TMP/cmain.ran" ] && [ -e "$TMP/cproj.ran" ]; then ok
else bad T15 "за два хода при пороге 2 пересчитаны не оба бэклога (главный: $([ -e "$TMP/cmain.ran" ] && echo да || echo нет), проект: $([ -e "$TMP/cproj.ran" ] && echo да || echo нет))"; fi

# === T16: архиватор ОТЛОЖИЛ перенос — это законный самоустраняющийся исход, а не «НЕ ОТВЕТИЛ» (D1000) ===
# Сборщик идёт фоном, и бэклог правят, пока архиватор исполняет «Проверки» закрытых пунктов; тогда
# архиватор не пишет ничего и говорит «Перенос отложен» (код 1). Сборщик обязан молчать: исход
# опознан, постоянного состояния нет, следующий Stop перенесёт по свежему файлу. Опровержение —
# тревога «НЕ ОТВЕТИЛ ни одним известным исходом» на каждой такой границе. Правку во время прогона
# ведёт сама «Проверка» пункта (один раз, отметка `ran`); настоящий архиватор, не заглушка: текст
# строки берётся у производителя, а не из памяти теста.
mkdir -p "$TMP/race"
{
    printf '%s\n' '# BACKLOG' '' '## Раздел' ''
    printf '%s\n' '- ☑ **L5** закрытый пункт, чья «Проверка» дописывает пункт в бэклог' '  **Результат.** Есть.'
    printf '  **Проверка.** `%s`\n' "[ -e ran ] || { : > ran; printf '\\n- ☐ **L6** дописан во время прогона\\n' >> BACKLOG.md; }"
} > "$TMP/race/BACKLOG.md"
OUT=$(_stop "$TMP/race" "$TMP/none.md" "$TMP/race/BACKLOG.md")
if grep -qF 'НЕ ОТВЕТИЛ' <<< "$OUT"; then bad T16a "отложенный перенос принят за неопознанный исход: $(printf '%s' "$OUT" | head -c 200)"; else ok; fi
if grep -qF 'ОТКАЗАЛСЯ' <<< "$OUT"; then bad T16b "отложенный перенос назван отказом: $(printf '%s' "$OUT" | head -c 200)"; else ok; fi
# Дописанный пункт ищется ЗАГОЛОВКОМ В НАЧАЛЕ СТРОКИ: L6 стоит и в тексте «Проверки» L5, и подстрока
# находила бы его там даже после затирания.
if grep -qE '^- ☐ \*\*L6\*\* ' "$TMP/race/BACKLOG.md"; then ok; else bad T16c "правка, внесённая во время прогона, затёрта"; fi
if grep -q 'L5' "$TMP/race/BACKLOG.md" && [ ! -e "$TMP/race/BACKLOG-archive.md" ]; then ok
else bad T16d "при отложенном переносе пункт ушёл из бэклога или тронут архив"; fi
OUT=$(_stop "$TMP/race" "$TMP/none.md" "$TMP/race/BACKLOG.md")
if grep -q 'L5' "$TMP/race/BACKLOG-archive.md" 2>/dev/null && ! grep -q 'L5' "$TMP/race/BACKLOG.md"; then ok
else bad T16e "следующий Stop не перенёс пункт по свежему файлу"; fi
if grep -qE '^- ☐ \*\*L6\*\* ' "$TMP/race/BACKLOG.md" && grep -qF 'унесено' <<< "$OUT"; then ok
else bad T16f "после повтора правка потеряна либо перенос не назван: $(printf '%s' "$OUT" | head -c 200)"; fi

echo "session collector local archive: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
