#!/usr/bin/env bash
# test_adv2_docclaim_regphrase_hits_wrong_hook.sh
# СУДИТ: hooks/tests/test_module_doc_registration_claims.sh
# Объявлено 20 сентября 2026 (D342). Индекс зависимостей связывал этот свидетель с
# `install.sh`, потому что тест кладёт фикстуру с таким именем в свою песочницу —
# прибор выхолащивал НЕ ТОТ файл, и честный свидетель числился ложно-зелёным.
# Предмет установлен по тому, что тест ЗАПУСКАЕТ, а не по упоминанию имени.
#
# АТАКА: у документа, чьё имя не совпадает ни с одним хуком, фраза «Регистрация:» вешается
# на ПЕРВЫЙ хук блока — то самое правило, которое страж объявил ошибочным и заменённым.
#
# Правило объявлено так: событие из фразы «Регистрация:» приписывается хуку, ОДНОИМЁННОМУ
# ДОКУМЕНТУ. `doc_hook()` возвращает пустую строку, если такого хука в регистрации нет, и
# тогда `claims()` молча возвращается к отвергнутому правилу «первый хук блока».
# Модульные доки описывают ПАРЫ («карта зависимостей + страж влияния»), их имена намеренно
# не совпадают с именем хука — на них правило и промахивается.
#
# Вход: док `pair-map.md` описывает два хука. Оба описаны ВЕРНО: alpha на PreToolUse,
# beta на Stop, фраза «Регистрация: Stop» относится к beta.
# Ожидание: расхождений нет, код 0.
# Факт: «pair-map.md: `alpha.sh` — заявлено событие Stop; в install.sh — PreToolUse», код 1.
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
      {"matcher": "Bash", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/alpha.sh"}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [{"type":"command","command":"bash ~/.claude/hooks/beta.sh"}]}
    ]
  }
}'
INST

cat > "$D/pair-map.md" <<'DOC'
# Пара «карта + сверка»

**Файлы.** `hooks/alpha.sh` — строит карту при обращении к оболочке.
`hooks/beta.sh` — сверяет карту в конце хода.
Регистрация: Stop, matcher пуст — сверка идёт по завершении хода
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
echo "--- в install.sh: alpha.sh на PreToolUse[Bash], beta.sh на Stop; док описывает обоих верно ---"

if grep -q 'alpha.sh' <<< "$OUT"; then
    echo "FAIL: страж требует править ВЕРНЫЙ документ: событие Stop из фразы «Регистрация:»"
    echo "      приписано alpha.sh, хотя относится к beta.sh. Адресат должен браться из имени"
    echo "      документа, а имя pair-map хуком не является — сработал отвергнутый запасной путь."
    fail=1
fi
if [ "$RC" -ne 0 ]; then
    echo "FAIL: код возврата $RC на документе, где оба утверждения верны."
    fail=1
fi
echo "песочница осталась: $T"
[ "$fail" -eq 0 ] && echo "PASS: фраза «Регистрация:» не промахивается по хуку"
exit "$fail"
