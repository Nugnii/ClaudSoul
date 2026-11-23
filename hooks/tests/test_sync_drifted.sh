#!/usr/bin/env bash
# СУДИТ: scripts/sync-drifted.sh
# test_sync_drifted.sh — синхронизатор чинит названное расхождение и не трогает лишнего.
#
# Повод (D316). Дрейф из шести хуков прожил сутки: `drift-check` называл его, а починка
# была одна — полный `install.sh`, который правит четыре области разом. Инструмент,
# соразмерный находке, обязан доказать три вещи, и все три проверяются здесь: он ЧИНИТ
# названное, НЕ ПИШЕТ в сухом прогоне и НЕ ТРОГАЕТ чужое.
#
# Отдельная нога — НЕЗНАКОМАЯ пара: сверщик обзаведётся новой, а синхронизатор о ней не
# узнает. Молчание в этом месте неотличимо от «чинить было нечего» — тот же род, что
# закрывает `hooks/lib/unread-lib.sh`: отказ обязан быть слышен.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SYNC="${SYNC_DRIFTED:-$ROOT/scripts/sync-drifted.sh}"
[ -f "$SYNC" ] || { echo "FAIL: нет $SYNC"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Песочница-приёмник: копия репозитория по тем путям, куда ставит install.sh.
HOME_OK="$TMP/home"
mkdir -p "$HOME_OK/hooks/lib" "$HOME_OK/commands" "$HOME_OK/bin" "$HOME_OK/templates" \
         "$HOME_OK/global-lessons"
cp "$ROOT"/hooks/*.sh "$HOME_OK/hooks/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }
cp "$ROOT"/hooks/lib/* "$HOME_OK/hooks/lib/" 2>/dev/null || true  # в hooks/lib/ есть каталог (__pycache__): cp краснеет на нём, все файлы скопированы
cp "$ROOT"/bin/resolve-claudsoul-repo.sh "$HOME_OK/bin/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }
cp "$ROOT"/templates/*.tmpl "$HOME_OK/templates/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }
cp "$ROOT"/scripts/statusline-claudsoul.sh "$HOME_OK/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }
_SK="$ROOT/skills"
for d in "$_SK"/*/; do
    n=$(basename "$d")
    mkdir -p "$HOME_OK/commands/$n"
    cp "$d"SKILL.md "$HOME_OK/commands/$n/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }
    if [ -d "$d/references" ]; then
        mkdir -p "$HOME_OK/commands/$n/references"
        cp "$d"references/* "$HOME_OK/commands/$n/references/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }
    fi
done
# shellcheck source=/dev/null
. "$ROOT/lib/claude-md-merge.sh" 2>/dev/null && _cm_write_managed_block "$ROOT/rules/CLAUDE.md" > "$HOME_OK/CLAUDE.md"
# Seed и регистрация — тоже пары сверщика. Без них «согласованное дерево» песочницы
# согласованным НЕ является, и нога T7 краснела на дрейфе, которого сама же не положила.
cp "$ROOT"/knowledge/*.md "$HOME_OK/global-lessons/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }
# Сторож секретов — тоже пара сверщика (10 сентября 2026). Без неё «согласованное дерево»
# опять оказывалось несогласованным, и T7 краснела на дрейфе, которого сама не клала, —
# ровно то, что описано двумя строками выше про seed и регистрацию. Третий раз один класс:
# фикстура ПЕРЕЧИСЛЯЕТ, что копировать, и отстаёт от установщика на каждую новую семью.
# НАЗВАННЫЙ ПРЕДЕЛ: перечень остаётся перечнем. Свести его к правилу можно только вызовом
# самого install.sh в песочницу, а он ставит launchd-агенты и регистрирует MCP — побочные
# действия вне песочницы. Условие снятия: у установщика появится режим, кладущий ТОЛЬКО
# файлы в указанный CLAUDE_HOME, и фикстура станет звать его.
mkdir -p "$HOME_OK/security"
cp "$ROOT"/security/* "$HOME_OK/security/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }
python3 "$ROOT/hooks/tests/_decl_hooks.py" "$ROOT/install.sh" > "$HOME_OK/settings.json" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_sync_drifted.sh:$LINENO" >&2; exit 1; }

run() { CLAUDE_HOME="$1" CLAUDSOUL_REPO="$ROOT" bash "$SYNC" "${2:---dry-run}" 2>&1; }

# --- T1: сухой прогон НАЗЫВАЕТ разошедшийся файл и НИЧЕГО не пишет ---
H1="$TMP/h1"; cp -R "$HOME_OK" "$H1"
printf '\n# ПОДЛОЖЕННОЕ РАСХОЖДЕНИЕ\n' >> "$H1/hooks/trust-guard.sh"
BEFORE=$(cksum < "$H1/hooks/trust-guard.sh")
OUT=$(run "$H1")
case "$OUT" in *trust-guard.sh*) ok ;; *) bad "T1" "файл не назван: $OUT" ;; esac
AFTER=$(cksum < "$H1/hooks/trust-guard.sh")
[ "$BEFORE" = "$AFTER" ] && ok || bad "T1b" "сухой прогон ИЗМЕНИЛ файл"

# --- T2: --apply чинит, и сверщик после этого молчит ---
OUT=$(run "$H1" --apply)
case "$OUT" in *trust-guard.sh*) ok ;; *) bad "T2" "перенос не назван: $OUT" ;; esac
if cmp -s "$ROOT/hooks/trust-guard.sh" "$H1/hooks/trust-guard.sh"; then ok
else bad "T2b" "файл не приведён к репозиторию"; fi
D=$(CLAUDE_HOME="$H1" CLAUDSOUL_REPO="$ROOT" bash "$ROOT/hooks/tests/drift-check.sh" 2>/dev/null | grep '^DRIFT|хуки')
[ -z "$D" ] && ok || bad "T2c" "после починки сверщик всё ещё видит дрейф: $D"

# --- T3: чужой файл в установке не тронут ---
H3="$TMP/h3"; cp -R "$HOME_OK" "$H3"
printf '# чужой хук машины\n' > "$H3/hooks/alien-local.sh"
printf '\n# ПОДЛОЖЕННОЕ\n' >> "$H3/hooks/trust-guard.sh"
run "$H3" --apply >/dev/null
if [ -f "$H3/hooks/alien-local.sh" ]; then ok; else bad "T3" "чужой хук удалён"; fi

# --- T4: НЕЗНАКОМАЯ пара названа, а не пропущена молча ---
STUB="$TMP/stub-check.sh"
printf '#!/usr/bin/env bash\nprintf "DRIFT|новая пара|3|1| нечто\\n"\n' > "$STUB"
OUT=$(CLAUDE_HOME="$HOME_OK" CLAUDSOUL_REPO="$ROOT" DRIFT_CHECK="$STUB" bash "$SYNC" --dry-run 2>&1)
case "$OUT" in *неизвестна*) ok ;; *) bad "T4" "незнакомая пара пропущена молча: $OUT" ;; esac

# --- T5: BROKEN сверщика — отказ, а не тихая починка ---
STUB2="$TMP/stub-broken.sh"
printf '#!/usr/bin/env bash\nprintf "BROKEN|корень|0|0|не разрешился\\n"\n' > "$STUB2"
CLAUDE_HOME="$HOME_OK" CLAUDSOUL_REPO="$ROOT" DRIFT_CHECK="$STUB2" bash "$SYNC" --apply >/dev/null 2>&1
RC=$?
[ "$RC" = "2" ] && ok || bad "T5" "на BROKEN код возврата $RC (ожидался 2)"

# --- T6: seed знаний НЕ синхронизируется (база владельца, а не файлы программы) ---
STUB3="$TMP/stub-seed.sh"
printf '#!/usr/bin/env bash\nprintf "DRIFT|seed знаний|3|1| knowledge/(генерируемые)\\n"\n' > "$STUB3"
OUT=$(CLAUDE_HOME="$HOME_OK" CLAUDSOUL_REPO="$ROOT" DRIFT_CHECK="$STUB3" bash "$SYNC" --apply 2>&1)
case "$OUT" in *"НЕ синхронизируется"*) ok ;; *) bad "T6" "seed не назван исключением: $OUT" ;; esac

# --- T6d: `knowledge/META.md` — файл программы, переносится, а генерируемый seed рядом остаётся человеку (D1061) ---
H6D="$TMP/home6d"; mkdir -p "$H6D/global-lessons"; echo старая > "$H6D/global-lessons/META.md"
STUB6D="$TMP/stub-seed-meta.sh"
printf '#!/usr/bin/env bash\nprintf "DRIFT|seed знаний|3|2| knowledge/(генерируемые) knowledge/META.md\\n"\n' > "$STUB6D"
OUT=$(CLAUDE_HOME="$H6D" CLAUDSOUL_REPO="$ROOT" DRIFT_CHECK="$STUB6D" bash "$SYNC" --apply 2>&1)
cmp -s "$ROOT/knowledge/META.md" "$H6D/global-lessons/META.md" && ok || bad "T6d" "META не перенесена в рабочую базу: $OUT"
case "$OUT" in *"НЕ синхронизируется"*"генерируемые"*) ok ;; *) bad "T6d" "генерируемый seed рядом с META не назван исключением: $OUT" ;; esac

# --- T6b/T6c: у дрейфа ТОЛЬКО seed свой код 3, у смешанного — прежний 1 (D354) ---
# Предмет: «seed отстал» и «хук не доставлен» — разные состояния мира с разными решениями
# (пересобрать к релизу против перенести сейчас), а до 12 сентября 2026 они выходили одним
# кодом. Потребителю оставалось разбирать текст, то есть держать вторую копию правила.
# ОБЕ ноги обязательны вместе: одна зелёная доказывала бы только, что код когда-то равен 3,
# но не то, что проверка РАЗЛИЧАЕТ состояния — контроль смешанного дрейфа и есть различение.
CLAUDE_HOME="$HOME_OK" CLAUDSOUL_REPO="$ROOT" DRIFT_CHECK="$STUB3" bash "$SYNC" --dry-run >/dev/null 2>&1
RC6b=$?
[ "$RC6b" = "3" ] && ok || bad "T6b" "дрейф ТОЛЬКО в seed вернул $RC6b (ожидался 3 — норма до релиза)"

STUB3M="$TMP/stub-seed-and-hook.sh"
printf '#!/usr/bin/env bash\nprintf "DRIFT|seed знаний|3|1| knowledge/(генерируемые)\\nDRIFT|хуки|106|1| trust-guard.sh\\n"\n' > "$STUB3M"
CLAUDE_HOME="$HOME_OK" CLAUDSOUL_REPO="$ROOT" DRIFT_CHECK="$STUB3M" bash "$SYNC" --dry-run >/dev/null 2>&1
RC6c=$?
[ "$RC6c" = "1" ] && ok || bad "T6c" "seed ВМЕСТЕ с недоставленным хуком вернул $RC6c (ожидался 1): код 3 поглотил настоящее отставание"

# --- T7: на согласованном дереве — «нечего», код 0 ---
OUT=$(run "$HOME_OK"); RC=$?
case "$OUT" in *"нечего"*) ok ;; *) bad "T7" "на чистом дереве: $OUT" ;; esac
[ "$RC" = "0" ] && ok || bad "T7b" "код возврата на чистом дереве: $RC"

# --- T8: неизвестный аргумент — отказ, а не молчаливый сухой прогон ---
CLAUDE_HOME="$HOME_OK" CLAUDSOUL_REPO="$ROOT" bash "$SYNC" --whatever >/dev/null 2>&1
[ "$?" = "2" ] && ok || bad "T8" "неизвестный аргумент принят"

# --- T9: библиотека хуков (имя приходит с префиксом lib/) ---
H9="$TMP/h9"; cp -R "$HOME_OK" "$H9"
_LIBF=$(basename "$(ls "$ROOT"/hooks/lib/*.sh 2>/dev/null | head -1)")
if [ -n "$_LIBF" ] && [ -f "$H9/hooks/lib/$_LIBF" ]; then
    printf '\n# ПОДЛОЖЕННОЕ\n' >> "$H9/hooks/lib/$_LIBF"
    run "$H9" --apply >/dev/null
    if cmp -s "$ROOT/hooks/lib/$_LIBF" "$H9/hooks/lib/$_LIBF"; then ok
    else bad "T9" "библиотека не синхронизирована (префикс lib/ не снят?)"; fi
else
    ok    # библиотек нет — доказывать нечего
fi

# --- T10: пара «правила» — блок между маркерами реально переносится ---
# Ноги на эту пару не было, и первая редакция скрипта звала НЕСУЩЕСТВУЮЩУЮ функцию:
# сообщение «слияние не удалось» печаталось честно, а прибор оставался зелёным.
H10="$TMP/h10"; cp -R "$HOME_OK" "$H10"
if [ -f "$H10/CLAUDE.md" ]; then
    # Портим ВНУТРИ блока: сверщик по замыслу сравнивает только область между маркерами,
    # снаружи живёт текст владельца. Первая редакция ноги дописывала строку В КОНЕЦ файла —
    # то есть за маркером конца, — сверщик честно печатал OK, и нога была зелена на
    # сломанном скрипте (мутация «выдуманная функция слияния» её не убивала).
    awk 'NR==2 {print "<!-- подложенное расхождение -->"} {print}' "$H10/CLAUDE.md" > "$H10/CLAUDE.md.tmp" \
        && mv "$H10/CLAUDE.md.tmp" "$H10/CLAUDE.md"
    run "$H10" --apply >/dev/null 2>&1
    D10=$(CLAUDE_HOME="$H10" CLAUDSOUL_REPO="$ROOT" bash "$ROOT/hooks/tests/drift-check.sh" 2>/dev/null | grep '^DRIFT|правила')
    [ -z "$D10" ] && ok || bad "T10" "после переноса пара «правила» всё ещё в дрейфе: $D10"
else
    ok    # блока правил в песочнице нет — доказывать нечего
fi

# --- T11: пара «сторож секретов» реально переносится ---
# Ветку добавили 10 сентября 2026 вместе с парой, и первая её проверка НИЧЕГО не доказывала:
# семья к тому времени лежала в согласованном дереве, дрейфа не было, ветка не вызывалась —
# мутация «снять ветку» оставляла тест зелёным (`case-2026-09-07-mutation-that-changes-nothing-proves-nothing`).
# Здесь дрейф КЛАДЁТСЯ намеренно, и проверяется состояние мира после переноса.
H11="$TMP/h11"; cp -R "$HOME_OK" "$H11"
_sec_one=$(basename "$(find "$ROOT/security" -maxdepth 1 -type f | sort | head -1)" 2>/dev/null)
if [ -n "$_sec_one" ] && [ -f "$H11/security/$_sec_one" ]; then
    printf '# подложенное расхождение\n' >> "$H11/security/$_sec_one"
    run "$H11" --apply >/dev/null 2>&1
    if cmp -s "$ROOT/security/$_sec_one" "$H11/security/$_sec_one"; then ok
    else bad "T11" "после переноса файл сторожа секретов всё ещё расходится: $_sec_one"; fi
    D11=$(CLAUDE_HOME="$H11" CLAUDSOUL_REPO="$ROOT" bash "$ROOT/hooks/tests/drift-check.sh" 2>/dev/null | grep '^DRIFT|сторож')
    [ -z "$D11" ] && ok || bad "T11b" "пара всё ещё в дрейфе: $D11"
else
    bad "T11" "песочница без файлов сторожа секретов — доказывать нечего, а семья в паре есть"
fi

# --- T9/T10: КОД ВОЗВРАТА отличает «дрейф есть» от «чисто» ---
# Повод, 7 сентября 2026. Сторож на Stop обязан узнать о дрейфе машинно. Пока скрипт
# возвращал 0 в обоих случаях, потребителю оставалось разбирать текст — то есть заводить
# у себя копию правила «что считается дрейфом» (род K реестра). Контракт как у diff:
# 0 — расхождения нет, 1 — есть, 2 — сверщик сломан (T5). У --apply смысл иной: там 0
# означает «перенос удался», иначе всякая успешная починка выглядела бы отказом.
H9="$TMP/h9"; cp -R "$HOME_OK" "$H9"
printf '\n# ПОДЛОЖЕННОЕ РАСХОЖДЕНИЕ\n' >> "$H9/hooks/trust-guard.sh"
CLAUDE_HOME="$H9" CLAUDSOUL_REPO="$ROOT" bash "$SYNC" --dry-run >/dev/null 2>&1
RC9=$?
[ "$RC9" = "1" ] && ok || bad "T9" "сухой прогон при ДРЕЙФЕ вернул $RC9 (ожидался 1)"

CLAUDE_HOME="$H9" CLAUDSOUL_REPO="$ROOT" bash "$SYNC" --apply >/dev/null 2>&1
RC10=$?
[ "$RC10" = "0" ] && ok || bad "T10" "успешный перенос вернул $RC10 (ожидался 0)"
# и после переноса сухой прогон обязан снова говорить «чисто» — иначе код 1 не о дрейфе
CLAUDE_HOME="$H9" CLAUDSOUL_REPO="$ROOT" bash "$SYNC" --dry-run >/dev/null 2>&1
RC10b=$?
[ "$RC10b" = "0" ] && ok || bad "T10b" "после переноса сухой прогон вернул $RC10b (ожидался 0)"


# --- T12: журнал переносов и третий исход «разошлось в обе стороны» (ADR-019, D350) ---
# Перенос записывается с хешем приёмника; правка приёмника ПОСЛЕ нашего переноса не
# перезаписывается ни сухим прогоном (он её называет), ни --apply (отказ, код 1, файл назван).
H12="$TMP/h12"; cp -R "$HOME_OK" "$H12"
printf '\n# ПОДЛОЖЕННОЕ РАСХОЖДЕНИЕ\n' >> "$H12/hooks/trust-guard.sh"
run "$H12" --apply >/dev/null 2>&1
LOG12="$H12/hooks/state/carry-log.tsv"
if [ -f "$LOG12" ] && grep -q "hooks/trust-guard.sh" "$LOG12"; then ok; else bad "T12" "перенос не записан в журнал $LOG12"; fi
. "$ROOT/lib/carry-log.sh"
H12HASH=$(awk -F'\t' '$4 ~ /hooks\/trust-guard\.sh$/ { h = $5 } END { print h }' "$LOG12" 2>/dev/null)
if [ -n "$H12HASH" ] && [ "$H12HASH" = "$(carry_hash "$H12/hooks/trust-guard.sh")" ]; then ok
else bad "T12b" "хеш записи «${H12HASH}» не равен хешу приёмника после переноса"; fi
printf '\n# ПРАВКА ВЛАДЕЛЬЦА ПРЯМО В ~/.claude\n' >> "$H12/hooks/trust-guard.sh"
B12=$(cksum < "$H12/hooks/trust-guard.sh")
OUT=$(run "$H12")
case "$OUT" in *"В ОБЕ СТОРОНЫ"*) ok ;; *) bad "T12c" "сухой прогон не назвал третий исход: $OUT" ;; esac
case "$OUT" in *trust-guard.sh*) ok ;; *) bad "T12c2" "сухой прогон не назвал файл: $OUT" ;; esac
case "$OUT" in *"отказано в переносе: 1"*) ok ;; *) bad "T12d" "итог сухого прогона не считает отказ: $OUT" ;; esac
[ "$(cksum < "$H12/hooks/trust-guard.sh")" = "$B12" ] && ok || bad "T12d2" "сухой прогон изменил приёмник"
OUT=$(run "$H12" --apply); RC12=$?
[ "$RC12" = "1" ] && ok || bad "T12e" "--apply при третьем исходе вернул $RC12 (ожидался 1: часть не перенесена)"
[ "$(cksum < "$H12/hooks/trust-guard.sh")" = "$B12" ] && ok || bad "T12f" "--apply перезаписал правку владельца"
case "$OUT" in *trust-guard.sh*) ok ;; *) bad "T12g" "--apply не назвал файл: $OUT" ;; esac
[ "$(grep -c "hooks/trust-guard.sh" "$LOG12")" = "1" ] && ok || bad "T12h" "отказ записан в журнал как перенос"
# Приёмник, о котором журнал не знает (положен до его появления), переносится как прежде и
# получает первую запись — названный предел библиотеки.
H12B="$TMP/h12b"; cp -R "$HOME_OK" "$H12B"
printf '\n# СТАРЫЙ ПРИЁМНИК БЕЗ ЗАПИСИ\n' >> "$H12B/hooks/trust-guard.sh"
run "$H12B" --apply >/dev/null 2>&1
cmp -s "$ROOT/hooks/trust-guard.sh" "$H12B/hooks/trust-guard.sh" && ok || bad "T12i" "приёмник без записи не перенесён"
[ "$(grep -c "hooks/trust-guard.sh" "$H12B/hooks/state/carry-log.tsv" 2>/dev/null)" = "1" ] && ok || bad "T12j" "первая запись приёмника не сделана"

echo "sync-drifted: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
