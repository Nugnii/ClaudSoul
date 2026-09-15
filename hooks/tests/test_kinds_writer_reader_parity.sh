#!/usr/bin/env bash
# test_kinds_writer_reader_parity.sh — сроды повода: писатель и читатель знают один список.
#
# Результат: каждый срод, который гейт ПИШЕТ в `five-whys-<SID>.seen`, объявлен в
#            RC_KINDS_RE, и каждый объявленный кем-то пишется
# Проверка результата: bash hooks/tests/test_kinds_writer_reader_parity.sh даёт 0
#
# Повод, 9 сентября 2026. Гейт завёл девятый срод `notfollowed` (five-whys-gate.sh:259),
# а перечень-владелец RC_KINDS_RE о нём не узнал. Цена измерена: 0 записей исхода из 1035,
# срод невидим сверщику (declared-problem-recorded.sh:76) и своду незакрытого
# (hooks/lib/open-findings-lib.sh:67). Три зелёных теста контура разрыва не заметили,
# потому что каждый проверял ПОВЕДЕНИЕ на известных сродах, а не ПОЛНОТУ списка.
#
# Признак ВЫВОДИТСЯ из дерева, а не перечисляется: список писателя добывается из кода
# гейта, список читателя — из значения переменной. Перечисли сроды в самом тесте — и он
# станет третьим местом, которое надо не забыть обновить, то есть тем же дефектом.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/hooks/root-cause-lib.sh"
GATE="$ROOT/hooks/five-whys-gate.sh"
for f in "$LIB" "$GATE"; do
    [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }
done

# Читатель: значение RC_KINDS_RE из библиотеки (источаем в подоболочке, чтобы не тащить
# в тест остальное окружение библиотеки).
READER="$(. "$LIB" >/dev/null 2>&1; printf '%s' "${RC_KINDS_RE:-}" | tr '|' '\n' | sed 's/:$//' | grep -v '^$' | sort -u)"
[ -n "$READER" ] || { echo "FAIL: RC_KINDS_RE пуст или библиотека не источается"; exit 1; }

# Писатель: сроды, которые гейт дописывает в KINDS. Форма — KINDS="${KINDS}<род>:...
WRITER="$(grep -oE 'KINDS="\$\{KINDS\}[a-z_-]+:' "$GATE" \
          | sed -E 's/.*\}([a-z_-]+):/\1/' | sort -u)"
[ -n "$WRITER" ] || { echo "FAIL: в гейте не найдено ни одного места записи срода — признак устарел"; exit 1; }

PASS=0; FAIL=0

# 1. Каждый пишущийся срод объявлен читателем. Это и есть дефект 9 сентября.
while IFS= read -r k; do
    [ -n "$k" ] || continue
    if grep -qxF "$k" <<< "$READER"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: гейт пишет срод '$k', но RC_KINDS_RE его не знает — исход этого срода не запишется никогда"
    fi
done <<< "$WRITER"

# 2. Обратная сторона: объявленный срод должен кем-то писаться, иначе перечень копит мёртвое.
#    `event` пишется гейтом же, но заводится извне (rc_note_event) — потому ищем по дереву.
while IFS= read -r k; do
    [ -n "$k" ] || continue
    if grep -qxF "$k" <<< "$WRITER"; then
        PASS=$((PASS+1))
    elif grep -rqE "\"?kind\"?[:=][[:space:]\"']*${k}\b" "$ROOT/hooks" "$ROOT/scripts" 2>/dev/null; then
        PASS=$((PASS+1))   # заводится внешним продюсером (событийные поводы)
    else
        FAIL=$((FAIL+1))
        echo "FAIL: RC_KINDS_RE объявляет срод '$k', но писателя в дереве нет — мёртвая запись перечня"
    fi
done <<< "$READER"

echo "--- писатель: $(printf '%s' "$WRITER" | tr '\n' ' ')"
echo "--- читатель: $(printf '%s' "$READER" | tr '\n' ' ')"
echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
