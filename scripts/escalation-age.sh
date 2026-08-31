#!/usr/bin/env bash
# escalation-age.sh — сколько по заявке на эскалацию НЕ действуют.
# Результат: нет заявок на эскалацию, по которым не действуют дольше порога
# Проверка результата: bash scripts/escalation-age.sh даёт 0
#
#
# Повод (D46). Дайджест сообщал об эскалации 13 недель подряд дословно одинаково: единственным
# меняющимся числом был `confirmed_count`, то есть мерилось, насколько знание подкрепилось, а
# не насколько долго по нему не действуют. Растущее число читалось как «всё под контролем».
#
# Теперь заявка имеет `escalation_opened`, и растёт возраст — число, растущее от БЕЗДЕЙСТВИЯ.
# Просроченная заявка роняет проверку, а не добавляет тринадцатый одинаковый абзац.
#
# Код возврата: 0 — открытых заявок нет либо все моложе порога; 1 — есть просроченные.

set -uo pipefail

LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
MAX_DAYS="${ESCALATION_MAX_DAYS:-60}"
[ -d "$LESSONS" ] || { echo "escalation-age: нет базы $LESSONS" >&2; exit 2; }

for lib in "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" 2>/dev/null && pwd)/portable-lib.sh" \
           "$HOME/.claude/hooks/portable-lib.sh"; do
    [ -f "$lib" ] && { . "$lib"; break; }
done

OPEN=0
STALE=0
for f in "$LESSONS"/pattern-*.md "$LESSONS"/principle-*.md; do
    [ -f "$f" ] || continue
    grep -q '^blocker: true' "$f" || continue
    th=$(sed -n 's/^escalation_threshold:[[:space:]]*\([0-9]*\).*/\1/p' "$f" | head -1)
    [ -n "$th" ] || continue
    cc=$(sed -n 's/^confirmed_count:[[:space:]]*\([0-9]*\).*/\1/p' "$f" | head -1)
    [ -n "$cc" ] && [ "$cc" -ge "$th" ] 2>/dev/null || continue
    OPEN=$((OPEN + 1))
    op=$(sed -n 's/^escalation_opened:[[:space:]]*\([0-9-]*\).*/\1/p' "$f" | head -1)
    age="?"
    if [ -n "$op" ] && command -v iso_epoch >/dev/null 2>&1; then
        e=$(iso_epoch "$op"); [ "${e:-0}" -gt 0 ] && age=$(( ( $(date +%s) - e ) / 86400 ))
    fi
    printf '  заявка: %-42s открыта %s дн. назад (confirmed %s ≥ %s)\n' "$(basename "$f" .md)" "$age" "$cc" "$th"
    case "$age" in ''|*[!0-9]*) ;; *) [ "$age" -gt "$MAX_DAYS" ] && STALE=$((STALE + 1)) ;; esac
done

if [ "$OPEN" -eq 0 ]; then
    echo "Заявки на эскалацию: открытых нет."
else
    echo "Заявок открыто: ${OPEN}, просрочено (> ${MAX_DAYS} дн.): ${STALE}."
fi
[ "$STALE" -eq 0 ]
