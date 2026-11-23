#!/usr/bin/env bash
# СУДИТ: hooks/git-stash-guard.sh hooks/rules-write-bypass.sh
# test_guard_generated_forms.sh — стражи команд на сгенерированных входах, а не только на вписанных руками.
#
# Результат: у стража трёх видов отказов нет: (1) равнозначная форма отвергнутой команды проходит;
#            (2) команда, лишь УПОМЯНУТАЯ (эхо, комментарий, данные heredoc), получает отказ;
#            (3) страж падает или виснет на мусоре. Каждый провал печатается с формой и приёмом.
# Проверка результата: bash hooks/tests/test_guard_generated_forms.sh даёт 0
#
# Зачем (18 ноября 2026, приём из статьи команды Claude Code о проверке: генерированные входы
# «не несут того же перекоса, что у автора кода»). Стражи R3 судят текст команды перечнем форм, и
# перечень в их тестах вписан тем же автором, что писал стража: форма, о которой автор не подумал,
# не попадает ни в код, ни в тест. Генератор комбинирует приёмы оболочки, сохраняющие смысл, и
# этим выходит за перечень автора.
#
# ВХОДЫ ДЕТЕРМИНИРОВАНЫ: зерно постоянное, прогон набора повторяем. Глубокий прогон — другое зерно
# и больше входов: GUARD_FORMS_SEED=<число> GUARD_FORMS_N=2000 bash <этот файл>.
#
# ИЗВЕСТНЫЕ ПРОПУСКИ называются ПРИЁМОМ в KNOWN ниже вместе с пунктом долга; такой пропуск печатается
# строкой «предел», а НОВЫЙ приём, давший пропуск, — провал. Приём, переставший давать пропуск,
# тоже провал: запись в KNOWN устарела и прячет починку.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export REPO TMP
mkdir -p "$TMP/home"   # песочница HOME для стражей: HOME= подменяется в вызове (python, env)
export GUARD_FORMS_N="${GUARD_FORMS_N:-20}" GUARD_FORMS_SEED="${GUARD_FORMS_SEED:-20261118}"

python3 - <<'PY'
import json, os, random, subprocess, sys, threading
from concurrent.futures import ThreadPoolExecutor

REPO, TMP = os.environ["REPO"], os.environ["TMP"]
N, SEED = int(os.environ["GUARD_FORMS_N"]), int(os.environ["GUARD_FORMS_SEED"])

GUARDS = {
    # Ядро — по одной команде на форму аргументов: перебор идёт ядро × приём, и цена набора — их произведение
    # (порог дорогого теста 20 с CPU, scripts/costly-tests.sh).
    "git-stash-guard.sh": ["git stash", "git stash pop", "git stash push -- a.txt"],
    "rules-write-bypass.sh": ["cp rules/CLAUDE.md ~/.claude/CLAUDE.md", "cat x > ~/.claude/CLAUDE.md",
                              'printf hi >> "$HOME/.claude/CLAUDE.md"'],
}
# (страж, приём) → пункт долга, где пропуск записан. Приём ложного отказа — шаблон упоминания.
# GUARD_FORMS_KNOWN=0 — строгий прогон без перечня: им судится пункт D1323.
# Пусто с 18 ноября 2026: 19 записей D1323 сняты починкой (цель записи и вызовы git называет владелец лексики).
KNOWN = {}

PROG = [("\\W", "\\{w}"), ('"W"', '"{w}"'), ("'W'", "'{w}'"), ("W''W", "{h}''{t}"), ("command W", "command {w}"),
        ("env W", "env {w}"), ("nice W", "nice {w}"), ("nohup W", "nohup {w}"), ("timeout 5 W", "timeout 5 {w}"),
        ("time W", "time {w}"), ("/usr/bin/W", "/usr/bin/{w}")]
PRE = ["true; ", "true && ", "false || ", "cd /tmp && ", "A=1 ", "2>/dev/null ", "true\n", ": ; "]
POST = ["; true", " || true", " &", " | cat", " 2>&1"]
# Подстановка с пробелом внутри: `x=$({})` поверх `( … )` даёт `$((` — арифметику, а не команду.
WRAP = ["( {} )", "{{ {}; }}", "x=$( {} )", "`{}`", "if true; then {}; fi", "for i in 1; do {}; done",
        "while false; do :; done; {}"]
INTERP = ["bash -c '{}'", "sh -c '{}'", "eval '{}'"]

def prog_fn(tpl):
    def f(c):
        w, _, rest = c.partition(" ")
        return tpl.format(w=w, h=w[0], t=w[1:]) + " " + rest
    return f

# (метка, приём, «слово программы»). Приём возвращает None, если к этой команде неприменим.
# Слово программы — первое слово ИСХОДНОЙ команды: после другого приёма первым стоит уже не оно.
TECH = ([("слово программы: " + lab, prog_fn(tpl), True) for lab, tpl in PROG]
        + [("перед: " + repr(p), (lambda p: lambda c: p + c)(p), False) for p in PRE]
        + [("после: " + repr(p), (lambda p: lambda c: c + p)(p), False) for p in POST]
        + [("обёртка: " + w, (lambda w: lambda c: w.format(c))(w), False) for w in WRAP]
        + [("интерпретатор: " + w, (lambda w: lambda c: None if "'" in c else w.format(c))(w), False) for w in INTERP]
        + [("пробел: " + repr(s), (lambda s: lambda c: c.replace(" ", s))(s), False) for s in ["  ", "\t"]]
        + [("перенос строки \\", lambda c: c.replace(" ", " \\\n", 1), False)])

MENTION = ['echo "{}"', "# {}", "printf '%s\\n' '{}'", "grep -n '{}' notes.txt", "cat <<'E'\n{}\nE"]
NOISE = ["'", '"', "$(", "`", "\\", "<<E", "a" * 200000, "ё" * 5000, "(" * 300, ";" * 2000,
         "git stash '", 'cat x > "~/.claude/CLAUDE.md', "$((", "${", "<<<", "\x01\x02", "git\x00stash"]

def call(guard, cmd):
    payload = json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
                          "tool_input": {"command": cmd}, "session_id": "gen"})
    # Свой каталог состояния у каждого потока: вызовы идут параллельно (8 потоков), вердикт — от команды.
    # HOME — песочница: страж судит текст команды, а читать живой ~/.claude тесту незачем (test_live_home_in_tests).
    env = dict(os.environ, STATE_DIR=os.path.join(TMP, f"state-{threading.get_ident()}"), HOME=os.path.join(TMP, "home"))
    try:
        p = subprocess.run(["bash", os.path.join(REPO, "hooks", guard)], input=payload.encode(),
                           capture_output=True, timeout=10, env=env)
    except subprocess.TimeoutExpired:
        return "timeout", ""
    out = p.stdout.decode(errors="replace").strip()
    if p.returncode != 0: return f"rc={p.returncode}", out
    if not out: return "silent", out
    try: d = json.loads(out)
    except ValueError: return "badjson", out
    return ("deny" if (d.get("hookSpecificOutput") or {}).get("permissionDecision") == "deny" else "hint"), out

# Входы собираются целиком (порядок и зерно — как без потоков), исполняются параллельно, судятся по порядку.
cases = []   # (вид, страж, команда, приёмы | шаблон упоминания)
for guard, cores in GUARDS.items():
    # Слой 1 — полный перебор: каждый приём один на каждой команде. Детерминирован: по нему
    # судится, жива ли запись KNOWN (по случайной выборке «не выпал» неотличимо от «починен»).
    for core in cores:
        for lab, fn, _ in TECH:
            c = fn(core)
            if c is not None: cases.append(("form", guard, c, [lab]))
    # Слой 2 — случайные сочетания 2–3 приёмов: то, чего перебор по одному не покрывает.
    r = random.Random(f"{SEED}:{guard}")
    for _ in range(N):
        c, steps = r.choice(cores), []
        for _ in range(r.randint(2, 3)):
            lab, fn, is_prog = r.choice(TECH)
            if is_prog and steps: continue
            c2 = fn(c)
            if c2 is not None: c, steps = c2, steps + [lab]
        if len(steps) >= 2: cases.append(("form", guard, c, steps))
    for core in cores:
        for m in MENTION:
            if '"' in core and m.startswith("echo"): continue
            if "'" in core and "'" in m: continue
            cases.append(("mention", guard, m.format(core), m))
    for z in NOISE:
        cases.append(("noise", guard, z, None))

with ThreadPoolExecutor(8) as ex:
    results = list(ex.map(lambda cs: call(cs[1], cs[2]), cases))

fail, known_hit, live, seen = [], {}, set(), len(cases)
for (kind, guard, c, meta), (verdict, out) in zip(cases, results):
    if kind == "form" and verdict != "deny":
        hit = next(((guard, s) for s in meta if (guard, s) in KNOWN), None)
        if hit: known_hit[hit] = known_hit.get(hit, 0) + 1
        else: fail.append(f"[пропуск] {guard} ({verdict}): {c!r} — приёмы: {' → '.join(meta)}")
        if len(meta) == 1: live.add((guard, meta[0]))
    elif kind == "mention" and verdict == "deny":
        live.add((guard, meta))
        if (guard, meta) in KNOWN: known_hit[(guard, meta)] = known_hit.get((guard, meta), 0) + 1
        else: fail.append(f"[ложный отказ] {guard}: {c!r}")
    elif kind == "noise" and (verdict in ("timeout", "badjson") or verdict.startswith("rc=")):
        fail.append(f"[падение] {guard} ({verdict}): {c[:60]!r} — {out[:120]!r}")

for (g, step), n in sorted(known_hit.items()):
    print(f"предел: {g} — {n} провал(ов) приёма {step!r} — {KNOWN[(g, step)]}")
for key in KNOWN:
    if key not in live:
        fail.append(f"[устарел KNOWN] {key[0]}: приём {key[1]!r} провалов не дал — снять запись ({KNOWN[key]})")
for f in fail: print("FAIL", f)
print(f"входов {seen}, провалов {len(fail)}, зерно {SEED}")
sys.exit(1 if fail else 0)
PY
FAIL=$?
exit $(( FAIL != 0 ))
