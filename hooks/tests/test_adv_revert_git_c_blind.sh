#!/usr/bin/env bash
# СУДИТ: hooks/revert-signal.sh
# test_adv_revert_git_c_blind.sh — revert-signal.sh держит СВОЮ копию матчера git-подкоманды,
# и копия слабее библиотечной: форма `git -C <каталог> …` и полный путь к git ею не видны.
#
# Атака. `revert-signal.sh` источает `command-scope-lib.sh` (там `is_git_commit`, где
# глобальные опции git перечислены поимённо и `/usr/bin/git` разрешён границей `/`), но
# вызывает НЕ её, а два собственных grep:
#     git[[:space:]]+revert    (:80)
#     git[[:space:]]+commit    (:96)
# Между `git` и подкомандой ничего вставить нельзя. Значит откат, сделанный формой, которую
# правила ЭТОГО проекта предписывают («`git -C "$каталог"`, а не голый `cd … && git`» —
# root-cause-lib.sh:213), повода разбора не заводит вовсе, и вторая половина хука
# (повторный hotfix одного файла) тоже не запускается.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

set -uo pipefail
# Рамка теста не наследует дерево вызывающего (D1366): ноги ждут записи повода, а `rc_env_is_real`
# (hooks/root-cause-lib.sh) считает фикстурой окружение, где CLAUDSOUL_REPO, CLAUDE_HOME или BACKLOG_FILE ведут под
# временный корень, — в клоне коммита с экспортированной CLAUDSOUL_REPO все ноги краснели.
unset CLAUDSOUL_REPO CLAUDE_HOME BACKLOG_FILE

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/revert-signal.sh"
[ -f "$HOOK" ] || { echo "FAIL: не найден $HOOK"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq недоступен";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

REPO_T="$TMP/proj"
mkdir -p "$REPO_T"
git -C "$REPO_T" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_revert_git_c_blind.sh:$LINENO" >&2; exit 1; }
git -C "$REPO_T" config user.email t@e; git -C "$REPO_T" config user.name t
printf 'x\n' > "$REPO_T/f.sh"
git -C "$REPO_T" add -A 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_revert_git_c_blind.sh:$LINENO" >&2; exit 1; }
git -C "$REPO_T" commit -qm 'fix(f): раз' 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_revert_git_c_blind.sh:$LINENO" >&2; exit 1; }
printf 'y\n' > "$REPO_T/f.sh"
git -C "$REPO_T" add -A 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_revert_git_c_blind.sh:$LINENO" >&2; exit 1; }
git -C "$REPO_T" commit -qm 'fix(f): два' 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_adv_revert_git_c_blind.sh:$LINENO" >&2; exit 1; }

# Каждый вызов — своё состояние: дедуп rc_note_event не должен смазывать картину.
fire() {   # fire <команда> → печатает роды заведённых событий
    local st="$TMP/state.$RANDOM.$RANDOM"
    mkdir -p "$st"
    jq -cn --arg c "$1" --arg d "$REPO_T" \
        '{session_id:"s1", tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
      | STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
    jq -r '.kind' "$st/pending-events.jsonl" 2>/dev/null | sort -u | tr '\n' ' '
}

# --- Контроль: голая форма видна, значит фикстура рабочая -----------------------
GOT=$(fire 'git revert HEAD')
case "$GOT" in *revert*) ok "контроль: «git revert HEAD» заводит повод" ;;
    *) bad "контроль не сработал — фикстура негодна (получено: [$GOT])" ;;
esac

# --- Атака 1: откат формой `git -C` --------------------------------------------
GOT=$(fire "git -C $REPO_T revert --no-edit HEAD")
case "$GOT" in
    *revert*) ok "«git -C <каталог> revert» заводит повод" ;;
    *) bad "ОТКАТ НЕ ЗАМЕЧЕН: «git -C <каталог> revert --no-edit HEAD» → поводов [$GOT]" ;;
esac

# --- Атака 2: откат полным путём к исполняемому файлу --------------------------
GOT=$(fire '/usr/bin/git revert HEAD')
case "$GOT" in
    *revert*) ok "«/usr/bin/git revert» заводит повод" ;;
    *) bad "ОТКАТ НЕ ЗАМЕЧЕН: «/usr/bin/git revert HEAD» → поводов [$GOT]" ;;
esac

# --- Атака 3: откат с глобальной опцией ----------------------------------------
GOT=$(fire 'git --no-pager revert HEAD')
case "$GOT" in
    *revert*) ok "«git --no-pager revert» заводит повод" ;;
    *) bad "ОТКАТ НЕ ЗАМЕЧЕН: «git --no-pager revert HEAD» → поводов [$GOT]" ;;
esac

# --- Атака 4: вторая половина хука. `git -C … commit` не открывает разбор
# повторного hotfix, хотя история репозитория его требует (два `fix(f)` подряд).
GOT=$(fire 'git commit -m "fix(f): три"')
case "$GOT" in *hotfix-repeat*) ok "контроль: голый «git commit» видит повторный hotfix" ;;
    *) bad "контроль второй половины не сработал (получено: [$GOT])" ;;
esac
GOT=$(fire "git -C $REPO_T commit -m 'fix(f): три'")
case "$GOT" in
    *hotfix-repeat*) ok "«git -C <каталог> commit» видит повторный hotfix" ;;
    *) bad "ПОВТОРНЫЙ HOTFIX НЕ ЗАМЕЧЕН при «git -C <каталог> commit» → поводов [$GOT]" ;;
esac

# --- Свидетельство: библиотека, УЖЕ загруженная этим хуком, форму знает ---------
# shellcheck source=/dev/null
. "$REPO/hooks/command-scope-lib.sh"
if is_git_commit "git -C $REPO_T commit -m x"; then
    ok "свидетельство: is_git_commit ту же форму распознаёт — копия слабее владельца"
else
    bad "свидетельство не получено: библиотека тоже не знает формы"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
