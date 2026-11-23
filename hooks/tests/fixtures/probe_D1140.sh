#!/usr/bin/env bash
# СУДИТ: hooks/backlog-vanish-check.sh
# probe_D1140 — существительное «закрытие» рядом с номером заявлением о закрытии не считается, а подсказка о заявленном
# закрытии несёт метки, а не имена переменных. Красная (1), пока «D11: закрытие пункта требует скептика» при открытом D11
# называется «объявленным закрытым» либо подсказка печатает `${BACKLOG_MARK_`. Контроль — «D11 закрыт» назван. Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$R/hooks/backlog-vanish-check.sh"; [ -f "$HOOK" ] && command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
T=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1140.XXXXXX") || exit 2
cd "$T" && git init -q . && git config user.email t@t && git config user.name t || exit 2
printf -- '- ☐ **D11** второй\n' > BACKLOG.md; printf 'архив\n' > BACKLOG-archive.md
git add -A && git commit -qm base || exit 2
msg() { jq -cn --arg c "git commit -m \"$1\"" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null; }
ctl=$(msg 'chore(backlog): D11 закрыт удалением дубля')
grep -q 'объявлен закрытым' <<< "$ctl" || exit 2
grep -qF '${BACKLOG_MARK_' <<< "$ctl" && { echo "подсказка печатает имена переменных вместо меток" >&2; exit 1; }
grep -q 'объявлен закрытым' <<< "$(msg 'docs(долг): D11: закрытие пункта требует скептика')" \
    && { echo "существительное «закрытие» прочитано заявлением" >&2; exit 1; }
grep -q 'объявлен закрытым' <<< "$(msg 'docs(долг): закрытие D11 требует скептика')" \
    && { echo "«закрытие D11 …» прочитано заявлением" >&2; exit 1; }
echo "заявление о закрытии — глагол, а не существительное; метки в подсказке — знаками"
exit 0
