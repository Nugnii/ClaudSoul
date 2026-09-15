#!/usr/bin/env bash
# test_adv_origin_func_positional.sh — путь, пришедший ПОЗИЦИОННЫМ ПАРАМЕТРОМ ФУНКЦИИ,
# не «происхождения не имеет»: вызов стоит в этом же дереве, и общий файл остаётся общим.
#
# Результат: род H называет носителем функцию, читающую и перезаписывающую общий файл,
#            имя которого пришло через `local target="$1"`
# Проверка результата: bash hooks/tests/test_adv_origin_func_positional.sh даёт 0
#
# Атака. `_h_kind` объявляет «неизвестным» всякое имя, у которого ВСЯ правая часть — `$1`,
# `$2`, `$@`: «путь пришёл извне, судить нельзя». Но `$1` ФУНКЦИИ оболочки — не argv
# скрипта: это аргумент вызова, стоящего в том же дереве. Живой носитель —
# `lib/claude-md-merge.sh:29` (`local target="$1"`), где строки 48-51 читают `$target`
# целиком (`head`/`tail`), правят в памяти и кладут обратно `mv "$tmp" "$target"` (:53);
# зовётся оно из `install.sh` c `$HOME/.claude/CLAUDE.md` — общим файлом, который правит
# и собеседник. Замка нет, окно read→write открыто. Прибор печатает по роду H ноль.
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

# НАСТОЯЩИЙ носитель: форма lib/claude-md-merge.sh — общий файл приходит в функцию `$1`.
cat > "$FIX/hooks/attack_func_arg.sh" <<'EOF'
#!/usr/bin/env bash
sync_it() {
    local target="$1"
    local tmp
    tmp=$(mktemp)
    head -n 3 "$target" > "$tmp"
    mv "$tmp" "$target"
}
sync_it "$HOME/.claude/CLAUDE.md"
EOF
# Положительный контроль: то же тело без функции — прибор обязан назвать его носителем.
cat > "$FIX/hooks/control_direct.sh" <<'EOF'
#!/usr/bin/env bash
target="$HOME/.claude/CLAUDE.md"
tmp=$(mktemp)
head -n 3 "$target" > "$tmp"
mv "$tmp" "$target"
EOF

git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.local
git -C "$FIX" config user.name t
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" commit -qm fix >/dev/null 2>&1

H=$(cd "$FIX" && python3 scripts/defect-class-carriers.py --genus H 2>/dev/null | grep '^  ·')

grep -q control_direct <<< "$H" && ok \
  || bad "T0" "прибор ослеп целиком: прямая форма того же тела не пойма́на — [$H]"
grep -q attack_func_arg <<< "$H" && ok \
  || bad "T1" "общий файл, пришедший позиционным параметром функции, не назван носителем H: [$H]"

echo ""
echo "adv origin func positional: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
