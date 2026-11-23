#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py scripts/dep-index.py hooks/lib/project_map.py
# probe_D1286 — карта связей (`code_lines`) и учёт (`code_only`) решают «проза ли строка питона» разборщиком
# (`project_map.py_prose_rows`), а не счётом тройных кавычек: строка, начатая ЗАКРЫВАЮЩЕЙ `'''` многострочного
# литерала, — не начало докстринга, и код ниже неё остаётся кодом. Повод (9 ноября 2026, скептик opus по 014f6455,
# D1265): у Jurnalist `tests/conftest.py:119` — закрывающая `'''` SQL-литерала, и строки 119–525 выпадали вместе с
# рёбрами; замер 10 ноября 2026 на копии: conftest назван тестом у 0 механизмов, после починки — у 5 (корень R3).
# Положительный контроль: докстринг (тройная кавычка, открывающая строку) прозой остаётся у обоих.
# Красная (1), пока код после закрывающей кавычки теряется; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
for f in scripts/project-graph.py scripts/dep-index.py hooks/lib/project_map.py; do [ -f "$R/$f" ] || exit 2; done
command -v python3 >/dev/null 2>&1 || exit 2
python3 - "$R" <<'PY'
import importlib.util, sys
R = sys.argv[1]
sys.argv = [sys.argv[0]]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
try:
    pg = load("pg_probe", R + "/scripts/project-graph.py")
    di = load("di_probe", R + "/scripts/dep-index.py")
except BaseException as e:
    print("рамка: прибор не загрузился:", repr(e)[:200], file=sys.stderr); sys.exit(2)
text = "\n".join([
    '"""Докстринг: здесь test_doc_only.py — проза."""',
    "def setup():",
    "    conn.execute('''",
    "        CREATE TABLE t (x)",
    "    ''')",
    "    conn.commit()",
    "QUARANTINE = ['tests/test_after_literal.py']",
    '"""',
    "многострочный докстринг test_doc_multi.py",
    '"""',
    "run('tests/test_tail.py')",
])
bad = 0
for name, fn in (("code_lines", pg.code_lines), ("code_only", di.code_only)):
    out = fn(text, True)
    if "test_doc_only" in out or "test_doc_multi" in out:
        print("рамка: %s оставил докстринг кодом — положительный контроль не прошёл" % name, file=sys.stderr); sys.exit(2)
    for want in ("test_after_literal.py", "test_tail.py", "conn.commit()"):
        if want not in out:
            print("%s потерял код после закрывающей кавычки: нет %s" % (name, want)); bad = 1
if pg.code_lines(text, True) != di.code_only(text, True):
    print("двойники разошлись: code_lines ≠ code_only"); bad = 1
sys.exit(bad)
PY
