#!/usr/bin/env bash
# probe_D438.sh — проба кандидата D438: страж исчезновения долга (`backlog-vanish-check.sh`)
# отвечает ОДНИМ молчанием на два разных состояния HEAD:BACKLOG.md — «пунктов нет вовсе» и
# «разбор не увидел ни одного, потому что незакрытый забор кода гасит остаток файла в
# backlog_strip_fenced» (`[ -n "$BEFORE" ] || exit 0`). Назван разбором D434 (комментарий в
# самом файле, «названный предел 1»); здоровый образец различения — канал #CG_BROKEN в
# hooks/completion-gate.sh (сверка сырого текста с очищенным).
# Результат: HEAD с незакрытым забором кода перед пунктом, который забор прячет от разбора,
# и пункт при этом исчезает из рабочего дерева без переезда в архив — страж обязан назвать
# исчезнувший пункт, а не молчать. То же исчезновение при исправном HEAD страж уже называет
# сейчас (положительный контроль, без него проба не отличила бы «умеет различать» от «сломан
# вообще»).
# Проверка результата: bash hooks/tests/fixtures/probe_D438.sh даёт 0
#
# Коды: 0 — желаемое поведение соблюдено; 1 — дефект наблюдён (stderr называет вывод стража);
#       2 — рамка не собралась (stderr называет, что).
# Механизм под судом берётся из CLAUDSOUL_REPO (зелёная сторона подставляет копию с починкой).
# Фикстура — свой git-репозиторий; HOME подменён. Судится ВЫВОД стража на payload `git commit`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
MECH="${CLAUDSOUL_REPO:-$ROOT}"
HOOK="$MECH/hooks/backlog-vanish-check.sh"
[ -f "$HOOK" ] || { echo "probe_D438: нет $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "probe_D438: нужен jq" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "probe_D438: нужен git" >&2; exit 2; }
T=$(mktemp -d) || { echo "probe_D438: нет временного каталога" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R" "$T/home"
GG() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -C "$R" "$@"; }
GG init -q 2>/dev/null || { echo "probe_D438: git init не удался" >&2; exit 2; }
run() { jq -cn --arg cwd "$R" '{cwd:$cwd, session_id:"probe-d438", tool_name:"Bash", tool_input:{command:"git commit -m x"}}' \
        | HOME="$T/home" bash "$HOOK" 2>/dev/null; }

# Положительный контроль: HEAD без забора, D901 живой; пункт исчезает из рабочего дерева
# без переезда в архив — страж УЖЕ СЕЙЧАС называет его. Без этого шага дефект и обычная
# поломка стража были бы неотличимы.
printf '# BACKLOG\n\n- ☐ **D901** живой пункт\n' > "$R/BACKLOG.md"
GG add BACKLOG.md >/dev/null 2>&1 && GG commit -qm base >/dev/null 2>&1 \
    || { echo "probe_D438: базовый коммит не состоялся" >&2; exit 2; }
HEADTXT=$(git -C "$R" show HEAD:BACKLOG.md 2>/dev/null || true)
grep -q 'D901' <<< "$HEADTXT" || { echo "probe_D438: HEAD не несёт D901 — фундамента нет" >&2; exit 2; }
printf '# BACKLOG\n' > "$R/BACKLOG.md"
O=$(run)
grep -q 'D901' <<< "$O" \
    || { echo "probe_D438: контроль — исчезновение при исправном HEAD не названо, рамка не собралась: [$O]" >&2; exit 2; }
GG checkout -q -- BACKLOG.md 2>/dev/null || { echo "probe_D438: файл не восстановлен" >&2; exit 2; }

# Суд: новый HEAD — незакрытый забор кода ПЕРЕД пунктом. Сырой текст несёт D901 (проверено
# ниже), а `backlog_strip_fenced` гасит всё от забора до конца файла, включая сам пункт —
# разбор HEAD не находит ни одного идентификатора. Пункт исчезает из рабочего дерева тем же
# способом, что и в контроле выше.
printf '# BACKLOG\n\n```\n- ☐ **D901** живой пункт\n' > "$R/BACKLOG.md"
GG add BACKLOG.md >/dev/null 2>&1 && GG commit -qm corrupt >/dev/null 2>&1 \
    || { echo "probe_D438: коммит с забором не состоялся" >&2; exit 2; }
HEADTXT=$(git -C "$R" show HEAD:BACKLOG.md 2>/dev/null || true)
grep -q 'D901' <<< "$HEADTXT" \
    || { echo "probe_D438: HEAD (с забором) не несёт D901 в сыром тексте — фундамента нет" >&2; exit 2; }
printf '# BACKLOG\n' > "$R/BACKLOG.md"
O=$(run)
# Желаемое поведение — НЕ МОЛЧАТЬ: страж обязан назвать сам ИДЕНТИФИКАТОР (лучший случай) либо,
# как минимум, различить состояние тем же приёмом, что #CG_BROKEN у completion-gate.sh — назвать,
# что разбор HEAD не увидел пунктов при непустом сыром тексте (там тоже только счётчик, не ID).
# Единственный запрещённый исход здесь — полная тишина: она и есть дефект, потому что неотличима
# от «пунктов в HEAD действительно не было».
if [ -z "$O" ]; then
    echo "probe_D438: дефект — незакрытый забор в HEAD:BACKLOG.md гасит разбор, исчезновение D901 не названо (страж молчит): [$O]" >&2
    exit 1
fi

# ПОЛУПОЧИНКА: заглушка «раз BEFORE пусто — всегда предупреждать» тоже сделала бы вывод выше
# непустым, не решив ничего — и вдобавок зашумила бы ЗАКОННУЮ тишину подлинно пустого HEAD.
# Проверяем это отдельным репозиторием: HEAD без единого пункта, рабочее дерево совпадает
# с HEAD — предупреждать здесь НЕЧЕГО, страж обязан остаться тихим.
T2=$(mktemp -d) || { echo "probe_D438: нет второго временного каталога" >&2; exit 2; }
R2="$T2/repo"; mkdir -p "$R2"
GG2() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -C "$R2" "$@"; }
GG2 init -q 2>/dev/null || { echo "probe_D438: git init (2) не удался" >&2; rm -rf "$T2"; exit 2; }
printf '# BACKLOG\n' > "$R2/BACKLOG.md"
GG2 add BACKLOG.md >/dev/null 2>&1 && GG2 commit -qm empty >/dev/null 2>&1 \
    || { echo "probe_D438: базовый коммит (2) не состоялся" >&2; rm -rf "$T2"; exit 2; }
O2=$(jq -cn --arg cwd "$R2" '{cwd:$cwd, session_id:"probe-d438-2", tool_name:"Bash", tool_input:{command:"git commit -m x"}}' \
        | HOME="$T/home" bash "$HOOK" 2>/dev/null)
rm -rf "$T2"
if [ -n "$O2" ]; then
    echo "probe_D438: полупочинка — заглушка зашумила подлинно пустой HEAD (законная тишина нарушена): [$O2]" >&2
    exit 1
fi
exit 0
