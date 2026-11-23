#!/usr/bin/env bash
# СУДИТ: scripts/publish-public.sh
# test_adv_pub_gate_order.sh — АТАКА на замкнутость гейта публикации.
#
# ДЫРА: гейт запретных токенов и гейт email СЛЕПЫ к двоичным файлам, а шаг замен их
# ПРОПУСКАЕТ. Три места одного устройства — флаг `-I` у grep:
#   scripts/publish-public.sh:248  `grep -Iq . "$file" 2>/dev/null || continue`  (шаг 3, redact)
#   scripts/publish-public.sh:335  `grep -rIEn -- "$pat" "$STAGE"`               (гейт 4a, запретные)
#   scripts/publish-public.sh:368  `grep -rIEno "…@…" "$STAGE"`                  (гейт 4b, email)
# `-I` велит grep СЧИТАТЬ ДВОИЧНЫЙ ФАЙЛ ПУСТЫМ. Поэтому файл с байтом \x00 (png, pdf,
# sqlite, любой экспорт) проходит все три места нетронутым: замена к нему не применяется,
# оба гейта его не читают, и гейт печатает «шаблонов, email, структура, объём — чисто».
#
# ЧЕМ ДОКАЗАНА. Прогон настоящего scripts/publish-public.sh по песочному репозиторию:
# в docs/assets/shot.png уложен СВОЙ синтетический токен, добавленный в копию forbidden.txt
# песочницы. Прежняя редакция брала настоящие клиентские имена из живого перечня — и вносила
# их в отслеживаемый файл, то есть САМА заводила утечку, которую проверяет (поймано гейтом
# 15 сентября 2026). Токен обязан быть в перечне и БЕЗ правила замены — тогда он ронял бы,
# у которых в redact.sed правила НЕТ намеренно (шапка forbidden.txt: такой токен обязан
# ронять гейт, а не подменяться тихо; тест T2 в test_publish_public.sh это и требует).
# Положи их в .md — гейт краснеет (положительный контроль T0 ниже). Положи те же байты
# в файл с \x00 — гейт зеленеет с кодом 0, а токены доживают до собранного снимка.
# Предмет утечки не выдуман: в дереве трекается docs/assets/knowledge-universe.png, и
# метаданные png (tEXt/iTXt) штатно несут путь автора — `/Users/<имя>/…`.
#
# КРАСНЕЕТ СЕЙЧАС: 2/6, T1 ждёт кода 1, скрипт даёт 0. ЗЕЛЕНЕЕТ ПОСЛЕ ПОЧИНКИ (6/6, проверено
# на копии скрипта): у ОБОИХ гейтов `-I` меняется на `-a` — :335 `grep -arEn`, :368 `grep -arEno`.
# Шаг замен (:248) остаётся как есть: sed по двоичному файлу его портит и валится на BSD sed,
# двоичному носителю запретного место в ОТКАЗЕ гейта, а не в тихой подмене.
#
# Песочный: живое дерево не правится, всё в $HOME/.claudsoul-adv-pubgate.XXXXXX.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"

# Предмет этого свидетеля в публичный снимок не входит (подсистема публикации). В неполном дереве
# «файла нет» значит «изъят по решению», а не «пропал»: пропуск называется, дефект не
# объявляется — иначе один канал несёт два состояния мира (корень R6).
UNIVERSE_ROOT="$REPO_ROOT"; . "$REPO_ROOT/hooks/lib/universe-lib.sh" 2>/dev/null || true
if command -v universe_partial_tree >/dev/null 2>&1 && universe_partial_tree; then
    universe_skip_note "test_adv_pub_gate_order" "подсистема публикации"; exit 0
fi
SCRIPT="$REPO_ROOT/scripts/publish-public.sh"
CONF="$REPO_ROOT/scripts/publish"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
# shellcheck source=/dev/null
. "$REPO_ROOT/hooks/timeout-lib.sh" || { echo "FAIL: нет hooks/timeout-lib.sh"; exit 1; }

PASS=0; FAIL=0
SB=$(mktemp -d "${HOME}/.claudsoul-adv-pubgate.XXXXXX") || exit 1
cleanup() { [ -n "${SB:-}" ] && rm -rf "$SB"; [ -n "${KEPT:-}" ] && rm -rf "$KEPT"; }
trap cleanup EXIT

ok_()   { PASS=$((PASS+1)); }
bad_()  { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
eq_()   { [ "$1" = "$2" ] && ok_ || bad_ "$3" "ожидался '$2', получен '$1'"; }

# Песочный репозиторий с настоящим конфигом публикации.
setup_repo() {
    rm -rf "$SB/repo"
    mkdir -p "$SB/repo/scripts/publish" "$SB/repo/docs/assets" "$SB/repo/knowledge"
    cp "$CONF/exclude.txt" "$CONF/redact.sed" "$CONF/forbidden.txt" "$SB/repo/scripts/publish/"
    # Свой токен дописывается в КОПИЮ перечня: без него признак не сработал бы вовсе, и
    # тест зеленел бы вхолостую. Правила замены ему намеренно не даём — по шапке
    # forbidden.txt такой токен обязан РОНЯТЬ гейт, а не подменяться тихо.
    printf '%s\n' "ZZTESTLEAKTOKEN" >> "$SB/repo/scripts/publish/forbidden.txt"
    cp "$SCRIPT" "$SB/repo/scripts/publish-public.sh"
    echo "9.9.9" > "$SB/repo/VERSION"
    echo "## [9.9.9] - 2026-01-01" > "$SB/repo/CHANGELOG.md"
    local i
    for i in $(seq 1 12); do echo "filler $i" > "$SB/repo/docs/f$i.md"; done
}
commit_repo() {
    ( cd "$SB/repo" && git init -q -b main \
      && git config user.email t@test.local && git config user.name t \
      && git add -A && git commit -q -m init ) >/dev/null 2>&1
}
# Код кладётся в файл, а не в переменную: вывод читается подстановкой, а она — подоболочка,
# и присваивание из неё наружу не выходит (первая редакция этого теста на том и упала).
run_publish() {  # $1 — --keep-stage, если снимок нужен для осмотра (иначе скрипт его сносит сам)
    : > "$SB/out.txt"
    ( cd "$SB/repo" && CLAUDSOUL_MIN_FILES=5 STATE_DIR="$SB/state" \
        bash scripts/publish-public.sh ${1:+"$1"} >"$SB/out.txt" 2>&1 )
    echo $? > "$SB/rc.txt"
    cat "$SB/out.txt"
}
rc_() { cat "$SB/rc.txt"; }

# Одни и те же байты утечки — единственная разница между T0 и T1 — байт \x00 в файле.
LEAK='ZZTESTLEAKTOKEN'   # синтетический: в живом перечне его нет, в копию песочницы допишем

# === T0: положительный контроль — те же токены в ТЕКСТОВОМ файле роняют гейт ===
# Без него зелёный T1 после починки ничего не доказывал бы: может, гейт вообще мёртв.
setup_repo
printf 'заметка: %s\n' "$LEAK" > "$SB/repo/knowledge/leak.md"
commit_repo
OUT=$(run_publish)
eq_ "$(rc_)" "1" "T0: текстовый носитель тех же токенов роняет гейт"
grep -q 'knowledge/leak.md' <<< "$OUT" && ok_ || bad_ "T0" "гейт не назвал файл knowledge/leak.md"

# === T1: АТАКА — те же токены в файле с \x00 проходят гейт ===
setup_repo
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR' > "$SB/repo/docs/assets/shot.png"
printf 'tEXtAuthor\x00%s\x00' "$LEAK"        >> "$SB/repo/docs/assets/shot.png"
commit_repo
OUT=$(run_publish --keep-stage)
eq_ "$(rc_)" "1" "T1: двоичный носитель запретных токенов обязан ронять гейт"
grep -q 'docs/assets/shot.png' <<< "$OUT" && ok_ \
    || bad_ "T1" "гейт не назвал двоичный носитель docs/assets/shot.png"
grep -q 'Гейт не пройден' <<< "$OUT" && ok_ \
    || bad_ "T1" "гейт объявил снимок чистым: $(grep -o 'шаблонов, email, структура, объём — чисто' <<< "$OUT")"

# === T2: токены дожили до СОБРАННОГО снимка — это утечка, а не огрех отчёта ===
KEPT=$(sed -n 's/^Собранное дерево: //p' <<< "$OUT" | tail -1)
if [ -n "$KEPT" ] && [ -f "$KEPT/docs/assets/shot.png" ]; then
    if LC_ALL=C grep -aq 'ZZTESTLEAKTOKEN' "$KEPT/docs/assets/shot.png"; then
        bad_ "T2" "запретный токен дожил до снимка: $KEPT/docs/assets/shot.png"
    else ok_; fi
else
    # Гейт упал ДО сборки снимка — значит дыры нет, это законный зелёный исход.
    ok_
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
