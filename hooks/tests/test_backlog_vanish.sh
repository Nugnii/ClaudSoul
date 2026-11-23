#!/usr/bin/env bash
# test_backlog_vanish.sh — характеризующий тест стража исчезающих пунктов долга.
# Повод: дважды за час 2026-08-26 правка одного пункта заменой ДИАПАЗОНА уносила
# соседние (D83/D85/D86, затем снова D83/D86). Тест держит три случая: пропажа
# ловится, закрытие с переездом в архив законно, обычный коммит молчит.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/backlog-vanish-check.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }

PASS=0; FAIL=0
assert_contains() {
    if grep -q -- "$2" <<< "$1"; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: не найдено '$2' в: $1"; fi
}
assert_empty() {
    if [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина, получено: $1"; fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q . 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_vanish.sh:$LINENO" >&2; exit 1; }
git config user.email t@t || { echo "подготовка мира не удалась: hooks/tests/test_backlog_vanish.sh:$LINENO" >&2; exit 1; }
git config user.name t || { echo "подготовка мира не удалась: hooks/tests/test_backlog_vanish.sh:$LINENO" >&2; exit 1; }
{
  printf -- '- ☐ **D10** первый\n'
  printf -- '- ☐ **D11** второй\n'
  printf -- '- ☐ **D12** третий\n'
} > BACKLOG.md
printf 'архив\n' > BACKLOG-archive.md
git add -A && git commit -qm base

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ФУНДАМЕНТА (7 сентября 2026). Предполагалось: базовый коммит
# состоялся и несёт три пункта. Не проверялось ничем, а на нём стоят восемь ног, чей
# вердикт — ТИШИНА: без `HEAD:BACKLOG.md` страж выходит на `[ -n "$BEFORE" ] || exit 0` и
# молчит по причине, к предмету ноги отношения не имеющей. Замер того же дня: с сорванным
# базовым коммитом (`git commit` заменён на `true`) 11 ног из 21 остались ЗЕЛЁНЫМИ — все
# «тишины» среди них; красным файл делали только громкие ноги, то есть исход зависел от
# соседей, а не от контроля. Теперь состояние фундамента предъявляется числом, и при
# расхождении ноги ниже не выполняются вовсе — зелёного на песке не бывает.
BASE_ITEMS=$(git show HEAD:BACKLOG.md 2>/dev/null | grep -cF -- '- ☐ **D1')
[ "${BASE_ITEMS:-0}" -eq 3 ] || {
    echo "FAIL [фундамент]: в базовом коммите пунктов ${BASE_ITEMS:-0} из 3 — ногам «тишины» не на чем стоять"
    exit 1
}

run() { printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | bash "$HOOK" 2>/dev/null; }

# 1. Пункт исчез бесследно — страж называет его.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
OUT=$(run)
assert_contains "$OUT" "D11" "исчезнувший пункт назван поимённо"
assert_contains "$OUT" "не найдены в архиве" "объяснено, что это не закрытие"

# 2. Пункт закрыт и уехал в архив — законно, тишина.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf -- 'архив\n- ☑ **D11** второй\n' > BACKLOG-archive.md
OUT=$(run)
assert_empty "$OUT" "переезд в архив нарушением не считается"

# 3. Пункт остался, но помечен закрытым в самом файле — тишина.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☑ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf 'архив\n' > BACKLOG-archive.md
OUT=$(run)
assert_empty "$OUT" "закрытый на месте пункт нарушением не считается"

# 4. Ничего не менялось — тишина (иначе страж станет фоном).
# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ (7 сентября 2026). Предполагалось двойное: что `git checkout`
# восстановил файл (отказ глотает `|| true`) и что тишина стража — про отсутствие
# изменений. Ложно и то и другое: замер того же дня — с занулённым VANISHED
# (`hooks/backlog-vanish-check.sh:175`) эта нога осталась зелёной, потому что онемевший
# страж молчит точно так же. Держат два предъявления: состояние дерева называется
# `git diff`, а способность стража говорить — канарейкой на ТОМ ЖЕ дереве.
git checkout -q -- BACKLOG.md 2>/dev/null || true
if git diff --quiet -- BACKLOG.md; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [дерево восстановлено]: BACKLOG.md разошёлся с HEAD, «без изменений» проверять не на чем"; fi
OUT=$(run)
assert_empty "$OUT" "без изменений молчит"
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
assert_contains "$(run)" "D11" "канарейка: на этом же дереве страж не онемел"
git checkout -q -- BACKLOG.md

# 5. Не git commit — не наше дело.
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "чужая команда игнорируется"

# --- Дубликат номера: один D у двух пунктов ---
# Повод 2026-08-26: две сессии работали параллельно, обе взяли следующий свободный номер,
# и D89 достался сразу пункту про fragile (закрыт, уехал в архив) и пункту про вставку
# чужого текста (открыт). Номер — единственный способ сослаться на пункт из CHANGELOG,
# коммита и соседнего пункта.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf -- 'архив\n- ☑ **D11** другой пункт с тем же номером\n' > BACKLOG-archive.md
OUT=$(run)
assert_contains "$OUT" "Один номер у двух пунктов" "дубликат номера назван"
assert_contains "$OUT" "D11" "дубликат назван поимённо"

# Открытая копия пункта в архиве — не коллизия, а след переноса летописи.
# Живой случай: при архивации туда уехали заголовки D59/D20/D23/D50 со статусом ☐, при
# том что сами пункты либо закрыты отдельной записью, либо продолжают жить в рабочем
# файле. Первая версия проверки объявила открытый D20 продублированным «архивным» —
# страж поймал сам себя на первом же коммите после появления.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf -- 'архив\n- ☐ **D11** старая открытая копия того же пункта\n' > BACKLOG-archive.md
OUT=$(run)
assert_empty "$OUT" "открытая копия в архиве коллизией не считается"

# Тот же набор без дубликата — тишина.
printf -- 'архив\n- ☑ **D09** закрытый\n' > BACKLOG-archive.md
OUT=$(run)
assert_empty "$OUT" "без дубликатов молчит"


# ── Объявлено закрытым в сообщении, а метка осталась открытой ─────────────────
# Повод измерен на себе 2026-08-27. Коммит 6b127b7 в сообщении: «D97 закрыт удалением
# дубля»; работа сделана в том же коммите (таблица мостов удалена из architecture.md);
# строка `- ☐ **D97**` не тронута. Итог: счёт открытого показывал 9 вместо 8, а
# backlog-recheck.sh — он перепроверяет ЗАКРЫТОЕ — единственный реально закрытый пункт
# не проверял вовсе.
run_msg() {
    jq -cn --arg c "git commit -m \"$1\"" \
        '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null
}

{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf 'архив\n' > BACKLOG-archive.md

OUT=$(run_msg 'chore(backlog): D11 закрыт удалением дубля')
assert_contains "$OUT" "D11" "заявленный закрытым пункт с меткой ☐ назван"
assert_contains "$OUT" "объявлен закрытым" "объяснено расхождение носителей"

# Обратный порядок слов ловится тоже.
OUT=$(run_msg 'chore: закрыт пункт D11')
assert_contains "$OUT" "D11" "порядок «закрыт D11» ловится"

# Метка переведена — тишина.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☑ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
OUT=$(run_msg 'chore(backlog): D11 закрыт удалением дубля')
assert_empty "$OUT" "переведённая метка нарушением не считается"

# Упоминание без объявления о закрытии — не повод. Иначе «D90 переписан» в одном
# сообщении с «D97 закрыт» поднимал бы тревогу по обоим.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
OUT=$(run_msg 'chore(backlog): D12 закрыт, D11 переписан')
assert_contains "$OUT" "D12" "закрытый назван"
if grep -q 'D11' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [упомянутый без «закрыт» не назван]: D11 попал в вывод: $OUT"
else PASS=$((PASS+1)); fi

# D1140: заявление — причастие «закрыт/а/о/ы» целым словом, а не любое слово с основой «закрыт». Существительное
# «закрытие» рядом с номером заявлением не было (коммит 187cc1e8 назвал открытый D1137 «объявленным закрытым»).
# Подсказка несёт метки знаками, а не именами переменных.
OUT=$(run_msg 'docs(долг): D11: закрытие пункта требует скептика')
assert_empty "$OUT" "D1140 «D11: закрытие …» заявлением не считается"
OUT=$(run_msg 'docs(долг): закрытие D11 требует скептика')
assert_empty "$OUT" "D1140 «закрытие D11 …» заявлением не считается"
OUT=$(run_msg 'chore: задача D11 закрыта')
assert_contains "$OUT" "D11" "D1140 «D11 закрыта» — заявление"
OUT=$(run_msg 'fix: страж — D11 закрыт (R6)')
assert_contains "$OUT" "D11" "D1140 «D11 закрыт (R6)» — заявление"
assert_contains "$OUT" "с ☐ пункт входит в счёт открытого" "D1140 подсказка несёт метку ☐ знаком"
if grep -qF '${BACKLOG_MARK_' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [D1140 подсказка без имён переменных]: $OUT"
else PASS=$((PASS+1)); fi
# Находки скептика D1140: граница слова судится по знакам в любой локали (M-1), конец строки (M-2, живая ловушка читает
# файл сообщения), номер без хвостовой точки (M-3), тире вплотную (L-1), левая граница (L-3), мутации M6/M7/M12/M13.
run_msg_c() { jq -cn --arg c "git commit -m \"$1\"" '{tool_name:"Bash", tool_input:{command:$c}}' | LC_ALL=C bash "$HOOK" 2>/dev/null; }
OUT=$(run_msg_c 'fix: D11 закрыт— дальше'); assert_contains "$OUT" "D11" "D1140 M-1 «D11 закрыт—» под LC_ALL=C"
OUT=$(run_msg_c 'docs: D11: закрытие пункта'); assert_empty "$OUT" "D1140 M-1 «D11: закрытие» под LC_ALL=C — не заявление"
OUT=$(jq -cn --arg c "$(printf 'git commit -m "fix: D11 закрыт\nдальше работа"')" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null)
assert_contains "$OUT" "D11" "D1140 M-2 «D11 закрыт» в конце строки сообщения"
OUT=$(run_msg 'chore: закрыт D11.'); assert_contains "$OUT" "D11" "D1140 M-3 «закрыт D11.» — номер без точки"
OUT=$(run_msg 'chore: закрыт—D11'); assert_contains "$OUT" "D11" "D1140 L-1 «закрыт—D11»"
OUT=$(run_msg 'chore: незакрыт пункт D11'); assert_empty "$OUT" "D1140 L-3 «незакрыт пункт D11» — не заявление"
OUT=$(run_msg 'chore: закрыты D11 и прочее'); assert_contains "$OUT" "D11" "D1140 «закрыты D11» (суффикс во втором порядке, M6)"
OUT=$(run_msg 'chore: закрыт (D11)'); assert_contains "$OUT" "D11" "D1140 «закрыт (D11)» (граница второго порядка, M7)"
OUT=$(run_msg 'chore: D11 закрытый пункт'); assert_empty "$OUT" "D1140 «D11 закрытый» — не заявление (M12)"
OUT=$(run_msg 'chore: D11 — закрыт'); assert_contains "$OUT" "D11" "D1140 «D11 — закрыт» (три знака между, M13)"

# Пункт уже уехал в архив закрытым — в рабочем файле его нет, тревоги нет.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D12** третий\n'; } > BACKLOG.md
printf -- 'архив\n- ☑ **D11** второй\n' > BACKLOG-archive.md
OUT=$(run_msg 'chore(backlog): D11 закрыт')
assert_empty "$OUT" "закрытый и уехавший в архив пункт тревоги не даёт"

# Команда, которая САМА закрывает пункт перед коммитом, тревоги не вызывает.
# Поймано на себе 28 августа 2026: закрытие пункта и коммит идут одной командой, а
# PreToolUse срабатывает ДО её начала — на момент проверки метка ещё «☐», хотя через
# секунду станет «☑». При обычном порядке работы страж кричал бы всегда.
{ printf -- '- ☐ **D10** первый\n'; printf -- '- ☐ **D11** второй\n'; } > BACKLOG.md
printf 'архив\n' > BACKLOG-archive.md
OUT=$(jq -cn '{tool_name:"Bash", tool_input:{command:"python3 - <<PY\n# правит BACKLOG.md\nPY\ngit add -A && git commit -m \"chore: D11 закрыт\""}}' | bash "$HOOK" 2>/dev/null)
if grep -q 'объявлен закрытым' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [своя правка в той же команде]: тревога на команде, которая сама закрывает пункт: $OUT"
else PASS=$((PASS+1)); fi

# А коммит БЕЗ правки долга в той же команде — тревога остаётся.
OUT=$(jq -cn '{tool_name:"Bash", tool_input:{command:"git commit -m \"chore: D11 закрыт\""}}' | bash "$HOOK" 2>/dev/null)
if grep -q 'объявлен закрытым' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [чистый коммит]: тревога пропала там, где правки нет: $OUT"; fi

# 8. Процесс хука вне репозитория сессии — корень берётся из cwd payload (D275).
# Прежние случаи запускают хук ИЗНУТРИ репозитория (cd "$REPO" выше), то есть в рамке,
# где чтение каталога процесса неотличимо от чтения payload.
{ printf -- '- \342\230\220 **D10** первый\n'; } > "$REPO/BACKLOG.md"
printf 'архив\n' > "$REPO/BACKLOG-archive.md"
OUT=$(cd / && printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$REPO" | bash "$HOOK" 2>/dev/null)
assert_contains "$OUT" "D11" "корень репозитория взят из cwd payload, а не из каталога процесса"
cd "$REPO"

echo ""
# --- ссылка на родню в заголовке пункта не есть второй пункт (3 сентября 2026) ---
# Своя копия признака брала ВСЕ D-номера строки, и пункт «- ☐ **D801** … родня D802»
# давал ложный сигнал «один номер у двух пунктов»: D802 лежал закрытым в архиве.
DUP=$(mktemp -d)
mkdir -p "$DUP/repo"
git -C "$DUP/repo" init -q .
printf -- '- \342\230\220 **D801** пункт со ссылкой на родню D802.\n' > "$DUP/repo/BACKLOG.md"
printf -- '- \342\230\221 **D802** закрытый пункт.\n' > "$DUP/repo/BACKLOG-archive.md"
git -C "$DUP/repo" add -A >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_vanish.sh:$LINENO" >&2; exit 1; }
git -C "$DUP/repo" -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_vanish.sh:$LINENO" >&2; exit 1; }
dup_run() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$DUP/repo" \
    | bash "$HOOK" 2>/dev/null; }

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ (7 сентября 2026). Предполагалось: раз строки «Один номер у двух
# пунктов» нет — значит ссылка на родню за пункт не принята. Ложно: этой строки нет и у
# стража, который данной фикстуры вовсе не читал (репозиторий не создался, коммит не
# состоялся, библиотека не нашлась — все три случая дают ту же тишину). Замер того же дня:
# с занулённым DUPES (`hooks/backlog-vanish-check.sh:183`) нога осталась зелёной.
# Держит канарейка на ТОЙ ЖЕ фикстуре: настоящий двойник D801 страж обязан НАЗВАТЬ, и
# только после этого его молчание про D802 что-то значит.
printf -- '- \342\230\221 **D801** закрытый двойник того же номера.\n- \342\230\221 **D802** закрытый пункт.\n' \
    > "$DUP/repo/BACKLOG-archive.md"
DUP_CTRL=$(dup_run)
if grep -q "D801" <<< "$DUP_CTRL" && grep -q "Один номер у двух пунктов" <<< "$DUP_CTRL"; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [канарейка родни]: настоящий двойник D801 не назван — фикстура не осмотрена: $DUP_CTRL"
fi

printf -- '- \342\230\221 **D802** закрытый пункт.\n' > "$DUP/repo/BACKLOG-archive.md"
DUP_OUT=$(dup_run)
rm -rf "$DUP"
if grep -q "Один номер у двух пунктов" <<< "$DUP_OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [родня]: ссылка на родню принята за второй пункт: $DUP_OUT"
else
    PASS=$((PASS+1))
fi

# --- файл долга удалён ЦЕЛИКОМ (17 сентября 2026, D434) ---
# До этого дня страж выходил на `[ -f BACKLOG.md ] || exit 0` РАНЬШЕ, чем спрашивал HEAD:
# потеря одного пункта называлась, потеря всех — молчала. Различает «долга у проекта нет» и
# «долг был, файл удалён» только HEAD, поэтому обе стороны готовятся на ОДНОМ репозитории:
# сперва HEAD без BACKLOG.md (тишина законна), затем HEAD с пунктами и удалённый файл.
# Песочница лежит внутри $TMP: его снимает trap в шапке файла, и обрыв до конца блока
# каталога не оставит (своего trap у блока нет — второй `trap … EXIT` заменил бы первый).
WH="$TMP/wh434"
mkdir -p "$WH/repo"
WG="git -C $WH/repo -c user.email=t@t -c user.name=t"
$WG init -q . 2>/dev/null
$WG commit -q --allow-empty -m empty >/dev/null 2>&1
wh_run() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$WH/repo" \
    | bash "$HOOK" 2>/dev/null; }

# 9. Проект без долга: ни в HEAD, ни в дереве файла нет — тишина, как прежде.
assert_empty "$(wh_run)" "проект без BACKLOG.md в HEAD молчит"

{ printf -- '- \342\230\220 **D10** первый\n'; printf -- '- \342\230\220 **D11** второй\n'; } > "$WH/repo/BACKLOG.md"
printf -- 'архив\n- \342\230\221 **D09** закрытый\n' > "$WH/repo/BACKLOG-archive.md"
$WG add -A >/dev/null 2>&1; $WG commit -qm base >/dev/null 2>&1
# Фундамент предъявляется числом: без пунктов в HEAD тишина ног ниже ничего бы не значила.
WH_BASE=$(git -C "$WH/repo" show HEAD:BACKLOG.md 2>/dev/null | grep -cF -- '**D1')
if [ "${WH_BASE:-0}" -eq 2 ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [фундамент D434]: в HEAD пунктов ${WH_BASE:-0} из 2"; fi

# 10. Простой `rm`: рабочей копии нет, HEAD несёт два пункта — названы ОБА и сказано, что
# файл удалён целиком (у прежнего текста «перезапись куска файла» здесь была бы неправдой).
rm -f "$WH/repo/BACKLOG.md"
OUT=$(wh_run)
assert_contains "$OUT" "D10" "удалён целиком (rm): первый пункт HEAD назван"
assert_contains "$OUT" "D11" "удалён целиком (rm): второй пункт HEAD назван"
assert_contains "$OUT" "удалён целиком" "удаление файла названо удалением, а не перезаписью куска"
assert_contains "$OUT" "не найдены в архиве" "общая часть сообщения сохранена"

# 11. `git rm`: нет ни в индексе, ни в дереве — то же.
$WG rm -q --cached BACKLOG.md >/dev/null 2>&1
assert_contains "$(wh_run)" "D11" "удалён целиком (git rm): пункт HEAD назван"

# 12. Все пункты HEAD лежат в архиве — удаление файла законно, тишина. Канарейка та же, что
# у ноги 4: на этом же дереве без одной архивной строки страж обязан заговорить.
# АРХИВ СТАВИТСЯ В ИНДЕКС (17 сентября 2026, D435). Нога готовила только рабочую копию, а
# payload у неё — голый `git commit`: он уносит ИНДЕКС, и с архивом лишь на диске коммит унёс бы
# удаление файла без архивной половины — страж теперь называет это, и называет верно. «Законное
# удаление» значит, что в коммит идут ОБЕ половины, поэтому фикстура доведена до честной.
printf -- 'архив\n- \342\230\221 **D10** первый\n- \342\230\221 **D11** второй\n' > "$WH/repo/BACKLOG-archive.md"
$WG add BACKLOG-archive.md >/dev/null 2>&1
assert_empty "$(wh_run)" "файл удалён, но все пункты в архиве — молчит"
printf -- 'архив\n- \342\230\221 **D10** первый\n' > "$WH/repo/BACKLOG-archive.md"
$WG add BACKLOG-archive.md >/dev/null 2>&1
OUT=$(wh_run)
assert_contains "$OUT" "D11" "канарейка: пункт вне архива назван на том же дереве"
if grep -q 'D10' <<< "$OUT"; then
    FAIL=$((FAIL+1)); echo "FAIL [архивный пункт не назван]: D10 лежит в архиве, а попал в вывод: $OUT"
else PASS=$((PASS+1)); fi
rm -rf "$WH"

# --- D435: какой снимок унесёт коммит — решает ФОРМА КОМАНДЫ ------------------------------------
# Дефект: в индексе BACKLOG.md без пункта, рабочая копия с ним, голый `git commit` — страж молчал,
# а коммит уносил индекс. Замер формы классификатором стража по 1411 командам проекта: у 95%
# команда сама собирает индекс (на момент хука он ещё старый — судится рабочая копия), голых
# коммитов 5% (судятся оба снимка). Каждая нога ниже — одна форма; раскладка у всех одна и
# готовится ЯВНО.
IX="$TMP/ix435"
mkdir -p "$IX/repo"
IG="git -C $IX/repo -c user.email=t@t -c user.name=t"
$IG init -q . 2>/dev/null
{ printf -- '- \342\230\220 **D10** первый\n'; printf -- '- \342\230\220 **D11** второй\n'; } > "$IX/repo/BACKLOG.md"
$IG add -A >/dev/null 2>&1; $IG commit -qm base >/dev/null 2>&1
printf -- '- \342\230\220 **D10** первый\n' > "$IX/repo/BACKLOG.md"
$IG add BACKLOG.md >/dev/null 2>&1                                   # индекс: без D11
{ printf -- '- \342\230\220 **D10** первый\n'; printf -- '- \342\230\220 **D11** второй\n'; } > "$IX/repo/BACKLOG.md"   # копия: с D11
ix_run() { jq -cn --arg cwd "$IX/repo" --arg c "$1" '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null; }
# Рамка предъявляется числом: без такой раскладки ноги ниже ничего бы не различали.
IX_IDX=$(git -C "$IX/repo" show :BACKLOG.md 2>/dev/null | grep -cF -- '**D11**')
IX_WT=$(grep -cF -- '**D11**' "$IX/repo/BACKLOG.md")
if [ "$IX_IDX" = "0" ] && [ "$IX_WT" = "1" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [рамка D435]: D11 в индексе $IX_IDX (ждали 0), в копии $IX_WT (ждали 1)"; fi

# 13. Голый коммит: уйдёт индекс, D11 в нём нет — назван, и сказано, КАКОЙ снимок судился.
OUT=$(ix_run 'git commit -m x')
assert_contains "$OUT" "D11" "голый коммит: пункт, которого нет в индексе, назван"
assert_contains "$OUT" "ИНДЕКС" "голый коммит: сказано, что судился индекс"
if grep -q 'D10' <<< "$OUT"; then FAIL=$((FAIL+1)); echo "FAIL [пункт на месте не назван]: D10 есть в обоих снимках, а попал в вывод"
else PASS=$((PASS+1)); fi
# 14. `-a`: в коммит идёт рабочая копия, D11 в ней есть — тишина.
assert_empty "$(ix_run 'git commit -a -m x')" "-a: судится рабочая копия, пункт на месте — молчит"
# 15. Слитные короткие флаги — та же форма.
assert_empty "$(ix_run 'git commit -qam x')" "-qam: флаг a в связке опознан — молчит"
# 16. `git add` в той же команде: индекс на момент хука старый, его перезапишет add — тишина.
assert_empty "$(ix_run 'git add BACKLOG.md && git commit -m x')" "git add до коммита: судится рабочая копия — молчит"
# 17. `-a` в ТЕКСТЕ сообщения флагом не является: форма читается с исполняемой части команды.
assert_contains "$(ix_run 'git commit -m "fix: flag -a and git add in text"')" "D11" "-a в тексте сообщения не снимает суд индекса"
# 18. Путь долга назван аргументом коммита — уйдёт рабочая копия этого пути, тишина.
assert_empty "$(ix_run 'git commit BACKLOG.md -m x')" "git commit <путь долга>: судится рабочая копия — молчит"
# --- находки скептика 17 сентября 2026: первая редакция починки решала снимок на КОМАНДУ, а git
# решает его на ПУТЬ; на каждой форме ниже она молчала при реально пропадающем пункте.
# 20. `git add <чужой путь>`: долг уйдёт из индекса, add его не касается — назван (398 команд истории).
: > "$IX/repo/other.txt"
assert_contains "$(ix_run 'git add other.txt && git commit -m x')" "D11" "git add чужого пути: судится индекс — назван"
# 21. Чужой флаг с буквой «a» СТРОКОЙ НИЖЕ коммита флагом коммита не является.
assert_contains "$(ix_run "$(printf 'git commit -m x\nls -la')")" "D11" "флаг соседней строки не снимает суд индекса"
# 22. `--all` — та же форма, что `-a` (мутант без неё проходил прежний тест).
assert_empty "$(ix_run 'git commit --all -m x')" "--all: судится рабочая копия — молчит"
# 23. `git -C <репозиторий> commit` из чужого каталога: коммит опознан, судится ЕГО репозиторий.
OUT=$(jq -cn --arg c "git -C $IX/repo commit -m x" '{tool_name:"Bash", cwd:"/", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null)
assert_contains "$OUT" "D11" "git -C <репозиторий> commit: опознан и судится названный репозиторий"
# 24. `git commit <чужой путь>`: в коммит идёт только он, долг останется как в HEAD — тишина.
assert_empty "$(ix_run 'git commit other.txt -m x')" "git commit <чужой путь>: долг не тронут — молчит"
# 19. Обратная раскладка при `-a`: в копии пункта нет — назван (страж не онемел на форме).
printf -- '- \342\230\220 **D10** первый\n' > "$IX/repo/BACKLOG.md"
assert_contains "$(ix_run 'git commit -a -m x')" "D11" "-a при копии без пункта: назван"
# 25. Пункта нет НИ в копии, НИ в индексе: назван ОДИН раз, сообщением о файле, а не вторым — об индексе.
OUT=$(ix_run 'git commit -m x')
N25=$(grep -c 'hookSpecificOutput' <<< "$OUT")
if [ "$N25" = "1" ] && ! grep -q 'ИНДЕКС' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [пункт назван дважды]: сообщений $N25 (ждали 1, без слова ИНДЕКС): $OUT"; fi
rm -rf "$IX"

# --- половина переноса и неотслеживаемый архив -------------------------------------------------
HT="$TMP/ht435"
mkdir -p "$HT/repo"
HG="git -C $HT/repo -c user.email=t@t -c user.name=t"
$HG init -q . 2>/dev/null
{ printf -- '- \342\230\220 **D10** первый\n'; printf -- '- \342\230\220 **D11** второй\n'; } > "$HT/repo/BACKLOG.md"
$HG add -A >/dev/null 2>&1; $HG commit -qm base >/dev/null 2>&1
# перенос D11 в архив сделан НА ДИСКЕ: из BACKLOG.md убран, в новый (неотслеживаемый) архив положен
printf -- '- \342\230\220 **D10** первый\n' > "$HT/repo/BACKLOG.md"
printf -- 'архив\n- \342\230\221 **D11** второй\n' > "$HT/repo/BACKLOG-archive.md"
ht_run() { jq -cn --arg cwd "$HT/repo" --arg c "$1" '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null; }
# 26. Половина переноса ОДНОЙ командой: в add назван только BACKLOG.md — архив в коммит не попадёт.
assert_contains "$(ht_run 'git add BACKLOG.md && git commit -m x')" "D11" "половина переноса (add без архива): назван"
assert_empty "$(ht_run 'git add BACKLOG.md BACKLOG-archive.md && git commit -m x')" "обе половины в add — молчит"
assert_empty "$(ht_run 'git add -A && git commit -m x')" "git add -A берёт и неотслеживаемый архив — молчит"
# 27. `-am` НЕотслеживаемый архив не возьмёт: пункт пропадёт — назван; архив отслеживается — тишина.
assert_contains "$(ht_run 'git commit -am x')" "D11" "-am при неотслеживаемом архиве: назван"
$HG add BACKLOG-archive.md >/dev/null 2>&1
assert_empty "$(ht_run 'git commit -am x')" "-am при отслеживаемом архиве — молчит"
rm -rf "$HT"

# 28. Индекс в состоянии КОНФЛИКТА не судится: `git show :BACKLOG.md` там отвечает отказом, и без
# гейта «не смог прочитать» выходило бы «все пункты исчезли» (мутант без гейта красит эту ногу).
CF="$TMP/cf435"
mkdir -p "$CF/repo"
CG="git -C $CF/repo -c user.email=t@t -c user.name=t"
$CG init -q . 2>/dev/null
printf -- '- \342\230\220 **D10** первый\n' > "$CF/repo/BACKLOG.md"
$CG add -A >/dev/null 2>&1; $CG commit -qm base >/dev/null 2>&1
CF_MAIN=$(git -C "$CF/repo" rev-parse --abbrev-ref HEAD)
$CG checkout -q -b side >/dev/null 2>&1
printf -- '- \342\230\220 **D10** первый, правка сбоку\n' > "$CF/repo/BACKLOG.md"; $CG commit -qam side >/dev/null 2>&1
$CG checkout -q "$CF_MAIN" >/dev/null 2>&1
printf -- '- \342\230\220 **D10** первый, правка в главной\n' > "$CF/repo/BACKLOG.md"; $CG commit -qam main >/dev/null 2>&1
$CG merge side >/dev/null 2>&1
if [ -n "$(git -C "$CF/repo" ls-files -u -- BACKLOG.md 2>/dev/null)" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [рамка конфликта]: конфликт в BACKLOG.md не получился — нога 28 ничего бы не различала"; fi
assert_empty "$(jq -cn --arg cwd "$CF/repo" '{tool_name:"Bash", cwd:$cwd, tool_input:{command:"git commit -m x"}}' | bash "$HOOK" 2>/dev/null)" "конфликт в индексе: индекс не судится — молчит"
rm -rf "$CF"

echo "backlog-vanish tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
