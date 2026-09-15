#!/usr/bin/env bash
# prune-rules.sh — убрать из набора всё, что не является правилом.
# Без этого ОДИН посторонний yaml роняет весь прогон: opengrep отдаёт exit=7 и
# «0 находок», неотличимые от чистого результата. Повод — stats/web_frameworks.yml,
# обрушивший 2074 валидных правила 9 сентября 2026.
# Признак «не правило» берётся по содержимому (нет ключа rules:), а не по списку имён:
# список имён я угадал дважды и дважды промахнулся.
set -uo pipefail
RULES="${1:-$HOME/.claude/security/rules}"
[ -d "$RULES" ] || { echo "нет набора: $RULES" >&2; exit 2; }
n=0
find "$RULES" \( -name '*.yaml' -o -name '*.yml' \) ! -path '*/.git/*' -print0 \
| while IFS= read -r -d '' f; do
    grep -q '^rules:' "$f" || { rm -f "$f"; n=$((n+1)); }
  done
echo "правил в наборе: $(find "$RULES" \( -name '*.yaml' -o -name '*.yml' \) ! -path '*/.git/*' | wc -l | tr -d '[:space:]')"
