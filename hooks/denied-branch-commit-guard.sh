#!/usr/bin/env bash
# denied-branch-commit-guard.sh — PreToolUse[Bash]: коммит не в ту ветку после отклонённого `git switch -c`.
# en: PreToolUse[Bash] — a commit after a denied branch creation, while HEAD is not that branch, is denied once.
#
# Результат: коммит после отклонённой стражем цепочки с созданием ветки X не уходит молча в другую
#            ветку: первый такой `git commit` отбивается отказом, называющим X и текущую ветку.
# Проверка результата: bash hooks/tests/test_denied_branch_commit_guard.sh
#
# Повод (11 октября 2026, ProjectA, D526). Цепочка `git switch -q -c fix/blind-stretches && …` отклонена
# гейтом разбора ЦЕЛИКОМ — вместе с безвредным созданием ветки. Правка повторена отдельно, ветка —
# нет; два коммита легли в main. Отказ отменяет весь вызов, а намерение «я на ветке X» переживает
# отказ: условие коммита (ветка) в команде не утверждено (`pattern-commit-condition-lives-in-the-command`).
#
# Почему отказ, а не подсказка. Подсказка PreToolUse доставляется вместе с результатом вызова, то
# есть ПОСЛЕ коммита. Последствие одно: коммит в чужую ветку. Отказ — ОДИН на пару «сессия × ветка»:
# повтор той же команды проходит. Раундов противника три (предел скилла); правки третьего раунда
# проверены ногами теста, четвёртого раунда не было.
#
# Молчит, когда условие коммита утверждено или предмета нет: команда коммита сама переключает
# ветку (`git switch X && … git commit`); HEAD каталога коммита — X (отказ отработан, отметка);
# отклонённый вызов и коммит — в разных репозиториях или копиях (или каталог отказа не установлен).
# Отказ — один на каждый отклонённый вызов (ключ — его tool_use_id), а не на имя ветки.
#
# Первая редакция (регулярное выражение по тексту с вырезанными кавычками) сломана противником
# 11 октября 2026: молчала на собственном поводе (`switch -q -c`; узнавала 9 форм создания ветки из
# 85 в корпусе), отбивала повтор отклонённой цепочки и коммиты в чужом репозитории. Здесь факты
# разбирает владелец лексики оболочки `hooks/lib/write_targets.py` (`git_calls`: кавычки, heredoc,
# позиция команды, `cd` и `-C`), отказ узнаёт `hooks/lib/deny_mark.py` (с префиксом харнесса — D527),
# git в папке сессии — `project_git`.
# НАЗВАННЫЕ ПРЕДЕЛЫ. Расшифровка читается с хвоста (`DBC_WINDOW` строк, 3000). `bash -c '…'` и `$(…)`
# не раскрываются. `cherry-pick`/`merge`/`revert`/`am` коммитом не считаются — судится `is_git_commit`.
# Берётся последний отклонённый вызов С созданием ветки, а не последний отклонённый вообще.
# Не разбираются (раунд 2 противника, в корпусе единицы из 3646 коммитов): `pushd`, `cd -`,
# `GIT_DIR=`/`--git-dir=` как каталог коммита; `git branch X && git switch X` как создание; тело
# heredoc, чья оболочка не первое слово строки; `#` внутри имени ветки; `-C` и подкоманда через `\`.
#
# Input  (stdin): {tool_name, tool_input:{command}, session_id, transcript_path, cwd}
# Output (stdout): {hookSpecificOutput:{permissionDecision:"deny", ...}} либо пусто
# Exit:  всегда 0.
set -uo pipefail

command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ "$(jq -r '.tool_name // ""' <<< "$INPUT" 2>/dev/null)" = Bash ] || exit 0
CMD=$(jq -r '.tool_input.command // ""' <<< "$INPUT" 2>/dev/null)
SID=$(jq -r '.session_id // ""' <<< "$INPUT" 2>/dev/null)
TR=$(jq -r '.transcript_path // ""' <<< "$INPUT" 2>/dev/null)
CWD=$(jq -r '.cwd // ""' <<< "$INPUT" 2>/dev/null)
[ -n "$CMD" ] && [ -n "$SID" ] && [ -n "$TR" ] && [ -f "$TR" ] || exit 0

_HD=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
_LIBDIR="$_HD/lib"; [ -f "$_LIBDIR/write_targets.py" ] || _LIBDIR="$HOME/.claude/hooks/lib"
[ -f "$_LIBDIR/write_targets.py" ] && [ -f "$_LIBDIR/deny_mark.py" ] || exit 0
for _lib in command-scope-lib.sh paths-lib.sh; do
    _f="$_HD/$_lib"; [ -f "$_f" ] || _f="$HOME/.claude/hooks/$_lib"
    [ -f "$_f" ] || exit 0
    # shellcheck source=/dev/null
    . "$_f" >/dev/null 2>&1
done
command -v is_git_commit >/dev/null 2>&1 && command -v project_git >/dev/null 2>&1 || exit 0
is_git_commit "$CMD" || exit 0

# Факты: ветка X последнего отклонённого вызова с её созданием, каталог того вызова, каталог
# коммита, переключает ли команда коммита ветку сама. Строки расшифровки читаются по одной:
# битая строка выпадает одна, а не роняет разбор целиком.
FACTS=$(python3 -I - "$TR" "$CMD" "$CWD" "$_LIBDIR" "${DBC_WINDOW:-3000}" <<'PY' 2>/dev/null
import collections, json, os, re, sys
tr, cmd, cwd, libdir, window = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
sys.path.insert(0, libdir)
from write_targets import git_calls
from deny_mark import is_denial, result_text

VALUE_FLAGS = {"switch": "cC", "checkout": "bB", "worktree": "bB"}
LONG = {"switch": ("--create", "--force-create", "--orphan"), "checkout": ("--orphan",), "worktree": ()}

def created(call):
    sub, a = call["sub"], call["args"]
    if sub not in VALUE_FLAGS:
        return None
    if sub == "worktree":
        if not a or a[0] != "add":
            return None
        a = a[1:]
    for k, t in enumerate(a):
        for p in LONG[sub]:
            if t == p and k + 1 < len(a):
                return a[k + 1]
            if t.startswith(p + "="):
                return t[len(p) + 1:]
        if re.match(r"^-[A-Za-z]", t) and not t.startswith("--"):
            for n, ch in enumerate(t[1:], start=1):
                if ch in VALUE_FLAGS[sub]:
                    rest = t[n + 1:]
                    return rest if rest else (a[k + 1] if k + 1 < len(a) else None)
    return None

def literal(x):
    return bool(x) and not x.startswith("-") and not re.search(r"[$\x60\s]", x)   # \x60 — обратная кавычка: bash 3.2 не разбирает её в heredoc внутри $( )

def where(base, call):
    d = base
    for p in call["cd"] + call["C"]:
        d = os.path.normpath(os.path.join(d, os.path.expanduser(p)))
    return d

uses, denied = {}, []
with open(tr, encoding="utf-8", errors="replace") as fh:
    tail = collections.deque(fh, maxlen=window)
for line in tail:
    try:
        o = json.loads(line)
    except Exception:
        continue
    c = (o.get("message") or {}).get("content") if isinstance(o, dict) else None
    if not isinstance(c, list):
        continue
    for b in c:
        if not isinstance(b, dict):
            continue
        if b.get("type") == "tool_use" and b.get("name") == "Bash":
            uses[b.get("id")] = ((b.get("input") or {}).get("command", ""), o.get("cwd") or cwd)
        elif b.get("type") == "tool_result" and b.get("is_error") and b.get("tool_use_id") in uses:
            if is_denial(result_text(b)):
                denied.append(uses[b["tool_use_id"]] + (b["tool_use_id"],))
x = xdir = did = None
for dcmd, dcwd, tid in denied:
    # Создание ветки засчитывается только ДО коммита в отклонённой цепочке: `git commit && git
    # switch -c next` нёс коммит для текущей ветки, а собственный отказ стража на такой команде
    # иначе подменял бы X (раунд 3 противника, Н4).
    for call in git_calls(dcmd):
        if call["sub"] == "commit":
            break
        br = created(call)
        if literal(br):
            x, xdir, did = br, where(dcwd, call), tid
if not x:
    sys.exit(0)
calls = git_calls(cmd)
commit_at = next((k for k, g in enumerate(calls) if g["sub"] == "commit"), None)
if commit_at is None:
    sys.exit(0)
def switches(g):
    if g["sub"] == "switch":
        return True
    if g["sub"] != "checkout":
        return False
    if created(g):
        return True
    free = [t for t in g["args"] if not t.startswith("-")]
    return "--" not in g["args"] and len(free) == 1
self_switch = any(switches(g) for g in calls[:commit_at])
print(json.dumps({"x": x, "xdir": xdir, "did": did or "", "cdir": where(cwd, calls[commit_at]), "self": self_switch}, ensure_ascii=False))
PY
)
_rc=$?
# Прибор сломан (исключение питона: старый write_targets без git_calls, сломанное выражение
# отказа) — сказать, а не промолчать: тишина здесь читалась бы как «чисто» (три состояния прибора).
if [ "$_rc" -ne 0 ]; then
    jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"⚠️ denied-branch-commit-guard: разбор не исполнился (прибор сломан) — коммит после отклонённого создания ветки сейчас не проверяется."}}'
    exit 0
fi
[ -n "$FACTS" ] || exit 0
X=$(jq -r '.x' <<< "$FACTS"); XDIR=$(jq -r '.xdir' <<< "$FACTS"); CDIR=$(jq -r '.cdir' <<< "$FACTS")
DID=$(jq -r '.did' <<< "$FACTS")
[ -n "$X" ] && [ -d "$CDIR" ] || exit 0

# Отметка — на ОТКАЗ (tool_use_id отклонённого вызова), а не на имя ветки: каждый новый отказ
# судится заново. Ставится только на ПРОВЕРЕННОМ исходе — коммит идёт на X либо выдан наш отказ.
# Раунд 3 противника: отметка на молчании и по имени ветки глушила повтор отклонённой цепочки
# (Н1), отказ в другом репозитории (Н3), повтор имени ветки вторым отказом (Н3б).
STATE_DIR="${STATE_DIR:-${HOME:-}/.claude/hooks/state}"
mkdir -p "$STATE_DIR" 2>/dev/null
_mark="$STATE_DIR/denied-branch-commit-${SID//\//_}-$(printf '%s' "$DID" | cksum | cut -d' ' -f1)"
[ -e "$_mark" ] && exit 0
# Отклонённый вызов и коммит — в одном репозитории: это надо УСТАНОВИТЬ, и до любого молчания.
# Каталог отказа не установлен (удалённый worktree, каталог вне git) — молчать: «не знаю» не равно «тот же».
_tc=$(project_git -C "$CDIR" rev-parse --show-toplevel 2>/dev/null)
_tx=$( [ -d "$XDIR" ] && project_git -C "$XDIR" rev-parse --show-toplevel 2>/dev/null)
[ -n "$_tc" ] && [ -n "$_tx" ] && [ "$_tc" = "$_tx" ] || exit 0
# Команда коммита сама переключает ветку — молчать, но НЕ отмечать: переключение может не случиться.
[ "$(jq -r '.self' <<< "$FACTS")" = true ] && exit 0
CUR=$(project_git -C "$CDIR" symbolic-ref --short -q HEAD 2>/dev/null) || CUR=""
if [ "$CUR" = "$X" ]; then ( set -C; : > "$_mark" ) 2>/dev/null; exit 0; fi
# Ветка X может и существовать (создана `git branch X` без переключения) — коммит всё равно не на ней.
( set -C; : > "$_mark" ) 2>/dev/null || exit 0

jq -cn --arg x "$X" --arg cur "${CUR:-отделённый HEAD}" '
  {hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:
   ("⛔ ОТКАЗ (коммит не выполнен): вызов, создававший ветку «" + $x + "», был отклонён стражем целиком, а коммит идёт в «" + $cur + "», не на неё.\n\nСоздай ветку отдельной командой (`git switch -c " + $x + "`) и закоммить на ней — или переключи ветку в той же команде, что и коммит. Если ветку бросил нарочно — повтори коммит: этот отказ выдаётся один раз на ветку за сессию (D526).")}}'
exit 0
