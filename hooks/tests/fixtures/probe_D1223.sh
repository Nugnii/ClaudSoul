#!/usr/bin/env bash
set -u
# СУДИТ: scripts/docs-refresh-claims.sh scripts/count-stats.sh
# probe_D1223 — у числа хуков в производном README два писателя (строка шапки — `count-stats.sh`, первая строка —
#   `docs-refresh-claims.sh run`), и оба следуют одному правилу к ОТСТАВШЕМУ производному документу: после прогона обоих
#   обе строки несут одно число, а документ остаётся отставшим (числа не маскируют непереведённую прозу). Рамка
#   настоящая: копии обоих писателей и их библиотек в песочном дереве; хуков в дереве три — их и считает count-stats,
#   то же число отдаёт заглушка источника чисел. Вторая половина правила: в сверке (`check`) отставший пропускается.
#   0 — обе строки «3», документ отставший; 1 — строки разошлись либо отставание замаскировано; 2 — нет писателей или
#   библиотек, контроль (документ до прогона отставший, count-stats дописал шапку) не прошёл.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
for f in scripts/docs-refresh-claims.sh scripts/count-stats.sh scripts/docs-derived-check.sh hooks/docs-derived-lib.sh \
         hooks/state-lock-lib.sh hooks/lib/unread-lib.sh hooks/lib/state_lock.py; do [ -f "$f" ] || exit 2; done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
R="$W/r"
mkdir -p "$R/scripts" "$R/hooks/lib" "$R/hooks/tests" "$R/skills" "$R/domains" "$R/bridges" "$R/mcp-server/tests"
cp scripts/docs-refresh-claims.sh scripts/count-stats.sh scripts/docs-derived-check.sh "$R/scripts/" \
    && cp hooks/docs-derived-lib.sh hooks/state-lock-lib.sh "$R/hooks/" && cp hooks/lib/unread-lib.sh hooks/lib/state_lock.py "$R/hooks/lib/" || exit 2
# Хук с отказом и хук с вопросом обязательны: на дереве без одного из видов count-stats выходит молча (пустой
# перечень под pipefail) — в настоящем дереве есть оба.
echo '#!/usr/bin/env bash' > "$R/hooks/a.sh"
echo "echo '{\"permissionDecision\": \"ask\"}'" > "$R/hooks/b.sh"
echo "echo '{\"permissionDecision\": \"deny\"}'" > "$R/hooks/c.sh"
echo "HOOKS_CONFIG='{}'" > "$R/install.sh"
cat > "$W/figures.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in hooks) echo 3 ;; *) echo n/a ;; esac
EOF
printf 'README.md\t^(\\d+) hooks \\(\\d+ of them wired\thooks\t\tхуков всего, первая строка\n' > "$W/claims.tsv"
printf 'README.md\t(\\d+) active hooks, \\d+ skills\thooks\t\tактивных хуков, шапка\n' >> "$W/claims.tsv"
echo '# R' > "$R/README.ru.md"
cat > "$R/README.md" <<'EOF'
<!-- derived-from: README.ru.md@000000000000 -->
# R

91 hooks (84 of them wired to Claude Code lifecycle events), 24 commands

**At a glance:** 91 active hooks, 24 skills, 1 inter-layer bridges, 1 domain nodes — tests green.
EOF
git -C "$R" init -q 2>/dev/null && git -C "$R" add -A 2>/dev/null || exit 2
stale() { [ "$(CLAUDSOUL_REPO="$R" bash "$R/scripts/docs-derived-check.sh" stale 2>/dev/null)" = README.md ]; }
stale || { echo "контроль: README.md до прогона не отставший"; exit 2; }
( cd "$R" && bash scripts/count-stats.sh --patch-claude-md >/dev/null 2>&1 )
grep -q '^\*\*At a glance:\*\* 3 active hooks' "$R/README.md" || { echo "контроль: count-stats не дописал шапку"; exit 2; }
CLAUDSOUL_REPO="$R" DOC_CLAIMS_FILE="$W/claims.tsv" DOC_FIGURES="$W/figures.sh" bash "$R/scripts/docs-refresh-claims.sh" run >/dev/null 2>&1
first=$(sed -n 's/^\([0-9]*\) hooks (.*/\1/p' "$R/README.md")
bad=0
[ "$first" = 3 ] || { echo "строки README разошлись после обоих писателей: первая ${first}, шапка 3"; bad=1; }
stale || { echo "отставание README.md замаскировано прогоном писателей"; bad=1; }
# Вторая половина правила (скептик opus по 1243ff65, L2): в СВЕРКЕ отставший пропускается и называется числом — его
# устаревшая строка сверщик не красит.
sed -i.bak 's/^3 hooks (/91 hooks (/' "$R/README.md" && rm -f "$R/README.md.bak"
chk=$(CLAUDSOUL_REPO="$R" DOC_CLAIMS_FILE="$W/claims.tsv" DOC_FIGURES="$W/figures.sh" bash "$R/scripts/docs-refresh-claims.sh" check 2>&1); crc=$?
[ "$crc" = 0 ] && grep -q 'пропущено (производный документ отстал' <<< "$chk" \
    || { echo "сверка не пропустила отставший перевод (код ${crc}): ${chk}"; bad=1; }
exit "$bad"
