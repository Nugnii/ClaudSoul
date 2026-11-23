#!/usr/bin/env bash
# test_docs_address_drift.sh — свидетель прибора «адрес указывает туда же, куда указывал».
# Предмет: уплывший адрес назван с НОВЫМ номером; целый — молчит; хроника не судится;
# неразличимое ожидание в уплывшие не попадает; грязный документ не судится;
# `--fix` переписывает однозначное и не трогает исчезнувшее.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
TOOL="$REPO_ROOT/scripts/docs-address-drift.py"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Песочница: документ ссылается на строку файла, затем файл РАЗДВИГАЕТСЯ вставкой сверху.
SB="$TMP/repo"; mkdir -p "$SB/hooks" "$SB/docs" "$SB/scripts"
( cd "$SB" && git init -q . && git config user.email t@t && git config user.name t )
printf '#!/usr/bin/env bash\n# первая\n# вторая\nnadezhnaya_stroka_proby=1\n# четвёртая\n' > "$SB/hooks/probe.sh"
printf 'Ссылка на `hooks/probe.sh:4` — опорная строка.\n' > "$SB/docs/live.md"
printf 'Хроника ссылается на `hooks/probe.sh:4` и судиться не должна.\n' > "$SB/CHANGELOG.md"
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )

run() { ( cd "$SB" && CLAUDSOUL_REPO="$SB" python3 "$TOOL" "$@" 2>&1 ); }

# Целый адрес → молчание о нём и код 0.
O=$(run); RC=$?
[ "$RC" = "0" ] && ok || bad T1 "целый адрес признан уплывшим (код $RC): ${O:0:160}"

# Файл раздвинут: опорная строка уехала с 4 на 6. Документ НЕ трогаем — иначе он станет
# грязным и судиться не будет (это отдельная нога ниже).
printf '#!/usr/bin/env bash\n# ноль\n# ещё\n# первая\n# вторая\nnadezhnaya_stroka_proby=1\n# четвёртая\n' > "$SB/hooks/probe.sh"
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm shift >/dev/null 2>&1 )
O2=$(run); RC2=$?
grep -qF "уехала на 6" <<< "$O2" && ok || bad T2 "новый номер не назван: ${O2:0:200}"
[ "$RC2" = "1" ] && ok || bad T2б "при уплывшем адресе код $RC2, а не 1"

# Хроника не судится: её номер был верен, когда писался.
if grep -qF "CHANGELOG.md" <<< "$O2"; then bad T3 "хроника попала под суд"; else ok; fi

# --fix переписывает однозначное.
run --fix >/dev/null 2>&1
grep -qF 'hooks/probe.sh:6' "$SB/docs/live.md" && ok || bad T4 "адрес не починен: $(cat "$SB/docs/live.md")"

# После починки документ ГРЯЗНЫЙ — не судится, иначе честная правка читается как дрейф.
O5=$(run)
# Признак «документ упомянут» с 14 сентября 2026 негоден: имя появляется и в разделе
# «НЕ СУДИЛОСЬ поимённо», где оно и должно быть. Судится строка о ДРЕЙФЕ.
if grep -qE "docs/live.md .*(строка уехала|содержимого больше нет)" <<< "$O5"; then bad T5 "грязный документ судится — починка читается как дрейф"; else ok; fi
grep -qE "правятся сейчас \(не судятся\): [1-9]" <<< "$O5" && ok || bad T5б "грязные не названы числом"

# Неразличимое ожидание в уплывшие не попадает: короткая строка есть везде.
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm fixed >/dev/null 2>&1 )
printf 'Короткая опора: `hooks/probe.sh:2`.\n' > "$SB/docs/short.md"
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm short >/dev/null 2>&1 )
printf '#!/usr/bin/env bash\n# ноль\n# ноль\n# первая\n# вторая\nnadezhnaya_stroka_proby=1\n# четвёртая\n' > "$SB/hooks/probe.sh"
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm dup >/dev/null 2>&1 )
O6=$(run)
if grep -qE "docs/short.md .*(строка уехала|содержимого больше нет)" <<< "$O6"; then bad T6 "неразличимое ожидание объявлено уплывшим"; else ok; fi
grep -qE "ожидание неразличимо: [1-9]" <<< "$O6" && ok || bad T6б "неразличимые не названы числом"

# T7: «НЕ СУДИЛОСЬ» ОТДЕЛЕНО ОТ «ЦЕЛО» И НАЗВАНО ПОИМЁННО (D414, 14 сентября 2026).
# Повод воспроизведён точным совпадением чисел: в час, когда четыре адреса лежали уплывшими,
# прибор напечатал «сверено 85; уплывших: 0; неразличимо: 8» — и на это сослались как на
# «адреса целы». Причина не в границе класса и не в поле зрения: те четыре документа ПРАВИЛИСЬ
# в тот момент, молча выпали из суда, и ноль уплывших относился к другому множеству.
# Нога держит обе стороны: документ, который правят, обязан быть НАЗВАН, а строка про ноль
# уплывших — сказать, о скольких проверенных она говорит.
printf 'Опора: `hooks/probe.sh:6`.\n' > "$SB/docs/dirty.md"
( cd "$SB" && git add -A >/dev/null 2>&1 && git commit -qm dirty >/dev/null 2>&1 )
printf '\nправка в работе\n' >> "$SB/docs/dirty.md"
O7=$(run)
grep -qF "docs/dirty.md — правится сейчас" <<< "$O7" && ok \
    || bad T7 "документ, который правят, не назван поимённо: суд его пропустил молча"
grep -qE "НЕ СУДИЛОСЬ поимённо: [1-9]" <<< "$O7" && ok \
    || bad T7б "нет строки «НЕ СУДИЛОСЬ поимённо» — ноль уплывших снова неотличим от «цело»"
grep -qE "сказано ТОЛЬКО о проверенных [0-9]+" <<< "$O7" && ok \
    || bad T7в "строка про ноль уплывших не называет, о скольких проверенных она говорит"
# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: убери правку — документ обязан ВЕРНУТЬСЯ в суд и исчезнуть
# из перечня «не судилось», иначе нога зеленела бы на любом выводе.
( cd "$SB" && git checkout -- docs/dirty.md >/dev/null 2>&1 )
O7c=$(run)
grep -qF "docs/dirty.md — правится сейчас" <<< "$O7c" && bad T7г "чистый документ всё ещё числится «правится сейчас»" || ok

# --- T8: починка одиночного адреса НЕ портит диапазон рядом (19 сентября 2026) ---
# Повод. `--fix` применял правку голым str.replace, и она била по ПРЕФИКСУ: замена
# `thing.sh:3` → `thing.sh:5` попадала в начало диапазона `thing.sh:3-4`, оставляя конец
# прежним. Так в живом BACKLOG.md появились `defect-class-carriers.py:166-160` и `:566-560` —
# НАЧАЛО ПОСЛЕ КОНЦА, то есть текст, испорченный починкой. Дробь: переписано 5 адресов,
# диапазонов среди них 3, испорчены 3 из 3.
# Прежние ноги этого не ловили: их фикстуры несут ТОЛЬКО одиночные адреса — форма входа была
# взята из образца, а не из мира, где диапазоны стоят в каждом втором пункте долга.
SB8="$TMP/repo8"; mkdir -p "$SB8/scripts" "$SB8/docs"
( cd "$SB8" && git init -q . && git config user.email t@t && git config user.name t )
printf 'aaa\nbbb\nnadezhnaya_stroka_diapazona=1\nccc\nddd\n' > "$SB8/scripts/thing.sh"
printf 'одиночный `scripts/thing.sh:3` и диапазон `scripts/thing.sh:3-4` рядом\n' > "$SB8/docs/note.md"
( cd "$SB8" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
printf 'ZZZ\nZZZ\naaa\nbbb\nnadezhnaya_stroka_diapazona=1\nccc\nddd\n' > "$SB8/scripts/thing.sh"
( cd "$SB8" && git add -A >/dev/null 2>&1 && git commit -qm shift >/dev/null 2>&1 )
( cd "$SB8" && CLAUDSOUL_REPO="$SB8" python3 "$TOOL" --fix >/dev/null 2>&1 )
N8=$(cat "$SB8/docs/note.md")
grep -qF 'scripts/thing.sh:5`' <<< "$N8" && ok || bad T8 "одиночный адрес не починен: $N8"
grep -qF 'scripts/thing.sh:3-4' <<< "$N8" && ok || bad T8б "диапазон испорчен починкой соседа: $N8"

# --- T9: адрес в КОММЕНТАРИИ кода судится и чинится, адрес в строке кода — нет (D1045) ---
# Повод: «смотри файл:строка» в комментарии хука — то же объявление, что в доке, а прибор брал
# только `*.md`; сверка адресов в четыре файла нашла девять уплывших в комментариях кода. В
# строке кода адрес бывает данными (фикстура, образец), поэтому судится только комментарий.
SB9="$TMP/repo9"; mkdir -p "$SB9/hooks"
( cd "$SB9" && git init -q . && git config user.email t@t && git config user.name t )
printf 'aaa\nnadezhnaya_stroka_koda=1\nbbb\n' > "$SB9/hooks/target.sh"
printf '#!/usr/bin/env bash\n# смотри hooks/target.sh:2 — опора\nX="hooks/target.sh:2"  # и здесь hooks/target.sh:2\n' > "$SB9/hooks/caller.sh"
( cd "$SB9" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 )
printf 'ZZZ\naaa\nnadezhnaya_stroka_koda=1\nbbb\n' > "$SB9/hooks/target.sh"
( cd "$SB9" && git add -A >/dev/null 2>&1 && git commit -qm shift >/dev/null 2>&1 )
O9=$( cd "$SB9" && CLAUDSOUL_REPO="$SB9" python3 "$TOOL" 2>&1 ); RC9=$?
grep -qF "hooks/caller.sh → hooks/target.sh:2 — строка уехала на 3" <<< "$O9" && ok || bad T9 "адрес в комментарии кода не назван: ${O9:0:240}"
[ "$(grep -c 'hooks/caller.sh → hooks/target.sh:2 — строка уехала' <<< "$O9")" = "2" ] && ok \
    || bad T9б "судимых адресов не два (два комментария, строка кода не в счёт): ${O9:0:240}"
[ "$RC9" = "1" ] && ok || bad T9в "при уплывшем адресе в коде код $RC9, а не 1"
( cd "$SB9" && CLAUDSOUL_REPO="$SB9" python3 "$TOOL" --fix >/dev/null 2>&1 )
N9=$(cat "$SB9/hooks/caller.sh")
grep -qF '# смотри hooks/target.sh:3 — опора' <<< "$N9" && ok || bad T9г "адрес в комментарии не починен: $N9"
grep -qF 'X="hooks/target.sh:2"  # и здесь hooks/target.sh:3' <<< "$N9" && ok \
    || bad T9д "починка тронула строку кода либо не дошла до хвостового комментария: $N9"

echo "test_docs_address_drift: прошло $PASS, упало $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
