#!/usr/bin/env bash
# СУДИТ: scripts/witness-subject-propose.sh
# АТАКА: объявлятель СУДИТ коммит, а ПИШЕТ в рабочую копию — это разные файлы.
#
# Перечень неразрешённых собирается по РАБОЧЕМУ дереву (glob в behavior-condition-probe.sh),
# прогон идёт в снимке `git clone --local` (witness-subject-propose.sh:70), то есть по HEAD,
# а строка `# СУДИТ:` вписывается в рабочую копию (:109-118). Ни сверки, ни предупреждения
# о грязном дереве нет.
#
# B1. Свидетель закоммичен судящим hooks/one.sh, затем переписан — теперь судит hooks/two.sh.
#     Ожидание: объявление описывает ТОТ файл, в который вписано (либо объявлятель отказывается,
#     назвав расхождение). Факт: в файл, судящий two.sh, вписано `# СУДИТ: hooks/one.sh`.
#     Цена не косметическая: прибор потом выхолащивает one.sh, свидетель остаётся зелёным и
#     попадает в «ложно-зелёные» — объявлятель ПРОИЗВОДИТ ровно тот дефект, который ищет прибор.
# B2. Свидетель только что написан и ещё не закоммичен — главный случай, ради которого приём
#     и заведён. Ожидание: предмет предложен. Факт: в снимке файла нет, `bash "$t"` даёт 127,
#     и честный свидетель записан в класс «рамка не собралась» — оператора посылают чинить
#     несуществующую поломку.
set -uo pipefail

command -v git     >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# ПЕСОЧНИЦА ОЧИЩАЕТ ЧУЖОЙ КОРЕНЬ (23 сентября 2026, находка замера instrument-result-measured).
# Тест строит СВОЁ дерево и зовёт в нём объявлятель, а тот зовёт прибор. Если в окружении
# осталась переменная корня от зовущего (а приборы её ставят — так делает и сам
# instrument-result-measured), вложенный прибор уходит судить ЧУЖОЕ дерево, возвращает пустой
# перечень, и объявлятель честно отвечает «объявлять нечего». Контраст прямой: с переменной
# 9 ног красных, без неё 9 из 9 зелёных.
unset CLAUDSOUL_REPO CLAUDSOUL_ROOT

TOOL="$REPO/scripts/witness-subject-propose.sh"
[ -f "$TOOL" ] || { echo "SKIP: нет $TOOL"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"

build() {  # build <каталог>
    local d="$1"
    mkdir -p "$d/scripts" "$d/hooks/tests" "$d/.claude-docs"
    cp "$TOOL" "$REPO/scripts/behavior-condition-probe.sh" "$d/scripts/"
    # Сторож срока — сосед библиотеки выхолащивания, и без него она отвечает BROKEN. Забыли его
    # 22 сентября 2026; на машине автора это маскировал фоллбек на ~/.claude, а замер suite-linux
    # в чистом контейнере показал настоящее (23 сентября 2026).
    cp "$REPO/hooks/subject-probe-lib.sh" "$REPO/hooks/frame-control-lib.sh" \
       "$REPO/hooks/state-lock-lib.sh" "$REPO/hooks/timeout-lib.sh" "$d/hooks/"
    [ -f "$REPO/hooks/portable-lib.sh" ] && cp "$REPO/hooks/portable-lib.sh" "$d/hooks/"
    printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$d/hooks/one.sh"
    printf '#!/usr/bin/env bash\necho SECOND\nexit 0\n' > "$d/hooks/two.sh"
    # Два кандидата у индекса — иначе предмет однозначен и свидетель в перечень не попадёт.
    {
        printf 'hooks/one.sh\t\t\t\t%s\n' "$2"
        printf 'hooks/two.sh\t\t\t\t%s\n' "$2"
    } > "$d/.claude-docs/dep-index.tsv"
}

witness() {  # witness <файл> <механизм> <маркер>
    {
        printf '#!/usr/bin/env bash\n'
        printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
        printf 'case "$(bash "$R/hooks/%s" 2>&1)" in *%s*) exit 0 ;; *) exit 1 ;; esac\n' "$2" "$3"
    } > "$1"
}

# ── B1: рабочая копия разошлась с коммитом ──────────────────────────────────────────────
D1="$TMP/drift"
build "$D1" "hooks/tests/test_adv_drift.sh"
witness "$D1/hooks/tests/test_adv_drift.sh" one.sh MARKER
( cd "$D1" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }
# правка есть, коммита ещё нет: теперь свидетель судит two.sh
witness "$D1/hooks/tests/test_adv_drift.sh" two.sh SECOND

( cd "$D1" && bash scripts/witness-subject-propose.sh --apply >/dev/null 2>&1 )
DECL=$(sed -n '2p' "$D1/hooks/tests/test_adv_drift.sh")

case "$DECL" in
    "# СУДИТ: hooks/two.sh") ok ;;
    "# СУДИТ: hooks/one.sh")
        bad B1 "в свидетеля, судящего two.sh, вписано «${DECL}» — предмет взят из коммита, а строка легла в рабочую копию" ;;
    "") ok ;;  # отказ без записи — законный исход: расхождение названо, данные не испорчены
    *) bad B1 "неожиданное объявление: «${DECL}»" ;;
esac

# ── B2: свидетель написан, но ещё не закоммичен ─────────────────────────────────────────
D2="$TMP/fresh"
build "$D2" "hooks/tests/test_adv_fresh.sh"
( cd "$D2" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }
witness "$D2/hooks/tests/test_adv_fresh.sh" one.sh MARKER   # не коммитится намеренно

OUT=$( cd "$D2" && bash scripts/witness-subject-propose.sh 2>&1 )

if grep -q '^# СУДИТ: hooks/one.sh	hooks/tests/test_adv_fresh.sh$' <<< "$OUT"; then ok
else bad B2 "новому свидетелю предмет не предложен; вывод: $OUT"; fi

if grep -q 'рамка не собралась: hooks/tests/test_adv_fresh.sh' <<< "$OUT"; then
    bad B2b "честный свидетель записан в «рамка не собралась» — его просто нет в снимке HEAD"
else ok; fi

echo "test_adv_propose_head_vs_worktree: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
