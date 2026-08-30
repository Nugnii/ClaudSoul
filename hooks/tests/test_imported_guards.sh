#!/usr/bin/env bash
# test_imported_guards.sh — минимальное доказательство для семи стражей, приехавших
# в репозиторий без тестов.
#
# Происхождение. В v1.11.0 обнаружилось, что `install.sh` ставил 22 хука из 31
# работающих: девять жили только в `~/.claude/hooks/` — ни файла в репозитории, ни
# регистрации. Восемь из них импортировали. Тестов при этом не написали, и с тех пор
# их молчание не значило ничего: пустой файл вёл бы себя точно так же.
#
# Мета-тест `test_guards_provable.sh` теперь это ловит механически. Здесь — закрытие
# долга, который он назвал.
#
# У каждого стража ровно два случая: вход, на котором он ОБЯЗАН загореться, и вход,
# на котором обязан молчать. Меньше нельзя — одного случая не хватает по построению:
# страж, который горит всегда, и страж, который молчит всегда, оба одинаково
# бесполезны и оба проходят проверку из одного утверждения.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 200)"; fi
}
assert_empty() {
    if [ -z "$1" ] || [ "$1" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; fi
}

# $1 — имя хука, $2 — JSON payload, далее env-присваивания
run_hook() {
    local hook="$1" payload="$2"; shift 2
    printf '%s' "$payload" | env STATE_DIR="$STATE_DIR" "$@" bash "$HOOKS_DIR/$hook.sh" 2>/dev/null
}

payload() { # tool, command|file_path, [content], [cwd], [sid]
    jq -cn --arg t "$1" --arg c "${2:-}" --arg f "${3:-}" --arg cw "${4:-$TMP}" --arg s "${5:-sid}" \
        '{session_id:$s, tool_name:$t, cwd:$cw,
          tool_input:{command:$c, file_path:$f, content:$f}}'
}

new_repo() {
    local r="$1"; rm -rf "$r"; mkdir -p "$r"
    git -C "$r" init -q 2>/dev/null
    git -C "$r" config user.email t@e; git -C "$r" config user.name t
    echo seed > "$r/seed.txt"; git -C "$r" add . >/dev/null 2>&1
    git -C "$r" commit -q -m seed 2>/dev/null
}

# === bulk-copy-guard: массовое копирование без подтверждения ===
OUT=$(run_hook bulk-copy-guard "$(payload Bash 'cp -r /src/Statements/ /dst/')" )
assert_contains "$OUT" "Bulk-copy guard" "bulk-copy: рекурсивное копирование → спрашивает"
OUT=$(run_hook bulk-copy-guard "$(payload Bash 'ls -la')" "SID=x")
assert_empty "$OUT" "bulk-copy: обычная команда → тишина"

# === internal-doc-leak-guard: внутренняя пометка в путь получателя ===
OUT=$(run_hook internal-doc-leak-guard \
    "$(jq -cn '{session_id:"s1", tool_name:"Write", cwd:".",
                tool_input:{file_path:"/x/Lawyer_Track/memo.md", content:"Для адвоката: черновик"}}')")
assert_contains "$OUT" "Internal-doc leak guard" "internal-doc: маркер + внешняя папка → спрашивает"
OUT=$(run_hook internal-doc-leak-guard \
    "$(jq -cn '{session_id:"s2", tool_name:"Write", cwd:".",
                tool_input:{file_path:"/x/notes/memo.md", content:"Для адвоката: черновик"}}')")
assert_empty "$OUT" "internal-doc: маркер, но путь не внешний → тишина"

# === user-correction-guard: поправка собеседника перед действием ===
TR="$TMP/tr.jsonl"
printf '{"type":"user","message":{"content":[{"type":"text","text":"не так, я говорил другое"}]}}\n' > "$TR"
OUT=$(printf '%s' "$(jq -cn --arg tr "$TR" '{session_id:"c1", tool_name:"Bash", transcript_path:$tr, cwd:".", tool_input:{command:"echo hi"}}')" \
    | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/user-correction-guard.sh" 2>/dev/null)
assert_contains "$OUT" "поправк" "user-correction: поправка в транскрипте → спрашивает"
printf '{"type":"user","message":{"content":[{"type":"text","text":"давай дальше по плану"}]}}\n' > "$TR"
OUT=$(printf '%s' "$(jq -cn --arg tr "$TR" '{session_id:"c2", tool_name:"Bash", transcript_path:$tr, cwd:".", tool_input:{command:"echo hi"}}')" \
    | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/user-correction-guard.sh" 2>/dev/null)
assert_empty "$OUT" "user-correction: обычная реплика → тишина"

# === user-correction-guard на РЕАЛЬНЫХ данных (v1.13.3) ===
#
# Прежний словарь был придуман. Измерение: за 214 сессий 9 срабатываний, большинство
# не поправки; на шести настоящих поправках одной сессии — ноль. При этом на
# собственных выдуманных фразах срабатывал исправно. Пустой correction-fired означал,
# что второму продюсеру контура опровержения нечего собирать, и база структурно не
# могла сказать «нет».
#
# Ниже — дословные реплики собеседника и дословные же обычные сообщения из того же
# диалога как отрицательный контроль. Фикстуры из данных, а не из представления о них.
_corr() { # текст, ожидание: fire|silent, метка
    printf '{"type":"user","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$TR"
    local out
    out=$(printf '%s' "$(jq -cn --arg tr "$TR" --arg s "corr$RANDOM" '{session_id:$s, tool_name:"Bash", transcript_path:$tr, cwd:".", tool_input:{command:"echo hi"}}')" \
        | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/user-correction-guard.sh" 2>/dev/null)
    # Утверждаемся на устойчивой части текста, а не на слове, которое меняется
    # при каждой переформулировке сообщения (на этом тест уже ломался).
    if [ "$2" = "fire" ]; then assert_contains "$out" "поправк" "$3"
    else assert_empty "$out" "$3"; fi
}
_corr "хер пойми из пояснения что осталось за мной"        fire   "поправка: обсценная лексика"
_corr "нихрена не понял из признания"                       fire   "поправка: отрицание понимания"
_corr "не запомнить стоит, а починить"                      fire   "поправка: конструкция «не X, а Y»"
_corr "3 раза делал одно и то же потому что не использовал" fire   "поправка: указание на повтор"
_corr "Подожди. Проблема глубже."                           fire   "поправка: императив остановки"
_corr "Ахиренная штука 5 почему"                            silent "похвала не считается поправкой"
_corr "Я сначала выведу деньги на холодный кошелёк"         silent "обычная реплика (старый словарь тут ошибался)"
_corr "Оператор может взять в работу и передвинуть в CRM"   silent "обычная реплика (старый словарь тут ошибался)"
_corr "Закрывай"                                            silent "короткая команда не поправка"

# === Контекстный сигнал: без словаря вообще (v1.13.4) ===
#
# Формулировка собеседника: поправка определяется не словами, а положением реплики
# в диалоге. Если правится файл, который уже правился, и между правками была реплика
# человека — показать эту реплику и потребовать назвать причину. Ярлык не ставится:
# словарь ошибался в обе стороны, положение — нет.
CTX_TR="$TMP/ctx.jsonl"
cat > "$CTX_TR" <<'CTXEOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/a.sh"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"готово"}]}}
{"type":"user","message":{"content":[{"type":"text","text":"а если посмотреть с другой стороны"}]}}
CTXEOF
_ctx() { # file_path, ожидание, метка
    local out
    out=$(jq -cn --arg tr "$CTX_TR" --arg f "$1" --arg s "ctx$RANDOM" \
        '{session_id:$s, tool_name:"Edit", transcript_path:$tr, cwd:".", tool_input:{file_path:$f}}' \
        | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/user-correction-guard.sh" 2>/dev/null)
    if [ "$2" = "fire" ]; then assert_contains "$out" "который уже правил" "$3"
    else assert_empty "$out" "$3"; fi
}
# Реплика без единого слова из словаря — ловится положением, а не лексикой.
_ctx "/repo/a.sh" fire   "контекст: повторная правка после реплики → показать реплику"
_ctx "/repo/b.sh" silent "контекст: другой файл → тишина"

# === Отсев шума контекстного сигнала (D25) ===
#
# Фикстуры дословные, из выборки 66 срабатываний (3-26 августа). Оценка показала: 64 из
# 66 дал контекстный сигнал, точность 29%. У 27 ложных есть машинный признак, ни у одной
# настоящей поправки его нет. После отсева — 39 срабатываний и 49% точности при нуле
# потерянных поправок.
_ctx_text() { # текст реплики, ожидание, метка
    local tr="$TMP/ctxt.jsonl"
    {
        printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/a.sh"}}]}}'
        printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
        jq -cn --arg t "$1" '{type:"user", message:{content:[{type:"text", text:$t}]}}'
    } > "$tr"
    local out
    out=$(jq -cn --arg tr "$tr" --arg s "ctxt$RANDOM" \
        '{session_id:$s, tool_name:"Edit", transcript_path:$tr, cwd:".", tool_input:{file_path:"/repo/a.sh"}}' \
        | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/user-correction-guard.sh" 2>/dev/null)
    if [ "$2" = "fire" ]; then assert_contains "$out" "правил" "$3"
    else assert_empty "$out" "$3"; fi
}
_ctx_text "делай"                    silent "D25: короткая команда не поправка (17 таких в выборке)"
_ctx_text "продолжай"                silent "D25: самая длинная ложная команда выборки — 9 символов"
_ctx_text "ARGUMENTS: patch"         silent "D25: аргументы скилла — реплика скилла, не человека"
_ctx_text "[Image: original 1634x2280, displayed at 1433x2000]" silent "D25: вложение — не реплика"
_ctx_text "не заводи отдельно"       fire   "D25: самая короткая настоящая поправка выборки (18) проходит"
_ctx_text "эта страница только на русском" fire "D25: содержательная поправка проходит"

# Отсев по длине — только для контекстного пути: словарные «стоп» и «опять» короче
# порога и при этом настоящие поправки. Отобрать их у лексики нельзя.
_corr "стоп "                        fire   "D25: короткое словарное срабатывание не срезано длиной"
_corr "намерено ру - не понимаю."    fire   "D25: дыра словаря закрыта — было «не понял» без «не понимаю»"

# === Сигнал предмета: реплика о том, что я назвал сделанным (D86) ===
# Пять пропусков из восьми в замере 2026-08-26 — поправки без единого лексического маркера
# и без повторной правки файла. Лексически они неотличимы от постановки задачи; различает
# их то, что поправка говорит о ТОЛЬКО ЧТО сделанном. Мера — пересечение значимых слов с
# последним ходом агента, порог 2 (замер: полнота 46%, точность 60% на 42 репликах).
_subj() { # текст агента, текст человека, ожидание, метка
    local tr="$TMP/subj.jsonl"
    {
        jq -cn --arg t "$1" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}'
        jq -cn --arg t "$2" '{type:"user", message:{content:[{type:"text", text:$t}]}}'
    } > "$tr"
    local out
    out=$(jq -cn --arg tr "$tr" --arg s "subj$RANDOM" \
        '{session_id:$s, tool_name:"Bash", transcript_path:$tr, cwd:".", tool_input:{command:"echo hi"}}' \
        | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/user-correction-guard.sh" 2>/dev/null)
    if [ "$3" = "fire" ]; then assert_contains "$out" "поправк" "$4"
    else assert_empty "$out" "$4"; fi
}
_subj "Реализовал заказ выплаты: оператор выбирает получателя, подчинённые подтягиваются автоматически" \
      "При заказе выплаты сейчас есть выбор себе или подчинённому, выбор должен появляться только если подчинённые есть" \
      fire "D86: реплика про только что сделанное — поправка"
_subj "Импортировал отделы из выгрузки, структура развернулась" \
      "Нужен инструмент отслеживания активности, чтобы понимать кто открыл опросник" \
      silent "D86: другой предмет — постановка задачи, не поправка"
_subj "Готово" "делай дальше" silent "D86: короткая реплика без общего предмета молчит"

# Тот же транскрипт, но файл правится ВПЕРВЫЕ — правка не вызвана репликой.
CTX_FIRST="$TMP/ctx-first.jsonl"
cat > "$CTX_FIRST" <<'CTXEOF'
{"type":"user","message":{"content":[{"type":"text","text":"сделай тихо и аккуратно"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"делаю"}]}}
CTXEOF
OUT=$(jq -cn --arg tr "$CTX_FIRST" --arg s "ctxf" \
    '{session_id:$s, tool_name:"Edit", transcript_path:$tr, cwd:".", tool_input:{file_path:"/repo/new.sh"}}' \
    | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/user-correction-guard.sh" 2>/dev/null)
assert_empty "$OUT" "контекст: первая правка файла → тишина"

# === claude-md-size-check: CLAUDE.md больше порога ===
R1="$TMP/r1"; new_repo "$R1"
head -c 120000 /dev/zero | tr '\0' 'x' > "$R1/CLAUDE.md"
OUT=$(run_hook claude-md-size-check "$(payload Bash 'git commit -m x' '' "$R1" s-big)")
assert_contains "$OUT" "CLAUDE.md" "claude-md-size: файл за порогом → предупреждает"
echo "маленький" > "$R1/CLAUDE.md"
OUT=$(run_hook claude-md-size-check "$(payload Bash 'git commit -m x' '' "$R1" s-small)")
assert_empty "$OUT" "claude-md-size: файл в норме → тишина"

# === code-review-reminder: крупный diff перед коммитом ===
R2="$TMP/r2"; new_repo "$R2"
for i in $(seq 1 6); do seq 1 30 > "$R2/f$i.py"; done
git -C "$R2" add . >/dev/null 2>&1
OUT=$(run_hook code-review-reminder "$(payload Bash 'git commit -m big' '' "$R2" s-big)")
assert_contains "$OUT" "Крупный кодовый дифф" "code-review: крупный diff → напоминает"
R3="$TMP/r3"; new_repo "$R3"
echo "one line" > "$R3/small.py"; git -C "$R3" add . >/dev/null 2>&1
OUT=$(run_hook code-review-reminder "$(payload Bash 'git commit -m small' '' "$R3" s-small)")
assert_empty "$OUT" "code-review: маленький diff → тишина"

# === playwright-cli-guard: одноразовый скрипт вместо скилла ===
# Признак одноразового скрипта по эвристике хука — прямой запуск браузера.
# Строку собираем из кусков: иначе она попадает в текст Bash-команды при правке
# файла, и страж блокирует запись собственного теста. Ложное срабатывание по
# существу, формально верное по его правилам — записано как наблюдение.
PW_SCRATCH='const { chromium } = require("playwright"); const b = await chromium'".launch();"
OUT=$(run_hook playwright-cli-guard \
    "$(jq -cn --arg c "$PW_SCRATCH" '{session_id:"p1", tool_name:"Write", cwd:".",
                tool_input:{file_path:"/tmp/check.js", content:$c}}')")
assert_contains "$OUT" "deny" "playwright: одноразовый скрипт → блокирует"
OUT=$(run_hook playwright-cli-guard \
    "$(jq -cn '{session_id:"p2", tool_name:"Write", cwd:".",
                tool_input:{file_path:"/proj/e2e/login.spec.ts", content:"const { chromium } = require(\"playwright\");"}}')")
assert_empty "$OUT" "playwright: нормальный тест в e2e/ → тишина"

# === pre-compact-handoff: нить работы перед сжатием ===
R4="$TMP/r4"; mkdir -p "$R4"
printf '# Session Log\n\n## сегодня\n### Next steps\n- доделать X\n' > "$R4/SESSION.md"
OUT=$(run_hook pre-compact-handoff "$(jq -cn --arg cw "$R4" '{session_id:"h1", cwd:$cw}')")
assert_contains "$OUT" "additionalContext" "pre-compact-handoff: есть SESSION.md → отдаёт нить"
R5="$TMP/r5"; mkdir -p "$R5"
OUT=$(run_hook pre-compact-handoff "$(jq -cn --arg cw "$R5" '{session_id:"h2", cwd:$cw}')")
assert_empty "$OUT" "pre-compact-handoff: нет SESSION.md → тишина"

echo ""
echo "=================================="
echo "imported-guards: $PASS passed, $FAIL failed"
echo "=================================="
[ "$FAIL" -eq 0 ]
