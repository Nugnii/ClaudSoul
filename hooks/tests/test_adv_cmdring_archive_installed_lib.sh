#!/usr/bin/env bash
# СУДИТ: scripts/backlog-archive.sh hooks/backlog-lib.sh
# test_adv_cmdring_archive_installed_lib.sh — архиватор в проекте сессии с установленной библиотекой без ограды кольца (D503) переносит закрытое, как переносил до неё.
#
# Атака (противник ограды кольца, 1 октября 2026). Ограда добавила `BACKLOG_CMD_SEP` в перечень
# обязательных имён библиотеки (`_need`), и архиватор при установленной копии без него
# отказывает кодом 2 «библиотека старше скрипта — перенос отменён». Установленная копия
# (`~/.claude/hooks/backlog-lib.sh`) в день правки совпадала с HEAD — ограды в ней не было, —
# а архиватор берёт её всякий раз, когда долг найден по cwd в проекте без своего hooks/ (шапка
# архиватора: «долг проекта по cwd»). Пять соседних исполнителей при такой библиотеке работают
# «без ограды, как было до неё»; архиватор вместо этого перестал переносить вовсе — до прогона
# install.sh.
#
# Рамка: HOME в песочнице; «установленная» библиотека — нынешняя без блока ограды (имя
# BACKLOG_CMD_SEP и три функции backlog_cmd_*), то есть копия, старше ограды. Контроль рамки:
# тот же проект и тот же архиватор с полной библиотекой переносят пункт.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d)   # временное уберёт система
mkhome() {  # <HOME> <полная|без-ограды>
    mkdir -p "$1/.claude/hooks"
    if [ "$2" = полная ]; then
        cp "$REPO/hooks/backlog-lib.sh" "$1/.claude/hooks/backlog-lib.sh"
    else
        python3 - "$REPO/hooks/backlog-lib.sh" "$1/.claude/hooks/backlog-lib.sh" <<'PY'
import io, re, sys
s = io.open(sys.argv[1], encoding="utf-8").read()
# Блок ограды: от присваивания разделителя до конца функции backlog_cmd_env.
m = re.search(r"^BACKLOG_CMD_SEP=.*?^backlog_cmd_env\(\) \{.*?^\}\n", s, re.S | re.M)
assert m, "блок ограды в библиотеке не найден"
io.open(sys.argv[2], "w", encoding="utf-8").write(s[:m.start()] + s[m.end():])
PY
    fi
}
mkproj() {  # <каталог> — проект сессии: CLAUDE.md + BACKLOG.md с одним закрытым (старше порога) и одним открытым
    mkdir -p "$1"; : > "$1/CLAUDE.md"
    printf -- '# Долг\n\n## Раздел\n\n- ☑ **D101** закрытый пункт\n- ☐ **D102** открытый пункт\n' > "$1/BACKLOG.md"
}
run_arch() {  # <HOME> <проект> <состояние> → вывод; код — код архиватора
    ( cd "$2" && env -u BACKLOG_FILE -u BACKLOG_ARCHIVE -u CLAUDSOUL_REPO -u BACKLOG_CHECKS_NESTED -u BACKLOG_CMD_RUNNING \
        HOME="$1" STATE_DIR="$3" PATHS_LIB="$REPO/hooks/paths-lib.sh" bash "$REPO/scripts/backlog-archive.sh" run 2>&1 )
}

# Контроль рамки: полная установленная библиотека — пункт уезжает.
mkhome "$T/h0" полная; mkproj "$T/p0"
OUT0=$(run_arch "$T/h0" "$T/p0" "$T/s0"); RC0=$?
{ [ "$RC0" = 0 ] && grep -q 'Перенесено в архив: 1' <<< "$OUT0"; } && ok \
    || bad TC "контроль: с полной библиотекой архиватор не перенёс пункт (rc $RC0): «${OUT0}»"

# Предмет: установленная библиотека старше ограды.
mkhome "$T/h1" без-ограды; mkproj "$T/p1"
grep -qE '^(BACKLOG_CMD_SEP=|backlog_cmd_)' "$T/h1/.claude/hooks/backlog-lib.sh" && bad T-old "рамка: из «старой» библиотеки ограда не вырезана" || ok
OUT1=$(run_arch "$T/h1" "$T/p1" "$T/s1"); RC1=$?
{ [ "$RC1" = 0 ] && grep -q 'Перенесено в архив: 1' <<< "$OUT1"; } && ok \
    || bad T1 "архиватор с установленной библиотекой без ограды перестал переносить (rc ${RC1}): «${OUT1}»"
grep -q '☑ \*\*D101\*\*' "$T/p1/BACKLOG.md" 2>/dev/null \
    && bad T2 "закрытый D101 остался в BACKLOG.md проекта — уборка, которую архиватор делал до ограды, не состоялась" || ok

echo "adv cmdring archive installed lib: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
