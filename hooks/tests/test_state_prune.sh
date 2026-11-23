#!/usr/bin/env bash
# СУДИТ: scripts/state-prune.sh
# test_state_prune.sh — уборщик состояния убирает лишнее и НЕ убирает нужное (D252).
#
# Ловушка: «уборщик работает» легко получить, снеся всё. Поэтому у каждой проверки удаления
# рядом стоит проверка сохранения — окно замеров, очередь незакрытого долга, живая сессия.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/scripts/state-prune.sh"
[ -f "$S" ] || { echo "FAIL: нет $S"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
# Маска раскрывается ВНУТРИ функции через find, а не `ls "$1"`: в кавычках на месте вызова
# шаблон приходит литералом, ls его не находит и счёт всегда ноль — первая редакция теста
# так и краснела на всех проверках разом, хотя скрипт был исправен.
# `-type f` обязателен: при маске `*` find засчитывает и сам каталог, и проверка T8
# краснела на исправном уборщике (третий за сессию дефект харнесса, выдавший себя за дефект
# предмета).
count() { find "$(dirname "$1")" -maxdepth 1 -type f -name "$(basename "$1")" 2>/dev/null | wc -l | tr -d ' '; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ST="$TMP/state"; mkdir -p "$ST"

sid() { printf '%08x-1111-2222-3333-%012x' "$1" "$1"; }
# 70 файлов посессионного семейства без читателей через сессии — 10 обязаны уйти.
for i in $(seq 1 70); do : > "$ST/session-speaker_$(sid "$i")"; done
# 70 файлов ОЧЕРЕДИ незакрытого долга — не уходит ни один.
for i in $(seq 1 70); do : > "$ST/disagreement-pending-$(sid "$i").jsonl"; done
# 5 копий одной базы — сверх трёх свежих уходят только с явным флагом.
for i in 1 2 3 4 5; do : > "$ST/thing.jsonl.bak.10000$i"; done
# Файл без идентификатора сессии не рассматривается вовсе.
: > "$ST/injection-log.jsonl"

# Каталог реестра задаётся ЯВНО, а не через HOME: полный прогон (run_all.sh) экспортирует
# свой SR_SESSIONS_DIR-песочницу, и библиотека реестра берёт его прежде $HOME — в наборе
# записи фикстуры оказывались в другом каталоге, и T7/T7b/T9 краснели при исправном уборщике.
run() { STATE_DIR="$ST" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" bash "$S" "$@" 2>/dev/null; }

# T1: сухой прогон ничего не удаляет.
OUT=$(run)
[ "$(count "$ST/session-speaker_*")" = "70" ] && ok || bad T1 "сухой прогон удалил"
grep -q "сухой прогон" <<< "$OUT" && ok || bad T1b "не назван сухим: $OUT"

# T2-T4: применение убирает лишнее и щадит нужное.
run --apply >/dev/null
[ "$(count "$ST/session-speaker_*")" = "60" ] && ok || bad T2 "окно хранения не соблюдено: $(count "$ST/session-speaker_*")"
# Рамка: HOME песочницы, библиотеки архива «в установке» нет — хранимые не трогаются вовсе (D1008, T15 — рамка с ней).
[ "$(count "$ST/disagreement-pending-*")" = "70" ] && ok || bad T3 "без библиотеки архива тронута ОЧЕРЕДЬ незакрытого долга"
[ -f "$ST/injection-log.jsonl" ] && ok || bad T4 "удалён файл без идентификатора сессии"

# T5: копии без явного флага целы.
[ "$(count "$ST/thing.jsonl.bak.*")" = "5" ] && ok || bad T5 "копии удалены без --include-backups"

# T6: с флагом — сверх трёх свежих уходят.
run --apply --include-backups >/dev/null
[ "$(count "$ST/thing.jsonl.bak.*")" = "3" ] && ok || bad T6 "копий осталось $(count "$ST/thing.jsonl.bak.*"), ждали 3"

# T7: живая сессия не трогается, даже если её файл за окном.
# Имя записи — ПРОДОВОЕ, `<sid>.json` (hooks/session-registry-lib.sh:86): до 2 сентября 2026
# фикстура клала `<sid>` без расширения, и тест был зелёным на форме, которой в мире нет, —
# а регулярка защиты строилась из имён КАК ЕСТЬ и потому не совпадала ни с одним файлом
# состояния без точки после sid (`session-speaker_<sid>`, `knowledge-capture-<sid>` и др.).
# Живость — свежая метка `live/<sid>.json`, как её кладёт `_sr_mark_live` (D298, D337):
# запись `active/` без метки живой сессией не считается — это T9.
mkdir -p "$TMP/.claude/sessions/active" "$TMP/.claude/sessions/live"
LIVE=$(sid 1)
: > "$ST/session-speaker_$LIVE"
: > "$TMP/.claude/sessions/active/$LIVE.json"
: > "$TMP/.claude/sessions/live/$LIVE.json"
for i in $(seq 100 180); do : > "$ST/session-speaker_$(sid "$i")"; done
run --apply >/dev/null
[ -f "$ST/session-speaker_$LIVE" ] && ok || bad T7 "удалён файл ЖИВОЙ сессии"

# T7b: ВСЕ обречённые файлы принадлежат живым сессиям — фильтр обязан отработать и тогда.
# `grep -vE … > f && mv f "$FILES"` рвался на пустом выводе (grep возвращает 1), и список
# оставался НЕОТФИЛЬТРОВАННЫМ ровно в том случае, ради которого фильтр написан.
rm -f "$ST"/session-speaker_* "$TMP/.claude/sessions/active/"* "$TMP/.claude/sessions/live/"*
LIVE2=$(sid 2)
# Только метка, без накопителя: так выглядит параллельная сессия после первого Stop
# (finalize унёс `active/<sid>.json` в реестр) — по одному `active/` она не защищалась (D337).
: > "$TMP/.claude/sessions/live/$LIVE2.json"
# Ровно KEEP свежих файлов мёртвых сессий + ОДИН самый старый, принадлежащий живой:
# обречённый ровно один, и он же единственный, кого фильтр обязан вычеркнуть. Тогда вывод
# grep пуст — тот самый случай, в котором рвалась связка `&&`.
for i in $(seq 200 259); do : > "$ST/rework-$(sid "$i")"; done
OLDEST="$ST/rework-$LIVE2"
: > "$OLDEST"
touch -t 200001010000 "$OLDEST"
run --apply >/dev/null
[ -f "$OLDEST" ] && ok || bad T7b "удалён файл живой сессии, когда обречёнными были только её файлы"

# T8 (1 сентября 2026): замороженные снимки среды для ablation НЕ трогаются. Уборщик не
# заглядывает в поддеревья, и это решение, а не случайность: копия внутри снимка есть часть
# плеча эксперимента. Проверка держит именно поддерево, а не имя каталога.
# Копий одной базы нужно БОЛЬШЕ трёх: правило режет только сверх трёх, и с одной копией
# проверка проходила бы при любом обходе — мутация «убрать -maxdepth 1» её не красила.
FROZEN="$ST/ablation/frozen-runtime-phase-1/hooks/state"
mkdir -p "$FROZEN"
for i in 1 2 3 4 5; do : > "$FROZEN/thing.jsonl.bak.20000$i"; done
: > "$FROZEN/session-speaker_$(sid 900)"
run --apply --include-backups >/dev/null
[ "$(count "$FROZEN/*")" = "6" ] && ok \
  || bad T8 "тронут замороженный снимок ablation: осталось $(count "$FROZEN/*") из 6"

# T9 (12 сентября 2026, D337): живость — признак процесса, а не наличие записи. Запись
# UUID-сессии с устаревшей меткой `live/` и запись с PID мёртвого процесса — «запись без
# процесса»: обе названы числом, их файлы защиты не получают; PID живого процесса среди
# названных нет. Мёртвый PID берётся у оболочки, которая уже вышла, живой — у самого теста.
rm -f "$ST"/rework-* "$TMP/.claude/sessions/active/"* "$TMP/.claude/sessions/live/"*
GHOST=$(sid 3); DEAD=$(sh -c 'echo $$'); ALIVE=$$
: > "$TMP/.claude/sessions/active/$GHOST.json"
: > "$TMP/.claude/sessions/live/$GHOST.json"
touch -t 200001010000 "$TMP/.claude/sessions/live/$GHOST.json"
: > "$TMP/.claude/sessions/active/$DEAD.json"
: > "$TMP/.claude/sessions/active/$ALIVE.json"
for i in $(seq 300 359); do : > "$ST/rework-$(sid "$i")"; done
: > "$ST/rework-$GHOST"; touch -t 200001010000 "$ST/rework-$GHOST"
OUT=$(run --apply)
ORPH=$(grep 'запись без процесса' <<< "$OUT")
grep -q -- "— 2 (" <<< "$ORPH" && grep -q "$GHOST" <<< "$ORPH" && grep -q " $DEAD[ )]" <<< "$ORPH" \
  && ok || bad T9 "записи без процесса не названы: ${ORPH:-<строки нет>}"
grep -q " $ALIVE[ )]" <<< "$ORPH" && bad T9b "живой процесс $ALIVE назван записью без процесса" || ok
[ ! -f "$ST/rework-$GHOST" ] && ok || bad T9c "файл записи без процесса защищён как живой"

# T10 (D1006, 19 октября 2026): мёртвое семейство прежней редакции диспетчера уходит целиком,
# хотя файлов в нём меньше окна; живое семейство той же длины (с хвостом корня) не тронуто.
rm -f "$ST"/rework-* "$TMP/.claude/sessions/active/"* "$TMP/.claude/sessions/live/"*
for i in 400 401 402; do
    : > "$ST/bash-dispatch-queue-$(sid "$i")"; : > "$ST/bash-dispatch-mark-$(sid "$i")"
    : > "$ST/bash-dispatch-done-$(sid "$i")-123456-abc"
    : > "$ST/bash-dispatch-queue-$(sid "$i")-987654321"
done
run --apply >/dev/null
[ "$(count "$ST/bash-dispatch-queue-*")" = "3" ] && [ "$(count "$ST/bash-dispatch-mark-*")" = "0" ] \
    && [ "$(count "$ST/bash-dispatch-done-*")" = "0" ] && ok \
    || bad T10 "мёртвые семейства диспетчера не сняты либо снята живая очередь: queue $(count "$ST/bash-dispatch-queue-*") (ждали 3 живых), mark $(count "$ST/bash-dispatch-mark-*"), done $(count "$ST/bash-dispatch-done-*")"
[ "$(find "$ST" -maxdepth 1 -name 'bash-dispatch-queue-*-987654321' | wc -l | tr -d ' ')" = "3" ] && ok \
    || bad T10b "тронута живая очередь с хвостом корня"

# T11 (D1006): файл сессии в тишине уходит из основы, где сессия вне KEEP последних, — кроме
# хранимых семейств. Тишина — ни один файл сессии не моложе STATE_PRUNE_IDLE_DAYS (14). У 61 сессии
# флаги с ключом после идентификатора (`module-ctx-<sid>-<ключ>.flag`) — каждый ключ своё семейство из
# одного файла, окно файлов их не берёт никогда; время в БУДУЩЕМ, чтобы ранг старых был больше окна
# при любом порядке равных по времени файлов.
rm -f "$ST"/bash-dispatch-*
for i in $(seq 1 61); do
    s=$(sid "$((600 + i))")
    for f in "module-ctx-$s-k$i.flag" "own-frame-notice-$s-$i"; do : > "$ST/$f"; touch -t 203001010000 "$ST/$f"; done
done
OLD=$(sid 700); MIX=$(sid 701); BGO=$(sid 702)
for f in "module-ctx-$OLD-k0.flag" "own-frame-notice-$OLD-77" "outcome-$OLD.jsonl" \
         "module-ctx-$MIX-k9.flag" "module-ctx-$BGO-k5.flag"; do
    : > "$ST/$f"; touch -t 202001010000 "$ST/$f"
done
: > "$ST/startup-signals-$MIX.txt"          # возобновление обновляет свой файл сессии
: > "$ST/disagreement-pending-$BGO.jsonl"   # фоновая допись за чужую сессию
run --apply >/dev/null
[ ! -f "$ST/module-ctx-$OLD-k0.flag" ] && [ ! -f "$ST/own-frame-notice-$OLD-77" ] && ok \
    || bad T11 "файлы сессии в тишине за окном своей основы не сняты"
[ -f "$ST/outcome-$OLD.jsonl" ] && ok || bad T11b "у сессии в тишине снят файл хранимого семейства"
[ -f "$ST/module-ctx-$MIX-k9.flag" ] && ok \
    || bad T11c "снят однажды записанный файл возобновлённой сессии: свежесть взята у семейства, а не у сессии"
[ ! -f "$ST/module-ctx-$BGO-k5.flag" ] && ok || bad T11d "фоновая допись disagreement-pending сочтена жизнью сессии"
[ "$(count "$ST/own-frame-notice-*")" = "61" ] && ok \
    || bad T11e "тронуты свежие сессии: own-frame-notice $(count "$ST/own-frame-notice-*") из 61"

# T12 (финальный скептик, 20 октября 2026): ранг — ВНУТРИ ОСНОВЫ, а не по каталогу. Журнал, который
# пишется не в каждой сессии, обязан сохранить свои KEEP последних сессий, сколько бы более свежих сессий
# ни было у каталога: 40 молчащих сессий `doc-state` при 61 свежей сессии в других основах. С рангом по
# каталогу 19 октября так ушло 49 из 58 `doc-state` и 89 `correction-fired` — окна читателей опустели.
rm -f "$ST"/module-ctx-* "$ST"/own-frame-notice-* "$ST"/*"$OLD"* "$ST"/*"$MIX"* "$ST"/*"$BGO"*
for i in $(seq 1 61); do f="$ST/t12n$i-$(sid "$((700 + i))")"; : > "$f"; touch -t 203001010000 "$f"; done
for i in $(seq 1 40); do f="$ST/doc-state-$(sid "$((800 + i))").jsonl"; : > "$f"; touch -t 202001010000 "$f"; done
run --apply >/dev/null
[ "$(count "$ST/doc-state-*")" = "40" ] && ok \
    || bad T12 "редкое семейство потеряло глубину: doc-state $(count "$ST/doc-state-*") из 40 — ранг взят по каталогу"
# T12b: пока сессий в основе не больше окна, тишина не снимает ничего.
rm -f "$ST"/t12n* "$ST"/doc-state-*
for i in 1 2 3; do f="$ST/t12-$(sid "$((850 + i))")"; : > "$f"; touch -t 202001010000 "$f"; done
run --apply >/dev/null
[ "$(count "$ST/t12-*")" = "3" ] && ok || bad T12b "снята сессия внутри окна последних: осталось $(count "$ST/t12-*") из 3"

# T17 (второй круг финального скептика, 20 октября 2026): группа ранга — основа ВМЕСТЕ с постоянным хвостом.
# Основу `semantic-prefetch-` в живом каталоге делят `.json` и `.json.prompt`. С рангом по одной основе 60 свежих
# сессий частого семейства вытесняли за окно все 50 сессий редкого, и те уходили «в тишине», не наполнив своего окна.
for i in $(seq 1 60); do f="$ST/t17-$(sid "$((1100 + i))").json"; : > "$f"; touch -t 203001010000 "$f"; done
for i in $(seq 1 50); do f="$ST/t17-$(sid "$((1200 + i))").json.prompt"; : > "$f"; touch -t 202001010000 "$f"; done
run --apply >/dev/null
[ "$(count "$ST/t17-*.json.prompt")" = "50" ] && [ "$(count "$ST/t17-*.json")" = "60" ] && ok \
    || bad T17 "семейства с общей основой делят ранг: .json.prompt $(count "$ST/t17-*.json.prompt") из 50, .json $(count "$ST/t17-*.json") из 60"
rm -f "$ST"/t17-*

# T15 (финальный скептик): каталог состояния — ССЫЛКА. find без -H в стартовую ссылку не входил,
# список свежих выходил пустым, и свежие сессии за окном основы уходили как «в тишине».
rm -f "$ST"/t12-*
for i in $(seq 1 70); do : > "$ST/t15-$(sid "$((900 + i))")-k$i"; done
ln -s "$ST" "$TMP/state-link"
STATE_DIR="$TMP/state-link" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" bash "$S" --apply >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_state_prune.sh:$LINENO" >&2; exit 1; }
[ "$(count "$ST/t15-*")" = "70" ] && ok || bad T15 "через ссылку снято свежее: осталось $(count "$ST/t15-*") из 70"

# T16 (финальный скептик): ручка дней тишины не число — уборка отказывается, а не сносит свежее.
for v in abc 2w 0; do
    OUT16=$(STATE_DIR="$ST" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_IDLE_DAYS="$v" bash "$S" --apply 2>&1); RC16=$?
    [ "$RC16" = "2" ] && [ "$(count "$ST/t15-*")" = "70" ] && ok \
        || bad T16 "STATE_PRUNE_IDLE_DAYS=$v: код $RC16, осталось $(count "$ST/t15-*") из 70: ${OUT16:0:120}"
done

# T18 (второй круг финального скептика): ВСЕ ручки — целые числа от своего минимума, иначе отказ. «00» проходил
# литеральный страж «0» и давал find «моложе 0 дней» — все сессии «в тишине»; «1x» awk сравнивал строкой и снимал
# 59 из 70; нечисловой BAK_KEEP давал `tail -n +1`, и с --include-backups уходили ВСЕ копии.
for i in $(seq 1 70); do : > "$ST/t18-$(sid "$((1300 + i))").jsonl"; done
for kv in STATE_PRUNE_IDLE_DAYS=00 STATE_PRUNE_KEEP=1x STATE_PRUNE_KEEP=0 STATE_PRUNE_BAK_KEEP=abc \
          STATE_PRUNE_KEEP=18446744073709551617 STATE_PRUNE_BAK_KEEP=18446744073709551616; do
    OUT18=$(env "$kv" STATE_DIR="$ST" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" bash "$S" --apply --include-backups 2>&1); RC18=$?
    [ "$RC18" = "2" ] && [ "$(count "$ST/t18-*")" = "70" ] && [ "$(count "$ST/thing.jsonl.bak.*")" = "3" ] && ok \
        || bad T18 "$kv: код $RC18, t18 $(count "$ST/t18-*") из 70, копий $(count "$ST/thing.jsonl.bak.*") из 3: ${OUT18:0:120}"
done
# T18b: нули в начале — то же число, а не восьмеричная ошибка (`10#`).
OUT18=$(STATE_DIR="$ST" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_IDLE_DAYS=08 bash "$S" 2>&1); RC18=$?
[ "$RC18" != "2" ] && grep -q 'дольше 8 дн\.' <<< "$OUT18" && ok || bad T18b "STATE_PRUNE_IDLE_DAYS=08: код $RC18: ${OUT18:0:160}"
rm -f "$ST"/t18-*

# T13: журнал срабатываний считает окно СЕССИЯМИ — его читатель signal-precision.sh берёт 40 сессий, а
# у сессии с субагентами журналов три. 61 сессия × 3 журнала: уходит ровно самая старая сессия; при счёте
# файлами осталось бы 60 файлов — 20 сессий. Время в будущем: все свежие, тишина не вмешивается.
rm -f "$ST"/t12-*
for i in $(seq 1 61); do
    t="20300101$(printf '%02d%02d' $((i / 60)) $((i % 60)))"
    for a in "" ".agent-a1" ".agent-a2"; do
        f="$ST/rework-fired-$(sid "$((900 + i))")$a.jsonl"; : > "$f"; touch -t "$t" "$f"
    done
done
run --apply >/dev/null
[ "$(count "$ST/rework-fired-*")" = "180" ] && [ ! -f "$ST/rework-fired-$(sid 901).jsonl" ] && ok \
    || bad T13 "журнал срабатываний подрезан не по сессиям: осталось $(count "$ST/rework-fired-*") из 183, ждали 180"

# T14: девять семейств вышли из хранимых и подрезаются окном; хранимое по праву не тронуто.
rm -f "$ST"/rework-fired-*
for i in $(seq 1 70); do
    : > "$ST/question-open-$(sid "$((1000 + i))").jsonl"; : > "$ST/outcome-$(sid "$((1000 + i))").jsonl"
done
run --apply >/dev/null
[ "$(count "$ST/question-open-*")" = "60" ] && ok \
    || bad T14 "вышедшее из хранимых семейство не подрезано окном: $(count "$ST/question-open-*") из 70"
[ "$(count "$ST/outcome-*")" = "70" ] && ok || bad T14b "без библиотеки архива тронуто хранимое: outcome $(count "$ST/outcome-*") из 70"

# T15 (D1008): с библиотекой архива хранимые за окном уходят в архив семейства — живых сессий 60, а строк не меньше:
# архив и живые файлы вместе несут все 70. Без строк пустой файл архиву ничего не даёт, поэтому у фикстуры строки есть.
ST2="$TMP/state2"; mkdir -p "$ST2"
for i in $(seq 1 70); do
    printf '{"key":"k%s","outcome":"pending"}\n' "$i" > "$ST2/disagreement-pending-$(sid "$((2000 + i))").jsonl"
    printf '{"key":"%s","signal":"rework","outcome":"deferred"}\n' "$i" > "$ST2/outcome-$(sid "$((2000 + i))").jsonl"
done
SA_REPO="$REPO/hooks/lib/state_archive.py"
STATE_DIR="$ST2" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_SA_LIB="$SA_REPO" \
    bash "$S" --apply >/dev/null 2>&1; _rc=$?; [ "$_rc" -le 1 ] || { echo "подготовка мира не удалась (код $_rc; 1 у чистки законен — было что подрезать): hooks/tests/test_state_prune.sh:258" >&2; exit 1; }
for fam in disagreement-pending outcome; do
    [ "$(count "$ST2/$fam-*")" = "60" ] && ok || bad T15 "$fam: живых не 60, а $(count "$ST2/$fam-*")"
    n=$(python3 "$SA_REPO" lines "$ST2" "$fam" | wc -l | tr -d ' ')
    [ "$n" = "70" ] && ok || bad T15 "$fam: строк архива и живых файлов $n из 70"
done
# T15b — одни кандидаты в архив (удалять нечего): сухой прогон их называет и выходит кодом 1, а живая сессия за окном
# в архив не уходит (скептик D1008, L3: фильтр живых у списка архива и перенос в коде возврата не держались).
ST3="$TMP/state3"; mkdir -p "$ST3" "$TMP/.claude/sessions/active" "$TMP/.claude/sessions/live"
for i in $(seq 1 70); do
    printf '{"key":"%s","signal":"rework","outcome":"deferred"}\n' "$i" > "$ST3/outcome-$(sid "$((3000 + i))").jsonl"
done
LIVE3=$(sid 3001)   # самая старая сессия — за окном
: > "$TMP/.claude/sessions/active/$LIVE3.json"; : > "$TMP/.claude/sessions/live/$LIVE3.json"
STATE_DIR="$ST3" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_SA_LIB="$SA_REPO" \
    bash "$S" >/dev/null 2>&1; rc3=$?
[ "$rc3" = 1 ] && ok || bad T15b "сухой прогон с одними кандидатами в архив вышел кодом $rc3, а не 1"
STATE_DIR="$ST3" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_SA_LIB="$SA_REPO" \
    bash "$S" --apply >/dev/null 2>&1; _rc=$?; [ "$_rc" -le 1 ] || { echo "подготовка мира не удалась (код $_rc; 1 у чистки законен — было что подрезать): hooks/tests/test_state_prune.sh:276" >&2; exit 1; }
[ -f "$ST3/outcome-$LIVE3.jsonl" ] && ok || bad T15b "файл ЖИВОЙ сессии ушёл в архив"
rm -f "$TMP/.claude/sessions/active/$LIVE3.json" "$TMP/.claude/sessions/live/$LIVE3.json"
# T15c — готовность: библиотека без читателей архива рядом — хранимые не трогаются (скептик D1008, M2).
ST4="$TMP/state4"; mkdir -p "$ST4" "$TMP/fakehooks/lib"
cp "$SA_REPO" "$TMP/fakehooks/lib/"
for i in $(seq 1 70); do : > "$ST4/outcome-$(sid "$((4000 + i))").jsonl"; done
STATE_DIR="$ST4" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_SA_LIB="$TMP/fakehooks/lib/state_archive.py" \
    bash "$S" --apply >/dev/null 2>&1; _rc=$?; [ "$_rc" -le 1 ] || { echo "подготовка мира не удалась (код $_rc; 1 у чистки законен — было что подрезать): hooks/tests/test_state_prune.sh:284" >&2; exit 1; }
[ "$(count "$ST4/outcome-*")" = "70" ] && ok || bad T15c "архив без читателей: outcome $(count "$ST4/outcome-*") из 70"
# Три читателя готовы, а сборщик архива не читает — готовности нет: каждое условие держит свою ногу (второй скептик).
cp "$REPO/hooks/disagreement-lib.sh" "$REPO/hooks/knowledge-counter-bump.sh" "$TMP/fakehooks/"
cp "$REPO/hooks/lib/open-findings-lib.sh" "$TMP/fakehooks/lib/"
printf '#!/usr/bin/env bash\n' > "$TMP/fakehooks/session-collector.sh"
STATE_DIR="$ST4" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_SA_LIB="$TMP/fakehooks/lib/state_archive.py" \
    bash "$S" --apply >/dev/null 2>&1; _rc=$?; [ "$_rc" -le 1 ] || { echo "подготовка мира не удалась (код $_rc; 1 у чистки законен — было что подрезать): hooks/tests/test_state_prune.sh:291" >&2; exit 1; }
[ "$(count "$ST4/outcome-*")" = "70" ] && ok || bad T15c "сборщик без архива, а хранимое тронуто: $(count "$ST4/outcome-*") из 70"
# Сборщик готов, а закрытие суждения архива не читает — тоже не готово.
cp "$REPO/hooks/session-collector.sh" "$TMP/fakehooks/"; printf '#!/usr/bin/env bash\n' > "$TMP/fakehooks/knowledge-counter-bump.sh"
STATE_DIR="$ST4" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_SA_LIB="$TMP/fakehooks/lib/state_archive.py" \
    bash "$S" --apply >/dev/null 2>&1; _rc=$?; [ "$_rc" -le 1 ] || { echo "подготовка мира не удалась (код $_rc; 1 у чистки законен — было что подрезать): hooks/tests/test_state_prune.sh:296" >&2; exit 1; }
[ "$(count "$ST4/outcome-*")" = "70" ] && ok || bad T15c "закрытие без архива, а хранимое тронуто: $(count "$ST4/outcome-*") из 70"
# T15d — имя чужой формы среди хранимых за окном (`five-whys-<sid>.jsonl`) не срывает перенос годных `.seen`.
ST5="$TMP/state5"; mkdir -p "$ST5"
# Чужих имён больше окна: иначе они в список архива не попадают вовсе, и нога ничего не судит.
for i in $(seq 1 70); do
    printf 'turn:%s|\n' "$i" > "$ST5/five-whys-$(sid "$((5000 + i))").seen"
    printf 'x\n' > "$ST5/five-whys-$(sid "$((5000 + i))").jsonl"
done
STATE_DIR="$ST5" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" STATE_PRUNE_SA_LIB="$SA_REPO" \
    bash "$S" --apply >/dev/null 2>&1; _rc=$?; [ "$_rc" -le 1 ] || { echo "подготовка мира не удалась (код $_rc; 1 у чистки законен — было что подрезать): hooks/tests/test_state_prune.sh:306" >&2; exit 1; }
[ "$(count "$ST5/five-whys-*.seen")" = "60" ] && ok || bad T15d "годные .seen не перенесены: живых $(count "$ST5/five-whys-*.seen") из 70"

# T16 (D1225): снимок стража разбора уходит у сессии, молчащей дольше трёх суток, а не по общему правилу тишины в 14
# дней (сессия молчит четверо суток — граница, а не запас: мутант со сроком пять дней краснеет); у сессии со свежим файлом — остаётся, даже если сам снимок старый (снимок общий для поводов сессии). Сироты копий
# гейта закрытия старше суток уходят (сирота 30 ч — мутант «старше двух суток» краснеет), свежие (гейт идёт сейчас) остаются.
ST6="$TMP/state6"; mkdir -p "$ST6"
OLD=$(sid 9001); NEW=$(sid 9002)
: > "$ST6/five-whys-$OLD.snap-111.blob"; : > "$ST6/five-whys-$OLD.seen"
: > "$ST6/five-whys-$NEW.snap-222.blob"; : > "$ST6/five-whys-$NEW.seen"
touch -t "$(date -v-4d +%Y%m%d%H%M 2>/dev/null || date -d '4 days ago' +%Y%m%d%H%M)" "$ST6/five-whys-$OLD.snap-111.blob" "$ST6/five-whys-$OLD.seen" "$ST6/five-whys-$NEW.snap-222.blob"
: > "$ST6/cg-stripped-arc-4242.md"; : > "$ST6/cg-stripped-4243.md"; : > "$ST6/cg-stripped-arc-4244.md"
touch -t "$(date -v-30H +%Y%m%d%H%M 2>/dev/null || date -d '30 hours ago' +%Y%m%d%H%M)" "$ST6/cg-stripped-arc-4242.md" "$ST6/cg-stripped-4243.md"
STATE_DIR="$ST6" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" bash "$S" --apply >/dev/null 2>&1 || true  # уборка отвечает 1, когда было что убрать, — штатный ответ: файлы проверяют строки ниже (D1261)
[ ! -e "$ST6/five-whys-$OLD.snap-111.blob" ] && ok || bad T16 "снимок сессии, молчащей четверо суток, остался"
[ -e "$ST6/five-whys-$NEW.snap-222.blob" ] && ok || bad T16b "снимок живой за трое суток сессии удалён (старый снимок свежей сессии)"
[ -e "$ST6/five-whys-$OLD.seen" ] && ok || bad T16c "журнал .seen ушёл вместе со снимком"
[ ! -e "$ST6/cg-stripped-arc-4242.md" ] && [ ! -e "$ST6/cg-stripped-4243.md" ] && ok || bad T16d "сирота копии гейта старше суток осталась"
[ -e "$ST6/cg-stripped-arc-4244.md" ] && ok || bad T16e "свежая копия идущего гейта удалена"

# T17 (D1274, D1300): ключи показанных файлов подсказки связей (`impact-inject-<sid>.keys`) уходят у сессии, молчащей
# дольше трёх суток (как снимок стража, T16), у свежей сессии остаются; посессионный флаг другой основы
# (`impact-inject-stale-<sid>`) этим правилом не берётся; прежний флаг по ключу файла (`…-<ключ>.flag`) уходит и у свежей
# сессии — читателя у этого формата нет с D1300.
ST7="$TMP/state7"; mkdir -p "$ST7"
OLD7=$(sid 9101); NEW7=$(sid 9102); KEY7=fedcba9876543210fedcba9876543210
: > "$ST7/impact-inject-$OLD7.keys"; : > "$ST7/impact-inject-stale-$OLD7.flag"
: > "$ST7/impact-inject-$NEW7.keys"; : > "$ST7/impact-inject-$NEW7-$KEY7.flag"; : > "$ST7/startup-signals-$NEW7.txt"
touch -t "$(date -v-4d +%Y%m%d%H%M 2>/dev/null || date -d '4 days ago' +%Y%m%d%H%M)" "$ST7/impact-inject-$OLD7.keys" \
    "$ST7/impact-inject-stale-$OLD7.flag" "$ST7/impact-inject-$NEW7.keys" "$ST7/impact-inject-$NEW7-$KEY7.flag"
STATE_PRUNE_II_HOOK="$REPO/hooks/impact-inject.sh" STATE_DIR="$ST7" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" bash "$S" --apply >/dev/null 2>&1 || true  # уборка отвечает 1, когда было что убрать, — штатный ответ: файлы проверяют строки ниже
[ ! -e "$ST7/impact-inject-$OLD7.keys" ] && ok || bad T17 "ключи подсказки сессии, молчащей четверо суток, остались"
[ -e "$ST7/impact-inject-$NEW7.keys" ] && ok || bad T17b "ключи подсказки свежей сессии удалены"
[ -e "$ST7/impact-inject-stale-$OLD7.flag" ] && ok || bad T17c "флаг другой основы ушёл по правилу флагов подсказки"
[ ! -e "$ST7/impact-inject-$NEW7-$KEY7.flag" ] && ok || bad T17d "прежний флаг по ключу у свежей сессии остался — читателя у формата нет (D1300)"
# T17e (D1300, скептик H1): установленный хук ещё прежний (ключей строками не пишет) — флаг по ключу свежей сессии
# живой, его читает установленная копия, и уборка из репозитория его не трогает.
ST7E="$TMP/state7e"; mkdir -p "$ST7E"; printf '#!/usr/bin/env bash\n# прежняя редакция без ключей\n' > "$TMP/old-impact-inject.sh"
: > "$ST7E/impact-inject-$NEW7-$KEY7.flag"; : > "$ST7E/startup-signals-$NEW7.txt"
STATE_PRUNE_II_HOOK="$TMP/old-impact-inject.sh" STATE_DIR="$ST7E" HOME="$TMP" SR_SESSIONS_DIR="$TMP/.claude/sessions" bash "$S" --apply >/dev/null 2>&1 || true
[ -e "$ST7E/impact-inject-$NEW7-$KEY7.flag" ] && ok || bad T17e "флаг по ключу свежей сессии снят при прежней установке — живой дедуп потерян"

echo "state prune: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
