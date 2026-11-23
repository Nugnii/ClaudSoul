#!/usr/bin/env bash
# mutation-snapshot.sh — снимок файла перед мутацией: имя выдаёт инструмент, а не агент.
# Имя не `snapshot.sh`: такой basename уже есть у `scripts/ablation/snapshot.sh`, а индекс
# зависимостей связывает механизмы по basename (поймано CI, test_adv3_dep_basename_collision).
#
# Результат: два агента, снимающие один файл в одной песочнице, получают РАЗНЫЕ пути по
#            построению; восстановление идёт в путь, записанный при снятии, и отказывается,
#            если снимок изменён после снятия
# Проверка результата: bash hooks/tests/test_mutation_snapshot.sh даёт 0
#
# Зачем (D344). 7 сентября 2026 четыре агента чинили тесты параллельно и снимали копии
# правимых механизмов под родовыми именами в общей песочнице: `guard.orig` одного агента
# перезаписал другой, и откат положил чужое содержимое в чужой файл. Ущерб не случился только
# потому, что снимавший сверял хеш после отката. Договор об именах — текстовое правило, а они
# измеренно не держатся; здесь имя выводит `mktemp` (столкновение невозможно по построению),
# исходный путь и хеш пишутся рядом со снимком, и восстановление сверяет хеш САМО.
# Идентификатор агента из среды не вывести — это измерено 12 сентября 2026: субагент делит с
# родителем и `CLAUDE_CODE_SESSION_ID`, и песочницу. Потому владельца снимка задаёт не имя
# агента, а уникальность имени плюс записанный при снятии путь.
#
# Применение:
#   mutation-snapshot.sh take <файл>        → stdout: путь снимка. Рядом <снимок>.meta: путь и хеш.
#   mutation-snapshot.sh restore <снимок>   → сверяет хеш, кладёт снимок в записанный путь. 0 — сделано,
#                                    2 — отказ (снимок изменён после снятия, записи нет).
#   mutation-snapshot.sh check <снимок>     → 0 цел, 1 изменён после снятия, 2 записи нет.
# Каталог: $SNAPSHOT_DIR, иначе ${TMPDIR:-/tmp}/claudsoul-snapshots/<session id | nosession>.
set -uo pipefail
_here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)
# shellcheck source=/dev/null
. "$_here/../hooks/hash-lib.sh" 2>/dev/null || { echo "snapshot: нет hooks/hash-lib.sh рядом со скриптом" >&2; exit 2; }

_dir="${SNAPSHOT_DIR:-${TMPDIR:-/tmp}/claudsoul-snapshots/${CLAUDE_CODE_SESSION_ID:-nosession}}"

_meta_get() { sed -n "s/^$2=//p" "$1.meta" 2>/dev/null | head -1; }

case "${1:-}" in
    take)
        f="${2:-}"
        [ -f "$f" ] || { echo "snapshot: нет такого файла: ${f:-<пусто>}" >&2; exit 2; }
        abs=$(cd -- "$(dirname -- "$f")" && pwd -P)/$(basename -- "$f")
        mkdir -p "$_dir" 2>/dev/null || { echo "snapshot: не создать каталог ${_dir}" >&2; exit 2; }
        snap=$(mktemp "$_dir/$(basename -- "$f").XXXXXX") || { echo "snapshot: mktemp отказал в ${_dir}" >&2; exit 2; }
        cp -p "$abs" "$snap" || { echo "snapshot: копия не снялась" >&2; exit 2; }
        h=$(hash_file "$snap") || { echo "snapshot: хеш не посчитан" >&2; exit 2; }
        printf 'path=%s\nhash=%s\n' "$abs" "$h" > "$snap.meta" || { echo "snapshot: запись ${snap}.meta не удалась" >&2; exit 2; }
        printf '%s\n' "$snap"
        ;;
    check)
        snap="${2:-}"
        [ -f "$snap" ] && [ -f "$snap.meta" ] || { echo "snapshot: нет снимка или записи: ${snap:-<пусто>}" >&2; exit 2; }
        want=$(_meta_get "$snap" hash); have=$(hash_file "$snap")
        [ -n "$want" ] && [ "$want" = "$have" ] && exit 0
        echo "snapshot: снимок изменён после снятия (${snap}): записано ${want}, сейчас ${have}" >&2
        exit 1
        ;;
    restore)
        snap="${2:-}"
        "$0" check "$snap" || exit 2   # отказ и на «изменён», и на «нет записи» — оба значат «не тот снимок»
        dst=$(_meta_get "$snap" path)
        [ -n "$dst" ] || { echo "snapshot: в записи нет пути" >&2; exit 2; }
        cp -p "$snap" "$dst" || { echo "snapshot: восстановление в ${dst} не удалось" >&2; exit 2; }
        echo "восстановлено: ${dst}"
        ;;
    *)
        echo "применение: $(basename "$0") take <файл> | restore <снимок> | check <снимок>" >&2
        exit 2
        ;;
esac
