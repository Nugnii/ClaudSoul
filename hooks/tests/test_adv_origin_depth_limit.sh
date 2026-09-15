#!/usr/bin/env bash
# test_adv_origin_depth_limit.sh — личное происхождение не теряется от длины цепочки.
#
# Результат: путь, выведенный из `mktemp -d` шестью присваиваниями, носителем H не числится
# Проверка результата: bash hooks/tests/test_adv_origin_depth_limit.sh даёт 0
#
# Атака (ложноположительный). В `_h_kind` рекурсия по ссылкам гейтится `depth < 4`. На
# пятом звене спуск обрывается и имя молча падает в «общий» — тот самый слитый исход, ради
# разделения которого заводился «неизвестно». Мир при этом ни от чего не зависит: файл
# лежит в собственном `mktemp -d` прогона, второго писателя нет.
# Достижимость: замер 9 сентября 2026 по дереву — 5 имён в 2 файлах меняют вердикт с
# «общий» на «личный», если снять предел: `hooks/knowledge-activator.sh` (SELF_ALT,
# VOLATILE_TAG, VOL) и `hooks/tests/test_periodic_digests.sh` (OUT_SELF, OUT_ESC_SECTION).
# Окна read→write на них сегодня нет, поэтому ложным носителем ни один пока не стал.
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

# ЛОЖНЫЙ носитель: шесть звеньев от mktemp -d.
cat > "$FIX/hooks/false_deep6.sh" <<'EOF'
#!/usr/bin/env bash
A=$(mktemp -d)
B="$A/run"
C="$B/state"
D="$C/hooks"
E="$D/session"
G="$E/counters.json"
jq '.n += 1' "$G" > "$G.t" && mv "$G.t" "$G"
EOF
# Положительный контроль ПРИБОРА: пять звеньев — та же песочница, вердикт «личное» верен.
cat > "$FIX/hooks/false_deep5.sh" <<'EOF'
#!/usr/bin/env bash
A=$(mktemp -d)
B="$A/run"
C="$B/state"
D="$C/hooks"
E="$D/counters.json"
jq '.n += 1' "$E" > "$E.t" && mv "$E.t" "$E"
EOF
# Положительный контроль: настоящий носитель — прибор в этой песочнице не ослеп.
cat > "$FIX/hooks/real_plain.sh" <<'EOF'
#!/usr/bin/env bash
STATE="$HOME/.claude/hooks/state/shared.json"
jq '.n += 1' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
EOF

git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.local
git -C "$FIX" config user.name t
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" commit -qm fix >/dev/null 2>&1

H=$(cd "$FIX" && python3 scripts/defect-class-carriers.py --genus H 2>/dev/null | grep '^  ·')

grep -q real_plain <<< "$H" && ok \
  || bad "T0" "прибор ослеп целиком: настоящий носитель не пойман — [$H]"
grep -q false_deep5 <<< "$H" && bad "T1" "пять звеньев от mktemp -d сочтены общим файлом: [$H]" || ok
grep -q false_deep6 <<< "$H" && bad "T2" "шесть звеньев от mktemp -d сочтены общим файлом — предел глубины 4 роняет вердикт: [$H]" || ok

echo ""
echo "adv origin depth limit: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
