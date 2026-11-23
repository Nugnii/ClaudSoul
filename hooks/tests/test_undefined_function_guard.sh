#!/usr/bin/env bash
# СУДИТ: hooks/activity-flush-lib.sh hooks/authorization-lib.sh hooks/backlog-lib.sh hooks/command-scope-lib.sh hooks/detection-signals-lib.sh hooks/disagreement-lib.sh hooks/docs-derived-lib.sh hooks/frame-control-lib.sh hooks/hash-lib.sh hooks/hook-input-lib.sh hooks/intrusiveness-cost-lib.sh hooks/intrusiveness-metrics-lib.sh hooks/intrusiveness-state-lib.sh hooks/lib/universe-lib.sh hooks/lib/write_targets.py hooks/portable-lib.sh hooks/root-cause-lib.sh hooks/session-registry-lib.sh hooks/state-lock-lib.sh hooks/throttle-lib.sh hooks/undefined-function-check.sh
# test_undefined_function_guard.sh — вызов функции, которой нет, называется в момент записи.
#
# Повод (D318, 6 сентября 2026). `scripts/sync-drifted.sh` звал `_cm_merge_into`, которого
# не существует: имя было достроено по образцу соседнего `_cm_write_managed_block`,
# увиденного у ПОТРЕБИТЕЛЯ библиотеки, а сама библиотека прочитана не была. Оболочка такой
# вызов не проверяет: он синтаксически верен, проходит `bash -n`, и всплывает лишь в
# рантайме общим ненулевым кодом — неотличимым от «функция отработала с ошибкой».
#
# Половина ног — ОТРИЦАТЕЛЬНЫЕ. Признак «имя в позиции команды» ловит переменные чужого
# языка (python, awk, jq внутри heredoc и кавычек): сырая его версия дала 65 ложных на этом
# же дереве при 0 настоящих. Тревога, которая врёт, хуже отсутствия тревоги.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${UNDEF_GUARD:-$ROOT/hooks/undefined-function-check.sh}"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
# Словарь утверждений — общий с остальными приборами проекта: по нему `test_guards_provable`
# отличает проверку СРАБАТЫВАНИЯ от проверки ТИШИНЫ. Свои формы (`case … in *X*)`) читаются
# человеком так же, а мета-стражем — нет.
assert_contains() { if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' нет в: $1"; fi; }
assert_empty()    { if [ -z "$1" ]; then ok; else bad "$2" "ожидалась тишина, получено: $1"; fi; }

TMP=$(mktemp -d)
# Уборка ЗАКЛАДЫВАЕТСЯ ДО первого запуска и охватывает всё, что нога пишет ВНЕ песочницы.
# T8 создаёт фикстуру в КОРНЕ репозитория (иначе не воспроизвести предмет — запись через
# оболочку), и голый `rm` после команды не исполняется, если тест убит по таймауту: 7 сентября
# 2026 `.probe-undef.sh` пережил такой прогон и всплыл в `git status` чужого коммита
# (pattern-external-test-write-teardown).
trap 'rm -rf "$TMP"' EXIT

# Прогон: подаём хуку PostToolUse по указанному файлу.
run_write() {  # $1 — путь файла
    printf '{"session_id":"t","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" \
        | CLAUDSOUL_REPO="$ROOT" bash "$HOOK" 2>/dev/null
}

# --- T1: выдуманное имя названо ---
cat > "$TMP/a.sh" <<'PROBE'
#!/usr/bin/env bash
. lib/claude-md-merge.sh
_cm_merge_into "$A" "$B"
PROBE
OUT=$(run_write "$TMP/a.sh")
assert_contains "$OUT" "_cm_merge_into" "T1: выдуманное имя названо"

# --- T2: НАСТОЯЩАЯ функция библиотеки — тишина ---
cat > "$TMP/b.sh" <<'PROBE'
#!/usr/bin/env bash
. lib/claude-md-merge.sh
sync_claude_md "$TARGET" "$MASTER"
PROBE
OUT=$(run_write "$TMP/b.sh")
assert_empty "$OUT" "T2: настоящая функция библиотеки"

# --- T3: переменная python внутри heredoc — не вызов ---
cat > "$TMP/c.sh" <<'PROBE'
#!/usr/bin/env bash
python3 - <<'PY'
min_id = int(os.environ.get("X", "1"))
max_runs = 3
PY
PROBE
OUT=$(run_write "$TMP/c.sh")
assert_empty "$OUT" "T3: переменная python в heredoc"

# --- T4: переменная awk внутри одинарных кавычек — не вызов ---
cat > "$TMP/d.sh" <<'PROBE'
#!/usr/bin/env bash
awk '
    in_fm && /^attributes:/ { in_attrs = 1; next }
    { src_state = "written" }
' file
PROBE
OUT=$(run_write "$TMP/d.sh")
assert_empty "$OUT" "T4: переменная awk в кавычках"

# --- T5: динамическое имя не ловится (значение неизвестно до исполнения) ---
cat > "$TMP/e.sh" <<'PROBE'
#!/usr/bin/env bash
fn=some_handler
"$fn" arg
${fn} arg
PROBE
OUT=$(run_write "$TMP/e.sh")
assert_empty "$OUT" "T5: динамическое имя"

# --- T6: функция, определённая В ЭТОМ ЖЕ файле — тишина ---
cat > "$TMP/f.sh" <<'PROBE'
#!/usr/bin/env bash
my_local_helper() { echo hi; }
my_local_helper
PROBE
OUT=$(run_write "$TMP/f.sh")
assert_empty "$OUT" "T6: функция из этого же файла"

# --- T7: не shell-файл не рассматривается ---
cp "$TMP/a.sh" "$TMP/g.py"
OUT=$(run_write "$TMP/g.py")
assert_empty "$OUT" "T7: не-shell файл"

# --- T8: путь ОБОЛОЧКИ — предмет есть изменённый файл, а не имя инструмента (D311) ---
STATE="$TMP/state"; mkdir -p "$STATE"
STAMP="$STATE/undefined-function-scan-t.stamp"   # метка своя у сессии «t» (D497)
: > "$STAMP"
sleep 1
# Пробник живёт во ВРЕМЕННОМ репозитории, а не в корне рабочего дерева (D360, 13 сентября
# 2026): страж берёт корень сканирования из CLAUDSOUL_REPO, а уборка через `trap EXIT` не
# переживает `kill -9` раннера — файл `.probe-undef.sh` дважды всплывал в `git status`
# чужого коммита (8 сентября 2026). Временный корень убирает система, что бы ни случилось с тестом.
# Требования стража к корню — из его пути решения (undefined-function-check.sh:66-70,180-200):
# каталог с hooks/, библиотека hooks/lib/universe-lib.sh внутри него и вселенная определений из
# ИНДЕКСА GIT этого корня — без git она пуста, и страж честно слепнет и молчит. Потому временный
# корень — репозиторий с закоммиченной библиотекой и одним .sh; пробник — неотслеживаемый файл
# новее отметки. `git -C "$TMP/…"` литералом: так раннер оставляет тест в параллельной фазе.
PROBE_REPO="$TMP/probe-repo"; mkdir -p "$PROBE_REPO/hooks/lib"
cp "$ROOT/hooks/lib/universe-lib.sh" "$PROBE_REPO/hooks/lib/"
printf '#!/usr/bin/env bash\nprobe_defined_helper() { :; }\n' > "$PROBE_REPO/hooks/base.sh"
git -C "$TMP/probe-repo" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh:$LINENO" >&2; exit 1; }
git -C "$TMP/probe-repo" add -A 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh:$LINENO" >&2; exit 1; }
git -C "$TMP/probe-repo" -c user.email=t@t -c user.name=t commit -qm probe 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh:$LINENO" >&2; exit 1; }
cat > "$PROBE_REPO/.probe-undef.sh" <<'PROBE'
#!/usr/bin/env bash
_totally_absent_helper "$1"
PROBE
OUT=$(printf '{"session_id":"t","tool_name":"Bash","tool_input":{"command":"cat > x <<EOF"}}' \
      | CLAUDSOUL_REPO="$PROBE_REPO" CLAUDSOUL_STATE_DIR="$STATE" bash "$HOOK" 2>/dev/null)
assert_contains "$OUT" "_totally_absent_helper" "T8: запись оболочкой рассмотрена"

# --- T10: имя, ЕСТЬ в PATH — не тревога (внешняя утилита, а не забытая функция) ---
# Ноги на PATH сначала не было, и мутация «не вычитать PATH» проходила прибор насквозь.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho ok\n' > "$TMP/bin/probe_tool_x"
chmod +x "$TMP/bin/probe_tool_x"
cat > "$TMP/h.sh" <<'PROBE'
#!/usr/bin/env bash
probe_tool_x --flag
PROBE
OUT=$(printf '{"session_id":"t","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$TMP/h.sh" \
      | PATH="$TMP/bin:$PATH" CLAUDSOUL_REPO="$ROOT" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T10: утилита из PATH"

# --- T11: имя из ФИКСТУРЫ внутри heredoc не считается определением ---
# `my_local_helper` определён в этом файле только внутри тела heredoc (нога T6). Сырой
# сбор универсума видел его как настоящую функцию, и вызов несуществующего имени молчал,
# если такое же имя стояло в чьей-то фикстуре. Эталон обязан чиститься так же, как цель.
cat > "$TMP/i.sh" <<'PROBE'
#!/usr/bin/env bash
my_local_helper arg
PROBE
OUT=$(run_write "$TMP/i.sh")
assert_contains "$OUT" "my_local_helper" "T11: имя из фикстуры не считается определением"

# --- T12: УСТАРЕВШИЙ кеш не даёт ложной тревоги ---
# Пересборка эталона привязана к подозрению, а не к правке файла (цена: 2.4 с против
# 0.07 с). Значит кеш штатно бывает устаревшим, и единственное, что спасает от ложной
# тревоги, — ПЕРЕПРОВЕРКА находки после пересборки. Ноги на это не было, и мутация
# «не перепроверять» проходила прибор насквозь.
STATE2="$TMP/state2"; mkdir -p "$STATE2"
FP="#src $(cksum < "$HOOK" 2>/dev/null | tr -s ' ' | cut -d' ' -f1,2)"
# Кеш с ВЕРНЫМ отпечатком, но заведомо неполный: `sync_claude_md` в нём нет.
{ printf '%s\n' "$FP"; printf 'some_unrelated_name\n'; } > "$STATE2/undefined-function-defs.txt"
cat > "$TMP/j.sh" <<'PROBE'
#!/usr/bin/env bash
sync_claude_md "$TARGET" "$MASTER"
PROBE
OUT=$(printf '{"session_id":"t","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$TMP/j.sh" \
      | CLAUDSOUL_REPO="$ROOT" CLAUDSOUL_STATE_DIR="$STATE2" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T12: устаревший кеш"

# --- T9: живое дерево чисто (иначе тревога станет фоном) ---
DIRTY=""
for f in "$ROOT"/hooks/*.sh "$ROOT"/scripts/*.sh "$ROOT"/lib/*.sh; do
    [ -f "$f" ] || continue
    o=$(run_write "$f")
    [ -n "$o" ] && DIRTY="$DIRTY $(basename "$f")"
done
[ -z "$DIRTY" ] && ok || bad "T9" "на живом дереве тревога:$DIRTY"

# --- T10: ПУСТОЙ УНИВЕРСУМ — отказ, а не пустой справочник ---
# Дерево без .git (распакованный git archive, tarball) даёт `git ls-files` ноль строк.
# Справочник известных имён оказался бы пуст, и КАЖДЫЙ вызов в проверяемом файле стал бы
# «функцией, которой нет», — тревога на всём подряд. Мутация «пустой универсум не отказ»
# проходила прибор насквозь, пока этой ноги не было.
BARE="$TMP/bare"; mkdir -p "$BARE/hooks/lib" "$BARE/scripts"
cp "$ROOT/hooks/lib/universe-lib.sh" "$BARE/hooks/lib/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh:$LINENO" >&2; exit 1; }
# Функция определена НЕ здесь, а в дереве (hooks/portable-lib.sh). При полном справочнике
# она известна и тревоги нет; при пустом — стала бы «несуществующей». Проба с локальным
# определением этого не различает: страж берёт определения и из самого файла, поэтому
# первая редакция ноги была зелёной при обеих мутациях.
cat > "$BARE/scripts/probe.sh" <<'PROBE'
#!/usr/bin/env bash
. hooks/portable-lib.sh
to_lower "ТЕКСТ"
PROBE
ERR10="$TMP/bare.err"
OUT10=$(printf '{"session_id":"t","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$BARE/scripts/probe.sh" \
        | CLAUDSOUL_REPO="$BARE" STATE_DIR="$TMP/state-bare" bash "$HOOK" 2>"$ERR10")
[ -z "$OUT10" ] && ok || bad "T10" "на дереве без индекса git страж заговорил: $(printf '%s' "$OUT10" | head -c 90)"
# Тишина в stdout сама по себе ничего не доказывает: хук может молчать ПАДАЯ. Отказ обязан
# быть назван, а не случиться. Без этой ноги мутация «пустой универсум не отказ» проходила
# насквозь трижды — хук валился на `DEFS: unbound variable`, и stderr глушился.
if grep -q 'универсум определений пуст' "$ERR10" 2>/dev/null &&
   ! grep -qE 'unbound variable|command not found|syntax error' "$ERR10" 2>/dev/null; then
    ok
else
    bad "T10b" "отказ не назван либо хук упал: $(head -c 110 "$ERR10" 2>/dev/null)"
fi

# --- T13: ПУСТОЙ УНИВЕРСУМ ПРИ НЕПУСТОМ УСТАРЕВШЕМ КЕШЕ — отказ, а не ложная тревога ---
# Повод, 7 сентября 2026. Страж живёт в ДВУХ местах: в репозитории и в установленной копии
# ~/.claude/hooks. Во второй CLAUDSOUL_REPO не задан, корень выводится из расположения файла
# (:66-70) и указывает на ~/.claude, а это НЕ git-репозиторий: универсум оттуда — 0 файлов
# против 519 из проекта. Тогда обещание самоисцеления кеша («имя, которого в кеше нет →
# пересобираем и перепроверяем») не исполняется: пересборка даёт пустой список, `mv` не
# выполняется, DEFS перечитывается из СТАРОГО снимка — и новая функция объявляется
# несуществующей. Живой случай: rc_outcome_observed, определённая в root-cause-lib.sh:343.
# T10 этого не ловит: там состояние чистое, DEFS выходит пустым и ветка отказа срабатывает.
# Здесь кеш непустой, ветка отказа молчит по построению.
BARE13="$TMP/bare13"; mkdir -p "$BARE13/hooks/lib" "$BARE13/scripts"
cp "$ROOT/hooks/lib/universe-lib.sh" "$BARE13/hooks/lib/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh:$LINENO" >&2; exit 1; }
cat > "$BARE13/scripts/probe.sh" <<'PROBE13'
#!/usr/bin/env bash
. hooks/portable-lib.sh
to_lower "ТЕКСТ"
PROBE13
STATE13="$TMP/state13"; mkdir -p "$STATE13"
# кеш С ВЕРНЫМ отпечатком сборщика (иначе он пересобрался бы по другой ветке) и БЕЗ to_lower
{ printf '#src %s\n' "$(cksum < "$HOOK" | tr -s ' ' | cut -d' ' -f1,2)"
  printf 'some_other_fn\nanother_fn\n'; } > "$STATE13/undefined-function-defs.txt"
ERR13="$TMP/bare13.err"
OUT13=$(printf '{"session_id":"t","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$BARE13/scripts/probe.sh" \
        | CLAUDSOUL_REPO="$BARE13" CLAUDSOUL_STATE_DIR="$STATE13" STATE_DIR="$STATE13" bash "$HOOK" 2>"$ERR13")
if [ -z "$OUT13" ]; then ok
else bad "T13" "универсум пуст, кеш устарел — страж объявил живую функцию несуществующей: $(printf '%s' "$OUT13" | head -c 110)"; fi
# и отказ обязан быть НАЗВАН, а не случиться тишиной
if grep -q 'универсум определений пуст' "$ERR13" 2>/dev/null &&
   ! grep -qE 'unbound variable|command not found|syntax error' "$ERR13" 2>/dev/null; then ok
else bad "T13b" "отказ проверки не назван в stderr: $(head -c 110 "$ERR13" 2>/dev/null)"; fi

# --- T14: ЗАПУСК ФАЙЛА, КОТОРОГО НЕТ (11 сентября 2026) -----------------------
# Вторая половина предмета: имя взято из ОБРАЗЦА, а не из источника. Прежде страж судил
# только функции в записанных файлах, и класс «зову скрипт, которого нет» проходил мимо:
# за одну сессию агента 12 выдуманных имён, в поле зрения хука попало 0. Замер по корпусу:
# 6088 вызовов `bash <файл>`, у 36 файла не существовало, 4 из них законны (файл создаётся
# тем же вызовом) — с клаузой точность 32 из 32.
_ufc_say() {   # $1 — команда, $2 — cwd; печатает 1, если страж сказал
    python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "$2" \
        | bash "$HOOK" 2>/dev/null | grep -c 'которого нет'
}
_R=$(cd "$(dirname "$0")/../.." && pwd)

[ "$(_ufc_say 'bash hooks/tests/run-all.sh' "$_R")" -gt 0 ] && ok \
    || bad "T14a" "выдуманный путь (run-all.sh против живого run_all.sh) не назван"

[ "$(_ufc_say 'bash hooks/tests/run_all.sh' "$_R")" -eq 0 ] && ok \
    || bad "T14b" "живой скрипт объявлен несуществующим"

[ "$(_ufc_say 'cat > /tmp/ufc_probe.sh <<EOF
echo x
EOF
bash /tmp/ufc_probe.sh' "$_R")" -eq 0 ] && ok \
    || bad "T14c" "контрпример сломан: файл создаётся тем же вызовом, отказ обязан молчать"

[ "$(_ufc_say 'bash "$SOME_VAR"' "$_R")" -eq 0 ] && ok \
    || bad "T14d" "путь из переменной статически непроверяем, а страж о нём заговорил"


# --- T15: КАТАЛОГ ВЫЗОВА не установлен — это МОЛЧАНИЕ, а не вердикт (D422) ------------
# Повод: два ложных предупреждения подряд на ЖИВЫХ файлах 16 сентября 2026. Форм неудачи
# раскрытия три, и третью нашёл только прогон — заплаты «третьего состояния» одной мало.
_LIVE="hooks/tests/test_error_tracker.sh"

# T15a: цель перехода — подстановка, значение до исполнения неизвестно.
[ "$(_ufc_say "cd \"\$(cat ~/.claude/claudsoul-repo)\" && bash $_LIVE" "$_R")" -eq 0 ] && ok \
    || bad "T15a" "нераскрытая подстановка в цели перехода дала утверждение об отсутствии"

# T15b: ХВОСТОВОЙ ПРОБЕЛ. Выражение извлечения жадно берёт всё до `&`, и `cd hooks && …`
# даёт «hooks » с пробелом — на нём `-d` отвечает ложью о живом каталоге.
[ "$(_ufc_say "cd hooks && bash tests/test_error_tracker.sh" "$_R")" -eq 0 ] && ok \
    || bad "T15b" "хвостовой пробел в цели перехода дал ложное утверждение"

# T15c: РАМКА. Цель относительная и раскрывается уверенно — но проверялась относительно
# каталога ПРОЦЕССА ХУКА, а не относительно cwd полезной нагрузки.
_OUT=$(cd / && python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
        "cd hooks && bash tests/test_error_tracker.sh" "$_R" | bash "$HOOK" 2>/dev/null | grep -c 'которого нет')
[ "$_OUT" -eq 0 ] && ok || bad "T15c" "относительная цель разрешена от каталога процесса хука, а не от cwd вызова"

# T15d: ОТЗЫВ. Перехода нет — предмет определён, выдуманный путь обязан быть назван.
[ "$(_ufc_say "bash hooks/tests/net_takogo_testa.sh" "$_R")" -gt 0 ] && ok \
    || bad "T15d" "сужение съело отзыв: выдуманный путь без перехода не назван"

# T15e: ОТЗЫВ при неизвестном каталоге. АБСОЛЮТНЫЙ путь от каталога не зависит — молчать
# на нём значило бы отдать отзыв там, где предмет определён.
[ "$(_ufc_say "cd \"\$(cat ~/.claude/claudsoul-repo)\" && bash /net/net/net.sh" "$_R")" -gt 0 ] && ok \
    || bad "T15e" "абсолютный выдуманный путь замолчал вместе с относительным"

# T15f/T15g: РАЗЛИЧАЮЩАЯ СПОСОБНОСТЬ — МУТАНТАМИ, А НЕ ПРЕЖНЕЙ РЕДАКЦИЕЙ.
#
# Первая редакция звала `git show HEAD:hooks/undefined-function-check.sh` как «прежнюю
# редакцию» и была зелена ровно до коммита починки: после него HEAD стал содержать саму
# починку, «прежняя» сравнялась с нынешней, нога покраснела в тот же час (коммит 0bc5877),
# и вместе с ней покраснела «Проверка» пункта D422. Корень — опорная точка задана
# ПОДВИЖНОЙ меткой, а не закреплена (`pattern-unowned-check-state-drifts`). Братья
# проверены и пусты: пять других тестов зовут `git show HEAD:`, но у них предмет иной —
# «расходится ли рабочее дерево с закоммиченным», там движение HEAD и есть смысл.
#
# ВТОРАЯ редакция мутантов тоже была красна, и это нашло НАСТОЯЩИЙ дефект проверок:
# половины починки отвечают за РАЗНОЕ, а обе ноги требовали от них одного. Снятие
# хвостового пробела отвечает за ОТЗЫВ (без него третье состояние всё равно гасит тревогу),
# а третье состояние — за ТОЧНОСТЬ. Заодно выяснилось, что путь пробы разрешался от корня
# репозитория, и нога T15a проходила ДАРОМ. Случаи ниже подобраны так, что каждый различает
# свою половину, и это измерено на четырёх прогонах: 0/1 и 1/0.
_ufc_mutant() {   # _ufc_mutant <sed-выражение> <команда> → сколько раз страж сказал
    local _sed="$1" _cmd="$2" _t _n
    _t=$(mktemp -d 2>/dev/null) || { echo "-1"; return; }
    mkdir -p "$_t/hooks"
    # Песочница строится там, где судимый механизм её ПРИНИМАЕТ (род M): хук берёт
    # библиотеку рядом с собой и выходит, если рядом нет каталога `hooks` (`:70`, `:76-79`).
    sed "$_sed" "$HOOK" > "$_t/hooks/undefined-function-check.sh"
    cp "$_R/hooks/command-scope-lib.sh" "$_t/hooks/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh:$LINENO" >&2; exit 1; }
    # Разбор вызовов — тоже носитель судимого механизма (D424): без него библиотека
    # уходит в УСТАНОВЛЕННУЮ копию, та бывает старше, и мутант молчит не оттого, что
    # проверяемое место работает (род M — песочница строится там, где механизм её принимает).
    mkdir -p "$_t/hooks/lib"
    cp "$_R/hooks/lib/write_targets.py" "$_t/hooks/lib/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh:$LINENO" >&2; exit 1; }
    _n=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
        "$_cmd" "$_R" \
      | CLAUDSOUL_REPO="$_R" bash "$_t/hooks/undefined-function-check.sh" 2>/dev/null | grep -c 'которого нет')
    rm -rf "$_t"
    printf '%s' "$_n"
}

# Случай S: цель перехода — подстановка, а файл живёт ПОД этой целью. Настоящий хук молчит
# (каталог не установлен); мутант «каталог всегда известен» судит от cwd вызова и врёт.
_CS='cd "$(printf %s hooks)" && bash tests/test_error_tracker.sh'
[ "$(_ufc_say "$_CS" "$_R")" -eq 0 ] && ok || bad "T15h" "нераскрытая подстановка дала утверждение об отсутствии"
_M=$(_ufc_mutant 's|^        _ufc_cwd_known=0$|        _ufc_cwd_known=1|' "$_CS")
[ "$_M" -gt 0 ] && ok || bad "T15g" "с заклиненным третьим состоянием страж молчит (получено '$_M') — ТОЧНОСТЬ ничем не доказана"

# Случай T: хвостовой пробел, а файла НЕТ. Здесь предмет — ОТЗЫВ: настоящий хук обязан
# назвать путь, мутант без снятия пробела теряет каталог и замолкает.
_CT='cd hooks && bash tests/net_takogo_testa.sh'
[ "$(_ufc_say "$_CT" "$_R")" -gt 0 ] && ok || bad "T15i" "хвостовой пробел съел ОТЗЫВ: выдуманный путь не назван"
_M=$(_ufc_mutant 's|^    _ufc_lead=\${_ufc_lead%.*$|    :|' "$_CT")
[ "$_M" -eq 0 ] && ok || bad "T15f" "без снятия хвостового пробела страж всё равно называет путь (получено '$_M') — ОТЗЫВ ничем не доказан"

# --- T16: ОБЛАСТЬ ПОИСКА ВЫЗОВА объявлена разбором, а не равна всему тексту (D424) ------
# Повод: страж объявлял вызовом путь внутри кавыченного аргумента. Поймано на СЕБЕ четырежды
# за два дня — предупреждение выходило на командах проверки D422 и на комментарии внутри
# самой этой починки. Корень R3, тот же, что у закрытого D420: роль фрагмента решалась
# наличием формы в тексте, а область поиска не была объявлена и потому равнялась всему.
#
# ПОЧЕМУ НЕ `executable_part`, хотя он звался бы одной строкой: он ВЫРЕЗАЕТ кавычки вместе
# с целью (`bash "x.sh"` → `bash  `). Замер по корпусу 35 633 вызовов: таких путей 195.
# Предел, названный пунктом заранее (тела heredoc оболочки), замером оказался ПУСТ — 0
# случаев; настоящим был другой. Обе ноги ниже, T16b и T16c, держат именно то, что
# `executable_part` потерял бы.

# T16a: ТОЧНОСТЬ. Путь внутри кавыченного аргумента — не вызов.
[ "$(_ufc_say 'jq -nc --arg c "cd x && bash tests/vydumannyi.sh" "{}"' "$_R")" -eq 0 ] && ok \
    || bad "T16a" "путь в кавыченном аргументе объявлен вызовом"

# T16b: ОТЗЫВ. Путь цели В КАВЫЧКАХ — настоящий вызов, и вырезание его потеряло бы.
[ "$(_ufc_say 'bash "hooks/tests/net_takogo_testa.sh"' "$_R")" -gt 0 ] && ok \
    || bad "T16b" "путь цели в кавычках потерян — сужение съело отзыв"

# T16c: ОТЗЫВ. Тело heredoc, открытого САМОЙ оболочкой, она же и исполняет.
[ "$(_ufc_say 'bash <<EOF
bash hooks/tests/net_takogo_testa.sh
EOF' "$_R")" -gt 0 ] && ok || bad "T16c" "вызов в теле heredoc оболочки не назван"

# T16d: ОТЗЫВ. Границу команды даёт и перевод строки, не только `;` и `&&`.
[ "$(_ufc_say 'cd hooks
bash tests/net_takogo_testa.sh' "$_R")" -gt 0 ] && ok || bad "T16d" "вызов со следующей строки не назван"

# T16e: ТОЧНОСТЬ. `bash -c <код>` файла не запускает — иначе кодом станет «путь».
[ "$(_ufc_say 'bash -c "cd /tmp && grep -n x nesushchestvuyushchiy.sh"' "$_R")" -eq 0 ] && ok \
    || bad "T16e" "код после -c объявлен запускаемым файлом"

# T16f: ТОЧНОСТЬ. Тело ЧУЖОГО heredoc исполняет не оболочка.
[ "$(_ufc_say "python3 - <<'PY'
p='bash hooks/tests/net_takogo_testa.sh'
PY" "$_R")" -eq 0 ] && ok || bad "T16f" "строка питона в теле heredoc объявлена вызовом"

# T16g/T16h: РАЗЛИЧАЮЩАЯ СПОСОБНОСТЬ — двумя мутантами, и каждый за СВОЮ половину.
# Половины отвечают за разное, и требовать от обеих одного значит не проверить ни одну
# (урок 16 сентября 2026, ноги T15f/T15g): сужение области держит ТОЧНОСТЬ, построчность
# разбора — ОТЗЫВ. Мутируется питон, а не оболочка, поэтому песочнице нужен и он: хук
# берёт библиотеку рядом с собой, а библиотека — разбор в своём `lib/` (род M).
_ufc_mutant_py() {   # _ufc_mutant_py <sed-выражение по write_targets.py> <команда>
    local _sed="$1" _cmd="$2" _t _n
    _t=$(mktemp -d 2>/dev/null) || { echo "-1"; return; }
    mkdir -p "$_t/hooks/lib"
    cp "$HOOK" "$_t/hooks/undefined-function-check.sh"
    cp "$_R/hooks/command-scope-lib.sh" "$_t/hooks/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh:$LINENO" >&2; exit 1; }
    sed "$_sed" "$_R/hooks/lib/write_targets.py" > "$_t/hooks/lib/write_targets.py"
    _n=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
        "$_cmd" "$_R" \
      | CLAUDSOUL_REPO="$_R" bash "$_t/hooks/undefined-function-check.sh" 2>/dev/null | grep -c 'которого нет')
    rm -rf "$_t"
    printf '%s' "$_n"
}

# T16g — ТОЧНОСТЬ: снимаем кавычки ДО токенизации, то есть возвращаем прежнюю несуженную
# область, — ложный случай обязан заговорить.
# ПЕРВАЯ редакция этого мутанта проверяла ОБРАТНОЕ задуманному (тот же промах, что 16
# сентября у T15f): она рвала токен по пробелам, путь выходил с висящей кавычкой
# `tests/vydumannyi.sh"`, отсекался фильтром `*.sh` — и мутант молчал по ПОСТОРОННЕЙ причине.
_M=$(_ufc_mutant_py 's|shlex.shlex(buf, posix=True|shlex.shlex(buf.replace(chr(34)," ").replace(chr(39)," "), posix=True|' \
     'jq -nc --arg c "cd x && bash tests/vydumannyi.sh" "{}"')
[ "$_M" -gt 0 ] && ok || bad "T16g" "со снятым разбором страж молчит (получено '$_M') — ТОЧНОСТЬ ничем не доказана"

# T16h — ОТЗЫВ: склеиваем строки в одну — граница команды по переводу строки исчезает.
_M=$(_ufc_mutant_py 's|for line in shell_text(cmd).split("\\n"):|for line in [shell_text(cmd).replace(chr(10), " ")]:|' \
     'cd hooks
bash tests/net_takogo_testa.sh')
[ "$_M" -eq 0 ] && ok || bad "T16h" "без построчного разбора страж всё равно называет путь (получено '$_M') — ОТЗЫВ ничем не доказан"

# T17: ВТОРОЙ ПЕРЕХОД (D1028, 22 октября 2026). Каталог брался из ведущего `cd`, и живой файл после второго перехода
# объявлялся несуществующим. Каталог относительных путей неизвестен — молчание; абсолютный путь судится как прежде.
[ "$(_ufc_say "cd /tmp && true; cd \"$_R\" && bash hooks/tests/run_all.sh" "$_R")" -eq 0 ] && ok \
    || bad "T17" "живой файл после второго cd объявлен несуществующим"
[ "$(_ufc_say "cd /tmp && true; cd \"$_R\" && bash /net/net/net.sh" "$_R")" -gt 0 ] && ok \
    || bad "T17b" "абсолютный путь к несуществующему файлу после второго cd не назван"
# T17c — переход ПОСЛЕ вызова каталог вызова не меняет: отсутствующий файл называется (первая редакция D1028 считала
# переходы во всей команде и молчала здесь — скептик, 425 из 11 580 вызовов).
[ "$(_ufc_say "cd hooks && bash tests/net_takogo_testa.sh && cd -" "$_R")" -gt 0 ] && ok \
    || bad "T17c" "переход после вызова заглушил настоящий отсутствующий файл"
# T17d — путь сперва упомянут в кавычках, потом вызван после второго перехода: префикс берётся до ПОСЛЕДНЕГО вхождения.
# Файл живёт ТОЛЬКО относительно перехода (hooks/tests/…), а не каталога сессии: иначе нога зеленеет при любом префиксе.
# Упоминание — через `:`, не `echo`: `echo … <путь>` страж читает как «файл создаётся этим вызовом» и пропускает путь
# до подсчёта переходов — нога зеленела бы и на префиксе до первого вхождения.
[ "$(_ufc_say ": \"x tests/test_error_tracker.sh\" && cd hooks && bash tests/test_error_tracker.sh" "$_R")" -eq 0 ] && ok \
    || bad "T17d" "упоминание пути в кавычках спрятало второй переход"

# --- T18: функция, объявленная только в ЧУЖОМ тесте, вызова не обеспечивает (D1038) ---
# Тест другой тест не подключает: `assert_eq` из десятков тестов засчитывала вызов в test_startup_signals.sh, где её не
# было, и четыре проверки падали мимо счётчика. Определение в библиотеке хуков (`hooks/x.sh`) и своё — по-прежнему в счёт.
R18="$TMP/probe18"; mkdir -p "$R18/hooks/lib" "$R18/hooks/tests"
cp "$ROOT/hooks/lib/universe-lib.sh" "$R18/hooks/lib/"
printf '#!/usr/bin/env bash\nshared_helper() { :; }\n' > "$R18/hooks/tests/test_a.sh"
printf '#!/usr/bin/env bash\nlib_helper() { :; }\n' > "$R18/hooks/base.sh"
git -C "$TMP/probe18" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh T18" >&2; exit 1; }
git -C "$TMP/probe18" add -A 2>/dev/null && git -C "$TMP/probe18" -c user.email=t@t -c user.name=t commit -qm p 2>/dev/null \
    || { echo "подготовка мира не удалась: hooks/tests/test_undefined_function_guard.sh T18" >&2; exit 1; }
printf '%s\n' '#!/usr/bin/env bash' 'own_helper() { :; }' 'shared_helper "x"' 'lib_helper "x"' 'own_helper "x"' > "$R18/hooks/tests/test_b.sh"
OUT18=$(printf '{"session_id":"t18","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$R18/hooks/tests/test_b.sh" \
        | CLAUDSOUL_REPO="$R18" CLAUDSOUL_STATE_DIR="$TMP/state18" bash "$HOOK" 2>/dev/null)
assert_contains "$OUT18" "shared_helper" "T18: функция только из чужого теста названа"
case "$OUT18" in *lib_helper*) bad "T18b" "функция библиотеки хуков объявлена несуществующей" ;; *) ok ;; esac
case "$OUT18" in *own_helper*) bad "T18c" "своя функция теста объявлена несуществующей" ;; *) ok ;; esac

echo "undefined function guard: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
