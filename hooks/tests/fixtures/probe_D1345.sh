#!/usr/bin/env bash
# СУДИТ: scripts/project-graph.py hooks/impact-inject.sh
# probe_D1345.sh — файл, внесённый в карту ДО записи (так зовёт живой страж правки), после записи отвечает своими
#   исходящими рёбрами без повторного касания и без пересборки.
# Проверка результата: bash hooks/tests/fixtures/probe_D1345.sh → 0 — ребро названо; 1 — узел одинок;
#   2 — не измерено (нет прибора, сборка не прошла, контроль не сошёлся).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$REPO/scripts/project-graph.py"
[ -f "$TOOL" ] || { echo "нет прибора — не измерено"; exit 2; }
command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { echo "нет git или python3 — не измерено"; exit 2; }
W=$(mktemp -d) || { echo "нет временного каталога — не измерено"; exit 2; }
trap 'rm -rf "$W"' EXIT
S="$W/repo"; mkdir -p "$S/scripts" "$S/hooks" "$S/.claude-docs" "$S/mcp-server/visualization" "$W/lessons"
cp "$TOOL" "$S/scripts/" || { echo "прибор не скопирован — не измерено"; exit 2; }
( cd "$S" && git init -q . && git config user.email t@t && git config user.name t ) || { echo "песочница не стала репозиторием — не измерено"; exit 2; }
printf '#!/usr/bin/env bash\nbase_helper() { echo 1; }\n' > "$S/hooks/base.sh"
{ printf '# path\tsha\tdeps\tdocs\ttests\tnames\n'; printf 'hooks/base.sh\ta\t\t\t\tbase_helper\n'; } > "$S/.claude-docs/dep-index.tsv"
( cd "$S" && git add -A && git commit -qm i ) >/dev/null 2>&1 || { echo "базовый коммит не прошёл — не измерено"; exit 2; }
pg() { ( cd "$S" && LESSONS_DIR="$W/lessons" CLAUDSOUL_REPO="$S" CLAUDSOUL_ROOT="$REPO" python3 scripts/project-graph.py "$@" 2>/dev/null ); }
pg --refresh >/dev/null || { echo "сборка карты не прошла — не измерено"; exit 2; }
pg --touch hooks/new.sh >/dev/null            # до записи: файла ещё нет — так зовёт hooks/impact-inject.sh
printf '#!/usr/bin/env bash\nsource hooks/base.sh\n' > "$S/hooks/new.sh"
before=$(pg --node hooks/new.sh | grep -c -- '--> hooks/base.sh')
pg --touch hooks/new.sh >/dev/null            # положительный контроль: касание ПОСЛЕ записи ребро даёт
after=$(pg --node hooks/new.sh | grep -c -- '--> hooks/base.sh')
[ "${after:-0}" -ge 1 ] || { echo "контроль: и после записи ребра нет — не измерено"; exit 2; }
[ "${before:-0}" -ge 1 ] && { echo "исходящее ребро названо без повторного касания"; exit 0; }
echo "узел, внесённый до записи, одинок: исходящих рёбер к hooks/base.sh 0"
exit 1
