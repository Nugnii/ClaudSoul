#!/usr/bin/env bash
# СУДИТ: hooks/module-context-inject.sh
# test_module_context_inject.sh — тест подачи модуля документации при правке файла.
# Предмет: молчит без индекса и на документации; на описанном файле подаёт ГЛАВНЫЙ модуль
# (тот, где файл в разделе «Файлы») и правила из него; на неописанном — говорит об этом.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/module-context-inject.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

assert_contains()     { if grep -qF "$2" <<< "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет '$2' в '${1:0:180}'"; fi; }
assert_not_contains() { if grep -qF "$2" <<< "$1"; then FAIL=$((FAIL+1)); echo "FAIL [$3]: не ждали '$2'"; else PASS=$((PASS+1)); fi; }
assert_empty()        { if [ -z "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$2]: ждали пусто, '${1:0:100}'"; fi; }

REPO="$TMP/repo"; mkdir -p "$REPO/.claude-docs/modules" "$REPO/lib"
cd "$REPO"; git init -q; git config user.email t@t; git config user.name t
echo "x" > lib/money.ts; echo "y" > lib/orphan.ts

cat > .claude-docs/modules/money.md <<'M'
# Модуль: Деньги
## Файлы
- `lib/money.ts` — расчёт
## Ключевые бизнес-правила
- **Резерв не снимается на паузе** — при паузе выплаты резерв заморожен.
- **Минус разрешён только при списании** — прочие операции его не создают.
M
cat > .claude-docs/modules/mentions.md <<'M'
# Модуль: Упоминания
## Назначение
Тут `lib/money.ts` только упомянут, в разделе «Файлы» его нет.
## Ключевые бизнес-правила
- **Правило-упоминание** — не должно попасть в подачу.
M
cat > .claude-docs/module-index.md <<'M'
# Индекс
- `lib/money.ts` → [money](modules/money.md), [mentions](modules/mentions.md)
- `lib/orphan.ts` → —
M

run() { # $1 state, $2 файл, $3 tool
    printf '{"session_id":"t-%s","tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s/%s"}}' \
        "$1" "${3:-Edit}" "$REPO" "$REPO" "$2" \
        | env STATE_DIR="$TMP/$1" PATHS_LIB="$HOOK_DIR/paths-lib.sh" bash "$HOOK" 2>/dev/null
}

O=$(run s1 lib/money.ts)
assert_contains "$O" "money"                        "T1: назван главный модуль"
assert_contains "$O" "Резерв не снимается на паузе" "T1: подано правило из главного модуля"
assert_contains "$O" "Задет также в: mentions"      "T1: попутное упоминание отделено"
assert_not_contains "$O" "Правило-упоминание"       "T1: правила попутного модуля не подаются"

# Срабатывание — это «контекст ПОДАН протоколом», а не «в выводе встретилось слово».
# T1 читает сырой stdout, и хук, напечатавший тот же текст мимо hookSpecificOutput,
# прошёл бы её молча: подача до агента не дошла бы, а тест остался зелёным.
O7=$(run s7 lib/money.ts)
assert_contains "$O7" '"hookEventName":"PreToolUse"' "T7: контекст подан протоколом PreToolUse"
assert_contains "$O7" '"additionalContext"'          "T7: поле контекста на месте"

assert_empty "$(run s1 lib/money.ts)"   "T2: throttle — второй раз по тому же файлу тихо"
assert_contains "$(run s3 lib/orphan.ts)" "не описывает НИ ОДИН модуль" "T3: неописанный файл назван"
assert_empty "$(run s4 .claude-docs/modules/money.md)" "T4: документацию не комментируем"
assert_empty "$(run s5 lib/money.ts Read)" "T5: чтение не трогаем, только правка"

rm -f .claude-docs/module-index.md
assert_empty "$(run s6 lib/money.ts)"   "T6: без индекса — молчит"

echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
