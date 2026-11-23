#!/usr/bin/env bash
# СУДИТ: hooks/pre-compact-handoff.sh
# test_precompact_snapshot_keep.sh — снимок SESSION.md перед сжатием контекста хранится в трёх
# последних на проект (D1006, решение владельца 19 октября 2026), снимки чужого проекта не трогаются.
#
# Ловушка: «хранит три» легко получить, снеся всё лишнее подряд. Поэтому рядом с проверкой удаления
# стоят проверки сохранения: остаются именно свежайшие, чужой проект цел.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/pre-compact-handoff.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P="$TMP/projA"; ST="$TMP/state"; SN="$ST/handoff-snapshots"
mkdir -p "$P" "$SN"
echo "# Session Log" > "$P/SESSION.md"
# Пять прежних снимков своего проекта и пять чужого; время задано явно, иначе `ls -t` упорядочит
# созданные в одну секунду файлы как придётся.
for i in 1 2 3 4 5; do
    for proj in projA projB; do
        f="$SN/$proj-precompact-old$i.md"; : > "$f"; touch -t "20200${i}010000" "$f"
    done
done

printf '{"session_id":"t","trigger":"auto","cwd":"%s"}' "$P" \
  | STATE_DIR="$ST" HOME="$TMP" bash "$HOOK" >/dev/null 2>&1

count() { find "$SN" -maxdepth 1 -type f -name "$1" | wc -l | tr -d ' '; }

# T1: снимков своего проекта — три (новый и два новейших прежних).
[ "$(count 'projA-precompact-*.md')" = "3" ] && ok \
  || bad T1 "снимков проекта осталось $(count 'projA-precompact-*.md'), ждали 3"
# T2: ушли самые старые, а не случайные.
[ -f "$SN/projA-precompact-old5.md" ] && [ -f "$SN/projA-precompact-old4.md" ] \
  && [ ! -f "$SN/projA-precompact-old3.md" ] && ok || bad T2 "ушли не самые старые снимки"
# T3: снимок этого сжатия записан — иначе «три» держались бы пустотой.
[ "$(find "$SN" -maxdepth 1 -type f -name 'projA-precompact-2*.md' | wc -l | tr -d ' ')" = "1" ] && ok \
  || bad T3 "снимок этого сжатия не записан"
# T4: чужой проект не тронут.
[ "$(count 'projB-precompact-*.md')" = "5" ] && ok \
  || bad T4 "тронуты снимки чужого проекта: $(count 'projB-precompact-*.md') из 5"

echo "precompact snapshot keep: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
