#!/usr/bin/env bash
# docs-refresh-claims.sh — числа в документах состояния считаются реестром, а не помнятся.
#
# Результат: каждое число документа состояния, записанное в scripts/doc-claims.tsv, равно
#            нынешнему значению своей команды (scripts/doc-figures.sh <ключ>)
# Проверка результата: bash scripts/docs-refresh-claims.sh --check даёт 0, когда ни одно
#            утверждение с доступным источником не разошлось с миром
#
# Зачем (30 августа 2026). Перед релизом v1.31.0 стояли шесть стражей документации, и все
# проверяли ФОРМУ: версия в семье документов, автотаблицы, одна сгенерированная строка,
# живые ссылки, дубли, индекс зависимостей. Правду чисел в прозе не проверял никто — у них
# не было команды. README ушёл наружу со 176 находками при 185, 52 хуками при 54, «пять
# хуков прерывают» при девяти. Владелец: «какого хера перед пушем не проверяется актуальность
# документации?». Тот же класс, что показания бэклога (D210): вписанное рукой устаревает в
# ту же секунду; ответ тот же — число объявляет команду, механизм подставляет и сверяет.
#
# ФОРМА. Строка реестра: файл, регулярное выражение с одной группой, ключ величины, формат,
# описание. `run` подставляет значение в группу первого совпадения; `--check` только
# сравнивает и называет расхождения (код 1). Ключ с источником, недоступным на этой машине
# (`n/a` — чужая машина, CI без базы знаний), пропускается и называется: это не расхождение.
#
# ГДЕ СТОИТ. `--check` зовут страж бампа версии (hooks/docs-family-check.sh, путь A) и гейт
# публикации (scripts/publish-public.sh, шаг 3c) — документ с устаревшим числом ни в релиз,
# ни наружу не уходит. Реестр замеров: `doc-claims` (7).
#
# НАЗВАННЫЙ ПРЕДЕЛ. Реестр держит числа и даты, а не смысл фраз: утверждение «blocker не
# останавливает вызов» без числа реестром не ловится — его ловит только сверка описания с
# кодом (аудит доков модулей и шапок). Условие снятия: у утверждений о поведении появится
# машинный носитель (например, тест, названный в строке реестра как источник истины).
# КОНТРПРИМЕР: регулярное выражение, не нашедшее совпадения, — не тишина, а находка
# («утверждение исчезло из документа»): реестр без своего места в тексте есть мёртвая строка.
set -uo pipefail

MODE="${1:-run}"
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
CLAIMS="${DOC_CLAIMS_FILE:-$REPO/scripts/doc-claims.tsv}"
FIGURES="${DOC_FIGURES:-$REPO/scripts/doc-figures.sh}"
[ -f "$CLAIMS" ] || { echo "нет реестра $CLAIMS" >&2; exit 0; }
[ -f "$FIGURES" ] || { echo "нет $FIGURES" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "нужен python3" >&2; exit 0; }

REPO_DIR="$REPO" CLAIMS_FILE="$CLAIMS" FIGURES_SH="$FIGURES" MODE="$MODE" python3 - <<'PY'
import os, re, subprocess, sys, pathlib
repo = pathlib.Path(os.environ["REPO_DIR"]); mode = os.environ["MODE"]
rows, broken = [], []
for lineno, line in enumerate(open(os.environ["CLAIMS_FILE"], encoding="utf-8"), 1):
    if not line.strip() or line.startswith("#"): continue
    parts = line.rstrip("\n").split("\t")
    # Ровно пять полей: лишний таб сдвигал ключ в «», и строка тихо уходила в «пропущено».
    if len(parts) != 5 or not all(parts[:3]):
        broken.append(f"строка {lineno}: полей {len(parts)}, а не 5 — {line.strip()[:80]}"); continue
    rows.append(parts)

cache = {}
def figure(key):
    if key not in cache:
        r = subprocess.run(["bash", os.environ["FIGURES_SH"], key], capture_output=True, text=True, timeout=120)
        cache[key] = (r.stdout or "").strip()
    return cache[key]

def fmt(v, f):
    if f == "comma": return v.replace(".", ",")
    if f == "thousands_comma": return f"{int(v):,}"
    if f == "thousands_space": return f"{int(v):,}".replace(",", " ")
    return v

drift, skipped, missing, changed = [], [], [], {}
texts = {}
for file, rx, key, f, note in rows:
    path = repo / file
    if not path.is_file():
        missing.append(f"{file}: файла нет"); continue
    text = texts.get(file) or path.read_text(encoding="utf-8")
    m = re.search(rx, text, re.M)
    if not m:
        missing.append(f"{file}: выражение не нашло места в тексте — «{note}» ({rx})"); continue
    val = figure(key)
    if val == "err":
        missing.append(f"{file}: «{note}» — источник {key} есть, но числа не дал (форма итога не разобрана)"); continue
    if val in ("", "n/a"):
        skipped.append(f"{file}: «{note}» — источник {key} недоступен здесь"); continue
    want = fmt(val, f)
    have = m.group(1)
    if have == want: continue
    drift.append(f"{file}: «{note}» — в документе {have}, в мире {want}")
    if mode != "--check":
        text = text[:m.start(1)] + want + text[m.end(1):]
        texts[file] = text; changed[file] = changed.get(file, 0) + 1
    else:
        texts[file] = text

for file, t in texts.items():
    if file in changed: (repo / file).write_text(t, encoding="utf-8")

if broken:
    print(f"сломанных строк реестра: {len(broken)}")
    for b in broken: print(f"  · {b}")
if skipped:
    print(f"пропущено (источник недоступен): {len(skipped)}")
    for s in skipped[:12]: print(f"  · {s}")
if missing:
    print("утверждения без места в документе (реестр устарел или текст переписан):")
    for s in missing: print(f"  · {s}")
if mode == "--check":
    if drift:
        print("числа документов разошлись с миром:")
        for d in drift: print(f"  · {d}")
    if drift or missing or broken:
        print("[замер: находки, не сбой] правь: bash scripts/docs-refresh-claims.sh run (реестр — scripts/doc-claims.tsv)")
        sys.exit(1)
    print(f"утверждения документов совпадают с миром: проверено {len(rows) - len(skipped)}")
    sys.exit(0)
if changed:
    print("подставлено: " + ", ".join(f"{k} ×{v}" for k, v in changed.items()))
    for d in drift: print(f"  · {d}")
else:
    print(f"обновлять нечего: проверено {len(rows) - len(skipped)}, всё совпадает")
sys.exit(1 if (missing or broken) else 0)
PY
