#!/usr/bin/env bash
# test_guards_provable.sh — мета-тест: страж, чьё срабатывание никогда не доказано,
# не считается стражем.
#
# Зачем. За четыре релиза подряд (v1.12.0-v1.12.3) проверка молчала по неверной
# причине, и каждый раз на её молчание ссылались как на факт:
#   v1.12.0 — метрика считала строки лога сессиями, «0% принятия» было артефактом;
#   v1.12.1 — страж загорался ровно при СОБЛЮДЕНИИ контракта, то есть всегда;
#   v1.12.2 — страж проверял присутствие файла в коммите вместо содержания;
#   v1.12.3 — та же проверка спрашивала только с README, план и архитектуру пропускала.
#
# Общее у всех четырёх: результат проверки был структурно независим от того, что
# она якобы проверяла. Молчание неотличимо от «проверил и чисто» ровно до тех пор,
# пока не показано, что эта проверка вообще СПОСОБНА загореться.
#
# Отсюда правило, вынесенное из текста в механизм: у каждого хука, который что-то
# инжектит или спрашивает (`additionalContext` / `permissionDecision`), обязан быть
# тест, и в нём обязано быть утверждение о СРАБАТЫВАНИИ — не только о тишине.
# Тест из одних `assert_empty` доказывает лишь, что хук молчит; он молчал бы и будучи
# пустым файлом.
#
# Чего этот тест НЕ гарантирует — важно, чтобы не переоценить его так же, как
# переоценивали предыдущие. Он не ловит случай, когда утверждение о срабатывании
# есть, но фикстура не соответствует живым данным: ровно так прошли v1.12.1
# (фикстура «complete» ставила `- [x]`, чего нет ни в одном реальном скилле) и
# v1.12.2. Против этого класса — `test_guards_live.sh`, прогон по настоящему дереву.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$TESTS_DIR/.." && pwd)"

PASS=0
FAIL=0
FAILED=()

# Словарь утверждений. Собран по живым тестам, а не придуман: первая версия знала
# только `assert_contains`/`assert_empty` и дала четыре ложных срабатывания —
# `assert_nonsilent`, `ok`/`no` и прочие локальные хелперы она не видела. Мета-тест,
# судящий о смысле по имени функции, — сам проверка со слабой связью с предметом,
# поэтому словарь расширяемый и намеренно не считает неоднозначные (`assert_rc`:
# код возврата не говорит, был вывод или нет).
FIRE_PATTERNS='assert_contains|assert_fires|assert_not_empty|assert_nonsilent|assert_output|^ok[[:space:]]|ok\('
SILENT_PATTERNS='assert_empty|assert_silent|assert_not_contains|assert_no_output|^no[[:space:]]|no\('

for hook in "$HOOKS_DIR"/*.sh; do
    base=$(basename "${hook%.sh}")
    case "$base" in *-lib) continue ;; esac

    # Страж = хук, который что-то говорит наружу. Строку ищем в КОДЕ, не в
    # комментариях: первая версия ловила `pre-compact-finalizer` по его же
    # комментарию «Silent: no systemMessage, no additionalContext» — то есть по
    # фразе, утверждающей обратное. Детектор, читающий комментарии как код,
    # измеряет текст о предмете, а не предмет.
    grep -vE '^[[:space:]]*#' "$hook" 2>/dev/null \
        | grep -q 'additionalContext\|permissionDecision' || continue

    # Свой тест. Сначала по соглашению об имени (`test_<hook>.sh` с подчёркиваниями) —
    # grep-угадывание брало ПЕРВЫЙ файл, упомянувший имя хука, и для session-collector
    # подсунуло чужой `test_disagreement_loop.sh`, где он лишь упоминается.
    conv="$TESTS_DIR/test_$(printf '%s' "$base" | tr '-' '_').sh"
    if [ -f "$conv" ]; then
        test_files="$conv"
    else
        test_files=$(grep -l -- "$base" "$TESTS_DIR"/test_*.sh 2>/dev/null | grep -v "test_guards_provable.sh" || true)
    fi

    if [ -z "$test_files" ]; then
        FAIL=$((FAIL + 1))
        FAILED+=("$base — теста нет вообще; его молчание ничего не значит")
        continue
    fi

    fire=0
    silent=0
    while IFS= read -r tf; do
        [ -n "$tf" ] || continue
        n=$(grep -cE "$FIRE_PATTERNS" "$tf" 2>/dev/null | head -1)
        fire=$((fire + ${n:-0}))
        n=$(grep -cE "$SILENT_PATTERNS" "$tf" 2>/dev/null | head -1)
        silent=$((silent + ${n:-0}))
    done <<EOF
$test_files
EOF

    if [ "$fire" -eq 0 ]; then
        FAIL=$((FAIL + 1))
        FAILED+=("$base — тест есть, но проверок срабатывания в нём нет (только тишина): пустой файл прошёл бы так же")
        continue
    fi
    if [ "$silent" -eq 0 ]; then
        FAIL=$((FAIL + 1))
        FAILED+=("$base — есть проверка срабатывания, но нет проверки тишины: страж, который горит всегда, тоже бесполезен (v1.12.1)")
        continue
    fi
    PASS=$((PASS + 1))
done

echo ""
echo "=================================="
echo "guards-provable: $PASS доказано, $FAIL без доказательства"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    for f in "${FAILED[@]}"; do echo "  ✗ $f"; done
fi
echo "=================================="
[ "$FAIL" -eq 0 ]
