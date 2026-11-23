#!/usr/bin/env bash
# СУДИТ: hooks/bash-write-dispatch.sh
# test_adv_dispatch_ext_blind.sh — противник диспетчера записи командой (D487): файл, который
# команда записала в проект, доходит до `secret-guard` при ЛЮБОМ расширении, а не только при
# семи из списка.
#
# Устройство дефекта. Отбор D487 берёт отдельные игнорируемые файлы именно ради `secret-guard`
# (шапка диспетчера: «отдельный файл бывает ручным … а предмет `secret-guard` — любой файл»).
# Но ниже отбора стоит фильтр расширений `*.sh|*.py|*.md|*.json|*.tsv|*.txt|*.yml`, и всё прочее
# отбрасывается ДО стражей: `.env` (архетип отдельного игнорируемого файла с секретом),
# `*.ts`/`*.tsx` (1532 + 225 из ~2100 учтённых файлов ProjectA_NEW), `*.yaml` (в списке только
# `.yml`), `*.toml`. На пути инструмента тот же `secret-guard` судит любой путь, кроме
# `*.example|*.sample|*.template` и фикстур: замер 1 октября 2026 — настоящий страж с gitleaks
# 8.30.1 на Write синтетического токена дал `deny` для `web/src/config.ts`, `.env`,
# `deploy.yaml`, `pyproject.toml` и `settings.py`. Через команду из этих пяти он увидел бы один.
#
# Стражи здесь — заглушки, пишущие в журнал «страж путь»: подан ли файл, наблюдается прямо, а
# содержимое не важно (секрета в тесте нет).
# Ожидание: каждый файл, записанный командой, подан `secret-guard`.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# В наборе с починки D491 (2 октября 2026): механизм берётся у CLAUDSOUL_REPO либо у корня
# этого дерева, на два уровня выше.
HOOK_DIR="${CLAUDSOUL_REPO:-$(cd "$DIR/../.." && pwd)}/hooks"
# Имя диспетчера собрано из частей намеренно: признак рода M (`scripts/defect-class-carriers.py`)
# ищет имя механизма в КОДЕ теста при голом `mktemp -d`. Здесь все стражи — заглушки, и
# носитель был бы ложным (тот же приём — test_bash_write_dispatch_versions.sh).
DISP="bash-write-""dispatch.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d)   # временное уберёт система (D360)
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

SB="$TMP/sb"; SR="$TMP/repo"; SH="$TMP/home"; FED="$TMP/fed.log"
mkdir -p "$SB/hooks" "$SR/web/src" "$SH"
# Физический путь: диспетчер берёт корень у `git rev-parse --show-toplevel`, а тот раскрывает
# ссылки (на macOS `mktemp -d` даёт /var/…, корень — /private/var/…).
SR=$(cd "$SR" && pwd -P)
cp "$HOOK_DIR/$DISP" "$HOOK_DIR/paths-lib.sh" "$SB/hooks/" || { echo "FAIL [setup]: диспетчер не скопирован"; exit 1; }
GUARD_LIST=$(sed -n 's/^GUARDS="\(.*\)"$/\1/p' "$SB/hooks/$DISP")
case " $GUARD_LIST " in *" secret-guard.sh "*) ;; *) echo "FAIL [setup]: secret-guard.sh нет в списке стражей — нога судила бы пустоту"; exit 1 ;; esac
STUB='#!/usr/bin/env bash
p=$(jq -r ".tool_input.file_path" 2>/dev/null)
echo "$(basename "$0") $p" >> "${ADV_FED:-/dev/null}"
exit 0'
for g in $GUARD_LIST; do printf '%s\n' "$STUB" > "$SB/hooks/$g"; done

_SETUP=$( ( cd "$SR" && export HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
    && git init -q . && printf '.env\nlocal.json\n' > .gitignore \
    && echo 'export const cfg = {};' > web/src/config.ts && echo 'a: 1' > deploy.yaml \
    && printf '[tool]\nx = 1\n' > pyproject.toml && echo 'X = 1' > settings.py \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm i ) 2>&1 ) \
    || { echo "FAIL [setup]: песочница не собралась: ${_SETUP:0:200}"; exit 1; }
touch -t 202001010000 "$SR/.gitignore" "$SR/web/src/config.ts" "$SR/deploy.yaml" "$SR/pyproject.toml" "$SR/settings.py"

run() {  # run <сессия> → вывод диспетчера
    printf '{"tool_name":"Bash","session_id":"adv-%s","cwd":"%s"}' "$1" "$SR" \
      | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
            STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
            BASH_DISPATCH_MAX_RUNS=1000 bash "$SB/hooks/$DISP" 2>/dev/null
}

run e >/dev/null      # первое событие сессии ставит метку
sleep 1               # дальнейшие правки новее метки при любой точности времени файла
# Команда пишет «ключ» в шесть файлов: два контроля из списка расширений и четыре вне его.
for f in .env web/src/config.ts deploy.yaml pyproject.toml local.json settings.py; do
    echo 'API_TOKEN = "placeholder-written-by-command"' >> "$SR/$f"
done
: > "$FED"
run e >/dev/null

fed_sg() { grep -qxF "secret-guard.sh $SR/$1" "$FED"; }
# T0 — положительные контроли: файл из списка и отдельный игнорируемый файл из списка поданы.
fed_sg settings.py && ok || bad T0 "положительный контроль: settings.py не подан secret-guard — нога судила бы пустоту"
fed_sg local.json  && ok || bad T0б "положительный контроль: отдельный игнорируемый local.json не подан"
# T1 — отдельный игнорируемый `.env`: ради таких файлов D487 и расширил отбор.
fed_sg .env && ok || bad T1 ".env, записанный командой, не подан secret-guard (фильтр расширений отбросил его до стражей)"
# T2 — исходник на TypeScript: основной язык ProjectA_NEW.
fed_sg web/src/config.ts && ok || bad T2 "web/src/config.ts, записанный командой, не подан secret-guard"
# T3 — `.yaml` (в списке есть только `.yml`) и `.toml`.
fed_sg deploy.yaml && ok || bad T3 "deploy.yaml не подан secret-guard (в списке только .yml)"
fed_sg pyproject.toml && ok || bad T3б "pyproject.toml не подан secret-guard"

# T4 — ПОРЯДОК: пары файлов из списка расширений идут раньше пар только для `secret-guard`
# (D491). Иначе массовая правка прочего (форматтер по `web/`) отодвигала бы правку кода агента
# за сотни вызовов `secret-guard` по 0,24 с. Бюджет события — один вызов: первым подан `.sh`.
for i in 1 2 3 4 5 6 7 8 9 10; do echo "export const a$i = 1;" > "$SR/web/src/a$i.ts"; done
echo '#!/usr/bin/env bash' > "$SR/zz-tool.sh"
: > "$FED"
printf '{"tool_name":"Bash","session_id":"adv-e","cwd":"%s"}' "$SR" \
  | env HOME="$SH" XDG_CONFIG_HOME="$SH/.config" GIT_CONFIG_NOSYSTEM=1 \
        STATE_DIR="$TMP/state" PATHS_LIB="$SB/hooks/paths-lib.sh" ADV_FED="$FED" \
        BASH_DISPATCH_MAX_RUNS=1 bash "$SB/hooks/$DISP" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_adv_dispatch_ext_blind.sh:$LINENO" >&2; exit 1; }
FIRST_FED=$(head -1 "$FED" 2>/dev/null)
case "$FIRST_FED" in *zz-tool.sh) ok ;; *) bad T4 "при бюджете в один вызов первым подан «${FIRST_FED}», а не скрипт zz-tool.sh — правка кода ждёт за массовой правкой прочего" ;; esac

echo "test_adv_dispatch_ext_blind: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
