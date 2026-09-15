#!/usr/bin/env bash
# test_timestamp_canary_check.sh — Stop-страж канарейки: молчит на здоровом
# ответе, алертит при пропаже/протухании таймштампа. Фикстурный транскрипт.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Путь стража переопределяется РАДИ МУТАЦИИ: зелень ног не доказывает ничего, пока они не
# покраснели на прежней редакции. Образец — test_drift_check.sh.
SCRIPT="${CANARY_SCRIPT:-$HOOKS_DIR/timestamp-canary-check.sh}"

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT not found"; exit 1; }

PASS=0
FAIL=0
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -Fq "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: '$needle' not in: $haystack"; fi
}
assert_empty() {
    local actual="$1" label="$2"
    if [ -z "$actual" ] || [ "$actual" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: expected empty, got: $actual"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Изоляция от живого маркера фазы: без него фазовая проверка молчит (T1-T8),
# фазные случаи (T9+) кладут фикстурный маркер сюда.
export ABLATION_DIR="$TMP/abl"
mkdir -p "$ABLATION_DIR"

# mktemp, не счётчик: вызов идёт через $(...), инкремент в подоболочке терялся,
# и все фикстуры молча писались в один файл (латентно с рождения теста).
make_transcript() {
    local f
    f=$(mktemp "$TMP/transcript-XXXXXX")
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    jq -nc --arg t "$1" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    printf '%s' "$f"
}


# Фикстура ДЛИННОГО ХОДА: инжект → шапка → ЕЩЁ инжект → продолжение без шапки.
# Форма взята из мира: замер 7 сентября 2026 показал в одном ходе ПЯТЬ инжектов и две
# шапки — инжекты приходят на каждом обращении к инструментам, а не раз на ход.
make_transcript_two_injects() { # $1 = ранний инжект (совпадает с шапкой), $2 = поздний, $3 = шапка, $4 = продолжение
    local f
    f=$(mktemp "$TMP/transcript-XXXXXX")
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    jq -nc --arg c "🕐 $1 — начни ответ этим таймштампом (канарейка контекста)" \
        '{type:"attachment", attachment:{type:"hook_additional_context",
          hookName:"UserPromptSubmit", content:[$c]}}' >> "$f"
    jq -nc --arg t "$3" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    jq -nc --arg c "🕐 $2 — начни ответ этим таймштампом (канарейка контекста)" \
        '{type:"attachment", attachment:{type:"hook_additional_context",
          hookName:"UserPromptSubmit", content:[$c]}}' >> "$f"
    jq -nc --arg t "$4" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    printf '%s' "$f"
}

# session_id уникален на фикстуру (basename транскрипта): маркер «уже алертили»
# ключуется сессией, общий id глушил бы алерты соседних тестов.
run_with() {
    printf '{"session_id":"sid-%s","transcript_path":"%s"}' "$(basename "$1")" "$1" | \
        CANARY_STATE_DIR="$TMP/state" \
        TIMESTAMP_INJECT_PATH="${2:-$HOOKS_DIR/timestamp-inject.sh}" bash "$SCRIPT" 2>/dev/null
}

NOW_TS=$(date '+%Y-%m-%d %H:%M')

# Транскрипт с инжектом: user → attachment(hook_additional_context) → assistant.
make_transcript_injected() { # $1 = значение инжекта, $2 = текст ответа
    local f
    f=$(mktemp "$TMP/transcript-XXXXXX")
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    jq -nc --arg c "🕐 $1 — начни ответ этим таймштампом (канарейка контекста)" \
        '{type:"attachment", attachment:{type:"hook_additional_context",
          hookName:"UserPromptSubmit", content:[$c]}}' >> "$f"
    jq -nc --arg t "$2" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    printf '%s' "$f"
}

# То же, но несколько реплик после одного инжекта: продолжение хода.
make_transcript_injected_multi() { # $1 = инжект, далее — тексты реплик
    local f inj t
    f=$(mktemp "$TMP/transcript-XXXXXX")
    inj="$1"; shift
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    jq -nc --arg c "🕐 $inj — начни ответ этим таймштампом (канарейка контекста)" \
        '{type:"attachment", attachment:{type:"hook_additional_context",
          hookName:"UserPromptSubmit", content:[$c]}}' >> "$f"
    for t in "$@"; do
        jq -nc --arg t "$t" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    done
    printf '%s' "$f"
}


# --- T1: ответ начат свежим таймштампом → молчит ---
F=$(make_transcript "🕐 $NOW_TS CEST

Готово, тесты зелёные.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T1: здоровый ответ — тишина"

# --- T1b: шапка в markdown-выделении — та же шапка, канарейка жива ---
# Повод (6 сентября 2026): страж дважды подряд объявил уплывание контекста на ответах,
# которые НАЧИНАЛИСЬ таймштампом — но в форме `**🕐 … **`. Признак требовал даты сразу
# после необязательного значка, а строка начиналась со звёздочек markdown. Ложная тревога
# у канарейки дороже обычной: она учит не читать ровно тот сигнал, ради которого страж
# поставлен. Комментарий самого стража это и предвосхищал: «значок 🕐 необязателен —
# канарейка ловит уплывание контекста, а не дисциплину»; выделение туда же.
F=$(make_transcript_injected "$NOW_TS CEST" "**🕐 $NOW_TS CEST**

Готово, тесты зелёные.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T1b: шапка в ** ** — тишина"

# --- T1c: одиночная звёздочка и подчёркивание — те же формы выделения ---
F=$(make_transcript_injected "$NOW_TS CEST" "*🕐 $NOW_TS CEST*

Готово.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T1c: шапка в * * — тишина"

# --- T1d: выделение НЕ заменяет дату: звёздочки без таймштампа — по-прежнему пропажа ---
# Ключевая нога: расширение признака не имеет права ослабить канарейку.
F=$(make_transcript_injected "$NOW_TS CEST" "**Готово, тесты зелёные.**

Коммит создан.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T1d: выделение без даты — пропажа, как и было"

# --- T1e: многоблочный ход, шапка в markdown только в ПЕРВОМ блоке ---
# Эта нога покрывает jq-половину признака, и без неё она не покрыта ничем: мутация
# «откатить is_header» на одноблочных фикстурах проходит незамеченной (34/34), потому что
# при отсутствии распознанной шапки jq берёт первый блок — а он же и единственный. Разница
# видна только там, где блоков несколько и последний шапки не несёт: именно так выглядит
# обычный ход агента с вызовами инструментов между репликами.
F=$(make_transcript_injected_multi "$NOW_TS CEST" "**🕐 $NOW_TS CEST**

Смотрю детектор." "Готово, тесты зелёные.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T1e: многоблочный ход, шапка в ** ** в первом блоке — тишина"

# --- T1f: шапка в markdown НЕ в первом блоке ---
# Единственный случай, где решает jq-половина признака: страж по замыслу берёт ПОСЛЕДНЮЮ
# выданную шапку (см. комментарий у head_line), а при нераспознанной шапке падает обратно
# на первый блок. Пока шапка совпадала с первым блоком, fallback давал тот же ответ, и
# мутация «откатить is_header» проходила незамеченной на всех прочих ногах.
F=$(make_transcript_injected_multi "$NOW_TS CEST" "Смотрю детектор." "**🕐 $NOW_TS CEST**

Готово, тесты зелёные.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T1f: шапка в ** ** во втором блоке — тишина (решает jq-половина)"

# --- T2: ответ без таймштампа → алерт с systemMessage ---
F=$(make_transcript_injected "$NOW_TS CEST" "Готово, тесты зелёные, коммит создан.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T2: пропажа детектирована"
assert_contains "$OUT" "additionalContext" "T2b: алерт доходит до агента (канал systemMessage снят 12 сентября 2026 — у владельца он рендерился построчно, а канарейка правит поведение агента)"

# --- T3: протухший таймштамп (сутки назад) → алерт ---
STALE=$(date -v-1d '+%Y-%m-%d %H:%M' 2>/dev/null || date -d 'yesterday' '+%Y-%m-%d %H:%M' 2>/dev/null)
F=$(make_transcript "🕐 $STALE CEST

Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "протухло" "T3: свежесть проверяется"

# --- T4: таймштамп не в первой строке → алерт (правило: НАЧИНАТЬ с него) ---
F=$(make_transcript_injected "$NOW_TS CEST" "Готово.

🕐 $NOW_TS CEST")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T4: таймштамп не в начале = пропажа"

# --- T5: механизм инжекта не задеплоен → тишина (другой класс проблемы) ---
F=$(make_transcript "Готово без таймштампа.")
OUT=$(run_with "$F" "$TMP/no-such-injector.sh")
assert_empty "$OUT" "T5: без инжектора страж молчит"

# --- T6: нет transcript_path → тихий выход ---
OUT=$(printf '{"session_id":"sid"}' | bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T6: без транскрипта тихий выход"

# --- T7/T8: ход с промежуточными репликами перед tool-вызовами ---
# Контракт c71af66: граница хода — реплика СОБЕСЕДНИКА; таймштамп обязан
# стоять в ПЕРВОМ текстовом блоке хода (шапка ответа) — так его видит
# владелец, прокручивая диалог сверху.
make_transcript_multi() {
    local f
    f=$(mktemp "$TMP/transcript-XXXXXX")
    printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$f"
    local t
    for t in "$@"; do
        jq -nc --arg t "$t" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$f"
    done
    printf '%s' "$f"
}

F=$(make_transcript_injected_multi "$NOW_TS CEST" "Смотрю детектор." "Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T7: ни одного блока с шапкой — пропажа"

F=$(make_transcript_multi "🕐 $NOW_TS CEST

Смотрю детектор." "Готово.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T8: таймштамп в первом блоке — тишина, финал без него легален"

# --- T11: цепочка ходов, запущенных хуком, без реплики владельца ---
# Регрессия 2026-08-09: Stop-хук запускает следующий ход сам, поэтому граница
# «последняя реплика владельца» не двигается, и проверка первого блока цепочки
# упиралась в ответ, который уже не изменить, — 6 ложных алертов подряд.
# Отличить «продолжение ответа» от «нового хода» в транскрипте нельзя:
# last-prompt пишется и внутри хода, а два текстовых блока подряд дают обе
# ситуации одинаково. Поэтому проверяется последняя выданная шапка.
F=$(make_transcript_multi "🕐 2000-01-01 00:00 CEST

Старый ответ без сегмента." "🕐 $NOW_TS CEST

Свежий ответ.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T11: свежая шапка в последнем ответе цепочки — тишина"

# --- T9/T10: сегмент фазы в шапке при активной фазе (amendment phase-3) ---
printf '{"phase":"phase-x","tag":"t","since":"2026-08-09T00:00:00Z"}' > "$ABLATION_DIR/active-phase.json"
F=$(make_transcript "🕐 $NOW_TS CEST · 🧪 phase-x · очередь 0/20

Готово.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T9: шапка с сегментом фазы — тишина"
F=$(make_transcript "🕐 $NOW_TS CEST

Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "без сегмента фазы" "T10: фаза активна, сегмента нет — алерт"
rm -f "$ABLATION_DIR/active-phase.json"

# --- T12/T13: самозацикливание — один алерт на ход владельца ---
# Регрессия 2026-08-15: алерт продолжает ход (харнесс ре-инвокает модель на
# additionalContext), продолжение по построению без свежего инжекта → снова нет
# шапки → алерт на каждом Stop («Без изменений» × N). Маркер глушит повтор,
# новая реплика владельца взводит канарейку заново.
F=$(make_transcript_injected_multi "$NOW_TS CEST" "Ответ без шапки." "Без изменений.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T12: первый Stop хода — алерт"
OUT=$(run_with "$F")
assert_empty "$OUT" "T12b: повторный Stop того же хода — тишина"

printf '{"message":{"role":"user","content":[{"type":"text","text":"ещё вопрос"}]}}\n' >> "$F"
printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Снова без шапки."}]}}\n' >> "$F"
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T13: новая реплика владельца — алерт снова"

# --- T14: stop_hook_active — ход уже продолжен Stop-хуком, тихий выход ---
F=$(make_transcript "Без шапки.")
OUT=$(printf '{"session_id":"sid-%s","transcript_path":"%s","stop_hook_active":true}' "$(basename "$F")" "$F" | \
    CANARY_STATE_DIR="$TMP/state" TIMESTAMP_INJECT_PATH="$HOOKS_DIR/timestamp-inject.sh" bash "$SCRIPT" 2>/dev/null)
assert_empty "$OUT" "T14: stop_hook_active=true — страж молчит"

# --- T15: отладочного журнала НЕТ — ни после алерта, ни после здорового ответа (D383, корень R2) ---
# Прежде здесь проверялось, что alert ДОПИСЫВАЕТ canary-debug.jsonl. Запись снята 13 сентября
# 2026: читателей у журнала не было, а всё записанное выводится прогоном стража по транскрипту.
# Алерт-кейсы выше уже отработали в том же $TMP/state — файла не должно быть и после них.
DBG="$TMP/state/canary-debug.jsonl"
F=$(make_transcript_injected "$NOW_TS CEST" "Ответ без шапки для проверки отсутствия журнала.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T15: alert сработал"
if [ ! -e "$DBG" ]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T15b]: canary-debug.jsonl появился — запись снята 13 сентября 2026 (D383)"; fi

# --- T16: здоровый ответ (с шапкой) — тихо ---
F=$(make_transcript "🕐 $NOW_TS CEST

Ответ со свежей шапкой.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T16: здоровый ответ — тихо"

# ---------------------------------------------------------------------------
# Сверка ЗНАЧЕНИЯ шапки с инжектом (2026-08-26). До неё страж проверял только
# форму первой строки и свежесть ±6ч — выдуманный, но правильно оформленный
# таймштамп проходил молча.
# ---------------------------------------------------------------------------

# --- T17: шапка совпадает с инжектом → тишина ---
F=$(make_transcript_injected "$NOW_TS CEST" "🕐 $NOW_TS CEST

Готово.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T17: точное эхо — тихо"

# --- T18: шапка правильной ФОРМЫ, но другое значение → алерт ---
# Ровно тот промах, ради которого сверка и заводилась: 14:47 при инжекте 14:12.
OTHER=$(date -v+35M '+%Y-%m-%d %H:%M' 2>/dev/null || date -d '+35 minutes' '+%Y-%m-%d %H:%M' 2>/dev/null)
F=$(make_transcript_injected "$NOW_TS CEST" "🕐 $OTHER CEST

Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "не совпадает с инжектом" "T18: выдуманное значение поймано"
assert_contains "$OUT" "$NOW_TS" "T18b: инжект назван в алерте"
assert_contains "$OUT" "$OTHER" "T18c: шапка названа в алерте"

# --- T19: инжект старый, но эхо точное → тишина (длинный ход не нарушение) ---
# Проверка свежести здесь НЕ применяется: контракт — эхо, а не близость к часам.
OLD=$(date -v-10H '+%Y-%m-%d %H:%M' 2>/dev/null || date -d '-10 hours' '+%Y-%m-%d %H:%M' 2>/dev/null)
F=$(make_transcript_injected "$OLD CEST" "🕐 $OLD CEST

Готово после долгого хода.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T19: точное эхо старого инжекта — тихо"

# --- T20: несколько инжектов → эталон последний ---
F=$(mktemp "$TMP/transcript-XXXXXX")
printf '{"message":{"role":"user","content":[{"type":"text","text":"первый"}]}}\n' > "$F"
jq -nc --arg c "🕐 $OLD CEST — начни ответ этим таймштампом (канарейка контекста)" \
    '{type:"attachment", attachment:{type:"hook_additional_context", content:[$c]}}' >> "$F"
jq -nc --arg c "🕐 $NOW_TS CEST — начни ответ этим таймштампом (канарейка контекста)" \
    '{type:"attachment", attachment:{type:"hook_additional_context", content:[$c]}}' >> "$F"
jq -nc --arg t "🕐 $NOW_TS CEST

Готово." '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$F"
OUT=$(run_with "$F")
assert_empty "$OUT" "T20: эталон — последний инжект, не первый"

# --- T21: инжект есть, шапки нет → прежний алерт о пропаже, не о расхождении ---
F=$(make_transcript_injected "$NOW_TS CEST" "Готово без шапки.")
OUT=$(run_with "$F")
assert_contains "$OUT" "БЕЗ таймштампа" "T21: пропажа важнее расхождения"

# --- T22: без инжекта в транскрипте — откат на проверку свежести ---
# Отсутствие данных не должно превращаться в алерт: старый формат, чужой харнесс.
F=$(make_transcript "🕐 $NOW_TS CEST

Готово.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T22: нет инжекта + свежая шапка — тихо"
F=$(make_transcript "🕐 $OLD CEST

Готово.")
OUT=$(run_with "$F")
assert_contains "$OUT" "отстаёт от часов" "T22b: нет инжекта + шапка 10ч назад → прежний алерт о протухании"
assert_contains "$OUT" "6 часов" "T22c: сработала именно откатная ветка, не сверка значения"

# --- T23: инжекта в окне НЕТ, шапки нет → тишина -----------------------------------
# Правило гласит «нет инжекта — нет таймштампа»: отсутствие шапки здесь верно, а не
# признак уплывания. До 28 августа 2026 страж утверждал «при живом инжекте», ни разу
# не проверив вторую половину утверждения: признак строился по форме ОТВЕТА, а вывод
# делался об ИСТОЧНИКЕ. После сжатия контекста инжект отсутствовал 470 строк подряд, и
# страж всё это время требовал перезапускать живую сессию. Сломанный инжектор — другой
# класс задачи: чинится хук, а не сессия.
F=$(make_transcript "Готово, шапки нет, инжекта тоже не было.")
OUT=$(run_with "$F")
assert_empty "$OUT" "T23: без инжекта отсутствие шапки — не уплывание"

# --- T37: ДЛИННЫЙ ХОД — шапка сверяется с инжектом, действовавшим НА ЕЁ МОМЕНТ ---
# Повод и положительный контроль правки 7 сентября 2026. До неё бралось `| last` по всему
# транскрипту: шапка, верная в момент написания, сравнивалась с инжектом, пришедшим позже,
# и страж объявлял уплывание. Ложных 2 из 2 на ходах с двумя и более инжектами; оба входа
# при этом ВЕРНЫ по отдельности — неверен был их отбор.
EARLY="2026-09-07 18:56"
LATE="2026-09-07 19:15"
F37=$(make_transcript_two_injects "$EARLY" "$LATE" "🕐 $EARLY CEST — ответ" "продолжение без шапки")
OUT=$(run_with "$F37")
assert_empty "$OUT" "T37: длинный ход — верная шапка не объявляется уплыванием"

# --- T37b: ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ — выдуманное значение всё ещё ловится ---
# Иначе правка была бы не сужением области, а ослеплением стража.
F37b=$(make_transcript_two_injects "$EARLY" "$LATE" "🕐 2026-09-07 03:03 CEST — ответ" "продолжение")
OUT=$(run_with "$F37b")
assert_contains "$OUT" "не совпадает" "T37b: выдуманная шапка ловится и в длинном ходе"

# --- T37c: КОНТРПРИМЕР — шапка позже ОБОИХ инжектов сверяется с поздним ---
# Правка не должна привязать шапку к первому инжекту навсегда: сверять надо с последним
# ДО неё, а не с первым в ходе.
F37c=$(mktemp "$TMP/transcript-XXXXXX")
printf '{"message":{"role":"user","content":[{"type":"text","text":"вопрос"}]}}\n' > "$F37c"
jq -nc --arg c "🕐 $EARLY — инжект" '{type:"attachment", attachment:{type:"hook_additional_context",
  hookName:"UserPromptSubmit", content:[$c]}}' >> "$F37c"
jq -nc --arg c "🕐 $LATE — инжект" '{type:"attachment", attachment:{type:"hook_additional_context",
  hookName:"UserPromptSubmit", content:[$c]}}' >> "$F37c"
jq -nc --arg t "🕐 $LATE CEST — ответ" '{"message":{"role":"assistant","content":[{"type":"text","text":$t}]}}' >> "$F37c"
OUT=$(run_with "$F37c")
assert_empty "$OUT" "T37c: шапка после обоих инжектов сверяется с поздним, а не с первым"

# --- T12-T14: ЧИСЛО шапок за ход (8 сентября 2026) ---
# Причина выдуманных значений не в невнимательности, а в количестве: инжект один на ход, и
# для второй, сотой шапки времени взять неоткуда. Замер: 254 шапки за 4 хода, 220 различных
# значений. Порог оценочный (законная цепочка Stop-хука неотличима от дефекта в транскрипте),
# и ноги держат ОБЕ его стороны — иначе он подгонка под один случай.
F=$(make_transcript_multi \
    "🕐 $NOW_TS CEST" "🕐 $NOW_TS CEST" "🕐 $NOW_TS CEST" \
    "🕐 $NOW_TS CEST" "🕐 $NOW_TS CEST" "🕐 $NOW_TS CEST")
OUT=$(run_with "$F")
if grep -qF "шапок с таймштампом" <<< "$OUT"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T12: шесть шапок за ход — алерта нет]"; fi

# КОНТРПРИМЕР: цепочка из трёх ходов хука, каждый со своей шапкой — предписанная форма.
F=$(make_transcript_multi "🕐 $NOW_TS CEST" "🕐 $NOW_TS CEST" "🕐 $NOW_TS CEST")
OUT=$(run_with "$F")
if grep -qF "шапок с таймштампом" <<< "$OUT"; then
    FAIL=$((FAIL + 1)); echo "FAIL [T13: три шапки объявлены дефектом — порог придавил законную цепочку]"
else PASS=$((PASS + 1)); fi

# Порог настраивается: при пределе 2 те же три шапки обязаны стать находкой. Без этой ноги
# зелень T13 не отличалась бы от «проверка вообще не работает».
F=$(make_transcript_multi "🕐 $NOW_TS CEST" "🕐 $NOW_TS CEST" "🕐 $NOW_TS CEST")
OUT=$(CANARY_MAX_HEADERS=2 run_with "$F")
if grep -qF "шапок с таймштампом" <<< "$OUT"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T14: порог CANARY_MAX_HEADERS не действует]"; fi

echo "test_timestamp_canary_check: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
