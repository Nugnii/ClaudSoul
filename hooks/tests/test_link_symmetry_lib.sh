#!/usr/bin/env bash
# test_link_symmetry_lib.sh — инвариант симметрии считается РАЗБОРОМ поля, а не подстрокой.
#
# Результат: `hooks/lib/link_symmetry.py` находит нарушение там, где имя кейса есть в
#            файле родителя, но НЕ в его `source_cases`; отказ разбора отличим от чистоты
# Проверка результата: bash hooks/tests/test_link_symmetry_lib.sh даёт 0
#
# Повод (D312). Два прибора инварианта D12 спрашивали «имя кейса not in текст родителя».
# Имя лежит и в `provenance_log.trigger_case`, и в `related`, и в прозе — для подстроки
# связь «есть». Замер 5 сентября 2026: приборы 1 нарушение, разбор поля 18.
#
# КОНТРПРИМЕРЫ, все проверяются ниже:
#   · кейс перечислен в source_cases — нарушения нет, как бы ни была записана форма;
#   · ребро кейс → КЕЙС родительства не объявляет и в счёт не идёт;
#   · снятый с учёта (DEPRECATED) кейс основанием не считается;
#   · родитель, чей source_cases разобрать не удалось, попадает в «не прочитано», а не в «чисто».
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO/lib/link_symmetry.py"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: нет PyYAML"; exit 0; }

PASS=0; FAIL=0
assert_eq() {  # <получено> <ожидание> <метка>
    if [ "$1" = "$2" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: ожидалось '$2', получено '$1'"; fi
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; mkdir -p "$L"

ask() {  # <что спросить> → печатает ответ
    python3 - "$L" "$1" <<'PY'
import sys
sys.path.insert(0, __import__("os").environ["LIB_DIR"])
import link_symmetry as ls
bad, unread = ls.asymmetric(sys.argv[1])
q = sys.argv[2]
if q == "bad":      print(len(bad))
elif q == "unread": print(len(unread))
elif q == "pairs":  print(" ".join(f"{c}->{t}" for c, _k, t in bad))
PY
}
export LIB_DIR="$REPO/lib"

mk_case() { printf -- '---\nname: c\ntype: case\nedges:\n  - specializes: %s\n---\n\n# C\n' "$2" > "$L/$1"; }

# --- T1: кейс перечислен — нарушения нет ---
printf -- '---\nname: p\nsource_cases:\n  - case-one.md\nrelated: []\n---\n\n# P\n' > "$L/pattern-a.md"
mk_case "case-one.md" "pattern-a.md"
assert_eq "$(ask bad)" "0" "T1: перечисленный кейс нарушением не считается"

# --- T2: ГЛАВНАЯ НОГА. Имя кейса есть в файле, но НЕ в source_cases ---
# Ровно форма, на которой подстрочный прибор был слеп: имя лежит в provenance_log.
printf -- '---\nname: p\nsource_cases:\n  - case-other.md\nprovenance_log:\n  - trigger_case: case-two.md\nrelated: []\n---\n\n# P\n' > "$L/pattern-b.md"
mk_case "case-two.md" "pattern-b.md"
assert_eq "$(ask bad)" "1" "T2: имя в provenance_log симметрией не является"
assert_eq "$(ask pairs)" "case-two.md->pattern-b.md" "T2b: названа именно эта пара"
# и контроль слепоты прежнего способа: подстрока в файле ЕСТЬ
if grep -q 'case-two.md' "$L/pattern-b.md"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T2c]: фикстура не воспроизводит слепоту — имени нет в файле"; fi

# --- T3: поточная форма разбирается наравне с блочной ---
rm -f "$L/pattern-b.md" "$L/case-two.md"
printf -- '---\nname: p\nsource_cases: [case-three.md, case-zero.md]\nrelated: []\n---\n\n# P\n' > "$L/pattern-c.md"
mk_case "case-three.md" "pattern-c.md"
assert_eq "$(ask bad)" "0" "T3: поточная форма читается как список"

# --- T4: КОНТРПРИМЕР — ребро кейс → КЕЙС родительства не объявляет ---
mk_case "case-four.md" "case-one.md"
assert_eq "$(ask bad)" "0" "T4: ребро на кейс в счёт не идёт"

# --- T5: КОНТРПРИМЕР — снятый с учёта кейс основанием не считается ---
printf -- '---\nname: p\nsource_cases:\n  - case-nobody.md\nrelated: []\n---\n\n# P\n' > "$L/pattern-d.md"
printf -- '---\nname: c\nstatus: DEPRECATED\nedges:\n  - confirms: pattern-d.md\n---\n\n# C\n' > "$L/case-five.md"
assert_eq "$(ask bad)" "0" "T5: DEPRECATED кейс нарушением не считается"

# --- T6: отказ разбора отличим от чистоты (род B) ---
rm -f "$L/case-five.md" "$L/pattern-d.md"
printf 'name: p\nsource_cases:\n  - case-nobody.md\n' > "$L/pattern-e.md"   # frontmatter нет
mk_case "case-six.md" "pattern-e.md"
assert_eq "$(ask unread)" "1" "T6: родитель без frontmatter попал в «не прочитано»"
assert_eq "$(ask bad)" "0" "T6b: неразобранный не засчитан нарушением"

# --- T7-T10: разбор БЕЗ PyYAML (13 сентября 2026) ------------------------------------
# Повод измерен в тот день: прямой прогон `backlog-recheck.sh` в оболочке владельца отвечал
# «7 инвариантов, все держатся», а тот же прогон с `env -i PATH=/usr/bin:/bin` — «? D12:
# 389 родителей не разобрать». В рамке периодического прогона python3 — это /usr/bin/python3
# (3.9.6, Xcode CLT) без PyYAML, а зависимость нигде не объявлена. Инвариант был непроверяем
# не «сегодня», а ПО УСТРОЙСТВУ — ровно там, где ходит сам.
#
# Фикстуры несут ПЯТЬ форм, СНЯТЫХ С ЖИВОЙ БАЗЫ, а не придуманных (pattern-fixture-form-not-
# taken-from-the-world): поточный список с парами, блочный список с комментарием между
# элементами, хвостовой комментарий после значения, поточное отображение с прозой в кавычках
# (запятые и двоеточия внутри), экранированная кавычка внутри двойных. Живой ~/.claude тест
# не читает (D403); паритет по всей базе мерился отдельно и дал 0 на 560 файлах.
F="$TMP/forms"; mkdir -p "$F"
cat > "$F/case-flow-pairs.md" << 'KF'
---
name: c
type: case
edges: [specializes: pattern-p.md, similar_to: case-x.md]
---
KF
cat > "$F/case-block-comment.md" << 'KF'
---
name: c
type: case
edges:
  - similar_to: case-a.md
  # пояснение между элементами — список на нём не кончается
  - specializes: pattern-p.md
---
KF
cat > "$F/case-trailing-comment.md" << 'KF'
---
name: c
type: case
edges:
  - led_to: case-b.md  # этот случай — продолжение
---
KF
cat > "$F/case-flow-map.md" << 'KF'
---
name: c
type: case
edges:
  - {type: similar_to, target: case-c.md, note: "проза с запятой, двоеточием: и словами"}
---
KF
cat > "$F/pattern-escaped.md" << 'KF'
---
name: p
type: pattern
source_cases: ["кейс прозой с \"кавычками\" внутри", case-a.md]
---
KF

# T7: два разбора совпадают на всех пяти формах
PARITY=$(python3 - "$F" << 'PYT7'
import os, sys
sys.path.insert(0, os.environ["LIB_DIR"])
import link_symmetry as ls
from pathlib import Path
diff = 0
for f in sorted(Path(sys.argv[1]).glob("*.md")):
    t = f.read_text()
    real, fb = ls._meta(t), ls._fallback_meta(ls.frontmatter(t))
    for k in ("source_cases", "edges"):
        if (real or {}).get(k) != (fb or {}).get(k):
            diff += 1
            print(f"{f.name}[{k}]: yaml={(real or {}).get(k)!r} fallback={(fb or {}).get(k)!r}", file=sys.stderr)
print(diff)
PYT7
)
assert_eq "$PARITY" "0" "T7: разбор без PyYAML совпадает с PyYAML на формах живой базы"

# T8: ответ инварианта одинаков с PyYAML и без него
mk_case "case-t8.md" "pattern-t8.md"
printf -- '---\nname: p\ntype: pattern\nsource_cases: []\n---\n' > "$L/pattern-t8.md"
BOTH=$(python3 - "$L" << 'PYT8'
import os, sys
sys.path.insert(0, os.environ["LIB_DIR"])
import link_symmetry as ls
a = ls.asymmetric(sys.argv[1])
ls.yaml = None
b = ls.asymmetric(sys.argv[1])
print("same" if a == b else f"diff {a} != {b}")
PYT8
)
assert_eq "$BOTH" "same" "T8: без PyYAML инвариант отвечает то же, а не «не проверено»"

# T9: КОНТРПРИМЕР — незнакомая форма даёт ОТКАЗ, а не догадку
printf -- '---\nname: p\ntype: pattern\nsource_cases: [case-a.md,\n  case-b.md]\n---\n' > "$F/pattern-multiline.md"
REFUSE=$(python3 - "$F/pattern-multiline.md" << 'PYT9'
import os, sys
sys.path.insert(0, os.environ["LIB_DIR"])
import link_symmetry as ls
print("отказ" if ls._fallback_meta(ls.frontmatter(open(sys.argv[1]).read())) is None else "разобрал")
PYT9
)
assert_eq "$REFUSE" "отказ" "T9: многострочная поточная форма — отказ, а не частичный разбор"

# T10: комментарий внутри блока не обрывает список (потерянный второй элемент)
N_EDGES=$(python3 - "$F/case-block-comment.md" << 'PYT10'
import os, sys
sys.path.insert(0, os.environ["LIB_DIR"])
import link_symmetry as ls
ls.yaml = None
print(len(ls._fallback_meta(ls.frontmatter(open(sys.argv[1]).read())).get("edges", [])))
PYT10
)
assert_eq "$N_EDGES" "2" "T10: комментарий между элементами список не кончает"

echo "link symmetry lib: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
