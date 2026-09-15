#!/usr/bin/env bash
# test_knowledge_activator.sh — характеризующий тест knowledge-activator.sh.
#
# Хук НЕ имел своего теста (988 строк, горячий путь L1→L2 broadcast). Этот тест
# фиксирует наблюдаемый контракт ПЕРЕД рефактором (разрез по слоям domain-graph /
# semantic-fallback / startup-context), чтобы рефактор не сломал поведение незаметно.
#
# Контролируемое окружение: фейковый HOME + минимальная global-lessons + фикс.
# CLAUDE_CODE_SESSION_ID (делает gate-файл детерминированным) → first-fire/cooldown
# воспроизводимы. cli_search / domains отсутствуют → graceful degradation (часть
# контракта). Ассерты — по сути (наличие секций, всплытие знания), не по форме.
set -uo pipefail
# Каталог реестра сессий выводится ИЗ HOME намеренно: предмет проверки — умолчание,
# по которому хук определяет проект. Раннер даёт каждому тесту свой SR_SESSIONS_DIR
# (D271), и унаследованная переменная увела бы запись в чужой каталог — тест зеленел
# бы в одиночку и краснел под раннером. Образец тот же, что в
# test_knowledge_delta_reaches_registry.sh:62 и test_startup_signals.sh:29.
unset SR_SESSIONS_DIR

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/knowledge-activator.sh"
REPO_ROOT="$(cd "$HOOK_DIR/.." && pwd)"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -qF "$needle" <<< "$haystack"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: не найдено '$needle'"
    fi
}

assert_empty() {
    local val="$1" label="$2"
    if [ -z "$val" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: ожидалось пусто, получено '${val:0:80}...'"
    fi
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: ожидалось '$expected', получено '$actual'"
    fi
}

setup_home() {
    rm -rf "$TMP/home"
    mkdir -p "$TMP/home/.claude/global-lessons" "$TMP/home/.claude/hooks/state"
    cat > "$TMP/home/.claude/global-lessons/pattern-deploy-safety.md" <<'KF'
---
name: deploy-safety
type: pattern
confidence: 4
impact: 4
domain: [devops]
situation: deploying_to_production
trigger: deploy_command
tags: [deploy, rsync, database, exclude]
volatile_anchors: [environment]   # прод может стать стейджем посреди выкладки
self_altering: "выкладка меняет само окружение, про которое знание"
---
Never copy DB/caches/env on deploy.
KF
}

run_activator() {
    local input="$1"
    local root="${2:-$REPO_ROOT}"
    printf '%s' "$input" | env \
        HOME="$TMP/home" \
        CLAUDE_CODE_SESSION_ID="test-ka-fixed" \
        STATE_DIR="$TMP/home/.claude/hooks/state" \
        CLAUDSOUL_ROOT="$root" \
        bash "$HOOK" 2>/dev/null
}

INPUT_MATCH='{"session_id":"test-ka-fixed","tool_name":"Bash","cwd":"/tmp/proj","tool_input":{"command":"rsync deploy database to production server"}}'

# === T1-T4: первое срабатывание с совпадающим знанием ===
setup_home
OUT=$(run_activator "$INPUT_MATCH")
RC=$?
assert_eq "0" "$RC" "T1: first-fire exit 0"
assert_contains "$OUT" '"hookEventName": "PreToolUse"' "T2: валидный PreToolUse-конверт"
assert_contains "$OUT" "pattern-deploy-safety" "T3: совпадающее знание всплыло (путь скоринга домен-графа)"
assert_contains "$OUT" "ПУНКТ 0" "T4: Пункт 0 (demand-first) инжектится на первом срабатывании"
# Изменчивость якорей (v0.3): предупреждение видно в момент дела, а не только
# тому, кто откроет файл знания руками (2026-08-27).
assert_contains "$OUT" "может уплыть по ходу: environment" "T4b: volatile_anchors в инжекте"
assert_contains "$OUT" "применение само меняет: выкладка меняет" "T4c: self_altering в инжекте"

# === B1-B2: род дефекта B — цена отбора названа, а не подставлена молча ===
# У фикстуры нет полей intensity и confirmed_count, и прежде оба молча становились нулём:
# intensity 0 — «сюрприза нет» (минус до 5 очков surprise_bonus), confirmed_count 0 —
# «не подтверждалось ни разу» (штраф FSRS до 50% и метка overdue). Запись опускалась в
# ранжировании из-за НЕЗАПОЛНЕННОГО поля, а список печатался как измеренный. Форма из
# мира: замер по живой базе — 14 записей из 50 ранжируемых без intensity.
assert_contains "$OUT" "Полей шапки не прочитано: 2 (intensity, confirmed_count)" \
    "B1: цена отбора названа прямо в инжекте"

# КОНТРПРИМЕР: поля на месте — ни слова про непрочитанное. Без него зелёный B1
# неотличим от строки, которая печатается всегда.
setup_home
cat > "$TMP/home/.claude/global-lessons/pattern-deploy-safety.md" <<'KFB'
---
name: deploy-safety
type: pattern
confidence: 4
impact: 4
intensity: 3
confirmed_count: 6
domain: [devops]
situation: deploying_to_production
trigger: deploy_command
tags: [deploy, rsync, database, exclude]
---
Never copy DB/caches/env on deploy.
KFB
OUT_READ=$(run_activator "$INPUT_MATCH")
assert_contains "$OUT_READ" "pattern-deploy-safety" "B2a: знание с полной шапкой всё ещё всплывает"
if grep -qF "Полей шапки не прочитано" <<< "$OUT_READ"; then
    FAIL=$((FAIL + 1)); echo "FAIL [B2b]: заполненная шапка объявлена непрочитанной"
else
    PASS=$((PASS + 1))
fi

# === T13-T16: кейсы-сироты приходят сами, обобщённые — нет ===
# До 26 августа 2026 кейс не попадал в контекст никогда: цикл перебирал только
# обобщения, а единственная дверь — семантический откат — закрылась, когда база
# паттернов доросла до того, что поиск по ключевым словам стал находить всегда.
# Замер: подач кейсов 440 / 625 / 283 за апрель-июнь и ноль за июль и август.
#
# Подаётся именно СИРОТА — кейс, не упомянутый ни в одном паттерне. Обобщённый
# кейс дублирует своё правило, и платить за него контекстом дважды незачем.
setup_orphans() {
    setup_home
    local d="$TMP/home/.claude/global-lessons"
    # сирота: ни один паттерн его не упоминает
    cat > "$d/case-2026-08-01-orphan-deploy-lesson.md" <<'KF'
---
name: orphan-deploy-lesson
description: Сирота про деплой, которого нет ни в одном паттерне
type: case
outcome: error
confidence: 3
impact: 5
domain: [devops]
situation: deploying_to_production
trigger: deploy_command
tags: [deploy, rsync, database, exclude]
---
Одинокий урок про деплой.
KF
    # обобщённый: на него ссылается pattern-deploy-safety
    cat > "$d/case-2026-08-02-cited-deploy-lesson.md" <<'KF'
---
name: cited-deploy-lesson
description: Кейс, уже вошедший в паттерн
type: case
outcome: error
confidence: 3
impact: 5
domain: [devops]
situation: deploying_to_production
trigger: deploy_command
tags: [deploy, rsync, database, exclude]
---
Урок, уже обобщённый.
KF
    printf '\nsource_cases: [case-2026-08-02-cited-deploy-lesson]\n' \
        >> "$d/pattern-deploy-safety.md"

    # Ещё три сироты с той же обстановкой и высоким весом. Без них проверка квоты
    # проходит вхолостую: на одном паттерне и одном кейсе вытеснения не случается
    # ни с квотой, ни без неё, и снятие квоты тест не замечает (поймано мутацией).
    # Четыре сироты против одного паттерна — при общей тройке обобщение вылетает.
    local i
    for i in 3 4 5; do
        cat > "$d/case-2026-08-0$i-orphan-extra.md" <<KF
---
name: orphan-extra-$i
description: Ещё одна сирота про деплой
type: case
outcome: error
confidence: 5
impact: 5
domain: [devops]
situation: deploying_to_production
trigger: deploy_command
tags: [deploy, rsync, database, exclude]
---
Сирота номер $i.
KF
    done
}

setup_orphans
OUT_ORPH=$(run_activator '{"session_id":"orph-1","tool_name":"Bash","cwd":"/tmp/proj","tool_input":{"command":"rsync deploy database to production server"}}')
# Проверяется, что подан КАКОЙ-ТО сирота, а не конкретный: слот один, и его берёт
# сирота с наибольшим весом. Фиксировать имя значило бы сторожить исход тай-брейка,
# а не требование «эпизод доходит до контекста».
if grep -qE 'case-2026-08-0[1345]-orphan' <<< "$OUT_ORPH"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL [T13]: ни один кейс-сирота не дошёл до контекста"
fi
if grep -qF "case-2026-08-02-cited-deploy-lesson" <<< "$OUT_ORPH"; then
    FAIL=$((FAIL + 1))
    echo "FAIL [T14]: обобщённый кейс подан — он дублирует свой паттерн"
else
    PASS=$((PASS + 1))
fi
assert_contains "$OUT_ORPH" "pattern-deploy-safety" \
    "T15: обобщение не вытеснено кейсом — квоты раздельные"

# Сирот нет вовсе → хук работает как прежде, без пустых строк в выводе.
setup_home
OUT_NOORPH=$(run_activator "$INPUT_MATCH")
assert_contains "$OUT_NOORPH" "pattern-deploy-safety" \
    "T16: без сирот поведение прежнее"

# === T5: повтор в окне cooldown → подавлено ===
OUT2=$(run_activator "$INPUT_MATCH")
assert_empty "$OUT2" "T5: cooldown подавляет повторное срабатывание"

# === T6: graceful — нет базы знаний → exit 0, пусто ===
setup_home
rm -rf "$TMP/home/.claude/global-lessons"
OUT3=$(run_activator "$INPUT_MATCH")
RC3=$?
assert_eq "0" "$RC3" "T6: нет global-lessons → exit 0 (graceful)"
assert_empty "$OUT3" "T6b: нет global-lessons → пустой вывод"

# === T7: первое срабатывание, секция релевантного знания присутствует ===
setup_home
OUT4=$(run_activator "$INPUT_MATCH")
assert_contains "$OUT4" "Relevant knowledge" "T7: секция 'Relevant knowledge' присутствует"

# === T8: семантический откат MCP при слабом keyword-скоринге (мост L1↔L2) ===
setup_home
STUB="$TMP/stubroot"
mkdir -p "$STUB/mcp-server/.venv/bin"
touch "$STUB/mcp-server/cli_search.py"
cat > "$STUB/mcp-server/.venv/bin/python" <<'PYEOF'
#!/usr/bin/env bash
echo '[{"file_path":"/x/pattern-mcp-hit.md","name":"mcp-hit","type":"pattern","confidence":4,"impact":4}]'
PYEOF
chmod +x "$STUB/mcp-server/.venv/bin/python"
INPUT_NOMATCH='{"session_id":"test-ka-fixed","tool_name":"Bash","cwd":"/tmp/proj","tool_input":{"command":"frobnicate the wibblefitz quux"}}'
OUT5=$(run_activator "$INPUT_NOMATCH" "$STUB")
assert_contains "$OUT5" "mcp-hit" "T8: семантический откат MCP всплывает при слабом keyword-скоринге"

# === D277 (3 сентября 2026): сессия регистрируется по cwd payload, не по каталогу
# процесса. Активатор — единственный из трёх вызывающих sr_register_session, который не
# делает `cd` в payload-каталог (session-start.sh:31 и session-end.sh:29 делают), и
# `cd` здесь и не годится: на $PWD стоят поиск графа доменов (:41) и venv MCP (:930).
# До правки прогон из `/` давал `"project": "/"` — Session Registry приписывал сессию
# каталогу ПРОЦЕССА. Фикстура уводит процесс в `/` и подаёт каталог только полем `cwd`.
setup_home
KA_PROJ="$TMP/ka-proj"
mkdir -p "$KA_PROJ"
printf '# fixture\n' > "$KA_PROJ/CLAUDE.md"
printf '{"session_id":"test-ka-cwd","tool_name":"Bash","cwd":"%s","tool_input":{"command":"rsync deploy database to production server"}}' "$KA_PROJ" \
    | (cd / && env HOME="$TMP/home" CLAUDE_CODE_SESSION_ID="test-ka-cwd" \
        STATE_DIR="$TMP/home/.claude/hooks/state" CLAUDSOUL_ROOT="$REPO_ROOT" \
        bash "$HOOK" >/dev/null 2>&1)
KA_REG=$(jq -r '.project' "$TMP/home/.claude/sessions/active/test-ka-cwd.json" 2>/dev/null)
assert_eq "$KA_PROJ" "$KA_REG" "D277: реестр записал каталог сессии из payload, а не каталог процесса"
# Отрицательный контроль: без `.cwd` регистрация остаётся по каталогу процесса — умолчание
# сохранено намеренно, и без этой пары ассерт выше зеленел бы у версии, игнорирующей $PWD.
printf '{"session_id":"test-ka-nocwd","tool_name":"Bash","tool_input":{"command":"rsync deploy database to production server"}}' \
    | (cd / && env HOME="$TMP/home" CLAUDE_CODE_SESSION_ID="test-ka-nocwd" \
        STATE_DIR="$TMP/home/.claude/hooks/state" CLAUDSOUL_ROOT="$REPO_ROOT" \
        bash "$HOOK" >/dev/null 2>&1)
KA_REG_NO=$(jq -r '.project' "$TMP/home/.claude/sessions/active/test-ka-nocwd.json" 2>/dev/null)
assert_eq "/" "$KA_REG_NO" "D277b: без .cwd в payload — прежнее умолчание на каталог процесса"

echo ""
echo "knowledge-activator tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
