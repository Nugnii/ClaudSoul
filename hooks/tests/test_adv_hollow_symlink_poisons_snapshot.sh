#!/usr/bin/env bash
# СУДИТ: hooks/subject-probe-lib.sh
# АТАКА: предмет — символическая ссылка; выхолащивание бьёт СКВОЗЬ неё и навсегда портит
# снимок для всех следующих свидетелей.
#
# Вход: `hooks/alias.sh` — ссылка на `hooks/one.sh`. Свидетель A объявляет предметом ссылку,
# свидетель B (позже по алфавиту) — сам `hooks/one.sh` и честен.
#
# Ожидание: снимок общий на весь прогон, и после каждого свидетеля он обязан вернуться в
# исходное состояние — договор библиотеки в её шапке: «предмет выхолощен и ВОССТАНОВЛЕН».
#
# Факт: одиночная ветка `sp_hollow_run` (subject-probe-lib.sh:156-191) делает
# `cp "$subj" "$subj.keep"` — копию СОДЕРЖИМОГО цели, — затем `printf … > "$subj"` пишет
# СКВОЗЬ ссылку и выхолащивает `hooks/one.sh`, а восстановление `mv "$subj.keep" "$subj"`
# кладёт на место ссылки обычный файл. Цель остаётся заглушкой до конца прогона: честный
# свидетель B краснеет и на живом предмете, и прибор зачисляет его в «рамка не собралась».
# Тот же ход без ссылки даёт B честным — разница и есть доказательство.
set -uo pipefail

command -v git     >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$REPO/scripts/behavior-condition-probe.sh"
[ -f "$REPO/hooks/subject-probe-lib.sh" ] || { echo "SKIP: нет hooks/subject-probe-lib.sh"; exit 0; }
[ -f "$PROBE" ] || { echo "SKIP: нет $PROBE"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"

D="$TMP/repo"
mkdir -p "$D/scripts" "$D/hooks/tests" "$D/.claude-docs"
cp "$PROBE" "$D/scripts/"
for f in subject-probe-lib.sh frame-control-lib.sh timeout-lib.sh portable-lib.sh; do
    [ -f "$REPO/hooks/$f" ] && cp "$REPO/hooks/$f" "$D/hooks/"
done

printf '#!/usr/bin/env bash\necho M1\n' > "$D/hooks/one.sh"
ln -s one.sh "$D/hooks/alias.sh" || { echo "SKIP: ссылки не создаются"; exit 0; }
{
    printf '#!/usr/bin/env bash\n'
    printf '# СУДИТ: hooks/alias.sh\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'case "$(bash "$R/hooks/alias.sh" 2>&1)" in *M1*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_a_link.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf '# СУДИТ: hooks/one.sh\n'
    printf 'R="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'case "$(bash "$R/hooks/one.sh" 2>&1)" in *M1*) exit 0 ;; *) exit 1 ;; esac\n'
} > "$D/hooks/tests/test_adv_b_honest.sh"
printf 'hooks/one.sh\t\t\t\thooks/tests/test_adv_b_honest.sh\n' > "$D/.claude-docs/dep-index.tsv"

( cd "$D" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) \
    || { echo "SKIP: git не отработал"; exit 0; }

OUT=$( cd "$D" && bash scripts/behavior-condition-probe.sh 2>&1 )
# РАМКА НЕ СОБРАЛАСЬ — КОД 2, А НЕ НОЛЬ (24 сентября 2026, D474). Выхолощенный прибор
# отвечает пустотой, и эта ветка выпускала тест НУЛЁМ — он был зелен на мёртвом
# предмете. Назвал его сам прибор, когда класс «судит сам прибор» перестал быть
# укрытием и все девять его членов впервые получили вердикт.
grep -q 'свидетелей-атак:' <<< "$OUT" || { echo "РАМКА НЕ СОБРАЛАСЬ: прибор не вынес вердикта на подготовленной фикстуре: ${OUT}" >&2; exit 2; }

# Положительный контроль: тот же честный свидетель БЕЗ ссылки в дереве.
rm -f "$D/hooks/tests/test_adv_a_link.sh" "$D/hooks/alias.sh"
( cd "$D" && git add -A && git -c user.email=t@t -c user.name=t commit -qm bez >/dev/null 2>&1 )
CTRL=$( cd "$D" && bash scripts/behavior-condition-probe.sh 2>&1 )
grep -q 'рамка не собралась: 0' <<< "$CTRL" \
    || { echo "SKIP: контроль нечист — честный свидетель красен и без ссылки: $CTRL"; exit 0; }

# E0 — КОНТРОЛЬ РАМКИ: прибор обязан был отработать. Обе ноги ниже судят ОТСУТСТВИЕ имени
# в выводе, а отсутствие имени бывает и оттого, что вывода нет вовсе: с выхолощенной
# библиотекой прибор выходит кодом 2 до всякой печати, и обе ноги зеленели вхолостую.
# Поймал это сам прибор ложной зелени 22 сентября 2026 — тест стоял в его находках.
if grep -q 'свидетелей-атак:' <<< "$OUT"; then ok
else bad E0 "прибор не отработал — судить отсутствие имени не на чем; вывод: $OUT"; fi

# E1 — честный свидетель не должен пострадать от чужого предмета-ссылки.
if grep -q 'test_adv_b_honest' <<< "$OUT"; then
    bad E1 "честный свидетель зачислен в «рамка не собралась» — снимок испорчен ссылкой; вывод: $OUT"
else ok; fi

# E2 — снимок обязан вернуться в исходное состояние после каждого свидетеля.
if grep -q 'рамка не собралась: 0' <<< "$OUT"; then ok
else bad E2 "после свидетеля с предметом-ссылкой снимок остался выхолощенным"; fi

echo "test_adv_hollow_symlink_poisons_snapshot: passed $PASS, failed $FAIL"
exit $(( FAIL != 0 ))
