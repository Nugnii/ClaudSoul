#!/usr/bin/env bash
# commit-condition-notice.sh — PreToolUse[Bash]: коммит, ушедший или уходящий без своего условия, называется с адресом.
# en: PreToolUse[Bash] — names a commit that went (or goes) without its condition: a failed edit of its batch, or a `;` step.
#
# Результат: коммит не остаётся без своего условия незамеченным. (1) Коммит прошлого пакета вызовов ушёл, а правка
#            файла того же репозитория в этом пакете не легла — подсказка на ближайшем вызове `Bash` называет коммит,
#            файл и причину, пока коммит не ушёл дальше (push — только по слову владельца). (2) Нынешняя команда
#            коммитит после шага, отделённого `;` или переводом строки, — подсказка называет шаг: коммит исполнится и
#            при упавшем шаге.
# Проверка результата: bash hooks/tests/test_commit_condition_notice.sh
#
# Повод (D1298, 15 ноября 2026; знание `pattern-commit-condition-lives-in-the-command`). Вызовы одного пакета модель
# отправляет разом, до результата первых: если правка не легла (привязка устарела, файл не прочитан, страж отбил),
# коммит того же пакета берёт дерево без неё. Замер по расшифровкам всех проектов: таких коммитов 18 (пересчёт
# скептика предикатом этого хука), из них 13 — после отказа стража на правке, 5 — после «строка не найдена»; среди них
# D1248 (8 ноября: правка CHANGELOG не легла, коммит ушёл). Вторая форма того же знания — «шаг; git commit»
# (2ccd3da, 7f64003, ProjectA 8 и 12 октября): 232 коммита из 5 829 стоят после шага через `;`, из них 93 — после шага,
# чей код и есть условие (`git add`, `cd`, интерпретатор, набор).
#
# ПОЧЕМУ ПОДСКАЗКА, А НЕ ОТКАЗ (замер 15 ноября 2026, D1298). Первая редакция отказывала коммиту своего пакета и в мире
# была слепа: пакет пишется в расшифровку ПОСЛЕ хуков своих вызовов (сессия без пользовательских настроек, зонд на
# PreToolUse[Bash]: своего `tool_use_id` в файле нет, правка пакета и её отказ лежат дальше конца файла), а правка, не
# прошедшая проверку харнесса, не зовёт ни одного хука. До коммита его пакет не виден никому — виден на следующем
# вызове, когда пакет уже на диске. Вторая форма — признак со смешанным исходом: коммит ломается, только если шаг
# упал (из 232 — маркер провала в выводе у 12, почти все — фикстуры), поэтому тоже подсказка.
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ. Знание держалось текстом (уровень 1). Соседи по знанию держат другие условия коммита: ветку —
# `denied-branch-commit-guard.sh`, состав индекса — `git-add-sweep-guard.sh`, набор по изменённым —
# `affected-tests-reminder.sh`. Владельцы фактов: «это коммит» — `command-scope-lib.sh` (`is_git_commit`), разбор
# команды и каталог коммита — `hooks/lib/write_targets.py` (`git_calls`, разделители, heredoc), текст результата —
# `hooks/lib/deny_mark.py` (`result_text`), git — `project_git` (`paths-lib.sh`). Своих копий разбора здесь нет.
#
# Молчит: правка легла; правка вне репозитория коммита (вложенный репозиторий — другой); коммит вернулся ошибкой;
# правка в другом пакете или после коммита; о коммите уже сказано (отметка по его `tool_use_id`); шаг перед коммитом —
# вывод (`echo`, `cat`, `git status` …), стоит под `&&`, `then` или `set -e`.
# НАЗВАННЫЕ ПРЕДЕЛЫ. Вызов субагента о прошлых пакетах молчит: его `transcript_path` — расшифровка родителя (D449), и
# подсказка ушла бы не тому. Ход, кончившийся пакетом коммита, услышит подсказку на первом `Bash` следующего хода.
# Расшифровка читается с хвоста (`CCN_TAIL_BYTES`, 4 МБ). Запись оболочкой в пакете (heredoc, `sed`) не судится — у её
# провала нет признака «правка». «No changes to make» считается непрошедшей правкой (частота 0 в корпусе).
#
# Input  (stdin): {tool_name, tool_input:{command}, session_id, transcript_path, cwd, agent_id?}
# Output (stdout): {hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext}} либо пусто
# Exit:  всегда 0.
set -uo pipefail

command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ "$(jq -r '.tool_name // ""' <<< "$INPUT" 2>/dev/null)" = Bash ] || exit 0
CMD=$(jq -r '.tool_input.command // ""' <<< "$INPUT" 2>/dev/null)
SID=$(jq -r '.session_id // ""' <<< "$INPUT" 2>/dev/null)
TR=$(jq -r '.transcript_path // ""' <<< "$INPUT" 2>/dev/null)
CWD=$(jq -r '.cwd // ""' <<< "$INPUT" 2>/dev/null)
AGENT=$(jq -r '.agent_id // ""' <<< "$INPUT" 2>/dev/null)
[ -n "$CMD" ] || exit 0
[ -n "$CWD" ] || CWD="$PWD"

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
STEP=0; is_git_commit "$CMD" && STEP=1
# Прошлые пакеты судятся у родителя и только по живой расшифровке.
PAST=0; [ -z "$AGENT" ] && [ -n "$SID" ] && [ -n "$TR" ] && [ -f "$TR" ] && PAST=1
[ "$STEP" = 1 ] || [ "$PAST" = 1 ] || exit 0

FACTS=$(python3 -I - "$CMD" "$STEP" "$PAST" "$TR" "$_LIBDIR" "${CCN_TAIL_BYTES:-4194304}" <<'PY' 2>/dev/null
import json, os, shlex, sys
cmd, step, past, tr, libdir, tail = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1", sys.argv[4], sys.argv[5], int(sys.argv[6])
sys.path.insert(0, libdir)
import write_targets as W
from deny_mark import result_text

# --- (2) нынешняя команда: шаг, чей код — условие коммита, отделён `;` / переводом строки -----------------------------
COND_GIT = {"add", "rm", "mv", "checkout", "switch", "reset", "restore", "apply", "am", "cherry-pick", "merge",
            "rebase", "revert", "stash", "pull", "fetch", "init", "update-index"}
COND_RUN = {"cd", "pushd", "python3", "python", "bash", "sh", "zsh", "node", "npx", "npm", "pnpm", "yarn", "pytest",
            "make", "vitest", "jest", "sed", "perl", "awk", "tsc", "eslint", "ruby", "cp", "mv", "patch"}
if step:
    try:
        lex = shlex.shlex(W._shell_words_text(W.shell_text(cmd)), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        toks = list(lex)
    except ValueError:
        toks = []
    segs, seps, seg = [], [], []
    for t in toks + [";"]:
        if W._is_sep(t):
            segs.append(W._strip_redirs(seg)); seps.append(t); seg = []
        else:
            seg.append(t)
    def head(s):
        i = W._cmd_pos(s)
        return (s[i].split("/")[-1], i) if i < len(s) else ("", i)
    errexit = False
    for k, s in enumerate(segs):
        w, i = head(s)
        if w == "set" and any(a.startswith("-") and "e" in a[1:] for a in s[i + 1:]):
            errexit = True
        g = W.git_calls(" ".join(shlex.quote(x) for x in s)) if w == "git" else []
        if not (g and g[0]["sub"] == "commit") or errexit or (i > 0 and s[i - 1] in ("then", "do")):
            continue
        j = k - 1
        while j >= 0 and not segs[j]:
            j -= 1
        if j < 0 or seps[j] != ";":
            continue
        pw, pi = head(segs[j])
        pg = W.git_calls(" ".join(shlex.quote(x) for x in segs[j])) if pw == "git" else []
        if (pg and pg[0]["sub"] in COND_GIT) or pw in COND_RUN:
            print(json.dumps({"kind": "step", "step": " ".join(segs[j][pi:pi + 6])[:120]}, ensure_ascii=False))
            break

# --- (1) прошлые пакеты: коммит ушёл, правка того же пакета не легла ------------------------------------------------
EDIT = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
if past:
    with open(tr, "rb") as fh:
        fh.seek(0, 2)
        size = fh.tell()
        fh.seek(max(0, size - tail))
        data = fh.read()
    if size > tail:
        data = data[data.find(b"\n") + 1:]
    if b'"is_error":true' in data and b"commit" in data:
        uses, order, res = {}, [], {}
        for line in data.split(b"\n"):
            if b'"tool_use"' not in line and b'"tool_result"' not in line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if not isinstance(o, dict):
                continue
            m = o.get("message") or {}
            c = m.get("content")
            if not isinstance(c, list):
                continue
            for b in c:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use" and b.get("id") not in uses:
                    uses[b.get("id")] = (m.get("id"), len(order), b.get("name"), b.get("input") or {}, o.get("cwd") or "")
                    order.append(b.get("id"))
                elif b.get("type") == "tool_result":
                    res[b.get("tool_use_id")] = (bool(b.get("is_error")), result_text(b))
        for u in order:
            mid, idx, name, inp, lcwd = uses[u]
            if name != "Bash" or not mid or u not in res or res[u][0]:
                continue
            ci = next((g for g in W.git_calls(inp.get("command") or "") if g["sub"] == "commit"), None)
            if ci is None:
                continue
            cdir = lcwd
            for p in ci["cd"] + ci["C"]:
                cdir = os.path.normpath(os.path.join(cdir, os.path.expanduser(p)))
            failed = []
            for e in order[:idx]:
                m2, _, n2, i2, l2 = uses[e]
                if m2 != mid or n2 not in EDIT or not res.get(e, (False, ""))[0]:
                    continue
                p = str(i2.get("file_path") or i2.get("notebook_path") or "")
                p = os.path.normpath(os.path.join(l2 or lcwd, p))
                d = os.path.dirname(p)
                while d and d != "/" and not os.path.isdir(d):      # каталог правки мог не родиться — ближайший живой
                    d = os.path.dirname(d)
                why = next((ln.strip() for ln in res[e][1].splitlines() if ln.strip()), "")
                failed.append([p, d, why[:160]])
            if failed:
                print(json.dumps({"kind": "batch", "use": u, "cdir": cdir, "failed": failed}, ensure_ascii=False))
PY
)
_rc=$?
# Прибор сломан (исключение питона, старый write_targets) — сказать: тишина здесь читалась бы «условия коммитов целы».
if [ "$_rc" -ne 0 ]; then
    jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"⚠️ commit-condition-notice: разбор не исполнился (прибор сломан) — коммит без своего условия сейчас не называется."}}'
    exit 0
fi
[ -n "$FACTS" ] || exit 0

MSG=""
_step=$(jq -r 'select(.kind == "step") | .step' <<< "$FACTS" 2>/dev/null | head -1)
[ -n "$_step" ] && MSG="⚠️ Коммит этой команды стоит после шага через \`;\` или перевод строки: \`$_step\` — коммит исполнится и при упавшем шаге. Проверь в выводе, что шаг прошёл; условие пиши в команде (\`&&\`, \`if\`)."$'\n'

STATE_DIR="${STATE_DIR:-${HOME:-}/.claude/hooks/state}"
mkdir -p "$STATE_DIR" 2>/dev/null
while IFS= read -r _b; do
    [ -n "$_b" ] || continue
    _use=$(jq -r '.use' <<< "$_b"); _cdir=$(jq -r '.cdir' <<< "$_b")
    _mark="$STATE_DIR/commit-condition-notice-${SID//\//_}-$(printf '%s' "$_use" | cksum | cut -d' ' -f1)"
    _tc=$(project_git -C "$_cdir" rev-parse --show-toplevel 2>/dev/null) || continue
    _list=""
    while IFS=$'\t' read -r _p _d _why; do
        [ -n "$_d" ] || continue
        _te=$(project_git -C "$_d" rev-parse --show-toplevel 2>/dev/null) || continue
        [ "$_te" = "$_tc" ] && _list="${_list}  · ${_p#"$_tc"/} — ${_why}"$'\n'
    done < <(jq -r '.failed[] | @tsv' <<< "$_b" 2>/dev/null)
    [ -n "$_list" ] || continue
    ( set -C; : > "$_mark" ) 2>/dev/null || continue
    MSG="${MSG}⚠️ Коммит прошлого пакета вызовов (\`${_use}\`, $(basename "$_tc")) ушёл, а правка этого репозитория в том же пакете не легла — коммит взял дерево без неё:"$'\n'"${_list}Почини правку и дополни коммит (\`git commit --amend\` до push либо следующим коммитом). Пакет пишется на диск после своих хуков, поэтому сказано сейчас, а не до коммита (D1298)."$'\n'
done < <(jq -c 'select(.kind == "batch")' <<< "$FACTS" 2>/dev/null)
[ -n "$MSG" ] || exit 0
jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
