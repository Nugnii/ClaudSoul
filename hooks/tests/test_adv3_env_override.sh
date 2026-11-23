#!/usr/bin/env bash
# test_adv3_env_override.sh — задокументированный override CLAUDSOUL_REPO хуки игнорируют.
#
# Шапка paths-lib.sh (строки 26-29) утверждает: «общее у двух мест — порядок, и он
# повторён здесь дословно, а не переизобретён». Порядок в bin/resolve-claudsoul-repo.sh:
#   CLAUDSOUL_REPO env → ~/.claude/claudsoul-repo → git-корень.
# Порядок в paths-lib.sh:
#   CLAUDSOUL_ROOT env → ~/.claude/claudsoul-repo → жёсткий дефолт.
# Имя переменной другое, и именно CLAUDSOUL_REPO названо пользователю в тексте ошибки
# резолвера: «либо задай CLAUDSOUL_REPO=/путь/к/ClaudSoul» (bin/resolve-claudsoul-repo.sh:31),
# и в skills/enrich/SKILL.md:32.
#
# Достижимость: пользователь выполняет ровно то, что ему велит сообщение об ошибке.
# Скиллы после этого работают, хуки — молча смотрят в $HOME/My Project/ClaudSoul.
# Это тот же отказ, ради которого заводился D72, только по второму входу.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/paths-lib.sh"
TMP="$(mktemp -d)"
mkdir -p "$TMP/home/.claude" "$TMP/elsewhere/ClaudSoul"

got=$(env -u CLAUDSOUL_ROOT HOME="$TMP/home" CLAUDSOUL_REPO="$TMP/elsewhere/ClaudSoul" \
      bash -c "source '$LIB'; printf '%s' \"\$CLAUDSOUL_ROOT\"")

if [ "$got" = "$TMP/elsewhere/ClaudSoul" ]; then
    echo "PASS: CLAUDSOUL_REPO учтён"
    echo "adv3 env override: 1/1 passed"
    exit 0
fi

echo "FAIL [paths-lib.sh:30-37]: CLAUDSOUL_REPO=«$TMP/elsewhere/ClaudSoul» проигнорирован."
echo "     Ожидалось: CLAUDSOUL_ROOT=$TMP/elsewhere/ClaudSoul"
echo "     Получено:  CLAUDSOUL_ROOT=$got"
echo "adv3 env override: 0/1 passed"
exit 1
