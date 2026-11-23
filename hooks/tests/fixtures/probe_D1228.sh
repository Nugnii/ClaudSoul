#!/usr/bin/env bash
set -u
# СУДИТ: scripts/reader-field-sweep.py scripts/measurements.tsv
# probe_D1228 — сверщик полей читателей состояния разрешает путь журнала, присвоенный вызовом владельца пути
#   (`$(throttle_file "$STATE" <семейство> …)`) и строкой с двумя подстановками подряд (`-${SID}${SUFFIX}.jsonl`), а
#   питонский читатель файлов ПРОЕКТА (без каталога состояния в тексте) не числится несверенным читателем состояния. Рамка
#   настоящая: прибор на песочном дереве (`RFS_REPO`) и песочном каталоге состояния с живыми записями. Контроль: читатель
#   выдуманного поля назван расхождением. У замера есть строка в реестре, и прибор в ней — этот.
#   0 — все три формы сверены, выдуманное поле названо, строка реестра есть; 1 — что-то из этого не так; 2 — нет прибора
#   или реестра, прибор не дал итоговой строки.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
S="$PWD/scripts/reader-field-sweep.py"
for f in "$S" scripts/measurements.tsv; do [ -f "$f" ] || exit 2; done
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/r/hooks/lib" "$W/r/scripts" "$W/st" "$W/ss"
U=00000000-0000-4000-8000-000000001228
printf '{"path":"/x","ts":1}\n' > "$W/st/rework-fired-$U.jsonl"
printf '{"key":"k","date":"d"}\n' > "$W/st/question-open-$U.jsonl"
cat > "$W/r/hooks/a.sh" <<'EOF'
#!/usr/bin/env bash
REWORK=$(throttle_file "$STATE" rework "$SID" "$SUFFIX")
jq -r '.path // empty' "$REWORK"
EOF
cat > "$W/r/hooks/b.sh" <<'EOF'
#!/usr/bin/env bash
QUESTION="$STATE/question-open-${SID}${SUFFIX}.jsonl"
jq -r '.key // empty' "$QUESTION"
EOF
cat > "$W/r/hooks/c.sh" <<'EOF'
#!/usr/bin/env bash
QUESTION="$STATE/question-open-${SID}.jsonl"
jq -r '.nofield // empty' "$QUESTION"
EOF
cat > "$W/r/hooks/lib/pm.py" <<'EOF'
import json, os
DESCRIPTOR = os.path.join(".claude-docs", "project-map.json")
m = json.loads(open(DESCRIPTOR).read())
print(m.get("version"))
EOF
# Питонский читатель состояния (каталог назван) просит выдуманное поле — сверщик обязан его назвать (скептик opus по
# e465b70c, M1: мутант «все питонские — вне состояния» проходил пробу).
cat > "$W/r/scripts/st.py" <<'EOF'
import json, os
STATE = os.environ.get("STATE_DIR")
for line in open(os.path.join(STATE, "question-open-*.jsonl")):
    rec = json.loads(line)
    print(rec.get("nopyfield"))
EOF
out=$(RFS_REPO="$W/r" STATE_DIR="$W/st" SR_SESSIONS_DIR="$W/ss" python3 "$S" --check 2>/dev/null)
grep -q '|reader-field-sweep|' <<< "$out" || exit 2
bad=0
grep -q 'a.sh:.*не разрешён' <<< "$out" && { echo "путь через throttle_file не разрешён"; bad=1; }
grep -q 'b.sh:.*не разрешён' <<< "$out" && { echo "путь с двумя подстановками подряд не разрешён"; bad=1; }
grep -q 'pm.py:.*не сверено' <<< "$out" && { echo "читатель файла проекта числится несверенным читателем состояния"; bad=1; }
grep -q 'c.sh:.*просит .nofield' <<< "$out" || { echo "контроль: выдуманное поле не названо расхождением"; bad=1; }
grep -q 'st.py:.*просит .nopyfield' <<< "$out" || { echo "питонский читатель состояния выдуманного поля не назван"; bad=1; }
# Четыре читателя состояния (a, b, c, st.py) сверены все; файл проекта (pm.py) — вне состояния.
grep -q 'население читателей состояния 4, сверено 4, не сверено 0, вне состояния 1' <<< "$out" \
    || { echo "счёт сверки не тот: $(grep '|reader-field-sweep|' <<< "$out")"; bad=1; }
awk -F'\t' '$1 == "reader-field-sweep" && $3 ~ /scripts\/reader-field-sweep\.py --check/ { f = 1 } END { exit !f }' scripts/measurements.tsv \
    || { echo "у замера сверщика нет строки в scripts/measurements.tsv"; bad=1; }
exit "$bad"
