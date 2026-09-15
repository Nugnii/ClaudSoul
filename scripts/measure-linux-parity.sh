#!/usr/bin/env bash
# measure-linux-parity.sh — проходит ли набор на машине БЕЗ установленного ClaudSoul.
# Результат: набор тестов зелёный на машине без установленного ClaudSoul
# Проверка результата: bash scripts/measure-linux-parity.sh даёт 0
#
#
# Отдельным скриптом, потому что у замера должен быть исполнимый вид: строка в реестре
# `scripts/measurements.tsv` обязана указывать на команду, а не на инструкцию в документации.
# Рецепт живёт ТОЛЬКО здесь; docs/development.md на него ссылается. До 12 сентября 2026 копия
# рецепта стояла и там и разошлась со скриптом в день, когда рецепт выровняли (R1).
set -uo pipefail
# Каталог скрипта — подстановкой параметра, без `dirname`: в урезанном PATH свидетеля внешней
# команды нет, подстановка вырождалась в `cd -- "/.."`, REPO становился `/`, и в контейнер
# монтировался корень диска (прожарка 13 сентября 2026, атака 5).
_self="${BASH_SOURCE[0]:-$0}"; _self_dir="${_self%/*}"; [ "$_self_dir" = "$_self" ] && _self_dir=.
REPO="${CLAUDSOUL_REPO:-$(cd -- "$_self_dir/.." 2>/dev/null && pwd -P)}"
# Корень обязан быть деревом ClaudSoul: монтировать наугад найденный каталог нельзя.
[ -f "$REPO/hooks/tests/run_all.sh" ] || { echo "measure-linux-parity: корень дерева не найден (${REPO:-пусто}) — не измерено"; exit 2; }
# Без docker замер НЕ ИЗМЕРЕН (код 2), а не зелёный: «пропущен» с кодом 0 читался планировщиком как успех.
command -v docker >/dev/null 2>&1 || { echo "measure-linux-parity: docker недоступен — не измерено"; exit 2; }
docker info >/dev/null 2>&1 || { echo "measure-linux-parity: демон docker не запущен — не измерено"; exit 2; }
cd "$REPO" || exit 2
# Рамка контейнера — та же, что у раннера GitHub, иначе замер мерит не «машину без ClaudSoul»,
# а свойства своего контейнера: 12 сентября 2026 он дал 35 красных при зелёном CI на том же
# дереве — 21 раз `No module named 'yaml'` (python3-yaml на раннере есть) и тесты прав, которые
# root игнорирует (T2d «read-only не сработал»). Поэтому: python3-yaml и непривилегированный
# пользователь. perl нужен сверщику понятий и вырезанию доктрины.
# Второй заход того же дня (D404), 5 красных → 0. procps: `pgrep -P` снимает дерево сторожа
# (run_all.sh:103) — без него `sleep` сторожа переживает родителя, держит трубу подстановки
# `$(run_all.sh)` в test_run_all_parallel, и тест висит до срока; `ps -p` судит живость сессии
# (session-registry-lib.sh:120). LANG=C.UTF-8: локаль образа POSIX, и `grep -i` не сворачивает
# регистр кириллицы, тогда как на раннере C.UTF-8 (тесты доктрины с `grep -qi` там зелёные).
# Оставлено ДВА расхождения, оба названы. awk здесь mawk (умолчание Debian), побайтовый: скобка
# `[Бб]` в нём не совпадает с двухбайтовой буквой, а awk раннера совпадает. Это более строгая
# рамка, а не шум: 12 сентября она нашла дефект module-context-inject.sh:90. gitleaks не ставится:
# тест стража называет пропуск, слой секретов мерится на CI (шаг workflow).
docker run --rm -v "$PWD":/repo:ro -w /repo debian:stable-slim bash -c '
  apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq jq git python3 python3-yaml perl procps >/dev/null 2>&1
  useradd -m tester 2>/dev/null
  # Строка `FAILED:<имена>` сводки (run_all.sh:495) сохраняется: `tail -2` оставлял только код,
  # и замер 12 сентября 2026 сказал «ЕСТЬ НАХОДКИ», не назвав ни одного теста
  # (case-2026-09-11-result-lived-only-in-the-output). Код выхода — код раннера.
  cp -R /repo /work && chown -R tester /work
  su tester -c "cd /work/hooks/tests && LANG=C.UTF-8 bash run_all.sh" > /tmp/run.log 2>&1; rc=$?
  grep -E "^FAILED:" /tmp/run.log; tail -2 /tmp/run.log; exit $rc'
