#!/usr/bin/env bash
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
[ "$(count "$ST/disagreement-pending-*")" = "70" ] && ok || bad T3 "тронута ОЧЕРЕДЬ незакрытого долга"
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

echo "state prune: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
