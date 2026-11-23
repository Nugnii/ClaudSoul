#!/usr/bin/env bash
# test_adv2_docclaim_empty_matcher_false_alarm.sh
# СУДИТ: hooks/tests/test_module_doc_registration_claims.sh
# Объявлено 20 сентября 2026 (D342). Индекс зависимостей связывал этот свидетель с
# `install.sh`, потому что тест кладёт фикстуру с таким именем в свою песочницу —
# прибор выхолащивал НЕ ТОТ файл, и честный свидетель числился ложно-зелёным.
# Предмет установлен по тому, что тест ЗАПУСКАЕТ, а не по упоминанию имени.
#
# АТАКА: хук, зарегистрированный на одном событии ДВАЖДЫ — с matcher и без него, — сверяется
# только по первому: `matchers_of()` отбрасывает пустой matcher (`if e == event and m`).
# Пустой matcher означает «на всех инструментах», то есть самый широкий случай выпадает из
# сверки, и верное утверждение дока объявляется расхождением.
#
# Аддитивное слияние install.sh умеет ДОБАВЛЯТЬ записи и не умеет удалять — шапка пары
# «регистрация хуков» в drift-check описывает ровно этот механизм на живом примере
# (`error-tracker` оказался зарегистрирован на двух событиях сразу). Две записи одного хука
# на одном событии — та же форма.
#
# Вход: alpha.sh висит на PreToolUse дважды: matcher "Bash" и matcher "" (все инструменты).
# Док пишет `PreToolUse[Read]` — и это ПРАВДА: вторая запись срабатывает на Read.
# Ожидание: расхождений нет, код 0.
# Факт: «заявлено matcher PreToolUse[Read]; в install.sh — PreToolUse[Bash]», код 1.
set -uo pipefail

REAL_REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REAL_REPO/hooks/tests/test_module_doc_registration_claims.sh"
[ -f "$GUARD" ] || { echo "FAIL: нет $GUARD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

T=$(mktemp -d)
R="$T/repo"; D="$R/.claude-docs/modules"
mkdir -p "$R/hooks/tests" "$D"
cp "$GUARD" "$R/hooks/tests/"

cat > "$R/install.sh" <<'INST'
#!/bin/bash
HOOKS_CONFIG='{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]},
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}
    ]
  }
}'
INST

cat > "$D/alpha.md" <<'DOC'
# alpha

**Файлы.** `hooks/alpha.sh` — считает прочитанное (PreToolUse[Read]).
DOC

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ (D342, 20 сентября 2026): судимый страж обязан покраснеть на
# ИЗВЕСТНОМ нарушении. Без него свидетель зеленел и на живом страже, и на выхолощенном до
# `:` — замер того дня дал 0/0 у всех четверых этой группы. Причина в устройстве, а не в
# написании вердикта: свидетель класса «ложная тревога» судит МОЛЧАНИЕ судимого, а молчание
# и есть то, что производит мёртвый механизм. Обратная форма вердикта (`RC -eq 0 → PASS`
# против `RC -ne 0 → FAIL`) на это не влияет — оба написания были зелены.
# Владелец контроля один на дерево: `frame_require_red` в `hooks/frame-control-lib.sh`.
. "$REAL_REPO/hooks/frame-control-lib.sh"
printf '# zzz\n\n**Файлы.** `hooks/zzz.sh` — подставной (PostToolUse[Write]).\n' \
    > "$R/.claude-docs/modules/zzz.md"
frame_require_red "док заявляет незарегистрированный hooks/zzz.sh" \
    bash "$R/hooks/tests/test_module_doc_registration_claims.sh" || exit $?
rm -f "$R/.claude-docs/modules/zzz.md"

OUT=$(bash "$R/hooks/tests/test_module_doc_registration_claims.sh" 2>&1); RC=$?

fail=0
echo "--- вывод стража (код $RC) ---"; printf '%s\n' "$OUT"
echo "--- в install.sh alpha.sh стоит на PreToolUse дважды: matcher \"Bash\" и matcher \"\" ---"

if grep -q 'matcher PreToolUse' <<< "$OUT"; then
    echo "FAIL: страж требует править ВЕРНЫЙ документ. Вторая запись — пустой matcher, то есть"
    echo "      все инструменты, Read в их числе: хук на Read срабатывает. Пустой matcher"
    echo "      выброшен из сверки условием if e == event and m, и самый широкий случай невидим."
    fail=1
fi
if [ "$RC" -ne 0 ]; then
    echo "FAIL: код возврата $RC на верном утверждении."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: пустой matcher учитывается при сверке"
exit "$fail"
