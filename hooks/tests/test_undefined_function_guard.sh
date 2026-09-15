#!/usr/bin/env bash
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
STAMP="$STATE/undefined-function-scan.stamp"
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
git -C "$TMP/probe-repo" init -q 2>/dev/null
git -C "$TMP/probe-repo" add -A 2>/dev/null
git -C "$TMP/probe-repo" -c user.email=t@t -c user.name=t commit -qm probe 2>/dev/null
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
cp "$ROOT/hooks/lib/universe-lib.sh" "$BARE/hooks/lib/" 2>/dev/null
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
cp "$ROOT/hooks/lib/universe-lib.sh" "$BARE13/hooks/lib/" 2>/dev/null
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

echo "undefined function guard: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
