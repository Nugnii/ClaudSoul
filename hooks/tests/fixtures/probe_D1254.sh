#!/usr/bin/env bash
set -u
# СУДИТ: hooks/command-scope-lib.sh
# probe_D1254 — сканер исполняемой части (`executable_part`, `hooks/command-scope-lib.sh`) разбирает подстановку обратной
#   кавычкой так, как bash: комментарий внутри неё кончается на закрывающей кавычке, а `\`` внутри неё — вложенная
#   подстановка. Вердикт `is_git_commit`:
#   (1) `` x=`echo a # c` ; git commit -q -m t `` — коммит (bash его запускает);
#   (2) `` x=`echo "\`git commit -q -m t\`"` `` — коммит (вложенная подстановка исполняется);
#   (к) `` x=`echo a # git commit -q -m t` `` — НЕ коммит: `git commit` в комментарии (отрицательный контроль).
# Код: 0 — все три совпали с bash; 1 — нет (названо); 2 — нет предмета.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
L="$R/hooks/command-scope-lib.sh"
[ -f "$L" ] || exit 2
# shellcheck source=/dev/null
. "$L" 2>/dev/null || exit 2
command -v is_git_commit >/dev/null 2>&1 || exit 2
v() { is_git_commit "$1" && echo yes || echo no; }
miss=""
[ "$(v 'x=`echo a # c` ; git commit -q -m t')" = yes ] || miss="$miss (1) коммит за комментарием в обратных кавычках не виден;"
[ "$(v 'x=`echo "\`git commit -q -m t\`"`')" = yes ] || miss="$miss (2) вложенная подстановка \\\` не видна;"
[ "$(v 'x=`echo a # git commit -q -m t`')" = no ] || miss="$miss (к) коммит из комментария принят за исполняемый;"
[ -z "$miss" ] && { echo "обе формы — коммит, комментарий — нет"; exit 0; }
echo "не держится:$miss"
exit 1
