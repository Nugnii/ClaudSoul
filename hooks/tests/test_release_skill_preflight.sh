#!/usr/bin/env bash
# test_release_skill_preflight.sh
#
# ПОВОД: релиз v1.32.0 (145fca0) ушёл с красным набором тестов — /release тегирует
# и пушит, не запуская hooks/tests/run_all.sh и не дожидаясь CI, хотя
# scripts/ci-status.sh написан ровно под это. Пять корней падения чинили уже
# ПОСЛЕ публикации тега (56836a4).
#
# Тест фиксирует две строки в установленном скилле /release:
#   T1 — pre-flight упоминает прогон тестов проекта (run_all.sh);
#   T2 — после push упоминается ожидание CI релизного коммита (ci-status.sh) —
#        локальный прогон не заменяет CI: macOS ≠ Linux (pattern-shell-portability,
#        живой пример — test_periodic_digests в v1.32.0).
#
# С 2 сентября 2026 скилл живёт В РЕПОЗИТОРИИ (skills/release/SKILL.md) и ставится
# install.sh общим циклом по skills/*/ (D260). До этого он лежал только на машине
# владельца, а тест целился туда же — то есть был зелён в CI по ОТСУТСТВИЮ файла и
# сторожил пустоту. Теперь отсутствие файла — настоящий FAIL: скилл выпал из репозитория.
#
# Путь строится ОТ $0, а не относительный: hooks/tests/run_all.sh делает cd в свой
# каталог, и `skills/release/SKILL.md` резолвился бы в hooks/tests/skills/… — тест был бы
# вечно красным (pattern-verification-frame-mismatch).
set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SKILL="${RELEASE_SKILL:-$REPO/skills/release/SKILL.md}"
[ -f "$SKILL" ] || { echo "FAIL: нет $SKILL — скилл выпал из репозитория"; exit 1; }

fail=0

if ! grep -q 'run_all\.sh' "$SKILL"; then
    echo "FAIL [T1]: pre-flight /release не упоминает прогон тестов (run_all.sh) —"
    echo "           релиз снова может уйти с красным набором, как v1.32.0."
    fail=1
fi

if ! grep -q 'ci-status\.sh' "$SKILL"; then
    echo "FAIL [T2]: /release не упоминает ожидание CI релизного коммита (ci-status.sh) —"
    echo "           расхождение сред (macOS ≠ Linux CI) остаётся невидимым до следующей сессии."
    fail=1
fi

[ "$fail" -eq 0 ] && echo "PASS: /release несёт прогон тестов в pre-flight и ожидание CI после push"
exit "$fail"
