#!/usr/bin/env bash
# test_split_provenance_log.sh — «Проверка результата» инструмента меряет объявленный им результат.
#
# Результат: строка `# Проверка результата:` у scripts/split-provenance-log.py красна на базе, где
#            провенанс-виды ещё лежат внутри modification_history, и зелена после --apply; законные
#            перекройки (narrowed, reinforced_after_challenge) остаются на месте байт в байт.
# Проверка результата: этот тест.
#
# Повод (D282, 3 сентября 2026). До починки строка звала `grep -l 'provenance_log:' …` — след
# прогона (поле где-то появилось), зелёный при ОДНОМ совпавшем файле из 440; замер того дня:
# 83 файла с provenance_log, 59 со строкой modification_history, объявленная проверка rc=0
# независимо от остатка. Команда здесь БЕРЁТСЯ из шапки инструмента и исполняется на подложенной
# базе, как в D274: форма строки — «<команда> даёт 0 — <пояснение>», пояснение ПЕРЕД командой
# сломает извлечение и тест покраснеет громко.
#
# Фикстура — четыре класса файлов: a полуразнесён (narrowed + reinforced в modification_history,
# provenance_log нет), b разнесён, c только narrowed (provenance_log появиться не должен),
# d только reinforced_after_challenge (META.md:180 — перекройка, у которой префикс совпадает с
# провенанс-видом; подстрочный признак унёс бы её). Класс e — provenance_log есть И остаток в
# modification_history — в фикстуру не входит: на нём инструмент сегодня падает RuntimeError
# (:179 против :144-149), это отдельный пункт-кандидат.
#
# T7 и T8 добавлены по разбору критика: без них тест пропускает двух мутантов, которые ЯВЛЯЮТСЯ
# предикатами на объекте результата, — сужение PROVENANCE_KINDS до {"reinforced"} (остаток вида
# contradicted/confirmation живёт вечно, а проверка зелена) и осмотр одного носителя
# (`files[:1] if args.check`). Оба зеленили тест 17/17 до этих ног.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/split-provenance-log.py"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
# Самоссылка отбивается ДО первого запуска и на верхнем уровне (внутри `$(...)` `exit`
# погасил бы только подоболочку): шапка, зовущая сам этот тест, даёт не красный код
# возврата, а неограниченную рекурсию — прожарка 3 сентября 2026: прогон не кончился за
# 120 с, процессов теста 416. Носителей сегодня 0, цена — четыре строки.
case "$(grep -m1 '^# Проверка результата:' "$TOOL")" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
esac

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not found in output"; fi
}
assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' unexpectedly present"
    else PASS=$((PASS + 1)); fi
}
assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: got '$actual', expected '$expected'"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mk_fixture() {
    local d="$1"
    mkdir -p "$d/0"
    printf -- '---\nmodification_history:\n  - date: 2026-01-01\n    kind: narrowed\n    reason: x\n  - date: 2026-01-02\n    kind: reinforced\n    reason: y\n---\n' > "$d/a.md"
    printf -- '---\nmodification_history: []\nprovenance_log:\n  - date: 2026-01-01\n    kind: reinforced\n    reason: x\n---\n' > "$d/b.md"
    printf -- '---\nmodification_history:\n  - date: 2026-01-01\n    kind: narrowed\n    reason: x\n---\n' > "$d/c.md"
    printf -- '---\nmodification_history:\n  - date: 2026-01-01\n    kind: reinforced_after_challenge\n    reason: x\n---\n' > "$d/d.md"
    cp "$d"/[abcd].md "$d/0/"
}
# Объявленная проверка из шапки, путь живой базы заменён на фикстуру. Исполняется из корня репо.
declared_check() {
    local d="$1" cmd
    cmd=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
        | sed -E 's/ (даёт 0|—).*//')
    cmd=${cmd//\~\/.claude\/global-lessons/$d}
    (cd "$REPO" && bash -c "$cmd" >/dev/null 2>&1); echo $?
}
same() { cmp -s "$1" "$2" && echo same || echo differs; }

# --- T1: объявленная проверка КРАСНА на полуразнесённой базе (характеризация: до починки — зелёная) ---
FX="$TMP/fx1"; mk_fixture "$FX"
rc=$(declared_check "$FX")
assert_eq "$([ "$rc" -ne 0 ] && echo red || echo green)" "red" "T1: объявленная проверка красна, пока reinforced лежит в modification_history"

# --- T2: после --apply объявленная проверка зелена, поля разнесены ---
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX" --apply >/dev/null 2>&1); rc_apply=$?
assert_eq "$rc_apply" "0" "T2: --apply даёт 0"
rc=$(declared_check "$FX")
assert_eq "$rc" "0" "T2: объявленная проверка зелена после --apply"
MH=$(sed -n '/^modification_history:/,/^provenance_log:/p' "$FX/a.md")
PL=$(sed -n '/^provenance_log:/,/^---$/p' "$FX/a.md")
assert_contains "$MH" "kind: narrowed" "T2: narrowed остался ПОД modification_history"
assert_not_contains "$MH" "kind: reinforced" "T2: reinforced ушёл из modification_history"
assert_contains "$PL" "kind: reinforced" "T2: reinforced лежит под provenance_log"

# --- T3: b/c/d не тронуты байт в байт ---
for f in b c d; do
    assert_eq "$(same "$FX/$f.md" "$FX/0/$f.md")" "same" "T3: $f.md после --apply не изменился"
done

# --- T4: --check ничего не пишет (и при --check --apply тоже), при остатке даёт 1 ---
FX4="$TMP/fx4"; mk_fixture "$FX4"
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX4" --check >/dev/null 2>&1); rc=$?
assert_eq "$rc" "1" "T4: --check даёт 1 при остатке"
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX4" --check --apply >/dev/null 2>&1)
for f in a b c d; do
    assert_eq "$(same "$FX4/$f.md" "$FX4/0/$f.md")" "same" "T4: --check не пишет ($f.md)"
done

# --- T5: повторный --apply идемпотентен ---
cp "$FX/a.md" "$TMP/a_after_first.md"
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX" --apply >/dev/null 2>&1); rc=$?
assert_eq "$rc" "0" "T5: второй --apply даёт 0"
assert_eq "$(same "$FX/a.md" "$TMP/a_after_first.md")" "same" "T5: второй --apply ничего не меняет"

# --- T6: живая база (только там, где она есть; в CI пропускается) ---
# ПРЕДМЕТ ЭТОГО НАБОРА — СКРИПТ, А НЕ БАЗА ВЛАДЕЛЬЦА (12 сентября 2026, D401, носитель 3).
# Прежняя редакция утверждала `rc == 0`, то есть требовала от ЖИВОЙ базы определённого
# состояния. Но остаток старого провенанса в ней — это состояние мира: он появляется, когда
# знание правят руками или переносят извне, и к исправности скрипта отношения не имеет.
# Красное показание при этом читалось бы как «прибор сломан» и отправляло чинить целое —
# ровно тот класс, ради которого заведён D401. Гейт `-d` отделял только «базы нет вовсе»,
# а «база в другом состоянии» и «скрипт сломан» по-прежнему шли одним значением.
# Теперь состояние базы НАЗЫВАЕТСЯ отдельной строкой и набор от него не краснеет; смерть
# самого прибора (код >= 2) остаётся красной — это уже о скрипте.
if [ -d "$HOME/.claude/global-lessons" ]; then
    (cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$HOME/.claude/global-lessons" --check >/dev/null 2>&1); rc=$?
    if [ "$rc" -ge 2 ]; then
        assert_eq "$rc" "0" "T6: прибор умер на живой базе (код $rc) — это о скрипте, а не о базе"
    elif [ "$rc" -eq 1 ]; then
        echo "  (T6: в живой базе есть остаток провенанса — состояние БАЗЫ, не дефект скрипта;"
        echo "       разнести: python3 scripts/split-provenance-log.py --dir ~/.claude/global-lessons --apply)"
    else
        assert_eq "$rc" "0" "T6: --check по живой базе отработал"
    fi
else
    echo "SKIP T6: живой базы нет"
fi

# --- T7: остаток ДРУГОГО провенанс-вида тоже красен (убивает сужение PROVENANCE_KINDS) ---
# FX уже разнесён (T2/T5). Кладём файл с `kind: contradicted` внутри modification_history:
# проверка обязана снова покраснеть, иначе прибор зовёт базу чистой при живом остатке.
printf -- '---\nmodification_history:\n  - date: 2026-01-04\n    kind: contradicted\n    reason: z\n---\n' > "$FX/z.md"
rc=$(declared_check "$FX")
assert_eq "$([ "$rc" -ne 0 ] && echo red || echo green)" "red" "T7: остаток вида contradicted красит проверку"

# --- T8: остаток НЕ в первом по алфавиту файле каталога (убивает осмотр одного носителя) ---
FX8="$TMP/fx8"; mkdir -p "$FX8"
printf -- '---\nmodification_history:\n  - date: 2026-01-01\n    kind: narrowed\n    reason: x\n---\n' > "$FX8/a_clean.md"
printf -- '---\nmodification_history:\n  - date: 2026-01-02\n    kind: reinforced\n    reason: y\n---\n' > "$FX8/z_dirty.md"
rc=$(declared_check "$FX8")
assert_eq "$([ "$rc" -ne 0 ] && echo red || echo green)" "red" "T8: остаток в последнем файле каталога красит проверку"

# --- T9 (D290): класс «поле есть И остаток внутри» — разбор не падает, запись переносится ---
FX9="$TMP/fx9"; mkdir -p "$FX9"
printf -- '---\nmodification_history:\n  - date: 2026-01-01\n    kind: reinforced\n    reason: x\nprovenance_log:\n  - date: 2026-01-02\n    kind: reinforced\n    reason: y\n---\n' > "$FX9/e.md"
out=$( (cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX9" --check 2>&1) ); rc=$?
assert_not_contains "$out" "Traceback" "T9: --check не падает на классе «поле есть И остаток внутри»"
assert_not_contains "$out" "инвариант строк нарушен" "T9: инвариант не ложно-красен при существующем provenance_log"
assert_eq "$([ "$rc" -le 1 ] && echo ok || echo "rc=$rc")" "ok" "T9: --check отдаёт 0 или 1, а не аварию"
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX9" --apply >/dev/null 2>&1)
assert_eq "$(grep -c 'kind: reinforced' "$FX9/e.md")" "2" "T9: обе провенанс-записи на месте после --apply"
MH9=$(sed -n '/^modification_history:/,/^provenance_log:/p' "$FX9/e.md")
assert_not_contains "$MH9" "kind: reinforced" "T9: в modification_history провенанса не осталось"
rc=$(declared_check "$FX9")
assert_eq "$rc" "0" "T9: после --apply объявленная проверка зелена"

# --- T10 (D301): многострочный скаляр — файл остаётся валидным YAML, а не рвётся ---
FX10="$TMP/fx10"; mkdir -p "$FX10"
printf -- '---\nmodification_history:\n  - date: 2026-01-01\n    kind: reinforced\n    reason: "первая часть\nвторая часть с нулевой колонки"\n---\n' > "$FX10/a.md"
cp "$FX10/a.md" "$TMP/a_multiline_orig.md"
out=$( (cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX10" --apply 2>&1) )
if python3 -c 'import yaml' 2>/dev/null; then
    yamlrc=$(python3 -c '
import pathlib, sys, yaml
t = pathlib.Path(sys.argv[1]).read_text()
try:
    yaml.safe_load(t.split("---")[1]); print("valid")
except Exception:
    print("broken")
' "$FX10/a.md")
    assert_eq "$yamlrc" "valid" "T10: после --apply файл остался валидным YAML"
    assert_eq "$(same "$FX10/a.md" "$TMP/a_multiline_orig.md")" "same" "T10: не смог перенести — не тронул файл"
    assert_contains "$out" "ОТКАЗ" "T10: отказ назван, а не проглочен"
else
    echo "SKIP T10: нет модуля yaml"
fi

# --- T11 (D301): CRLF сохраняется, инвариант «побайтово» не врёт ---
FX11="$TMP/fx11"; mkdir -p "$FX11"
printf -- '---\r\nmodification_history:\r\n  - date: 2026-01-01\r\n    kind: reinforced\r\n    reason: x\r\n---\r\n' > "$FX11/c.md"
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX11" --apply >/dev/null 2>&1)
assert_eq "$(grep -c $'\r' "$FX11/c.md")" "$(wc -l < "$FX11/c.md" | tr -d ' ')" "T11: все строки остались CRLF"
assert_contains "$(cat "$FX11/c.md")" "provenance_log:" "T11: перенос всё же состоялся"

# --- T12 (D301): одно исключение не обрывает прогон ---
FX12="$TMP/fx12"; mkdir -p "$FX12"
printf -- '---\nmodification_history:\n  - date: 2026-01-01\n    kind: reinforced\n    reason: x\nprovenance_log:\n  - date: 2026-01-02\n    kind: reinforced\n    reason: y\n---\n' > "$FX12/a_bad.md"
printf -- '---\nmodification_history:\n  - date: 2026-01-02\n    kind: reinforced\n    reason: y\n---\n' > "$FX12/z_good.md"
out=$( (cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX12" --apply 2>&1) )
assert_contains "$out" "ЗАПИСАНО" "T12: итоговая строка напечатана, прогон не оборвался"
assert_contains "$(cat "$FX12/z_good.md")" "provenance_log:" "T12: файл ПОСЛЕ сбойного всё равно обработан"

# --- T13 (D301): непонятая форма списка не зовётся чистой ---
for form in zero four flow; do
    FXF="$TMP/fx13_$form"; mkdir -p "$FXF"
    case "$form" in
        zero) printf -- '---\nmodification_history:\n- date: 2026-01-01\n  kind: reinforced\n  reason: x\n---\n' > "$FXF/f.md" ;;
        four) printf -- '---\nmodification_history:\n    - date: 2026-01-01\n      kind: reinforced\n      reason: x\n---\n' > "$FXF/f.md" ;;
        flow) printf -- '---\nmodification_history: [{date: 2026-01-01, kind: reinforced, reason: x}]\n---\n' > "$FXF/f.md" ;;
    esac
    if python3 -c 'import yaml' 2>/dev/null; then
        rc=$(declared_check "$FXF")
        assert_eq "$([ "$rc" -ne 0 ] && echo red || echo green)" "red" "T13/$form: остаток в непонятой форме не зеленит проверку"
    else
        echo "SKIP T13/$form: нет модуля yaml"
    fi
done

# --- T14 (D301): YAML-комментарий после kind не прячет остаток ---
FX14="$TMP/fx14"; mkdir -p "$FX14"
printf -- '---\nmodification_history:\n  - date: 2026-01-01\n    kind: reinforced  # почему\n    reason: x\n---\n' > "$FX14/k.md"
rc=$(declared_check "$FX14")
assert_eq "$([ "$rc" -ne 0 ] && echo red || echo green)" "red" "T14: запись с комментарием после kind считается остатком"
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX14" --apply >/dev/null 2>&1)
assert_contains "$(sed -n '/^provenance_log:/,$p' "$FX14/k.md")" "# почему" "T14: комментарий переехал вместе со строкой"

# --- T15 (D302): «предмета нет» отличимо от «результат достигнут» ---
FX15="$TMP/fx15_empty"; mkdir -p "$FX15"
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX15" --check >/dev/null 2>&1); rc=$?
assert_eq "$rc" "2" "T15: пустой каталог даёт код 2, а не 0"
out=$( (cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX15" --check 2>&1) )
assert_contains "$out" "ПРЕДМЕТА НЕТ" "T15: отсутствие предмета названо словами"
rc=$(declared_check "$TMP/нет-такого-каталога")
assert_eq "$([ "$rc" -ne 0 ] && echo red || echo green)" "red" "T15: объявленная проверка красна на машине без базы"
printf -- 'не знание, без frontmatter\n' > "$FX15/plain.md"
(cd "$REPO" && python3 scripts/split-provenance-log.py --dir "$FX15" --check >/dev/null 2>&1); rc=$?
assert_eq "$rc" "2" "T15: файл без frontmatter предметом не считается"

# --- T16 (D302): у самой строки «Проверка результата» есть отрицательный контроль ---
# Код 2 из инструмента держит различение для ТЕХ, кто читает код. Строку из шапки читают и
# глазами, и грепом реестра: без предиката на существование базы она снова становится
# командой, зелёной там, где предмета нет. Мутация «убрать test -d» роняет ровно эту ногу.
HDR=$(grep -m1 '^# Проверка результата:' "$TOOL")
case "$HDR" in
    *"~/"*|*'$HOME'*)
        case "$HDR" in
            *"test -"*|*"[ -"*|*"|| exit"*) PASS=$((PASS + 1)) ;;
            *) FAIL=$((FAIL + 1)); echo "FAIL [T16]: шапка читает живую базу без предиката на её существование" ;;
        esac ;;
    *) PASS=$((PASS + 1)) ;;
esac

echo ""
echo "split-provenance-log tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
