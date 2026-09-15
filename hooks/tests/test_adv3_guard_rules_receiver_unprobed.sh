#!/usr/bin/env bash
# АТАКА: приёмник ~/.claude/CLAUDE.md не виден НИ ОДНОМУ из двух стражей пары.
#
# Поведенческий страж строит песочницу-установку РУКАМИ и перечисляет пробы поимённо:
# хуки, библиотеки, скиллы, bin, шаблоны, статусная строка. Файла ~/.claude/CLAUDE.md
# он не кладёт и не портит — значит пара «правила» на каждом прогоне печатает одно и
# то же (её приёмника в песочнице нет), и никакая её поломка вывод не изменит.
# Страж покрытия его тоже не видит: доставка идёт вызовом `sync_claude_md` из
# lib/claude-md-merge.sh, а признак доставки — перечень команд (cp|install|ln|mv|
# rsync|cat|tee|printf|echo|jq). Тот самый перечень форм, против которого страж и заведён.
#
# Вход: копия репозитория, из drift-check вырезана ВСЯ пара «правила».
# Ожидание: хотя бы один из двух стражей краснеет — приёмник install.sh перестал
# сравниваться.
# Факт: «приёмников проверено подменой: 6, пар без сравнения: 0» и «непокрытых пар: 0».
# Оба зелёные.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BEHAV="$REPO/hooks/tests/test_drift_pair_actually_compares.sh"
COVER="$REPO/hooks/tests/test_drift_pairs_cover_install.sh"
for f in "$BEHAV" "$COVER" "$REPO/hooks/tests/drift-check.sh"; do
    [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }
done
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

TMP=$(mktemp -d)
D="$TMP/repo"
SRC_SKILLS="$REPO/skills"
DST_SKILLS="$D/skills"
mkdir -p "$D/hooks/lib" "$D/hooks/tests" "$D/bin" "$D/templates" "$D/knowledge" \
         "$D/rules" "$D/lib" "$D/scripts" "$DST_SKILLS"
cp "$REPO/install.sh" "$D/"
cp "$REPO"/hooks/*.sh "$D/hooks/" 2>/dev/null
cp "$REPO"/hooks/lib/* "$D/hooks/lib/" 2>/dev/null
cp "$REPO"/bin/*.sh "$D/bin/" 2>/dev/null
cp "$REPO"/templates/*.tmpl "$D/templates/" 2>/dev/null
cp "$REPO"/knowledge/*.md "$D/knowledge/" 2>/dev/null
cp "$REPO/rules/CLAUDE.md" "$D/rules/CLAUDE.md"
cp "$REPO/lib/claude-md-merge.sh" "$D/lib/"
cp "$REPO/scripts/statusline-claudsoul.sh" "$D/scripts/" 2>/dev/null
cp "$REPO/scripts/regen-seed.py" "$D/scripts/" 2>/dev/null
for _d in "$SRC_SKILLS"/*/ ; do
    [ -d "$_d" ] || continue
    _n=$(basename "$_d")
    mkdir -p "$DST_SKILLS/$_n"
    cp "$_d/SKILL.md" "$DST_SKILLS/$_n/SKILL.md" 2>/dev/null
    if [ -d "$_d/references" ]; then
        mkdir -p "$DST_SKILLS/$_n/references"
        cp "$_d"/references/*.md "$DST_SKILLS/$_n/references/" 2>/dev/null
    fi
done
cp "$REPO/hooks/tests/drift-check.sh" "$D/hooks/tests/"
cp "$BEHAV" "$D/hooks/tests/"
cp "$COVER" "$D/hooks/tests/"

# Диверсия: пара «правила» вырезана целиком.
CUT=$(python3 - "$D/hooks/tests/drift-check.sh" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
i = t.index('_rules_src="$REPO/rules/CLAUDE.md"')
j = t.index('# --- 6. Seed знаний')
p.write_text(t[:i] + "# пара «правила» вырезана целиком (диверсия противника)\n\n" + t[j:])
print(j - i)
PY
)
[ -n "$CUT" ] || { echo "FAIL: не удалось вырезать пару"; exit 1; }
if grep -q 'rules/CLAUDE.md' "$D/hooks/tests/drift-check.sh"; then
    echo "FAIL: пара «правила» осталась в копии — диверсия не удалась"; exit 1
fi
echo "  вырезано символов пары «правила»: $CUT"

OUT_B=$(bash "$D/hooks/tests/test_drift_pair_actually_compares.sh" 2>&1); RC_B=$?
OUT_C=$(bash "$D/hooks/tests/test_drift_pairs_cover_install.sh" 2>&1);   RC_C=$?
printf '%s\n' "$OUT_B" | sed 's/^/  | поведенческий: /'
printf '%s\n' "$OUT_C" | sed 's/^/  | покрытие:      /'
echo "  коды возврата: поведенческий $RC_B, покрытие $RC_C"

if [ "$RC_B" -ne 0 ] || [ "$RC_C" -ne 0 ]; then
    echo "PASS: пропажа пары «правила» замечена"
    exit 0
fi
echo "FAIL: пара «правила» вырезана из drift-check, оба стража зелёные."
echo "      Поведенческий: его песочница не создаёт ~/.claude/CLAUDE.md и пробы для него"
echo "      нет — «по каждому приёмнику» на деле означает «по шести перечисленным»."
echo "      Покрытие: доставка идёт через sync_claude_md, а признак доставки — перечень"
echo "      команд записи, куда вызов функции не входит; строка даже не названа неразобранной."
exit 1
