#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh hooks/lib/write-target-lib.sh
# test_write_target_scope.sh — отказ гейта разбора смотрит на ЦЕЛЬ записи, а не на факт записи.
#
# Повод (5 сентября 2026). Признак записи в `five-whys-gate` отвечал на вопрос «пишет ли», а
# отказ утверждает «правка не пройдёт» — то есть о левом, а сказано о правом. Замер по
# 74 отказам гейта в корпусе расшифровок:
#   · записи в ДЕРЕВО проекта — 24, цепочка произнесена в 24 из 24: там гейт безупречен;
#   · записи в ПЕСОЧНИЦУ — 32, и все 6 «обходов» замера `stopper-effect` приходятся сюда.
# Отказ на временном зонде не защищает ничего и мешает: субагент писал `probe.py`, чтобы
# НАЙТИ причину, и получал «сначала назови причину».
#
# ОСВОБОЖДЕНИЕ ТОЛЬКО ТАМ, ГДЕ ЦЕЛЬ ОБЪЯВЛЕНА ПОЛЕМ (Edit/Write/MultiEdit). Разбор целей из
# текста Bash-команды был написан и снят: противник дал 5 подтверждённых дыр из 6 —
# достаточно распознаваемой приманки в /tmp рядом с нераспознанной записью в дерево, и
# предикат «все НАЙДЕННЫЕ цели вне проекта» освобождал вызов. Поэтому у Bash отказ остаётся
# всегда, и ноги ниже это ЗАКРЕПЛЯЮТ: ослабление здесь тихо снимет страж уровня 4.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/five-whys-gate.sh"
LIB="$REPO/hooks/lib/write-target-lib.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
[ -f "$LIB" ]  || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
# shellcheck source=/dev/null
. "$LIB"
# Платформа (D1233): ноги про `/private` (на macOS `/tmp` и `/var` — ссылки туда) и про регистр путей — свойства macOS;
# на Linux `/private` нет и файловая система чувствительна к регистру, страж там ведёт себя верно, а ноги краснели.
MAC=0; [ "$(_wt_real /tmp)" = /private/tmp ] && MAC=1

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STATE_DIR="$TMP/state"; mkdir -p "$STATE_DIR"
PROJ="$TMP/proj"; mkdir -p "$PROJ/hooks"
SCRATCH="/private/tmp/claude-501/-x/sess/scratchpad"; [ "$MAC" = 1 ] || SCRATCH="/tmp/claude-501/-x/sess/scratchpad"

# Ход с НАХОДКОЙ и без цепочки — на нём гейт обязан отказывать пишущему вызову.
TR="$TMP/find.jsonl"
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$TR"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Оказалось, страж поймал мой же тест. Чиню."}]}}' >> "$TR"

call() { # call <sid> <tool> <json полей tool_input>
    jq -cn --arg s "$1" --arg n "$2" --arg p "$TR" --arg w "$PROJ" --argjson ti "$3" \
      '{session_id:$s, transcript_path:$p, cwd:$w, hook_event_name:"PreToolUse", tool_name:$n, tool_input:$ti}' \
    | STATE_DIR="$STATE_DIR" bash "$HOOK" 2>/dev/null
}
dec() { jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$1" 2>/dev/null; }
sig() { touch "$STATE_DIR/error_streak_fired_$1"; }

# ── Освобождение: цель объявлена полем и лежит в песочнице ────────────────────
sig w1; OUT=$(call w1 Write "$(jq -cn --arg f "$SCRATCH/probe.py" '{file_path:$f, content:"x"}')")
[ -z "$(dec "$OUT")" ] && ok || bad "T1 Write в песочницу" "отказано, а цель вне проекта: $OUT"

sig w2; OUT=$(call w2 Edit "$(jq -cn --arg f "$SCRATCH/note.md" '{file_path:$f, old_string:"a", new_string:"b"}')")
[ -z "$(dec "$OUT")" ] && ok || bad "T2 Edit в песочницу" "отказано: $OUT"

# ── ЗАЩИТА: цель в дереве — отказ обязан остаться ─────────────────────────────
sig w3; OUT=$(call w3 Write "$(jq -cn --arg f "$PROJ/hooks/x.sh" '{file_path:$f, content:"x"}')")
[ "$(dec "$OUT")" = "deny" ] && ok || bad "T3 Write в дерево" "ОСВОБОЖДЕНО, а цель в проекте: $OUT"

sig w4; OUT=$(call w4 Edit "$(jq -cn --arg f "$PROJ/CLAUDE.md" '{file_path:$f, old_string:"a", new_string:"b"}')")
[ "$(dec "$OUT")" = "deny" ] && ok || bad "T4 Edit в дерево" "ОСВОБОЖДЕНО: $OUT"

# ── ЗАЩИТА: Bash не освобождается НИКОГДА, даже с целью в песочнице ───────────
# Это закрепление снятого разбора: 5 подтверждённых дыр из 6 при попытке освобождать Bash.
sig b1; OUT=$(call b1 Bash "$(jq -cn --arg c "cat > $SCRATCH/probe.py <<E
x
E" '{command:$c}')")
[ "$(dec "$OUT")" = "deny" ] && ok || bad "T5 Bash в песочницу" "ОСВОБОЖДЕНО — разбор Bash снят намеренно: $OUT"

sig b2; OUT=$(call b2 Bash "$(jq -cn --arg c "printf x > /tmp/decoy.txt; /usr/bin/tee -a \"$PROJ/hooks/y.sh\" </dev/null" '{command:$c}')")
[ "$(dec "$OUT")" = "deny" ] && ok || bad "T6 приманка в /tmp + запись в дерево" "ОСВОБОЖДЕНО — это ровно дыра противника: $OUT"

# ── Чтение обязано проходить: без него цепочку не построить ───────────────────
sig r1; OUT=$(call r1 Bash "$(jq -cn --arg c "grep -n foo $PROJ/hooks/x.sh" '{command:$c}')")
[ -z "$(dec "$OUT")" ] && ok || bad "T7 чтение" "заблокировано чтение: $OUT"

# ── Сам предикат пути ─────────────────────────────────────────────────────────
_wt_outside "$SCRATCH/a.md" "$PROJ"            && ok || bad "T8"  "путь песочницы не признан внешним"
_wt_outside "$PROJ/a.md" "$PROJ"               && bad "T9"  "путь проекта признан внешним" || ok
_wt_outside "" "$PROJ"                         && bad "T10" "пустой путь признан внешним" || ok
_wt_outside "hooks/a.sh" "$PROJ"               && bad "T11" "относительный путь признан внешним" || ok
# Восхождение отменяет доказательство: /tmp/../Users/… ведёт В ПРОЕКТ. Найдено этим тестом
# до подключения правила к стражу.
_wt_outside "/tmp/../$PROJ/a.md" "$PROJ"       && bad "T12" "путь с «..» признан внешним" || ok
# Проект внутри временного каталога (так живут проверочные копии) — внутреннее остаётся
# внутренним.
_wt_outside "/private/tmp/copy/x.md" "/private/tmp/copy" && bad "T13" "путь внутри проекта-во-временном признан внешним" || ok
# D1112: перечень корней один (`wt_temp_roots`) и знает оба написания каждого места macOS — `/var/folders` ($TMPDIR) и
# `/private/var/folders` (после `pwd -P`); до того страж знал только второе, а замер точности — только первое.
_wt_outside "/var/folders/ab/cd/T/x.md" "$PROJ"         && ok || bad "T14" "/var/folders (значение \$TMPDIR) не признан внешним"
[ "$MAC" = 1 ] && { _wt_outside "/private/var/folders/ab/cd/T/x.md" "$PROJ" && ok || bad "T15" "/private/var/folders не признан внешним"; }
_wt_outside "/dev/shm/x.md" "$PROJ"                     && ok || bad "T16" "/dev/shm не признан внешним"
# Корень из окружения хука страж НЕ берёт (скептик D1112, L1): `TMPDIR=$HOME` освободил бы установку.
( TMPDIR=/opt/tmpx/; _wt_outside "/opt/tmpx/a.md" "$PROJ" ) && bad "T17" "страж взял корень из \$TMPDIR" || ok
( TMPDIR=/; _wt_outside "/opt/x/a.md" "$PROJ" )         && bad "T18" "TMPDIR=/ сделал внешним произвольный путь" || ok
( TMPDIR="$HOME"; _wt_outside "$HOME/.claude/hooks/x.sh" "$PROJ" ) && bad "T18b" "TMPDIR=\$HOME освободил запись в установку" || ok
_wt_outside "/tmpfoo/a.md" "$PROJ"                      && bad "T19" "/tmpfoo принят за /tmp — граница звена потеряна" || ok
( TMPDIR=tmp; _wt_outside "tmp/a.md" "$PROJ" )          && bad "T20" "относительный TMPDIR сделал внешним относительный путь" || ok
# Проект во временном корне, цель и каталог проекта в РАЗНЫХ написаниях одного места — внутри (скептик D1112, H1):
# `cwd` события приходит после `pwd -P`, цель — как набрана; место обоих входов спрашивается у ФС (`_wt_real`).
for _pair in "/var/folders/ab/T/proj|/private/var/folders/ab/T/proj" "/private/var/folders/ab/T/proj|/var/folders/ab/T/proj" \
             "/var/tmp/proj|/private/var/tmp/proj" "/private/var/tmp/proj|/var/tmp/proj" "/tmp/proj|/private/tmp/proj" "/private/tmp/proj|/tmp/proj"; do
    [ "$MAC" = 1 ] || continue   # одно место под двумя именами — только на macOS
    _wt_outside "${_pair%%|*}/hooks/x.sh" "${_pair#*|}" && bad "T21" "цель ${_pair%%|*} в проекте ${_pair#*|} признана внешней" || ok
done
# `//` и `/./` — то же место: в проект не освобождают, во временный корень — освобождают.
_wt_outside "///$PROJ/hooks/x.sh" "$PROJ"               && bad "T22" "/// перед путём проекта освободил запись" || ok
_wt_outside "/.$PROJ/hooks/x.sh" "$PROJ"                && bad "T23" "/./ перед путём проекта освободил запись" || ok
_wt_outside "//tmp/./x.md" "$PROJ"                      && ok || bad "T24" "//tmp/./x.md не признан внешним"
[ "$(_wt_real "//tmp/./нет_такого/./x")" = "$(_wt_real /tmp)/нет_такого/x" ] \
    && ok || bad "T25" "_wt_real: «$(_wt_real "//tmp/./нет_такого/./x")» против «$(_wt_real /tmp)/нет_такого/x»"
# Скептики D1112, круги 2–3: тождество места задаёт ФС, а не строка (D1112, четвёртый круг) — проект в другом регистре
# (ASCII и кириллица), в другой форме нормализации, через символьную ссылку — внутри. Каталоги НАСТОЯЩИЕ: у
# несуществующего хвоста подменять собой нечего. Регистр и NFD судятся только там, где ФС к ним не чувствительна.
mkdir -p "$TMP/proj2/hooks" "$TMP/Проект/hooks"
[ -d "$TMP/PROJ2" ] && { _wt_outside "$TMP/PROJ2/hooks/x.sh" "$TMP/proj2" && bad "T26" "проект в другом регистре — цель внешняя" || ok; }
if [ -d "$TMP/PROJ2" ]; then
    _wt_outside "$TMP/ПРОЕКТ/hooks/x.sh" "$TMP/Проект" && bad "T26b" "проект в другом регистре кириллицы — цель внешняя" || ok
else
    echo "SKIP [T26b]: ФС чувствительна к регистру"
fi
_nfd=$(python3 -c "import unicodedata;print(unicodedata.normalize('NFD','Тайник'),end='')" 2>/dev/null)
_nfc=$(python3 -c "import unicodedata;print(unicodedata.normalize('NFC','Тайник'),end='')" 2>/dev/null)
if [ -n "$_nfd" ] && mkdir -p "$TMP/$_nfd/hooks" && [ -d "$TMP/$_nfc/hooks" ]; then
    _wt_outside "$TMP/$_nfc/hooks/x.sh" "$TMP/$_nfd" && bad "T26c" "проект в NFD, цель в NFC — цель внешняя" || ok
else
    echo "SKIP [T26c]: ФС различает формы нормализации (или нет python3)"
fi
ln -s /usr "$TMP/lnk_usr" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_write_target_scope.sh:$LINENO" >&2; exit 1; }
_wt_outside "$TMP/lnk_usr/x.sh" "$PROJ" && bad "T26d" "ссылка из временного каталога вне его признана внешней" || ok
( IFS=:; _wt_outside "$TMP/other/x.md" "$PROJ" ) && ok || bad "T26e" "при IFS=: вызывающего временный путь не признан внешним"
_wt_outside "$PROJ/hooks/x.sh" "$PROJ/." && bad "T27" "cwd с хвостом /. — цель в проекте внешняя" || ok
# Границы сравнения мест (мутанты четвёртого круга): сам каталог проекта — внутри; соседний каталог с тем же
# префиксом имени — вне проекта; корень-префикс (`/private/tmpfoo`) — не корень; `..` после несуществующего звена ФС
# не разрешит — держит проверка по сырому пути.
_wt_outside "$TMP/proj2" "$TMP/proj2"            && bad "T29" "сам каталог проекта признан внешним" || ok
_wt_outside "$TMP/proj2x/x.md" "$TMP/proj2"      && ok || bad "T30" "соседний каталог proj2x принят за проект proj2"
_wt_outside "$(_wt_real /tmp)foo/a.md" "$PROJ"   && bad "T31" "корень-префикс принят за временный корень" || ok
_wt_outside "$TMP/нет_звена/../../../$PROJ/x" "$PROJ" && bad "T32" "«..» после несуществующего звена освобождено" || ok
# Относительный путь — не место, и ответ обязан прийти сразу: подъём к предку на пути без `/` крутился вечно.
( _wt_real "a/b" >/dev/null; _r1=$?; _wt_outside "/tmp/x.md" "proj"; echo "$_r1$?" > "$TMP/t33" ) & _p=$!
for _i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/t33" ] && break; sleep 0.5; done
kill "$_p" 2>/dev/null
[ "$(cat "$TMP/t33" 2>/dev/null)" = "11" ] && ok || bad "T33" "относительный путь: висит или принят за место ($(cat "$TMP/t33" 2>/dev/null))"
# Пятый круг (скептик четвёртого, H1, M1, L1, L5). Ссылка в хвосте — на файл или висячая — не место: запись идёт туда,
# куда она ведёт; ссылка на каталог разрешается ФС (T26d). Проект `ссылка/..` — физический родитель, не текстовый.
# Хвост длиннее 32 звеньев — не место. Без `/bin/pwd` — не место (встроенный `pwd` отдаёт набранный регистр).
echo x > "$PROJ/hooks/f.sh"; ln -s "$PROJ/hooks/f.sh" "$TMP/flink5"; ln -s "$PROJ/hooks/nope.sh" "$TMP/dangle5"
ln -s "$PROJ/hooks" "$TMP/lp5"
_wt_outside "$TMP/other.md" "$TMP/lp5/.."   && ok || bad "T34" "проект lp5/.. (физически $PROJ) — временный путь вне его не внешний"
_wt_outside "$TMP/flink5" "$PROJ"            && bad "T35" "ссылка на файл проекта из временного каталога признана внешней" || ok
_wt_outside "$TMP/dangle5" "$PROJ"           && bad "T35b" "висячая ссылка в проект из временного каталога признана внешней" || ok
# Шестой круг (скептик пятого, M1, L1–L3): висячая ссылка в СЕРЕДИНЕ хвоста; границы 32/33 шага и 1024/1025 символа.
ln -s "$PROJ/hooks/newdir" "$TMP/dmid6"
_wt_outside "$TMP/dmid6/x.sh" "$PROJ"        && bad "T35c" "висячая ссылка в середине хвоста признана внешней" || ok
_p="$TMP"; for _i in $(seq 31); do _p="$_p/a"; done
_wt_outside "$_p/x" "$PROJ"                  && ok || bad "T36" "32 несуществующих звена — временный путь не внешний"
_wt_outside "$_p/a/x" "$PROJ"                && bad "T36c" "33 шага подъёма признаны внешним путём" || ok
for _i in $(seq 1000); do _p="$_p/a"; done
_wt_outside "$_p/x" "$PROJ"                  && bad "T36b" "хвост длиннее 32 звеньев признан внешним" || ok
_p="$TMP"; while [ $((${#_p} + 201)) -lt 1023 ]; do _p="$_p/$(printf 'b%.0s' $(seq 200))"; done
_p="$_p/$(printf 'c%.0s' $(seq $((1024 - ${#_p} - 1))))"
_wt_outside "$_p" "$PROJ"                    && ok || bad "T36d" "путь в ${#_p} символов (ждём 1024) не внешний"
_wt_outside "${_p}c" "$PROJ"                 && bad "T36e" "путь в 1025 символов признан внешним" || ok
# Положительный контроль рамки (L3): профиль без запрета обязан дать «внешний», иначе сбой sandbox-exec (битый профиль
# rc=65, запрет самого bash rc=71) засчитался бы «верно». Под запретом ответ обязан ПРИЙТИ строкой — и быть «не место».
_sb() { sandbox-exec -p "$1" bash -c '. "$1"; _wt_outside "$2/other.md" "$3"; echo "rc=$?"' _ "$LIB" "$TMP" "$PROJ" 2>/dev/null; }
if command -v sandbox-exec >/dev/null 2>&1 && [ "$(_sb '(version 1)(allow default)')" = "rc=0" ]; then
    _o=$(_sb '(version 1)(allow default)(deny process-exec (literal "/bin/pwd"))')
    [ "$_o" = "rc=1" ] && ok || bad "T37" "без /bin/pwd ждём rc=1, получено «${_o}» (rc=0 — временный путь внешний; пусто — запрет не исполнился)"
else
    echo "SKIP [T37]: нет sandbox-exec либо профиль без запрета не дал «внешний» (положительный контроль)"
fi
[ "$MAC" = 1 ] && { _wt_outside "/tmp/x.md" "/private/tmp" && bad "T28" "проект /private/tmp — /tmp/x.md внешний" || ok; }

echo ""
echo "write target scope: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
