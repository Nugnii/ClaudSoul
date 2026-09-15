#!/usr/bin/env bash
# test_adv_bump_inline_source_cases.sh — АТАКА: `source_cases` в поточной (inline) форме
# теряется целиком при добавлении кейса.
#
# Скрипт знает три состояния поля: отсутствует, `source_cases: []`, блочный список.
# Четвёртой формы — НЕПУСТОГО поточного списка `source_cases: [case-a.md, case-b.md]` —
# в разборе нет. Такая строка не совпадает ни с одним из двух образцов (строки 245 и 248),
# `src_state` остаётся "absent", и на выходе из frontmatter (строка 227) печатается ВТОРОЙ
# ключ `source_cases:` с одним новым кейсом.
#
# Дубль ключа в YAML-отображении не ошибка разбора: `yaml.safe_load` берёт ПОСЛЕДНИЙ.
# То есть файл остаётся валидным, тест целостности frontmatter молчит, а прежние кейсы
# исчезают из графа знаний бесшумно. `mcp-server/indexer.py:272` читает ровно это поле.
#
# Достижимость: в боевой базе (~/.claude/global-lessons) семь файлов записаны этой формой —
# pattern-defensive-misdiagnosis, pattern-complementary-repo-borrowing,
# pattern-identity-from-name-coincidence, pattern-guard-scope-blindness,
# pattern-keep-list-drifts-from-its-consumers, pattern-patch-waves-degrade-outgoing-text,
# pattern-problem-framing-bounds-verification. Вход — документированный вызов
# /learn Step 4a: `knowledge-counter-bump.sh <pattern> confirmed "<почему>" <case-файл>`.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-counter-bump.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: $SCRIPT не найден"; exit 0; }
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: нет pyyaml"; exit 0; }

T=$(mktemp -d)
export LESSONS_DIR="$T/lessons" STATE_DIR="$T/state"
unset CLAUDE_STATE_DIR
mkdir -p "$LESSONS_DIR" "$STATE_DIR"

cat > "$LESSONS_DIR/pattern-probe.md" <<'KN'
---
name: проба
confidence: 4
impact: 3
confirmed_count: 2
contradicted_count: 0
last_confirmed: 2026-01-01
source_cases: [case-old-a.md, case-old-b.md]
provenance_log: []
---
тело
KN

bash "$SCRIPT" pattern-probe confirmed "подтвердилось третьим случаем" case-new.md >/dev/null 2>&1

got=$(python3 - "$LESSONS_DIR/pattern-probe.md" <<'PY'
import sys, yaml
t = open(sys.argv[1], encoding="utf-8").read()
fm = t.split("\n---\n")[0].lstrip("-\n")
d = yaml.safe_load(fm) or {}
print(",".join(sorted(d.get("source_cases") or [])))
PY
)

echo "source_cases после вызова: [$got]"
rc=0
for want in case-old-a.md case-old-b.md case-new.md; do
    case ",$got," in
        *",$want,"*) ;;
        *) echo "FAIL: '$want' отсутствует в source_cases после записи"; rc=1 ;;
    esac
done

if [ "$rc" -ne 0 ]; then
    echo ""
    echo "Ожидание: поле source_cases содержит три кейса — два прежних и добавленный."
    echo "Факт:     прежние кейсы стёрты дублирующим ключом. Файл после записи:"
    sed -n '1,20p' "$LESSONS_DIR/pattern-probe.md" | sed 's|^|    |'
    echo "adv bump inline-source-cases: КРАСНЫЙ"
else
    echo "adv bump inline-source-cases: 1/1 passed"
fi
exit "$rc"
