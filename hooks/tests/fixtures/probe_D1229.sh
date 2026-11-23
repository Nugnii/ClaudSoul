#!/usr/bin/env bash
set -u
# СУДИТ: scripts/probes/R2.sh hooks/playwright-cli-guard.sh
# probe_D1229 — проба корня R2 («журнал без читателя») считает читателем чтение по МАСКЕ имени (`*-fired-*.jsonl` у
#   `scripts/signal-precision.sh`), а не только по литеральному имени, и на дереве не называет никого. Рамка настоящая:
#   проба R2 на песочном git-дереве — журнал `*-fired-<sid>.jsonl`, читаемый маской, не назван; журнал без всякого
#   читателя — назван (контроль); затем проба R2 на самом дереве.
#   0 — песочный читатель по маске принят, контроль назван, на дереве пусто; 1 — что-то из этого не так; 2 — нет пробы.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
P="$PWD/scripts/probes/R2.sh"
[ -f "$P" ] || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
R="$W/r"; mkdir -p "$R/hooks" "$R/scripts"
cat > "$R/hooks/a.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"ts":1}\n' >> "$STATE_DIR/zeta-guard-fired-${SID}.jsonl"
printf '%s\n' x >> "$STATE_DIR/orphan-trace.tsv"
EOF
cat > "$R/scripts/reader.sh" <<'EOF'
#!/usr/bin/env bash
for f in "$STATE_DIR"/*-fired-*.jsonl; do wc -l < "$f"; done
ls "$STATE_DIR"/*.tsv | head -1
EOF
# Маска без слова в имени (`*.tsv`) — обход каталога, не читатель (скептик opus по f22b3b78, M5); маска в .gitignore и в
# прозе — не код (M4).
printf 'orphan-*.tsv
' > "$R/.gitignore"
mkdir -p "$R/skills"; printf 'читает orphan-*.tsv
' > "$R/skills/n.md"
git -C "$R" init -q 2>/dev/null && git -C "$R" add -A 2>/dev/null || exit 2
out=$(CLAUDSOUL_REPO="$R" bash "$P" 2>/dev/null)
bad=0
grep -q 'zeta-guard-fired' <<< "$out" && { echo "журнал, читаемый маской *-fired-*.jsonl, назван без читателя"; bad=1; }
grep -q 'orphan-trace.tsv' <<< "$out" || { echo "контроль: журнал без читателя не назван"; bad=1; }
live=$(bash "$P" 2>/dev/null)
[ -z "$live" ] || { echo "проба R2 на дереве называет:"; printf '%s\n' "$live"; bad=1; }
exit "$bad"
