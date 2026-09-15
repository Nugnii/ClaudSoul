#!/usr/bin/env bash
# test_docs_concepts.sh — понятия ранга этапа названы в документах состояния, а прибор умеет краснеть.
#
# Результат: ни одно понятие реестра не пропало; при пропаже прибор называет его поимённо.
# Проверка результата: bash hooks/tests/test_docs_concepts.sh даёт 0
#
# Повод, 10 сентября 2026. Карта корней («лес») построена 9 сентября, а к следующему утру не
# упоминалась НИ В ОДНОМ документе состояния — нашёл собеседник чтением, не механизм.
# Числа документов держит реестр (173 проверки), у понятий сверщика не было вовсе.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Предмет ноги ниже — ЖИВАЯ карта корней, она внутренняя и в публичный снимок не
# входит; сам прибор и шаблон карты входят, поэтому ноги на песочнице остаются предметом.
UNIVERSE_ROOT="$ROOT"; . "$ROOT/hooks/lib/universe-lib.sh" 2>/dev/null || true
partial() { command -v universe_partial_tree >/dev/null 2>&1 && universe_partial_tree; }
CHK="$ROOT/scripts/docs-concepts-check.sh"
REG="$ROOT/scripts/doc-concepts.tsv"
[ -f "$CHK" ] || { echo "FAIL: нет $CHK"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P=0; F=0
ok()  { P=$((P+1)); printf '  ✅ %s\n' "$1"; }
bad() { F=$((F+1)); printf '  ❌ %s\n' "$1"; }

# --- T1: на нынешнем дереве понятия на месте ---
bash "$CHK" >/dev/null 2>&1
rc=$?
[ "$rc" = "0" ] && ok "нынешнее дерево: все понятия на месте" \
                || bad "нынешнее дерево: код $rc — понятие пропало, смотри вывод $CHK"

# --- T2: пропажу прибор ВИДИТ. Без этой ноги «на месте» неотличимо от слепоты ---
# Песочница-копия: понятие вычищается из документа, и прибор обязан назвать его поимённо.
mkdir -p "$TMP/scripts" "$TMP/docs"
cp "$CHK" "$REG" "$TMP/scripts/" 2>/dev/null
while IFS=$'\t' read -r _n _p files _w; do
    case "${_n:-}" in ''|'#'*) continue ;; esac
    IFS=',' read -r -a _fs <<< "${files:-}"
    for f in "${_fs[@]}"; do
        [ -f "$ROOT/$f" ] || continue
        mkdir -p "$TMP/$(dirname "$f")"; cp "$ROOT/$f" "$TMP/$f"
    done
done < "$REG"
CLAUDSOUL_REPO="$TMP" bash "$TMP/scripts/docs-concepts-check.sh" >/dev/null 2>&1
[ "$?" = "0" ] && ok "копия дерева зелена (контроль песочницы)" \
               || bad "копия дерева красна — песочница собрана неверно, T2 ничего не докажет"

# Вычищаем понятие «крона» из документа-экспорта копии.
_doc="$TMP/docs/mechanism-errors-and-backlog.ru.md"
if [ -f "$_doc" ]; then
    # -Mutf8 обязателен: -CSD включает UTF-8 для ПОТОКОВ, а шаблон в -e берётся байтами,
    # и кириллический класс [а-яё] молча не совпадает ни с чем. Первая редакция этой ноги
    # так и вышла: замена не меняла ничего, прибор честно говорил «на месте», и нога
    # доказывала слепоту вместо зоркости.
    perl -CSD -Mutf8 -pi -e 's/крон[а-яё]*/ветвь/gi' "$_doc" 2>/dev/null
    out=$(CLAUDSOUL_REPO="$TMP" bash "$TMP/scripts/docs-concepts-check.sh" 2>&1); rc=$?
    if [ "$rc" = "1" ] && grep -q 'крона' <<< "$out"; then ok "пропажу понятия прибор называет поимённо"
    else bad "пропажа не поймана: код $rc, вывод: ${out:0:80}"; fi
else
    bad "в песочнице нет документа-экспорта — реестр указывает не туда"
fi

# --- T2b: корень карты, не названный в документах, виден. Эта часть НЕ из реестра ---
# Реестр понятий пополняется рукой, и в этом его предел. Корни выводятся из самой карты:
# новый корень подхватывается сам. Проверено на копии — из документов вычищается R1.
if [ -f "$ROOT/ROOTS.md" ]; then
    cp "$ROOT/ROOTS.md" "$TMP/ROOTS.md"
    for _d in CLAUDE.md docs/architecture.md docs/mechanism-errors-and-backlog.ru.md; do
        [ -f "$TMP/$_d" ] || continue
        LC_ALL=C sed -i.bak 's/R1/RX/g' "$TMP/$_d" 2>/dev/null; rm -f "$TMP/$_d.bak"
    done
    out=$(CLAUDSOUL_REPO="$TMP" bash "$TMP/scripts/docs-concepts-check.sh" 2>&1); rc=$?
    if [ "$rc" = "1" ] && grep -q 'R1' <<< "$out"; then ok "корень без описания снаружи назван поимённо"
    else bad "корень R1 вычищен из документов, а прибор молчит: код $rc"; fi
else
    if partial; then universe_skip_note "карта корней" "ROOTS.md"
    else bad "карты ROOTS.md нет — вторая часть прибора не проверена"; fi
fi

# --- T3: реестра нет — это ОТКАЗ прибора, а не «понятия на месте» ---
mv "$TMP/scripts/doc-concepts.tsv" "$TMP/scripts/doc-concepts.off"
CLAUDSOUL_REPO="$TMP" bash "$TMP/scripts/docs-concepts-check.sh" >/dev/null 2>&1
[ "$?" = "2" ] && ok "нет реестра → код 2, отказ прибора назван" \
               || bad "нет реестра: код $? (ожидался 2) — молчание тут читается как «чисто»"

# --- T4: у каждой строки реестра есть объяснение, зачем понятие в документе ---
# Без него сообщение о пропаже становится «допиши слово», и понятие впишут формально.
_no_why=$(awk -F'\t' 'NF>0 && $1 !~ /^#/ && $1 != "" && ($4 == "" || $4 ~ /^[[:space:]]*$/) {print $1}' "$REG")
[ -z "$_no_why" ] && ok "у каждого понятия названо, зачем оно в документе" \
                  || bad "без объяснения: $_no_why"

echo
echo "docs-concepts: прошло $P, провалено $F"
exit $(( F != 0 ))
