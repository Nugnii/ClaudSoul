#!/usr/bin/env bash
# test_adv_origin_heredoc_mention.sh — упоминание heredoc в комментарии и арифметический
# сдвиг `<<` не открывают тело: хвост файла остаётся кодом.
#
# Результат: род H видит окно read→write ниже строки, где `<<` стоит текстом, а не синтаксисом
# Проверка результата: bash hooks/tests/test_adv_origin_heredoc_mention.sh даёт 0
#
# Атака. `_h_sh_code` и `_h_py_lines` ищут открытие heredoc регуляркой
# `<<-?\s*(['\"]?)(\w+)\1(?!<)` по СЫРОЙ строке — комментарии не отсекаются, кавычки не
# снимаются, арифметика не отличается. Комментарий `# кейс записан `cat > … <<EOF`` ставит
# маркер EOF, и всё до строки, равной ровно «EOF», гасится; закрытия обычно нет, и гаснет
# ВЕСЬ хвост файла. Замер 9 сентября 2026 по дереву: регулярка срабатывает на 42 строках,
# где `<<` — текст, а не синтаксис; в 31 файле маркер не закрывается никогда, и хвост
# теряется целиком — `hooks/detection-signals-lib.sh:256` (311 строк ниже),
# `hooks/knowledge-frontmatter-check.sh:32` (237), `hooks/undefined-function-check.sh:22`
# (224), `hooks/knowledge-link-symmetry.sh:40` (203), `hooks/command-scope-lib.sh:15` (201).
# Вторая форма того же корня — `$(( 1 << 3 ))`: группа `\w+` берёт `3` за маркер.
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

# НАСТОЯЩИЙ носитель 1: heredoc назван в КОММЕНТАРИИ (форма knowledge-frontmatter-check.sh:32).
cat > "$FIX/hooks/attack_comment.sh" <<'EOF'
#!/usr/bin/env bash
# повод: кейс записан `cat > … <<EOF`, проверка не срабатывала ни разу
STATE="$HOME/.claude/hooks/state/shared.json"
jq '.n += 1' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
EOF
# НАСТОЯЩИЙ носитель 2: арифметический сдвиг (форма test_adv4_ansi_arith_comment.sh:121).
cat > "$FIX/hooks/attack_shift.sh" <<'EOF'
#!/usr/bin/env bash
MASK=$(( 1 << 3 ))
STATE="$HOME/.claude/hooks/state/shared.json"
jq ".n += $MASK" "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
EOF
# Положительный контроль: тот же файл без строки с `<<`.
cat > "$FIX/hooks/control_plain.sh" <<'EOF'
#!/usr/bin/env bash
# повод: кейс записан документом, проверка не срабатывала ни разу
STATE="$HOME/.claude/hooks/state/shared.json"
jq '.n += 1' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
EOF

git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.local
git -C "$FIX" config user.name t
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" commit -qm fix >/dev/null 2>&1

H=$(cd "$FIX" && python3 scripts/defect-class-carriers.py --genus H 2>/dev/null | grep '^  ·')

grep -q control_plain <<< "$H" && ok \
  || bad "T0" "прибор ослеп целиком: тот же файл без строки с \`<<\` не пойман — [$H]"
grep -q attack_comment <<< "$H" && ok \
  || bad "T1" "упоминание heredoc в комментарии погасило хвост файла: окно не найдено: [$H]"
grep -q attack_shift <<< "$H" && ok \
  || bad "T2" "арифметический сдвиг \$(( 1 << 3 )) принят за открытие heredoc: окно не найдено: [$H]"

echo ""
echo "adv origin heredoc mention: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
