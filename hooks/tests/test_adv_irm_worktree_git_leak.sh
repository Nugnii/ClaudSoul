#!/usr/bin/env bash
# test_adv_irm_worktree_git_leak.sh — АТАКА: дерево — linked worktree (`.git` — файл), и
# git-операции свидетеля в «копии» ложатся в индекс НАСТОЯЩЕГО worktree.
#
# scripts/instrument-result-measured.sh копирует `.git` через `cp -R`. У linked worktree
# `.git` — файл `gitdir: …/.git/worktrees/<имя>`; копия получает тот же файл и тем самым
# ДЕЛИТ с настоящим worktree индекс, HEAD и ветку. Всё, что свидетель делает через git
# в своём корне (`git add`, `git commit`, `git stash`), меняет состояние настоящего
# worktree, а не копии. Харнесс заводит worktree для изолированных агентов штатно
# (isolation: worktree), и прибор оттуда зовётся как из любого корня.
#
# Ожидание: после прогона индекс настоящего worktree не изменился.
# Факт: в индексе worktree появился marker.txt, добавленный свидетелем из копии.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
IRM="${ROOT}/scripts/instrument-result-measured.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d)
MAIN="${TMP}/main"; WT="${TMP}/wt"
mkdir -p "${MAIN}/scripts" "${MAIN}/hooks/tests" "${TMP}/state"

printf '#!/usr/bin/env bash\n# good.sh\n# Результат: печать ok\n# Проверка результата: bash hooks/tests/test_good.sh даёт 0\necho ok\n' > "${MAIN}/scripts/good.sh"
# Свидетель по поведению, который заодно делает git add в СВОЁМ корне (как делал бы тест,
# проверяющий страж коммита на собственном дереве).
printf '#!/usr/bin/env bash\nout=$(bash "$(dirname "$0")/../../scripts/good.sh")\n[ "$out" = ok ] || exit 1\nR="$(cd "$(dirname "$0")/../.." && pwd)"\necho x > "$R/marker.txt"\ngit -C "$R" add marker.txt >/dev/null 2>&1\nexit 0\n' > "${MAIN}/hooks/tests/test_good.sh"
chmod +x "${MAIN}"/scripts/* "${MAIN}"/hooks/tests/*
git init -q "${MAIN}" \
    && git -C "${MAIN}" -c user.email=t@t -c user.name=t add -A \
    && git -C "${MAIN}" -c user.email=t@t -c user.name=t commit -qm init \
    && git -C "${MAIN}" worktree add -q "${WT}" -b adv 2>/dev/null \
    || { echo "FAIL: фикстура worktree не собралась"; exit 1; }
[ -f "${WT}/.git" ] || { echo "FAIL: у worktree .git не файл — фикстура не о том"; exit 1; }

BEFORE=$(git -C "${WT}" ls-files | sort)
OUT=$(IRM_ROOT="${WT}" STATE_DIR="${TMP}/state" SUITE_BASELINE_FILE="${TMP}/нет-базиса" IRM_TIMEOUT=2 bash "${IRM}" 2>&1); RC=$?
AFTER=$(git -C "${WT}" ls-files | sort)

# T1: индекс настоящего worktree не должен меняться от прогона по «копии».
if [ "${BEFORE}" = "${AFTER}" ]; then ok; else bad T1 "индекс настоящего worktree изменён из копии: было «$(tr '\n' ' ' <<< "${BEFORE}")», стало «$(tr '\n' ' ' <<< "${AFTER}")»; git status: $(git -C "${WT}" status --short | tr '\n' ' ')"; fi
# T2: сам замер при этом отчитался как обычно (rc 0) — утечка снаружи невидима.
if [ "${RC}" -eq 0 ]; then ok; else bad T2 "rc=${RC}: ${OUT}"; fi

echo ""
echo "adv irm worktree git leak: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
