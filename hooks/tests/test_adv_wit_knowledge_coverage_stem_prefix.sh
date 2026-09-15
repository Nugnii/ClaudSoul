#!/usr/bin/env bash
# test_adv_wit_knowledge_coverage_stem_prefix.sh — починка «родитель — чужой файл» в knowledge-coverage.sh ищет стем ПОДСТРОКОЙ: запись, чей стем — префикс имени другой записи, названной родителем, считается представленной.
#
# Результат: orphan `case-2026-01-02-orphan` (impact 5, confirmed 20, нигде не названа) объясняется
#            «представлен родителем», потому что родитель перечисляет `case-2026-01-02-orphan-two`,
#            а `stem in text` не знает границы имени. Ожидание: НЕОБЪЯСНЁННЫХ: 1, orphan назван, код 1.
#            Достижимость на живой базе на 13 сентября 2026: среди 415 стемов пар «стем — префикс
#            другого стема» ноль; дефект латентный, класс имён (`…-foo` и `…-foo-2`) ничем не запрещён.
# Проверка результата: этот тест.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/knowledge-coverage.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"; mkdir -p "$L" "$S"
rec() {   # имя impact confirmed
    printf -- '---\nname: %s\nimpact: %s\nconfirmed_count: %s\ncontradicted_count: 0\n---\nтело\n' "${1#*-}" "$2" "$3" > "$L/$1"
}
rec case-2026-01-01-served.md 5 10
rec case-2026-01-02-orphan.md 5 20
rec case-2026-01-02-orphan-two.md 5 30
printf -- '---\nname: pattern-parent\nimpact: 1\nconfirmed_count: 0\ncontradicted_count: 0\nsource_cases:\n  - case-2026-01-02-orphan-two\n---\n' > "$L/pattern-parent.md"
printf '{"file":"case-2026-01-01-served.md","injected":true}\n' > "$S/injection-log.jsonl"

# --- T1: orphan не подавалась, не названа ни одним родителем, ранг выше медианы — обязана быть названа
OUT=$(cd "$REPO" && LESSONS_DIR="$L" STATE_DIR="$S" bash "$TOOL" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok || bad T1 "rc=$RC — orphan сошла за представленную соседом-по-префиксу: ${OUT}"
has T1 'представлен родителем: 1'
has T1 'НЕОБЪЯСНЁННЫХ: 1'
has T1 '· case-2026-01-02-orphan.md'

echo ""
echo "adv knowledge-coverage stem prefix: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
