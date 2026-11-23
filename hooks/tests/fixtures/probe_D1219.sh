#!/usr/bin/env bash
# СУДИТ: scripts/setup-call-guard.py
# probe_D1219 — признак немых подготовительных вызовов судит каждую команду строки, а не только начало: вызов после
#   `X=…;` или `echo …;` в той же строке назван, а `--fix` ставит стража каждому носителю строки. Контроли: вызов со
#   стражем, вызов внутри подстановки и `;` в комментарии носителями не стали.
#   0 — признак видит команду после `;`; 1 — не видит либо `--fix` её не закрыл; 2 — нет прибора или песочницы.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
T="$R/scripts/setup-call-guard.py"
[ -f "$T" ] && command -v python3 >/dev/null 2>&1 || exit 2
S=$(mktemp -d) || exit 2
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/bad/hooks/tests" "$S/good/hooks/tests" || exit 2
cat > "$S/bad/hooks/tests/test_x.sh" <<'FIX' || exit 2
#!/usr/bin/env bash
K="$TMP/k"; bash "$TRAP" --install "$K" >/dev/null 2>&1
echo seed > "$r/seed.txt"; git -C "$r" add . >/dev/null 2>&1; git -C "$r" commit -qm s >/dev/null 2>&1
for x in a b; do cp "$x" "$S/y" 2>/dev/null; done
commit() { git -C "$r" add -A >/dev/null; git -C "$r" commit -qm "$1"; }
EXP=$(python3 - <<'EOF'
print(int("1"))
EOF
)
git -C "$r" init -q 2>/dev/null
printf '%s\n' "git commit -F - <<'EOF'" 'x'
cp a b 2>/dev/null
L=$(awk '/[(]x/ { print }' f)
mkdir -p "$S/z" 2>/dev/null
echo ok
FIX
cat > "$S/good/hooks/tests/test_x.sh" <<'FIX' || exit 2
#!/usr/bin/env bash
K="$TMP/k"; bash "$TRAP" --install "$K" >/dev/null 2>&1 || exit 1
OUT=$(cd "$r"; git status 2>/dev/null)
echo ok  # ; git add . >/dev/null 2>&1
run() { bash "$HOOK" 2>/dev/null; }
X=1; if [ -d "$r" ] &&
    git -C "$r" diff --quiet >/dev/null 2>&1; then echo same; fi
while IFS= read -r f; do A+=("$f"); done < <(
    git -C "$r" ls-files 2>/dev/null | grep -v x
)
run_bash() {
    bash "$HOOK" 2>/dev/null
}
cat > "$r/t.sh" <<'EOF'
git -C "$r" add . >/dev/null 2>&1
EOF
FIX
n=$(python3 "$T" --root "$S/bad" --count 2>/dev/null)
[ "$n" = 8 ] || { echo "носителей после ';', 'do', заголовка функции и за heredoc/скобкой в кавычках названо [$n], а не 8"; exit 1; }
n=$(python3 "$T" --root "$S/good" --count 2>/dev/null)
[ "$n" = 0 ] || { echo "контроль: страж, подстановка, комментарий, код функции или хвост условия дали носителей [$n]"; exit 1; }
python3 "$T" --root "$S/bad" --fix >/dev/null 2>&1 || { echo "--fix не закрыл носителей строки"; exit 1; }
bash -n "$S/bad/hooks/tests/test_x.sh" 2>/dev/null || { echo "--fix сломал синтаксис"; exit 1; }
n=$(python3 "$T" --root "$S/bad" --count 2>/dev/null)
[ "$n" = 0 ] || { echo "после --fix носителей [$n]"; exit 1; }
# Страж после `|` в конце строки сломал бы синтаксис: файл не пишется, отказ назван кодом.
mkdir -p "$S/pipe/hooks/tests" || exit 2
printf '#!/usr/bin/env bash\ngit ls-files 2>/dev/null |\n    wc -l\n' > "$S/pipe/hooks/tests/test_p.sh" || exit 2
cp "$S/pipe/hooks/tests/test_p.sh" "$S/pipe.orig" || exit 2
python3 "$T" --root "$S/pipe" --fix >/dev/null 2>&1 && { echo "--fix не назвал отказ записи при сломанном синтаксисе"; exit 1; }
cmp -s "$S/pipe/hooks/tests/test_p.sh" "$S/pipe.orig" || { echo "--fix записал файл со сломанным синтаксисом"; exit 1; }
echo "команды после ';' судятся, --fix ставит стража каждой"
exit 0
