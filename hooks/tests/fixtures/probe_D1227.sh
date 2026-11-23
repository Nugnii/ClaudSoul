#!/usr/bin/env bash
set -u
# СУДИТ: scripts/defect-class-carriers.py
# probe_D1227 — признак рода H («общее состояние переписывается без замка») не называет носителем три формы, где
#   потерянной записи быть не может, и называет настоящий носитель. Рамка настоящая: прибор родов (`carriers_h`) на
#   песочном git-дереве из пяти файлов:
#   · отметка, прочитанная только в условии `[ "$(cat "$F")" = … ]`, перезаписана значением не из прочитанного;
#   · питон, напечатанный `printf` внутри строки (`printf 'python3 - … <<PYY\n'`) — данные, а не код файла;
#   · фикстура pytest (`tmp_path`) — личный каталог теста;
#   · контроль: общий файл читается и переписывается без замка (`cat "$F" | sort > "$t"; mv "$t" "$F"`) и тот же
#     питон в настоящем heredoc — оба носители.
#   0 — три формы не названы, оба контроля названы; 1 — названа ложная форма либо пропущен контроль; 2 — нет прибора
#   или он не отработал на песочном дереве.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
REG="$PWD/scripts/defect-class-carriers.py"
[ -f "$REG" ] || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
R="$W/r"; mkdir -p "$R/hooks/tests" "$R/mcp-server/tests"
cat > "$R/hooks/seen.sh" <<'EOF'
#!/usr/bin/env bash
SEEN="$STATE_DIR/shot-seen-$SID"
[ "$(cat "$SEEN" 2>/dev/null)" = "$RUN" ] && exit 0
printf '%s\n' "$RUN" > "$SEEN" 2>/dev/null
EOF
cat > "$R/hooks/tests/test_printed.sh" <<'EOF'
#!/usr/bin/env bash
gen() {
    {
        printf 'python3 - "$D/x" <<PYY\n'
        printf 'p = sys.argv[1]\n'
        printf 's = open(p, encoding="utf-8").read()\n'
        printf 'open(p, "w", encoding="utf-8").write(s)\n'
        printf 'PYY\n'
    } > "$1"
}
EOF
cat > "$R/mcp-server/tests/test_fixture.py" <<'EOF'
def test_log(tmp_path):
    log_path = tmp_path / "log.jsonl"
    log_path.write_text("a\n", encoding="utf-8")
    s = log_path.read_text(encoding="utf-8")
    log_path.write_text(s + "b\n", encoding="utf-8")
EOF
cat > "$R/hooks/shared.sh" <<'EOF'
#!/usr/bin/env bash
F="$HOME/.claude/shared.txt"
t="$F.tmp"
cat "$F" | sort -u > "$t"
mv "$t" "$F"
EOF
cat > "$R/hooks/shared-py.sh" <<'EOF'
#!/usr/bin/env bash
python3 - "$HOME/.claude/shared.json" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s)
PY
EOF
# Положительные контроли (скептик opus по 2ae73909, M1–M3): настоящее чтение сразу после команды-условия; heredoc на
# строке, которая начинается закрывающей кавычкой многострочного литерала; настоящий носитель ниже `printf "… <<'PY'"`
# в двойных кавычках (маркер, принятый за открытие, ослеплял хвост файла).
cat > "$R/hooks/cond-then-read.sh" <<'EOF'
#!/usr/bin/env bash
F="$HOME/.claude/c.txt"
[ "$(cat "$F")" ] && cat "$F" | sort -u > "$F.t"; mv "$F.t" "$F"
EOF
cat > "$R/hooks/multiline-quote.sh" <<'EOF'
#!/usr/bin/env bash
probe() { python3 -c 'import sys
' 2>/dev/null || python3 - "$HOME/.claude/shared2.json" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s)
PY
}
EOF
cat > "$R/hooks/dq-printf.sh" <<'EOF'
#!/usr/bin/env bash
printf "python3 - <<'PY'\n"
F="$HOME/.claude/d.txt"
t="$F.tmp"
cat "$F" | sort -u > "$t"
mv "$t" "$F"
EOF
git -C "$R" init -q 2>/dev/null && git -C "$R" add -A 2>/dev/null || exit 2
out=$(python3 - "$REG" "$R" <<'PY' 2>/dev/null
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("dcc", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.ROOT = pathlib.Path(sys.argv[2])
for f, places in m.carriers_h():
    print(pathlib.Path(f).resolve().relative_to(m.ROOT.resolve()))
PY
) || exit 2
bad=0
for f in hooks/seen.sh hooks/tests/test_printed.sh mcp-server/tests/test_fixture.py; do
    grep -qx "$f" <<< "$out" && { echo "ложный носитель рода H: $f"; bad=1; }
done
for f in hooks/shared.sh hooks/shared-py.sh hooks/cond-then-read.sh hooks/multiline-quote.sh hooks/dq-printf.sh; do
    grep -qx "$f" <<< "$out" || { echo "пропущен настоящий носитель рода H: $f"; bad=1; }
done
exit "$bad"
