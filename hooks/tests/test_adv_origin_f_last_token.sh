#!/usr/bin/env bash
# СУДИТ: scripts/defect-class-carriers.py
# test_adv_origin_f_last_token.sh — снятие с учёта по роду F решает ЦЕЛЬ КОПИИ,
# а не последний токен строки.
#
# Результат: глоб, копирующий в живую систему, остаётся носителем F при хвостовом
#            перенаправлении в личный каталог
# Проверка результата: bash hooks/tests/test_adv_origin_f_last_token.sh даёт 0
#
# Атака. `_f_copy_into_private` берёт цель через `F_LAST_ARG`, привязанную к КОНЦУ СТРОКИ,
# и потому получает не аргумент `cp`, а последний токен строки: любой хвост — `>> "$LOG"`,
# `; : > "$T/x"`, второе звено `&&` — подменяет цель. Личный вид хвоста снимает с учёта
# всю строку (`continue`), включая настоящий глоб. Правило рода при этом прямо говорит
# обратное: разделитель — ЦЕЛЬ копии, а `install.sh` тем же глобом копирует в живую
# систему и остаётся носителем.
# Достижимость: расхождение «цель cp ≠ последний токен» есть в дереве на 3 адресах —
# `hooks/tests/test_contract_line_anchor.sh`, `hooks/tests/test_mode_arg_guard.sh`
# (обе формы `cp … ; : > "$TMP/archN.md"`) и `hooks/tests/test_docs_family_check.sh`.
# Там обе стороны личные, поэтому живого носителя сегодня не потеряно.
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

mkdir -p "$FIX/scripts" "$FIX/hooks/lib"
cp "$REG" "$FIX/scripts/defect-class-carriers.py"
printf '#!/usr/bin/env bash\ntrue\n' > "$FIX/install.sh"
# Подкаталог, невидимый мелкому шаблону `hooks/*.sh`, — предмет рода F.
printf '#!/usr/bin/env bash\ntrue\n' > "$FIX/hooks/lib/deep.sh"

# НАСТОЯЩИЙ носитель: копия в ЖИВУЮ систему, хвост — журнал в личном каталоге.
cat > "$FIX/hooks/attack_tail_log.sh" <<'EOF'
#!/usr/bin/env bash
LOGDIR=$(mktemp -d)
cp "$REPO"/hooks/*.sh "$HOME/.claude/hooks/" >> "$LOGDIR/install.log"
EOF
# Положительный контроль: та же строка без хвоста — прибор её видит.
cat > "$FIX/hooks/control_no_tail.sh" <<'EOF'
#!/usr/bin/env bash
cp "$REPO"/hooks/*.sh "$HOME/.claude/hooks/"
EOF

git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.local
git -C "$FIX" config user.name t
git -C "$FIX" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_origin_f_last_token.sh:$LINENO" >&2; exit 1; }
git -C "$FIX" commit -qm fix >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_origin_f_last_token.sh:$LINENO" >&2; exit 1; }

F=$(cd "$FIX" && python3 scripts/defect-class-carriers.py --genus F 2>/dev/null | grep '^  ·')

grep -q control_no_tail <<< "$F" && ok \
  || bad "T0" "прибор ослеп целиком: та же копия без хвоста не пойма́на — [$F]"
grep -q attack_tail_log <<< "$F" && ok \
  || bad "T1" "хвостовое перенаправление в личный каталог сняло с учёта копию в живую систему: [$F]"

echo ""
echo "adv origin f last token: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
