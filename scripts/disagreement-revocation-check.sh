#!/usr/bin/env bash
# disagreement-revocation-check.sh — журнал контура пишется одним форматом, и каждый отзыв
# суждения имеет ровно один сопоставимый оригинал.
#
# Результат: у долговременного журнала один писатель по форме — всякая строка компактна и
#            несёт известный набор полей; отзыв (`supersedes`) сопоставим с оригиналом
# Проверка результата: bash scripts/disagreement-revocation-check.sh check даёт 0
#
# Зачем (D254). У контура нет отмены: `knowledge-counter-bump.sh` знает только приращения
# (`confirmed_count++`, `contradicted_count++`), пути уменьшения нет ни одного. Отзыв
# суждения поэтому делался РУКОЙ, и рука писала в своём формате: 56 строк от 2026-08-08
# несут пробел после двоеточия, тогда как писатель (`dis_close_outcome`) печатает компактно.
#
# Цена измерена 1 сентября 2026. Формат журнала нигде не объявлен — он живёт литералом в
# одном printf и в пяти grep/awk читателей. Поэтому `grep '"outcome":"'` находил 198 строк
# из 254 и не видел отзывов ВООБЩЕ (metrics-collector.sh:585,604), а jq-читатели видели все
# 254 и считали оригинал вместе с его отзывом (five-whys-gate.sh, injection-outcome.sh).
# Два класса читателей одного журнала видели разные миры; доля «знание не к месту» читалась
# 43% при живых 52%, и прибор молчал там, где обязан был дать находку.
#
# КОНТРПРИМЕР: строка с полем `supersedes` — НЕ нарушение формата сама по себе. Нарушение —
# написание с пробелом после двоеточия и набор полей вне известных.
set -uo pipefail
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
JOURNAL="${DIS_JOURNAL:-$STATE/disagreement-outcomes.jsonl}"
MODE="${1:-check}"

# Режим сверяется с перечнем: неизвестное значение НЕ означает умолчание (тот же страж, что
# у соседей по семейству — см. hooks/tests/test_mode_arg_guard.sh).
case "$MODE" in
    check|--check) MODE=check ;;
    *) echo "применение: $(basename "$0") [check]" >&2; exit 2 ;;
esac

[ -f "$JOURNAL" ] || { echo "журнала ещё нет: $JOURNAL"; exit 0; }
# Без python3 журнал не разобрать — код 2, а не 0: нулевой код выдавал журнал с нарушением
# формата за единый (прожарка 13 сентября 2026, атака 2).
command -v python3 >/dev/null 2>&1 || { echo "disagreement-revocation-check: нужен python3 — не измерено" >&2; exit 2; }

JOURNAL="$JOURNAL" python3 - <<'PY'
import os, json, re, sys, collections

path = os.environ["JOURNAL"]
raw = [l.rstrip("\n") for l in open(path, errors="replace") if l.strip()]

KNOWN = {
    frozenset(("date", "session", "knowledge", "confidence", "outcome", "case")),
    frozenset(("date", "session", "knowledge", "confidence", "outcome", "case",
               "supersedes", "note")),
}

broken, spaced, unknown = [], [], []
rows = []
for i, line in enumerate(raw, 1):
    try:
        r = json.loads(line)
    except ValueError:
        broken.append(i)
        continue
    rows.append((i, r))
    # Признак второго писателя: пробел после двоеточия ключа. Компактную печать даёт
    # `dis_close_outcome`; всё прочее пришло не от него.
    if re.search(r'":\s', line):
        spaced.append(i)
    if frozenset(r.keys()) not in KNOWN:
        unknown.append((i, ",".join(sorted(r.keys()))))

# Отзыв обязан иметь ровно один более ранний оригинал: та же (knowledge, session) и исход,
# равный полю supersedes. Иначе «отменено» не значит ничего.
consumed, unmatched = set(), []
for i, r in rows:
    if "supersedes" not in r:
        continue
    hit = None
    for j, x in rows:
        if j in consumed or "supersedes" in x:
            continue
        if (x.get("knowledge") == r.get("knowledge")
                and x.get("session") == r.get("session")
                and x.get("outcome") == r.get("supersedes")
                and x.get("date", "") < r.get("date", "")):
            hit = j
            break
    if hit:
        consumed.add(hit)
    else:
        unmatched.append(i)

revs = sum(1 for _, r in rows if "supersedes" in r)
print(f"журнал контура: {len(raw)} строк, отзывов {revs}")
bad = 0
if broken:
    print(f"  битых строк JSON: {len(broken)} (строки {broken[:5]})"); bad += 1
if spaced:
    print(f"  строк в ЧУЖОМ формате (пробел после двоеточия): {len(spaced)}")
    print(f"    первые: {spaced[:5]} — их не видит ни один грепающий читатель")
    bad += 1
if unknown:
    print(f"  строк с неизвестным набором полей: {len(unknown)}")
    for i, k in unknown[:3]:
        print(f"    строка {i}: {k}")
    bad += 1
if unmatched:
    print(f"  отзывов без сопоставимого оригинала: {len(unmatched)} (строки {unmatched[:5]})")
    bad += 1
if not bad:
    print("  формат един, отзывы сопоставлены")
raise SystemExit(1 if bad else 0)
PY
