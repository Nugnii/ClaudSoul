#!/usr/bin/env bash
set -u
# СУДИТ: hooks/tests/test_write_target_scope.sh hooks/tests/test_five_whys_gate.sh hooks/tests/test_impact_inject.sh hooks/tests/test_adv2_doc_impact_stale_row.sh hooks/tests/test_project_git.sh hooks/tests/test_uninstall.sh
# probe_D1233 — шесть тестов, красных на Linux, больше не держатся за свойства машины автора: в каждом стоит рамка, найденная
#   разбором 7 ноября 2026 (платформа для ног про `/private` и регистр; CLAUDSOUL_ROOT дерева теста; модуль описания рядом
#   с прибором в песочнице; личность git у коммита подмодуля; PATH без jq каталогом ссылок). Сам прогон на Linux — замер
#   `suite-linux` (`scripts/measure-linux-parity.sh`): контейнер здесь не поднимается, проба судит наличие рамок и зелень
#   тестов на этой машине. Рамка засчитывается только вне комментария, а тесты, чья рамка заменяет свойство машины
#   автора, идут в мире БЕЗ него (скептик opus по 97f51972, M3): пустой HOME (нет указателя на репозиторий и установки),
#   git без глобальной личности — иначе на macOS автора мутант со снятой рамкой зеленел.
#   0 — рамки на месте и тесты зелены; 1 — рамки нет или тест красен; 2 — нет тестов.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
T=hooks/tests
bad=0
chk() { grep -q -- "^[^#]*$2" "$T/$1" || { echo "$1: нет рамки «$2»"; bad=1; }; }
for f in test_write_target_scope test_five_whys_gate test_impact_inject test_adv2_doc_impact_stale_row test_project_git test_uninstall; do
    [ -f "$T/$f.sh" ] || exit 2
done
chk test_write_target_scope.sh 'MAC=0; \[ "$(_wt_real /tmp)" = /private/tmp \] && MAC=1'
chk test_five_whys_gate.sh 'export CLAUDSOUL_ROOT="$REPO"'
chk test_impact_inject.sh 'cp "$REPO_ROOT/hooks/lib/project_map.py" hooks/lib/'
chk test_adv2_doc_impact_stale_row.sh 'cp "$REPO/hooks/lib/project_map.py" "$R/hooks/lib/"'
chk test_project_git.sh 'git -c user.email=t@t -c user.name=t commit -qm moved'
chk test_uninstall.sh 'NOJQ="$(mktemp -d)"'
chk test_uninstall.sh 'xargs cksum)'
E=$(mktemp -d) || exit 2
trap 'rm -rf "$E"' EXIT
# Адрес ClaudSoul тесты берут у себя, а не из окружения пробы: CLAUDSOUL_REPO, унаследованный от исполнителя «Проверки»,
# подменял снятую рамку CLAUDSOUL_ROOT, и мутант test_five_whys_gate зеленел (сверка мутантом 7 ноября 2026).
U="env -u CLAUDSOUL_REPO -u CLAUDSOUL_ROOT"
# Параллельно: поодиночке шесть тестов шли 2,5 минуты, а «Проверка» обязана укладываться в 120 с. Код каждого — в файл.
for f in test_write_target_scope test_uninstall; do
    ( $U bash "$T/$f.sh" >/dev/null 2>&1; echo $? > "$E/$f.rc" ) &
done
for f in test_five_whys_gate test_impact_inject test_adv2_doc_impact_stale_row; do
    mkdir -p "$E/$f"; ( $U HOME="$E/$f" bash "$T/$f.sh" >/dev/null 2>&1; echo $? > "$E/$f.rc" ) &
done
( $U GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash "$T/test_project_git.sh" >/dev/null 2>&1; echo $? > "$E/test_project_git.rc" ) &
wait
for f in test_write_target_scope test_uninstall test_five_whys_gate test_impact_inject test_adv2_doc_impact_stale_row test_project_git; do
    [ "$(cat "$E/$f.rc" 2>/dev/null)" = 0 ] || { echo "$f красен (пустой HOME, git без глобальной личности, без адреса ClaudSoul)"; bad=1; }
done
exit "$bad"
