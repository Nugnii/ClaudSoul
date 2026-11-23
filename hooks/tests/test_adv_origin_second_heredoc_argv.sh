#!/usr/bin/env bash
# СУДИТ: scripts/defect-class-carriers.py
# test_adv_origin_second_heredoc_argv.sh — argv питона берётся у СВОЕГО места вызова,
# а не у первого heredoc файла.
#
# Результат: род H судит каждый python-heredoc по его собственным аргументам
# Проверка результата: bash hooks/tests/test_adv_origin_second_heredoc_argv.sh даёт 0
#
# Атака. `_h_py_lines` собирает аргументы только у ПЕРВОГО heredoc (`if argv is not None
# and not argv`), а `carriers_h` подставляет их во все `sys.argv[N]` файла. Файл с двумя
# вставками получает происхождение первой на обе. Форма живая: 20 файлов дерева несут 2+
# python-heredoc, у 15 хотя бы один с аргументами — `scripts/backlog-recheck.sh:101`
# подаёт `"$LESSONS"`, `:165` подаёт `"$_sp"`, и второй судится по первому;
# `hooks/tests/test_error_tracker.sh:177,192`, `hooks/tests/test_injection_log_rotate_concurrent.sh:41,68,83`.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
REG="${DCC_REGISTRY:-$REPO/scripts/defect-class-carriers.py}"
[ -f "$REG" ] || { echo "FAIL: нет $REG"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

PASS=0; FAIL=0
FIX=$(mktemp -d)
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

mkdir -p "$FIX/scripts" "$FIX/hooks"
cp "$REG" "$FIX/scripts/defect-class-carriers.py"
printf '#!/usr/bin/env bash\ntrue\n' > "$FIX/install.sh"

# НАСТОЯЩИЙ носитель: ВТОРАЯ вставка правит общий файл, первой подан личный.
cat > "$FIX/hooks/attack_second.sh" <<'EOF'
#!/usr/bin/env bash
TMP=$(mktemp -d)
STATE="$HOME/.claude/hooks/state/shared.json"
python3 - "$TMP/scratch.json" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text("x")
PY
python3 - "$STATE" <<'PY'
import sys, pathlib
q = pathlib.Path(sys.argv[1])
t = q.read_text()
q.write_text(t + "y")
PY
EOF
# Положительный контроль: ТЕ ЖЕ две вставки в обратном порядке — прибор их видит.
cat > "$FIX/hooks/control_order.sh" <<'EOF'
#!/usr/bin/env bash
TMP=$(mktemp -d)
STATE="$HOME/.claude/hooks/state/shared.json"
python3 - "$STATE" <<'PY'
import sys, pathlib
q = pathlib.Path(sys.argv[1])
t = q.read_text()
q.write_text(t + "y")
PY
python3 - "$TMP/scratch.json" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text("x")
PY
EOF

git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.local
git -C "$FIX" config user.name t
git -C "$FIX" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_origin_second_heredoc_argv.sh:$LINENO" >&2; exit 1; }
git -C "$FIX" commit -qm fix >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_origin_second_heredoc_argv.sh:$LINENO" >&2; exit 1; }

H=$(cd "$FIX" && python3 scripts/defect-class-carriers.py --genus H 2>/dev/null | grep '^  ·')

grep -q control_order <<< "$H" && ok \
  || bad "T0" "прибор ослеп целиком: та же пара вставок в обратном порядке не пойма́на — [$H]"
grep -q attack_second <<< "$H" && ok \
  || bad "T1" "второй python-heredoc судится по аргументам первого: общий файл не назван носителем H: [$H]"

echo ""
echo "adv origin second heredoc argv: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
