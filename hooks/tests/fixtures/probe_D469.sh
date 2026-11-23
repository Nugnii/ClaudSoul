#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_named_limit_has_exit.sh
# probe_D469.sh — «Проверка» пункта D469: `hooks/tests/test_named_limit_has_exit.sh:63`
# читает файлы по списку из `git ls-files` без вопроса, есть ли они на диске. Файл, живой в
# индексе и снятый с диска (обычное состояние между `rm` и `git add -u`), роняет прибор
# Traceback'ом с кодом 1 — тем же, которым он говорит «нашёл предел без условия снятия».
# Результат: пропущенный файл НАЗВАН, разбор продолжается, а вердикт остаётся вердиктом:
#            «файла нет» и «предел без условия снятия» перестают отвечать одним кодом.
# Проверка результата: bash hooks/tests/fixtures/probe_D469.sh → 0. Сегодня 1 (дефект
#            наблюдён), 2 — рамка не собралась.
#
# Форма починки взята у соседа В ТОМ ЖЕ ДЕРЕВЕ, а не придумана: `tracked()` в
# `scripts/defect-class-carriers.py` закрыл ровно это состояние по пункту D447 — называет
# пропущенного в stderr ОДИН раз за прогон и не трогает код возврата.
#
# Механизм берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой) и
# исполняется в СВОЕЙ песочнице-репозитории: живое дерево не трогается.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
SUT="$MECH/hooks/tests/test_named_limit_has_exit.sh"
[ -f "$SUT" ] || { echo "probe_D469: нет $SUT" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D469: нет python3 — рамка не собралась" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D469: нет git — рамка не собралась" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D469: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
W="$T/repo"
mkdir -p "$W/hooks/tests" || exit 2
cp "$SUT" "$W/hooks/tests/" || exit 2

# Здоровый файл с объявленным пределом И условием снятия: без него прибор не найдёт ни
# одного объявления и «чисто» будет означать «нечего судить».
cat > "$W/hooks/a.sh" <<'FIX'
#!/usr/bin/env bash
# НАЗВАННЫЙ ПРЕДЕЛ: судится одна форма записи.
# Условие снятия: появится разбор второй формы — предел уйдёт.
exit 0
FIX
# Файл, который будет снят с диска при живой строке в индексе.
cat > "$W/hooks/vanishing.sh" <<'VAN'
#!/usr/bin/env bash
# НАЗВАННЫЙ ПРЕДЕЛ: этот файл существует только ради пробы.
# Условие снятия: пункт D469 закрыт.
exit 0
VAN
( cd "$W" && git init -q && git add -A && \
  git -c user.email=p@p -c user.name=p -c commit.gpgsign=false commit -qm i ) >/dev/null 2>&1 \
    || { echo "probe_D469: песочница не стала репозиторием — рамка не собралась" >&2; exit 2; }

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ПЕРЕД СУДОМ: на целой песочнице прибор обязан дать свой вердикт.
OK_OUT=$( cd "$W" && bash hooks/tests/test_named_limit_has_exit.sh 2>&1 )
OK_RC=$?
if [ "$OK_RC" != 0 ] || ! grep -q 'названных пределов' <<< "$OK_OUT"; then
    echo "probe_D469: контроль — на ЦЕЛОЙ песочнице прибор не дал вердикта (код $OK_RC) — рамка не собралась:" >&2
    printf '%s\n' "$OK_OUT" >&2
    exit 2
fi

# Судимое состояние: строка в индексе жива, файла на диске нет.
rm -f "$W/hooks/vanishing.sh"
OUT=$( cd "$W" && bash hooks/tests/test_named_limit_has_exit.sh 2>&1 )
RC=$?

if grep -q 'Traceback' <<< "$OUT"; then
    echo "probe_D469: дефект — прибор упал Traceback'ом на файле, снятом с диска:" >&2
    printf '%s\n' "$OUT" | tail -3 >&2
    exit 1
fi
if ! grep -q 'vanishing.sh' <<< "$OUT"; then
    echo "probe_D469: дефект — пропущенный файл НЕ НАЗВАН, разбор шёл по неполному входу молча (код $RC):" >&2
    printf '%s\n' "$OUT" | tail -3 >&2
    exit 1
fi
exit 0
