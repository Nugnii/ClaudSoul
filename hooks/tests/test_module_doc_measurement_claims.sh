#!/usr/bin/env bash
# test_module_doc_measurement_claims.sh — заявленный период замера сверяется с реестром.
#
# Результат: модульный док не называет период, которого нет в scripts/measurements.tsv
# Проверка результата: bash hooks/tests/test_module_doc_measurement_claims.sh даёт 0
#
# Зачем (D108). Числа в документах выводит генератор и сверяет страж; прочие утверждения о
# том же дереве — нет, хотя выводимы механически. Видов таких утверждений в модульных доках
# четыре: счётные фразы, событие регистрации хука, присутствие файла в дереве, замер в
# реестре. Первые два сверяются (`test_derived_counts_inventory.sh`,
# `test_module_doc_registration_claims.sh`); здесь заводится третий.
#
# Почему отдельным стражем, а не веткой в соседнем: источник истины другой
# (`scripts/measurements.tsv` против `HOOKS_CONFIG` в `install.sh`), и общей логики разбора
# между ними нет. Одно имя на два разных предмета было бы хуже, чем два имени.
#
# ПРАВИЛО. Утверждение — пара «идентификатор замера в обратных кавычках» и «период N дней»
# в одном предложении. Идентификатор ищется в реестре, период сверяется с его столбцом.
#
# КОНТРПРИМЕР: предложение, называющее `scripts/measurements.tsv` БЕЗ идентификатора и без
# периода (`ablation-runner.md`: «строка в `scripts/measurements.tsv` — только с первой
# завершённой парой»), утверждением о периоде не является и не проверяется. Проверять там
# нечего: док говорит КОГДА строка появляется, а не какой у неё срок.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
REG="$REPO/scripts/measurements.tsv"
DOCS="$REPO/.claude-docs/modules"
[ -f "$REG" ] || { echo "FAIL: нет $REG"; exit 1; }
[ -d "$DOCS" ] || { echo "SKIP: нет $DOCS"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

python3 - "$REG" "$DOCS" <<'PY'
import re, sys, pathlib

reg_path, docs_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

# Реестр: идентификатор → период. Источник истины, а не копия в голове.
periods = {}
for line in reg_path.read_text(errors="replace").splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) >= 2 and parts[1].strip().isdigit():
        periods[parts[0].strip()] = int(parts[1].strip())

# Период относится к БЛИЖАЙШЕМУ названному перед ним замеру, а не к первому в предложении.
# Границей служит расстояние, а не вёрстка: предложение переносится на новую строку, и в
# одном могут стоять два замера с разными сроками («`docs-inventory` — период 7 дней,
# `docs-duplicates` — период 14»). Первая редакция резала по строкам и приписывала первый
# период обоим — предмет был задан вёрсткой, а не близостью.
ID = re.compile(r'`([a-z][a-z0-9-]{2,})`')
# `\w*` вместо диапазона `[а-я]`: в Python он юникодный и покрывает окончания, а
# диапазон кириллицы — известный источник поломок при переносе (страж отбил его
# на записи файла, и спорить с ним дешевле, чем доказывать, что тут Python).
PERIOD = re.compile(r'период\w*\s+(\d+)\s*дн')

WINDOW = 160          # символов назад — в пределах одной фразы, пусть и перенесённой

checked, bad, unknown = 0, [], []
for d in sorted(docs_dir.glob("*.md")):
    text = d.read_text(errors="replace")
    for pm in PERIOD.finditer(text):
        head = text[max(0, pm.start() - WINDOW):pm.start()]
        near = [i for i in ID.findall(head) if i in periods]
        if not near:
            # Период назван, а замера реестра рядом нет — утверждение есть, предмет его
            # неизвестен. Называем вслух, дефектом не считаем: период мог относиться к
            # другому (сроку возврата, окну замера).
            unknown.append((d.name, text[pm.start():pm.end() + 40].replace("\n", " ")[:70]))
            continue
        i = near[-1]          # ближайший названный перед периодом
        want = int(pm.group(1))
        checked += 1
        if periods[i] != want:
            bad.append((d.name, i, want, periods[i]))

print(f"утверждений о периоде замера проверено: {checked}, расходятся с реестром: {len(bad)}")
for doc, i, want, real in bad:
    print(f"  · {doc}: `{i}` заявлен с периодом {want} дн.; в реестре — {real}")
if unknown:
    print(f"  период назван без идентификатора реестра ({len(unknown)}) — предмет неизвестен:")
    for doc, s in unknown[:5]:
        print(f"    · {doc}: {s}")
if bad:
    print("  Утверждение о дереве пишется ИЗ дерева. Поправь док либо реестр.")
sys.exit(1 if bad else 0)
PY
