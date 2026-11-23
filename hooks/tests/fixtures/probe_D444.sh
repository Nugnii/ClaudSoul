#!/usr/bin/env bash
# СУДИТ: scripts/ablation/sampler.py scripts/defect-class-carriers.py scripts/docs-address-drift.py scripts/five-whys-attribution-replay.py scripts/self-repeat-replay.py scripts/signal-precision-corpus.py
# probe_D444.sh — проба кандидата D444 (C7): питоновы приборы-замеры глотают отказ чтения
# без счётчика — `except OSError: continue/return` в scripts/signal-precision-corpus.py
# (:84,:280,:380), scripts/five-whys-attribution-replay.py (:71), scripts/self-repeat-replay.py
# (:78), scripts/docs-address-drift.py (:102), scripts/defect-class-carriers.py (:560); родственно —
# scripts/ablation/sampler.py, где отсутствие journal.jsonl (:88-90) неотличимо от «журнал есть,
# все решения сошлись» (:cmd_verify, exit 0 в обоих случаях).
# Результат: нечитаемый файл на входе (chmod 000) даёт РОВНО ТОТ ЖЕ результат/stderr, что
#            чистый корпус без него — отказ чтения не назван нигде и не увеличил счётчика.
# Проверка результата: bash hooks/tests/fixtures/probe_D444.sh даёт 0
#
# Коды: 0 — носителей с симптомом 0; 1 — дефект наблюдён (стдерр называет носителей и число);
# 2 — рамка не собралась (стдерр называет, чего не хватает).
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой),
# собственный корень — от пути этого файла. Живой ~/.claude не читается — только mktemp -d.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
for f in scripts/signal-precision-corpus.py scripts/five-whys-attribution-replay.py \
         scripts/self-repeat-replay.py scripts/docs-address-drift.py \
         scripts/defect-class-carriers.py scripts/ablation/sampler.py; do
    [ -f "$MECH/$f" ] || { echo "probe_D444: нет $MECH/$f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "probe_D444: нужен python3" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D444: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

cat > "$T/check.py" <<'PY'
import importlib.util, os, sys, io, contextlib, hashlib, hmac, json, shutil

MECH = sys.argv[1]
T = sys.argv[2]

def load(name, relpath):
    p = os.path.join(MECH, relpath)
    spec = importlib.util.spec_from_file_location(name, p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def capture(fn, *a, **kw):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            r = fn(*a, **kw)
            ok = True
        except SystemExit as e:
            r, ok = e.code, True
        except Exception as e:
            r, ok = f"{type(e).__name__}: {e}", False
    return ok, r, out.getvalue(), err.getvalue()

results = []  # (name, symptom_present: bool, detail)

def report(name, symptom, detail):
    results.append((name, symptom, detail))
    print(f"CARRIER {name}: SYMPTOM={'1' if symptom else '0'} — {detail}")

def report_named(name, err_bad, err_clean, bad_name="bad", good_name="good"):
    """Симптом = отказ НЕ назван ЛИБО назван кто попало.

    Прежний предикат спрашивал одно: встретилось ли имя плохого файла в stderr. Скептик
    19 сентября 2026 позеленил им починку, которая печатает имя ВСЕГДА, перед каждым
    `open()`, а `except` оставляет глотающим: 7 носителей из 8 охранялись свидетелем,
    принимающим пустышку. Теперь нужны ОБА конца: на плохом файле отказ назван, на ЧИСТОМ
    прогоне прибор молчит. «Назвал всех подряд» — уже не починка.
    """
    named = bad_name in err_bad
    quiet_when_clean = good_name not in err_clean
    symptom = (not named) or (not quiet_when_clean)
    detail = f"назван={named} молчит_на_чистом={quiet_when_clean} stderr_bad={err_bad!r:.120} stderr_clean={err_clean!r:.80}"
    report(name, symptom, detail)

def assert_unreadable(path):
    # chmod 000 под root игнорируется файловой системой — тогда open() не бросит,
    # и весь корпус читается «чисто»: симптом не проверится ни на одном носителе,
    # а нули дадут вид «дефекта нет». Рамка тогда НЕ собралась — код 2, не 0.
    try:
        open(path).read()
    except OSError:
        return
    print(f"probe_D444: chmod 000 не подействовал (root?): {path}", file=sys.stderr)
    sys.exit(2)

# ── фикстуры: файл good читается, файл bad — chmod 000 ──────────────────────
corpus = os.path.join(T, "corpus")
os.makedirs(corpus, exist_ok=True)
with open(os.path.join(corpus, "good.jsonl"), "w") as f:
    f.write(json.dumps({"message": {"role": "assistant", "content": [
        {"type": "tool_use", "name": "Bash", "input": {"command": "git status"}}]}}) + "\n")
bad_jsonl = os.path.join(corpus, "bad.jsonl")
open(bad_jsonl, "w").close()
os.chmod(bad_jsonl, 0)
assert_unreadable(bad_jsonl)

lessons = os.path.join(T, "lessons")
os.makedirs(lessons, exist_ok=True)
with open(os.path.join(lessons, "pattern-good.md"), "w") as f:
    f.write('outcome_signals:\n  - "тестовая фраза"\nконец\n')
bad_md = os.path.join(lessons, "pattern-bad.md")
with open(bad_md, "w") as f:
    f.write('outcome_signals:\n  - "недостижимая"\nконец\n')
os.chmod(bad_md, 0)
assert_unreadable(bad_md)

# ЧИСТЫЙ КОРПУС — ВТОРОЙ КОНЕЦ КАЖДОГО ПРЕДИКАТА. На нём прибор обязан МОЛЧАТЬ: иначе
# «печатаю имя всегда» проходило бы за починку (скептик, 19 сентября 2026).
clean = os.path.join(T, "clean")
os.makedirs(clean, exist_ok=True)
shutil.copy(os.path.join(corpus, "good.jsonl"), os.path.join(clean, "good.jsonl"))
clean_lessons = os.path.join(T, "clean-lessons")
os.makedirs(clean_lessons, exist_ok=True)
shutil.copy(os.path.join(lessons, "pattern-good.md"), os.path.join(clean_lessons, "pattern-good.md"))

# ── 1-3: signal-precision-corpus.py ──────────────────────────────────────────
spc = load("spc", "scripts/signal-precision-corpus.py")
spc.CORPUS = corpus
ok, r, out, err_bad = capture(lambda: list(spc.calls()))
spc.CORPUS = clean
ok, r, out, err_clean = capture(lambda: list(spc.calls()))
report_named("signal-precision-corpus.py:84 calls()", err_bad, err_clean)
spc.CORPUS = corpus
ok, r, out, err_bad = capture(lambda: list(spc.turn_texts()))
spc.CORPUS = clean
ok, r, out, err_clean = capture(lambda: list(spc.turn_texts()))
report_named("signal-precision-corpus.py:380 turn_texts()", err_bad, err_clean)
ok, r, out, err_bad = capture(spc.outcome_phrases, lessons_dir=lessons)
ok, r, out, err_clean = capture(spc.outcome_phrases, lessons_dir=clean_lessons)
report_named("signal-precision-corpus.py:280 outcome_phrases()", err_bad, err_clean)

# ── 4: five-whys-attribution-replay.py ───────────────────────────────────────
fwr = load("fwr", "scripts/five-whys-attribution-replay.py")
ok, r, out, err_bad = capture(fwr.turn_texts, bad_jsonl)
ok, r, out, err_clean = capture(fwr.turn_texts, os.path.join(clean, "good.jsonl"))
report_named("five-whys-attribution-replay.py:71 turn_texts()", err_bad, err_clean)

# ── 5: self-repeat-replay.py ──────────────────────────────────────────────────
srr = load("srr", "scripts/self-repeat-replay.py")
ok, r, out, err_bad = capture(srr.turns, bad_jsonl)
ok, r, out, err_clean = capture(srr.turns, os.path.join(clean, "good.jsonl"))
report_named("self-repeat-replay.py:78 turns()", err_bad, err_clean)

# ── 6: defect-class-carriers.py ───────────────────────────────────────────────
dcc = load("dcc", "scripts/defect-class-carriers.py")
from pathlib import Path
dcc.tracked = lambda *a, **kw: [Path(os.path.join(lessons, "pattern-good.md")), Path(bad_md)]
ok, r, out, err_bad = capture(dcc._prose_corpus)
dcc.tracked = lambda *a, **kw: [Path(os.path.join(clean_lessons, "pattern-good.md"))]
ok, r, out, err_clean = capture(dcc._prose_corpus)
report_named("defect-class-carriers.py:560 _prose_corpus()", err_bad, err_clean)

# ── 7: docs-address-drift.py (git полностью замокан) ─────────────────────────
docsrepo = os.path.join(T, "docsrepo")
os.makedirs(docsrepo, exist_ok=True)
with open(os.path.join(docsrepo, "referenced.py"), "w") as f:
    f.write("line1\nline2 anchor\nline3\n")
with open(os.path.join(docsrepo, "good.md"), "w") as f:
    f.write("# doc\n\nсмотри referenced.py:2\n")
bad_doc = os.path.join(docsrepo, "bad.md")
with open(bad_doc, "w") as f:
    f.write("# doc\n\nсмотри referenced.py:2\n")
os.chmod(bad_doc, 0)
assert_unreadable(bad_doc)

os.environ["CLAUDSOUL_REPO"] = docsrepo
dad = load("dad", "scripts/docs-address-drift.py")
ref_content = open(os.path.join(docsrepo, "referenced.py")).read()

def fake_git(*args):
    if args and args[0] == "ls-files":
        return "\0".join(fake_git.files) + "\0"
    if args and args[0] == "diff":
        return ""
    if args and args[0] == "log":
        return "deadbeef\n"
    if args and args[0] == "show":
        return ref_content
    return ""

dad.git = fake_git
fake_git.files = ["good.md", "bad.md", "referenced.py"]
ok, r, out, err = capture(dad.main)
# ЗДЕСЬ ОБЕЩАНА КОПИЛКА, А НЕ ЛЮБОЙ КАНАЛ. Пункт D444 говорит: у этого прибора пропуск
# уходит в уже существующий `unjudged` — значит и судить надо блок «НЕ СУДИЛОСЬ», а не
# факт упоминания имени где угодно. Прежний предикат принимал и stderr, и тогда «уплывших:
# 0» в stdout осталось бы ровно тем, чем было до D414 (скептик, 19 сентября 2026).
_in_unjudged = "НЕ СУДИЛОСЬ" in out and "bad.md" in out.split("НЕ СУДИЛОСЬ", 1)[-1]
report("docs-address-drift.py:102 main()", not _in_unjudged,
       f"rc={r!r} в_копилке={_in_unjudged} stdout={out!r:.200}")

# ── 8: ablation/sampler.py — «журнала нет» неотличимо от «журнал есть, всё сошлось» ──
salt_path = os.path.join(T, "ablation-salt.txt")
with open(salt_path, "wb") as f:
    f.write(b"probe-d444-salt")
os.environ["ABLATION_SALT"] = salt_path
os.environ["ABLATION_COMMITMENT"] = hashlib.sha256(b"probe-d444-salt").hexdigest()
sampler = load("sampler", "scripts/ablation/sampler.py")

abl_empty = os.path.join(T, "abl_empty")
os.makedirs(abl_empty, exist_ok=True)
os.environ["ABLATION_DIR"] = abl_empty
ok, r_missing, out_missing, err_missing = capture(sampler.cmd_verify, None)

# ТРЕТЬЕ СОСТОЯНИЕ: журнал ЕСТЬ и ПУСТ. Без него проба принимала починку, ключённую на
# пустоте (`if not events: exit 2`), — а она лишь переносит смешение: «журнала нет» и
# «журнал есть, но пуст» снова отвечали бы одним кодом (скептик, 19 сентября 2026).
abl_blank = os.path.join(T, "abl_blank")
os.makedirs(abl_blank, exist_ok=True)
open(os.path.join(abl_blank, "journal.jsonl"), "w").close()
os.environ["ABLATION_DIR"] = abl_blank
ok, r_blank, out_blank, err_blank = capture(sampler.cmd_verify, None)
os.environ["ABLATION_DIR"] = abl_empty

abl_full = os.path.join(T, "abl_full")
os.makedirs(abl_full, exist_ok=True)
salt = open(salt_path, "rb").read()
task_id, output_hex = "task-1", "00" * 32
pulse = {"timeStamp": "2026-01-01T00:00:00Z", "outputValue": output_hex, "statusCode": 0}
with open(os.path.join(abl_full, f"beacon-{task_id}.json"), "w") as f:
    json.dump(pulse, f)
msg = b"claudsoul-ablation-v1\x00" + task_id.encode() + b"\x00" + bytes.fromhex(output_hex)
r = hmac.new(salt, msg, hashlib.sha256).digest()
selected = int.from_bytes(r, "big") % 4 == 0
with open(os.path.join(abl_full, "journal.jsonl"), "w") as f:
    f.write(json.dumps({"e": "sampler", "id": task_id, "selected": selected}) + "\n")
os.environ["ABLATION_DIR"] = abl_full
ok, r_full, out_full, err_full = capture(sampler.cmd_verify, None)

# Предмет — НЕРАЗЛИЧИМОСТЬ двух состояний («журнала нет» / «журнал есть, всё сошлось»),
# а не факт, что оба кода нулевые: сравнение с нулём засчитало бы починку, которая всегда
# отдаёт код 2 (журнал прочитать не смог НИКОГДА), как «дефекта нет».
symptom_sampler = (r_missing == r_full) or (r_missing == r_blank)
report("ablation/sampler.py cmd_verify() без журнала", symptom_sampler,
       f"rc(нет журнала)={r_missing!r} rc(журнал есть, сошлось)={r_full!r} rc(журнал есть и пуст)={r_blank!r}")

total = sum(1 for _, s, _ in results if s)
print(f"TOTAL={total}")
sys.exit(0 if total == 0 else 1)
PY

OUT=$(python3 "$T/check.py" "$MECH" "$T" 2>&1)
RC=$?
echo "$OUT" >&2
if [ "$RC" -eq 0 ]; then
    exit 0
fi
if [ "$RC" -ge 2 ]; then
    echo "probe_D444: рамка не собралась (см. вывод выше)" >&2
    exit 2
fi
N=$(grep -oE 'TOTAL=[0-9]+' <<< "$OUT" | grep -oE '[0-9]+' | tail -1)
if [ -z "$N" ]; then
    echo "probe_D444: рамка не собралась — прибор под судом упал прежде TOTAL (см. вывод выше)" >&2
    exit 2
fi
echo "probe_D444: дефект — носителей с симптомом: ${N}" >&2
exit 1
