#!/usr/bin/env bash
# test_guards_live.sh — стражи прогоняются по НАСТОЯЩЕМУ дереву, а не по фикстурам.
#
# Зачем отдельно от test_guards_provable. Тот доказывает, что у стража есть проверка
# срабатывания. Этого мало: у `quality-gate-check` она была, и он всё равно три релиза
# горел ровно при соблюдении контракта. Фикстура «complete» ставила `- [x]`, чего нет
# ни в одном живом скилле, — тест был зелёный, хук неверный, и зелёный тест служил
# доказательством правильности.
#
# Общее у четырёх багов v1.12.0-v1.12.3: **ни один не был бы пойман фикстурой, потому
# что фикстуры строились из представления о данных, а не из данных.** Все четыре
# вскрывались одной и той же командой — прогнать проверку по живому дереву и
# посмотреть, что она скажет. Это и мехнизируется здесь.
#
# Правило: на ЗДОРОВОМ дереве (HEAD, ничего не сломано) страж обязан молчать.
# Загорелся — ложное срабатывание, и оно видно сразу, а не через три релиза.
#
# Дерево берём из `git worktree` на HEAD, а не рабочее: рабочее в середине правки
# даёт то шум, то тишину, и тест станет плавающим. Детерминизм важнее свежести.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO="$(cd "$HOOKS_DIR/.." && pwd)"

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "SKIP: не git-репозиторий"; exit 0; }

PASS=0
FAIL=0
NOISY=()

TMP=$(mktemp -d)
WT="$TMP/live"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Дерево строим так, чтобы КАЖДЫЙ страж действительно запустился.
#
# Две предыдущие версии этого теста проходили вхолостую, и обе я сначала счёл
# зелёными:
#   1) чистый worktree на HEAD — staged пусто, коммит-стражи выходят на первой
#      проверке; молчание означало «не запускался»;
#   2) воспроизведение последнего коммита — покрытие стало случайным: в HEAD не было
#      ни одного `skills/*/SKILL.md`, и quality-gate-check снова не запускался.
# Оба раза заведомо сломанная версия хука из v1.12.0 проходила тест насквозь.
#
# Отсюда правило построения: не «какой-то реальный коммит», а ВСЁ дерево как staged.
# Тогда запуск стража не зависит от того, что случайно попало в последний коммит.
# Содержимое настоящее (`git archive HEAD`), индекс полный, история пустая — вызовы
# вида `git show HEAD:file` внутри стражей деградируют в «файл новый», и проверки,
# требующие прошлой ревизии, просто не участвуют. Это честно: они покрыты фикстурами.
mkdir -p "$WT"
git -C "$REPO" archive HEAD 2>/dev/null | tar -x -C "$WT" 2>/dev/null || {
    echo "SKIP: не удалось выгрузить дерево HEAD"; exit 0; }
git -C "$WT" init -q 2>/dev/null || { echo "SKIP: git init не отработал"; exit 0; }
git -C "$WT" config user.email t@e >/dev/null 2>&1
git -C "$WT" config user.name  t   >/dev/null 2>&1
git -C "$WT" add -A >/dev/null 2>&1 || true

export STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

STAGED_N=$(git -C "$WT" diff --cached --name-only 2>/dev/null | wc -l | tr -d '[:space:]')
: "${STAGED_N:=0}"
# Порог, а не «больше нуля»: полдесятка файлов означало бы, что выгрузка сорвалась,
# и тест снова доказывал бы тишину незапущенных хуков.
if [ "${STAGED_N:-0}" -lt 100 ]; then
    echo "SKIP: в индексе всего $STAGED_N файлов — дерево не собралось, прогон был бы пустым"
    exit 0
fi
# Страж, которому нечего проверять, не проверяет ничего: убеждаемся, что файлы,
# на которые смотрят коммит-стражи, реально в индексе.
SKILLS_STAGED=$(git -C "$WT" diff --cached --name-only 2>/dev/null | grep -c '^skills/.*/SKILL\.md$' || true)
: "${SKILLS_STAGED:=0}"

# Сценарии, на которых здоровое дерево обязано молчать. Ключ — чем кормим стража.
commit_payload() {
    jq -cn --arg cw "$WT" --arg s "live-$1" \
        '{session_id:$s, tool_name:"Bash", cwd:$cw, tool_input:{command:"git commit -m release"}}'
}

check_silent() {
    local hook="$1" payload="$2" label="$3"
    local out
    out=$(printf '%s' "$payload" | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/$hook.sh" 2>/dev/null)
    if [ -z "$out" ] || [ "$out" = "{}" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        NOISY+=("$hook — $label; сказал: $(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // .hookSpecificOutput.permissionDecisionReason // .' 2>/dev/null | head -3 | tr '\n' ' ' | cut -c1-160)")
    fi
}

# Различение, которое пришлось ввести после первого же прогона: не всякий говорящий
# хук — страж нарушения.
#
#   СТРАЖ НАРУШЕНИЯ горит, когда что-то не так. На здоровом дереве обязан молчать,
#   и его срабатывание здесь — ложная тревога.
#   НАПОМИНАНИЕ горит в штатной работе по определению (крупный дифф, накопленный
#   материал). Требовать от него тишины — значит объявить нормальную работу дефектом.
#
# Первая версия теста мешала их в одну кучу и обвинила `code-review-reminder` в
# ложном срабатывании на коммите с 90 строками кода — а он ровно для этого и сделан.
# Разделение существенное: если требовать тишины от напоминаний, тест начнёт краснеть
# на здоровых релизах, его отключат, и вместе с ним умрут проверки настоящих стражей.
for h in quality-gate-check skill-review-check docs-family-check claude-md-size-check; do
    [ -f "$HOOKS_DIR/$h.sh" ] || continue
    check_silent "$h" "$(commit_payload "$h")" "здоровое дерево на HEAD, коммит без нарушений"
done

# Напоминания: тишины не требуем, но требуем валидный контракт вывода — молчание или
# корректный hookSpecificOutput. Кривой JSON ломает промпт целиком.
for h in changelog-reminder code-review-reminder knowledge-capture-reminder; do
    [ -f "$HOOKS_DIR/$h.sh" ] || continue
    out=$(printf '%s' "$(commit_payload "$h")" | env STATE_DIR="$STATE_DIR" bash "$HOOKS_DIR/$h.sh" 2>/dev/null)
    if [ -z "$out" ] || printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        NOISY+=("$h — напоминание вернуло не пустоту и не валидный hookSpecificOutput: $(printf '%s' "$out" | head -c 120)")
    fi
done

# Стражи действий: безобидная команда не должна вызывать вопросов.
for h in bulk-copy-guard trust-guard playwright-cli-guard bash-cost-detector; do
    [ -f "$HOOKS_DIR/$h.sh" ] || continue
    check_silent "$h" \
        "$(jq -cn --arg cw "$WT" --arg s "live-$h" \
            '{session_id:$s, tool_name:"Bash", cwd:$cw, tool_input:{command:"ls -la"}}')" \
        "безобидная команда ls"
done

echo ""
echo "=================================="
echo "guards-live: $PASS молчат на здоровом дереве ($STAGED_N staged файлов, из них SKILL.md: $SKILLS_STAGED), $FAIL шумят"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Страж, горящий на здоровом дереве, — ложное срабатывание. Его сигнал"
    echo "перестают читать, и настоящая находка тонет вместе с ним."
    for n in "${NOISY[@]}"; do echo "  ✗ $n"; done
fi
echo "=================================="
[ "$FAIL" -eq 0 ]
