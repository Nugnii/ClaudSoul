#!/usr/bin/env bash
# probe_D471.sh — «Проверка» пункта D471: `hooks/git-add-sweep-guard.sh` молчит на трёх
# формах, ради которых он и написан.
#   · каталог ЦЕЛИКОМ новый: `git status --porcelain` без `-uall` схлопывает его в строку
#     `brandnew/`, а `--dry-run` называет файлы поимённо — сверка не совпадает ни разу;
#   · имя не-ASCII: `porcelain` при `core.quotePath` (умолчание) отдаёт путь в кавычках с
#     восьмеричными escape, `--dry-run` — как есть; тот же класс, что онемил пять стражей
#     28 августа 2026;
#   · обход `CLAUDSOUL_ALLOW_ADD_SWEEP=1` снимается упоминанием литерала в heredoc, в
#     строке с отступом и в комментарии — закрыто одно написание, не класс.
# Результат: во всех трёх случаях страж СПРАШИВАЕТ и называет захваченные файлы поимённо.
# Проверка результата: bash hooks/tests/fixtures/probe_D471.sh → 0. Сегодня 1 (дефект
#            наблюдён), 2 — рамка не собралась.
#
# Находки противника (Opus, чистый контекст, 20 сентября 2026); здесь они превращены в
# исполнимую пробу. Механизм берётся из CLAUDSOUL_REPO — зелёная сторона подставляет копию.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
G="$MECH/hooks/git-add-sweep-guard.sh"
[ -f "$G" ] || { echo "probe_D471: нет $G" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D471: нет jq — рамка не собралась" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D471: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/docs" || exit 2
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && echo t > docs/tracked.md && git add docs/tracked.md \
  && git -c commit.gpgsign=false commit -qm base ) >/dev/null 2>&1 \
    || { echo "probe_D471: песочница не собралась — рамка не собралась" >&2; exit 2; }

ask() {  # ask <команда> → печатает решение стража
    jq -cn --arg c "$1" --arg d "$R" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
      | bash "$G" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "МОЛЧИТ"' 2>/dev/null
}
why() {
    jq -cn --arg c "$1" --arg d "$R" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
      | bash "$G" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null
}

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ПЕРЕД СУДОМ: на форме, которую страж заведомо ловит, он спрашивает.
echo plain > "$R/docs/plain.ru.md"
[ "$(ask 'git add -A -- docs')" = "ask" ] || {
    echo "probe_D471: контроль — страж молчит на обычном захвате, рамка не собралась" >&2; exit 2; }
rm -f "$R/docs/plain.ru.md"

_bad=0

# 1. Каталог целиком новый.
mkdir -p "$R/brandnew"; echo a > "$R/brandnew/a.md"; echo b > "$R/brandnew/b.md"
if [ "$(ask 'git add brandnew')" != "ask" ]; then
    echo "probe_D471: дефект — каталог ЦЕЛИКОМ новый, страж молчит (уйдут brandnew/a.md, brandnew/b.md)" >&2
    _bad=1
elif ! grep -qF 'brandnew/a.md' <<< "$(why 'git add brandnew')"; then
    echo "probe_D471: дефект — спросил, но файлы нового каталога не названы поимённо" >&2
    _bad=1
fi
rm -rf "$R/brandnew"

# 2. Не-ASCII имя рядом с ASCII-соседом: сосед назван, не-ASCII выпал.
echo x > "$R/docs/second.ru.md"; echo y > "$R/docs/русский.ru.md"
_w=$(why 'git add -A -- docs')
if ! grep -qF 'русский.ru.md' <<< "$_w"; then
    echo "probe_D471: дефект — не-ASCII имя выпало из перечня захвата: $(printf '%s' "$_w" | head -3 | tr '\n' ' ')" >&2
    _bad=1
fi
rm -f "$R/docs/second.ru.md" "$R/docs/русский.ru.md"

# 3. Обход снимается упоминанием литерала не в позиции присваивания.
echo z > "$R/docs/third.ru.md"
for _form in \
    'git add -A -- docs; cat <<EOF
  CLAUDSOUL_ALLOW_ADD_SWEEP=1
EOF' \
    'git add -A -- docs; echo "текст; CLAUDSOUL_ALLOW_ADD_SWEEP=1 конец"' \
    'git add -A -- docs
# комментарий; CLAUDSOUL_ALLOW_ADD_SWEEP=1'
do
    if [ "$(ask "$_form")" != "ask" ]; then
        echo "probe_D471: дефект — обход снят упоминанием литерала: $(printf '%s' "$_form" | tr '\n' ' ' | cut -c1-70)" >&2
        _bad=1
    fi
done
rm -f "$R/docs/third.ru.md"

[ "$_bad" -eq 0 ] || exit 1
exit 0
