#!/usr/bin/env bash
# СУДИТ: hooks/lib/write_targets.py
# test_write_targets_cd_oracle.sh — эталон «куда команда пишет с учётом `cd`» (D1088, D1072).
#
# Результат: цели `targets` (по умолчанию) после разрешения от каталога запроса — ровно то, что создала команда, когда
#            её исполнил настоящий bash в песочнице; цели режима `--literal` — только созданное (призрака в карте нет).
# Проверка результата: bash hooks/tests/test_write_targets_cd_oracle.sh даёт 0
#
# Почему эталон, а не примеры: первая редакция D1088 прошла собственные примеры и упала на скептике (`cd` в `( … )`,
# `cd` из кавычек, `normpath` нелитерального каталога). Ожидаемых ответов в таблице нет — ответ даёт исполнение.
set -uo pipefail
LIB="$(cd "$(dirname "$0")/.." && pwd)/lib/write_targets.py"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/wt-cd-oracle.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

python3 -I - "$LIB" "$TMP" <<'PY'
import importlib.util, os, posixpath, subprocess, sys
spec = importlib.util.spec_from_file_location("wt", sys.argv[1]); wt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wt)
root = os.path.normpath(sys.argv[2])     # TMPDIR на macOS кончается «/»: без этого «//» в пути песочницы
PASS = FAIL = 0
def bad(tag, msg):
    global FAIL; FAIL += 1; print(f"FAIL [{tag}]: {msg}")

def world(n):
    d = os.path.join(root, f"w{n}")
    for p in ("w/sub/deep", "home/.claude/skills/pre", "abs"):
        os.makedirs(os.path.join(d, p))
    for f in ("w/a.txt", "w/m.txt"):
        open(os.path.join(d, f), "w").close()
    return d

def snapshot(d):
    out = set()
    for dp, dn, fn in os.walk(d):
        for x in dn + fn:
            out.add(os.path.join(dp, x))
    return out

def run(form, n):
    d = world(n); w, h, a = (os.path.join(d, x) for x in ("w", "home", "abs"))
    before = snapshot(d)
    subprocess.run(["bash", "-c", form], cwd=w, env={"PATH": os.environ["PATH"], "HOME": h, "ABS": a},
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    made = snapshot(d) - before
    leaves = {p for p in made if not any(q != p and q.startswith(p + "/") for q in made)}
    return w, h, a, leaves

def resolve(t, w, h, a):
    if t == "/dev/null":
        return None
    for k, v in (("~", h), ("$HOME", h), ("${HOME}", h), ("$ABS", a), ("${ABS}", a)):
        if t == k or t.startswith(k + "/"):
            t = v + t[len(k):]
            break
    if "$" in t:
        return "?" + t                              # каталог, неизвестный до исполнения
    return posixpath.normpath(t if t.startswith("/") else posixpath.join(w, t))

FORMS = [
    "cd sub && touch f", "cd sub; touch f", "cd ~/.claude/skills && mkdir x", "cd && touch f", "cd ~ && touch f",
    "(cd sub && touch f)", "(cd sub && touch f); touch g", "( cd sub; touch f ) && touch g",
    "cd nonexist 2>/dev/null || touch f", "cd sub || exit 1; touch f",
    'echo "x; cd sub; y" > o.txt', 'echo "a; cd sub; b" && touch f',
    "bash -c 'cd sub; touch f'", "bash -c 'cd sub' && touch f",
    "bash <<'X'\ncd sub\ntouch f\nX\ntouch g", "d=$(cd sub && pwd) && touch f",
    "if cd sub; then touch f; fi", "{ cd sub; touch f; }", "builtin cd sub && touch f", "command cd sub && touch f",
    "pushd sub >/dev/null && touch f && popd >/dev/null && touch g",
    "cd sub && cd deep && touch f", "cd sub && cd .. && touch f", "cd sub && cd - >/dev/null && touch f",
    'cd "$ABS" && touch f', "cd sub | true; touch f", "cd sub & wait; touch f",
    "cd sub && echo x > o.txt", "cd sub && cp ../a.txt b.txt", "cd sub && mv ../m.txt n.txt",
    "X=1 cd sub && touch f", "cd -P sub && touch f", "cd -- sub && touch f", "true && cd sub; touch f",
    "touch plain", "mkdir -p q/r", "echo x >> log.md",
    # раунд 2 скептика: `..` после `~` и ключи между `-c` и скриптом
    "cd ~/.claude/skills/pre && cd .. && mkdir y", "bash -c -- 'cd sub; touch f'", "bash -c -e 'cd sub; touch f'",
    # D1160, круг 2 скептика: `eval` — обёртка позиции команды, предел «eval cd X не раскрывается» снят
    "eval cd sub; touch f",
    # D1260: `<<` внутри кавычек heredoc не открывает — предел «echo 'x <<EOF' после cd» снят
    "cd sub && touch f; echo 'x <<EOF'",
]
LIMITS = [   # названные пределы `targets`: эталон и разбор ОБЯЗАНЫ расходиться; совпали — предел снят, перенеси форму
    "false && cd sub; touch f", "{ cd sub; } | cat; touch f",
    "(case a in a) cd sub;; esac); touch f", "f() { cd sub; }; touch f", "cd sub || { touch f; }",
]
n = 0
for form in FORMS:
    n += 1
    w, h, a, made = run(form, n)
    if not made:
        bad("таблица", f"форма ничего не создала — она ничего не судит: {form!r}"); continue
    got = {resolve(t, w, h, a) for t in wt.targets(form)} - {None}
    lit = {resolve(t, w, h, a) for t in wt.targets(form, literal=True)} - {None}
    if got != made:
        bad("полнота", f"{form!r}: создано {sorted(p[len(w)-1:] for p in made)}, разбор {sorted(got)}")
    elif not lit <= made:
        bad("призрак", f"{form!r}: --literal назвал несозданное {sorted(lit - made)}")
    else:
        PASS += 1
for form in LIMITS:
    n += 1
    w, h, a, made = run(form, n)
    got = {resolve(t, w, h, a) for t in wt.targets(form)} - {None}
    if got == made:
        bad("предел", f"предел снят — перенеси в таблицу: {form!r}")
    else:
        PASS += 1
# Нелитеральный каталог не нормализуется в литеральную цель (скептик D1088, находка 6).
for form in ('cd "$X" && cat >> ../S.md', "cd ~ && cd .. && cat >> S.md"):
    if wt.targets(form, literal=True):
        bad("нелитеральный", f"{form!r}: --literal дал {wt.targets(form, literal=True)}")
    else:
        PASS += 1
print(f"test_write_targets_cd_oracle: прошло {PASS}, упало {FAIL}")
sys.exit(1 if FAIL else 0)
PY
FAIL=$?
exit "$FAIL"
