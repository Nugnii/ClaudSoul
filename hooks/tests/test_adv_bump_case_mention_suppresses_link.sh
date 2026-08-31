#!/usr/bin/env bash
# test_adv_bump_case_mention_suppresses_link.sh — АТАКА: обратная сторона ссылки не пишется,
# если имя кейса УЖЕ встречается где-нибудь в файле — хотя бы в собственной записи скрипта.
#
# Дедуп сделан поиском по ВСЕМУ файлу (строка 192): `grep -Fq "$_tc" "$FILE"`. Поле
# source_cases при этом не читается вовсе. Совпадение в теле, в `related`, в чужом более
# длинном имени или в `trigger_case:` внутри provenance_log — всё считается «уже есть».
#
# Отравляющая запись — своя собственная. Ветка `contradicted` пишет `trigger_case: case-X.md`
# в provenance_log и намеренно НЕ трогает source_cases (комментарий на строке 184:
# «КОНТРПРИМЕР: … contradicted "разошлось" case-X.md — source_cases не трогается»).
# После этого никакой последующий `confirmed` с тем же кейсом источник уже не внесёт:
# grep находит имя в провенансе. Кейс навсегда остаётся вне source_cases родителя.
#
# Требование, которое нарушается, названо в самом скрипте (строки 173-179): «Ребро
# кейс → паттерн пишется в ДВУХ файлах … здесь — место, где требование выполняется».
# `mcp-server/indexer.py:272` строит граф по source_cases, а не по провенансу.
#
# Достижимость: обе ветки /learn Step 4a принимают `<case-файл>` четвёртым аргументом
# (skills/learn/SKILL.md:82,85) — «противоречит» и «подтверждает» описаны рядом как
# нормальный ход разбора одного и того же знания.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: нет pyyaml"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons" STATE_DIR="$T/state"
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

srccases() {
    python3 - "$1" <<'PY'
import sys, yaml
t = open(sys.argv[1], encoding="utf-8").read()
fm = t.split("\n---\n")[0].lstrip("-\n")
d = yaml.safe_load(fm) or {}
print(",".join(d.get("source_cases") or []))
PY
}

rc=0

# --- Проба 1: сперва contradicted тем же кейсом, затем confirmed ---
cat > "$LESSONS_DIR/pattern-seq.md" <<'KN'
---
name: проба
confidence: 4
confirmed_count: 2
contradicted_count: 0
source_cases: []
provenance_log: []
---
тело
KN
bash "$SCRIPT" pattern-seq contradicted "разошлось на краю" case-foo.md >/dev/null 2>&1
bash "$SCRIPT" pattern-seq confirmed   "подтвердилось после сужения" case-foo.md >/dev/null 2>&1
got1=$(srccases "$LESSONS_DIR/pattern-seq.md")
echo "проба 1 (contradicted → confirmed): source_cases = [$got1]"
case ",$got1," in
    *",case-foo.md,"*) ;;
    *) echo "FAIL [1]: case-foo.md не внесён в source_cases — ссылка осталась односторонней"; rc=1 ;;
esac

# --- Проба 2: имя кейса упомянуто в теле документа ---
cat > "$LESSONS_DIR/pattern-prose.md" <<'KN'
---
name: проба
confidence: 4
confirmed_count: 2
contradicted_count: 0
source_cases: []
provenance_log: []
---
Разбор опирается на case-bar.md — подробности там.
KN
bash "$SCRIPT" pattern-prose confirmed "подтвердилось" case-bar.md >/dev/null 2>&1
got2=$(srccases "$LESSONS_DIR/pattern-prose.md")
echo "проба 2 (имя в теле):              source_cases = [$got2]"
case ",$got2," in
    *",case-bar.md,"*) ;;
    *) echo "FAIL [2]: упоминание в ТЕЛЕ засчитано за наличие ссылки во frontmatter"; rc=1 ;;
esac

if [ "$rc" -ne 0 ]; then
    echo ""
    echo "Ожидание: после confirmed с файлом кейса имя кейса стоит в поле source_cases родителя."
    echo "Факт:     поле пусто; единственный носитель имени — provenance_log, который"
    echo "          обходом графа (indexer.py:272) не читается."
    echo "adv bump case-mention-suppresses-link: КРАСНЫЙ"
else
    echo "adv bump case-mention-suppresses-link: 2/2 passed"
fi
exit "$rc"
