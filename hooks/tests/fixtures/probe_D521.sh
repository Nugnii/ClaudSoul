#!/usr/bin/env bash
# СУДИТ: hooks/declared-problem-recorded.sh
# probe_D521.sh — «находка записана не в тот носитель» судит по ЗАПИСАННОМУ пункту, а не по
# тексту ответа (D521).
#
# `dpr_foreign_carrier` искал признаки ClaudSoul в последнем тексте ответа: сессия чужого проекта,
# упомянувшая ClaudSoul мимоходом («страж ClaudSoul отказал»), получала тревогу за пункт о своём
# коде, а пункт о хуке ClaudSoul при ответе без этого слова проходил молча. Предмет — строки,
# добавленные в бэклог проекта.
#
# Функция берётся из самого хука (копия разошлась бы молча); paths-lib подключается, чтобы у неё
# был `project_git` — бэклог лежит в чужой папке. Контроль: пункт о хуке ClaudSoul при ответе со
# словом ClaudSoul — «чужой носитель»; иначе код 2.
# Код: 0 — вердикт по пункту; 1 — по тексту ответа; 2 — проба не исполнима либо контроль мёртв.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SUT="$REPO/hooks/declared-problem-recorded.sh"
[ -f "$SUT" ] || { echo "проба не исполнима: нет hooks/declared-problem-recorded.sh в $REPO"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "проба не исполнима: нет git"; exit 2; }

W=$(mktemp -d "${HOME}/.probeD521.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
sed -n '/^dpr_foreign_carrier()/,/^}/p' "$SUT" > "$W/fn.sh"
[ -s "$W/fn.sh" ] || { echo "проба не исполнима: в хуке нет dpr_foreign_carrier"; exit 2; }
mkdir -p "$W/cs"
printf 'страж ClaudSoul отказал на коммите; поправил src/app.ts, тесты зелёные\n' > "$W/say_cs.txt"
printf 'поправил src/app.ts, тесты зелёные\n' > "$W/say_own.txt"

_proj() {   # <каталог> <строка пункта> — проект с бэклогом и пунктом, добавленным в ходе (не закоммичен)
    mkdir -p "$1" && printf '# Бэклог\n' > "$1/BACKLOG.md" \
        && { git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -qm x; } >/dev/null 2>&1 \
        || return 1
    printf '%s\n' "$2" >> "$1/BACKLOG.md"
}
# Заглушка речи пишется в файл, имя собрано из частей: у функции один владелец — root-cause-lib
# (прибор родов считает буквальное определение вторым владельцем имени).
printf '%s%s() { cat "$TR"; }\n' rc_last _block > "$W/stub.sh"
verdict() {   # <проект> <файл речи> → foreign|no
    PL="$REPO/hooks/paths-lib.sh" CS="$W/cs" BL="$1/BACKLOG.md" TR="$2" FN="$W/fn.sh" ST="$W/stub.sh" bash -c '
        [ -f "$PL" ] && . "$PL" >/dev/null 2>&1
        . "$ST"
        . "$FN"
        CLAUDSOUL_ROOT="$CS" LOCAL_BACKLOG="$BL" TRANSCRIPT=x dpr_foreign_carrier && echo foreign || echo no'
}

# Путь хука в примере собран из частей: буквальное имя прибор родов читает как предмет пробы.
_cs_hook="rework""-detector.sh"
_proj "$W/p_cs" "- ☐ **B1** дефект в hooks/${_cs_hook} — счётчик не обнуляется" \
    && _proj "$W/p_own" '- ☐ **B2** src/app.ts теряет фильтр при сбросе' \
    || { echo "проба не исполнима: проект не собрался"; exit 2; }

# контроль: пункт о хуке ClaudSoul, ответ со словом ClaudSoul — «чужой носитель» при любом устройстве
[ "$(verdict "$W/p_cs" "$W/say_cs.txt")" = foreign ] \
    || { echo "контроль мёртв: пункт о хуке ClaudSoul не назван чужим носителем"; exit 2; }

BAD=""
# пункт о своём коде, ответ упоминает ClaudSoul мимоходом — тревоги быть не должно
[ "$(verdict "$W/p_own" "$W/say_cs.txt")" = no ] || BAD="${BAD}ложная-тревога "
# пункт о хуке ClaudSoul, ответ без этого слова — тревога обязана быть
[ "$(verdict "$W/p_cs" "$W/say_own.txt")" = foreign ] || BAD="${BAD}пропуск "
if [ -n "$BAD" ]; then echo "вердикт по тексту ответа, а не по пункту: ${BAD}"; exit 1; fi
echo "вердикт по записанному пункту: случаев проверено 2"
exit 0
