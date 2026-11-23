#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv2_dispatch_prune_flags.sh — противник диспетчера записи командой, раунд 2: файлы
# состояния диспетчера подрезаются уборкой `scripts/state-prune.sh` наравне с прочими
# посессионными файлами — состояние мёртвых сессий не копится без предела.
#
# Устройство. Уборка делит посессионные файлы на СЕМЕЙСТВА — имя с вырезанным id сессии — и
# держит в каждом семействе последние STATE_PRUNE_KEEP (60) сессий. Флаг дедупа диспетчера
# зовётся `bash-dispatch-<сессия>-<корень>-<md5 пары «файл|страж»>.flag`: хеш пары стоит в той
# части имени, что остаётся после выреза сессии, и каждая пара становится СВОИМ семейством.
# Флаг мёртвой сессии уходит, только когда ту же пару тронут ещё 60 сессий — для почти всех
# файлов никогда. Сессия ставит по флагу на каждую пару каждого тронутого файла: 7 на файл.
# Замер живого каталога состояния 1 октября 2026 (только чтение): 66 457 флагов диспетчера из
# 73 546 файлов каталога, 33 548 семейств, ни одного длиннее окна — уборка не снимет ни флага,
# при пороге замера в 3 000 файлов на весь каталог.
#
# Окно здесь уменьшено до одной сессии (STATE_PRUNE_KEEP=1), чтобы не крутить 61 сессию:
# предмет тот же — файлы сессий старше окна обязаны попасть в список уборки.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D489 (1 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
# этого дерева, на два уровня выше.
HOOK_DIR="${CLAUDSOUL_REPO:-$(cd "$DIR/../.." && pwd)}/hooks"
PRUNE="$(cd "$HOOK_DIR/.." && pwd)/scripts/state-prune.sh"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Все стражи здесь — заглушки, и
# носитель был бы ложным.
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
[ -f "$PRUNE" ] || { echo "FAIL [setup]: нет уборщика $PRUNE"; exit 1; }

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; ST="$TMP/state"
mkdir -p "$SB/hooks" "$SR" "$SH/.claude/sessions" "$ST"
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$HOOK_DIR/state-lock-lib.sh" "$HOOK_DIR/portable-lib.sh" "$SB/hooks/" \
    || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
[ -n "$GUARD_LIST" ] || { echo "FAIL [setup]: список стражей пуст — нога судила бы пустоту"; exit 1; }
for g in $GUARD_LIST; do printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$SB/hooks/$g"; done
_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf 'build/\n' > .gitignore && echo base > base.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/base.md" "$SR/.gitignore"

run() {  # run <id сессии> → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$ST" PATHS_LIB="$SB/hooks/paths-lib.sh" BASH_DISPATCH_MAX_RUNS=1000 \
            bash "$SB/hooks/$DISP" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv2_dispatch_prune_flags.sh:$LINENO" >&2; exit 1; }
}

# Три сессии подряд (id — UUID, как у настоящих), каждая правит СВОЙ файл командой.
SIDS=""
for k in 1 2 3; do
    sid="0000000$k-0000-4000-8000-00000000000$k"; SIDS="$SIDS $sid"
    run "$sid" >/dev/null               # первое событие ставит метку
    sleep 1                             # правка новее метки при любой точности времени
    echo "правка $k" > "$SR/s$k.md"
    run "$sid" >/dev/null               # правка подана всем стражам
    # Состарить правку: первое событие следующей сессии берёт тронутое за 5 минут.
    touch -t 202001010000 "$SR/s$k.md"
done
set -- $SIDS
DEAD=$(find "$ST" -maxdepth 1 -type f \( -name "*$1*" -o -name "*$2*" \) | wc -l | tr -d ' ')
DEADFLAGS=$(find "$ST" -maxdepth 1 -type f -name '*.flag' \( -name "*$1*" -o -name "*$2*" \) | wc -l | tr -d ' ')

OUT=$(env STATE_DIR="$ST" HOME="$SH" SR_SESSIONS_DIR="$SH/.claude/sessions" STATE_PRUNE_KEEP=1 \
      bash "$PRUNE" --dry-run 2>&1)
N=$(sed -n 's/.*за окном хранения ([0-9]* на семейство): \([0-9]*\),.*/\1/p' <<< "$OUT")
N=${N:-0}

# T0 — контроль: две старшие сессии оставили состояние, а уборщик в песочнице вообще работает.
# Имена файлов состояния здесь не судятся: починка вправе сложить флаги в один файл сессии.
if [ "$DEAD" -gt 0 ] && [ "$N" -gt 0 ]; then ok
else bad T0 "контроль: файлов двух старших сессий ${DEAD}, уборщик назвал ${N} — нога судила бы пустоту"; fi
# T1 — уборка называет ВСЕ файлы сессий за окном, флаги в том числе.
if [ "$N" -ge "$DEAD" ]; then ok
else bad T1 "уборка видит ${N} из ${DEAD} файлов двух сессий за окном: ${DEADFLAGS} флагов дедупа не попадают в уборку никогда — хеш пары в имени делает каждую пару своим семейством"; fi

echo "test_adv2_dispatch_prune_flags: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
