#!/usr/bin/env bash
# state-prune.sh — состояние не растёт монотонно: файлы мёртвых сессий и лишние копии.
# Результат: нет посессионных файлов старше окна замеров; копии сверх трёх свежих на базу
#            названы и ждут решения владельца (без --include-backups не трогаются)
# Проверка результата: bash scripts/state-prune.sh | grep -q 'за окном хранения ([0-9]* на семейство): 0,'
#
# Повод (D252). Замер 1 сентября 2026: 2559 файлов и 36 МБ при порогах 3000 / 40 МБ — 85% и
# 90%. Темп с 15 апреля около 18 файлов в день, то есть порог берётся примерно через месяц,
# и замер краснеет без того, кто его чинит. Инструмент, который только называет число, —
# не инструмент: результат есть состояние мира, а не работа прибора.
#
# ЧТО МОЖНО УБИРАТЬ, А ЧТО НЕЛЬЗЯ — разделитель назван и проверен, а не угадан.
#
# 1. Окно замеров. Самое длинное окно в СЕССИЯХ — 40 (`dead-sensor-check.sh:25`,
#    `signal-precision.sh:27`). Число 200 в `knowledge-activator.sh:824` относится к общему
#    журналу инжектов, а не к посессионным файлам. Порог хранения 60 покрывает все известные
#    окна с запасом; уменьшать его — значит резать вход замерам.
#
# 2. ОЧЕРЕДЬ ≠ ВЫБОРКА. Файл, который держит НЕЗАКРЫТЫЙ долг (исход, о котором ещё напомнят),
#    очередью и остаётся: у него нет окна, у него есть незакрытые записи. Такие семейства
#    исключены поимённо ниже. Выборка (журнал срабатываний, из которого считают долю)
#    подрезается по числу — старое за окном на долю уже не влияет.
#
# 3. Живая сессия не трогается никогда, даже если её файлы старые: источник — реестр
#    ~/.claude/sessions (записи `active/`, метки `live/`), а живость — признак процесса,
#    а не наличие записи (D337, см. ниже).
#
# Как пересобрать список семейств, читаемых ЧЕРЕЗ сессии (если добавится новый механизм):
#   grep -rhoE '/[a-z][a-z0-9_-]*[-_]\*\.?[a-z]*' hooks/*.sh scripts/*.sh scripts/*.py \
#     | sed 's|^/||' | sort -u
set -uo pipefail

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
KEEP="${STATE_PRUNE_KEEP:-60}"
APPLY=0; INCLUDE_BAKS=0
BAK_KEEP="${STATE_PRUNE_BAK_KEEP:-3}"
for a in "$@"; do
    case "$a" in
        --apply) APPLY=1 ;;
        --include-backups) INCLUDE_BAKS=1 ;;
        --dry-run) ;;
        *) echo "usage: $0 [--dry-run|--apply] [--include-backups]"; exit 2 ;;
    esac
done
[ -d "$STATE" ] || { echo "каталога состояния нет: $STATE"; exit 0; }

# Очереди незакрытого долга и журналы, из которых считают доли по маске через сессии.
# Их не подрезаем вовсе: цена ошибки здесь — потерянный долг либо перекошенный замер,
# а выигрыш по месту мал (все эти семейства меньше 100 файлов).
KEEP_FAMILIES='disagreement-pending|question-open|narrative-pending|output-violations|backlog-stale-read|blocker-fired|correction-fired|rework-fired|trust-guard-fired|detection|outcome|doc-state|five-whys|intrusiveness|compile-counted|compile-reminded'

# Имена в реестре живых сессий — `<sid>.json`, а файлы состояния зовутся `<sid>`,
# `response-<sid>.jsonl`, `session-speaker_<sid>`. Регулярка `<sid>.json` совпадала только
# там, где после sid идёт точка, — то есть ЧЕТЫРЕ семейства из семи (`session-speaker_`,
# `knowledge-capture-`, `knowledge-capture-marker-`, `itr_event_last_fire_`) живой сессией
# не защищались вовсе. Пока прибор бегал сухим, это было безвредно; при исполняющем режиме
# уборка сносила бы состояние ИДУЩЕГО разговора (D274). Расширение снимается, остаётся sid.
#
# Живость решается ПРИЗНАКОМ процесса, а не наличием записи (D337, корень R3). Признак один
# на систему и живёт у реестра — `sr_record_alive` (hooks/session-registry-lib.sh): за
# числовым sid стоит процесс, за UUID — свежая метка `live/<sid>.json`. Читаются ОБА
# каталога: после первого Stop накопитель `active/<sid>.json` унесён в реестр, и параллельная
# сессия видна только меткой — по одному `active/` она не защищалась вовсе. Запись без
# признака (фикстура прогона, брошенный накопитель) защиты не получает и называется числом.
# Замер 6 сентября 2026: в `active/` 3 записи, 2 из них фикстуры (`perf.json`, `probe.json`)
# — обе защищали файлы, которых нет. Сами записи прибор не удаляет: это предмет
# `sr_cleanup_stale`, и срок там свой (накопитель хода нельзя снести раньше, чем finalize
# унесёт его в реестр).
ACTIVE=""; ORPHANS=""; ORPHAN_N=0
SR_LIB="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/hooks/session-registry-lib.sh"
[ -f "$SR_LIB" ] || SR_LIB="$HOME/.claude/hooks/session-registry-lib.sh"
if [ -f "$SR_LIB" ]; then
    # shellcheck source=/dev/null
    . "$SR_LIB"
    while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        _sid=$(basename "$_f" .json)
        case "|$ACTIVE|$ORPHANS|" in *"|$_sid|"*) continue ;; esac
        if sr_record_alive "$_sid"; then
            ACTIVE="${ACTIVE:+$ACTIVE|}$_sid"
        else
            ORPHANS="${ORPHANS:+$ORPHANS|}$_sid"; ORPHAN_N=$((ORPHAN_N + 1))
        fi
    done <<EOF
$(find "$SR_ACTIVE_DIR" "$(_sr_live_dir)" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
EOF
elif [ -d "$HOME/.claude/sessions/active" ]; then
    # Библиотеки нет — признака процесса взять неоткуда; это состояние «прибор сломан», и
    # оно называется, а не глотается: молчание здесь читалось бы как «фикстур нет».
    echo "библиотеки реестра нет ($SR_LIB): живость по наличию записи, без признака процесса"
    ACTIVE=$(ls "$HOME/.claude/sessions/active" 2>/dev/null | sed 's/\.json$//' | tr '\n' '|' | sed 's/|$//')
fi

SID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
TMP=$(mktemp -d) || exit 0
trap 'rm -rf "$TMP"' EXIT

# Семейство = имя файла с вырезанным идентификатором сессии. Файл без идентификатора
# посессионным не является и не рассматривается вовсе.
ls -t "$STATE" 2>/dev/null | while IFS= read -r n; do
    [ -f "$STATE/$n" ] || continue
    grep -qE "$SID_RE" <<< "$n" || continue
    fam=$(printf '%s' "$n" | sed -E "s/$SID_RE/<sid>/g")
    case "$fam" in *"<sid>"*) ;; *) continue ;; esac
    printf '%s\t%s\n' "$fam" "$n"
done > "$TMP/all.tsv"

TOTAL=0; FILES="$TMP/doomed.txt"; : > "$FILES"
cut -f1 "$TMP/all.tsv" | sort -u | while IFS= read -r fam; do
    stem=$(printf '%s' "$fam" | sed 's/<sid>.*//; s/[-_]$//')
    grep -qE "^($KEEP_FAMILIES)$" <<< "$stem" && continue
    # `ls -t` выше уже отсортировал по свежести — порядок в all.tsv это сохраняет.
    awk -F'\t' -v f="$fam" '$1 == f {print $2}' "$TMP/all.tsv" | tail -n "+$((KEEP + 1))" \
        >> "$FILES"
done

# Живые сессии выбрасываются из списка ПОСЛЕ отбора: иначе их файлы сдвигали бы окно.
if [ -n "$ACTIVE" ]; then
    # `&&` здесь был дырой: когда ВСЕ обречённые файлы принадлежат живым сессиям, grep не
    # выводит ни строки и возвращает 1, `mv` не исполняется — и список остаётся
    # НЕОТФИЛЬТРОВАННЫМ, то есть живые файлы попадают под удаление именно в том случае,
    # ради которого фильтр и написан. Разделено на два шага.
    grep -vE "$ACTIVE" "$FILES" > "$FILES.f" 2>/dev/null || true
    mv "$FILES.f" "$FILES"
fi

N=$(wc -l < "$FILES" | tr -d ' ')
BYTES=0
while IFS= read -r n; do
    [ -n "$n" ] || continue
    s=$(wc -c < "$STATE/$n" 2>/dev/null | tr -d ' ')
    case "${s:-}" in ''|*[!0-9]*) s=0 ;; esac
    BYTES=$((BYTES + s))
done < "$FILES"

if [ "$ORPHAN_N" -gt 0 ]; then
    printf 'реестр живых сессий: запись без процесса — %s (%s); их файлы защиты не получают\n' \
        "$ORPHAN_N" "$(printf '%s' "$ORPHANS" | tr '|' ' ')"
fi
printf 'посессионных файлов за окном хранения (%s на семейство): %s, %s КБ\n' \
    "$KEEP" "${N:-0}" "$((BYTES / 1024))"
if [ "${N:-0}" -gt 0 ]; then
    printf 'по семействам:\n'
    sed -E "s/$SID_RE/<sid>/g" "$FILES" | sort | uniq -c | sort -rn | head -12 | sed 's/^/  /'
fi

# ── Резервные копии с уникальным именем ───────────────────────────────────────
# Отдельный предмет и отдельное решение (D252, разбор 1 сентября 2026).
#
# Устройство: `cp/mv "$F" "$F.bak.$(date +%s)"` — имя включает метку времени, поэтому
# каждый прогон создаёт НОВЫЙ файл, ни один не перезаписывается, читателей нет ни одного
# (только писатели), и срока жизни нет. Носителей пять:
#   install.sh:680                  — копия settings.json на КАЖДОЙ установке
#   lib/claude-md-merge.sh:41,57    — копия правил на КАЖДОМ слиянии
#   hooks/backfill-intrusiveness.sh:71, hooks/backfill-compliance.sh:211 — в каталоге состояния
# Замер: 179 копий в ~/.claude и 4 в каталоге состояния, вместе 8,4 МБ.
#
# Почему уборка централизована, а не по месту записи: писателей пять, и каждый пришлось бы
# учить одному и тому же. Цена — копии копятся между прогонами уборщика; она ограничена
# сроком из реестра замеров.
#
# Удаление требует ЯВНОГО `--include-backups`: это единственная копия состояния до
# перезаписи, и решение о ней принимает владелец, а не расписание.
# Каталоги перечислены ПОИМЁННО и без спуска вглубь — это решение, а не побочный эффект.
# 1 сентября 2026 после уборки нашлось 24 копии в ~/.claude/ablation/frozen-runtime-*/hooks/state:
# это ЗАМОРОЖЕННЫЕ снимки среды для ablation-замера, а не забытые копии, и удаление любой из
# них портит плечо эксперимента. Уборщик их не тронул только потому, что не заглядывал так
# глубоко; расширь кто-нибудь обход на поддеревья — и снимки уедут молча. Поэтому: список
# каталогов явный, `-maxdepth 1` обязателен, а замороженные снимки названы вслух.
BAK_DIRS="$STATE $HOME/.claude"
BAKS="$TMP/baks.txt"; : > "$BAKS"
for d in $BAK_DIRS; do
    [ -d "$d" ] || continue
    find "$d" -maxdepth 1 -name '*.bak.*' -type f 2>/dev/null
done | sed -E 's/\.bak\.[0-9]+$//' | sort -u | while IFS= read -r base; do
    ls -t "$base".bak.* 2>/dev/null | tail -n "+$((BAK_KEEP + 1))" >> "$BAKS"
done
BN=$(wc -l < "$BAKS" | tr -d ' ')
if [ "${BN:-0}" -gt 0 ]; then
    BKB=$(while IFS= read -r f; do wc -c < "$f" 2>/dev/null; done < "$BAKS" \
          | awk '{s+=$1} END {printf "%d", s/1024}')
    printf 'резервных копий сверх %s свежих на базу: %s, %s КБ\n' "$BAK_KEEP" "$BN" "${BKB:-0}"
    sed -E 's|.*/||; s/\.bak\.[0-9]+$//' "$BAKS" | sort | uniq -c | sort -rn | head -5 | sed 's/^/  /'
    [ "$INCLUDE_BAKS" -eq 1 ] || printf '  не трогаю без --include-backups (единственная копия до перезаписи)\n'
fi

if [ "$APPLY" -eq 1 ] && [ "$INCLUDE_BAKS" -eq 1 ] && [ "${BN:-0}" -gt 0 ]; then
    while IFS= read -r f; do [ -n "$f" ] && rm -f "$f" 2>/dev/null; done < "$BAKS"
    printf 'резервных копий удалено: %s\n' "$BN"
fi

if [ "$APPLY" -eq 1 ]; then
    while IFS= read -r n; do
        [ -n "$n" ] && rm -f "$STATE/$n" 2>/dev/null
    done < "$FILES"
    printf 'удалено: %s\n' "${N:-0}"
else
    [ "${N:-0}" -gt 0 ] && printf 'сухой прогон. Удалить: %s --apply\n' "$0"
fi

# Код возврата: 0 — убирать нечего, 1 — есть что убрать. Прибор, всегда возвращающий ноль,
# в реестре замеров бесполезен: он не может покраснеть, и «находок нет» становится
# свойством прибора, а не мира (pattern-detector-wired-to-failure). После `--apply` мир уже
# приведён в порядок, и ноль честен; в сухом прогоне ноль означает «нечего убирать».
if [ "$APPLY" -eq 1 ]; then
    # Копии, оставленные намеренно (без --include-backups), находкой не считаются:
    # решение о них принято, а не отложено. А вот СДЕЛАННАЯ уборка находкой считается, и
    # это не формальность: с 2 сентября 2026 недельный замер зовёт именно `--apply`, и
    # прибор, всегда возвращающий ноль, в реестре замеров бесполезен — «находок нет»
    # становится свойством прибора, а не мира. Образец рядом: scripts/backlog-archive.sh:203
    # в исполняющем режиме возвращает 1, когда что-то перенёс.
    [ "${N:-0}" -gt 0 ] && exit 1
    [ "$INCLUDE_BAKS" -eq 1 ] && [ "${BN:-0}" -gt 0 ] && exit 1
    exit 0
fi
if [ "${N:-0}" -gt 0 ] || [ "${BN:-0}" -gt 0 ]; then exit 1; fi
exit 0
